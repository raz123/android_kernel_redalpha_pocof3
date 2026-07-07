# Potential Imports — Complete Index

**Date:** 2026-07-07 | **Kernel:** 4.19.325 | **Device:** Poco F3 (SM8250)
**Repos scanned:** 22 | **Total patches identified:** 100+
**Evaluation complete:** 2026-07-07

---

## Import Files — Final Status

| File | Source | Priority | Status | Reason |
|---|---|---|---|---|
| `cpumask-builtin-helpers.md` | Kosminor (Sultan Alsawaf) | P2 MEDIUM | ✅ Shipped b171 | Real win — NR_CPUS=8 ≤ BITS_PER_LONG=64 |
| `ufs-write-booster.md` | PocoF3Releases | P1 HIGH | ⏭️ Already in tree | WB gate already has 0x300 + 0x220 at line 8607 |
| `lib-string-optimizations.md` | Danda420 + kvsnr113 | P2 MEDIUM | ✅ Shipped b171 | Dead code on ARM64 (arch overrides active) |
| `int-sqrt-optimization.md` | Danda420 + kvsnr113 | P3 LOW | ✅ Shipped b171 | 3x faster integer sqrt |
| `power-efficient-workqueue.md` | Kosminor | P2 MEDIUM | ✅ Shipped b171 | WQ_POWER_EFFICIENT defaults OFF — inert unless opted in |
| `vmscan-critical-process.md` | EmanuelCN + kvsnr113 | P2 MEDIUM | ✅ Shipped b171 | Protect display composer (oom_score_adj ≤ -900) |
| `zram-lz4-dictionary.md` | GustavoMends | P2 MEDIUM | ⏭️ Deferred | Needs architecture port — our zram uses crypto API backends |
| `rcu-boot-only-expedited.md` | Kosminor | P2 MEDIUM | ✅ Shipped b171 | Standard Android pattern |
| `drm-atomic-latency.md` | Kosminor | P2 MEDIUM | ✅ Shipped b171 | PM QOS cap on ioctl duration |
| `zram-bugfixes.md` | Danda420 + kvsnr113 | P1 HIGH | ⏭️ Already in tree | Our entry-based dedup architecture doesn't have these bugs |
| `sched-fair-fixes.md` | kvsnr113 + GustavoMends | P1 HIGH | ⏭️ Incompatible | Target EEVDF scheduler — we have CFS+WALT |
| `display-panel-reset.md` | PocoF3Releases | P2 MEDIUM | ⏭️ Not evaluated | Low priority — deferred |
| `cs35l41-xlog-removal.md` | LineageOS | P3 LOW | ✅ Shipped b171 | Deleted send_data_to_xlog.c/h (-1215 lines) |
| `mglru.md` | Upstream (Yu Zhao, Google) | DEFERRED | ⏭️ Not applicable | No 4.19 backport exists; UtsavBalar1231 tried and removed it |

---

## Evaluation Summary

| Status | Count | Details |
|---|---|---|
| ✅ Shipped (b171) | 9 | lib/string, sqrt, cpumask, workqueue, vmscan, DRM, RCU, xlog removal |
| ⏭️ Already in tree | 3 | UFS write booster, zram bugfixes (×4), cpumask |
| ⏭️ Incompatible | 1 | sched-fair-fixes (EEVDF vs CFS+WALT) |
| ⏭️ Deferred | 2 | zram LZ4 dictionary (arch port), MGLRU (no 4.19 backport) |
| ⏭️ Not evaluated | 1 | display-panel-reset (low priority) |

**All HIGH priority imports evaluated. No actionable items remaining.**

---

## PR Strategy (Historical)

One PR per import. Each is independent, small, and can be tested/reverted individually.

### Tier 1 — Import First (HIGH priority, LOW risk)
1. ~~`import/ufs-write-booster`~~ — Already in tree
2. ~~`import/zram-bugfixes`~~ — Already in tree
3. ~~`import/sched-fair-fixes`~~ — Incompatible (EEVDF vs CFS+WALT)

### Tier 2 — Import Next (MEDIUM priority, LOW risk)
4. ~~`import/lib-string-optimizations`~~ — Shipped b171
5. ~~`import/power-efficient-workqueue`~~ — Shipped b171
6. ~~`import/vmscan-critical-process`~~ — Shipped b171
7. `import/zram-lz4-dictionary` — Deferred (needs architecture port)
8. ~~`import/rcu-boot-only-expedited`~~ — Shipped b171
9. ~~`import/cpumask-builtin-helpers`~~ — Shipped b171
10. `import/display-panel-reset` — Not evaluated (low priority)

### Tier 3 — Import When Ready (LOW priority, LOW risk)
11. ~~`import/drm-atomic-latency`~~ — Shipped b171
12. ~~`import/cs35l41-xlog-removal`~~ — Shipped b171
13. ~~`import/int-sqrt-optimization`~~ — Shipped b171

---

## Repos Scanned (22 total)

| Repo | Key Contributions | Rating |
|---|---|---|
| `EmanuelCN/kernel_xiaomi_sm8250` | cpufreq cubic, EEVDF, f2fs, binder, vmscan | PRIMARY SOURCE |
| `Danda420/kernel_xiaomi_sm8250` | Kcompressd, memcpy optimizations, IPA panic fix | STRONG CANDIDATE |
| `KopsourcesORG/KosminorKernel-Alioth` | cpumask, SLUB, workqueue, RCU, display | STRONG CANDIDATE |
| `kvsnr113/xiaomi_sm8250_kernel_e404` | sched/fair fixes, vmscan, zram, CASS | STRONG CANDIDATE |
| `PocoF3Releases/kernel_xiaomi_sm8250` | UFS write booster, display panel, build fixes | GOOD SOURCE |
| `LineageOS/android_kernel_qcom_sm8250` | LTO/CFI/KFENCE configs, cs35l41 xlog | SELECTIVE |
| `GustavoMends/kernel_xiaomi_alioth` | cpufreq cubic, zram LZ4, scheduler fixes | GOOD SOURCE |
| `ltlly/android_kernel_xiaomi_sm8250-bpf-research` | BPF research, UFS write booster source | GOOD SOURCE |
| `kvsnr113/xiaomi_sm8250_kernel` | lib/string optimizations, BORE scheduler | GOOD SOURCE |
| `dtrail/nethunter_kernel_xiaomi_sm8250` | Burst headroom, PELT prediction | GOOD SOURCE |
| `Flicker-Android-Devices/kernel_xiaomi_sm8250` | Build fixes, BPF, IPv6 | SELECTIVE |
| `SD870/kernel_xiaomi_sm8250` | BPF security fixes | SELECTIVE |
| `crdroidandroid/android_device_xiaomi_sm8250-common` | Signal overlay, BLE fix, WiFi 6 | SELECTIVE |
| `TIMISONG-dev/kernel_xiaomi_sm8250` | KernelSU, SUSFS | SELECTIVE |
| `YangQi0408/kernel_xiaomi_sm8250_mod` | BPF UAF fix (critical) | SELECTIVE |
| `PixelLineage/kernel_xiaomi_sm8250` | vidc CFI fix, display fixes | SELECTIVE |
| `ApartTUSITU/kernel_xiaomi_sm8250_mod` | Fork of TIMISONG | SKIP |
| `Rve27/android_kernel_xiaomi_sm8250` | cpufreq min/max fix | SELECTIVE |
| `liyafe1997/kernel_xiaomi_sm8250_mod` | UFS write booster | SELECTIVE |
| `UJX6N/bbrplus-4.19` | No actionable patches | SKIP |
| `xyz219888/kernel_xiaomi_sm8250_mod` | Build script updates only | SKIP |
| `ltlly/alioth-kernel-research` | Companion docs | SKIP |

---

## Already Shipped (not in potential-imports)

| Build | Fixes |
|---|---|
| b151 | cs35l41 PDN poll removal |
| b156 | FG debug spam fix |
| b160 | DS28E16, IRQ affinity, VM tuning, DEBUG_KERNEL |
| b162 | ReSukiSU vm_tuning module |
| b165 | Smack heap overflow, binder dbitmap |
| b168 | SLUB hardening, f2fs RT priority |
| b171 | 9 performance imports (lib/string, cpumask, workqueue, vmscan, RCU, DRM, xlog removal) |

---

## Additional Research Completed

| Topic | Result |
|---|---|
| MGLRU backport (UtsavBalar1231) | Was in release 4.0.0, removed by 5.0.0 — stability issues on SM8250 |
| RTMM delta (UtsavBalar1231) | Identical to our tree — zero incremental value |
| MI_RECLAIM | Separate subsystem already in our tree — complements RTMM |
| EEVDF scheduler patches | Incompatible — our tree uses CFS+WALT, not EEVDF |
