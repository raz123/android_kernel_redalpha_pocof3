#!/system/bin/sh
# Rogers VoLTE carrier config fix (service.sh - runs after boot)
# Patches carrier config XML to enable VoLTE for Rogers (MCC 302/MNC 720)
CC_DIR=/data/user_de/0/com.android.phone/files
for f in $CC_DIR/carrierconfig-*.xml; do
  [ -f "$f" ] || continue
  grep -q 'carrier_volte_available_bool" value="true"' "$f" 2>/dev/null && continue
  grep -q '</bundle>' "$f" || continue
  sed -i 's|</bundle>|<boolean name="carrier_volte_available_bool" value="true" />\n<boolean name="carrier_volte_provisioning_required_bool" value="false" />\n<boolean name="carrier_ims_gba_required_bool" value="false" />\n</bundle>|' "$f"
done
