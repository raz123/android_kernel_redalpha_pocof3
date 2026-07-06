#!/system/bin/sh
#=== VM Tuning: Reduce kswapd CPU and compaction failures =====================
#
# Installed as part of RedAlpha kernel builds for Poco F3 (alioth/SM8250).
#
# Reduces kswapd scan volume (lower CPU usage, less battery drain) and
# compaction failure rate without meaningful memory tradeoffs on 8GB device.
#
# Changes:
#   watermark_scale_factor: 10 → 50
#     Kswapd starts at higher watermark, reclaims more per cycle.
#     Fewer wakeups, less total scanning. ~40MB extra reserved.
#
#   extfrag_threshold: 500 → 750
#     More fragmentation tolerated before compaction triggers.
#     Fewer attempts → fewer reported failures.
#
#   vfs_cache_pressure: 100 → 75
#     Less aggressive inode/dentry cache reclaim.
#     Less scanning, slightly more cache memory.
#
#   swappiness: default (60) → 40
#     Less aggressive page reclaim from anonymous memory.
#     Keeps more app pages in RAM longer.
#
#   min_free_kbytes: default → 48000 (~47MB)
#     Reserves more memory for emergency allocations.
#     Reduces direct reclaim stalls under memory pressure.
#==============================================================================

echo 50 > /proc/sys/vm/watermark_scale_factor
echo 750 > /proc/sys/vm/extfrag_threshold
echo 75  > /proc/sys/vm/vfs_cache_pressure
echo 40 > /proc/sys/vm/swappiness
echo 48000 > /proc/sys/vm/min_free_kbytes
