// burst-load: synchronized on/off load on every CPU core, to test whether sudden power steps on
// battery cause the UX3407NA's hard resets. All cores switch on and off at the same instant
// (shared CLOCK_MONOTONIC schedule), running NEON fused multiply-adds (high current) while "on".
//
// Build:  gcc -O2 -o /tmp/burst-load ~/work/omarchy-setup/ux3407na/tools/burst-load.c
// Run:    /tmp/burst-load              all cores, full schedule (~2.5 min)
//         /tmp/burst-load 1 0.05       1 core, 5% of the durations (quick harmless check)
// Progress goes to the terminal and to the journal (journalctl -t burst-load), so after a reset
// `journalctl -b -1 -t burst-load` shows which phase was running. Ctrl+C stops it.
#define _GNU_SOURCE
#include <arm_neon.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

struct phase { const char *name; long on_us, off_us, secs; };
static const struct phase phases[] = {
	{ "1 s on / 2 s off (like the first test)", 1000000, 2000000, 15 },
	{ "100 ms on / 100 ms off",                  100000,  100000, 30 },
	{ "20 ms on / 80 ms off",                     20000,   80000, 30 },
	{ "5 ms on / 15 ms off",                       5000,   15000, 30 },
	{ "1 ms on / 4 ms off",                        1000,    4000, 30 },
	{ "continuous full load",                         1,       0, 15 },
};
#define NPHASES (sizeof(phases) / sizeof(phases[0]))

static long long now_ns(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000000000LL + t.tv_nsec;
}

static void sleep_until(long long ns)
{
	struct timespec t = { ns / 1000000000LL, ns % 1000000000LL };
	while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &t, NULL))
		;
}

static volatile float sink;

static void spin_until(long long end)
{
	float32x4_t a0 = vdupq_n_f32(1.0f), a1 = a0, a2 = a0, a3 = a0, a4 = a0, a5 = a0, a6 = a0, a7 = a0;
	const float32x4_t m = vdupq_n_f32(0.9999999f), c = vdupq_n_f32(1e-7f);

	while (now_ns() < end) {
		for (int i = 0; i < 256; i++) {
			a0 = vfmaq_f32(c, a0, m); a1 = vfmaq_f32(c, a1, m);
			a2 = vfmaq_f32(c, a2, m); a3 = vfmaq_f32(c, a3, m);
			a4 = vfmaq_f32(c, a4, m); a5 = vfmaq_f32(c, a5, m);
			a6 = vfmaq_f32(c, a6, m); a7 = vfmaq_f32(c, a7, m);
		}
	}
	a0 = vaddq_f32(vaddq_f32(vaddq_f32(a0, a1), vaddq_f32(a2, a3)), vaddq_f32(vaddq_f32(a4, a5), vaddq_f32(a6, a7)));
	sink += vgetq_lane_f32(a0, 0);
}

static void worker(int cpu, long long start, double scale)
{
	cpu_set_t set;
	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	sched_setaffinity(0, sizeof(set), &set);

	long long t = start;
	for (unsigned p = 0; p < NPHASES; p++) {
		long long on = phases[p].on_us * 1000LL, off = phases[p].off_us * 1000LL;
		long long end = t + (long long)(phases[p].secs * scale * 1e9);
		if (off == 0) {
			sleep_until(t);
			spin_until(end);
		} else {
			for (long long k = t; k < end; k += on + off) {
				sleep_until(k);
				spin_until(k + on);
			}
		}
		t = end;
	}
	_exit(0);
}

int main(int argc, char **argv)
{
	int ncpu = argc > 1 ? atoi(argv[1]) : (int)sysconf(_SC_NPROCESSORS_ONLN);
	double scale = argc > 2 ? atof(argv[2]) : 1.0;
	long long start = now_ns() + 500000000LL;

	openlog("burst-load", 0, LOG_USER);
	printf("burst-load: %d cores, schedule scale %.2f\n", ncpu, scale);
	for (int i = 0; i < ncpu; i++)
		if (fork() == 0)
			worker(i, start, scale);

	long long t = start;
	for (unsigned p = 0; p < NPHASES; p++) {
		sleep_until(t);
		printf("phase %u/%zu: %s for %.0f s\n", p + 1, NPHASES, phases[p].name, phases[p].secs * scale);
		fflush(stdout);
		syslog(LOG_NOTICE, "phase %u/%zu: %s (%d cores)", p + 1, NPHASES, phases[p].name, ncpu);
		t += (long long)(phases[p].secs * scale * 1e9);
	}
	while (wait(NULL) > 0)
		;
	printf("finished, no reset\n");
	syslog(LOG_NOTICE, "finished, no reset");
	return 0;
}
