#!/bin/bash
set -eo pipefail
cd /workspace

echo "=== build ==="
./build.sh BoardConfig-LubanCat-3588-debian-xfce.mk
./build.sh

echo "=== archive ==="
VER=$(date +%Y%m%d-%H%M)
mkdir -p /workspace/output
cp rockdev/update.img /workspace/output/lubancat-rk3588-${VER}.img
ls -lh /workspace/output/lubancat-rk3588-${VER}.img
echo "BUILD OK: lubancat-rk3588-${VER}.img"
