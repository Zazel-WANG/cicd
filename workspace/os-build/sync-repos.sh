#!/bin/bash
# sync-repos.sh - sync 8 LubanCat RK3588 SDK repos + one-time setup
# 方案 C: git clone/pull 替代 repo sync
# Usage: ./sync-repos.sh   (inside /workspace)
# Docker UID mismatch workaround
git config --global --add safe.directory /workspace 2>/dev/null || true
for d in /workspace/*; do [ -d "$d/.git" ] && git config --global --add safe.directory "$d" 2>/dev/null; done
set -e
GITEA="ssh://git@10.0.0.1:2222/wangzhongqi"
WORKSPACE="/workspace"
cd "$WORKSPACE"
echo "=== OS SDK sync $(date) ==="

CHANGED=0
mkdir -p device

sync_repo() {
    local repo="$1" path="$2"
    if [ ! -d "$path/.git" ]; then
        echo "[NEW]  $repo -> $path"
        git clone "$GITEA/$repo.git" "$path" 2>&1 | tail -1
        CHANGED=1
    else
        BEFORE=$(git -C "$path" rev-parse HEAD 2>/dev/null)
        echo -n "[SYNC] $path "
        git -C "$path" fetch origin 2>&1 | tail -1
        git -C "$path" reset --hard origin/master 2>&1 | tail -1
        AFTER=$(git -C "$path" rev-parse HEAD 2>/dev/null)
        if [ "$BEFORE" != "$AFTER" ]; then
            echo "       $BEFORE -> $AFTER"
            CHANGED=1
        else
            echo "       no change"
        fi
    fi
}

sync_repo "rkbin"        "rkbin"
sync_repo "u-boot"       "u-boot"
sync_repo "tools"        "tools"
sync_repo "device_rockchip" "device/rockchip"
sync_repo "kernel"       "kernel"
sync_repo "debian11"     "debian"
sync_repo "ubuntu"       "ubuntu"
sync_repo "gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu" "prebuilts"
echo "=== sync done ==="

# ---------- first-run setup ----------
# linkfile replacements (repo)
rm -f device/rockchip/.target_product device/rockchip/.BoardConfig.mk
ln -sf rk3588 device/rockchip/.target_product
ln -sf .target_product/BoardConfig-LubanCat-3588-debian-xfce.mk device/rockchip/.BoardConfig.mk
# wrapper scripts (symlinks break TOP_DIR resolution in build.sh)
for script in build.sh mkfirmware.sh rkflash.sh; do
    [ ! -f $script ] && { echo "#!/bin/bash" > $script; echo "exec device/rockchip/common/$script \"\$@\"" >> $script; chmod +x $script; }
done
ln -sf /usr/bin/python3 /usr/bin/python

# ---------- toolchain setup ----------
GCC_ACTUAL="prebuilts/gcc/linux-x86/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu"
GCC_EXPECT="prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu"
GCC_BIN="$GCC_ACTUAL/bin"

# 1) build.sh: path depth fix
if grep -q "$GCC_EXPECT" device/rockchip/common/build.sh 2>/dev/null; then
    echo "[INIT] fix build.sh toolchain path"
    sed -i "s|$GCC_EXPECT|$GCC_ACTUAL|g" device/rockchip/common/build.sh
fi
# 2) u-boot/make.sh: GCC 6.3 -> 10.3
if grep -q "gcc-linaro-6.3.1" u-boot/make.sh 2>/dev/null; then
    echo "[INIT] fix u-boot/make.sh toolchain"
    sed -i "s|../prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64-aarch64-linux-gnu/bin/|../$GCC_BIN/|g" u-boot/make.sh
fi
# 3) prefix aliases
echo "[INIT] toolchain prefix aliases"
cd "$GCC_BIN"
for f in aarch64-none-linux-gnu-*; do
    new=$(echo $f | sed 's/none-linux-gnu/linux-gnu/')
    [ ! -e "$new" ] && ln -sf "$f" "$new"
done
cd "$WORKSPACE"
# 4) GCC permissions (lost in SCP)
echo "[INIT] fix GCC permissions"
chmod -R +x "$GCC_ACTUAL" 2>/dev/null || true
# 5) fix CRLF line endings (Windows->Linux transfer)
echo "[INIT] fix CRLF line endings"
# 只修文本，不动二进制
find . -not -path "*/.git/*" -type f \( -name "*.sh" -o -name "*.h" -o -name "*.dts" -o -name "*.dtsi" -o -name "*.mk" -o -name "Kconfig" -o -name "Kconfig*" -o -name "Makefile" -o -name "Makefile*" -o -name "*.c" -o -name "*.py" -o -name "*.pl" -o -name "*.S" -o -name "*.txt" \) -exec sed -i "s/\r$//" {} + 2>/dev/null || true
# 5b) fix DTC include-prefix: replace mapping files with symlinks to real include/
echo "[INIT] fix DTC include-prefixes"
PREF=/workspace/kernel/scripts/dtc/include-prefixes
if [ -f $PREF/dt-bindings ]; then mv $PREF/dt-bindings $PREF/dt-bindings.txt; fi
[ ! -L $PREF/dt-bindings ] && ln -sf ../../../include/dt-bindings $PREF/dt-bindings
# 5c) fix DTC include-prefix files (missing newlines from Windows)
echo "[INIT] fix DTC include-prefixes"
find . -path "*/scripts/dtc/include-prefixes/*" -type f -print0 | while IFS= read -r -d "" f; do echo "" >> "$f"; done 2>/dev/null || true
# 6) permissions (scripts + binaries, lost during Windows SCP)
echo "[INIT] fix permissions"
chmod +x u-boot/tools/* 2>/dev/null || true
chmod +x tools/linux/Linux_Pack_Firmware/rockdev/* 2>/dev/null || true
find . -name "*.sh" -o -name "*.py" -o -name "*.pl" 2>/dev/null | xargs chmod +x 2>/dev/null || true
# ELF binaries
find . -type f -exec file {} + 2>/dev/null | grep "ELF" | cut -d: -f1 | xargs -r chmod +x 2>/dev/null || true

echo ""
if [ "$CHANGED" -eq 1 ]; then
    echo "RESULT: changed"
    touch "$WORKSPACE/.build-needed"
else
    echo "RESULT: no change"
    rm -f "$WORKSPACE/.build-needed"
fi
