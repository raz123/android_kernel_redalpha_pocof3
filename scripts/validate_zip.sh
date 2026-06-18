#!/bin/bash
set -euo pipefail

ZIP_FILE="${1:?Usage: $0 <path-to-anykernel3.zip>}"

# Resolve to absolute path to avoid issues when running from a different directory
if [[ ! "$ZIP_FILE" = /* ]]; then
    ZIP_FILE="$(pwd)/$ZIP_FILE"
fi

# Check if zip file exists and is valid
if [[ ! -f "$ZIP_FILE" ]]; then
    echo "ERROR: ZIP file not found: $ZIP_FILE" >&2
    exit 1
fi

# Check file size is non-zero
if [[ ! -s "$ZIP_FILE" ]]; then
    echo "ERROR: ZIP file is empty: $ZIP_FILE" >&2
    exit 1
fi

# Validate ZIP integrity using multiple methods (non-fatal)
ZIP_VALID=true

# Method 1: file command check
if command -v file >/dev/null 2>&1; then
    if ! file "$ZIP_FILE" | grep -qi 'zip'; then
        echo "WARN: file command does not identify $ZIP_FILE as a ZIP archive" >&2
        ZIP_VALID=false
    fi
fi

# Method 2: zip -T (preferred, more reliable)
if command -v zip >/dev/null 2>&1; then
    if ! zip -T "$ZIP_FILE" >/dev/null 2>&1; then
        echo "WARN: zip -T reports issues with $ZIP_FILE" >&2
        ZIP_VALID=false
    fi
# Method 3: unzip -t fallback
elif command -v unzip >/dev/null 2>&1; then
    if ! unzip -t "$ZIP_FILE" >/dev/null 2>&1; then
        echo "WARN: unzip -t reports issues with $ZIP_FILE" >&2
        ZIP_VALID=false
    fi
fi

if [[ "$ZIP_VALID" = false ]]; then
    echo "WARN: ZIP validation had issues (check manually): $ZIP_FILE" >&2
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