#!/bin/bash
set -ex

# Run on HOST (not Docker) — only needs git, sed, zip
# Env: BUILD_NUMBER, KSU_ENABLED

# Determine KSU suffix for filename
KSU_SUFFIX="_ReSukiSU"
[ "${KSU_ENABLED}" != "true" ] && KSU_SUFFIX="_vanilla"

# Save VoLTE module before cleaning
[ -d "anykernel-modules/fix_rogers_volte" ] && cp -r anykernel-modules/fix_rogers_volte .volte_backup

# Clone AnyKernel3 flasher (provides tools/ak3-core.sh, bin/, etc.)
rm -rf anykernel
git clone https://github.com/AstideLabs/AnyKernel3 -b master --single-branch --depth=1 anykernel

# Overlay our custom anykernel.sh (has dual-slot flash + VoLTE module install)
cp anykernel.sh anykernel/anykernel.sh

# === A/B SLOT FIX ===
grep -q '^SLOT_SELECT=active' anykernel/anykernel.sh || sed -i '1i\SLOT_SELECT=active' anykernel/anykernel.sh

# Copy kernel image
mkdir -p anykernel/kernels/aosp/
if [ -f out/arch/arm64/boot/Image.gz-dtb ]; then
  cp out/arch/arm64/boot/Image.gz-dtb anykernel/kernels/aosp/Image
elif [ -f out/arch/arm64/boot/Image ]; then
  cp out/arch/arm64/boot/Image anykernel/kernels/aosp/Image
fi

# Copy DTB
for dtb in out/arch/arm64/boot/dts/qcom/sm8250*.dtb out/arch/arm64/boot/dtb; do
  [ -f "$dtb" ] && cp "$dtb" anykernel/kernels/aosp/dtb && break
done

# Copy dtbo.img
[ -f out/arch/arm64/boot/dtbo.img ] && cp out/arch/arm64/boot/dtbo.img anykernel/kernels/aosp/dtbo.img

# Relax checks if dtb or dtbo missing
if [ ! -f anykernel/kernels/aosp/dtb ] || [ ! -f anykernel/kernels/aosp/dtbo.img ]; then
  sed -i "s|\[ -f \$AKHOME/kernels/\$os/Image \] && \[ -f \$AKHOME/kernels/\$os/dtb \] && \[ -f \$AKHOME/kernels/\$os/dtbo.img \]|[ -f \$AKHOME/kernels/\$os/Image ]|" anykernel/anykernel.sh
  sed -i "/mv \$AKHOME\/kernels\/\$os\/dtb/d" anykernel/anykernel.sh
  sed -i "/dtbo.img/d" anykernel/anykernel.sh
fi

# Copy kernel modules
[ -d "out/modules" ] && [ "$(ls -A out/modules 2>/dev/null)" ] && mkdir -p anykernel/anykernel-modules/ && cp out/modules/*.ko anykernel/anykernel-modules/ 2>/dev/null || true

# Include ZRAM/uclamp scripts
[ -f "zram-resize.sh" ] && cp zram-resize.sh anykernel/anykernel-modules/
[ -f "uclamp_tuning.sh" ] && cp uclamp_tuning.sh anykernel/anykernel-modules/
[ -f "vm_tuning.sh" ] && cp vm_tuning.sh anykernel/anykernel-modules/ 2>/dev/null || true

# Include Rogers VoLTE fix KernelSU module
if [ -d ".volte_backup" ]; then
  cp -r .volte_backup anykernel/anykernel-modules/fix_rogers_volte_module
  chmod 755 anykernel/anykernel-modules/fix_rogers_volte_module/*.sh 2>/dev/null || true
fi

# Build ZIP (use python zipfile — zip may not be installed)
ZIP_FILENAME="rp-pocof3${KSU_SUFFIX}_b${BUILD_NUMBER}.zip"
python3 -c "
import zipfile, os
with zipfile.ZipFile('$ZIP_FILENAME', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for root, dirs, files in os.walk('anykernel'):
        dirs[:] = [d for d in dirs if d != '.git']
        for f in files:
            if f == '.gitignore': continue
            fp = os.path.join(root, f)
            arcname = os.path.relpath(fp, 'anykernel')
            zf.write(fp, arcname=arcname)
"
echo "=== Package complete: $ZIP_FILENAME ==="
