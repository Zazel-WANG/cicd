#!/bin/bash
set -eo pipefail
cd /workspace

# git 全局配置已进 Dockerfile
ln -sf rootfs.ext4 rockdev/rootfs.img 2>/dev/null || true

echo "=== repo sync ==="
BEFORE=$(git -C .repo/manifests log -1 --format=%h 2>/dev/null)
.repo/repo/repo sync -c --no-repo-verify
AFTER=$(git -C .repo/manifests log -1 --format=%h 2>/dev/null)

if [ "$BEFORE" = "$AFTER" ] && [ -n "$BEFORE" ]; then
    echo "NO CHANGE: $BEFORE"
    exit 0
fi

echo "CHANGED: $BEFORE -> $AFTER"
echo "=== build ==="
./build.sh BoardConfig-LubanCat-3588-debian-xfce.mk
./build.sh

echo "=== archive ==="
VER=$(date +%Y%m%d-%H%M)
ARCHIVE="/workspace/output"
mkdir -p "$ARCHIVE"
cp rockdev/update.img "$ARCHIVE/lubancat-rk3588-${VER}.img"
ls -lh "$ARCHIVE/lubancat-rk3588-${VER}.img"
ls -t "$ARCHIVE"/lubancat-rk3588-*.img 2>/dev/null | tail -n +4 | xargs rm -f
echo "BUILD OK: lubancat-rk3588-${VER}.img"
