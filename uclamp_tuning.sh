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
# Reviewed by Android kernel/scheduler specialist (2026-07-03).
# Key findings:
#  - min=0.00 + LS=1 paradoxically biases toward little cores
#    (uclamp_boosted=false negates the big-core preference)
#  - RT tasks use RT scheduler, NOT EAS/CFS — uclamp min doesn't
#    affect their placement; 20% mild floor is generous enough
#  - Buckets 20 is overkill for 5 distinct values but harmless
#
# INSTALLATION:
#   Copy to /data/adb/ksu/service.d/uclamp_tuning.sh
#   chmod +x /data/adb/ksu/service.d/uclamp_tuning.sh
#==============================================================================

CPU_DIR=/dev/cpuctl

# top-app — interactive/foreground app: big cores, fast frequency ramp
# min=10% ensures uclamp_boosted=true → LS=1 drives to big idle CPUs
if [ -f "$CPU_DIR/top-app/cpu.uclamp.min" ]; then
  echo 0.10 > "$CPU_DIR/top-app/cpu.uclamp.min"
  echo 1.00 > "$CPU_DIR/top-app/cpu.uclamp.max"
  echo 1    > "$CPU_DIR/top-app/cpu.uclamp.latency_sensitive"
fi

# foreground — visible system services: prefer big cores
# min=0.05 is critical — at 0.00, uclamp_boosted=false and LS=1
# paradoxically sends foreground tasks to little cores
if [ -f "$CPU_DIR/foreground/cpu.uclamp.min" ]; then
  echo 0.05 > "$CPU_DIR/foreground/cpu.uclamp.min"
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

# rt — real-time (audio, IRQ, IO completion): mild floor
# Frequency boosting for RT comes from schedtune, not uclamp.
# min=20% is for any CFS cross-path tasks that may be in this group.
if [ -f "$CPU_DIR/rt/cpu.uclamp.min" ]; then
  echo 0.20 > "$CPU_DIR/rt/cpu.uclamp.min"
  echo 1.00 > "$CPU_DIR/rt/cpu.uclamp.max"
  echo 1    > "$CPU_DIR/rt/cpu.uclamp.latency_sensitive"
fi
