/* sep-outbox-off: clear the enable bit (bit 0) of the SEP mailbox's OUTBOX_CTRL on J414s/T6020
 * (0x396408000 + 0x114) through /dev/mem, as macOS does after the enclave's SLEEP ack.
 * Only that word; test boots that end in a reset only (nothing sets it again).
 * usage: sep-outbox-off */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

#define MBOX 0x396408000ULL

int main(void)
{
	long pg = sysconf(_SC_PAGESIZE);
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, pg, PROT_READ | PROT_WRITE, MAP_SHARED,
				    fd, MBOX & ~((uint64_t)pg - 1));
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *r = p + (((MBOX & ((uint64_t)pg - 1)) + 0x114) >> 2);
	uint32_t before = *r;
	*r = before & ~1u;
	printf("0x%08x -> 0x%08x\n", before, *r);
	return 0;
}
