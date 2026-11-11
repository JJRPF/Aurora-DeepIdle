/* aura-ctl: show or set Aura's S2R control word (image 52, psci.c psci_ctl). It finds the block by its magic in the
 * "reserved" DRAM ranges of /proc/iomem (as scan-magic does), refuses unless there is exactly one, and writes only the
 * word after the magic. Bits: 1 PMGR S2R timer, 2 every core into macOS's deep sleep, 4 quiesceHW's power domains
 * (AFR off, SIO auto-enable off), 8 quiesceHW's ClkGen and PLL-off writes (image 53), 16 to 64 images 54 to 56, image 58:
 * 0x100 records (psci_dbg2), 0x200 AMCC error enables off, 0x400 stop WD2 after the timer, 0x800 AIC mask-all; image 59: 0x1000 WD1 off before the timer, 0x2000 resume right after it. 0 = image 51's suspend.
 * usage: aura-ctl            print the address and the word
 *        aura-ctl <value>    write it, read it back
 *        aura-ctl <value> <mask>  also write the next word, psci_ctl[2]: image 57's held-domain mask (bits 0-11, 0 = all)
 *        aura-ctl <value> <mask> <cap>  also psci_ctl[3]: heartbeats (60 s each) after which a suspend with no wake line
 *                                       resumes by itself (0 = Aura's default 5, 0xffff = never; Aura 876622bf on) */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define MAGIC 0x5332524354524c21ULL /* "S2RCTRL!" */

int main(int argc, char **argv)
{
	int fd = open("/dev/mem", argc > 1 ? O_RDWR | O_SYNC : O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	FILE *f = fopen("/proc/iomem", "r");
	char line[256];
	uint64_t hit = 0;
	int hits = 0;
	while (fgets(line, sizeof line, f)) {
		unsigned long long a, b;
		if (!strstr(line, "reserved")) continue;
		if (sscanf(line + strspn(line, " "), "%llx-%llx", &a, &b) != 2) continue;
		if (a < 0x10000000000ULL || a >= 0x20000000000ULL) continue;
		uint64_t len = b - a + 1;
		if (len > (64ULL << 20)) continue;
		volatile uint64_t *p = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, a);
		if (p == MAP_FAILED) continue;
		for (uint64_t i = 0; i < len / 8; i++)
			if (p[i] == MAGIC) { hit = a + i * 8; hits++; }
		munmap((void *)p, len);
	}
	if (hits != 1) { fprintf(stderr, "aura-ctl: %d control blocks found, need exactly 1\n", hits); return 1; }
	uint64_t page = hit & ~0x3fffULL;
	volatile uint64_t *p = mmap(NULL, 0x4000, argc > 1 ? PROT_READ | PROT_WRITE : PROT_READ, MAP_SHARED, fd, page);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint64_t *w = p + (hit - page) / 8 + 1;
	if (argc > 1) {
		uint64_t v = strtoull(argv[1], NULL, 0);
		if (v & ~0x1fffffffULL) { fprintf(stderr, "aura-ctl: only bits 0 to 28 are defined: 1 timer, 2 cores off, 4 domains, 8 clocks, 16 clusters (54), 32 stop requests (55), 64 held domains (56), 0x80 test marker, 0x100 records, 0x200 AMCC errors off, 0x400 stop WD2, 0x800 AIC mask-all (58), 0x1000 WD1 off before the timer, 0x2000 resume right after it (59), 0x4000 PMU breadcrumbs in scratch 0x6004 (60), 0x8000 quiet commit: release before the timer, nothing after it (60g), 0x10000 EACC (the boot cluster) target 0 too (60h), 0x20000 cluster APSC off before the timer (61), 0x40000 fabric auto-PM floor 0 (62), 0x80000 atcN_pcie and atcN_common off (63), 0x100000 apcie_gp_sys, apcie_gpshr_sys, apcie_gp off, 0x200000 atc1-3_usb_aon and msg off (64; commit runs only), 0x400000 pmp and pms_sram off (65; commit runs only), 0x800000 SPMI notify enable before the commit (66), 0x1000000 SEP outbox off and ps_sep 0x1000030f in the commit (67; needs the SLEEP sent from Linux), 0x2000000 cluster APSC off after the secondaries have slept (70), 0x4000000 each core clears its EDPRCR before its deep WFI (72), 0x8000000 one P core observes the boot complex after the commit (73), 0x10000000 the observer is a core of the first P complex (74)\n"); return 2; }
		*w = v;
		w[1] = argc > 2 ? strtoull(argv[2], NULL, 0) & 0xfff : 0;
		w[2] = argc > 3 ? strtoull(argv[3], NULL, 0) & 0xffff : 0;
	}
	printf("aura ctl at 0x%llx: 0x%llx mask 0x%llx cap %llu\n", (unsigned long long)hit, (unsigned long long)*w, (unsigned long long)w[1], (unsigned long long)w[2]);
	return 0;
}
