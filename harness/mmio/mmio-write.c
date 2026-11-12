/* mmio-write: one 32-bit write through /dev/mem, then read back.
 * Limited to the nub-spmi0 and nub-spmi1 controller pages (0x29e114000-0x29e1140ff, 0x29e154000-0x29e1540ff) and, since
 * R41 (2026-11-12), the three display controllers' register blocks macOS programs at suspend (0x38a000000, 0x28a000000,
 * 0x316000000, offsets below 0xc00)
 * so a typo cannot reach anything else.
 * usage: mmio-write <phys-addr> <value> */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#define LO0 0x29e114000ULL
#define LO1 0x29e154000ULL

int main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: %s <phys> <value>\n", argv[0]);
		return 2;
	}
	uint64_t phys = strtoull(argv[1], NULL, 0);
	uint32_t val = strtoul(argv[2], NULL, 0);
	static const struct { uint64_t base, len; } win[] = {
		{0x29e114000ULL, 0x100}, {0x29e154000ULL, 0x100},
		{0x38a000000ULL, 0xc00}, {0x28a000000ULL, 0xc00}, {0x316000000ULL, 0xc00},
	};
	uint64_t LO = 0;
	for (unsigned i = 0; i < sizeof(win) / sizeof(win[0]); i++)
		if (phys >= win[i].base && phys < win[i].base + win[i].len) LO = win[i].base;
	if (!LO || (phys & 3)) {
		fprintf(stderr, "0x%llx outside the allowed window\n",
			(unsigned long long)phys);
		return 2;
	}
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE,
				    MAP_SHARED, fd, LO);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *w = p + (phys - LO) / 4;
	uint32_t old = *w;
	*w = val;
	printf("0x%09llx 0x%08x -> wrote 0x%08x -> 0x%08x\n",
	       (unsigned long long)phys, old, val, *w);
	return 0;
}
