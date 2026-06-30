# SPEC: Imported Fixes — Ecosystem Cherry-Picks (Phase 3)

## Source Repos

| Source | Repo URL | Branch | What to take |
|--------|----------|--------|--------------|
| UJX6N | `UJX6N/bbrplus-4.19` | master | BBRplus TCP congestion control |
| Danda420 | `Danda420/kernel_xiaomi_sm8250` | bpf | ZRAM backports, ipa_uc suspend fix, scheduler fixes |
| dtrail | `dtrail/nethunter_kernel_xiaomi_sm8250` | staging | Cubic DVFS headroom, scheduler fixes |
| kvsnr113 | `kvsnr113/xiaomi_sm8250_kernel` | (main) | lib/string optimizations, V-002 security, binder fix |

## 1. BBRplus TCP Congestion Control

**Source**: `UJX6N/bbrplus-4.19`

### What it is
Enhanced BBR TCP congestion control with ACK aggregation compensation, long-term bandwidth estimator, and token-bucket policer detection. Coexists with stock `tcp_bbr`.

### Files to create/modify

#### 1.1 New file: `net/ipv4/tcp_bbrplus.c`
- Copy the 1187-line file from the upstream patch.
- Verify it compiles as a standalone module (`obj-$(CONFIG_TCP_CONG_BBRPLUS)`).

#### 1.2 Modify: `net/ipv4/Makefile`
Add after the `tcp_bbr.o` line:
```
obj-$(CONFIG_TCP_CONG_BBRPLUS) += tcp_bbrplus.o
```

#### 1.3 Modify: `net/ipv4/Kconfig`
Add after the existing BBR config block:
```
config TCP_CONG_BBRPLUS
	tristate "BBRplus TCP"
	default y
	---help---
	BBRplus is an enhanced variant of BBR (Bottleneck Bandwidth and RTT)
	TCP congestion control. It adds ACK aggregation compensation,
	a longer-term bandwidth estimator, and better policer detection.

choice
	prompt "Default TCP congestion control"
	default DEFAULT_BBRPLUS
	# ... add BBRPLUS option here ...
```
**Note**: The upstream patch changes the default CC to bbrplus. Do NOT do this — keep CUBIC as default. Only make BBRplus *available*, not default. The user can switch via sysctl:
```
echo bbrplus > /proc/sys/net/ipv4/tcp_congestion_control
```

#### 1.4 Modify: `include/net/tcp.h`
In `struct tcp_congestion_ops`, add a new callback:
```c
/* hook for bbrplus to override TSO segment goal (optional) */
u32 (*tso_segs_goal)(struct sock *sk);
```
Also export `tcp_tso_autosize` declaration:
```c
u32 tcp_tso_autosize(const struct sock *sk, unsigned int mss_now, int min_tso_segs);
```

#### 1.5 Modify: `net/ipv4/tcp_output.c`
Change `tcp_tso_autosize()` from `static` to non-static (remove `static` keyword).

#### 1.6 Modify: `include/net/inet_connection_sock.h`
In `struct inet_connection_sock`, change:
```c
u64 icsk_ca_priv[104 / sizeof(u64)];  // BEFORE (13 slots)
```
to:
```c
u64 icsk_ca_priv[112 / sizeof(u64)];  // AFTER (14 slots for larger BBRplus state)
```

### Defconfig
Add to `arch/arm64/configs/alioth_defconfig`:
```
CONFIG_TCP_CONG_BBRPLUS=y
```

### Contingency if conflicts
- The patch targets mainline 4.19. Android's TCP stack is nearly identical at this level.
- If `tcp_output.c` differs significantly, the `tcp_tso_autosize` export is the only change needed — manually verify the function signature matches.
- If `tcp.h` already has fields in that position, add `tso_segs_goal` at the end of `tcp_congestion_ops`.
- If `inet_connection_sock.h` struct layout is different, find `icsk_ca_priv` and bump the array size by 8 bytes.

## 2. ZRAM Backports from Danda420

**Source**: `Danda420/kernel_xiaomi_sm8250`, branch `bpf`

### 2.1 Identify commits to cherry-pick
Browse Danda420's `drivers/block/zram/` commit history. Target these specific improvements:
- Custom compression backends API (lzo/lzorle, lz4, lz4hc, zstd, zlib, 842)
- ZRAM disksize config restore fix
- OOM NULL ptr fix

### 2.2 Cherry-pick procedure
```bash
git remote add danda420 https://github.com/Danda420/kernel_xiaomi_sm8250.git
git fetch danda420 bpf
# For each identified commit SHA:
git cherry-pick <sha>
```

### 2.3 Defconfig additions
```
CONFIG_ZRAM_WRITEBACK=y
CONFIG_ZRAM_MEMORY_TRACKING=y
CONFIG_ZRAM_DEF_COMP_LZ4=y  # may already be set
```

### Contingency
- The Danda420 kernel is CLO-based (CodeLinaro). Our base is LineageOS-based. The zram driver (`drivers/block/zram/`) is an upstream Linux driver — should be nearly identical.
- If zram commits don't cherry-pick cleanly, focus on the OOM fix and disksize restore (highest value, smallest diffs). Skip the custom compression backend API if it's too invasive.

## 3. ipa_uc Suspend Panic Fix

**Source**: `Danda420/kernel_xiaomi_sm8250`

### What it does
Bypasses uC debug stats allocation in `drivers/ipa/ipa_uc/` to prevent kernel panic during suspend-to-idle. The debug stats allocation can fail or cause issues when the IPA (IP Accelerator) power collapses.

### Cherry-pick
Locate the specific commit in Danda420's repo (`drivers/ipa/ipa_uc/` path). Apply directly:
```bash
git cherry-pick <sha>
```

### Verification
Leave device idle overnight (screen off, not charging). Check `dmesg` in the morning — no "ipa_uc" panic or crash messages.

## 4. DVFS Headroom Improvements

**Source**: `dtrail/nethunter_kernel_xiaomi_sm8250`, branch `staging`

### Target commits (in this order)
1. `646c98b` — Replace quadratic headroom with normalized cubic curve
2. `28f4bda` — Precomputed LUT for DVFS
3. `93894eb` — Suppress low-util boosting
4. `15ded9e` — Burst headroom

### Files affected
- `kernel/sched/cpufreq_schedutil.c` — main DVFS governor logic
- `include/trace/events/sched.h` — possibly trace events

### WALT compatibility
These patches operate at the cpufreq governor level — they're scheduler-agnostic. However, the nethunter kernel uses PELT. Key WALT differences per walt-pelt-porting skill:
- **DO NOT modify `map_util_freq()`** — WALT's 1.25x headroom (`freq + (freq >> 2)`) lives there.
- **Apply headroom to `util` BEFORE it enters `map_util_freq()`** — not after.
- If a patch references `sugov_effective_cpu_perf()`, `apply_dvfs_headroom()`, or `approximate_util_avg()`, these do NOT exist in WALT. Rewrite that logic inline.
- If a patch uses `use_pelt()`, it returns `false` under WALT — the PELT branch is dead code. Remove or guard with `#ifndef CONFIG_SCHED_WALT`.

### Cherry-pick procedure
```bash
git remote add nethunter https://github.com/dtrail/nethunter_kernel_xiaomi_sm8250.git
git fetch nethunter staging
git cherry-pick 646c98b  # cubic headroom
# Resolve WALT conflicts (see above)
git cherry-pick 28f4bda  # precomputed LUT
git cherry-pick 93894eb  # low-util suppression
git cherry-pick 15ded9e  # burst headroom
```

### Contingency
If WALT adaptation is too complex for the cubic headroom patch, skip it. Apply only the low-util suppression (`93894eb`) and burst headroom (`15ded9e`) which are simpler.

## 5. Scheduler Fixes

**Source**: Both Danda420 and Nethunter

### 5.1 Danda420 scheduler improvements
- `sched/fair`: nohz CPU tracking (cpumask weight) — cherry-pick if commit is clean
- `sched/cass`: LLC cache affinity — evaluate for WALT. If it references PELT structs, skip.
- `mm/vmscan`: skip reclaim throttle on critical processes — scheduler-agnostic, safe to cherry-pick
- OOM scoring for binder tasks — safe to cherry-pick

### 5.2 Nethunter scheduler fixes (from staging branch)
These are CFS `fair.c` fixes — not scheduler-class specific:
- Overflow in `enqueue_entity`
- Negative lag during delayed dequeue
- `avg_vruntime` fix
- `zero_vruntime` fix

Cherry-pick each, verify `kernel/sched/fair.c` applies cleanly. These are bug fixes, not features.

### Skip
- `CONFIG_SCHED_CASS` — PELT-specific
- `CONFIG_UCLAMP_TASK` — PELT-specific
- Nethunter's `CONFIG_POWERSAFE_TOGGLE` — invasive, PELT-dependent

## 6. Security & Optimization Patches

**Source**: `kvsnr113/xiaomi_sm8250_kernel`

### 6.1 lib/string optimizations
- Optimized `memcpy` and `memmove` (these were already cherry-picked in old redalpha)
- Locate the specific commits in kvsnr113's repo and cherry-pick directly

### 6.2 V-002 strcat/strcpy security
- Hardening for unsafe string functions
- Cherry-pick from kvsnr113

### 6.3 binder dbitmap double-free fix
- Already in old redalpha
- Locate the upstream or kvsnr113 commit and cherry-pick

### Cherry-pick procedure
```bash
git remote add kvsnr113 https://github.com/kvsnr113/xiaomi_sm8250_kernel.git
git fetch kvsnr113
git cherry-pick <sha1> <sha2> <sha3>  # identify exact SHAs from old redalpha's cherry-pick history
```

## 7. Release & Verification

- Build via CI pipeline
- Flash on device
- **Gate checks**:
  - `cat /proc/sys/net/ipv4/tcp_available_congestion_control` includes `bbrplus`
  - `cat /sys/block/zram0/backing_dev` and writeback stats exist
  - Overnight idle: no ipa_uc panic, no unexpected reboots
  - All Phase 2 features still work (ultrasound, audio EC, ReSukiSU)
  - `uname -r` still shows `4.19.325-redalpha3-perf`
