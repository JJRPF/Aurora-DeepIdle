/* pmgr-cpu-write: one 32-bit write through /dev/mem to the PMGR CPU start/stop block of die 0
 * (T6020: 0x28e0a8000 .. 0x28e0a801f, the registers Aura's smp_start_cpu/smp_stop_cpu write),
 * then read back. Limited to that window at compile time.
 *   +0x0 stop request (bit = 4*cluster + core), +0x4 "system level start" bit,
 *   +0x8 + 4*cluster: start (bit = core)
 * usage: pmgr-cpu-write <phys-addr> <value> */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#define LO 0x28e0a8000ULL
#define HI 0x28e0a8020ULL

int main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: %s <phys> <value>\n", argv[0]);
		return 2;
	}
	uint64_t phys = strtoull(argv[1], NULL, 0);
	uint32_t val = strtoul(argv[2], NULL, 0);
	if (phys < LO || phys >= HI || (phys & 3)) {
		fprintf(stderr, "0x%llx outside the allowed window\n", (unsigned long long)phys);
		return 2;
	}
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, LO & ~0x3fffULL);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *r = p + ((phys - (LO & ~0x3fffULL)) / 4);
	*r = val;
	printf("0x%llx <- 0x%x, reads back 0x%x\n", (unsigned long long)phys, val, *r);
	return 0;
}
