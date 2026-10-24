/* pmp-cycle: try to restart the PMP's ASC CPU after a failed wake, the way macOS's
 * AppleA7IOP::stopCPU / startCPUWithOptions power-cycle it (worklog 2026-10-23).
 * Touches only these registers (anything else is refused at compile time):
 *   PMGR 0x28e0802c8 ps_pmp, 0x28e0802d0 ps_pms_sram    (power state)
 *   ASC  0x28ec00044 CPU_CONTROL (RUN bit 4), 0x28ec00048 CPU_STATUS (read)
 *   MBOX 0x28ec08110 A2I_CONTROL (read), 0x28ec08114 I2A_CONTROL (bit 0 outbox enable)
 *   DART 0x28e300000 (pmp_dart, t8110): PROTECT 0x200 (read), ENABLE_STREAMS 0xc00..0xc1c,
 *        TCR(sid) 0x1000 + 4 sid, TTBR(sid) 0x1400 + 4 sid, sids 0-15: written back only if a
 *        reset lost them (the values Linux's apple-dart programmed, apple_dart_resume order)
 * PMGR writes follow Linux pmgr-pwrstate.c: the W1C flags, BUSY, RESET, DEV_DISABLE and
 * AUTO_ENABLE are written as 0, then AUTO_ENABLE is set again once the domain is on.
 * usage: pmp-cycle read | sram-cycle | reset-cycle
 *   sram-cycle: clear RUN, gate ps_pms_sram (target 0), ungate, outbox on, RUN; then sample
 *   CPU_STATUS and both mailbox counts for 2 s. ps_pmp is only read (its PS_MIN is 0xf).
 *   reset-cycle: clear RUN, save the DART, reset ps_pmp the way Linux's PMGR reset does
 *   (DEV_DISABLE, RESET, 1 ms, release both), restore the DART if the reset cleared it,
 *   outbox on, RUN, sample as above. This is how apple-nvme cold-starts its ASC.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define PMGR_BASE 0x28e080000ULL
#define ASC_BASE  0x28ec00000ULL
#define MBOX_BASE 0x28ec08000ULL
#define DART_BASE 0x28e300000ULL

#define PS_PMP      0x2c8
#define PS_PMS_SRAM 0x2d0
#define CPU_CONTROL 0x44
#define CPU_STATUS  0x48
#define A2I_CONTROL 0x110
#define I2A_CONTROL 0x114

#define CPU_RUN (1u << 4)
#define PS_KEEP_MASK ~((1u << 31) | (1u << 28) | (1u << 12) | (1u << 11) | (1u << 10) | \
		       (1u << 9) | (1u << 8) | 0xfu)
#define PS_AUTO_ENABLE (1u << 28)
#define PS_RESET (1u << 31)
#define PS_DEV_DISABLE (1u << 10)
#define PS_FLAGS ((1u << 9) | (1u << 8))

#define DART_PROTECT 0x200
#define DART_ENABLE_STREAMS 0xc00
#define DART_TCR(s) (0x1000 + 4 * (s))
#define DART_TTBR(s) (0x1400 + 4 * (s))
#define NSID 16

static volatile uint32_t *pmgr, *asc, *mbox, *dart;

static double now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static volatile uint32_t *map(int fd, uint64_t base)
{
	void *p = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
	if (p == MAP_FAILED) { perror("mmap"); return NULL; }
	return p;
}

static uint32_t rd(volatile uint32_t *b, unsigned off) { return b[off / 4]; }
static void wr(volatile uint32_t *b, unsigned off, uint32_t v) { b[off / 4] = v; }

static void show(const char *tag)
{
	uint32_t p = rd(pmgr, PS_PMP), s = rd(pmgr, PS_PMS_SRAM);
	uint32_t c = rd(asc, CPU_CONTROL), st = rd(asc, CPU_STATUS);
	uint32_t a = rd(mbox, A2I_CONTROL), i = rd(mbox, I2A_CONTROL);
	printf("%-14s ps_pmp 0x%08x (t%x a%x) pms_sram 0x%08x (t%x a%x) RUN %u STATUS 0x%x "
	       "A2I 0x%08x (n %u) I2A 0x%08x (n %u)\n", tag,
	       p, p & 0xf, (p >> 4) & 0xf, s, s & 0xf, (s >> 4) & 0xf, (c >> 4) & 1, st,
	       a, (a >> 20) & 0xff, i, (i >> 20) & 0xff);
	printf("%-14s dart PROTECT 0x%x STREAMS 0x%08x TCR0 0x%08x TTBR0 0x%08x\n", "",
	       rd(dart, DART_PROTECT), rd(dart, DART_ENABLE_STREAMS), rd(dart, DART_TCR(0)),
	       rd(dart, DART_TTBR(0)));
}

static uint32_t sv_streams[8], sv_tcr[NSID], sv_ttbr[NSID];

static void dart_save(void)
{
	for (int k = 0; k < 8; k++)
		sv_streams[k] = rd(dart, DART_ENABLE_STREAMS + 4 * k);
	for (int k = 0; k < NSID; k++) {
		sv_tcr[k] = rd(dart, DART_TCR(k));
		sv_ttbr[k] = rd(dart, DART_TTBR(k));
	}
}

/* Write back what the reset changed: streams first, then TTBR before TCR. */
static void dart_restore(void)
{
	int n = 0;
	for (int k = 0; k < 8; k++)
		if (rd(dart, DART_ENABLE_STREAMS + 4 * k) != sv_streams[k]) {
			wr(dart, DART_ENABLE_STREAMS + 4 * k, sv_streams[k]);
			n++;
		}
	for (int k = 0; k < NSID; k++) {
		if (rd(dart, DART_TTBR(k)) != sv_ttbr[k]) {
			wr(dart, DART_TTBR(k), sv_ttbr[k]);
			n++;
		}
		if (rd(dart, DART_TCR(k)) != sv_tcr[k]) {
			wr(dart, DART_TCR(k), sv_tcr[k]);
			n++;
		}
	}
	printf("dart: %d registers restored\n", n);
}

static void run_and_sample(void)
{
	wr(mbox, I2A_CONTROL, rd(mbox, I2A_CONTROL) | 1);
	wr(asc, CPU_CONTROL, rd(asc, CPU_CONTROL) | CPU_RUN);
	double t0 = now_ms();
	const int at[] = { 1, 10, 100, 500, 2000 };
	for (unsigned k = 0; k < sizeof(at) / sizeof(at[0]); k++) {
		while (now_ms() - t0 < at[k])
			usleep(200);
		char tag[16];
		snprintf(tag, sizeof(tag), "RUN +%d ms", at[k]);
		show(tag);
	}
}

/* Set a domain's target and wait up to 100 ms for ACTUAL to follow. */
static int ps_set(unsigned off, unsigned target, int auto_enable)
{
	uint32_t v = (rd(pmgr, off) & PS_KEEP_MASK) | target;
	wr(pmgr, off, v);
	double t0 = now_ms();
	while (((rd(pmgr, off) >> 4) & 0xf) != target) {
		if (now_ms() - t0 > 100) {
			printf("ps 0x%x: target %x not reached (0x%08x)\n", off, target, rd(pmgr, off));
			return -1;
		}
	}
	printf("ps 0x%x: actual %x after %.3f ms\n", off, target, now_ms() - t0);
	if (auto_enable)
		wr(pmgr, off, v | PS_AUTO_ENABLE);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc != 2 || (strcmp(argv[1], "read") && strcmp(argv[1], "sram-cycle") &&
			  strcmp(argv[1], "reset-cycle"))) {
		fprintf(stderr, "usage: %s read | sram-cycle | reset-cycle\n", argv[0]);
		return 2;
	}
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	if (!(pmgr = map(fd, PMGR_BASE)) || !(asc = map(fd, ASC_BASE)) || !(mbox = map(fd, MBOX_BASE)) ||
	    !(dart = map(fd, DART_BASE)))
		return 1;
	show("now");
	if (!strcmp(argv[1], "read"))
		return 0;

	wr(asc, CPU_CONTROL, rd(asc, CPU_CONTROL) & ~CPU_RUN);
	usleep(1000);
	show("RUN cleared");
	if (!strcmp(argv[1], "reset-cycle")) {
		dart_save();
		uint32_t v = rd(pmgr, PS_PMP) & ~PS_FLAGS;
		wr(pmgr, PS_PMP, v | PS_DEV_DISABLE);
		wr(pmgr, PS_PMP, v | PS_DEV_DISABLE | PS_RESET);
		usleep(1000);
		show("reset held");
		wr(pmgr, PS_PMP, v | PS_DEV_DISABLE);
		wr(pmgr, PS_PMP, v);
		usleep(1000);
		show("reset released");
		dart_restore();
		show("dart checked");
		run_and_sample();
		return 0;
	}
	if (ps_set(PS_PMS_SRAM, 0x0, 0) == 0)
		show("sram gated");
	usleep(1000);
	if (ps_set(PS_PMS_SRAM, 0xf, 1)) {
		show("sram stuck");
		return 1;
	}
	show("sram on");
	run_and_sample();
	return 0;
}
