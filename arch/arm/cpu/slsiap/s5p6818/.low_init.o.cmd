cmd_arch/arm/cpu/slsiap/s5p6818/low_init.o := /home/honey/work/arm/s5p6818sdk_lzy1/Linux/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-gcc -Wp,-MD,arch/arm/cpu/slsiap/s5p6818/.low_init.o.d  -nostdinc -isystem /home/honey/work/arm/s5p6818sdk_lzy1/Linux/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/../lib/gcc/arm-eabi/4.8/include -Iinclude  -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/include -D__KERNEL__ -DCONFIG_SYS_TEXT_BASE=0x43C00000  -D__ASSEMBLY__ -g      -DCONFIG_ARM -D__ARM__ -marm -mno-thumb-interwork  -mabi=aapcs-linux  -mword-relocations  -ffunction-sections -fdata-sections -fno-common -ffixed-r9  -msoft-float  -mno-unaligned-access -mcpu=cortex-a9 -fno-short-enums -fstrict-aliasing  -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/s5p6818/prototype/module -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/s5p6818/prototype/base -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/include/asm/arch-s5p6818 -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/common -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/devices -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/board/s5p6818/common -D__LINUX__ -DNX_RELEASE -Wno-unused-but-set-variable -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/board/s5p6818/x6818/include -pipe     -c -o arch/arm/cpu/slsiap/s5p6818/low_init.o arch/arm/cpu/slsiap/s5p6818/low_init.S

source_arch/arm/cpu/slsiap/s5p6818/low_init.o := arch/arm/cpu/slsiap/s5p6818/low_init.S

deps_arch/arm/cpu/slsiap/s5p6818/low_init.o := \
    $(wildcard include/config/skip/lowlevel/init.h) \

arch/arm/cpu/slsiap/s5p6818/low_init.o: $(deps_arch/arm/cpu/slsiap/s5p6818/low_init.o)

$(deps_arch/arm/cpu/slsiap/s5p6818/low_init.o):
