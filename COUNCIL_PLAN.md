# Council Review Plan: F2FS Fix + Workflow Improvements

## Goal
Fix F2FS corruption on Poco F3 (alioth) by replacing the F2FS subsystem with a jun15 proven version, and improve the CI workflow with A/B slot support and better release handling.

## Proposed Changes

### A. F2FS Subsystem Replace (3 cherry-picks)
Cherry-pick onto a new `f2fs-fix` branch from `android16-aptusitu`:

1. **`dcbff391c`** — `fix: replace F2FS subsystem with jun15 proven version (full copy)`
   - Replaces entire `fs/f2fs/` directory with version proven stable
   - Key fixes: `SBI_NEED_FSCK`, `cp_error` handling, `DATA_GENERIC_ENHANCE_UPDATE`, dentry corruption fixes
   - Adds `iostat.c`/`iostat.h` for F2FS IO stats
   - Files changed: 30 files, +6486 -3533

2. **`a81ced683`** — `fix: update F2FS headers from main branch`
   - Updates `include/trace/events/f2fs.h` to match new F2FS implementation
   
3. **`d5d009eae`** — `fix: update F2FS trace event header from main branch`
   - Additional trace event header alignment

### B. Workflow Improvements (4 edits to .github/workflows/pocof3-build.yml)
1. **A/B slot fix** — Poco F3 (alioth) is an A/B device. AnyKernel3's `ak3-core.sh` auto-detects slot via `ro.boot.slot_suffix`. The cloned `anykernel.sh` already sets `BLOCK=boot` + `IS_SLOT_DEVICE=auto` which handles A/B correctly. **No change needed** — the defaults work. Do NOT hardcode `boot_b`.
2. **CACHEBUST** — Already present in `pocof3-build.yml` (line 28: `--build-arg CACHEBUST=$(date +%s)`). Already valid. No additional change needed.
3. **permissions: contents: write** — Add `permissions: contents: write` at job level (required for release actions).
4. **Release action** — Keep existing `gh release create` approach (simpler, fewer external dependencies). Skip softprops/action-gh-release migration.
### C. Build & Verify
- Push `f2fs-fix` branch to origin
- Trigger `workflow_dispatch` on pocof3-build.yml
- Download artifact ZIP
- Flash on Poco F3 and verify F2FS corruption is resolved

## Risk Assessment
- **F2FS replace**: Well-tested proven version. Low risk of regression. Cherry-pick already tested clean.
- **Workflow changes**: Only affects CI, not kernel binary. Very low risk.
- **A/B slot fix**: Required for proper flashing on A/B devices (Poco F3). Low risk.

## Verification
- CI must pass all QA gates (KALLSYMS, SELinux, Binder, Image size)
- Resulting ZIP must flash on Poco F3
- Device must boot without F2FS corruption in /data/data
