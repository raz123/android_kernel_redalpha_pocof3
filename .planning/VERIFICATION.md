# VERIFICATION: Gates & Test Procedures

## Per-Phase Verification Gates

### CI Pipeline (before any builds)

| # | Check | Command/Procedure | Expected |
|---|-------|-------------------|----------|
| CI.1 | Dockerfile builds | `docker build -t kernel-builder:test .` in repo root | Image builds without error |
| CI.2 | docker-build workflow | Trigger `docker-build.yml`, check GHCR | `ghcr.io/raz123/kernel-builder:latest` pushed |
| CI.3 | kernel-build with KSU=0 | Trigger `kernel-build.yml` with `ksu=false` | Build succeeds, artifacts uploaded |
| CI.4 | kernel-build with KSU=1 | Trigger `kernel-build.yml` with `ksu=true` | Build succeeds, all QA gates pass |
| CI.5 | anykernel3-package | Trigger `anykernel3-package.yml` | ZIP artifact produced |
| CI.6 | release workflow | Trigger `release.yml` | GitHub Release created with tag |

### Baseline Gate (vanilla build, KSU=0)

| # | Check | Command/Procedure | Expected |
|---|-------|-------------------|----------|
| B.1 | Kernel boots | Flash vanilla ZIP, reboot | Device reaches home screen |
| B.2 | Kernel version | `uname -r` | `4.19.325` (no suffix) |
| B.3 | Audio EC (critical) | Phone call, ask other party about echo | No echo heard |
| B.4 | Speaker | Play music/video | Sound from bottom speaker |
| B.5 | WiFi/BT/Mobile | Connect, pair, use data | All function |
| B.6 | No kernel panics | `adb shell dmesg \| grep -i "BUG\|Oops\|panic"` | Empty |
| B.7 | Overnight idle (optional) | Leave overnight | No spontaneous reboots |

**If B.3 fails**: Stop. The vanilla base does not fix Audio EC. Re-evaluate base branch.


### Phase 1 — Foundation

| # | Check | Command/Procedure | Expected |
|---|-------|-------------------|----------|
| 1.1 | Kernel boots | Flash ZIP, reboot | Device reaches home screen |
| 1.2 | Kernel version | `uname -r` | `4.19.325-redalpha3-perf` |
| 1.3 | ReSukiSU version | Open ReSukiSU manager app | Shows v4.1.0 "Installed" |
| 1.4 | Root access | `adb shell` then `su -c 'id'` | `uid=0(root) gid=0(root)` |
| 1.5 | SuSFS symbols | `adb shell cat /proc/kallsyms \| grep susfs` | Multiple susfs symbols present |
| 1.6 | Audio EC (critical) | Make a phone call, ask other party about echo | No echo heard |
| 1.7 | Speaker | Play music/video | Sound from bottom speaker |
| 1.8 | Basic sensors | Auto-rotate, brightness, proximity during call | All function normally |
| 1.9 | WiFi/BT | Connect to WiFi, pair BT device | Both work |
| 1.10 | Deep sleep | Leave device idle 5 min, check `dmesg \| grep suspend` | Device enters suspend |

### Phase 2 — Own Fixes

| # | Check | Command/Procedure | Expected |
|---|-------|-------------------|----------|
| 2.1 | Ultrasound sensor init | `adb shell dmesg \| grep -i "ch101\|mius\|ultrasound"` | Sensor initialized, no errors |
| 2.2 | Proximity sensor | Make call, cover top of screen | Screen turns off |
| 2.3 | Proximity wake | Uncover top of screen during call | Screen turns on |
| 2.4 | CS35L41 speaker | Play audio at various volumes | Clear sound, no distortion |
| 2.5 | Audio EC (re-verify) | Phone call echo test | Still no echo |
| 2.6 | No bq2597x spam | `adb shell dmesg \| grep bq2597x` | No register dump hex lines (init messages OK) |
| 2.7 | No SoundWire errors | `adb shell dmesg \| grep -i "swr\|soundwire\|fifo"` | No overflow/underflow errors |
| 2.8 | Schedtune groups | `adb shell cat /dev/stune/top-app/schedtune.boost` | Works (value writable) |
| 2.9 | VIDC quiet | `adb shell dmesg \| grep -c vidc` | Significantly fewer vidc messages than without patch |
| 2.10 | All Phase 1 gates | Re-run Phase 1.1–1.10 | All still pass |

### Phase 3 — Imported Fixes

| # | Check | Command/Procedure | Expected |
|---|-------|-------------------|----------|
| 3.1 | BBRplus available | `adb shell cat /proc/sys/net/ipv4/tcp_available_congestion_control` | Includes `bbrplus` |
| 3.2 | BBRplus functional | `adb shell 'echo bbrplus > /proc/sys/net/ipv4/tcp_congestion_control && cat /proc/sys/net/ipv4/tcp_congestion_control'` | `bbrplus` |
| 3.3 | ZRAM writeback | `adb shell cat /sys/block/zram0/backing_dev` | File exists (may be empty if no backing dev configured) |
| 3.4 | ZRAM memory tracking | `adb shell cat /sys/block/zram0/mm_stat` | Shows stats (orig_data_size, compr_data_size, etc.) |
| 3.5 | No ipa_uc panic | Leave device idle overnight, check `adb shell dmesg \| grep -i "ipa_uc\|panic\|Kernel panic"` | No panic |
| 3.6 | DVFS headroom | `adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` while idle vs load | Frequency scales smoothly, no spikes |
| 3.7 | No scheduler crashes | `adb shell dmesg \| grep -i "sched\|fair\|BUG\|WARNING"` | No scheduler BUG/WARNING |
| 3.8 | Security hardening | `adb shell cat /proc/self/attr/current` | SELinux context shown (not "unconfined") |
| 3.9 | All Phase 2 gates | Re-run Phase 2.1–2.10 | All still pass |
| 3.10 | All Phase 1 gates | Re-run Phase 1.1–1.10 | All still pass |

## CI QA Gates (from android-kernel-cicd-pipeline skill)

All gates are implemented in `kernel-build.yml`. Below are the manual verification equivalents.

| Gate | Check | Command | Pass Condition | KSU-only |
|------|-------|---------|----------------|----------|
| 0 SuSFS | Source scan | `grep -r "CONFIG_KSU_SUSFS\|ksu_susfs\|susfs_" drivers/kernelsu/` | Must find matches | Yes |
| 1 Hook mode | Defconfig | `grep CONFIG_KSU_MANUAL_HOOK arch/arm64/configs/alioth_defconfig` | `=y` | Yes |
| 2 KALLSYMS | Defconfig | `grep CONFIG_KALLSYMS arch/arm64/configs/alioth_defconfig` | Both `=y` | No |
| 3 SELinux | Defconfig | `grep CONFIG_SECURITY_SELINUX arch/arm64/configs/alioth_defconfig` | `=y`, not `=n` | No |
| 4 Binder | Defconfig | `grep CONFIG_ANDROID_BINDER arch/arm64/configs/alioth_defconfig` | `=y` | No |
| 5 DTBO | DTS scan | `grep -ri "dtbo" arch/arm64/boot/dts/vendor/qcom/` | Empty (Qualcomm uses dtb) | No |
| 6 Boot image size | Binary | `stat -c%s out/Image.gz-dtb` | > 15728640 (15MB) | No |
| 7 Size budget | Binary | Same as Gate 6 | Warn if > 26214400 (25MB) | No |
| 8 Changelog | File | `test -f CHANGELOG.md` | Warn if missing | No |
2. Backup current boot partition: `adb shell dd if=/dev/block/by-name/boot_a of=/sdcard/boot_backup.img`
3. Flash new AnyKernel3 ZIP
4. Wipe cache/dalvik (optional but recommended)

### After Each Flash
1. Wait for full boot (up to 2 minutes first boot)
2. Run Phase-specific verification gates above
3. Test daily-use scenarios:
   - Phone call (incoming and outgoing) — check audio EC
   - WiFi + mobile data
   - Bluetooth audio
   - Camera (front + back, photo + video)
   - GPS lock (use Maps or GPS Test app)
   - Charging (plug/unplug, check charge rate)
   - Fingerprint sensor
   - 30+ minutes screen-on use (no random reboots)
4. If any gate fails: restore backup boot image, diagnose, fix, retest

### Rollback Procedure
```bash
# In TWRP:
adb push boot_backup.img /tmp/
adb shell dd if=/tmp/boot_backup.img of=/dev/block/by-name/boot_a
adb reboot
```

## Council Review Integration

Each phase gets 3 rounds of `council-review-2yea` before release:
- Run the review workflow against the phase's commit range
- Each round requires 2 YEA votes to pass
- Fix any NAY issues before re-running
- Track results in phase commit messages: `review: council round N/3 passed (2 YEA, 0 NAY)`
