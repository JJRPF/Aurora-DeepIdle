/* scan-magic: search the "reserved" DRAM ranges (nested ones too) of /proc/iomem for a 64-bit value (8-byte aligned),
 * print the address and the next 8 words. Read only. usage: scan-magic <value> [maxrange-MB] */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 2) return 2;
	uint64_t magic = strtoull(argv[1], NULL, 0);
	uint64_t maxlen = (argc > 2 ? strtoull(argv[2], NULL, 0) : 64) << 20;
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	FILE *f = fopen("/proc/iomem", "r");
	char line[256];
	while (fgets(line, sizeof line, f)) {
		unsigned long long a, b;
		if (!strstr(line, "reserved")) continue;
		if (sscanf(line + strspn(line, " "), "%llx-%llx", &a, &b) != 2) continue;
		if (a < 0x10000000000ULL || a >= 0x20000000000ULL) continue;
		uint64_t len = b - a + 1;
		if (len > maxlen) continue;
		volatile uint64_t *p = mmap(NULL, len, PROT_READ, MAP_SHARED, fd, a);
		if (p == MAP_FAILED) continue;
		for (uint64_t i = 0; i < len / 8; i++)
			if (p[i] == magic) {
				printf("0x%llx:", (unsigned long long)(a + i * 8));
				for (int k = 1; k <= 24 && i + k < len / 8; k++)
					printf(" %llx", (unsigned long long)p[i + k]);
				printf("\n");
			}
		munmap((void *)p, len);
	}
	return 0;
}
