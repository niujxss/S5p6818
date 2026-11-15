#!/bin/sh
# 在“新机器”上首次使用前跑一次：修复拷贝过程中丢失的可执行位
set -e
SELF=$(cd "$(dirname "$0")" && pwd)
cd "$SELF"
chmod +x build.sh tools/mk6818 2>/dev/null || true
echo "已设置可执行位: build.sh tools/mk6818"
