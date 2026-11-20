// SPDX-License-Identifier: GPL-2.0
/*
 * GH-5 test module: after a real S2R wake on T6020 (J414s) the Wi-Fi's PCIe slot is unpowered (the SMC dropped PWREN,
 * SMC gpio 13) and its link is down; pcie-apple only powers and trains the slot at probe. Replay that part of
 * apple_pcie_setup_port() for port 0: PERST# assert, PWREN on, 150 ms, PERST# release (port register and AP gpio 4),
 * wait PORT_STATUS ready, start the LTSSM and wait for link up. Userspace then rescans PCI. Results in dmesg and in
 * the module parameter "result": bit 0 port ready, bit 1 link up, bit 2 PWREN reads 1, bit 3 PERST# reads released,
 * bit 4 refclk ACKs; bits 8-15 PORT_STATUS, 16-23 LINKSTS at the end; negative = error. v2 adds the PHY refclk
 * request (apple_pcie_setup_refclk) between PWREN and the PERST# release.
 */
#include <linux/module.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/iopoll.h>

#define PORT0_BASE     0x594008000ULL
#define PORT_LTSSMCTL  0x080
#define PORT_INTSTAT   0x100
#define PORT_LINKSTS   0x208
#define PORT_STATUS    0x804
#define PORT_T602X_PERST 0x82c
#define PHY0_BASE      0x59e00c000ULL /* t602x port 0 PHY lane (DT reg "phy0") */

static int result = -1;
module_param(result, int, 0444);
static char *smc_label = "macsmc-pmu-gpio";
module_param(smc_label, charp, 0444);
static char *ap_label = "39b028000.pinctrl";
module_param(ap_label, charp, 0444);

static struct gpio_desc *find_desc(const char *label, unsigned int line)
{
	struct gpio_device *gdev = gpio_device_find_by_label(label);
	struct gpio_desc *d;

	if (!gdev)
		return NULL;
	d = gpio_device_get_desc(gdev, line);
	gpio_device_put(gdev);
	return IS_ERR(d) ? NULL : d;
}

static int __init kick_init(void)
{
	struct gpio_desc *pwren = find_desc(smc_label, 13), *perst = find_desc(ap_label, 4);
	void __iomem *p = ioremap(PORT0_BASE, 0x4000);
	u32 v;
	int ret, refclk_ok = 0;

	if (!pwren || !perst || !p) {
		pr_err("s2r_wifi_kick: pwren %p perst %p regs %p\n", pwren, perst, p);
		result = -2;
		if (p)
			iounmap(p);
		return 0;
	}
	pr_info("s2r_wifi_kick: before: pwren %d perst %d linksts %#x status %#x perstreg %#x\n",
		gpiod_get_raw_value_cansleep(pwren), gpiod_get_raw_value_cansleep(perst),
		readl(p + PORT_LINKSTS), readl(p + PORT_STATUS), readl(p + PORT_T602X_PERST));
	gpiod_set_raw_value_cansleep(perst, 0);			/* PERST# is active low: assert */
	writel(readl(p + PORT_T602X_PERST) & ~1U, p + PORT_T602X_PERST);
	gpiod_set_raw_value_cansleep(pwren, 0);
	msleep(2);
	gpiod_set_raw_value_cansleep(pwren, 1);
	{
		void __iomem *phy = ioremap(PHY0_BASE, 0x4000);

		if (phy) {
			writel(readl(phy) | BIT(0), phy);
			ret = readl_poll_timeout(phy, v, v & BIT(2), 100, 50000);
			if (!ret) {
				writel(readl(phy) | BIT(1), phy);
				ret = readl_poll_timeout(phy, v, v & BIT(3), 100, 50000);
			}
			if (!ret) {
				writel(readl(phy) | BIT(9) | BIT(10), phy);
				refclk_ok = 1;
			}
			iounmap(phy);
		}
	}
	msleep(150);
	writel(readl(p + PORT_T602X_PERST) | 1U, p + PORT_T602X_PERST);
	gpiod_set_raw_value_cansleep(perst, 1);			/* release */
	msleep(100);
	ret = readl_poll_timeout(p + PORT_STATUS, v, v & 1, 100, 250000);
	result = ret ? 0 : 1;
	writel(~0U, p + PORT_INTSTAT);
	writel(1, p + PORT_LTSSMCTL);
	ret = readl_poll_timeout(p + PORT_LINKSTS, v, v & 1, 1000, 1000000);
	if (!ret)
		result |= 2;
	if (gpiod_get_raw_value_cansleep(pwren) == 1)
		result |= 4;
	if (gpiod_get_raw_value_cansleep(perst) == 1)
		result |= 8;
	if (refclk_ok)
		result |= 16;
	result |= (readl(p + PORT_STATUS) & 0xff) << 8 | (readl(p + PORT_LINKSTS) & 0xff) << 16;
	pr_info("s2r_wifi_kick: after: result %d pwren %d perst %d linksts %#x status %#x\n", result,
		gpiod_get_raw_value_cansleep(pwren), gpiod_get_raw_value_cansleep(perst),
		readl(p + PORT_LINKSTS), readl(p + PORT_STATUS));
	iounmap(p);
	return 0;
}

static void __exit kick_exit(void)
{
}

module_init(kick_init);
module_exit(kick_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("GH-5 test: repower and retrain the Wi-Fi PCIe slot after an S2R wake");
