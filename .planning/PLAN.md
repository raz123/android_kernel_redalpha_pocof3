# RedAlpha Kernel Rebuild — Master Plan Index

## Scope

Rebuild the redalpha kernel from a fresh fork of the confirmed-working AstideLabs `android16-aptusitu-new` base, preserving the old `raz123/android_kernel_redalpha` repo as reference. Target repo: `raz123/android_kernel_redalpha_pocof3`.

## Reference: Old Repo (DO NOT DELETE)

The `raz123/android_kernel_redalpha` repo is preserved as a read-only reference until the rebuild is fully validated. Key reference points:
- **Default branch**: `android16-aptusitu` (5 custom commits + cherry-picks on top of AstideLabs base)
- **Patches directory**: `patches/ultrasound/`, `patches/stability/`, `patches/performance/` — applied via CI, not committed
- **Audio fix branch**: `fix/audio-cs35l41-quat-tdm` — CS35L41 TDM rerouting (merged to default)
- **CI workflow**: `.github/workflows/build.yml` — self-hosted Docker runner
- **Config**: `config/alioth.env` — lists 9 local patches

## Design Files

This plan is split across multiple focused files to keep coding agents lean:

| File | Contents |
|------|----------|
| [`SPEC-base.md`](local://SPEC-base.md) | **Phase 1**: Fork setup, **vanilla baseline build & test (hard gate)**, Docker CI/CD pipeline, ReSukiSU v4.1.0 integration, defconfig, first release |
| [`SPEC-fixes-redalpha.md`](local://SPEC-fixes-redalpha.md) | RedAlpha own fixes: ultrasound patches, audio CS35L41 fix, stability patches, performance patches (Phase 2) |
| [`SPEC-fixes-imported.md`](local://SPEC-fixes-imported.md) | Cherry-picks from ecosystem: BBRplus, ZRAM backports, ipa_uc fix, DVFS headroom, scheduler fixes, security patches (Phase 3) |
| [`SPEC-optional.md`](local://SPEC-optional.md) | Optional Phase 4 enhancements requiring user approval: PD charging bypass, KSU anti-detection, battery 1% fix, FUSE_BPF revert, power supply fixes |
| [`SPEC-cleanup.md`](local://SPEC-cleanup.md) | Phase 5 cleanup: README, dead code removal, .gitignore, documentation |
| [`VERIFICATION.md`](local://VERIFICATION.md) | Verification gates per phase, QA gates (0-8 from cicd skill), device testing procedures |

## Phase Execution Order

0. **CI Pipeline** (`SPEC-base.md` Section 2): Set up Dockerfile + workflows + build script. No kernel changes yet.
1. **Baseline Gate** (`SPEC-base.md` Section 3): Build unmodified fork via CI with `ksu=false` → flash → verify Audio EC works. **HARD STOP if this fails.**
2. **Phase 1 — Foundation** (`SPEC-base.md` Sections 4–6): ReSukiSU, branding, first release → device test
2. **Phase 2 — Own Fixes**: `SPEC-fixes-redalpha.md` → Second release → device test
3. **Phase 3 — Imported Fixes**: `SPEC-fixes-imported.md` → Third release → device test
4. **Phase 4 — Optional**: `SPEC-optional.md` → User decides per option → release + test
5. **Phase 5 — Cleanup**: `SPEC-cleanup.md` → Final release

## Constraints

- **OLD REPO IS SACRED**: The `raz123/android_kernel_redalpha` repo is never deleted during this process. It serves as the authoritative reference for redalpha-specific fixes.
- **Audio EC must work**: This is the primary motivator for the rebuild. Every phase must verify Audio EC is not regressed.
- **Docker-only CI**: The self-hosted runner has ONLY Docker. No host-installed toolchains, compilers, or build tools. Everything runs in the `ghcr.io/raz123/kernel-builder:latest` container.
- **ReSukiSU v4.1.0**: Pinned to tag `v4.1.0` (commit `0d27e68`), not `main` branch.
- **Manual Hook mode**: Non-negotiable for 4.19 kernel. No tracepoint redirect.
- **Three council review rounds per phase**: Each phase gets 3 rounds of council-review-2yea (2 YEA votes each) before release.
- **Incremental testing**: Every release is flashed and tested on the actual Poco F3 device before proceeding.

## Plan Persistence

All SPEC and VERIFICATION files live in the repo's `.planning/` directory (committed in Phase 1, Step 1.3 of `SPEC-base.md`). Each coding session starts by reading `.planning/PLAN.md` to pick up where the last session left off. Progress is tracked by updating the SPEC files inline — marking sections done, recording commit SHAs, noting any findings.
