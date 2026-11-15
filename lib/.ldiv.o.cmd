cmd_lib/ldiv.o := /home/honey/2026workspace/uboot/S5p6818/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-gcc -Wp,-MD,lib/.ldiv.o.d  -nostdinc -isystem /home/honey/2026workspace/uboot/S5p6818/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/../lib/gcc/arm-eabi/4.8/include -Iinclude  -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/include -D__KERNEL__ -DCONFIG_SYS_TEXT_BASE=0x43C00000 -Wall -Wstrict-prototypes -Wno-format-security -fno-builtin -ffreestanding -Os -fno-stack-protector -g -fstack-usage -Wno-format-nonliteral -DCONFIG_ARM -D__ARM__ -marm -mno-thumb-interwork -mabi=aapcs-linux -mword-relocations -ffunction-sections -fdata-sections -fno-common -ffixed-r9 -msoft-float -mno-unaligned-access -mcpu=cortex-a9 -fno-short-enums -fstrict-aliasing -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/s5p6818/prototype/module -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/s5p6818/prototype/base -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/include/asm/arch-s5p6818 -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/common -I/home/honey/2026workspace/uboot/S5p6818/arch/arm/cpu/slsiap/devices -I/home/honey/2026workspace/uboot/S5p6818/board/s5p6818/common -D__LINUX__ -DNX_RELEASE -Wno-unused-but-set-variable -I/home/honey/2026workspace/uboot/S5p6818/board/s5p6818/x6818/include -pipe    -D"KBUILD_STR(s)=\#s" -D"KBUILD_BASENAME=KBUILD_STR(ldiv)"  -D"KBUILD_MODNAME=KBUILD_STR(ldiv)" -c -o lib/ldiv.o lib/ldiv.c

source_lib/ldiv.o := lib/ldiv.c

deps_lib/ldiv.o := \

lib/ldiv.o: $(deps_lib/ldiv.o)

$(deps_lib/ldiv.o):
