# SPEC: Cleanup & Documentation (Phase 5)

## 1. README.md Rewrite

Replace the inherited AstideLabs README. Write a new `README.md` with:

### Sections
```markdown
# RedAlpha Kernel v3

Custom Android kernel for Xiaomi Poco F3 (alioth, SM8250/SD870) with ReSukiSU root support.

## Features
- Kernel 4.19.325-redalpha3 (based on AstideLabs android16-aptusitu-new)
- WALT scheduler with DVFS headroom improvements
- Full BPF stack (BPF_LSM, BPF_SYSCALL, BPF_JIT_ALWAYS_ON) — Android 16 compatible
- ReSukiSU v4.1.0 with SuSFS (Manual Hook mode for 4.19)
- BBRplus TCP congestion control
- ZRAM with writeback (LZ4, ZSTD)
- CH101 ultrasound proximity sensor support
- CS35L41 QUAT_TDM audio routing (fixes Audio EC)
- USB serial drivers (CH340, FTDI, PL2303, CP210X)
- CAN bus and USB CAN adapter support
- F2FS realtime discard, EROFS support
- WireGuard built-in
- Battery fixes and charging improvements
- AnyKernel3 flashable ZIP packaging

## Supported Devices
| Device | Codename | Status |
|--------|----------|--------|
| Xiaomi Poco F3 | alioth | Primary |

## Download
Pre-built AnyKernel3 flashable ZIPs: [GitHub Releases](https://github.com/raz123/android_kernel_redalpha_pocof3/releases)

## Build Instructions
### CI Build (Recommended)
Trigger the GitHub Actions workflows:
1. `docker-build` → build container image
2. `kernel-build` → compile kernel
3. `anykernel3-package` → create flashable ZIP

### Local Build
```bash
git clone https://github.com/raz123/android_kernel_redalpha_pocof3.git
cd android_kernel_redalpha_pocof3
git clone --depth=1 -b v4.1.0 https://github.com/ReSukiSU/ReSukiSU KernelSU
ln -sf ../KernelSU/kernel drivers/kernelsu
# Download AOSP Clang toolchain (see build-kernel.sh)
bash build-kernel.sh
```

## Credits
- [AstideLabs](https://github.com/AstideLabs) — base kernel
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) — KernelSU fork with KPM/SuSFS
- [Danda420](https://github.com/Danda420/kernel_xiaomi_sm8250) — ZRAM backports, ipa_uc fix
- [kvsnr113](https://github.com/kvsnr113/xiaomi_sm8250_kernel) — security patches, lib optimizations
- [dtrail](https://github.com/dtrail/nethunter_kernel_xiaomi_sm8250) — DVFS headroom
- [UJX6N](https://github.com/UJX6N/bbrplus-4.19) — BBRplus TCP
- [LineageOS](https://github.com/LineageOS/android_kernel_xiaomi_sm8250) — base kernel source
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — flashable ZIP packaging

## License
GNU General Public License v2.0
```

## 2. Dead Code Removal

### Remove from fork (if present from AstideLabs)
- `build.sh` — AstideLabs' host-based build script (we use `build-kernel.sh` in Docker)
- `build-miui.sh` — MIUI-specific build script (not needed; target is AOSP)
- `.github/workflows/build.yml` — AstideLabs' host-based CI (replaced by Docker workflows)
- `.github/workflows/release_all.yml` — AstideLabs' matrix release (replaced)
- `config/` directory if it exists (old CI environment configs)
- `patches/` directory if it exists and patches have been committed (Phase 2 should delete `patches/` after committing them)

### Verify no stale redalpha CI artifacts
- No `config/alioth.env` (the old patch-application system)
- No `.github/workflows/build.yml` from old redalpha (it references `kernel-builder` but has different structure)

## 3. .gitignore

Add to `.gitignore`:
```
# Build artifacts
out/
*.zip
*.gz-dtb

# ReSukiSU (cloned at build time)
KernelSU/

# Toolchain (downloaded at build time)
toolchain/

# Editor/IDE
.vscode/
.idea/
*.swp
*.swo
*~

# macOS
.DS_Store
```

## 4. CHANGELOG.md

Create initial `CHANGELOG.md`:
```markdown
# Changelog

## v3.0.0 (2026-07-XX) — Rebuild from AstideLabs base
- Fresh fork from AstideLabs android16-aptusitu-new (v4.19.325-cip133)
- ReSukiSU v4.1.0 with Manual Hook mode
- Docker-based CI/CD pipeline
- CS35L41 QUAT_TDM audio routing (fixes Audio EC)
- CH101 ultrasound proximity sensor support
- SoundWire RX FIFO overflow fix
- bq2597x register dump silencing
- schedtune groups increased to 7
- VIDC log level reduced
- BBRplus TCP congestion control
- ZRAM writeback and memory tracking
- ipa_uc suspend panic fix
- Cubic DVFS headroom improvements
- Scheduler fairness fixes
- Optimized lib/string routines
- Security hardening (V-002 strcat/strcpy)
- Binder dbitmap double-free fix
```

## 5. Final Release

- Update `EXTRAVERSION` to `-redalpha3` (verify no drift)
- Build final release via CI pipeline
- Flash and test all features end-to-end
- Tag as `v3.0.0` (or `v2026.07.XX-<sha7>-<run>` per cicd skill convention)
- Push tag to trigger release workflow

## 6. Old Repo Reference

The old `raz123/android_kernel_redalpha` repo remains untouched. Once the new kernel is fully validated:
- Add a note to the old repo's README: "**Reference** — Active development at [android_kernel_redalpha_pocof3](https://github.com/raz123/android_kernel_redalpha_pocof3)."
- Do NOT delete or archive it.
