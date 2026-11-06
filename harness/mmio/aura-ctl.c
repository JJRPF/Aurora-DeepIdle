/* aura-ctl: show or set Aura's S2R control word (image 52, psci.c psci_ctl). It finds the block by its magic in the
 * "reserved" DRAM ranges of /proc/iomem (as scan-magic does), refuses unless there is exactly one, and writes only the
 * word after the magic. Bits: 1 PMGR S2R timer, 2 every core into macOS's deep sleep, 4 quiesceHW's power domains
 * (AFR off, SIO auto-enable off), 8 quiesceHW's ClkGen and PLL-off writes (image 53). 0 = image 51's suspend.
 * usage: aura-ctl            print the address and the word
 *        aura-ctl <value>    write it, read it back
 *        aura-ctl <value> <mask>  also write the next word, psci_ctl[2]: image 57's held-domain mask (bits 0-11, 0 = all) */
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
		if (v > 0x7f && v != 0x80) { fprintf(stderr, "aura-ctl: only bits 0 to 6 (and the test marker 0x80) are defined; bit 4 (16) is image 54\x27s soc-cluster power-off, bit 5 (32) image 55\x27s CPU stop requests, bit 6 (64) image 56\x27s held domains off\n"); return 2; }
		*w = v;
		w[1] = argc > 2 ? strtoull(argv[2], NULL, 0) & 0xfff : 0;
	}
	printf("aura ctl at 0x%llx: 0x%llx mask 0x%llx\n", (unsigned long long)hit, (unsigned long long)*w, (unsigned long long)w[1]);
	return 0;
}
