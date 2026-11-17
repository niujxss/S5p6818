#!/bin/sh
# board-enable-ssh.sh —— 在板子上跑一次：修 DNS / 默认路由 → 装 openssh-server
#                        → 配 root 公钥免密 → 起 sshd → 把 /usr/sbin/init 换成 v2
#
# 板上用法（root，串口控制台）：
#   /usr/local/bin/x6818-diag fetch 192.168.31.146 8000 /board-enable-ssh.sh /tmp/b.sh
#   sh /tmp/b.sh
#
# 前提：
#   * 服务器 192.168.31.146:8000 正在跑 HTTP 服务（根 = ~/2026workspace/out）
#   * 板子已由 init 配好 192.168.31.150/24（上一条 fetch 能成功就说明通了）
#
# 这个脚本只做三件"可逆"的事：装 openssh-server（apt）、写 root 的 authorized_keys、
# 换 /usr/sbin/init（旧文件备份为 init.bak）。不碰分区、不碰 u-boot。
set -eu

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

SRV=192.168.31.146
HTTP_PORT=8000
GW=192.168.31.1

say() { echo "==> $*"; }
die() { echo "!! $*" >&2; exit 1; }

# ---------- 0. 换上带 route 子命令的 x6818-diag ----------
# 板上现有的那份是旧版（只有 mdio/pmic/netinfo/netup/fetch），没有 route。
say "更新 x6818-diag"
/usr/local/bin/x6818-diag fetch "$SRV" "$HTTP_PORT" /diag/x6818-diag /tmp/x6818-diag.new \
	|| die "取不到新版 x6818-diag：服务器上的 HTTP 服务没起？"
install -m 755 /tmp/x6818-diag.new /usr/local/bin/x6818-diag
rm -f /tmp/x6818-diag.new

# ---------- 1. DNS ----------
# ubuntu-base 的 /etc/resolv.conf 指向 127.0.0.53（systemd-resolved 的桩），
# 板上没有 systemd-resolved，不修就是"域名全解析不了"，apt 必然失败。
if ! grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null ||
   grep -q '^nameserver 127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
	say "修 /etc/resolv.conf（原来是 127.0.0.53 的桩）"
	printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf
fi
say "DNS: $(tr '\n' ' ' < /etc/resolv.conf)"

# ---------- 2. 默认路由 ----------
# netup 只配 IP/掩码；要访问本网段以外（apt 镜像站）必须有默认路由。
say "默认路由"
/usr/local/bin/x6818-diag route "$GW" || die "加默认路由失败（网关不是 $GW？）"

# ---------- 3. 装 openssh-server ----------
if [ -x /usr/sbin/sshd ]; then
	say "openssh-server 已装，跳过 apt"
else
	# 板上没有 systemd：让包的 service 脚本直接返回 101（"不启动"），
	# 否则 invoke-rc.d 会失败把 dpkg 配置卡住。
	printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
	chmod 755 /usr/sbin/policy-rc.d
	say "apt-get update"
	apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Languages=none update \
		|| die "apt update 失败：先看上面的 DNS / 路由"
	say "apt-get install openssh-server"
	apt-get install -y --no-install-recommends openssh-server \
		|| die "装 openssh-server 失败"
fi

# ---------- 4. root 公钥登录 ----------
mkdir -p /run/sshd /var/empty /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys <<'KEY'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCVgTnfBSC5hGNNqa2YLo+vznpq0l+Fry3f+omcNNwbWtaMbEFZnm5enYhZICN7oR+9lVtAnYiNePwoff13KlHjh/o4rKAiGgrOrVvA2Car4O2qd4LM0O9+H62F45X25GdPcAiZm7eq414RvOxz2bT7EYv1UGn/bB6fESj4qU6F0HJvFE6Boe727tQNW8e/nZkaID6JcplhQUpVGxpA7eetZzpcyd5QsNnWWMSyAO3ffOUtg1CPJ2s52P/7NX062PYWGp286C818uHkIQC88WvyiUaaO9OqkJ51zzKTLLHN86ss0xUZkyQTQcc6KL6u6/h4ejPuNxVYmz5bPdCWTLj4qEU46e5vmxKobWGf0BYNbUqihLxzvyveaMkON3F9h8k65wKI5QxQmcMIWKZmY4p5GBopjX3TyMXVtGxsvFhWB/ZjATsXn3J+2NWYDyoZptVqA8mNFaFj2tpZ3SA5q38Kbu8KW2q+sEOVwdcWKeTx4tWKoK4Cp3v6X2OzaAGdS80= honey@honey-Home
KEY
chmod 600 /root/.ssh/authorized_keys

# root 只允许公钥（板子在局域网里，别开 root 口令登录）
sed -i \
	-e 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' \
	-e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
	-e 's/^#\?UsePAM.*/UsePAM no/' \
	/etc/ssh/sshd_config
grep -q '^PermitRootLogin' /etc/ssh/sshd_config || echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
grep -q '^UsePAM' /etc/ssh/sshd_config || echo 'UsePAM no' >> /etc/ssh/sshd_config

# 权限分离用户（包正常安装时已经建好，兜底一下）
id sshd >/dev/null 2>&1 || \
	adduser --system --group --quiet --home /run/sshd --no-create-home \
	        --disabled-password sshd >/dev/null 2>&1 || true

ssh-keygen -A >/dev/null 2>&1 || true
/usr/sbin/sshd -t || die "sshd 配置检查失败"
pkill -x sshd 2>/dev/null || true
/usr/sbin/sshd

# ---------- 5. 开机自启：/usr/sbin/init 换成 v2 ----------
if ! grep -q 'x6818 init v2' /usr/sbin/init 2>/dev/null; then
	say "更新 /usr/sbin/init（默认路由 + sshd 自启），旧的备份为 init.bak"
	[ -f /usr/sbin/init ] && cp -a /usr/sbin/init /usr/sbin/init.bak
	cat > /usr/sbin/init <<'INIT'
#!/bin/sh
# x6818 init v2
# x6818 最小 bring-up init（ubuntu-base 官方 tarball 里没有 systemd/init）
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc  none /proc
mount -t sysfs none /sys
mkdir -p /dev/pts; mount -t devpts none /dev/pts
mount -t tmpfs none /tmp
hostname x6818 2>/dev/null

# DNS：ubuntu-base 自带的 /etc/resolv.conf 指向 127.0.0.53（systemd-resolved 的桩），
# 本 rootfs 里没有 systemd-resolved，原样留着等于没有 DNS，apt 必然解析失败。
if ! grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null ||
   grep -q '^nameserver 127\.0\.0\.53' /etc/resolv.conf 2>/dev/null; then
	printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf
fi

# 网口：静态 IP + 默认路由。rootfs 里没有 ip/ifconfig，用自带的小工具（纯 ioctl）。
# 改 IP/网关：设 X6818_IP / X6818_GW，或直接改下面的默认值。
X6818_IP=${X6818_IP:-192.168.31.150/24}
X6818_GW=${X6818_GW:-192.168.31.1}
if [ -x /usr/local/bin/x6818-diag ]; then
	/usr/local/bin/x6818-diag netup "$X6818_IP" >/dev/null 2>&1 || true
	/usr/local/bin/x6818-diag route "$X6818_GW" >/dev/null 2>&1 || true
fi

# 板子没有 systemd：装了 openssh-server 就手工拉起 sshd（没装就静默跳过）
if [ -x /usr/sbin/sshd ]; then
	mkdir -p /run/sshd
	/usr/sbin/sshd 2>/dev/null || true
fi

echo "--- x6818: mainline Linux up, serial console ttySAC0 ---"
echo "    ip: ${X6818_IP}  gw: ${X6818_GW}"
exec /usr/sbin/agetty -L -a root 115200 ttySAC0 vt100
INIT
	chmod 755 /usr/sbin/init
fi

# ---------- 6. 自检 ----------
say "监听 22："
grep -i ':0016' /proc/net/tcp || die "sshd 没在监听 22"
say "完成。PC 上试： ssh root@192.168.31.150"
