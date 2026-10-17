// Reproducible desktop-like wake load for the deep idle A/B: THREADS threads, each sleeping an
// exponentially distributed time (mean MEAN_US) and then spinning WORK_US, until killed.
// usage: wakeload THREADS MEAN_US WORK_US
#define _GNU_SOURCE
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long mean_us, work_us;

static uint64_t now_ns(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000000000ull + t.tv_nsec;
}

static void *worker(void *arg)
{
	unsigned int seed = (unsigned int)(uintptr_t)arg * 2654435761u;
	for (;;) {
		double u = (rand_r(&seed) + 1.0) / ((double)RAND_MAX + 2.0);
		long ns = (long)(-log(u) * mean_us * 1000.0);
		struct timespec t = { ns / 1000000000, ns % 1000000000 };
		clock_nanosleep(CLOCK_MONOTONIC, 0, &t, NULL);
		uint64_t end = now_ns() + work_us * 1000;
		while (now_ns() < end)
			;
	}
	return NULL;
}

int main(int argc, char **argv)
{
	if (argc != 4) {
		fprintf(stderr, "usage: %s THREADS MEAN_US WORK_US\n", argv[0]);
		return 2;
	}
	int threads = atoi(argv[1]);
	mean_us = atol(argv[2]);
	work_us = atol(argv[3]);
	pthread_t t;
	for (int i = 0; i < threads; i++)
		pthread_create(&t, NULL, worker, (void *)(uintptr_t)(i + 1));
	pthread_join(t, NULL);
	return 0;
}
