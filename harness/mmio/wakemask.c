/* wakemask: the PMGR's AP wake-source mask (9 words at 0x29e00400c, 1 = disabled; macOS 13.5
 * AppleT6020PMGR::setAPWakeupSources) and the wake status (9 words at 0x29e004030). Only these
 * addresses can be reached.
 * usage: wakemask show | wakemask macos | wakemask write w0 .. w8
 *   macos: write what macOS writes, valid & ~enabled (only its 22 ADT ap-wake-sources enabled) */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define PAGE   0x29e004000ULL /* PMGR RegMap 42 = ADT pmgr reg 7 (not reg 42) */
#define MASK   0x0c
#define STATUS 0x30
#define WORDS  9

static const uint32_t macos[WORDS] = {
	0x0c005000, 0x005e0900, 0x04200000, 0xc0000000, 0x0000003f, 0, 0x80000000, 0, 0,
};

static const uint32_t valid[WORDS] = {	/* getAPWakeupSourcesValidMasks */
	0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0x0000007f,
};

static void show(volatile uint32_t *p, const char *what)
{
	printf("%s mask", what);
	for (int i = 0; i < WORDS; i++)
		printf(" %08x", p[(MASK >> 2) + i]);
	printf("; status");
	for (int i = 0; i < WORDS; i++)
		printf(" %08x", p[(STATUS >> 2) + i]);
	printf("\n");
	fflush(stdout);
}

int main(int argc, char **argv)
{
	if (argc < 2 || (strcmp(argv[1], "show") && strcmp(argv[1], "macos") &&
			 (strcmp(argv[1], "write") || argc != 2 + WORDS))) {
		fprintf(stderr, "usage: %s show | macos | write w0 .. w8\n", argv[0]);
		return 2;
	}
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, PAGE);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	show(p, "before");
	if (!strcmp(argv[1], "show"))
		return 0;
	for (int i = 0; i < WORDS; i++) {
		uint32_t v = !strcmp(argv[1], "macos") ? valid[i] & ~macos[i]
						       : (uint32_t)strtoul(argv[2 + i], NULL, 16);
		p[(MASK >> 2) + i] = v;
	}
	__sync_synchronize();
	show(p, "after");
	return 0;
}
