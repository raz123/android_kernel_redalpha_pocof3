# Council Review Round 1 — CI/CD Specialist

**Reviewer**: Council Member 2 (CI/CD Specialist)
**Plan**: `COUNCIL_PLAN.md` — F2FS Fix + Workflow Improvements
**Date**: 2026-07-02

---

## Rating Summary

| Criterion | Rating |
|-----------|--------|
| A/B Slot Fix | **FAIL** — hardcodes boot_b, conflicts with slot detection |
| CACHEBUST | **PASS** (already present), but **NAY** on approach — ccache is strictly better |
| Permissions: `contents: write` | **PASS** — correct and well-motivated |
| softprops/action-gh-release | **CONDITIONAL PASS** — reasonable but marginal benefit; ensure correct env propagation |
| Edge Case Handling (workflow) | **PASS** — DTB/DTBO fallback, module handling, QA gates all solid |
| CI Breaking Risk | **WARNING** — A/B slot change carries real brick risk |
| Overall Workflow Proposals | **MIXED** — fix A/B slot approach before accepting |

---

## 1. A/B Slot Fix: `SLOT_SELECT=active` + `BLOCK=/dev/block/by-name/boot_b`

### Finding: This is incorrect and potentially dangerous

I thoroughly analyzed the AnyKernel3 `ak3-core.sh` logic (from AstideLabs/AnyKernel3) to understand how slot detection works. The `setup_ak()` function:

1. **Detects the slot** via `ro.boot.slot_suffix` or `androidboot.slot_suffix` → yields `_a` or `_b`.
2. **Applies `SLOT_SELECT`**: The only handled case is `inactive` (flips `_a`→`_b` or `_b`→`_a`). There is **no `active` case** in the switch — if `SLOT_SELECT=active`, it's a no-op; the detected slot value is used as-is. So `SLOT_SELECT=active` is the default behavior and does nothing.
3. **Resolves `BLOCK`**: When `BLOCK` starts with `/dev/` (e.g., `/dev/block/by-name/boot_b`), the script checks if `$BLOCK$SLOT` exists, otherwise uses `$BLOCK` directly. Since `/dev/block/by-name/boot_b_b` will never exist, it falls through and writes to `boot_b` regardless of slot.

**The result**: `BLOCK=/dev/block/by-name/boot_b` hardcodes writing to slot B, ignoring which slot the device is actually running from. `SLOT_SELECT=active` has no corrective effect.

**Poco F3 (alioth)**: It IS an A/B device. The cloned `anykernel.sh` already sets:
- `BLOCK=boot;` (works with auto-detection)
- `IS_SLOT_DEVICE=auto;` (auto-detect A/B)

With these defaults, `ak3-core.sh` correctly:
1. Determinably detects the active slot (`_a` or `_b`)
2. Searches `/dev/block/by-name/boot_a` or `/dev/block/by-name/boot_b`
3. Flashes to the correct partition

**Verdict**: REJECT the proposed `BLOCK=/dev/block/by-name/boot_b` approach. The current defaults (`BLOCK=boot` + `IS_SLOT_DEVICE=auto`) are correct. If any change is desired, `SLOT_SELECT=active` can be added as documentation (it's a no-op), but it's unnecessary.

**Risk**: If merged as-is, a user whose device is running from slot A would have their flash go to slot B. The device would still boot the old kernel from slot A, appearing as if the flash failed — or worse, if slot B is corrupted, the device could become unbootable.

**Recommendation**:
- Keep the cloned `anykernel.sh` defaults (`BLOCK=boot`, `IS_SLOT_DEVICE=auto`)
- OR, if a `/dev/*` path is desired for explicitness, use `BLOCK=/dev/block/by-name/boot` (no slot suffix) so the script appends `$SLOT` correctly

---

## 2. CACHEBUST: `--build-arg CACHEBUST=$(date +%s)`

### Finding: Already present; but ccache is superior

The CACHEBUST arg and Dockerfile `ARG CACHEBUST` are **already present** in the current `pocof3-build.yml` (line 28) and `Dockerfile`. The `f2fs-fix` branch already contains commits `08ecd92a3869` and `fb16c302a96e` that add this mechanism. So the plan's proposal to "add" it is a no-op.

**Analysis of CACHEBUST itself**:
- **Purpose**: Forces Docker to rebuild the image from scratch (invalidates all cached layers) every CI run.
- **Cost**: Every build re-downloads apt packages and the ZyC-Clang 16 toolchain (~500MB+ tarball), even when nothing changed. This wastes bandwidth and time.
- **Benefit**: Ensures reproducible environment, avoids stale-layer bugs.

**Better alternative**: There is a commit `538f5126f707` ("perf: add ccache + remove CACHEBUST anti-pattern, 3-5x build speedup") on a different branch that replaces CACHEBUST with ccache. This:
- Keeps environment freshness through the Dockerfile layer cache (which is deterministic)
- Mounts a persistent `/tmp/ccache-cache` volume for cross-build cache sharing
- Passes `CC='ccache clang'` to accelerate kernel rebuilds
- Reports ccache stats at build end for debugging

**Verdict**: CACHEBUST is already present and works. But the plan should **prefer the ccache approach** from the separate optimization commit, which provides 3-5x build speed improvements while still maintaining build reproducibility. Do NOT add CACHEBUST — it's already there; consider upgrading to ccache instead.

---

## 3. Permissions: `permissions: contents: write`

### Finding: Correct and low-risk

Adding `permissions: contents: write` at the job level is a good practice:
- GitHub Actions now defaults to `contents: read` for `GITHUB_TOKEN` on many repos/organizations
- Both `gh release create` and `softprops/action-gh-release` need `contents: write`
- Explicit declaration is preferred over relying on org-level default token permissions

**Verdict**: PASS. No issues.

**One note**: The permission must be at the job level (not step level) so all steps that need it can use it. The plan correctly targets `jobs.build.permissions`.

---

## 4. softprops/action-gh-release@v2

### Finding: Reasonable but introduces external dependency

**Pros**:
- Cleaner YAML configuration vs shell script
- Automatic tag creation if it doesn't exist
- Handles multiple file uploads gracefully
- Well-maintained (30k+ stars)

**Cons**:
- Introduces external action dependency (trust/supply-chain risk)
- The existing `gh release create` works fine and is simpler
- **Critical: Tag name computation**. The current `gh` approach computes `TAG_NAME` and `KSU_LABEL` inside a shell script. If switching to softprops, these values must be computed in a previous step using `${{ steps.SOMETHING.outputs.X }}` or the `env` context. The plan doesn't specify how this migration happens.
- **ZIP file path**: The current workflow has `working-directory: build` and runs `gh release create` from there. Softprops would need `files: build/*.zip` relative to workspace root, and the ZIP must be present before the step runs.

**Verdict**: CONDITIONAL PASS — feasible but ensure:
1. Tag name/label computation happens in a prior `env` or `steps.outputs` block (not inline in the action)
2. ZIP file path is correct relative to workspace
3. `GITHUB_TOKEN` is passed (softprops uses `GITHUB_TOKEN` env var, not `GH_TOKEN`)

**Suggestion**: Keep the existing `gh release create` approach. It's simpler, has no external dependency, and the shell script is already debugged. The marginal benefit of softprops doesn't justify the migration risk and external dependency for this simple use case.

---

## 5. Edge Case Handling

### Missing DTB/DTBO
**PASS**. The packaging step already checks for DTB/DTBO existence and patches `anykernel.sh` to remove their requirement. The sed commands correctly target the assertion in anykernel.sh. Well handled.

### Missing kernel image
**PASS**. QA Gates step checks for `Image`/`Image.gz-dtb` existence and fails the build if none found.

### Missing modules
**PASS**. Upload step uses `if-no-files-found: ignore`. Packaging step has a guarded `[ -d "out/modules" ] && ... cp` with `|| true` fallback.

### Missing VBMETA / AVB signing
Not addressed by the plan, but also not a regression — the anykernel.sh sets `PATCH_VBMETA_FLAG=auto` which handles this.

### Note: modules not actually installed
The cloned anykernel.sh sets `do.modules=0`. The workflow copies `.ko` files into `anykernel/anykernel-modules/`, but with `do.modules=0` these modules are never installed by AnyKernel3. This is a pre-existing issue, not introduced by the plan, but worth noting.

---

## 6. CI Breaking Risk Assessment

| Change | Risk Level | Rationale |
|--------|-----------|-----------|
| A/B slot fix | **HIGH** | Hardcoded `boot_b` could flash wrong slot → device fails to boot with new kernel |
| CACHEBUST | **NONE** | Already present, no change |
| Permissions | **LOW** | Permissions block only restricts, never grants more than the token's base capability |
| softprops/action-gh-release | **MEDIUM** | Only on `release: true` path; risk is the release step silently doing wrong thing (wrong tag, missing asset) |

---

## Questions for the Author

1. **A/B slot**: What device behavior led you to propose `BLOCK=/dev/block/by-name/boot_b`? Are you sure the existing `BLOCK=boot` + `IS_SLOT_DEVICE=auto` doesn't handle A/B correctly? Have you tested this on a Poco F3 that was previously on slot A?

2. **CACHEBUST**: Why add it when it's already present? And have you considered the ccache approach from commit `538f5126f707` which removes CACHEBUST and provides 3-5x build speedup?

3. **softprops**: How do you plan to pass the dynamic tag name/label values into the action? The current `gh` script computes `TAG_NAME` from `date +'%Y%m%d'` and `git rev-parse`. These must be available as env vars or step outputs for softprops to use.

4. **ccache vs CACHEBUST**: If the goal is fast CI, would you be open to replacing this entire CACHEBUST anti-pattern with the ccache approach from the `build/cbbad411` branch?

---

## Final Verdict

**NAY** — with conditions for approval:

1. **A/B slot fix**: MUST be corrected. Use `BLOCK=boot` (default from clone) or `BLOCK=/dev/block/by-name/boot` (without slot suffix). Do NOT hardcode `boot_b`.
2. **CACHEBUST**: No action needed (already present). But strongly consider upgrading to ccache instead.
3. **Permissions + softprops**: Permissions change is fine. For softprops, either ensure correct env propagation or keep the simpler `gh release create`.
4. **All other workflow changes**: Acceptable as-is or with minor corrections above.

The F2FS kernel changes (3 cherry-picks) are out of my scope — this review covers only the 4 workflow proposals. The workflow changes are salvageable with corrections to the A/B slot approach, but the current plan's slot fix would cause real device issues.

---

*Review conducted by Council Member 2 (CI/CD Specialist)*
