#!/bin/sh
# board-bootstrap.sh —— 把板子从"只能串口"恢复到"能 ssh、能 apt"
#
# 板上用法（root，串口控制台）：
#   /usr/local/bin/x6818-diag fetch 192.168.31.146 8000 /board-bootstrap.sh /tmp/b.sh
#   sh /tmp/b.sh
#
# 前提：服务器 192.168.31.146:8000 在跑 HTTP 服务（根 = ~/2026workspace/out），
#       板上已有 x6818-diag（没有就只能先用优盘/YMODEM 送一个进去）。
#
# 幂等：重复跑没关系。
set -eu

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SRV=192.168.31.146
PORT=8000
GW=192.168.31.1

say() { echo "==> $*"; }
die() { echo "!! $*" >&2; exit 1; }

[ -x /usr/local/bin/x6818-diag ] ||
	die "板上没有 /usr/local/bin/x6818-diag：先用优盘或 u-boot loady 把它送进去"

# ---------- 1. 网络：IP + 默认路由 ----------
# netup 只配 IP/掩码；没有默认路由就只能访问 192.168.31.0/24，apt/公网 DNS 全废。
/usr/local/bin/x6818-diag netup 192.168.31.150/24 >/dev/null 2>&1 || true
/usr/local/bin/x6818-diag route "$GW" >/dev/null 2>&1 || true
say "网络: $(ip -br a show eth0 2>/dev/null || true) $(ip r 2>/dev/null | head -1 || true)"

# ---------- 2. DNS ----------
# ubuntu-base 的 resolv.conf 指向 127.0.0.53（systemd-resolved 的桩），板上没有它。
if ! grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null ||
   grep -q '^nameserver 127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
	printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf
fi

# ---------- 3. 关 IPv6 ----------
# DNS 会先返回 AAAA，本板没有 v6 出口 → apt 会卡在连不上的 IPv6 上。
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true
printf 'Acquire::ForceIPv4 "true";\nAcquire::Languages "none";\n' > /etc/apt/apt.conf.d/99force-ipv4

# ---------- 4. 关 THP ----------
# 开 THP 时 apt "Reading package lists" 会把内核搞 panic（2026-11-17 复现两次）。
if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
	echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
fi

# ---------- 5. /root 属主 ----------
# 镜像用 tar --no-same-owner 解包，/root 会变成 1000:1000，
# dropbear/sshd 的 StrictModes 会直接拒绝 root 公钥登录。
chown root:root /root 2>/dev/null || true

# ---------- 6. 换 init v3 ----------
# v3 修了"串口里按 Ctrl-C 杀 PID 1 → Kernel panic: Attempted to kill init"，
# 并把 DNS / IPv6 / THP / 路由 / sshd 都做成开机自启。
/usr/local/bin/x6818-diag fetch "$SRV" "$PORT" /init-v3 /usr/sbin/init.new
chmod 755 /usr/sbin/init.new
[ -f /usr/sbin/init ] && cp -a /usr/sbin/init /usr/sbin/init.bak 2>/dev/null || true
mv /usr/sbin/init.new /usr/sbin/init
say "init v3 已就位"

# ---------- 7. SSH：没装就装离线 dropbear ----------
mkdir -p /etc/dropbear /root/.ssh
chmod 700 /root/.ssh
if [ ! -x /usr/sbin/dropbear ] && [ ! -x /usr/sbin/sshd ]; then
	say "装离线 dropbear（不依赖 apt）"
	/usr/local/bin/x6818-diag fetch "$SRV" "$PORT" /ssh-bundle.tar.gz /tmp/ssh-bundle.tar.gz
	mkdir -p /tmp/ssh-bundle
	tar xzf /tmp/ssh-bundle.tar.gz -C /tmp/ssh-bundle
	sh /tmp/ssh-bundle/install.sh
fi

if [ -x /usr/sbin/dropbear ]; then
	pgrep -x dropbear >/dev/null 2>&1 || /usr/sbin/dropbear -R -p 22
elif [ -x /usr/sbin/sshd ]; then
	mkdir -p /run/sshd
	pgrep -x sshd >/dev/null 2>&1 || /usr/sbin/sshd
fi
sleep 1

if grep -qi ':0016' /proc/net/tcp; then
	echo "==> SSH OK：PC 上 ssh root@192.168.31.150"
else
	die "22 没起来"
fi
