cmd_lib/crc16.o := /home/honey/work/arm/s5p6818sdk_lzy1/Linux/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-gcc -Wp,-MD,lib/.crc16.o.d  -nostdinc -isystem /home/honey/work/arm/s5p6818sdk_lzy1/Linux/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/../lib/gcc/arm-eabi/4.8/include -Iinclude  -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/include -D__KERNEL__ -DCONFIG_SYS_TEXT_BASE=0x43C00000 -Wall -Wstrict-prototypes -Wno-format-security -fno-builtin -ffreestanding -Os -fno-stack-protector -g -fstack-usage -Wno-format-nonliteral -DCONFIG_ARM -D__ARM__ -marm -mno-thumb-interwork -mabi=aapcs-linux -mword-relocations -ffunction-sections -fdata-sections -fno-common -ffixed-r9 -msoft-float -mno-unaligned-access -mcpu=cortex-a9 -fno-short-enums -fstrict-aliasing -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/s5p6818/prototype/module -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/s5p6818/prototype/base -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/include/asm/arch-s5p6818 -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/common -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/cpu/slsiap/devices -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/board/s5p6818/common -D__LINUX__ -DNX_RELEASE -Wno-unused-but-set-variable -I/home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/board/s5p6818/x6818/include -pipe    -D"KBUILD_STR(s)=\#s" -D"KBUILD_BASENAME=KBUILD_STR(crc16)"  -D"KBUILD_MODNAME=KBUILD_STR(crc16)" -c -o lib/crc16.o lib/crc16.c

source_lib/crc16.o := lib/crc16.c

deps_lib/crc16.o := \
  include/crc.h \
  include/linux/types.h \
    $(wildcard include/config/uid16.h) \
  include/linux/posix_types.h \
  include/linux/stddef.h \
  /home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/include/asm/posix_types.h \
  /home/honey/work/arm/s5p6818sdk_lzy1/Linux/src/uboot/arch/arm/include/asm/types.h \
    $(wildcard include/config/arm64.h) \
  /home/honey/work/arm/s5p6818sdk_lzy1/Linux/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/lib/gcc/arm-eabi/4.8/include/stdbool.h \

lib/crc16.o: $(deps_lib/crc16.o)

$(deps_lib/crc16.o):
