// SPDX-License-Identifier: GPL-2.0-only
/*
 * Test only: switch the HDMI port's two power rails off and on at run time,
 * to measure what they cost with nothing plugged in.
 *
 * The DCP driver (dcpext0) requests hdmi-pwren (SMC GPIO 23, gP17) and
 * dp2hdmi-pwren (SMC GPIO 6, gP06) high at probe and never lowers them; its
 * own TODO asks whether that is needed. This module drives those two lines
 * through gpiolib, through the descriptors the DCP already holds; it touches
 * no other line. Unloading it turns both rails back on.
 *
 *   insmod smc-pwr-test.ko
 *   echo 0 > /sys/module/smc_pwr_test/parameters/hdmi       # gP17 off
 *   echo 0 > /sys/module/smc_pwr_test/parameters/dp2hdmi    # gP06 off (HDMI hot-plug detect needs it)
 *   rmmod smc_pwr_test                                      # both on again
 *
 * Only with nothing plugged into the HDMI port.
 */
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/module.h>
#include <linux/moduleparam.h>

#define SMC_GPIO_LABEL	"macsmc-pmu-gpio"
#define LINE_HDMI	23
#define LINE_DP2HDMI	6

static struct gpio_device *gdev;
static int hdmi = 1, dp2hdmi = 1;

static int set_line(unsigned int line, int on)
{
	struct gpio_desc *desc = gpio_device_get_desc(gdev, line);

	if (IS_ERR(desc))
		return PTR_ERR(desc);
	return gpiod_set_raw_value_cansleep(desc, on);
}

static int param_set_line(const char *val, const struct kernel_param *kp)
{
	unsigned int line = kp->arg == &hdmi ? LINE_HDMI : LINE_DP2HDMI;
	bool on;
	int ret;

	ret = kstrtobool(val, &on);
	if (ret)
		return ret;
	if (!gdev)
		return -ENODEV;
	ret = set_line(line, on);
	if (ret)
		return ret;
	*(int *)kp->arg = on;
	pr_info("smc-pwr-test: SMC GPIO %u (%s) %s\n", line,
		line == LINE_HDMI ? "hdmi-pwren" : "dp2hdmi-pwren", on ? "on" : "off");
	return 0;
}

static const struct kernel_param_ops line_ops = {
	.set = param_set_line,
	.get = param_get_int,
};
module_param_cb(hdmi, &line_ops, &hdmi, 0644);
MODULE_PARM_DESC(hdmi, "HDMI power, SMC GPIO 23 (gP17): 1 on, 0 off");
module_param_cb(dp2hdmi, &line_ops, &dp2hdmi, 0644);
MODULE_PARM_DESC(dp2hdmi, "DP-to-HDMI converter power, SMC GPIO 6 (gP06): 1 on, 0 off");

static int __init smc_pwr_test_init(void)
{
	gdev = gpio_device_find_by_label(SMC_GPIO_LABEL);
	if (!gdev) {
		pr_err("smc-pwr-test: no GPIO chip labelled %s\n", SMC_GPIO_LABEL);
		return -ENODEV;
	}
	pr_info("smc-pwr-test: loaded; HDMI rails on until written\n");
	return 0;
}

static void __exit smc_pwr_test_exit(void)
{
	set_line(LINE_DP2HDMI, 1);
	set_line(LINE_HDMI, 1);
	gpio_device_put(gdev);
	pr_info("smc-pwr-test: unloaded; HDMI rails on\n");
}

module_init(smc_pwr_test_init);
module_exit(smc_pwr_test_exit);
MODULE_DESCRIPTION("Test only: HDMI power rails off/on at run time");
MODULE_LICENSE("GPL");
