/* ps-sep-write: one 32-bit write to the SEP's PMGR power word on J414s/T6020
 * (pmgr_east 0x290280000 + 0xc00) through /dev/mem, then the read-back.
 * Only that address; test boots that end in a reset only (nothing restores it).
 * usage: ps-sep-write <value> */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#define PS_SEP 0x290280c00ULL

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s <value>\n", argv[0]);
		return 2;
	}
	uint32_t val = strtoul(argv[1], NULL, 0);
	long pg = sysconf(_SC_PAGESIZE);
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_SHARED,
				    fd, PS_SEP & ~((uint64_t)pg - 1));
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *r = p + ((PS_SEP & ((uint64_t)pg - 1)) >> 2);
	uint32_t before = *r;
	*r = val;
	printf("0x%08x -> 0x%08x\n", before, *r);
	return 0;
}
