#!/bin/bash
# 编译 X6818 主线内核的封装。路径相对脚本定位，可整体移动。
#
#   ./build-kernel.sh                    # Image dtbs
#   ./build-kernel.sh x6818_defconfig    # 重置配置
#   ./build-kernel.sh modules            # 编模块
#   KERNEL_DIR=/path/to/linux ./build-kernel.sh
#
# 内核树默认取同级的 S5p6818-kernel 目录。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)

if [ -z "${KERNEL_DIR:-}" ]; then
	for c in "$REPO/../S5p6818-kernel" "$REPO/../kernel" "$REPO/../linux"; do
		[ -f "$c/Makefile" ] && KERNEL_DIR=$(cd "$c" && pwd) && break
	done
fi
[ -n "${KERNEL_DIR:-}" ] && [ -f "$KERNEL_DIR/Makefile" ] || {
	echo "!! 找不到内核树，请设置 KERNEL_DIR=/path/to/linux-7.2.15"; exit 1; }

export ARCH=${ARCH:-arm64}
export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
JOBS=${JOBS:-$(nproc)}

TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(Image dtbs)

echo "[build] 内核树: $KERNEL_DIR"
echo "[build] ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE -j$JOBS ${TARGETS[*]}"
cd "$KERNEL_DIR"
make -j"$JOBS" "${TARGETS[@]}"
