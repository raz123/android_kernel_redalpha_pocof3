# SPEC: Foundation — Fork, CI, ReSukiSU, First Release

## 1. Fork & Repo Setup

### 1.1 Create new repo
- Create `raz123/android_kernel_redalpha_pocof3` as a fork of `AstideLabs/android_kernel_xiaomi_sm8250`.
- Target branch: **`android16-aptusitu-new`** (most current, rebuilt from lineage-20, merged v4.19.325-cip133).
- If the branch has diverged significantly after Jun 30, pin to a specific commit SHA (note it here: `___` — fill at fork time).

### 1.2 Clone & configure
```bash
git clone https://github.com/raz123/android_kernel_redalpha_pocof3.git
cd android_kernel_redalpha_pocof3
git checkout android16-aptusitu-new
```

### 1.3 Commit plan files to repo
Create a `.planning/` directory in the repo root and copy the plan files in. These track progress across coding sessions:
```bash
mkdir -p .planning
# Copy from the local plan session (files listed in PLAN.md index):
#   PLAN.md SPEC-base.md SPEC-fixes-redalpha.md SPEC-fixes-imported.md
#   SPEC-optional.md SPEC-cleanup.md VERIFICATION.md
cp /path/to/plan/files/*.md .planning/
git add .planning/
git commit -m "docs: add kernel rebuild plan files"
```
The `.planning/` directory stays in the repo. Each phase updates the relevant SPEC file's status (mark sections done, note findings, record commit SHAs).

## 2. Docker-Based CI/CD Pipeline

The android-kernel-cicd-pipeline skill's golden rule: **ALL workflows MUST be Docker-only.** The self-hosted runner has ONLY Docker installed. This pipeline is set up BEFORE any builds — both the vanilla baseline and all future builds use it.

### 2.1 Dockerfile (`Dockerfile`)
```dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc bison build-essential ca-certificates clang curl flex git \
    libelf-dev libncurses-dev libssl-dev lld llvm lz4 python3 rsync zip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD ["/bin/bash"]
```

### 2.2 Workflow: `docker-build.yml`
- Trigger: `workflow_dispatch`
- Runs on: `self-hosted`
- Steps:
  1. Checkout
  2. `docker build -t ghcr.io/raz123/kernel-builder:latest .`
  3. `docker push ghcr.io/raz123/kernel-builder:latest`

### 2.3 Workflow: `kernel-build.yml`
- Trigger: `workflow_dispatch` with inputs:
  - `ksu` (boolean, default `true`) — whether to build with ReSukiSU
- Runs on: `self-hosted`
- Container: `ghcr.io/raz123/kernel-builder:latest`
- Steps:
  1. Checkout
  2. Run `build-kernel.sh` with `KSU=${{ inputs.ksu }}`
  3. Run QA gates (gates 0–1 skipped when `ksu=false`)
  4. Upload `arch/arm64/boot/Image.gz-dtb` and `out/modules/` as artifacts

### 2.4 Workflow: `anykernel3-package.yml` + `release.yml`
- `anykernel3-package.yml`: Triggered by `workflow_dispatch`. Downloads artifacts from `kernel-build.yml`, packages with AnyKernel3, uploads ZIP artifact.
- `release.yml`: Triggered by `workflow_run` on anykernel3 completion. Creates GitHub Release with tag `vYYYY.MM.DD-<sha7>-<run_number>`. Optional Telegram notification.

### 2.5 Build script (`build-kernel.sh`)
Create new script (NOT carry-over from AstideLabs or old redalpha). The `KSU` variable controls whether ReSukiSU is integrated — pass `KSU=0` for vanilla builds:
```bash
#!/bin/bash
set -euo pipefail
DEVICE="${DEVICE:-alioth}"
KSU="${KSU:-1}"

# Toolchain — use AOSP kernel-build clang
if [ ! -d "toolchain/clang" ]; then
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
        -b master-kernel-build-2024 toolchain/clang
fi
export PATH="$PWD/toolchain/clang/bin:$PATH"

# Cross-compiler
export ARCH=arm64
export SUBARCH=arm64

# ReSukiSU (skip when KSU=0 for vanilla builds)
if [ "$KSU" = "1" ]; then
    if [ ! -d "KernelSU" ]; then
        git clone --depth=1 -b v4.1.0 https://github.com/ReSukiSU/ReSukiSU KernelSU
    fi
    ln -sf ../KernelSU/kernel drivers/kernelsu
    # Disable check_mk files that block build
    for check in drivers/kernelsu/tools/*_check.mk; do
        echo "# Disabled for CI" > "$check" 2>/dev/null || true
    done
fi

# Build
make CC=clang LD=ld.lld ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    vendor/alioth_defconfig

if [ "$KSU" = "1" ]; then
    scripts/config --disable CONFIG_LTO_CLANG
    scripts/config --enable CONFIG_LTO_NONE
    scripts/config --enable CONFIG_KSU
    scripts/config --enable CONFIG_KSU_MANUAL_HOOK
fi

make CC=clang LD=ld.lld ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    -j$(nproc)

# Collect output
mkdir -p out
cp arch/arm64/boot/Image.gz-dtb out/
find . -name "*.ko" -exec cp {} out/modules/ \; 2>/dev/null || true
```

### 2.6 QA Gates (implemented in `kernel-build.yml`)

Gates 0–1 are KSU-only and **skipped when `ksu=false`** (vanilla builds).

| Gate | Check | Action | KSU-only |
|------|-------|--------|----------|
| 0 SuSFS | `grep -r "CONFIG_KSU_SUSFS\|ksu_susfs\|susfs_" drivers/kernelsu/` must have results | HARD BLOCK | Yes |
| 1 Hook mode | Verify `CONFIG_KSU_MANUAL_HOOK=y` in .config | HARD BLOCK | Yes |
| 2 KALLSYMS | Verify `CONFIG_KALLSYMS=y` + `CONFIG_KALLSYMS_ALL=y` | HARD BLOCK | No |
| 3 SELinux | Verify enforcing but not fully restrictive | HARD BLOCK | No |
| 4 Binder | Verify binder configs present | HARD BLOCK | No |
| 5 DTBO | `grep -i dtbo arch/arm64/boot/dts/vendor/qcom/*.dts` MUST be empty | HARD BLOCK | No |
| 6 Boot image | `stat -c%s out/Image.gz-dtb` > 15MB | HARD BLOCK | No |
| 7 Size budget | Warn if > 25MB | WARNING | No |
| 8 Changelog | Warn if no CHANGELOG.md | WARNING | No |

## 3. Vanilla Baseline Build & Test (HARD GATE)

**DO NOT add ANY code changes to the repo.** This uses the CI pipeline from Section 2 to build the unmodified fork. If the vanilla base fails Audio EC, we have a mis-identified root cause and must stop.

### 3.1 Build via CI
1. Commit and push the unmodified fork (with only Dockerfile, workflows, and build script from Section 2).
2. Trigger `docker-build.yml` → verify image pushed to GHCR.
3. Trigger `kernel-build.yml` with **`ksu=false`** → vanilla build, no ReSukiSU.
4. Verify build succeeds and QA gates 2–8 pass.

### 3.2 Package and flash
- Trigger `anykernel3-package.yml` to package the vanilla `Image.gz-dtb` into an AnyKernel3 ZIP.
- Download the ZIP from the workflow artifacts.
- Flash on the Poco F3 device via TWRP.

### 3.3 Baseline acceptance (HARD GATE — stop if any fail)
| # | Check | Expected |
|---|-------|----------|
| 0.1 | Device boots to home screen | Boot succeeds |
| 0.2 | `uname -r` | `4.19.325` (no suffix — this is vanilla) |
| 0.3 | Audio EC | Make a phone call. Other party hears NO echo. |
| 0.4 | Speaker | Play audio — bottom speaker works |
| 0.5 | WiFi / BT / Mobile data | All function |
| 0.6 | No kernel panics in `dmesg` | Clean dmesg, no BUG/Oops/panic |
| 0.7 | Overnight idle (optional but recommended) | No spontaneous reboots |

**If Gate 0.3 (Audio EC) fails**: The vanilla AstideLabs `android16-aptusitu-new` branch does NOT fix Audio EC on this device. Stop — do not proceed. The user must re-evaluate the base.

**If all gates pass**: Proceed. The base is confirmed good. Now we add ReSukiSU, branding, and finalize the release (Sections 4–6).

### 3.4 Git state after baseline test
The repo at this point has CI plumbing committed but the kernel source is the unmodified fork. The next sections make the first actual kernel commits. Do NOT commit the toolchain directory — it is `.gitignore`d.

## 4. ReSukiSU v4.1.0 Integration

### 4.1 Verify existing integrations
The AstideLabs base already has KSU plumbing. Verify:
- `drivers/Kconfig` includes `source "drivers/kernelsu/Kconfig"` before `endmenu`
- `drivers/Makefile` includes `obj-$(CONFIG_KSU) += kernelsu/`
- If either is missing, add them (path: end of file, before closing).
- `drivers/kernelsu/` directory exists (empty placeholder — content comes from symlink at build time).

### 4.2 Defconfig additions (in `arch/arm64/configs/alioth_defconfig`)
```
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
```
These MUST be the only KSU hook configs. Do NOT set `CONFIG_KSU_TRACEPOINT_REDIRECT` or `CONFIG_KSU_SUSFS_INLINE_HOOK` — those are for GKI 5.10+.

### 4.3 LTO disable for KSU on 4.19
ReSukiSU manual hook mode on 4.19 requires LTO disabled. In the build script, after `make defconfig`:
```bash
scripts/config --disable CONFIG_LTO_CLANG
scripts/config --enable CONFIG_LTO_NONE
```
Or set `CONFIG_LTO_NONE=y` in defconfig directly.

### 4.4 CI clone and symlink
The critical detail from kernel-resukisu-integration skill:
- Clone to `KernelSU/` at repo root
- Symlink: `ln -sf ../KernelSU/kernel drivers/kernelsu` (NOT copy!)
- ReSukiSU's Kbuild checks for `.git` at parent directory; copying fails with "You should use ReSukiSU as a git submodule instead of copying code directly".
- Disable `*_check.mk` files in `drivers/kernelsu/tools/` during CI (they reference build-environment paths that don't exist in container).

### 4.5 Verification after build
```bash
# In built kernel:
grep -c "ksu_" arch/arm64/boot/Image # symbols present
# On device after flash:
cat /proc/kallsyms | grep ksu_handle  # hooks registered
dmesg | grep KernelSU                  # active
su -c 'id'                              # uid=0(root)
```

## 5. Branding

### 5.1 Set EXTRAVERSION
In top-level `Makefile`, change:
```
EXTRAVERSION = -redalpha3
```
(v3 because old repo used v1→v2; this is the fresh rebuild third iteration).

### 5.2 Defconfig localversion
In `arch/arm64/configs/alioth_defconfig`:
```
CONFIG_LOCALVERSION="-redalpha3-perf"
```
This overrides the AstideLabs `-aptusitu-perf` suffix.

## 6. First Release Procedure

1. Push all Phase 1 changes to `android16-aptusitu-new` branch.
2. Run docker-build workflow → verify image pushed.
3. Run kernel-build workflow (with `ksu=true`) → verify Image.gz-dtb > 15MB, all QA gates pass.
4. Run anykernel3-package → verify ZIP produced.
5. Release workflow auto-fires → verify GitHub Release + tag.
6. Download ZIP, flash on Poco F3 via TWRP.
7. **Acceptance**: Device boots, `uname -r` = `4.19.325-redalpha3-perf`, ReSukiSU manager v4.1.0 shows "Installed", `su -c 'id'` = root, Audio EC works (no echo on call).

## Dependencies
- `Dockerfile` must exist before `docker-build.yml` can succeed.
- `build-kernel.sh` must exist before `kernel-build.yml` can succeed.
- Container image must be built and pushed before `kernel-build.yml` can use it.
- `drivers/kernelsu/` directory must exist (even if empty) for symlink to work.
