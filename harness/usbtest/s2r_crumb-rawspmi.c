// SPDX-License-Identifier: GPL-2.0
/*
 * GH-5 debug: write suspend progress to the PMU's scratch (it survives a reset; DRAM does not), with a raw,
 * polled SPMI write on nub-spmi0 (as Aura's qs_crumb_write does), so it keeps working with interrupts off and
 * the AIC masked (the SPMI driver waits for its completion IRQ there and hangs).
 * 0x601d counter, 0x6020 event, 0x6021 phase letter, 0x6022/0x6023/0x6025/0x6026/0x6027 five name chars.
 */
#include <linux/device.h>
#include <linux/pm.h>
#include <linux/string.h>
#include <linux/io.h>
#include <linux/delay.h>

#define S2R_SPMI_BASE	0x29e114000ULL
#define S2R_PMU_ADDR	0xb
#define ST		0x00
#define CMD		0x04
#define RSP		0x08
#define RX_EMPTY	BIT(24)
#define TX_EMPTY	BIT(8)

static void __iomem *s2r_spmi;
static u8 s2r_crumb_count;

void s2r_crumb_raw(u16 reg, const u8 *v, int len)
{
	u32 data = 0;
	int i;

	if (!s2r_spmi || len < 1 || len > 4)
		return;
	for (i = 0; i < 2000000 && !(readl(s2r_spmi + ST) & TX_EMPTY); i++)
		cpu_relax();
	for (i = 0; i < 16 && !(readl(s2r_spmi + ST) & RX_EMPTY); i++)
		readl(s2r_spmi + RSP);
	writel(((u32)reg << 16) | BIT(15) | (S2R_PMU_ADDR << 8) | 0x30 | (len - 1), s2r_spmi + CMD);
	for (i = 0; i < len; i++)
		data |= (u32)v[i] << (8 * i);
	writel(data, s2r_spmi + CMD);
	for (i = 0; i < 2000000; i++) {
		if (!(readl(s2r_spmi + ST) & RX_EMPTY)) {
			readl(s2r_spmi + RSP);
			writel(1, s2r_spmi + 0x80);
			(void)readl(s2r_spmi + 0x80);
			return;
		}
		cpu_relax();
	}
}

static void s2r_put(u8 ev, u8 ph, const char *n)
{
	u8 a[4] = { ev, ph, 0, 0 }, b[3] = { };
	int i;

	for (i = 0; n && n[i] && i < 5; i++) {
		if (i < 2)
			a[2 + i] = n[i];
		else
			b[i - 2] = n[i];
	}
	s2r_crumb_count++;
	s2r_crumb_raw(0x601d, &s2r_crumb_count, 1);
	s2r_crumb_raw(0x6020, a, 4);
	s2r_crumb_raw(0x6025, b, 3);
}

void s2r_crumb(struct device *dev, pm_message_t state, const char *info)
{
	if (!s2r_spmi)
		s2r_spmi = ioremap(S2R_SPMI_BASE, 0x4000);
	/* R58M: no per-device crumbs (the SPMI driver may be mid-transfer on another CPU); device suspend is known to finish */
}

void s2r_crumb_mark(char c)
{
	s2r_put(0xee, c, NULL);
}

void s2r_crumb_fn(int idx, void *fn)
{
	char n[16];

	snprintf(n, sizeof(n), "%ps", fn);
	s2r_put(0xef, idx, n);
}

void s2r_crumb_aic(u8 stage, u16 i)
{
	u8 a[4] = { 0xa1, stage, i & 0xff, i >> 8 };

	s2r_crumb_raw(0x6020, a, 4);
}
