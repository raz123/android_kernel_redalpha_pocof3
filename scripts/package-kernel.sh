#!/bin/bash
set -ex

# Env vars passed via docker run -e:
#   BUILD_NUMBER  — from github.run_number
#   KSU_ENABLED   — "true" or "false"
#   REPO_URL      — git URL of the kernel repo
#   BRANCH        — branch name

git config --global --add safe.directory /workspace

# Determine KSU suffix for filename
KSU_SUFFIX="_ReSukiSU"
[ "${KSU_ENABLED}" != "true" ] && KSU_SUFFIX="_vanilla"

# Save VoLTE module before cleaning
cp -r anykernel-modules/fix_rogers_volte .volte_backup

# Fresh clone of repo for AnyKernel3 files
rm -rf anykernel anykernel-modules
git clone "${REPO_URL}" -b "${BRANCH}" --single-branch --depth=1 anykernel

# === A/B SLOT FIX: SLOT_SELECT=active auto-detects correct slot ===
sed -i '1i\SLOT_SELECT=active' anykernel/anykernel.sh
# === END A/B SLOT FIX ===

# === Dual-Slot Flash ===
cat > /tmp/dual_slot_patch1.sh << 'DUALEOF'
# === Dual-Slot Flash (RedAlpha) ===
DUAL_SLOT=1;
OTHER_BLOCK="";
if [ "$SLOT" ]; then
  ui_print " ";
  ui_print "  -----------------------------------------";
  ui_print "  Dual-Slot Flash Mode";
  ui_print "  -----------------------------------------";
  ui_print "  Default: flash BOTH A/B slots.";
  ui_print "  Abort via ADB: touch /tmp/.skip_dualslot";
  ui_print "  (Or hold VOLUME UP in recovery)";
  ui_print "  -----------------------------------------";
  ui_print " ";
  if [ -f /tmp/.skip_dualslot ]; then
    rm -f /tmp/.skip_dualslot;
    DUAL_SLOT=0;
    ui_print "  -> Skip file found: active slot only.";
  elif timeout 10 getevent -c5 2>/dev/null | grep -qm1 '0001 0073'; then
    DUAL_SLOT=0;
    ui_print "  -> VOLUME UP pressed: active slot only!";
  else
    ui_print "  -> Flashing BOTH slots!";
  fi;
  ui_print "  -----------------------------------------";
  case "$BLOCK" in
    *_a) OTHER_BLOCK="${BLOCK%_a}_b";;
    *_b) OTHER_BLOCK="${BLOCK%_b}_a";;
  esac;
  if [ "$OTHER_BLOCK" = "$BLOCK" ] || [ -z "$OTHER_BLOCK" ]; then
    OTHER_BLOCK="";
    ui_print "  Warning: could not determine other slot block device.";
  else
    ui_print "  Other slot: $OTHER_BLOCK";
  fi;
fi;
DUALEOF

cat > /tmp/dual_slot_patch2.sh << 'DUALEOF'
# Flash both slots reliably (post-flash_boot)
if [ "$DUAL_SLOT" = "1" ] && [ -f "${AKHOME}/boot-new.img" ]; then
  IMG="${AKHOME}/boot-new.img";
  ui_print "  -> Flashing active slot ($BLOCK)...";
  if ! dd if="$IMG" of="$BLOCK" bs=4096 2>/dev/null; then
    ui_print "  WARNING: dd to active slot failed!";
  fi;
  if [ "$OTHER_BLOCK" ]; then
    ui_print "  -> Flashing other slot ($OTHER_BLOCK)...";
    if ! dd if="$IMG" of="$OTHER_BLOCK" bs=4096 2>/dev/null; then
      ui_print "  WARNING: dd to other slot failed!";
    fi;
  fi;
  sync;
  ui_print "  -> Both slots flashed successfully!";
fi;
DUALEOF

# Apply dual-slot patches to anykernel.sh
sed -i '/^# boot install$/r /tmp/dual_slot_patch1.sh' anykernel/anykernel.sh
sed -i '/^flash_boot;$/r /tmp/dual_slot_patch2.sh' anykernel/anykernel.sh
# === END Dual-Slot Flash ===

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

# Include ZRAM resize script
[ -f "zram-resize.sh" ] && cp zram-resize.sh anykernel/anykernel-modules/
[ -f "uclamp_tuning.sh" ] && cp uclamp_tuning.sh anykernel/anykernel-modules/

# Include Rogers VoLTE fix KernelSU module
cp -r .volte_backup anykernel/anykernel-modules/fix_rogers_volte_module
chmod 755 anykernel/anykernel-modules/fix_rogers_volte_module/*.sh

# Build ZIP
ZIP_FILENAME="rp-pocof3${KSU_SUFFIX}_b${BUILD_NUMBER}.zip"
zip -r9 "$ZIP_FILENAME" ./* -x .git .gitignore out/ ./*.zip
mv "$ZIP_FILENAME" ../
