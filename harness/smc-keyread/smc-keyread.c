// SPDX-License-Identifier: GPL-2.0
/*
 * Read-only SMC power sensor dump for the deep idle work (test module, not for upstream).
 *
 * At load it lists every readable, non-function SMC key of type 'flt ' whose name starts
 * with 'P' (the power sensors), then /sys/kernel/debug/smc_keyread/power reads them all:
 * "KEY raw-hex milliwatts" per line. .../all lists every key: name, type, size, flags, and
 * for a readable non-function key of at most 8 bytes its raw value. Only
 * apple_smc_get_key_by_index, apple_smc_get_key_info and apple_smc_read are used; nothing is
 * written to the SMC.
 */
#include <linux/debugfs.h>
#include <linux/device.h>
#include <linux/mfd/macsmc.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/seq_file.h>
#include <linux/slab.h>

#define MAX_KEYS 256

static char *smc_dev = "2a2400000.smc";
module_param(smc_dev, charp, 0444);

static struct device *dev;
static struct apple_smc *smc;
static smc_key keys[MAX_KEYS];
static int nkeys;
/* "watch": up to 16 keys named by the keys= parameter, read raw (at most 8 bytes each). */
static char *watch_keys = "zSPa zSPc zSPi zSLa zSEw zSEi zSAa BAAC";
module_param(watch_keys, charp, 0444);
static smc_key wkeys[16];
static u8 wsize[16];
static int nwkeys;
static struct dentry *dir;

/* IEEE 754 single to an integer in thousandths, without the FPU. */
static s64 f32_milli(u32 b)
{
	int e = (b >> 23) & 0xff;
	s64 m = b & 0x7fffff, v;

	if (e == 0)
		return 0;
	if (e == 0xff)
		return S64_MAX;
	m |= 0x800000;
	e -= 127 + 23;
	v = m * 1000;
	v = e >= 0 ? (e > 30 ? S64_MAX : v << e) : (-e > 62 ? 0 : v >> -e);
	return (b >> 31) ? -v : v;
}

static int power_show(struct seq_file *s, void *unused)
{
	int i;

	for (i = 0; i < nkeys; i++) {
		u32 raw;
		int ret = apple_smc_read(smc, keys[i], &raw, sizeof(raw));

		if (ret < 0)
			seq_printf(s, "%p4ch err %d\n", &keys[i], ret);
		else
			seq_printf(s, "%p4ch %08x %lld\n", &keys[i], raw, f32_milli(raw));
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(power);

static u32 total;

static int all_show(struct seq_file *s, void *unused)
{
	struct apple_smc_key_info info;
	int i, j;

	for (i = 0; i < total; i++) {
		smc_key key;
		u8 buf[8];
		u32 t;

		if (apple_smc_get_key_by_index(smc, i, &key) < 0 ||
		    apple_smc_get_key_info(smc, key, &info) < 0)
			continue;
		t = info.type_code;
		seq_printf(s, "%p4ch %c%c%c%c %2u %02x", &key, t >> 24, (t >> 16) & 0xff,
			   (t >> 8) & 0xff, t & 0xff, info.size, info.flags);
		if ((info.flags & APPLE_SMC_READABLE) && !(info.flags & APPLE_SMC_FUNCTION) &&
		    info.size && info.size <= sizeof(buf) &&
		    apple_smc_read(smc, key, buf, info.size) >= 0) {
			seq_puts(s, " ");
			for (j = 0; j < info.size; j++)
				seq_printf(s, "%02x", buf[j]);
		}
		seq_puts(s, "\n");
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(all);

static int watch_show(struct seq_file *s, void *unused)
{
	int i, j;

	seq_printf(s, "t_ns %llu\n", ktime_get_boottime_ns());
	for (i = 0; i < nwkeys; i++) {
		u8 buf[8];

		seq_printf(s, "%p4ch ", &wkeys[i]);
		if (apple_smc_read(smc, wkeys[i], buf, wsize[i]) < 0) {
			seq_puts(s, "err\n");
			continue;
		}
		for (j = 0; j < wsize[i]; j++)
			seq_printf(s, "%02x", buf[j]);
		seq_puts(s, "\n");
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(watch);

static void parse_watch(void)
{
	struct apple_smc_key_info info;
	const char *p = watch_keys;

	while (*p && nwkeys < ARRAY_SIZE(wkeys)) {
		smc_key key;

		while (*p == ' ')
			p++;
		if (strlen(p) < 4)
			break;
		key = __SMC_KEY(p[0], p[1], p[2], p[3]);
		p += 4;
		if (apple_smc_get_key_info(smc, key, &info) < 0 || !(info.flags & APPLE_SMC_READABLE) ||
		    (info.flags & APPLE_SMC_FUNCTION) || !info.size || info.size > 8)
			continue;
		wkeys[nwkeys] = key;
		wsize[nwkeys++] = info.size;
	}
}

static int __init smc_keyread_init(void)
{
	struct apple_smc_key_info info;
	u32 count;
	int i, ret;

	dev = bus_find_device_by_name(&platform_bus_type, NULL, smc_dev);
	if (!dev)
		return -ENODEV;
	smc = dev->driver ? dev_get_drvdata(dev) : NULL;
	if (!smc) {
		put_device(dev);
		return -ENODEV;
	}
	ret = apple_smc_read(smc, SMC_KEY(#KEY), &count, sizeof(count));
	if (ret < 0)
		goto fail;
	count = be32_to_cpu((__force __be32)count);
	total = count;
	for (i = 0; i < count && nkeys < MAX_KEYS; i++) {
		smc_key key;
		u8 c;

		if (apple_smc_get_key_by_index(smc, i, &key) < 0)
			continue;
		c = key >> 24;
		if (c != 'P' || apple_smc_get_key_info(smc, key, &info) < 0)
			continue;
		if (info.type_code != __SMC_KEY('f', 'l', 't', ' ') || info.size != 4)
			continue;
		if (!(info.flags & APPLE_SMC_READABLE) || (info.flags & APPLE_SMC_FUNCTION))
			continue;
		keys[nkeys++] = key;
	}
	dir = debugfs_create_dir("smc_keyread", NULL);
	debugfs_create_file("power", 0400, dir, NULL, &power_fops);
	debugfs_create_file("all", 0400, dir, NULL, &all_fops);
	parse_watch();
	debugfs_create_file("watch", 0400, dir, NULL, &watch_fops);
	dev_info(dev, "smc_keyread: %d power keys of %u\n", nkeys, count);
	return 0;
fail:
	put_device(dev);
	return ret;
}

static void __exit smc_keyread_exit(void)
{
	debugfs_remove_recursive(dir);
	put_device(dev);
}

module_init(smc_keyread_init);
module_exit(smc_keyread_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Read-only SMC power sensor dump (deep idle test)");
