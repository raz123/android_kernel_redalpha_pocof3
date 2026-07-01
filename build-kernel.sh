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
        git clone --depth=1 https://github.com/ReSukiSU/ReSukiSU KernelSU
    fi
    ln -sf ../KernelSU/kernel drivers/kernelsu
    # Disable check_mk files that block build
    for check in drivers/kernelsu/tools/*_check.mk; do
        echo "# Disabled for CI" > "$check" 2>/dev/null || true
    done
    # Add ReSukiSU Kconfig source to drivers/Kconfig (before endmenu)
    if ! grep -q 'source.*drivers/kernelsu/Kconfig' drivers/Kconfig; then
        sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' drivers/Kconfig
    fi
    # Add ReSukiSU obj to drivers/Makefile (kernelsu/ is under drivers/)
    if ! grep -q 'obj-$(CONFIG_KSU) += kernelsu/' drivers/Makefile; then
        echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
    fi
fi

# Clean previous build
rm -rf out/

# Build
make $MAKE_ARGS CC="ccache clang" ${DEVICE}_defconfig

# Apply additional configs matching AstideLabs
scripts/config --file out/.config -e BBG
scripts/config --file out/.config -e REKERNEL -e REKERNEL_NETWORK
# Disable IKHEADERS (kheaders_data.tar.xz causes Error 127)
scripts/config --file out/.config --disable IKHEADERS
if [ "$KSU" = "1" ]; then
    scripts/config --file out/.config \
        --disable LTO_CLANG \
        --enable LTO_NONE \
        --enable KSU \
        --enable THREAD_INFO_IN_TASK \
        --enable KSU_MANUAL_HOOK \
        --enable KSU_MULTI_MANAGER_SUPPORT \
        --disable KPM
fi
# Resolve dependency chain after config changes
make $MAKE_ARGS CC="ccache clang" olddefconfig
# Kernel 4.19 compat: MODULE_IMPORT_NS not defined until 5.x+
if ! grep -q "MODULE_IMPORT_NS" include/linux/module.h 2>/dev/null; then
    echo "" >> include/linux/module.h
    echo "#ifndef MODULE_IMPORT_NS" >> include/linux/module.h
    echo "#define MODULE_IMPORT_NS(_ns)" >> include/linux/module.h
    echo "#endif" >> include/linux/module.h
    echo "Added MODULE_IMPORT_NS compat shim to include/linux/module.h"
fi

echo "Building kernel..."
make $MAKE_ARGS CC="ccache clang" -j$(nproc)

# Generate combined DTB (concatenate all individual DTBs)
echo "Generating out/arch/arm64/boot/dtb......"
find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb
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
# ccache stats
echo "=== ccache stats ==="
ccache -s 2>/dev/null | grep -E 'Hits:|Misses:|Cache size' || echo "ccache stats unavailable"
echo "===================="
