#!/system/bin/sh
#=== UCLAMP Tuning ============================================================
#
# Installed as part of RedAlpha kernel builds for Poco F3 (alioth/SM8250).
# Sets utilization clamping values per cpuset after boot.
#
# Requires: CONFIG_UCLAMP_TASK=y, CONFIG_UCLAMP_TASK_GROUP=y in kernel.
#
# Values use 0-1024 scale (0% to 100% of CPU capacity).
# - uclamp.min: floor — task gets at least this much capacity
# - uclamp.max: ceiling — task never exceeds this
#
# INSTALLATION:
#   Copy to /data/adb/ksu/service.d/uclamp_tuning.sh
#   chmod +x /data/adb/ksu/service.d/uclamp_tuning.sh
#==============================================================================

CPUSET_DIR=/dev/cpuset

# Global defaults
sysctl -w kernel.sched_util_clamp_min=128 2>/dev/null

# top-app — interactive/foreground app: minimum floor, prefers big cores
if [ -f "$CPUSET_DIR/top-app/uclamp.min" ]; then
  echo 10    > "$CPUSET_DIR/top-app/uclamp.min"
  echo max   > "$CPUSET_DIR/top-app/uclamp.max"
  echo 1     > "$CPUSET_DIR/top-app/uclamp.latency_sensitive"
fi

# foreground — system services visible to user: moderate
if [ -f "$CPUSET_DIR/foreground/uclamp.min" ]; then
  echo 0     > "$CPUSET_DIR/foreground/uclamp.min"
  echo 50    > "$CPUSET_DIR/foreground/uclamp.max"
  echo 1     > "$CPUSET_DIR/foreground/uclamp.latency_sensitive"
fi

# background — cached apps: low priority, stay on little cores
if [ -f "$CPUSET_DIR/background/uclamp.min" ]; then
  echo 0     > "$CPUSET_DIR/background/uclamp.min"
  echo 30    > "$CPUSET_DIR/background/uclamp.max"
  echo 0     > "$CPUSET_DIR/background/uclamp.latency_sensitive"
fi

# system-background — services: minimal impact
if [ -f "$CPUSET_DIR/system-background/uclamp.min" ]; then
  echo 0     > "$CPUSET_DIR/system-background/uclamp.min"
  echo 40    > "$CPUSET_DIR/system-background/uclamp.max"
  echo 0     > "$CPUSET_DIR/system-background/uclamp.latency_sensitive"
fi
