#!/bin/sh
# S5P6818 U-Boot 自包含构建入口
# 工具链、芯片 prototype 驱动全部在树内，不依赖外部 SDK。
#   ./build.sh              # 首次自动 x6818_config，然后并行编译
#   ./build.sh purge        # 清中间产物（比 distclean 彻底）
#   ./build.sh distclean    # 全清
#   ./build.sh -j8          # 其它参数透传给 make
set -e
SELF=$(cd "$(dirname "$0")" && pwd)
TC="$SELF/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin"
if [ ! -x "$TC/arm-eabi-gcc" ]; then
    echo "错误：树内工具链缺失 $TC/arm-eabi-gcc" >&2
    exit 1
fi
export PATH="$TC:$PATH"
export ARCH=arm
export CROSS_COMPILE="$TC/arm-eabi-"
cd "$SELF"
JOBS=${JOBS:-$(nproc)}
case "$1" in
  purge)
    find . -name '*.o' -delete
    find . -name '*.o.cmd' -delete
    find . -name '*.su' -delete
    find . -name 'asm-offsets.s' -delete
    find . -name '.depend' -delete
    rm -f System.map u-boot u-boot.bin u-boot.srec u-boot.map u-boot.lds ubootpak.bin
    rm -rf include/config include/generated
    rm -f include/autoconf.mk include/autoconf.mk.dep include/config.h include/config.mk
    echo "purge done" ;;
  "")
    [ -f include/config.mk ] || make x6818_config
    exec make -j"$JOBS" ;;
  *)
    exec make "$@" ;;
esac
