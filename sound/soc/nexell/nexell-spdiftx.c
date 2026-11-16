// SPDX-License-Identifier: GPL-2.0
/*
 * Nexell S5P6818/S5P4418 S/PDIF transmitter (ASoC CPU DAI).
 *
 * Ported from the Nexell 4.14 BSP (nexell-spdiftx.c) to the mainline generic
 * dmaengine-PCM. On the S5P6818 the SPDIF-TX output is wired internally to the
 * HDMI controller's S/PDIF input, so this DAI is the audio source for HDMI
 * audio (paired with a spdif-transmitter codec via simple-audio-card).
 *
 * Original author: Hyunseok Jung <hsjung@nexell.co.kr>, Nexell Co., Ltd.
 */

#include <linux/module.h>
#include <linux/clk.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/reset.h>

#include <sound/pcm.h>
#include <sound/pcm_params.h>
#include <sound/soc.h>
#include <sound/dmaengine_pcm.h>

#define SND_SOC_SPDIF_TX_FORMATS \
	(SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S24_LE)
#define SND_SOC_SPDIF_RATES \
	(SNDRV_PCM_RATE_44100 | SNDRV_PCM_RATE_48000 | SNDRV_PCM_RATE_96000)

#define SPDIF_DAT_OFFSET	0x10
#define SPDIF_CLKCON_OFFSET	0x00
#define SPDIF_CON_OFFSET	0x04
#define SPDIF_CSTAS_OFFSET	0x0c

#define CLKCON_POWER_POS	0
#define CON_FIFO_TH_POS		19
#define CON_FIFO_TR_POS		17
#define CON_ENDIAN_POS		13
#define CON_USERDATA_POS	12
#define CON_SW_RESET_POS	5
#define CON_RATIO_POS		3
#define CON_PCM_BIT_POS		1
#define CON_PCM_POS		0

#define CSTAS_FREQUENCY_POS	24
#define CSTAS_CATEGORY_POS	8
#define CSTAS_COPYRIGHT_POS	2
#define CSTAS_PCM_TYPE_POS	1

#define CON_FIFO_LEVEL_15	7
#define CON_FIFO_TR_DMA		0
#define CON_ENDIAN_BIG		0
#define PCM_16BIT		0
#define PCM_24BIT		2
#define RATIO_256		0
#define RATIO_384		1
#define CATEGORY_CD		1
#define NO_COPYRIGHT		1
#define LINEAR_PCM		0

#define SPDIF_MAX_BURST		4	/* bytes */

struct clock_ratio {
	unsigned int sample_rate;
	unsigned int ratio_256;
	unsigned int ratio_384;
	int reg_val;
};

static const struct clock_ratio clk_ratio[] = {
	{  32000,  8192000, 12288000,  3, },
	{  44100, 11289600, 16934400,  0, },
	{  48000, 12288000, 18432000,  2, },
	{  96000, 24576000, 36864000, 10, },
};

struct nx_spdif {
	struct device *dev;
	void __iomem *base;
	struct clk *clk;
	struct reset_control *rst;
	struct snd_dmaengine_dai_dma_data play_dma;
	long master_clock;
	int master_ratio;
	u32 con;
	u32 cstas;
};

/* Compute the clock rate/ratio + CON/CSTAS for a rate + PCM width. */
static int nx_spdif_cfg(struct nx_spdif *nx, unsigned int rate, int pcm_bits)
{
	unsigned long request, rate_hz;
	int ratio, sample_hz = -1, pcm, i;

	pcm = (pcm_bits == 16) ? PCM_16BIT : PCM_24BIT;

	for (i = 0; i < ARRAY_SIZE(clk_ratio); i++) {
		if (rate == clk_ratio[i].sample_rate) {
			sample_hz = clk_ratio[i].reg_val;
			break;
		}
	}
	if (sample_hz < 0) {
		dev_err(nx->dev, "unsupported spdif rate %u\n", rate);
		return -EINVAL;
	}

	ratio = RATIO_384;
	request = clk_ratio[i].ratio_384;
	rate_hz = clk_round_rate(nx->clk, request);
	if (rate_hz != request && pcm == PCM_16BIT) {
		unsigned long o_rate = rate_hz;

		ratio = RATIO_256;
		request = clk_ratio[i].ratio_256;
		rate_hz = clk_round_rate(nx->clk, request);
		if (abs((long)(request - rate_hz)) > abs((long)(request - o_rate))) {
			rate_hz = o_rate;
			ratio = RATIO_384;
		}
	}

	nx->master_clock = rate_hz;
	nx->master_ratio = ratio;

	nx->con = (CON_FIFO_LEVEL_15 << CON_FIFO_TH_POS) |
		  (CON_FIFO_TR_DMA << CON_FIFO_TR_POS) |
		  (CON_ENDIAN_BIG << CON_ENDIAN_POS) |
		  (1 << CON_USERDATA_POS) |
		  (ratio << CON_RATIO_POS) |
		  (pcm << CON_PCM_BIT_POS) |
		  (1 << CON_PCM_POS);
	nx->cstas = (sample_hz << CSTAS_FREQUENCY_POS) |
		    (CATEGORY_CD << CSTAS_CATEGORY_POS) |
		    (LINEAR_PCM << CSTAS_PCM_TYPE_POS) |
		    (NO_COPYRIGHT << CSTAS_COPYRIGHT_POS);
	return 0;
}

static int nx_spdif_hw_params(struct snd_pcm_substream *substream,
			      struct snd_pcm_hw_params *params,
			      struct snd_soc_dai *dai)
{
	struct nx_spdif *nx = snd_soc_dai_get_drvdata(dai);
	int bits = (params_format(params) == SNDRV_PCM_FORMAT_S16_LE) ? 16 : 24;
	int ret;

	nx->play_dma.addr_width = (bits == 16) ?
		DMA_SLAVE_BUSWIDTH_2_BYTES : DMA_SLAVE_BUSWIDTH_4_BYTES;
	nx->play_dma.maxburst = SPDIF_MAX_BURST / (bits == 16 ? 2 : 4);

	ret = nx_spdif_cfg(nx, params_rate(params), bits);
	if (ret)
		return ret;

	/* Apply the clock + program the block for this mode. */
	clk_set_rate(nx->clk, nx->master_clock);
	clk_prepare_enable(nx->clk);

	if (nx->rst && reset_control_status(nx->rst))
		reset_control_reset(nx->rst);
	writel(1 << CON_SW_RESET_POS, nx->base + SPDIF_CON_OFFSET);

	writel(nx->con, nx->base + SPDIF_CON_OFFSET);
	writel(nx->cstas | (readl(nx->base + SPDIF_CSTAS_OFFSET) & 0x3fffffff),
	       nx->base + SPDIF_CSTAS_OFFSET);
	return 0;
}

static int nx_spdif_trigger(struct snd_pcm_substream *substream, int cmd,
			    struct snd_soc_dai *dai)
{
	struct nx_spdif *nx = snd_soc_dai_get_drvdata(dai);
	u32 clkcon = readl(nx->base + SPDIF_CLKCON_OFFSET);

	switch (cmd) {
	case SNDRV_PCM_TRIGGER_RESUME:
	case SNDRV_PCM_TRIGGER_START:
	case SNDRV_PCM_TRIGGER_PAUSE_RELEASE:
		writel(nx->con, nx->base + SPDIF_CON_OFFSET);
		writel(clkcon | (1 << CLKCON_POWER_POS),
		       nx->base + SPDIF_CLKCON_OFFSET);
		break;
	case SNDRV_PCM_TRIGGER_SUSPEND:
	case SNDRV_PCM_TRIGGER_PAUSE_PUSH:
	case SNDRV_PCM_TRIGGER_STOP:
		writel(clkcon & ~(1 << CLKCON_POWER_POS),
		       nx->base + SPDIF_CLKCON_OFFSET);
		break;
	default:
		return -EINVAL;
	}
	return 0;
}

static int nx_spdif_hw_free(struct snd_pcm_substream *substream,
			    struct snd_soc_dai *dai)
{
	struct nx_spdif *nx = snd_soc_dai_get_drvdata(dai);

	/* Balance the clk_prepare_enable() from hw_params(). */
	clk_disable_unprepare(nx->clk);
	return 0;
}

static int nx_spdif_dai_probe(struct snd_soc_dai *dai)
{
	struct nx_spdif *nx = snd_soc_dai_get_drvdata(dai);

	snd_soc_dai_init_dma_data(dai, &nx->play_dma, NULL);
	return 0;
}

static const struct snd_soc_dai_ops nx_spdif_dai_ops = {
	.probe		= nx_spdif_dai_probe,
	.hw_params	= nx_spdif_hw_params,
	.hw_free	= nx_spdif_hw_free,
	.trigger	= nx_spdif_trigger,
};

static struct snd_soc_dai_driver nx_spdif_dai = {
	.name = "nexell-spdif-tx",
	.playback = {
		.channels_min = 2,
		.channels_max = 2,
		.formats = SND_SOC_SPDIF_TX_FORMATS,
		.rates = SND_SOC_SPDIF_RATES,
	},
	.ops = &nx_spdif_dai_ops,
};

static const struct snd_soc_component_driver nx_spdif_component = {
	.name = "nexell-spdif-tx",
	.legacy_dai_naming = 1,
};

static int nx_spdif_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct nx_spdif *nx;
	struct resource *res;
	int ret;

	nx = devm_kzalloc(dev, sizeof(*nx), GFP_KERNEL);
	if (!nx)
		return -ENOMEM;
	nx->dev = dev;

	nx->base = devm_platform_get_and_ioremap_resource(pdev, 0, &res);
	if (IS_ERR(nx->base))
		return PTR_ERR(nx->base);

	nx->clk = devm_clk_get(dev, NULL);
	if (IS_ERR(nx->clk))
		return dev_err_probe(dev, PTR_ERR(nx->clk), "no clock\n");

	nx->rst = devm_reset_control_get_optional(dev, "spdiftx-reset");
	if (IS_ERR(nx->rst))
		return PTR_ERR(nx->rst);

	nx->play_dma.addr = res->start + SPDIF_DAT_OFFSET;
	nx->play_dma.addr_width = DMA_SLAVE_BUSWIDTH_2_BYTES;
	nx->play_dma.maxburst = SPDIF_MAX_BURST / 2;

	dev_set_drvdata(dev, nx);

	ret = devm_snd_soc_register_component(dev, &nx_spdif_component,
					      &nx_spdif_dai, 1);
	if (ret)
		return ret;

	return devm_snd_dmaengine_pcm_register(dev, NULL, 0);
}

static const struct of_device_id nx_spdif_match[] = {
	{ .compatible = "nexell,nexell-spdif-tx" },
	{ }
};
MODULE_DEVICE_TABLE(of, nx_spdif_match);

static struct platform_driver nx_spdif_driver = {
	.probe = nx_spdif_probe,
	.driver = {
		.name = "nexell-spdif-tx",
		.of_match_table = nx_spdif_match,
	},
};
module_platform_driver(nx_spdif_driver);

MODULE_DESCRIPTION("Nexell S5P6818 S/PDIF transmitter (HDMI audio source)");
MODULE_LICENSE("GPL");
