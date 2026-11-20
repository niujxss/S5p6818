#!/bin/bash
# ============================================================
# build-2604.sh  在 x86 Ubuntu 上构建 Ubuntu 26.04 LTS (resolute) arm64 rootfs
#
#   用法:  sudo bash build-2604.sh [--clean] [--publish]
#     --clean    删除旧的 r2604/ 重新解包
#     --publish  发布产物并起 HTTP :8000（默认发到 <发布用户家目录>/2026workspace/out）
#
#   脚本不写死任何绝对路径，可以放在任意目录运行；以下环境变量都可覆盖：
#     WORKDIR=...   构建工作目录（默认 = 脚本所在目录）
#     PUBDIR=...    发布目录（默认 = <OWNER 家目录>/2026workspace/out）
#     HOST_IP=...   打印 URL 用的 IP（默认取 hostname -I 的第一个）
#     ROOTDEV=...   目标 fstab 设备（默认 /dev/mmcblk2p2）
#     MIRROR=...    apt 镜像（默认清华 ubuntu-ports）
#     OWNER=...     产物属主（默认 sudo 的发起用户）
#
#   产物:  <WORKDIR>/r2604.tar.gz (+ .sha256)，日志 <WORKDIR>/build-2604.log
#   依赖:  qemu-aarch64-static >= 6（4.2 会段错误，见计划书 P0.5）
#   说明:  纯用户态 rootfs，不含内核/引导器/init；内核由板子上的 /boot 提供
# ============================================================
set -euo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$BASE}"
R="$WORKDIR/r2604"
TARBALL="$WORKDIR/ubuntu-base-26.04.1-base-arm64.tar.gz"
SUMS="$WORKDIR/SHA256SUMS"
OUT="$WORKDIR/r2604.tar.gz"
LOG="$WORKDIR/build-2604.log"
OWNER="${OWNER:-${SUDO_USER:-${USER:-$(id -un)}}}"
HOMEDIR="$(getent passwd "$OWNER" | cut -d: -f6)"
ROOTDEV="${ROOTDEV:-/dev/mmcblk2p2}"
MIRROR="${MIRROR:-http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/}"
HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
[ -n "$HOST_IP" ] || HOST_IP=127.0.0.1
PUBDIR="${PUBDIR:-${HOMEDIR:-$HOME}/2026workspace/out}"
MOUNTS=()
CLEAN=0
PUBLISH=0

for a in "$@"; do
  case "$a" in
    --clean)   CLEAN=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $a"; exit 2 ;;
  esac
done

exec > >(tee -a "$LOG") 2>&1

step() { printf '\n\033[1;36m===== %s =====\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*"; exit 1; }

cleanup() {
  set +e
  local i m
  # 反序卸载：dev/pts 在 dev 下面，先卸子再卸父
  for (( i=${#MOUNTS[@]}-1; i>=0; i-- )); do
    m="${MOUNTS[$i]}"
    [ -n "$m" ] || continue
    if mountpoint -q "$R/$m"; then
      umount "$R/$m" 2>/dev/null || umount -l "$R/$m" 2>/dev/null || true
    fi
  done
  # 兜底：清理不在数组里的残留
  for m in dev/pts sys proc dev; do
    if mountpoint -q "$R/$m"; then
      umount "$R/$m" 2>/dev/null || umount -l "$R/$m" 2>/dev/null || true
    fi
  done
  set -e
}
trap cleanup EXIT

crun() {
  chroot "$R" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root TERM=dumb LC_ALL=C DEBIAN_FRONTEND=noninteractive "$@"
}

step "0. 环境检查"
[ "$(id -u)" -eq 0 ] || die "请用 sudo 运行：sudo bash $0"
[ "$(uname -m)" = "x86_64" ] || warn "主机是 $(uname -m)，不是 x86_64（qemu 方案可能不适用）"
QVER="$(/usr/bin/qemu-aarch64-static --version 2>/dev/null | head -1 || true)"
echo "  主机: $(uname -m) / $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "  qemu: ${QVER:-未安装}"
case "$QVER" in
  *"version 4."*|*"version 5."*|"")
    die "qemu 太旧（需要 >= 6，推荐 8.2）。按计划书 P0.5 替换 /usr/bin/qemu-aarch64-static 后重跑" ;;
esac
echo "  目标 fstab: $ROOTDEV（板子装到 p2 时用 p2，装到 p7 时用 p7）"
echo "  镜像源: $MIRROR"
echo "  工作目录: $WORKDIR"
if [ -d "$BASE/.git" ] && [ "$WORKDIR" = "$BASE" ]; then
  warn "脚本在 git 仓库里，构建产物会落进仓库；不想提交的话：sudo WORKDIR=\$HOME/build-2604 bash $0"
fi
AVAIL_KB="$(df -Pk "$WORKDIR" | awk 'NR==2{print $4}')"
echo "  可用空间: $(( ${AVAIL_KB:-0} / 1024 )) MB"
if [ "${AVAIL_KB:-0}" -lt 2097152 ]; then
  die "磁盘空间不足：至少需要 2 GB 空闲（当前 $((${AVAIL_KB:-0}/1024)) MB）"
fi

step "1. 准备 base tarball"
BN="$(basename "$TARBALL")"
# 允许把已经下好的 tar / SHA256SUMS 放在脚本旁边（换目录时不用重下）
if [ ! -f "$TARBALL" ] && [ "$BASE" != "$WORKDIR" ] && [ -f "$BASE/$BN" ]; then
  cp -f "$BASE/$BN" "$TARBALL"
fi
if [ ! -f "$SUMS" ] && [ "$BASE" != "$WORKDIR" ] && [ -f "$BASE/SHA256SUMS" ]; then
  cp -f "$BASE/SHA256SUMS" "$SUMS"
fi
if [ ! -f "$TARBALL" ]; then
  echo "  下载 $BN ..."
  wget -q -O "$TARBALL" \
    "http://cdimage.ubuntu.com/ubuntu-base/releases/26.04.1/release/$BN"
fi
ls -lh "$TARBALL"
if [ -f "$SUMS" ]; then
  # 注意不要写成 awk | grep -q：pipefail 下 grep 提前退出会让 awk 收 SIGPIPE，
  # 管线返回 141，校验会被静默跳过（踩过）
  SUMS_LINE="$(awk -v f="$BN" '{n=$2; sub(/^\*/,"",n); if (n==f) print}' "$SUMS")"
  if [ -n "$SUMS_LINE" ]; then
    ( cd "$WORKDIR" && printf '%s\n' "$SUMS_LINE" | sha256sum -c - ) || die "sha256 校验失败"
  else
    warn "SHA256SUMS 里没有 $BN，跳过校验"
  fi
else
  warn "没有 SHA256SUMS，跳过校验"
fi

step "2. 解包到 $R"
cleanup
# 安全闸门：$R/dev 是宿主机 /dev 的 bind，残留时 rm -rf 会删到宿主机设备节点
for d in dev proc sys dev/pts; do
  if mountpoint -q "$R/$d"; then
    die "$R/$d 仍在挂载，请先手动 sudo umount $R/$d 再重跑"
  fi
done
if [ "$CLEAN" = 1 ] || [ ! -x "$R/bin/sh" ]; then
  rm -rf "$R"; mkdir -p "$R"
  tar --numeric-owner -xpf "$TARBALL" -C "$R"
  echo "  解包完成"
else
  echo "  已存在 /bin/sh，跳过解包（要重来加 --clean）"
fi
grep -q 'VERSION_ID="26.04"' "$R/etc/os-release" || die "$R 不是 26.04"
echo "  当前大小: $(du -shx "$R" 2>/dev/null | cut -f1 || true)"

step "3. 挂载 /dev /proc /sys /dev/pts"
for d in dev proc sys dev/pts; do
  mkdir -p "$R/$d"
  if mountpoint -q "$R/$d"; then
    echo "  $d 已挂载（沿用，退出时会卸载）"
    MOUNTS+=("$d")
  else
    mount --bind "/$d" "$R/$d"
    MOUNTS+=("$d")
    echo "  挂载 $d"
  fi
done

step "4. DNS / policy-rc.d / apt 源"
# 不能直接拷宿主机 resolv.conf：20.04 桌面通常是 127.0.0.53（systemd-resolved 桩），
# chroot 里没有 resolved，会解析失败
rm -f "$R/etc/resolv.conf"
printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > "$R/etc/resolv.conf"

printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"
chmod 755 "$R/usr/sbin/policy-rc.d"

mkdir -p "$R/etc/apt/sources.list.d" "$R/etc/apt/apt.conf.d"
: > "$R/etc/apt/sources.list"
cat > "$R/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: resolute resolute-updates resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
cat > "$R/etc/apt/apt.conf.d/99x6818" <<'EOF'
Acquire::ForceIPv4 "true";
Acquire::Languages "none";
Acquire::Check-Valid-Until "false";
Acquire::Retries "3";
EOF
[ -f "$R/usr/share/keyrings/ubuntu-archive-keyring.gpg" ] || warn "rootfs 里没有 ubuntu-archive-keyring.gpg，apt 可能报 NO_PUBKEY"

step "5. apt-get update"
if ! crun apt-get update; then
  die "apt-get update 失败：若提示缺 sqv，按计划书 P0.5 手动装 arm64 的 sqv deb 后重跑"
fi

step "6. 装包（qemu 下较慢，5-15 分钟，耐心等）"
mkdir -p "$R/etc/dpkg/dpkg.cfg.d"
cat > "$R/etc/dpkg/dpkg.cfg.d/nodoc" <<'EOF'
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/locale/*
EOF
crun apt-get install -y --no-install-recommends \
  dropbear iproute2 ethtool kmod procps less nano util-linux util-linux-extra \
  e2fsprogs fdisk rsync netbase iputils-ping logrotate tzdata chrony \
  ca-certificates wget u-boot-tools
crun apt-get clean
rm -rf "$R"/var/lib/apt/lists/*
SZ_MB="$(du -smx "$R" 2>/dev/null | cut -f1)" || true
echo "  装完大小: ${SZ_MB} MB"
[ "${SZ_MB:-0}" -le 600 ] || warn "rootfs 已超过 600MB，p2（690MB）可能装不下，建议清 /usr/share/{doc,man,locale}"

step "7. 定制（init / 网络 / ssh / fstab / fw_env）"
# systemd 259 会通过 tmpfiles 往 /etc/profile.d 链 OSC 3008 shell 集成脚本，
# 串口终端不认这个转义序列会刷屏；我们不跑 systemd，直接删掉并 mask
rm -f "$R/etc/profile.d/80-systemd-osc-context.sh" "$R/etc/profile.d/70-systemd-shell-extra.sh"
mkdir -p "$R/etc/tmpfiles.d"
ln -sf /dev/null "$R/etc/tmpfiles.d/20-systemd-osc-context.conf"
ln -sf /dev/null "$R/etc/tmpfiles.d/20-systemd-shell-extra.conf"
cat > "$R/usr/sbin/init" <<'INIT'
#!/bin/sh
# x6818 init v4  (Ubuntu 26.04)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /run /var/log /var/run 2>/dev/null || true
mount -t proc  none /proc
mount -t sysfs none /sys
mkdir -p /dev/pts; mount -t devpts none /dev/pts
mount -t tmpfs none /tmp
hostname x6818 2>/dev/null
chown root:root /root 2>/dev/null || true
if ! grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null ||
   grep -q '^nameserver 127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
	printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf
fi
if [ -e /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
	echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
	echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true
fi
X6818_IP=${X6818_IP:-192.168.31.150/24}
X6818_GW=${X6818_GW:-192.168.31.1}
if [ -x /usr/local/bin/x6818-diag ]; then
	/usr/local/bin/x6818-diag netup "$X6818_IP" >/dev/null 2>&1 || true
	/usr/local/bin/x6818-diag route "$X6818_GW" >/dev/null 2>&1 || true
fi
# 时间：这块板没有 RTC 电池，冷启动 RTC 是垃圾值（实测 2072 年）。
# 网络起来后用 NTP 拉一次，再把结果写回 RTC（有电池的热启动就能保持）。
if [ "$(date +%Y)" -gt 2030 ] || [ "$(date +%Y)" -lt 2020 ]; then
	[ -x /usr/sbin/chronyd ] && timeout 30 /usr/sbin/chronyd -q 'server ntp.aliyun.com iburst' >/dev/null 2>&1 || true
	[ -x /usr/sbin/chronyd ] && timeout 30 /usr/sbin/chronyd -q 'server cn.pool.ntp.org iburst' >/dev/null 2>&1 || true
fi
[ -x /usr/sbin/hwclock ] && /usr/sbin/hwclock -w 2>/dev/null || true
if [ -x /usr/sbin/dropbear ]; then
	mkdir -p /etc/dropbear
	pgrep -x dropbear >/dev/null 2>&1 || /usr/sbin/dropbear -R -p 22 2>/dev/null || true
fi
if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
	echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
fi
echo 10 > /proc/sys/kernel/panic 2>/dev/null || true
swapon -a 2>/dev/null || true
echo "--- x6818: Ubuntu 26.04 up, serial console ttySAC0 ---"
echo "    ip: ${X6818_IP}  gw: ${X6818_GW}"
while :; do
	/sbin/agetty -L -a root 115200 ttySAC0 vt100
	sleep 1
done
INIT
chmod 755 "$R/usr/sbin/init"
# 26.04 默认 usrmerge，/sbin 是软链；万一不是，补一个
if [ ! -e "$R/sbin/init" ]; then ln -sf /usr/sbin/init "$R/sbin/init"; fi

ln -sf /usr/share/zoneinfo/Asia/Shanghai "$R/etc/localtime"
echo x6818 > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\tx6818\n' > "$R/etc/hosts"
mkdir -p "$R/etc/dropbear" "$R/root/.ssh" "$R/boot/dtb/nexell" \
         "$R/usr/local/bin" "$R/srv" "$R/mnt"
chmod 700 "$R/root/.ssh"
echo "$ROOTDEV / ext4 defaults,noatime,errors=remount-ro 0 1" > "$R/etc/fstab"
printf '/dev/mmcblk2 0x80000 0x1000\n' > "$R/etc/fw_env.config"
echo "  fstab: $(cat "$R/etc/fstab")"

step "8. chroot 冒烟测试"
crun /bin/sh -c '. /etc/os-release; echo "  $PRETTY_NAME"; uname -m'
crun /usr/sbin/dropbear -V 2>&1 | head -1 || true
crun /usr/bin/apt-get -s install --reinstall coreutils >/dev/null 2>&1 && echo "  apt 模拟安装 OK" || warn "apt 模拟安装失败"
crun /bin/ls -l /sbin/init 2>/dev/null | sed 's/^/  /' || true

step "9. 卸挂载并打包"
cleanup
trap - EXIT
for d in dev proc sys dev/pts; do
  mountpoint -q "$R/$d" && warn "注意：$R/$d 仍处于挂载状态（打包会按 --one-file-system 跳过它）"
done
cd "$R"
tar -cpf - --numeric-owner --one-file-system \
  --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./mnt . \
  | gzip -1 > "$OUT"
cd "$WORKDIR"
ls -lh "$OUT"
( cd "$WORKDIR" && sha256sum r2604.tar.gz > r2604.tar.gz.sha256 )
cat "$OUT.sha256"
chown "$OWNER:$OWNER" "$OUT" "$OUT.sha256" "$LOG" 2>/dev/null || true

if [ "$PUBLISH" = 1 ]; then
  step "10. 发布到 HTTP"
  [ -n "$PUBDIR" ] || die "PUBDIR 为空（用 PUBDIR=... 指定发布目录）"
  mkdir -p "$PUBDIR"
  cp -f "$OUT" "$OUT.sha256" "$PUBDIR/"
  chown "$OWNER:$OWNER" "$PUBDIR/r2604.tar.gz" "$PUBDIR/r2604.tar.gz.sha256" 2>/dev/null || true
  if ! (ss -tln 2>/dev/null || netstat -tln) | grep -q ':8000'; then
    setsid su "$OWNER" -c "cd '$PUBDIR' && exec python3 -m http.server 8000" \
      >/dev/null 2>&1 </dev/null &
    sleep 1
  fi
  echo "  发布目录: $PUBDIR"
  echo "  URL: http://$HOST_IP:8000/r2604.tar.gz"
fi

step "完成"
echo "  产物: $OUT"
echo "  sha : $(cut -d' ' -f1 "$OUT.sha256")"
echo
echo "板子侧下一步（在现 22.04 上跑）："
echo "  fw_printenv > /root/env-2204.txt"
echo "  mkfs.ext4 -m 1 -O ^64bit,^metadata_csum -L ub2604 /dev/mmcblk2p2"
echo "  mkdir -p /mnt/p2 && mount /dev/mmcblk2p2 /mnt/p2"
echo "  wget -qO- http://$HOST_IP:8000/r2604.tar.gz | tar -C /mnt/p2 -xzpf - --numeric-owner"
echo "  然后按计划书 P6：补 /boot/Image、dtb、diag、公钥 -> env 0:2 重启验证"
