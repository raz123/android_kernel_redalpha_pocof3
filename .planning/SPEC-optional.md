# SPEC: Optional Enhancements (Phase 4)

**GATE**: Each option requires explicit user approval before implementation. Do NOT proceed with any option without the user saying "yes" to that specific option.

## Option A: PD Charging Bypass

**Source**: `SD870/kernel_xiaomi_sm8250`

### What it does
Allows forcing USB-PD charging protocol with unofficial/non-compliant chargers while keeping safety limits (voltage, current, temperature) enforced by the PMIC. Useful for chargers that don't negotiate PD correctly but can deliver power.

### Files touched
- `drivers/power/supply/qcom/` — PD policy engine
- Probably a small patch to the USB PD stack

### Risk
Low. The safety limits remain enforced by hardware PMIC. Only affects PD negotiation.

### Decision needed
Does the user experience charging issues with non-Xiaomi chargers? If yes, apply. If no, skip.

---

## Option B: Flicker Kernel's KernelSU Anti-Detection

**Source**: `Flicker-Android-Devices/kernel_xiaomi_sm8250`

### What it does
- Faked lineage paths/symlinks (hides custom kernel from detection)
- jit-zygote-cache flags (avoids detection via app runtime behavior)
- seccomp improvements (hardens syscall filtering)

### Files touched
- Various kernel source files — need to locate specific commits in Flicker's repo
- Note: Flicker uses PELT, but these anti-detection patches are scheduler-agnostic

### Risk
Medium. Anti-detection patches can break compatibility with certain apps or SafetyNet/Play Integrity. Test thoroughly.

### Decision needed
Does the user need root-hiding beyond what ReSukiSU's SuSFS provides? ReSukiSU v4.1.0 already has SuSFS with uname spoofing, cmdline spoofing, and symbol hiding.

---

## Option C: Battery 1% Fix

**Source**: `liyafe1997/kernel_xiaomi_sm8250_mod`

### What it does
Fixes the infamous Xiaomi battery stuck-at-1% bug. Adds a voltage threshold check (3700mV) in `qpnp-fg-gen4.c` fuel gauge driver to exit the `rapid_soc_dec` (rapid SoC decrease) state when battery voltage recovers.

### Files touched
- `drivers/power/supply/qcom/qpnp-fg-gen4.c` — `fg_gen4_get_prop_soc_scale()` function

### Risk
Low. The fix is well-documented and widely used (328 stars, 120 forks on liyafe1997's repo). Only activates when voltage is above 3700mV.

### Pre-check
The AstideLabs base may already have a different battery fix. Check `drivers/power/supply/qcom/qpnp-fg-gen4.c` for any existing `rapid_soc_dec` modifications on the base before applying.

### Decision needed
Has the user experienced the 1% battery bug on their device? If yes (or if they want it as a preventative), apply.

---

## Option D: FUSE_BPF Revert

**Source**: `Rve27/android_kernel_xiaomi_sm8250`

### What it does
Reverts FUSE_BPF (BPF-based FUSE) from the kernel. FUSE_BPF has been known to break camera and storage on some ROMs.

### Files touched
- `fs/fuse/` — revert BPF-related changes
- Possibly defconfig to disable `CONFIG_FUSE_BPF`

### Risk
Medium. Only needed if the target ROM shows camera or storage issues. Reverting FUSE_BPF may break features on ROMs that depend on it.

### Decision needed
Does the user's target ROM (ArrowOS-MiPa-Edition for Poco F3) have camera/storage issues with this kernel? Test first before deciding.

---

## Option E: Redline Kernel Power Supply Fixes

**Source**: `PocoF3Releases/kernel_xiaomi_sm8250`

### What it does
Fixes for power supply ICs on alioth:
- bq2597x charger IC
- smb1398 charge pump
- ln8000 (possibly wireless charger)

### Files touched
- `drivers/power/supply/qcom/bq2597x*`
- `drivers/power/supply/qcom/smb1398*`
- Possibly DTS changes

### Risk
Low for specific fixes, but need to verify they don't conflict with Phase 2's `mipa-bq2597x-silence-dump` patch. Deduplicate if overlap exists.

### Decision needed
Does the user experience charging issues (slow charging, overheating, charge stopping early)?

---

## Option F: KosminorKernel I/O Schedulers

**Source**: `KopsourcesORG/KosminorKernel-Alioth`

### What it does
Adds custom I/O schedulers:
- Maple (Samsung's governor-based scheduler, balanced)
- SIO (Simple I/O, minimal overhead)
- FIOPS (Fair IO Per Second, flash-optimized) — set as default
- Zen (fairness-focused)

### Files touched
- `block/` — new scheduler files
- `block/Kconfig.iosched` — config entries
- `block/Makefile` — build entries
- Defconfig to set default

### Risk
Low. These are well-tested I/O schedulers from the Android custom kernel ecosystem. Only minor Kconfig/Makefile additions.

### Decision needed
Does the user want more I/O scheduler options? AstideLabs base has BFQ/CFQ. These add flash-optimized alternatives.

---

## Implementation if Approved

For each approved option:
1. Cherry-pick the relevant commits from the source repo
2. Resolve any conflicts with the current tree
3. Build and test on device
4. Run the council-review-2yea workflow (3 rounds) before merging
