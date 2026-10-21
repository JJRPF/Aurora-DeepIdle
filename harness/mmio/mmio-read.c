/* mmio-read: read 32-bit MMIO words through /dev/mem. Read only.
 * usage: mmio-read <phys-addr> [count-words] */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s <phys> [words]\n", argv[0]);
		return 2;
	}
	uint64_t phys = strtoull(argv[1], NULL, 0);
	unsigned long n = argc > 2 ? strtoul(argv[2], NULL, 0) : 1;
	long pg = sysconf(_SC_PAGESIZE);
	uint64_t base = phys & ~(uint64_t)(pg - 1);
	size_t len = (phys - base) + n * 4;
	len = (len + pg - 1) & ~(size_t)(pg - 1);
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, base);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *w = (volatile uint32_t *)((volatile char *)p + (phys - base));
	for (unsigned long i = 0; i < n; i++)
		printf("0x%09llx 0x%08x\n", (unsigned long long)(phys + 4 * i), w[i]);
	return 0;
}
