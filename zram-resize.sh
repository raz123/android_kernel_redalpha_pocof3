#!/system/bin/sh
#=== ZRAM Resize to 4GB =======================================================
#
# Installed as part of RedAlpha kernel builds for Poco F3 (alioth/SM8250).
#
# WHY: The stock /vendor/etc/fstab.qcom sets zramsize=2147483648 (2GB),
# which is insufficient for Android 16+ with memory-heavy workloads.
# This script overrides that at boot to provide 4GB of compressed ZRAM.
#
# HOW IT WORKS:
# - Android init triggers swapon_all from fstab.qcom at sys.boot_completed=1,
#   which creates 2GB ZRAM and enables swap.
# - KernelSU service.d scripts also start at late_start (same trigger).
# - This script waits for ZRAM to be fully set up, then:
#   1. swapoff /dev/block/zram0
#   2. Reset the ZRAM device
#   3. Set disksize to 4294967296 (4 GiB)
#   4. mkswap + swapon
#
# INSTALLATION (pick one):
#
# 1) KernelSU service.d (RECOMMENDED):
#    Copy this script to /data/adb/ksu/service.d/zram-resize.sh
#    chmod +x /data/adb/ksu/service.d/zram-resize.sh
#    Reboot. ReSukiSU runs it at late_start automatically.
#
# 2) AnyKernel3 ZIP (automatic with RedAlpha builds):
#    This script is included in the ZIP at anykernel-modules/zram-resize.sh.
#    The ZIP only replaces boot.img. After flashing, still copy to KSU
#    service.d as in method 1.
#
# 3) Manual via ADB (lasts only until reboot):
#    adb push zram-resize.sh /data/local/tmp/
#    adb shell chmod +x /data/local/tmp/zram-resize.sh
#    adb shell sh /data/local/tmp/zram-resize.sh
#
# VERIFICATION:
#    cat /sys/block/zram0/disksize  -->  4294967296
#    cat /proc/swaps               -->  /dev/block/zram0  partition  4194296
#    cat /proc/meminfo | grep SwapTotal -->  SwapTotal: 4194296 kB
#
# TROUBLESHOOTING:
# - ZRAM module not loaded: check /proc/config.gz for CONFIG_ZRAM=y
# - swapoff fails (busy): increase WAIT_MAX below
# - Still 2GB after reboot: script not in KSU service.d (check /data/adb/ksu/service.d/)
#================================================================================

WAIT_MAX=15
ZRAM_DEV=/dev/block/zram0
SZ_DISK=/sys/block/zram0/disksize
SZ_RESET=/sys/block/zram0/reset

# Sanity: skip if ZRAM doesn't exist
test -e "$SZ_DISK" || exit 0

# Check if already 4GB
CUR_SZ=$(cat "$SZ_DISK" 2>/dev/null || echo 0)
if [ "$CUR_SZ" = "4294967296" ]; then
  exit 0
fi

# Wait for ZRAM swap to be activated by init
WAITED=0
while [ "$WAITED" -lt "$WAIT_MAX" ]; do
  if grep -q "zram0" /proc/swaps 2>/dev/null; then
    break
  fi
  sleep 0.3
  WAITED=$((WAITED + 1))
done

# Resize
swapoff "$ZRAM_DEV" 2>/dev/null
echo 1 > "$SZ_RESET" 2>/dev/null
echo 4294967296 > "$SZ_DISK" 2>/dev/null

if [ "$(cat "$SZ_DISK" 2>/dev/null)" = "4294967296" ]; then
  mkswap "$ZRAM_DEV" 2>/dev/null
  swapon "$ZRAM_DEV" 2>/dev/null
fi
