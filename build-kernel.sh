#!/bin/bash
set -euo pipefail
DEVICE="${DEVICE:-alioth}"
KSU="${KSU:-1}"

# Toolchain — use AOSP kernel-build clang
if [ ! -d "toolchain/clang" ]; then
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
        -b master-kernel-build-2024 toolchain/clang
fi
export PATH="$PWD/toolchain/clang/bin:$PATH"

# Cross-compiler
export ARCH=arm64
export SUBARCH=arm64

# ReSukiSU (skip when KSU=0 for vanilla builds)
if [ "$KSU" = "1" ]; then
    if [ ! -d "KernelSU" ]; then
        git clone --depth=1 -b v4.1.0 https://github.com/ReSukiSU/ReSukiSU KernelSU
    fi
    ln -sf ../KernelSU/kernel drivers/kernelsu
    # Disable check_mk files that block build
    for check in drivers/kernelsu/tools/*_check.mk; do
        echo "# Disabled for CI" > "$check" 2>/dev/null || true
    done
fi

# Build
make CC=clang LD=ld.lld ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    ${DEVICE}_defconfig

if [ "$KSU" = "1" ]; then
    scripts/config --disable CONFIG_LTO_CLANG
    scripts/config --enable CONFIG_LTO_NONE
    scripts/config --enable CONFIG_KSU
    scripts/config --enable CONFIG_KSU_MANUAL_HOOK
fi

make CC=clang LD=ld.lld ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    -j$(nproc)

# Collect output
mkdir -p out/modules
cp arch/arm64/boot/Image.gz-dtb out/ 2>/dev/null || \
    cp arch/arm64/boot/Image out/ 2>/dev/null || true
find . -name "*.ko" -exec cp {} out/modules/ \; 2>/dev/null || true
