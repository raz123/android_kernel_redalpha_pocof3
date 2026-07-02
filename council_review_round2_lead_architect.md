# Council Review Round 2 — Lead Architect

**Reviewer**: Lead Kernel Architect — Council Round 2
**Date**: 2026-07-02
**Plan**: `COUNCIL_PLAN.md` — F2FS Fix + Workflow Improvements
**Branch**: `f2fs-fix`, target cherry-picks from `origin/test/earliest-ec-f2fs-fix`

---

## Criteria Ratings

| # | Criterion | Rating | Evidence |
|---|-----------|--------|----------|
| 1 | Cherry-pick order correctness | **PASS** | Verified chronologically: dcbff391c (F2FS replace) → a81ced683 (trace header) → d5d009eae (trace refinement). The replace commit carries `include/uapi/linux/f2fs.h` which the trace header (`#include <uapi/linux/f2fs.h>`) depends on. |
| 2 | Internal fs/f2fs/ consistency | **PASS** | All 30 files updated in lockstep. Kconfig adds 4 new symbols (F2FS_IOSTAT, F2FS_FS_LZ4HC, F2FS_FS_LZORLE, F2FS_UNFAIR_RWSEM). Old F2FS_IO_TRACE removed. Makefile includes iostat.o correctly. No stale INMEM/inmem_entry_slab references remain. |
| 3 | External reference consistency | **PASS** | No stale references to old functions (f2fs_stop_checkpoint old signature, f2fs_kmem_cache_alloc, trace_f2fs_* INMEM events) found outside `fs/f2fs/`. Trace header updated by commits 2+3 to remove INMEM events and match new subsystem. |
| 4 | Trace event header alignment | **PASS** | The final trace header (`d5d009eae`) correctly: removes INMEM/INMEM_DROP/INMEM_INVALIDATE/INMEM_REVOKE enums, adds `#include <uapi/linux/f2fs.h>`, fixes field types (nid[3] array, file_write_iter types), updates f2fs_map_blocks prototype. No stale references to removed tracepoints. |
| 5 | Workflow: permissions block | **CONDITIONAL PASS** | `permissions: contents: write` not yet in pocof3-build.yml. Plan correctly identifies it as needed. Must be applied before merging. |
| 6 | Workflow: CACHEBUST | **PASS** | Already present in Dockerfile and workflow line: `--build-arg CACHEBUST=$(date +%s)`. Valid, no action needed. |
| 7 | Workflow: gh release create | **PASS** | Already present and functional. No migration to softprops/action-gh-release needed. |
| 8 | Min git/CI environment for build | **PASS** | Dockerfile specifies ubuntu:22.04 with gcc-aarch64-linux-gnu, gcc-arm-linux-gnueabi, ZyC-Clang 16.0.6, libxml2, bc, flex, bison, libssl-dev, libelf-dev. Self-hosted runner with Docker + sudo access. No additional kernel modules required. |
| 9 | Kconfig symbol changes | **PASS** | New symbols (F2FS_IOSTAT, F2FS_FS_LZ4HC, F2FS_FS_LZORLE) all `default y` — auto-enabled by `olddefconfig`. F2FS_UNFAIR_RWSEM depends on BLK_CGROUP and has no default — will not auto-enable. Old F2FS_IO_TRACE was never set in any target defconfig. No defconfig changes needed. |
| 10 | Round 1 conditions addressed | **PASS** | All 3 R1 council members' findings reflected in COUNCIL_PLAN: (a) cherry-pick order maintained, (b) A/B slot defaults kept, (c) CACHEBUST noted as already present, (d) gh release create retained, (e) permissions block added to plan. |

---

## Detailed Findings

### 1. Cherry-Pick Order and Dependency Analysis

The three target commits on `origin/test/earliest-ec-f2fs-fix` (in chronological order):

```
dcbff391cc1e  — "fix: replace F2FS subsystem with jun15 proven version (full copy)"
a81ced683202  — "fix: update F2FS headers from main branch"
d5d009eae03c  — "fix: update F2FS trace event header from main branch"
```

**Order is correct** and verified:
- `dcbff391cc1e` replaces `fs/f2fs/` entirely (30 files, +6486/-3533) and restores `include/uapi/linux/f2fs.h` which is currently absent from `f2fs-fix` HEAD
- `a81ced683202` updates `include/trace/events/f2fs.h` (+297/-47 lines), removes INMEM trace enums, adds `#include <uapi/linux/f2fs.h>`, fixes field types — the uapi header must exist first
- `d5d009eae03c` further refines the same trace header (+295/-46 lines) with additional struct member/type fixes

The test branch also has 4 fixup commits after the cherry-picks (`5752c1d0`, `df35022b`, `a1d6c814`, `96ee310c`). These are **CI script fixes only** (validation grep patterns, AnyKernel3 cleanup, IKHEADERS disable). The IKHEADERS disable is already handled on `f2fs-fix` (commit `60c8a27890d8`). **No kernel compilation fix commits are needed** — the cherry-picks should build cleanly.

### 2. F2FS Internal Consistency

- **Kconfig**: New symbols `F2FS_IOSTAT` (replaces old `F2FS_IO_TRACE`, which was never enabled), `F2FS_FS_LZ4HC`, `F2FS_FS_LZORLE`, and `F2FS_UNFAIR_RWSEM` (BLK_CGROUP-gated). Compression selects moved from individual config blocks to conditional selects under `config F2FS_FS` — functionally equivalent.
- **Makefile**: Includes `iostat.o` under `CONFIG_F2FS_IOSTAT`. Correct.
- **No stale function references**: The INMEM atomic write mechanism is fully replaced by COW-based atomic writes (`f2fs_abort_atomic_write`, revoke entry mechanism). The old `inmem_entry_slab` and `f2fs_register_inmem_page` are completely removed.
- **Storage structs**: `SBI_NEED_FSCK`, `STOP_CP_REASON`, `ERROR_*` enums consistently used across all modified files.
- **Atomic write change**: The change from INMEM to COW-based atomic writes is the most significant behavioral change. This is the upstream standard (well-tested in mainline). Android SQLite uses `F2FS_IOC_START_ATOMIC_WRITE` — this change is compatible but represents a different implementation path. The F2FS specialist's Round 1 review noted this as the main area for test monitoring.

### 3. Outside fs/f2fs/ References

Grep across entire codebase for old function signatures (`f2fs_stop_checkpoint` old form, `f2fs_kmem_cache_alloc`, `trace_f2fs_ignore_page_writeback`, `trace_f2fs_register_inmem_page`, `f2fs_io_tracer_ops`) found **zero hits outside fs/f2fs/**. The trace event header (`include/trace/events/f2fs.h`) is the only external file that references F2FS internals, and it's correctly updated by commits 2 and 3.

The `include/uapi/linux/f2fs.h` is currently **missing from f2fs-fix HEAD** but restored by cherry-pick `dcbff391cc1e`. This is critical because the updated trace header `#include`s it. The uapi header is backward-compatible: it adds new ioctl commands for compression (`F2FS_IOC_GET_COMPRESS_BLOCKS` through `F2FS_IOC_COMPRESS_FILE`, plus `F2FS_IOC_START_ATOMIC_REPLACE` = ioctls 17-25) and `F2FS_IOC_SHUTDOWN` — all new additions that don't change existing ioctl numbering.

### 4. Trace Event Header Match

The final trace header (`d5d009eae` state):
- Removes INMEM/INMEM_DROP/INMEM_INVALIDATE/INMEM_REVOKE enums (correct — atomic write mechanism changed)
- Removes `show_block_type()` entries for INMEM variants
- Adds `#include <uapi/linux/f2fs.h>` for structure definitions
- Fixes `nid[3]` field from `__field(nid_t, nid[3])` to `__array(nid_t, nid, 3)` (correct for trace event struct)
- Updates `f2fs_file_write_iter` types (`unsigned long` → `loff_t`/`size_t`/`ssize_t`)
- Expands `f2fs_map_blocks` parameters (adds `create`, `flag`, `m_multidev_dio` fields)
- Changes `dev` source from `inode->i_sb->s_dev` to `map->m_bdev->bd_dev` (correct for multi-device F2FS)
- Adds conditional `f2fs_iostat` and `f2fs_iostat_latency` trace events under `CONFIG_F2FS_IOSTAT`

### 5. Workflow Changes

#### Current state of `.github/workflows/pocof3-build.yml`:

| Item | Status | Action Required |
|------|--------|-----------------|
| CACHEBUST | Already present (line in docker build) | **None** |
| `gh release create` | Already present | **None** |
| `permissions: contents: write` | **NOT present** | **Must be added** at job level (`jobs.build.permissions`) |
| A/B slot handling | Correct by default (`BLOCK=boot` + `IS_SLOT_DEVICE=auto` in cloned anykernel.sh) | **None** |

The `permissions: contents: write` addition is the only remaining workflow change. The COUNCIL_PLAN correctly identifies it. The R1 CI/CD specialist's NAY was on the A/B slot approach (which was subsequently removed from the plan), not on the permissions change.

#### GitHub environment requirements:
- **Runner**: Any GitHub Actions runner (self-hosted compatible)
- **Docker**: Required for isolated build environment
- **Storage**: ~5GB for toolchain + kernel build output
- **Toolchain**: ubuntu:22.04 base, ZyC-Clang 16.0.6 (~500MB tarball from GitHub), gcc cross-compilers for aarch64

### 6. Kconfig / Defconfig Impact

**New symbols** compared to current `f2fs-fix` Kconfig:

| Symbol | Type | Default | Impact |
|--------|------|---------|--------|
| `F2FS_FS_LZ4HC` | bool | `y` (depends on F2FS_FS_LZ4) | Auto-enabled; selects LZ4HC_COMPRESS |
| `F2FS_FS_LZORLE` | bool | `y` (depends on F2FS_FS_LZO) | Auto-enabled; selects LZO_COMPRESS + DECOMPRESS |
| `F2FS_IOSTAT` | bool | `y` | Auto-enabled; adds iostat.c, iostat.h, trace events |
| `F2FS_UNFAIR_RWSEM` | bool | none (depends on BLK_CGROUP) | Only enabled if BLK_CGROUP=y; no-op otherwise |
| `F2FS_IO_TRACE` | *removed* | — | Was never enabled in any target defconfig |

No target defconfig (`arch/arm64/configs/alioth_defconfig` et al.) references any F2FS-specific kernel symbols currently. The `olddefconfig` mechanism will handle the transition automatically. **No defconfig updates are required.**

### 7. Round 1 Concerns — Verification of Resolution

| R1 Concern | Source | Resolution |
|------------|--------|------------|
| A/B slot `boot_b` hardcode is dangerous | CI/CD specialist (NAY condition) | Plan correctly says "No change needed — defaults work" |
| CACHEBUST already present | CI/CD specialist | Plan correctly notes "Already present" |
| permissions: contents: write needed | CI/CD specialist | Plan includes this; needs actual YAML edit |
| softprops/action-gh-release concerns | CI/CD specialist | Plan says "Keep existing gh release create" |
| 3 cherry-picks may need fixups | Android engineer | Test branch has 4 CI fixup commits (validation scripts, IKHEADERS) — none are kernel code fixes. IKHEADERS already handled on f2fs-fix |
| Atomic write behavioral change | F2FS specialist | COW atomic write is upstream standard; test recommended |
| COMPILATION is the final gate | All R1 reviewers | Acknowledged — CI build after merging is the gate |

---

## Build-Time Risk Assessment

| Risk | Likelihood | Impact | Notes |
|------|-----------|--------|-------|
| Compile failure from trace header mismatch | **LOW** | Build failure | Commits applied in correct order; uapi header restored first |
| Compile failure from missing uapi header | **NONE** | — | Restored by commit 1 before commits 2-3 reference it |
| New compression libs not available | **LOW** | Link failure | LZ4HC_COMPRESS/LZO_COMPRESS selected in Kconfig; both are libraries present in kernel tree |
| F2FS_IOSTAT default y changes kernel size | **TRIVIAL** | +1.5KB | Minimal; iostat is mostly tracepoint/sysfs boilerplate |
| Docker build failure from missing deps | **LOW** | CI failure | Dockerfile already includes needed packages (no new deps from F2FS change) |
| Regression on existing F2FS partition | **LOW** | Data unavailable | On-disk structures unchanged; only in-memory logic changed |
| Atomic write path regression | **LOW-MEDIUM** | App crash | COW atomic is upstream standard; recommended to test SQLite paths |
| `do.modules=0` in AnyKernel3 | **KNOWN** | Modules not installed | Pre-existing issue, not introduced by plan |

---

## Verdict

### **YEA** — The plan is approved with one minor requirement.

**Reasons:**
1. **Correct cherry-pick order** — verified the dependency chain: dir replace (restores uapi header) → trace header → trace refinement.
2. **All internal references consistent** — Kconfig, Makefile, function signatures, type definitions all updated in lockstep across 30 files.
3. **Zero stale external references** — no old functions referenced outside `fs/f2fs/`.
4. **Trace header properly aligned** — INMEM events removed, IOSTAT events added, field types corrected.
5. **Kconfig transition is seamless** — new symbols auto-enable via `default y`; no defconfig changes needed.
6. **Round 1 concerns addressed** — A/B slot approach corrected, permissions change planned, CACHEBUST/release approach clarified.

**Condition for merge** (must be done before or as part of merging):
1. **Add `permissions: contents: write`** to `jobs.build` level in `.github/workflows/pocof3-build.yml`.

**Recommendations:**
1. **Compile-test before flashing** — CI build will be the final verification gate. The R1 Android engineer's caution about potential F2FS integration issues is prudent.
2. **Test atomic write paths** — The COW-based atomic write change from INMEM is well-tested in upstream but should be validated on actual Poco F3 hardware, especially SQLite write paths.
3. **Consider ccache** — The R1 CI/CD specialist's recommendation to replace CACHEBUST with ccache for 3-5x build speedup is sound, though not blocking.

---

*Review conducted by Lead Kernel Architect — Council Round 2*
