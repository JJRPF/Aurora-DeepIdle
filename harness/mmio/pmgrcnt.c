/* pmgrcnt: the PMGR's system-state counters (ADT pmgr `events`, perf block 0 = pmgr reg 1 + 0x48000,
 * 0x29e2c8000, perf-counter-version 1: config at +0x100 + 16 * idx, 64-bit count at +0x108/+0x10c).
 * Only indices 42 to 55 of that block can be reached.
 * usage: pmgrcnt show | pmgrcnt enable
 *   enable: config = (old & ~7) | 4 | 1, as ApplePMGR::_enableSOCPerfCounter(group, idx, true, false) */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define BLOCK 0x29e2c8000ULL
static const char *names[] = { "SLP_DDR", "SLP_DDR.2", "AWAKE", "AWAKE.2", "SLP_S2R", "SLP_S2R.2",
	"DEEP_WAIT", "DEEP_WAIT.2", "SYS_AWAKE", "SYS_AWAKE.2", "SYS_S2R_AOP", "SYS_S2R_AOP.2",
	"SYS_SLP_DDR", "SYS_SLP_DDR.2" };

int main(int argc, char **argv)
{
	int en = argc == 2 && !strcmp(argv[1], "enable");
	if (argc != 2 || (!en && strcmp(argv[1], "show"))) {
		fprintf(stderr, "usage: %s show | enable\n", argv[0]);
		return 2;
	}
	int fd = open("/dev/mem", en ? O_RDWR | O_SYNC : O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, 0x1000, en ? PROT_READ | PROT_WRITE : PROT_READ, MAP_SHARED, fd, BLOCK);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	for (int idx = 42; idx <= 55; idx++) {
		volatile uint32_t *c = p + ((0x100 + 16 * idx) >> 2);
		if (en)
			c[0] = (c[0] & ~7u) | 4 | 1;
		printf("%s=%x:%llu ", names[idx - 42], c[0],
		       (unsigned long long)c[2] | (unsigned long long)c[3] << 32);
	}
	printf("\n");
	return 0;
}
