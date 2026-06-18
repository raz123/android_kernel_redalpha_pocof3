#!/bin/bash
set -euo pipefail

# Default defconfig path
DEFCONFIG="${1:-arch/arm64/configs/alioth_defconfig}"

# List of required CONFIG options
REQUIRED_CONFIGS=(
  "CONFIG_SCHED_WALT"
  "CONFIG_BPF_LSM"
  "CONFIG_BPF_SYSCALL"
  "CONFIG_BPF_JIT_ALWAYS_ON"
  "CONFIG_MODULES"
  "CONFIG_ANDROID_VENDOR_HOOKS"
  "CONFIG_KALLSYMS_ALL"
  "CONFIG_LTO_CLANG"
  "CONFIG_ZRAM"
  "CONFIG_ZRAM_WRITEBACK"
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
    if grep -qE "^${config}=[ym]" "$DEFCONFIG" || grep -qE "^# ${config} is not set$" "$DEFCONFIG"; then
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