# Potential Imports — Complete Index

**Date:** 2026-07-07 | **Kernel:** 4.19.325 | **Device:** Poco F3 (SM8250)
**Repos scanned:** 22 | **Total patches identified:** 100+

---

## Import Files

| File | Source | Priority | Risk | Impact |
|---|---|---|---|---|
| `cpumask-builtin-helpers.md` | Kosminor (Sultan Alsawaf) | P2 MEDIUM | LOW | Scheduler hot-path optimization |
| `ufs-write-booster.md` | PocoF3Releases | P1 HIGH | LOW | 75% write speed improvement |
| `lib-string-optimizations.md` | Danda420 + kvsnr113 | P2 MEDIUM | LOW | memcpy/memset +52-72% |
| `int-sqrt-optimization.md` | Danda420 + kvsnr113 | P3 LOW | LOW | 3x faster integer sqrt |
| `power-efficient-workqueue.md` | Kosminor | P2 MEDIUM | LOW | Battery life improvement |
| `vmscan-critical-process.md` | EmanuelCN + kvsnr113 | P2 MEDIUM | LOW | Reduces UI jank |
| `zram-lz4-dictionary.md` | GustavoMends | P2 MEDIUM | HIGH | Better compression (needs architecture port) |
| `rcu-boot-only-expedited.md` | Kosminor | P2 MEDIUM | LOW | Power savings |
| `drm-atomic-latency.md` | Kosminor | P2 MEDIUM | LOW | Display latency reduction |
| `zram-bugfixes.md` | Danda420 + kvsnr113 | P1 HIGH | LOW | Crash fixes |
| `sched-fair-fixes.md` | kvsnr113 + GustavoMends | P1 HIGH | MEDIUM | Kernel panic fixes |
| `display-panel-reset.md` | PocoF3Releases | P2 MEDIUM | LOW | Display quality |
| `cs35l41-xlog-removal.md` | LineageOS | P3 LOW | LOW | Telemetry removal |
| `mglru.md` | Upstream (Yu Zhao, Google) | DEFERRED | HIGH | Multi-Gen LRU (needs architecture port) |

---

## PR Strategy

One PR per import. Each is independent, small, and can be tested/reverted individually.

### Tier 1 — Import First (HIGH priority, LOW risk)
1. `import/ufs-write-booster` — 75% write speed improvement
2. `import/zram-bugfixes` — crash fixes
3. `import/sched-fair-fixes` — kernel panic fixes

### Tier 2 — Import Next (MEDIUM priority, LOW risk)
4. `import/lib-string-optimizations` — memcpy/memset +52-72%
5. `import/power-efficient-workqueue` — battery life
6. `import/vmscan-critical-process` — UI jank reduction
7. `import/zram-lz4-dictionary` — compression improvement
8. `import/rcu-boot-only-expedited` — power savings
9. `import/cpumask-builtin-helpers` — scheduler optimization
10. `import/display-panel-reset` — display quality

### Tier 3 — Import When Ready (LOW priority, LOW risk)
11. `import/drm-atomic-latency` — display latency
12. `import/cs35l41-xlog-removal` — telemetry removal
13. `import/int-sqrt-optimization` — math optimization

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
