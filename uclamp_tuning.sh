#!/system/bin/sh
#=== UCLAMP Tuning ============================================================
#
# Installed as part of RedAlpha kernel builds for Poco F3 (alioth/SM8250).
# Sets utilization clamping values per cpu cgroup after boot.
#
# Requires: CONFIG_UCLAMP_TASK=y, CONFIG_UCLAMP_TASK_GROUP=y in kernel.
#
# NOTE: UCLAMP guides TASK PLACEMENT (EAS big vs little core).
# Frequency boosting needs schedtune.boost at /dev/stune/<group>/
# — this script does NOT touch schedtune.
#
# Values use 0.00-1.00 scale (0% to 100% of CPU capacity).
# - uclamp.min: floor — task needs at least this much capacity
# - uclamp.max: ceiling — task never exceeds this
# - uclamp.latency_sensitive: prefer idle CPU placement
#
# Reviewed by Android kernel/scheduler specialist (2026-07-03, revised).
# Battery-aware final values:
#  - UCLAMP guides task placement (EAS), NOT frequency (schedtune).
#  - Only top-app gets min=10% for first-frame latency.
#  - foreground min=0.00 → uclamp_boosted=false → LS=1 prefers
#    little idle CPUs (battery-safe). Big-core bias would cost standby.
#  - RT UCLAMP is a no-op on WALT — RT uses RT scheduler, not EAS,
#    and frequency boost comes from schedtune's 50ms boost-hold.
#    rt group is intentionally NOT set here.
#  - Buckets 20 is overkill but harmless.
#
#==============================================================================

CPU_DIR=/dev/cpuctl

# top-app — interactive/foreground app: big cores, fast frequency ramp
# min=10% ensures uclamp_boosted=true → LS=1 drives to big idle CPUs
if [ -f "$CPU_DIR/top-app/cpu.uclamp.min" ]; then
  echo 0.10 > "$CPU_DIR/top-app/cpu.uclamp.min"
  echo 1.00 > "$CPU_DIR/top-app/cpu.uclamp.max"
  echo 1    > "$CPU_DIR/top-app/cpu.uclamp.latency_sensitive"
fi

# foreground — visible system services: battery-safe, no boost
# min=0.00 → uclamp_boosted=false → LS=1 prefers little idle CPUs
# (at min=0.05 it would bias to big cores — bad for battery)
if [ -f "$CPU_DIR/foreground/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/foreground/cpu.uclamp.min"
  echo 1.00 > "$CPU_DIR/foreground/cpu.uclamp.max"
  echo 1    > "$CPU_DIR/foreground/cpu.uclamp.latency_sensitive"
fi

# background — cached apps: pack efficiently on expanded 4-core cpuset
# max=20% prevents background from appearing to need full core capacity
if [ -f "$CPU_DIR/background/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/background/cpu.uclamp.min"
  echo 0.20 > "$CPU_DIR/background/cpu.uclamp.max"
  echo 0    > "$CPU_DIR/background/cpu.uclamp.latency_sensitive"
fi

# system-background — services: moderate cap
if [ -f "$CPU_DIR/system-background/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/system-background/cpu.uclamp.min"
  echo 0.50 > "$CPU_DIR/system-background/cpu.uclamp.max"
  echo 0    > "$CPU_DIR/system-background/cpu.uclamp.latency_sensitive"
fi

# system — shell/adbd/debug: loose cap
if [ -f "$CPU_DIR/system/cpu.uclamp.min" ]; then
  echo 0.00 > "$CPU_DIR/system/cpu.uclamp.min"
  echo 0.80 > "$CPU_DIR/system/cpu.uclamp.max"
  echo 0    > "$CPU_DIR/system/cpu.uclamp.latency_sensitive"
fi
