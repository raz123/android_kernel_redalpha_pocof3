#!/bin/bash
set -euo pipefail

# Default defconfig path
DEFCONFIG="${1:-arch/arm64/configs/alioth_defconfig}"

# List of required CONFIG options
REQUIRED_CONFIGS=(
    "CONFIG_SCHED_WALT=y"
    "CONFIG_BPF_LSM=y"
    "CONFIG_BPF_SYSCALL=y"
    "CONFIG_BPF_JIT_ALWAYS_ON=y"
    "CONFIG_MODULES=y"
    "CONFIG_ANDROID_VENDOR_HOOKS=y"
    "CONFIG_KALLSYMS=y"
    "CONFIG_KALLSYMS_ALL=y"
    "CONFIG_LTO_CLANG=y"
    "CONFIG_ZRAM=y"
    "CONFIG_ZRAM_WRITEBACK=y"
)

# Check if defconfig exists
if [[ ! -f "$DEFCONFIG" ]]; then
    echo "ERROR: Defconfig file not found: $DEFCONFIG" >&2
    exit 1
fi

echo "Validating defconfig: $DEFCONFIG"
echo "========================================="

FAILED=0

for config in "${REQUIRED_CONFIGS[@]}"; do
    if grep -q "^${config}$" "$DEFCONFIG"; then
        echo "PASS: $config"
    else
        echo "FAIL: $config"
        FAILED=1
    fi
done

echo "========================================="

if [[ "$FAILED" -eq 0 ]]; then
    echo "All required configs are enabled."
else
    echo "Some configs are missing."
    exit 1
fi