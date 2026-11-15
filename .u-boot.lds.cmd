cmd_u-boot.lds := /home/honey/2026workspace/uboot/S5p6818/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-gcc -E -Wp,-MD,./.u-boot.lds.d -D__KERNEL__ -DCONFIG_SYS_TEXT_BASE=0x43C00000   -DCONFIG_ARM -D__ARM__ -marm -mno-thumb-interwork  -mabi=aapcs-linux  -mword-relocations  -ffunction-sections -fdata-sections -fno-common -ffixed-r9  -msoft-float  -mno-unaligned-access -mcpu=cortex-a9 -fno-short-enums -fstrict-aliasing  -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/s5p6818/prototype/module -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/s5p6818/prototype/base -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/include/asm/arch-s5p6818 -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/common -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/devices -I/home/honey/2026workspace/uboot/S5p6818/board/s5p6818/common -D__LINUX__ -DNX_RELEASE -Wno-unused-but-set-variable -I/home/honey/2026workspace/uboot/S5p6818/board/s5p6818/x6818/include -pipe -Iinclude  -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/include  -nostdinc -isystem /home/honey/2026workspace/uboot/S5p6818/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/../lib/gcc/arm-eabi/4.8/include -DSOCDIR=arch/arm/cpu/slsiap/s5p6818 -include /home/honey/2026workspace/uboot/S5p6818/include/u-boot/u-boot.lds.h -DCPUDIR=arch/arm/cpu/slsiap  -ansi -D__ASSEMBLY__ -x assembler-with-cpp -P -o u-boot.lds /home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/u-boot.lds

source_u-boot.lds := /home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/u-boot.lds

deps_u-boot.lds := \
  /home/honey/2026workspace/uboot/S5p6818/include/u-boot/u-boot.lds.h \

u-boot.lds: $(deps_u-boot.lds)

$(deps_u-boot.lds):
