SLOT_SELECT=active
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=APTKernel by ApartTUSITU @ AstideLabs
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=alioth
device.name2=aliothin
device.name3=apollo
device.name4=apolloin
device.name5=lmi
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

NO_BLOCK_DISPLAY=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

## Select the correct image to flash
userflavor="$(file_getprop /system/build.prop "ro.build.flavor")";
case "$userflavor" in
    missi*|qssi*) os="miui"; os_string="MIUI ROM";;
    *) os="aosp"; os_string="AOSP ROM";;
esac;
ui_print "  -> $os_string is detected!";
if [ -f $AKHOME/kernels/$os/Image ] && [ -f $AKHOME/kernels/$os/dtb ] && [ -f $AKHOME/kernels/$os/dtbo.img ]; then
    mv $AKHOME/kernels/$os/Image $AKHOME/Image;
    mv $AKHOME/kernels/$os/dtb $AKHOME/dtb;
    #mv $AKHOME/kernels/$os/dtbo.img $AKHOME/dtbo.img; # uncomment this
else
    ui_print "  -> There is no kernel for $os_string in this zip! Aborting...";
    ui_print "  -> Please check that you have the correct kernel zip!";
    exit 1;
fi;
ui_print "  -> Flashing DTBO is not recommended by default.";
ui_print "  -> If you need to flash them, please uncomment the code in the script.";

# boot install
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
split_boot;
flash_boot;
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
#flash_dtbo; # uncomment this
# Post-flash: apply VoLTE carrier config fix
for script in ${AKHOME}/anykernel-modules/fix_*.sh; do
  if [ -f "$script" ] && [ -x "$script" ]; then
    . "$script";
  fi;
done;
 ## end boot install
