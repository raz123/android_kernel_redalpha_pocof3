# SPEC: RedAlpha Own Fixes (Phase 2)

## Source

All patches and commits come from the old `raz123/android_kernel_redalpha` repo, default branch `android16-aptusitu`. The old repo is preserved read-only as reference.

**IMPORTANT**: These patches exist as `.patch` files in the old repo's `patches/` directory and were applied at CI time via `git apply`. For the new repo, convert each patch into a real git commit with a descriptive message.

## 1. Ultrasound Sensor Patches

**Source**: `raz123/android_kernel_redalpha:patches/ultrasound/` (4 files)

Copy each `.patch` file to the new repo, then apply and commit individually:

### 1.1 `mipa-iio-poll-data-ready`
- **What**: Adds poll-based data-ready mechanism to IIO (Industrial I/O) subsystem for CH101 ultrasound sensor.
- **Files touched**: drivers/iio/ (verify exact paths from patch)
- **Commit message**: `fix(ultrasound): add IIO poll data-ready for CH101 sensor`

### 1.2 `mipa-mius-apr-fifo-bridge`
- **What**: MIUS (Multi-Interface Ultrasound System) APR (Audio Processing Router) FIFO bridge for ultrasound data path.
- **Files touched**: techpack/audio/ or sound/soc/ (verify exact paths)
- **Commit message**: `fix(ultrasound): add MIUS APR FIFO bridge`

### 1.3 `mipa-us-prox-iio-keepalive`
- **What**: Ultrasound proximity sensor IIO keepalive mechanism to prevent sensor timeout.
- **Files touched**: drivers/iio/ or drivers/misc/ (verify exact paths)
- **Commit message**: `fix(ultrasound): add US proximity IIO keepalive`

### 1.4 `mipa-us-prox-read-raw`
- **What**: Raw read capability for ultrasound proximity sensor.
- **Files touched**: drivers/iio/ or drivers/misc/ (verify exact paths)
- **Commit message**: `fix(ultrasound): add US proximity raw read support`

### Application procedure
For each patch:
```bash
git apply --check patches/ultrasound/<patch>.patch  # dry-run
# If clean:
git am patches/ultrasound/<patch>.patch
# If conflicts: resolve, then git am --continue
```

**Contingency**: If patches conflict on `android16-aptusitu-new` (unlikely since old base was also AstideLabs), manually locate the equivalent driver files and apply the changes by hand. The patch contents are small and focused.

## 2. Stability Patches

**Source**: `raz123/android_kernel_redalpha:patches/stability/` (2 unique files + duplicates of ultrasound patches — skip duplicates)

### 2.1 `mipa-swr-fifo-overflow-fix`
- **What**: Fix SoundWire RX FIFO overflow that causes audio glitches/pops.
- **Files touched**: drivers/soundwire/ (verify exact path)
- **Commit message**: `fix(audio): prevent SoundWire RX FIFO overflow`
- **Size**: ~4.6KB

### 2.2 `mipa-bq2597x-silence-dump`
- **What**: Suppress bq2597x charger IC register dump that floods dmesg with debug spam.
- **Files touched**: drivers/power/supply/qcom/bq2597x* (verify exact path)
- **Commit message**: `fix(charging): silence bq2597x register dump in dmesg`
- **Size**: ~2.9KB

## 3. Performance Patches

**Source**: `raz123/android_kernel_redalpha:patches/performance/` (3 files)

### 3.1 `mipa-mius-diagnostic-logging`
- **What**: MIUS diagnostic logging for debugging ultrasound.
- **Files touched**: drivers/misc/ or drivers/mius/ (verify exact path)
- **Commit message**: `feat(ultrasound): add MIUS diagnostic logging`

### 3.2 `mipa-schedtune-increase-groups`
- **What**: Increase schedtune cgroup groups from 5 to 7 for finer-grained boosting control.
- **Files touched**: kernel/sched/tune.c or similar (verify exact path)
- **Commit message**: `perf(sched): increase schedtune groups from 5 to 7`
- **Size**: ~383 bytes (very small)

### 3.3 `mipa-vidc-dsilog-level`
- **What**: Reduce VIDC (video decoder) logging verbosity to reduce dmesg spam.
- **Files touched**: techpack/video/msm/vidc/ (verify exact path)
- **Commit message**: `perf(video): reduce VIDC log level`
- **Size**: ~555 bytes

## 4. Audio CS35L41 QUAT_TDM Fix

**Source**: Commit `cae9918a6d6edff124f2faa1e8924009bfec82b9` from old redalpha.

### What it does
Moves the CS35L41 smart speaker amplifier from TERT_TDM RX to QUAT_TDM TX on alioth only. The TERTIARY LPASS serial interface is needed for echo cancellation reference signal. Moving the amp to QUAT_TDM frees TERT_TDM for EC.

### Files changed (verify from commit diff):
- `techpack/audio/asoc/kona.c` or similar machine driver — change CS35L41 dai_link from TERT_TDM to QUAT_TDM
- Add `#ifdef CONFIG_MACH_XIAOMI_ALIOTH` guard around the change
- Exclude `QUAT_TDM_RX_0` stub codec from base TDM BE array for alioth to avoid name collision

### Cherry-pick procedure
```bash
# From the old redalpha repo (if cloned locally):
git remote add old-redalpha https://github.com/raz123/android_kernel_redalpha.git
git fetch old-redalpha android16-aptusitu
git cherry-pick cae9918a6d6edff124f2faa1e8924009bfec82b9
```
**Contingency**: If the file structure differs on `android16-aptusitu-new` (AstideLabs rebuilt from lineage-20), locate the equivalent ASoC machine driver file and apply the change manually. The key logic is:
1. Find where CS35L41 dai_link is defined (search for "cs35l41" in techpack/audio/)
2. Change its TDM interface from TERT_TDM to QUAT_TDM
3. Guard with `#ifdef CONFIG_MACH_XIAOMI_ALIOTH`
4. Exclude QUAT_TDM_RX_0 from the base TDM array for alioth

## 5. Defconfig Customization

After applying all patches, customize `arch/arm64/configs/alioth_defconfig`:
- `CONFIG_LOCALVERSION="-redalpha3-perf"` (override AstideLabs `-aptusitu-perf`)
- `CONFIG_KSU=y`
- `CONFIG_KSU_MANUAL_HOOK=y`
- `CONFIG_LTO_NONE=y`
- `# CONFIG_LTO_CLANG is not set`

Keep all AstideLabs features (WALT, BPF, EROFS, F2FS, CAN, USB serial, WireGuard, etc.) — only change localversion and KSU/LTO settings.

## 6. Release & Verification

- Build via `kernel-build.yml` workflow
- Flash on Poco F3
- **Gate checks**:
  - `dmesg | grep -i "ch101\|ultrasound\|prox"` shows sensor initialization
  - Proximity sensor works (screen off during call, wakes when moved away)
  - CS35L41 speaker output works (play audio, hear from bottom speaker)
  - Audio EC works (make a call, no echo heard by other party)
  - No bq2597x register dump in `dmesg` (no repeated hex dumps)
  - `uname -r` shows `4.19.325-redalpha3-perf`
  - All Phase 1 features still work (ReSukiSU, root)
