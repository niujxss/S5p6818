#!/bin/bash
# make-ssh-bundle.sh —— 在服务器上打一个"离线 SSH 包"，给还没装 ssh 的板子用
#
#   ./make-ssh-bundle.sh
#   → out/ssh-bundle.tar.gz
#      ├── libtommath1.deb / libtomcrypt1.deb / dropbear-bin.deb
#      ├── authorized_keys   （取自 $PUBKEY，默认 ~/.ssh/id_rsa.pub）
#      └── install.sh        （板上 dpkg -i + 配 root 公钥 + 起 dropbear）
#
# 包里的 dropbear 版本是 jammy 的；换发行版/架构要改下面的 URL。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
OUT=${OUT:-$REPO/out}
PUBKEY=${PUBKEY:-$REPO/keys/root_authorized_keys.pub}

MIRROR=${MIRROR:-http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports}
DROPBEAR_POOL=pool/universe/d/dropbear/dropbear-bin_2020.81-5ubuntu0.1_arm64.deb
TOMCrypt_POOL=pool/universe/libt/libtomcrypt/libtomcrypt1_1.18.2-5_arm64.deb
TOMMATH_POOL=pool/main/libt/libtommath/libtommath1_1.2.0-6ubuntu0.22.04.1_arm64.deb

[ -f "$PUBKEY" ] || { echo "!! 找不到公钥 $PUBKEY"; exit 1; }
mkdir -p "$OUT"
WK=$(mktemp -d)
trap 'rm -rf "$WK"' EXIT

echo "==> 下载 deb（arm64）"
for item in "$TOMMATH_POOL" "$TOMCrypt_POOL" "$DROPBEAR_POOL"; do
	curl -sSf -m 120 -o "$WK/$(basename "$item")" "$MIRROR/$item"
done

install -m 600 "$PUBKEY" "$WK/authorized_keys"

cat > "$WK/install.sh" <<'EOS'
#!/bin/sh
# 离线装 dropbear（板子上还没有 ssh 时用）
set -e
cd "$(dirname "$0")"
dpkg -i ./libtommath1_*.deb ./libtomcrypt1_*.deb ./dropbear-bin_*.deb
mkdir -p /root/.ssh /etc/dropbear
chmod 700 /root/.ssh
cp authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
# StrictModes：/root 属主必须是 root（镜像解包可能留下 1000:1000）
chown root:root /root 2>/dev/null || true
pkill -x dropbear 2>/dev/null || true
/usr/sbin/dropbear -R -p 22
sleep 1
grep -qi ':0016' /proc/net/tcp && echo "OK: 22 已监听" || { echo "FAIL: 22 没监听"; exit 1; }
EOS
chmod 755 "$WK/install.sh"

tar czf "$OUT/ssh-bundle.tar.gz" -C "$WK" .
echo "==> $OUT/ssh-bundle.tar.gz"
ls -lh "$OUT/ssh-bundle.tar.gz"
