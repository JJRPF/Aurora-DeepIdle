/*
 * RAM-only test init for the PSCI-via-EFI hotplug test: PID 1 of an initramfs boot that never opens
 * the LUKS root or mounts btrfs, so a hang or hard reset cannot damage the owner's filesystem. Only the
 * ESP (vfat, small) is mounted: first to put the stock boot.bin back, then for a breadcrumb file.
 * Static, no libc beyond the syscalls.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <linux/fiemap.h>
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <time.h>
#include <stdarg.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <unistd.h>

static int kmsg = -1, crumb = -1, rawfd = -1;
static off_t rawoff;

#define LOGSZ (256 * 1024)
static char logbuf[LOGSZ], kbuf[96 * 1024];
static int loglen;

/* Rewrite the preallocated log file from offset 0: our lines, then the kernel log tail. Data-only synchronous
 * writes into already-allocated clusters, so a hang right after loses nothing that was said before it. */
static void flush_log(void)
{
    if (crumb < 0 && rawfd < 0)
        return;
    int n = loglen, kl = 0;
    int k = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
    if (k >= 0) {
        char rec[2048];
        ssize_t r;
        kl = snprintf(kbuf, sizeof kbuf, "\n== kmsg ==\n");
        while ((r = read(k, rec, sizeof rec - 1)) > 0 || (r < 0 && errno == EPIPE)) {
            if (r < 0)
                continue;
            rec[r] = 0;
            char *m = strchr(rec, ';');
            if (m && kl < (int)sizeof kbuf - 2048)
                kl += snprintf(kbuf + kl, sizeof kbuf - kl, "%s", m + 1);
        }
        close(k);
        /* keep only the newest part that fits */
        if (kl > (int)(LOGSZ - n - 1))
            memmove(kbuf, kbuf + kl - (LOGSZ - n - 1), LOGSZ - n - 1), kl = LOGSZ - n - 1;
    }
    memcpy(logbuf + n, kbuf, kl);
    if (rawfd >= 0) {
        memset(logbuf + n + kl, '\n', LOGSZ - n - kl);
        pwrite(rawfd, logbuf, LOGSZ, rawoff);
    } else {
        pwrite(crumb, logbuf, n + kl, 0);
    }
    logbuf[n] = 0;
}

static void say(const char *fmt, ...)
{
    char b[256], c[300];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int n = snprintf(c, sizeof c, "psci-ram: [%4ld.%02ld] %s\n", (long)ts.tv_sec, ts.tv_nsec / 10000000, b);
    if (kmsg >= 0)
        write(kmsg, c, n);
    if (loglen + n < LOGSZ / 2) {
        memcpy(logbuf + loglen, c + 10, n - 10);
        loglen += n - 10;
    }
    flush_log();
}

static int rd(const char *p, char *buf, int n)
{
    int f = open(p, O_RDONLY), r = -1;
    if (f >= 0) {
        r = read(f, buf, n - 1);
        close(f);
    }
    if (r < 0)
        r = 0;
    buf[r] = 0;
    while (r > 0 && (buf[r - 1] == '\n'))
        buf[--r] = 0;
    return r;
}

static int wr(const char *p, const char *s)
{
    int f = open(p, O_WRONLY);
    if (f < 0)
        return -1;
    int r = write(f, s, strlen(s));
    close(f);
    return r < 0 ? -1 : 0;
}

static int copy(const char *from, const char *to)
{
    char buf[65536];
    int a = open(from, O_RDONLY), b = open(to, O_WRONLY | O_CREAT | O_TRUNC, 0755);
    if (a < 0 || b < 0)
        return -1;
    ssize_t n;
    while ((n = read(a, buf, sizeof buf)) > 0)
        if (write(b, buf, n) != n)
            return -1;
    fsync(b);
    close(a);
    close(b);
    return 0;
}

int main(void)
{
    char v[128], p[96];
    mkdir("/proc", 0755);
    mkdir("/sys", 0755);
    mkdir("/dev", 0755);
    mount("proc", "/proc", "proc", 0, 0);
    mount("sysfs", "/sys", "sysfs", 0, 0);
    mount("devtmpfs", "/dev", "devtmpfs", 0, 0);
    kmsg = open("/dev/kmsg", O_WRONLY);
    say("init up; online %s", (rd("/sys/devices/system/cpu/online", v, sizeof v), v));

    for (int i = 0; i < 100 && access("/dev/nvme0n1p4", F_OK); i++)
        usleep(200000);
    {
        /* Durable log: raw synchronous writes into a free run of ESP clusters picked by install.sh (vfat
         * keeps files and their size in cache, so a hard reset loses them). Read back with dd next boot. */
        char c0[1024];
        rd("/proc/cmdline", c0, sizeof c0);
        char *r = strstr(c0, "psci_ram_raw=");
        if (r) {
            rawoff = atoll(r + 13);
            rawfd = open("/dev/nvme0n1p4", O_WRONLY | O_SYNC);
            say("raw log at partition offset %lld (fd %d)", (long long)rawoff, rawfd);
        }
    }
    /* No ESP mount at all: the stock boot.bin is put back by psci-efi-early.service of the next boot, and
     * everything we have to say goes to the raw log region. */
    say("psci: %s", (rd("/sys/devices/system/cpu/online", v, sizeof v), v));
    int cycles = 3;
    rd("/proc/cmdline", v, sizeof v); /* only the head; cycles via psci_ram_cycles=N is read below */
    char cl[1024];
    rd("/proc/cmdline", cl, sizeof cl);
    char *q = strstr(cl, "psci_ram_cycles=");
    if (q)
        cycles = atoi(q + 16);
    int fail = 0;
    if (cycles < 0) {
        say("cycles=%d: no CPU work, boot check only", cycles);
        char *w = strstr(cl, "psci_ram_wait=");
        for (int i = 0, n = w ? atoi(w + 14) : 0; i < n; i++) {
            sleep(1);
            say("idle %d/%d", i + 1, n);
        }
    }
    for (int c = 1; cycles >= 0 && c <= 9 && !fail; c++) {
        snprintf(p, sizeof p, "/sys/devices/system/cpu/cpu%d/online", c);
        if (access(p, F_OK)) {
            say("cpu%d: no online file", c);
            continue;
        }
        say("cpu%d: onlining (CPU_ON)", c);
        if (wr(p, "1")) { say("cpu%d: online write failed", c); fail = 1; break; }
        rd(p, v, sizeof v);
        say("cpu%d: online=%s", c, v);
        for (int i = 1; i <= cycles; i++) {
            say("cpu%d cycle %d: offline (CPU_OFF)", c, i);
            if (wr(p, "0")) { say("cpu%d cycle %d: offline write failed", c, i); fail = 1; break; }
            rd(p, v, sizeof v);
            say("cpu%d cycle %d: offline -> %s; online now %s", c, i, v, (rd("/sys/devices/system/cpu/online", cl, sizeof cl), cl));
            if (v[0] != '0') { fail = 1; break; }
            usleep(200000);
            say("cpu%d cycle %d: online (CPU_ON)", c, i);
            if (wr(p, "1")) { say("cpu%d cycle %d: online write failed", c, i); fail = 1; break; }
            rd(p, v, sizeof v);
            say("cpu%d cycle %d: online -> %s", c, i, v);
            if (v[0] != '1') { fail = 1; break; }
        }
        say("cpu%d: %s", c, fail ? "FAILED" : "all cycles ok");
    }
    say("done fail=%d; online %s", fail, (rd("/sys/devices/system/cpu/online", v, sizeof v), v));
    /* the kernel's own view of the last lines */
    flush_log();
    sleep(2);
    reboot(RB_AUTOBOOT);
    return 0;
}
