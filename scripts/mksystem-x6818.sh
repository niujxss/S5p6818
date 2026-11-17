#!/bin/bash
# 组装 eMMC 的 system 分区（p2）用的 ext4 镜像。
# 所有路径都相对本脚本定位，整个目录搬到任何位置都能直接跑。不需要 root。
#
#   ./mksystem-x6818.sh                  # 用仓库里的 rootfs/ 树打包
#   ./mksystem-x6818.sh --from-base      # 丢弃 rootfs/，从 base/ 重新解包并组装
#   SIZE_MB=512 ./mksystem-x6818.sh      # 指定镜像大小（默认 256）
#   KERNEL=/path/to/linux ./mksystem-x6818.sh   # 指定内核树，取其 Image/dtb
#   OUT=/path/x.img ./mksystem-x6818.sh  # 指定输出路径
#
# 说明：没有内核树时，会沿用 rootfs/boot/ 里已有的 Image 和 dtb。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)

ROOTFS=${ROOTFS:-$REPO/rootfs}
OUT=${OUT:-$REPO/out/system-p2.img}
SIZE_MB=${SIZE_MB:-256}
DTS_NAME=${DTS_NAME:-s5p6818-x6818.dtb}
FROM_BASE=0
[ "${1:-}" = "--from-base" ] && FROM_BASE=1

say() { printf '  %s\n' "$*"; }

# ---------- 1. 找基础 rootfs ----------
if [ "$FROM_BASE" = 1 ] || [ ! -d "$ROOTFS/etc" ]; then
	echo "==> 从 base/ 解包 rootfs"
	BASE=$(ls -1 "$REPO"/base/ubuntu-base-*-arm64.tar.gz 2>/dev/null | head -1 || true)
	[ -n "${BASE:-}" ] || { echo "!! base/ 下找不到 ubuntu-base-*-arm64.tar.gz"; exit 1; }
	rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
	tar -xzf "$BASE" -C "$ROOTFS" --no-same-owner
	say "解包 $(basename "$BASE") -> rootfs/"
fi

# ---------- 2. 注入配置（幂等，可重复执行） ----------
echo "==> 注入配置"
printf '/dev/mmcblk2p2\t/\text4\tdefaults,noatime,errors=remount-ro\t0 1\n' > "$ROOTFS/etc/fstab"
echo x6818 > "$ROOTFS/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tx6818\n' > "$ROOTFS/etc/hosts"
[ -f /etc/resolv.conf ] && cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# root 口令：只在当前为空/被锁时设置，避免每次改动 /etc/shadow
if grep -q '^root:[!*]\|^root::' "$ROOTFS/etc/shadow"; then
	HASH=$(openssl passwd -6 root)
	python3 - "$ROOTFS/etc/shadow" "$HASH" <<'PY'
import sys
path, h = sys.argv[1], sys.argv[2]
out = []
for line in open(path).read().splitlines():
    f = line.split(':')
    if f[0] == 'root':
        f[1] = h
        line = ':'.join(f)
    out.append(line)
open(path, 'w').write('\n'.join(out) + '\n')
PY
	say "已设置 root 口令（root）"
fi

cat > "$ROOTFS/etc/apt/sources.list" <<'APT'
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse
APT

# 最小 init：ubuntu-base 的 tarball 里没有 systemd/init
cat > "$ROOTFS/usr/sbin/init" <<'INIT'
#!/bin/sh
# 最小 bring-up init（ubuntu-base 不含 systemd）
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount -t proc  none /proc
mount -t sysfs none /sys
mkdir -p /dev/pts; mount -t devpts none /dev/pts
mount -t tmpfs none /tmp
hostname x6818 2>/dev/null
echo "--- x6818: mainline Linux up, serial console ttySAC0 ---"
exec /usr/sbin/agetty -L -a root 115200 ttySAC0 vt100
INIT
chmod 755 "$ROOTFS/usr/sbin/init"
printf 'ttySAC0\ntty1\nconsole\n' > "$ROOTFS/etc/securetty"

# ---------- 3. 放入内核与设备树 ----------
KERNEL=${KERNEL:-}
if [ -z "$KERNEL" ]; then
	for c in "$REPO/../S5p6818-kernel" "$REPO/../kernel" "$REPO/../linux"; do
		[ -f "$c/arch/arm64/boot/Image" ] && KERNEL=$(cd "$c" && pwd) && break
	done
fi

mkdir -p "$ROOTFS/boot/dtb/nexell"
if [ -n "$KERNEL" ] && [ -f "$KERNEL/arch/arm64/boot/Image" ]; then
	echo "==> 放入内核（KERNEL=$KERNEL）"
	cp "$KERNEL/arch/arm64/boot/Image" "$ROOTFS/boot/Image"
	DTSRC="$KERNEL/arch/arm64/boot/dts/nexell/$DTS_NAME"
	[ -f "$DTSRC" ] && cp "$DTSRC" "$ROOTFS/boot/dtb/nexell/"
	say "Image $(stat -c%s "$ROOTFS/boot/Image") B, dtb $(stat -c%s "$ROOTFS/boot/dtb/nexell/$DTS_NAME" 2>/dev/null || echo 缺) B"
else
	echo "==> 未找到内核树，沿用 rootfs/boot/ 里已有的文件"
	[ -f "$ROOTFS/boot/Image" ] || { echo "!! rootfs/boot/Image 不存在，且没有内核树可用"; exit 1; }
	say "Image $(stat -c%s "$ROOTFS/boot/Image") B"
fi

# ---------- 4. 打包 ext4 ----------
echo "==> 打包 ext4（$SIZE_MB MiB，无需 root）"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
truncate -s $(( SIZE_MB * 1024 * 1024 )) "$OUT"
# u-boot 2016.01 的 ext4 驱动不认 64bit / metadata_csum
mke2fs -q -F -t ext4 -O ^64bit,^metadata_csum,^metadata_csum_seed -I 256 \
       -L system -d "$ROOTFS" "$OUT"
e2fsck -fn "$OUT" >/dev/null 2>&1 && say "fsck 通过"

# ---------- 5. 汇总 ----------
echo
echo "==> 产物: $OUT"
ls -lh "$OUT" | awk '{print "    大小: "$5}'
debugfs -R 'ls -l /boot' "$OUT" 2>/dev/null | sed -n '4,9p'
sha256sum "$OUT"
