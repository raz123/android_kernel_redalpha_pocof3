#!/bin/bash
set -euo pipefail

KERNEL_IMAGE="${1:?Usage: $0 <path-to-kernel-image>}"

# Check if kernel image exists
if [[ ! -f "$KERNEL_IMAGE" ]]; then
    echo "ERROR: Kernel image not found: $KERNEL_IMAGE" >&2
    exit 1
fi

echo "Validating KSU symbols in: $KERNEL_IMAGE"
echo "========================================="

# List of required KSU symbols
REQUIRED_SYMBOLS=(
    "ksu_handle_restart"
    "ksu_hooker"
    "ksu_is_enabled"
)

FAILED=0

for symbol in "${REQUIRED_SYMBOLS[@]}"; do
    # Use strings to extract readable symbols from binary and grep for exact match
    # Use word boundary to avoid partial matches
    if strings "$KERNEL_IMAGE" | grep -qE "\b${symbol}\b"; then
        echo "PASS: $symbol"
    else
        echo "FAIL: $symbol"
        FAILED=1
    fi
done

echo "========================================="

if [[ "$FAILED" -eq 0 ]]; then
    echo "All KSU symbols found."
else
    echo "Some KSU symbols missing."
    exit 1
fi