#
# (C) Copyright 2009
# jung hyun kim, Nexell Co, <jhkim@nexell.co.kr>
#
# See file CREDITS for list of people who contributed to this
# project.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA 02111-1307 USA
#

# =========================================================================
#	Cross compiler
# =========================================================================
# 树内自带工具链（相对树根，整树可整体搬移）
# 如需用外部工具链，构建时传 CROSS_COMPILE=/path/xx- 覆盖即可
ifeq ($(origin CROSS_COMPILE),undefined)
CROSS_COMPILE := $(srctree)/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-
endif

# prevent GCC-4.6.x (arm-linux-gnueabi-gcc) warning
CC = $(CROSS_COMPILE)gcc
GCCVERSION =  $(shell $(CC) -dumpversion | cut -f2 -d.)

ifneq "$(GCCVERSION)" "3"
PLATFORM_RELFLAGS += -Wno-unused-but-set-variable
endif

# PLATFORM_RELFLAGS += -Wno-strict-aliasing

# =========================================================================
# option "-pie" when ld, -pie must be used with -fPIC gcc option
# set use relocate code
# =========================================================================
BUILD_PIC_OPTION := n
ifeq ($(BUILD_PIC_OPTION),y)
PLATFORM_RELFLAGS += -fPIC
else
#when under u-boot-2013.x
#LDFLAGS_u-boot :=
endif

# =========================================================================
#	Build options
# =========================================================================
BOARD_CFLAGS += -I$(srctree)/board/$(VENDOR)/$(BOARD)/include

PLATFORM_RELFLAGS += $(BOARD_CFLAGS)

# =========================================================================
# common debug macro
# for debug() message
# =========================================================================
# PLATFORM_CPPFLAGS += -DDEBUG


