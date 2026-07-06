#!/sbin/sh
# fix_rogers_volte.sh — Enable VoLTE for Rogers (MCC 302, MNC 720)
#
# The stock carrier config XML is missing carrier_volte_available_bool,
# which prevents IMS registration and breaks VoLTE calls.
# This script patches the carrier config on every flash.

ui_print "  -> Applying Rogers VoLTE fix...";

# Find carrier config files matching this SIM's carrier ID (1403 = Rogers)
CC_DIR="/data/user_de/0/com.android.phone/files";
CC_PATTERN="carrierconfig-com.android.carrierconfig-*";

found=0;
for cc_file in ${CC_DIR}/${CC_PATTERN}; do
  [ -f "$cc_file" ] || continue;

  # Check if this config already has VoLTE enabled
  if grep -q 'carrier_volte_available_bool" value="true"' "$cc_file" 2>/dev/null; then
    ui_print "     $cc_file already patched, skipping.";
    found=1;
    continue;
  fi;

  # Add VoLTE support before closing </bundle>
  if grep -q '</bundle>' "$cc_file"; then
    sed -i 's|</bundle>|<boolean name="carrier_volte_available_bool" value="true" />\n<boolean name="carrier_volte_provisioning_required_bool" value="false" />\n<boolean name="carrier_ims_gba_required_bool" value="false" />\n</bundle>|' "$cc_file";
    if [ $? -eq 0 ]; then
      ui_print "     Patched: $cc_file";
      found=1;
    else
      ui_print "     WARNING: Failed to patch $cc_file";
    fi;
  fi;
done;

if [ "$found" -eq 0 ]; then
  ui_print "     No carrier config files found (first boot?).";
  ui_print "     VoLTE fix will apply after SIM registration.";
fi;

ui_print "  -> Rogers VoLTE fix complete.";
