# Council Review Round 1 — F2FS Specialist

**Reviewer**: F2FS Filesystem Specialist
**Date**: 2026-07-02
**Commit under review**: `dcbff391c` (+ companion commits `a81ced683`, `d5d009eae`)
**Branch**: `f2fs-fix`

---

## Criteria Ratings

### 1. Wholesale replace vs cherry-picking: **PASS**

| Aspect | Assessment |
|--------|-----------|
| Atomicity | The replacement syncs fs/f2fs/ to a newer revision from the same android16-aptusitu tree. Every caller of changed interfaces (f2fs_stop_checkpoint, f2fs_kmem_cache_alloc, etc.) is updated in lockstep — no stale callers. |
| Dependency correctness | All interdependent changes (iostat integration, error handling refactors, GC tiering) are applied atomically. No risk of missing a prerequisite patch. |
| Cherry-pick viability | Cherry-picking individual fixes would be impractical: the changes are deeply interwoven (iostat replaces trace.h across 7 files, error codes propagate through multiple layers, f2fs_stop_checkpoint signature change touches 6+ files). |
| Provenance | The source is the same kernel tree (android16-aptusitu), so the F2FS version is already proven to build and run on this base. This is significantly safer than importing from upstream Linux. |

**Rationale**: A wholesale directory replace is the correct approach here. The diff is too entangled for surgical cherry-picks, and the source provenance guarantees API compatibility with the rest of the kernel tree.

### 2. Inclusion of critical fixes: **PASS**

| Fix | Present? | Coverage |
|-----|----------|----------|
| SBI_NEED_FSCK | YES | 50+ references across 13 files. New code adds detection in dentry ops (dir.c:1010-1033), node validation (node.c:36), segment consistency (segment.c:3571, segment.h:724-733), and inode corruption (inode.c:212-236). Sets CP_FSCK_FLAG during checkpoint when flagged. |
| cp_error handling | YES | Complete overhaul: STOP_CP_REASON enum for root-cause tracking, f2fs_handle_stop() for shutdown sequencing, f2fs_handle_error() with typed ERROR_* codes, f2fs_handle_page_eio() for meta/node read failures. The old `f2fs_stop_checkpoint(sbi, false)` now carries reason flags throughout. |
| Dentry corruption prevention | YES | Casefold name switched to dedicated slab cache (f2fs_cf_name_slab), null-safe freeing. f2fs_match_name return type changed bool->int for error propagation. is_ciphertext_name -> is_nokey_name (fscrypt API update). __f2fs_find_dentry refactored for correctness. |
| DATA_GENERIC_ENHANCE_UPDATE | YES **NEW** | This is an entirely new check not present in the old code. __is_bitmap_valid() now distinguishes UPDATE writes that find a block already valid in the bitmap — signals cross-contamination that needs fsck. |

### 3. On-disk format compatibility: **PASS**

| Component | Status |
|-----------|--------|
| Superblock magic | Unchanged (F2FS_SUPER_MAGIC). Superblock structure layout unchanged. |
| Checkpoint format | Unchanged (same CP_PACK layout, same CRC32 checksum verification). |
| NAT/SIT/SSA layout | Unchanged. |
| Feature flags | Unchanged. New code reads existing flags correctly. |
| Mount-time validation | Additional sanity checks added (CRC offset bounds, area boundary validation) — these are strictly additive checks that won't reject a valid existing filesystem. |

**Key findings**:
- `f2fs_tuning_parameters()` on lines ~4520-4522 calls `f2fs_update_time()` at mount — benign initialization.
- The `adjust_unusable_cap_perc()` and `adjust_reserved_segment()` helpers are new but run only for specific mount options.
- `sanity_check_area_boundary()` validates superblock geometry but won't fail a properly formatted device.
- **Verdict**: An existing F2FS partition will mount identically. No format migration needed.

### 4. iostat.c/iostat.h: **PASS**

| Aspect | Assessment |
|--------|------------|
| Config gating | Proper CONFIG_F2FS_IOSTAT (defined in Kconfig, default y). When disabled, all calls compile to inline stubs — zero code impact. |
| Replaces trace.h | The old CONFIG_F2FS_IO_TRACE/trace.h mechanism (depends on FUNCTION_TRACER) is replaced. None of the target defconfigs enabled CONFIG_F2FS_IO_TRACE, so this is a clean swap. |
| Bio integration | iostat_alloc_and_bind_ctx / iostat_update_and_unbind_ctx / iostat_update_submit_ctx hooks into the existing bio pathway with no additional allocations in the fast path. |
| No performance concern | The iostat struct is piggybacked on `bio->bi_private` which was already used. Latency tracking uses jiffies — negligible overhead. |
| Sysfs exposure | Exposes IO stats via sysfs and periodic tracepoint events. Adds debug value without risk. |

**Concern**: None. The iostat framework is well-designed, properly config-guarded, and replaces the old trace.h mechanism cleanly.

---

## Full Technical Analysis

### Diff Character
- **30 files changed**, +6486 -3533 lines
- Core on-disk format structures: UNCHANGED
- All internal function signatures: CONSISTENTLY UPDATED across fs/f2fs/
- Error recovery paths: SIGNIFICANTLY IMPROVED with typed error codes and stop reasons
- GC algorithm: IMPROVED with urgency tiering (URGENT_HIGH/MID/NORMAL + gc_remaining_trials)
- Atomic write handling: REWORKED (inmem_entry_slab removed, revoke_entry_slab added, new f2fs_abort_atomic_write)
- Compression: EXPANDED (LZ4HC, LZO-RLE, ZSTD level selection, per-ext nocompress)

### Config Impact
The old `Kconfig` had:
```c
config F2FS_IO_TRACE      // depends on FUNCTION_TRACER — rarely enabled
```
The new `Kconfig` has:
```c
config F2FS_IOSTAT         // default y, no deps — auto-enables for everyone
```
Defconfigs for all target devices (alioth, pipa, apollo, etc.) do NOT set CONFIG_F2FS_IO_TRACE, so the removal is transparent. The new CONFIG_F2FS_IOSTAT will auto-enable via `olddefconfig`.

### Error Detection Improvements (specific to corruption)
The new code adds `SBI_NEED_FSCK` triggers in:
- **DATA_GENERIC_ENHANCE_UPDATE** path: detects when an UPDATE write targets an already-allocated block in SIT (cross-contamination)
- **dentry operations**: validates dentry hash/name consistency during lookup
- **node validation**: detects corrupted inode references in f2fs_check_nid_range
- **segment consistency**: validates summary footer/type/block-count consistency
- **recovery**: adaptive readahead (adjust_por_ra_blocks) and max_rf_node_blocks guard

### Specific Risk: Atomic Write Refactoring
The old `f2fs_register_inmem_page` and `inmem_entry_slab` are removed. The new code uses `f2fs_abort_atomic_write` and `revoke_entry_slab`. This is an upstream change that moves atomic writes to a COW inode approach. The `__is_cp_guaranteed` function also changed — it no longer treats atomic file pages as CP-guaranteed. This is *correct* behavior for COW-based atomic writes but represents a behavioral change that has been well-tested upstream.

---

## Final Verdict

### **YEA** — The F2FS subsystem replacement is approved.

**Reasons**:

1. The wholesale replace is the right strategy given the interleaved nature of the changes — cherry-picking is neither feasible nor safer.
2. All four target fixes (SBI_NEED_FSCK, cp_error handling, dentry corruption, DATA_GENERIC_ENHANCE_UPDATE) are robustly implemented, with many additional corruption detection points beyond what the plan enumerates.
3. On-disk format is unchanged — existing F2FS partitions will mount without issue.
4. iostat.c/iostat.h is a clean, config-guarded replacement for the unused trace.h mechanism.
5. The companion commits update the trace event headers and uapi header, completing the dependency chain.
6. The code comes from the same kernel tree (android16-aptusitu), not an external or untrusted source.

**Minor note**: The atomic write/inmem rework in segment.c is a behavioral change worth awareness during testing. If the device uses `F2FS_IOC_START_ATOMIC_WRITE` (Android SQLite does), monitor for regression. The COW inode approach is the upstream standard and is well-proven, but test coverage of atomic write paths is recommended.
