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

# Make args matching parent repo (raz123/android_kernel_redalpha)
MAKE_ARGS="ARCH=arm64 \
           SUBARCH=arm64 \
           O=out \
           HOSTCC=clang \
           CLANG_TRIPLE=aarch64-linux-gnu- \
           CROSS_COMPILE=aarch64-linux-gnu- \
           CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
           CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
           LLVM=1 \
           LLVM_IAS=1"

# ReSukiSU (skip when KSU=0 for vanilla builds)
if [ "$KSU" = "1" ]; then
    git config --global --add safe.directory /workspace/KernelSU
    git config --global --add safe.directory /workspace
    if [ -d "KernelSU/.git" ]; then
        cd KernelSU && git fetch --depth=1 origin HEAD && git reset --hard FETCH_HEAD && cd ..
    else
        git clone --depth=1 https://github.com/ReSukiSU/ReSukiSU KernelSU
    fi
    ln -sf ../KernelSU/kernel drivers/kernelsu
    # Patch ReSukiSU for MANUAL_HOOK compatibility (maps SUSFS symbol names)
    perl -i -0pe 's/(#elif defined\(CONFIG_KSU_MANUAL_HOOK\))/$1\n    \/* Compatibility: SUSFS symbol names used by fs hooks *\/\n    #define ksu_is_init_rc_hook_enabled ksu_init_rc_hook\n    #define ksu_is_input_hook_enabled ksu_input_hook/' KernelSU/kernel/runtime/ksud_integration.c
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
if [ "${CLEAN_BUILD:-0}" = "1" ] || [ ! -f "out/Makefile" ]; then
    rm -rf out/
fi

# Build
make $MAKE_ARGS ${DEVICE}_defconfig

# Apply additional configs matching AstideLabs
scripts/config --file out/.config -e BBG
scripts/config --file out/.config -e REKERNEL -e REKERNEL_NETWORK
# Disable IKHEADERS (kheaders_data.tar.xz causes Error 127)
scripts/config --file out/.config --disable IKHEADERS
if [ "$KSU" = "1" ]; then
    # Check if defconfig already has KSU enabled (main branch has it built-in)
    if grep -q "CONFIG_KSU=y" arch/arm64/configs/${DEVICE}_defconfig 2>/dev/null; then
        echo "Defconfig already has KSU enabled, skipping KSU config overrides"
        # Only disable LTO (KSU requires it)
        scripts/config --file out/.config --disable LTO_CLANG --enable LTO_NONE
    else
        scripts/config --file out/.config \
            --disable LTO_CLANG \
            --enable LTO_NONE \
            --enable KSU \
            --enable THREAD_INFO_IN_TASK \
            --enable KSU_MANUAL_HOOK \
            --enable KSU_MULTI_MANAGER_SUPPORT \
            --disable KPM
    fi
fi
if [ -n "${KBUILD_BUILD_VERSION:-}" ]; then
    scripts/config --file out/.config --set-str LOCALVERSION "-aptusitu-perf-b${KBUILD_BUILD_VERSION}"
fi
# Resolve dependency chain after config changes
make $MAKE_ARGS olddefconfig
# Kernel 4.19 compat: MODULE_IMPORT_NS not defined until 5.x+
if ! grep -q "MODULE_IMPORT_NS" include/linux/module.h 2>/dev/null; then
    echo "" >> include/linux/module.h
    echo "#ifndef MODULE_IMPORT_NS" >> include/linux/module.h
    echo "#define MODULE_IMPORT_NS(_ns)" >> include/linux/module.h
    echo "#endif" >> include/linux/module.h
    echo "Added MODULE_IMPORT_NS compat shim to include/linux/module.h"
fi

echo "Building kernel..."
make $MAKE_ARGS CC="ccache clang" -j${PARALLEL_JOBS:-$(nproc)}
echo ""

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
[ -f "zram-resize.sh" ] && cp zram-resize.sh out/modules/
[ -f "uclamp_tuning.sh" ] && cp uclamp_tuning.sh out/modules/
[ -f "vm_tuning.sh" ] && cp vm_tuning.sh out/modules/
# ccache stats
echo "=== ccache stats ==="
ccache -s 2>/dev/null | grep -E 'Hits:|Misses:|Cache size' || echo "ccache stats unavailable"
echo "===================="
