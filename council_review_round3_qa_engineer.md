# Council Review Round 3 — QA & Test Engineer — Final Acceptance

**Reviewer**: QA & Test Engineer — Council Round 3
**Date**: 2026-07-02
**Plan**: COUNCIL_PLAN.md — F2FS Fix + Workflow Improvements
**Branch**: `f2fs-fix`, cherry-picks from `origin/test/earliest-ec-f2fs-fix`

---

## Final Checklist

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | All 3 cherry-picks in correct order (dcbff391c → a81ced683 → d5d009eae) | **PASS** | Commits exist on `origin/test/earliest-ec-f2fs-fix` in correct chronological order. R2 Lead Architect verified dependency chain: `dcbff391cc1e` restores `include/uapi/linux/f2fs.h` → `a81ced683202` updates trace header (depends on uapi) → `d5d009eae03c` further refines trace header. Order is correct. |
| 2 | No hardcoded boot_b in A/B slot handling | **PASS** | Workflow (pocof3-build.yml) clones AnyKernel3 from AstideLabs/AnyKernel3 at runtime, which defaults to `BLOCK=boot` + `IS_SLOT_DEVICE=auto`. No `boot_b` string exists anywhere in the workflow. COUNCIL_PLAN explicitly rejects the `boot_b` hardcode. R1 CI/CD specialist's condition satisfied. |
| 3 | permissions: contents: write added to workflow | **FAIL** | The workflow file `.github/workflows/pocof3-build.yml` has **no `permissions:` block** at the job level. Line 18 starts `jobs:` → `build:` → `runs-on:` → `steps:` without any permissions declaration. R2 Lead Architect's merge condition #1: "Must add `permissions: contents: write` to `jobs.build` level". This must be added before merging. |
| 4 | CACHEBUST already present (no change needed) | **PASS** | Line 28 of pocof3-build.yml: `docker build --build-arg CACHEBUST=$(date +%s) -t kernel-builder .`. Already present. Commit `08ecd92a3869` and `fb16c302a96e` added it. No change needed. |
| 5 | gh release create kept (no softprops migration) | **PASS** | Lines 150-165 use `gh release create` with proper tag name computation (`TAG_NAME="v${BUILD_DATE}-$(git rev-parse --short=7 HEAD)"`) and `GITHUB_TOKEN` env var. No softprops/action-gh-release in the workflow. R1 CI/CD specialist's recommendation followed. |
| 6 | Existing on-disk corruption requires fsck.f2fs documented | **FAIL** | R1 Android engineer's merge condition #4: "Document that users with existing corruption may need `fsck.f2fs` after the upgrade." No such documentation exists anywhere in the repo. README.md, VERIFICATION.md, and all SPEC files lack any mention of fsck.f2fs for end users. No CHANGELOG or release notes file exists. The kernel will detect and flag existing corruption but cannot repair it — users need to know to run `fsck.f2fs /dev/block/by-name/userdata`. This must be added to release notes or README before merging. |
| 7 | Cherry-pick applied cleanly in prior test | **PASS** | The cherry-picks exist on `origin/test/earliest-ec-f2fs-fix` with 4 subsequent fixup commits (`5752c1d0d716`, `df35022b117e`, `a1d6c8144cbf`, `96ee310c794f`). R2 Lead Architect confirmed these are CI/environment fixups only (IKHEADERS disable, directory cleanup) — **no kernel compilation fix commits needed**. The cherry-picks build cleanly. |
| 8 | All previous round conditions met | **CONDITIONAL PASS** | See detailed breakdown below. Two pre-merge actions remain. |

---

## Previous Round Conditions — Verification

### Round 1 — F2FS Specialist

| Condition | Status | Notes |
|-----------|--------|-------|
| Whole-replace approach approved | **PASS** | Correct strategy for interleaved changes. |
| Atomic write path monitoring noted | **PASS** | COW-based atomic write is upstream standard. Noted as recommendation, not blocking. |

### Round 1 — Android Engineer (Merge Conditions)

| Condition | Status | Notes |
|-----------|--------|-------|
| 1. Apply 3 cherry-picks in order | **PASS** | Correct order verified on test branch. Ready to apply to f2fs-fix. |
| 2. Verify CI compilation passes before merging | **PASS** (pending) | Cherry-picks tested clean (no kernel fixups needed). CI build is the final gate. |
| 3. No hardcoded boot_b | **PASS** | Defaults kept (`BLOCK=boot` + `IS_SLOT_DEVICE=auto`). |
| 4. Document fsck.f2fs for users | **FAIL** | No end-user documentation exists. Must be added before merging. |

### Round 1 — CI/CD Specialist

| Condition | Status | Notes |
|-----------|--------|-------|
| A/B slot fix rejected (boot_b hardcode) | **PASS** | Plan correctly keeps defaults. |
| permissions: contents: write approved | **PASS** | Plan correctly identifies need. Not yet implemented. |
| CACHEBUST already present confirmed | **PASS** | Present since commits `08ecd92a`/`fb16c302`. |
| gh release create kept | **PASS** | Confirmed in workflow. |

### Round 2 — Lead Architect (Merge Condition)

| Condition | Status | Notes |
|-----------|--------|-------|
| **Add `permissions: contents: write` at job level** | **FAIL** | Not yet present in pocof3-build.yml. Must be added before merging. |
| Cherry-pick order verified | **PASS** | Dependency chain verified. |
| All consistency checks passed | **PASS** | Internal/external references, Kconfig, trace headers all consistent. |

### Round 2 — Security Auditor

| Condition | Status | Notes |
|-----------|--------|-------|
| No security vulnerabilities | **PASS** | Net improvement with SBI_NEED_FSCK hardening and BUG_ON reduction. |
| Net security improvement | **PASS** | Confirmed. |

---

## Pre-Merge Action Items

Both items must be resolved before this plan can be merged:

1. **Add `permissions: contents: write` to job level** in `.github/workflows/pocof3-build.yml`:
   ```yaml
   jobs:
     build:
       permissions:
         contents: write
       runs-on: self-hosted
   ```
   Required for `gh release create` to work with GitHub Actions' default read-only token permissions. Source: R2 Lead Architect merge condition, R1 CI/CD specialist approval.

2. **Document `fsck.f2fs` requirement** for users with existing corruption:
   Add a note to README.md or create a CHANGELOG/RELEASE-NOTES entry explaining:
   - The new F2FS code *detects* corruption but does not *repair* it
   - Users experiencing persistent app crashes should run:
     ```
     fsck.f2fs /dev/block/by-name/userdata
     ```
     (via TWRP recovery)
   - If fsck doesn't help, format /data as last resort after backup
   Source: R1 Android engineer merge condition #4.

---

## Summary of Findings

### What's solid
- All 3 cherry-picks are the correct set, in the correct order, build cleanly
- A/B slot handling is correct — no dangerous `boot_b` hardcode
- CACHEBUST already deployed, `gh release create` already working
- F2FS replacement is technically sound per 5 previous reviews
- Security posture improved (no new vulns, better corruption detection)

### What's missing (2 items)
1. `permissions: contents: write` not yet added to workflow
2. No end-user documentation for `fsck.f2fs` on existing corruption

---

## Final Verdict

### **YEA** — with 2 pre-merge conditions

The plan is technically sound and approved for merging **provided** the two pre-merge actions above are completed:

1. Add `permissions: contents: write` to pocof3-build.yml
2. Document `fsck.f2fs` requirement for users with existing corruption

These are straightforward, low-risk changes that do not affect the kernel binary. The F2FS replacement itself has been thoroughly reviewed across 5 prior reviews (2 rounds × 2-3 reviewers each) with unanimous approval on the kernel changes.

**After these two items are resolved, the plan is ready for execution:**
- Apply the 3 cherry-picks to `f2fs-fix` branch
- Trigger CI workflow
- Flash and verify on Poco F3 hardware

---

*Review conducted by QA & Test Engineer — Council Round 3*
