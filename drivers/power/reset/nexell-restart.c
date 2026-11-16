// SPDX-License-Identifier: GPL-2.0
/*
 * Nexell S5P6818 restart handler.
 *
 * PSCI SYSTEM_RESET (via the fork bootloader's secure monitor) only performs a
 * partial reset on this SoC and comes back unreliably. Do the same full
 * software reset the vendor u-boot's reset_cpu() does: arm the software-reset
 * enable in CLKPWR PWRCONT, then trigger it in PWRMODE. That is a full SoC
 * reset and reboots cleanly.
 *
 * Copyright (C) 2026 Igor Pecovnik <igor@armbian.com>
 */

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/notifier.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>
#include <linux/reboot.h>

/* offsets within the CLKPWR block (reg base points at PWRCONT) */
#define NX_PWRCONT		0x00	/* 0xc0010224 */
#define NX_PWRMODE		0x04	/* 0xc0010228 */
#define NX_SWRST_ENABLE		BIT(3)	/* in PWRCONT: arm software reset */
#define NX_SWRST_TRIGGER	BIT(12)	/* in PWRMODE: fire software reset */

struct nx_restart {
	void __iomem *base;
	struct notifier_block nb;
};

static int nx_restart_notify(struct notifier_block *nb, unsigned long action,
			     void *data)
{
	struct nx_restart *priv = container_of(nb, struct nx_restart, nb);
	u32 val;

	val = readl(priv->base + NX_PWRCONT);
	writel(val | NX_SWRST_ENABLE, priv->base + NX_PWRCONT);
	writel(NX_SWRST_TRIGGER, priv->base + NX_PWRMODE);

	/* give the reset time to take effect before falling through */
	mdelay(500);

	return NOTIFY_DONE;
}

static int nx_restart_probe(struct platform_device *pdev)
{
	struct nx_restart *priv;
	int ret;

	priv = devm_kzalloc(&pdev->dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	/*
	 * of_iomap() (not a reserving mapping): PWRCONT is shared with the RTC
	 * wakeup bit, so this window overlaps the RTC's clkpwr mapping.
	 */
	priv->base = of_iomap(pdev->dev.of_node, 0);
	if (!priv->base)
		return -ENOMEM;

	priv->nb.notifier_call = nx_restart_notify;
	priv->nb.priority = 192;	/* above PSCI's restart handler (129) */

	ret = register_restart_handler(&priv->nb);
	if (ret) {
		iounmap(priv->base);
		return ret;
	}

	platform_set_drvdata(pdev, priv);
	return 0;
}

static void nx_restart_remove(struct platform_device *pdev)
{
	struct nx_restart *priv = platform_get_drvdata(pdev);

	unregister_restart_handler(&priv->nb);
	iounmap(priv->base);
}

static const struct of_device_id nx_restart_of_match[] = {
	{ .compatible = "nexell,s5p6818-reboot" },
	{}
};
MODULE_DEVICE_TABLE(of, nx_restart_of_match);

static struct platform_driver nx_restart_driver = {
	.probe = nx_restart_probe,
	.remove = nx_restart_remove,
	.driver = {
		.name = "nexell-restart",
		.of_match_table = nx_restart_of_match,
	},
};
builtin_platform_driver(nx_restart_driver);
