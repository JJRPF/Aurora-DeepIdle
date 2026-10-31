/*
 * RAM-only test init for the PSCI-via-EFI hotplug test: PID 1 of an initramfs boot that never opens
 * the LUKS root or mounts btrfs, so a hang or hard reset cannot damage the owner's filesystem. Only the
 * ESP (vfat, small) is mounted: first to put the stock boot.bin back, then for a breadcrumb file.
 * Static, no libc beyond the syscalls.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <unistd.h>

static int kmsg = -1, crumb = -1;

static void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
#include <stdarg.h>
static void say(const char *fmt, ...)
{
    char b[256], c[300];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    int n = snprintf(c, sizeof c, "psci-ram: %s\n", b);
    if (kmsg >= 0)
        write(kmsg, c, n);
    if (crumb >= 0) {
        write(crumb, c + 10, n - 10);
        fsync(crumb);
    }
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
    mount("proc", "/proc", "proc", 0, 0);
    mount("sysfs", "/sys", "sysfs", 0, 0);
    mount("devtmpfs", "/dev", "devtmpfs", 0, 0);
    kmsg = open("/dev/kmsg", O_WRONLY);
    say("init up; online %s", (rd("/sys/devices/system/cpu/online", v, sizeof v), v));

    for (int i = 0; i < 100 && access("/dev/nvme0n1p4", F_OK); i++)
        usleep(200000);
    mkdir("/esp", 0755);
    if (mount("/dev/nvme0n1p4", "/esp", "vfat", MS_SYNCHRONOUS | MS_NOATIME, 0)) {
        say("cannot mount ESP: stopping");
        sleep(5);
        reboot(RB_AUTOBOOT);
    }
    /* Stock Aura back at once, as psci-efi-early.service does: any later reset boots the normal image. */
    if (copy("/boot.bin.stock", "/esp/m1n1/boot.bin.tmp") == 0 && rename("/esp/m1n1/boot.bin.tmp", "/esp/m1n1/boot.bin") == 0)
        say("stock boot.bin restored");
    else
        say("stock boot.bin restore FAILED");
    sync();
    crumb = open("/esp/psci-ram.log", O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
    say("psci: %s", (rd("/sys/devices/system/cpu/online", v, sizeof v), v));

    int cycles = 3;
    rd("/proc/cmdline", v, sizeof v); /* only the head; cycles via psci_ram_cycles=N is read below */
    char cl[1024];
    rd("/proc/cmdline", cl, sizeof cl);
    char *q = strstr(cl, "psci_ram_cycles=");
    if (q)
        cycles = atoi(q + 16);
    int fail = 0;
    for (int c = 1; c <= 9 && !fail; c++) {
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
    close(crumb);
    sync();
    umount("/esp");
    sleep(2);
    reboot(RB_AUTOBOOT);
    return 0;
}
