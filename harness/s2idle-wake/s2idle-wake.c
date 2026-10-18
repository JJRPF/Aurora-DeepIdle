// SPDX-License-Identifier: GPL-2.0
/*
 * Test only: end an s2idle suspend after a set time, since macsmc-rtc has no alarm.
 *
 *   insmod s2idle-wake.ko seconds=1200      every suspend from now ends after 20 min
 *   echo 0 > /sys/module/s2idle_wake/parameters/seconds   off again (or rmmod)
 *
 * A CLOCK_BOOTTIME hrtimer armed at PM_SUSPEND_PREPARE calls pm_system_wakeup(). Nothing
 * programs a wake-up in hardware: the timer is checked on the SoC's own wake-ups in s2idle
 * (the AOP mailbox wakes it a few times a second), so the suspend ends at most a few
 * hundred ms late. The lid still wakes the machine as usual.
 */
#include <linux/hrtimer.h>
#include <linux/module.h>
#include <linux/suspend.h>

static unsigned int seconds;
module_param(seconds, uint, 0644);
MODULE_PARM_DESC(seconds, "end each suspend after this many seconds (0 = off)");

static struct hrtimer timer;
static bool fired;

static enum hrtimer_restart wake_fn(struct hrtimer *t)
{
	fired = true;
	pm_system_wakeup();
	return HRTIMER_NORESTART;
}

static int pm_cb(struct notifier_block *nb, unsigned long action, void *data)
{
	switch (action) {
	case PM_SUSPEND_PREPARE:
		fired = false;
		if (seconds)
			hrtimer_start(&timer, ktime_set(seconds, 0), HRTIMER_MODE_REL);
		break;
	case PM_POST_SUSPEND:
		hrtimer_cancel(&timer);
		if (seconds)
			pr_info("s2idle-wake: %s after %u s\n", fired ? "woke it" : "did not fire", seconds);
		break;
	}
	return NOTIFY_DONE;
}

static struct notifier_block nb = { .notifier_call = pm_cb };

static int __init s2idle_wake_init(void)
{
	hrtimer_setup(&timer, wake_fn, CLOCK_BOOTTIME, HRTIMER_MODE_REL);
	return register_pm_notifier(&nb);
}

static void __exit s2idle_wake_exit(void)
{
	unregister_pm_notifier(&nb);
	hrtimer_cancel(&timer);
}

module_init(s2idle_wake_init);
module_exit(s2idle_wake_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("End s2idle after a set time (deep idle test)");
