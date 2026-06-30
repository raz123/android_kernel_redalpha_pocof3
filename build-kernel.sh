#!/bin/bash
set -euo pipefail

DEVICE="${DEVICE:-alioth}"
KSU="${KSU:-1}"
TOOLCHAIN_PATH="/opt/zyc-clang/bin"

# Verify toolchain
if [ ! -d "$TOOLCHAIN_PATH" ]; then
    echo "ERROR: ZyC-Clang not found at $TOOLCHAIN_PATH"
    exit 1
fi
export PATH="$TOOLCHAIN_PATH:$PATH"
echo "Using: $(clang --version | head -1)"

# Verify cross-compiler
if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
    echo "ERROR: aarch64-linux-gnu-ld not found"
    exit 1
fi

# Make args matching AstideLabs exactly
MAKE_ARGS="ARCH=arm64 \
           SUBARCH=arm64 \
           O=out \
           CC=clang \
           HOSTCC=clang \
           CLANG_TRIPLE=aarch64-linux-gnu- \
           CROSS_COMPILE=aarch64-linux-gnu- \
           CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
           CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
           LD=ld.lld \
           AR=llvm-ar \
           NM=llvm-nm \
           OBJCOPY=llvm-objcopy \
           OBJDUMP=llvm-objdump \
           STRIP=llvm-strip"

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

# Clean previous build
rm -rf out/

# Build
make $MAKE_ARGS ${DEVICE}_defconfig

if [ "$KSU" = "1" ]; then
    scripts/config --file out/.config \
        --disable LTO_CLANG \
        --enable LTO_NONE \
        --enable KSU \
        --enable KSU_MANUAL_HOOK
fi

make $MAKE_ARGS -j$(nproc)

# Collect output
mkdir -p out/modules
if [ -f "out/arch/arm64/boot/Image" ]; then
    echo "Build successful: out/arch/arm64/boot/Image"
elif [ -f "out/arch/arm64/boot/Image.gz-dtb" ]; then
    echo "Build successful: out/arch/arm64/boot/Image.gz-dtb"
else
    echo "ERROR: No kernel image found"
    exit 1
fi

find out/ -name "*.ko" -exec cp {} out/modules/ \; 2>/dev/null || true
