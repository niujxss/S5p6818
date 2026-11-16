/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Minimal SoC-only replacement for the vendor s5pxx18_drm_dp.h glue header.
 *
 * The vendor header pulls the full 4.14 KMS glue (drm_crtc/plane/encoder/
 * connector inside nx_drm_device). The SoC HDMI code (s5pxx18_dp_hdmi.c) only
 * ever touches display->res and display->ctrl.dpc, so this provides just those
 * structures - DRM-free - letting the SoC layer build without the KMS glue.
 * The modern KMS driver (nx_display_drv.c) constructs an nx_drm_device with
 * these fields and drives the SoC HDMI API directly.
 */
#ifndef _S5PXX18_SOC_DP_GLUE_H_
#define _S5PXX18_SOC_DP_GLUE_H_

#include <linux/reset.h>
#include <video/videomode.h>

#include "s5pxx18_dp_dev.h"

#define MAX_RES_NUM		8

struct nx_drm_res {
	void *base;
	struct reset_control *reset;
	void *dev_bases[MAX_RES_NUM];
	int   num_devs;
	void *dev_clk_bases[MAX_RES_NUM];
	int   dev_clk_ids[MAX_RES_NUM];
	int   num_dev_clks;
	struct reset_control *dev_resets[MAX_RES_NUM];
	int   num_dev_resets;
	u32   tieoffs[MAX_RES_NUM][2];
	int   num_tieoffs;
};

struct nx_drm_ctrl {
	struct dp_control_dev dpc;
};

struct nx_drm_device {
	struct device *dev;
	struct nx_drm_ctrl ctrl;
	struct nx_drm_res res;
	bool suspended;
};

#endif /* _S5PXX18_SOC_DP_GLUE_H_ */
