#!/system/bin/sh
# VM Tuning for PocoF3 (SM8250 8GB)
# Runs at boot via ReSukiSU service.sh

# Reduce swap tendency — favor file cache over anon swap
echo 40 > /proc/sys/vm/swappiness

# Reserve 48MB for emergency allocations
echo 48000 > /proc/sys/vm/min_free_kbytes

# kswapd wakes earlier to avoid direct reclaim stalls
echo 50 > /proc/sys/vm/watermark_scale_factor

# Reduce external fragmentation pressure
echo 750 > /proc/sys/vm/extfrag_threshold

# Reclaim dentries/inodes more aggressively
echo 75 > /proc/sys/vm/vfs_cache_pressure
