#!/bin/bash
set -euo pipefail

ZIP_FILE="${1:?Usage: $0 <path-to-anykernel3.zip>}"

# Check if zip file exists and is valid
if [[ ! -f "$ZIP_FILE" ]]; then
    echo "ERROR: ZIP file not found: $ZIP_FILE" >&2
    exit 1
fi

if ! unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
    echo "ERROR: ZIP file is invalid or corrupted: $ZIP_FILE" >&2
    exit 1
fi

echo "Validating AnyKernel3 ZIP: $ZIP_FILE"
echo "========================================="

FAILED=0

# Check for kernel image (Image.gz-dtb or Image)
if unzip -l "$ZIP_FILE" | grep -qE 'Image\.gz-dtb|Image'; then
    echo "PASS: Kernel image found"
else
    echo "FAIL: Kernel image not found (expected Image.gz-dtb or Image)"
    FAILED=1
fi

# Check for anykernel.sh
if unzip -l "$ZIP_FILE" | grep -q 'anykernel.sh'; then
    echo "PASS: anykernel.sh found"
else
    echo "FAIL: anykernel.sh not found"
    FAILED=1
fi

# Check for module.prop
if unzip -l "$ZIP_FILE" | grep -q 'module.prop'; then
    echo "PASS: module.prop found"
else
    echo "FAIL: module.prop not found"
    FAILED=1
fi

# Extract anykernel.sh to temporary location for further checks
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

if unzip -o "$ZIP_FILE" "anykernel.sh" -d "$TEMP_DIR" >/dev/null 2>&1; then
    ANYKERNEL_FILE="$TEMP_DIR/anykernel.sh"
else
    echo "ERROR: Failed to extract anykernel.sh" >&2
    FAILED=1
    echo "========================================="
    exit 1
fi

# Check device.name1=alioth or device.name2=aliothin
if grep -qE 'device\.name1=alioth|device\.name2=aliothin' "$ANYKERNEL_FILE"; then
    echo "PASS: Device name matches alioth/aliothin"
else
    echo "FAIL: Device name not set to alioth or aliothin"
    FAILED=1
fi

# Check IS_SLOT_DEVICE=1 (case-insensitive)
if grep -qi 'IS_SLOT_DEVICE=1' "$ANYKERNEL_FILE"; then
    echo "PASS: IS_SLOT_DEVICE=1"
else
    echo "FAIL: IS_SLOT_DEVICE=1 not found"
    FAILED=1
fi

# Check BLOCK=/dev/block/bootdevice/by-name/boot (case-insensitive)
if grep -qi 'BLOCK=/dev/block/bootdevice/by-name/boot' "$ANYKERNEL_FILE"; then
    echo "PASS: BLOCK set correctly"
else
    echo "FAIL: BLOCK not set to /dev/block/bootdevice/by-name/boot"
    FAILED=1
fi

echo "========================================="

if [[ "$FAILED" -eq 0 ]]; then
    echo "All validations passed."
else
    echo "Some validations failed."
    exit 1
fi