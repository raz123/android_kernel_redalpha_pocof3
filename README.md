# RedAlpha Kernel

Custom Android kernel for Xiaomi Poco F3 (codename alioth, SM8250/SD870) with ReSukiSU root support.

> **Warning:** This kernel source is under active development. Use at your own risk.

---

## Table of Contents

- [Features](#features)
- [Supported Devices](#supported-devices)
- [Build Instructions](#build-instructions)
- [Download](#download)
- [Credits](#credits)
- [License](#license)

---

## Features

- Kernel 4.19.325 (upgrading to 4.19.420)
- WALT scheduler
- Full BPF stack (BPF_LSM, BPF_SYSCALL, BPF_JIT_ALWAYS_ON)
- LTO_CLANG compilation
- ANDROID_VENDOR_HOOKS support
- ReSukiSU KernelSU integration (supports KPM and SuSFS)
- NoKernelSU variant available (compatible with Magisk and APatch)
- zRAM with writeback (LZ4, ZSTD, and other compression algorithms)
- AnyKernel3 flashable ZIP packaging
- USB serial drivers (CH340, FTDI, PL2303, CP210X, and more)
- CANBus and USB CAN adapter support
- F2FS realtime discard for better TRIM
- EROFS support
- Backported 5.10 BPF (Android 16 compatible)
- Xiaomi vendor touch/camera/audio/display/GPU drivers
- Battery fix (stuck at 1% issue)
- Backlight brightness fix

---

## Supported Devices

| Device | Codename | Status |
|--------|----------|--------|
| Xiaomi Poco F3 | alioth | Primary |
| Xiaomi Mi 11i (flat) | - | Secondary |
| Redmi K40 Pro | - | Secondary |

---

## Build Instructions

### Local Build

1. **Install dependencies:**

```bash
sudo apt-get install git build-essential bc bison flex libssl-dev libelf-dev ccache python3
```

2. **Clone the repo:**

```bash
git clone https://github.com/AstideLabs/android_kernel_redalpha.git
cd android_kernel_redalpha
```

3. **Clone ReSukiSU (optional, for KernelSU support):**

```bash
git clone https://github.com/ReSukiSU/ReSukiSU.git -b main
```

4. **Download the Clang toolchain:**

```bash
mkdir -p ~/clang && cd ~/clang
git clone https://gitlab.com/nicco141/AnyKernel3-clang.git -b release/18
```

Or use ZyCromerZ Clang:

```bash
git clone https://gitlab.com/nicco141/AnyKernel3-clang.git -b release/18
```

5. **Build the kernel:**

```bash
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=path/to/clang/bin/aarch64-linux-gnu-
export CC=path/to/clang/bin/clang
make redalpha_defconfig
make -j$(nproc)
```

### CI Build

The project uses GitHub Actions with a self-hosted runner for automated builds. Push to a tagged branch or create a release to trigger a CI build.

---

## Download

Pre-built AnyKernel3 flashable ZIPs are available on the [GitHub Releases](https://github.com/AstideLabs/android_kernel_redalpha/releases) page.

Flash via TWRP or any recovery that supports AnyKernel3 ZIPs.

---

## Credits

- [AstideLabs](https://github.com/AstideLabs) — Primary base kernel
- [raz123/jun15](https://github.com/raz123) — CI scripts and patches
- [kvsnr113](https://github.com/kvsnr113) — Security patches
- [Danda420](https://github.com/Danda420) — Security patches
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) — KernelSU fork with KPM support
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — Flashable ZIP packaging
- [ZyCromerZ](https://gitlab.com/nicco141/AnyKernel3-clang) — Clang toolchain
- [LineageOS](https://github.com/LineageOS/android_kernel_xiaomi_sm8250) — Base kernel source
- [UtsavBalar1231](https://github.com/UtsavBalar1231/kernel_xiaomi_sm8250) — Vendor driver sources

---

## License

This project is licensed under the [GNU General Public License v2.0](LICENSE).

See the [GPL-2.0 license text](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) for details.
