#!/system/bin/sh
#
# Quick Audio EC Check — non-interactive, headless-safe
# Just checks kernel audio subsystem health, no user input needed.
#
# Usage:
#   adb push scripts/test_audio_ec_quick.sh /data/local/tmp/
#   adb shell chmod +x /data/local/tmp/test_audio_ec_quick.sh
#   adb shell su -c /data/local/tmp/test_audio_ec_quick.sh
#
# Exit: 0 = PASS, 1 = FAIL
#

echo "Audio EC Quick Check — Poco F3 / SM8250"
echo "========================================="
echo ""

FAIL=0
PASS=0

check() {
    # check <pass_msg> <fail_msg> <command>
    _msg="$1"
    _fail_msg="$2"
    shift 2
    _out=$("$@" 2>/dev/null)
    _rc=$?
    if [ $_rc -eq 0 ] && [ -n "$_out" ]; then
        echo "  [PASS] $_msg"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $_fail_msg"
        FAIL=$((FAIL + 1))
    fi
}

echo "1. ALSA Sound Subsystem"
check "Sound cards present" \
      "No /proc/asound/cards" \
      cat /proc/asound/cards

check "PCM devices present" \
      "No /proc/asound/pcm" \
      cat /proc/asound/pcm

echo ""
echo "2. Audio Codec"
if [ -f /proc/asound/card0/codec#0 ]; then
    _codec=$(head -3 /proc/asound/card0/codec#0 2>/dev/null)
    if echo "$_codec" | grep -qi "wcd938\|wcd934\|wcd"; then
        echo "  [PASS] WCD codec detected: $_codec"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] Non-WCD codec: $_codec"
    fi
else
    echo "  [FAIL] Cannot read codec info"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "3. EC Reference Controls"
# Try tinymix
for _tm in /vendor/bin/tinymix /system/bin/tinymix tinymix; do
    if command -v "$_tm" >/dev/null 2>&1 || [ -x "$_tm" ]; then
        _ec=$("$_tm" 2>/dev/null | grep -iE 'ec_ref|aec|echo' | head -5)
        _ecn=$(echo "$_ec" | grep -c . || true)
        if [ "$_ecn" -gt 0 ]; then
            echo "  [PASS] EC mixer controls found ($_ecn)"
            echo "$_ec" | sed 's/^/    /'
            PASS=$((PASS + 1))
        else
            echo "  [WARN] No EC controls via tinymix"
        fi
        break
    fi
done

echo ""
echo "4. Audio HAL"
if ls /vendor/lib64/hw/audio.primary.*.so 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo "  [PASS] Audio HAL present"
    PASS=$((PASS + 1))
elif ls /vendor/lib/hw/audio.primary.*.so 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo "  [PASS] Audio HAL present (32-bit)"
    PASS=$((PASS + 1))
else
    echo "  [FAIL] Audio HAL not found"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "5. Voice Call / AEC Framework"
if command -v dumpsys >/dev/null 2>&1; then
    _aec=$(dumpsys audio 2>/dev/null | grep -icE 'aec|echo.?cancel' || true)
    if [ "$_aec" -gt 0 ]; then
        echo "  [PASS] AEC framework references ($_aec)"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] No AEC references in dumpsys audio"
    fi
else
    echo "  [WARN] dumpsys unavailable"
fi

echo ""
echo "6. Kernel Modules"
if command -v lsmod >/dev/null 2>&1; then
    _snd=$(lsmod 2>/dev/null | grep -c 'snd' || true)
    if [ "$_snd" -gt 0 ]; then
        echo "  [PASS] $_snd snd modules loaded"
        PASS=$((PASS + 1))
    else
        echo "  [WARN] No snd modules in lsmod (may be built-in)"
    fi
fi

echo ""
echo "========================================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "========================================="
if [ "$FAIL" -eq 0 ]; then
    echo "  RESULT: PASS — Audio subsystem OK"
    exit 0
else
    echo "  RESULT: FAIL — $FAIL issue(s) found"
    exit 1
fi
