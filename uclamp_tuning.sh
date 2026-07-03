#!/system/bin/sh
#=== UCLAMP Tuning ============================================================
#
# Installed as part of RedAlpha kernel builds for Poco F3 (alioth/SM8250).
# Sets utilization clamping values per cpu cgroup after boot.
#
# Requires: CONFIG_UCLAMP_TASK=y, CONFIG_UCLAMP_TASK_GROUP=y in kernel.
#
# UCLAMP sysfs is exposed via cgroup v1 cpu controller (not cpuset):
#   /dev/cpuctl/<group>/cpu.uclamp.{min,max}
#
# Values use 0.00-1.00 scale (0% to 100% of CPU capacity).
# - uclamp.min: floor — task gets at least this much capacity
# - uclamp.max: ceiling — task never exceeds this
#
# INSTALLATION:
#   Copy to /data/adb/ksu/service.d/uclamp_tuning.sh
#   chmod +x /data/adb/ksu/service.d/uclamp_tuning.sh
#==============================================================================

CPU_DIR=/dev/cpuctl

# top-app — interactive/foreground app: minimum floor, prefers big cores
if [ -f "$CPU_DIR/top-app/cpu.uclamp.min" ]; then
  echo 0.10 > "$CPU_DIR/top-app/cpu.uclamp.min"
  echo 1.00 > "$CPU_DIR/top-app/cpu.uclamp.max"
  echo 1    > "$CPU_DIR/top-app/cpu.uclamp.latency_sensitive"
fi

# foreground — visible system services: moderate ceiling
if [ -f "$CPU_DIR/foreground/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/foreground/cpu.uclamp.min"
  echo 0.50 > "$CPU_DIR/foreground/cpu.uclamp.max"
  echo 1    > "$CPU_DIR/foreground/cpu.uclamp.latency_sensitive"
fi

# background — cached apps: low priority, low ceiling
if [ -f "$CPU_DIR/background/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/background/cpu.uclamp.min"
  echo 0.30 > "$CPU_DIR/background/cpu.uclamp.max"
  echo 0    > "$CPU_DIR/background/cpu.uclamp.latency_sensitive"
fi

# system-background — services: minimal impact
if [ -f "$CPU_DIR/system-background/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/system-background/cpu.uclamp.min"
  echo 0.40 > "$CPU_DIR/system-background/cpu.uclamp.max"
  echo 0    > "$CPU_DIR/system-background/cpu.uclamp.latency_sensitive"
fi
