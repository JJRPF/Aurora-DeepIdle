// Wake-up latency probe: timer overshoot on one CPU, or futex wake across two CPUs.
// usage: wakelat timer CPU SAMPLES PERIOD_US
//        wakelat ipi CPU_WAKER CPU_SLEEPER SAMPLES PERIOD_US
// Prints p50 p90 p99 max in microseconds. Runs SCHED_FIFO 50 when allowed.
#define _GNU_SOURCE
#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static int64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

static void pin(int cpu)
{
	cpu_set_t set;
	struct sched_param sp = { .sched_priority = 50 };

	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set)) {
		perror("sched_setaffinity");
		exit(1);
	}
	sched_setscheduler(0, SCHED_FIFO, &sp);
}

static int cmp(const void *a, const void *b)
{
	int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
	return (x > y) - (x < y);
}

static void report(int64_t *lat, int n)
{
	qsort(lat, n, sizeof(*lat), cmp);
	printf("p50 %.1f p90 %.1f p99 %.1f max %.1f\n", lat[n / 2] / 1e3, lat[n * 9 / 10] / 1e3,
	       lat[n * 99 / 100] / 1e3, lat[n - 1] / 1e3);
}

static atomic_int word;
static _Atomic int64_t stamp;
static int sleeper_cpu, samples;
static int64_t *lat;

static void *sleeper(void *arg)
{
	(void)arg;
	pin(sleeper_cpu);
	for (int i = 0; i < samples; i++) {
		while (atomic_load(&word) == 0)
			syscall(SYS_futex, &word, FUTEX_WAIT_PRIVATE, 0, NULL, NULL, 0);
		lat[i] = now_ns() - atomic_load(&stamp);
		atomic_store(&word, 0);
	}
	return NULL;
}

int main(int argc, char **argv)
{
	if (argc == 5 && !strcmp(argv[1], "timer")) {
		int cpu = atoi(argv[2]), n = atoi(argv[3]);
		int64_t period = atoll(argv[4]) * 1000, *l = calloc(n, sizeof(*l));
		struct timespec ts;

		pin(cpu);
		clock_gettime(CLOCK_MONOTONIC, &ts);
		for (int i = 0; i < n; i++) {
			int64_t target = (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec + period;

			ts.tv_sec = target / 1000000000;
			ts.tv_nsec = target % 1000000000;
			clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL);
			l[i] = now_ns() - target;
		}
		report(l, n);
		return 0;
	}
	if (argc == 6 && !strcmp(argv[1], "ipi")) {
		int waker = atoi(argv[2]);
		int64_t period = atoll(argv[5]) * 1000;
		pthread_t t;

		sleeper_cpu = atoi(argv[3]);
		samples = atoi(argv[4]);
		lat = calloc(samples, sizeof(*lat));
		pthread_create(&t, NULL, sleeper, NULL);
		pin(waker);
		for (int i = 0; i < samples; i++) {
			struct timespec ts = { 0, period };

			nanosleep(&ts, NULL);
			while (atomic_load(&word) != 0)
				sched_yield();
			atomic_store(&stamp, now_ns());
			atomic_store(&word, 1);
			syscall(SYS_futex, &word, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
		}
		pthread_join(t, NULL);
		report(lat, samples);
		return 0;
	}
	fprintf(stderr, "usage: wakelat timer CPU N PERIOD_US | ipi WAKER SLEEPER N PERIOD_US\n");
	return 2;
}
