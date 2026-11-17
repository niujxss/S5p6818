#!/bin/bash
# 组装可直接 dd 到 SD 卡的完整镜像：MBR + u-boot blob(扇区1) + ext4 分区(扇区2048起)。
# 路径相对脚本定位，可整体移动。不需要 root。
#
#   ./mkimage-x6818.sh                 # 2 GiB 镜像，输出 out/s5p6818-x6818-sd.img
#   SIZE_MB=4096 ./mkimage-x6818.sh    # 指定总大小
#
# 注意：本仓库当前这块板子没有 SD 卡，eMMC 场景请用 mksystem-x6818.sh。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)

ROOTFS=${ROOTFS:-$REPO/rootfs}
BLOB=${BLOB:-$REPO/uboot/boot-nanopi3-1g.img}
OUT=${OUT:-$REPO/out/s5p6818-x6818-sd.img}
SIZE_MB=${SIZE_MB:-2048}
START=2048          # 分区起始扇区（给 512 KiB 的引导区留足空间）

[ -f "$BLOB" ] || { echo "!! 找不到 u-boot blob: $BLOB"; exit 1; }
[ -d "$ROOTFS/etc" ] || { echo "!! 找不到 rootfs 树: $ROOTFS（先跑 mksystem-x6818.sh --from-base）"; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

TOTAL=$(( SIZE_MB * 2048 ))
PARTSZ=$(( TOTAL - START ))

echo "==> 生成分区文件系统（$(( PARTSZ / 2048 )) MiB）"
truncate -s $(( PARTSZ * 512 )) "$WORK/part.img"
mke2fs -q -F -t ext4 -O ^64bit,^metadata_csum,^metadata_csum_seed -I 256 \
       -L rootfs -d "$ROOTFS" "$WORK/part.img"
e2fsck -fn "$WORK/part.img" >/dev/null 2>&1 && echo "    fsck 通过"

echo "==> 组装镜像（$SIZE_MB MiB）"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
truncate -s $(( TOTAL * 512 )) "$OUT"
sfdisk "$OUT" >/dev/null <<EOF
label: dos
start=$START, size=$PARTSZ, type=83, bootable
EOF

# 引导区：blob 写到扇区 1；偏移 0x50 的字节 = 启动介质（0=SD, 2=eMMC）
cp "$BLOB" "$WORK/boot-sd.img"
printf '\0' | dd of="$WORK/boot-sd.img" bs=1 seek=80 conv=notrunc status=none
dd if="$WORK/boot-sd.img" of="$OUT" bs=512 seek=1 conv=notrunc status=none
dd if="$WORK/part.img"      of="$OUT" bs=512 seek=$START conv=notrunc status=none
sync

echo
echo "==> 产物: $OUT"
sfdisk -d "$OUT" | tail -2
ls -lh "$OUT" | awk '{print "    大小: "$5}'
sha256sum "$OUT"
