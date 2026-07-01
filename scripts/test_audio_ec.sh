#!/system/bin/sh
#
# Audio Echo Cancellation (EC) Test Script
# Target: Poco F3 (alioth / SM8250 / WCD9380 / TFA9874)
#
# Usage (from host):
#   adb push scripts/test_audio_ec.sh /data/local/tmp/
#   adb shell chmod +x /data/local/tmp/test_audio_ec.sh
#   adb shell su -c /data/local/tmp/test_audio_ec.sh
#
# What this tests:
#   1. ALSA sound subsystem initialization (cards, PCM devices, modules)
#   2. EC reference path mixer controls (hardware AEC via Bolero/WCD938x)
#   3. Audio HAL and framework readiness for echo cancellation
#   4. Codec-level EC registration and firmware
#   5. (Optional) Audio loopback echo detection via tinyalsa
#
# Exit codes: 0 = PASS, 1 = FAIL
#

# No set -e: we handle errors explicitly per test
PASS=0
FAIL=0
WARN=0
TOTAL=0
TMPDIR="/data/local/tmp/_ec_test_$$"
DETAIL=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
cleanup() {
    rm -rf "$TMPDIR" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$TMPDIR"

pass() {
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
    echo "  [PASS] $1"
    DETAIL="${DETAIL}PASS  $1
"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $1"
    DETAIL="${DETAIL}FAIL  $1
"
}

warn() {
    WARN=$((WARN + 1))
    echo "  [WARN] $1"
    DETAIL="${DETAIL}WARN  $1
"
}

info() {
    echo "  [INFO] $1"
}

header() {
    echo ""
    echo "================================================================"
    echo " $1"
    echo "================================================================"
}

# File size in bytes (works on Android toybox)
file_size() {
    _sz=$(stat -c '%s' "$1" 2>/dev/null)
    if [ -z "$_sz" ]; then
        _sz=$(ls -l "$1" 2>/dev/null | awk '{print $5}')
    fi
    echo "${_sz:-0}"
}

# Calculate RMS of raw 16-bit PCM (signed LE) using awk
calc_rms() {
    _file="$1"
    _bytes="$2"
    if [ ! -f "$_file" ] || [ "$_bytes" -le 0 ] 2>/dev/null; then
        echo "0"
        return
    fi
    # od -t i2 converts to signed 16-bit integers; awk computes RMS
    # Use dd to limit bytes read (od may be slow on huge files)
    dd if="$_file" bs=4096 count=$(( (_bytes / 4096) + 1 )) 2>/dev/null | \
        od -A n -t i2 -v | \
        awk '{
            for (i = 1; i <= NF; i++) {
                v = $i + 0
                s += v * v
                n++
            }
        }
        END {
            if (n > 0) printf "%d", sqrt(s / n)
            else print 0
        }'
}

# ---------------------------------------------------------------------------
# PHASE 0: Tool Detection
# ---------------------------------------------------------------------------
header "PHASE 0: Tool Detection"

HAS_TINYCAP=0
HAS_TINYPLAY=0
HAS_TINYMIX=0

# Locate tinyalsa binaries
for tool in tinycap tinyplay tinymix; do
    _path=""
    for dir in /vendor/bin /system/bin /sbin /data/local/tmp; do
        if [ -x "$dir/$tool" ]; then
            _path="$dir/$tool"
            break
        fi
    done
    if [ -n "$_path" ]; then
        info "Found: $_path"
        case "$tool" in
            tinycap)  HAS_TINYCAP=1;  TINYCAP_BIN="$_path" ;;
            tinyplay) HAS_TINYPLAY=1; TINYPLAY_BIN="$_path" ;;
            tinymix)  HAS_TINYMIX=1;  TINYMIX_BIN="$_path" ;;
        esac
    fi
done

# Root check
IS_ROOT=0
if [ "$(id -u 2>/dev/null)" = "0" ]; then
    IS_ROOT=1
    info "Running as root"
else
    info "Running as non-root (some sysfs/debugfs may be restricted)"
fi

# ---------------------------------------------------------------------------
# PHASE 1: ALSA Sound Subsystem
# ---------------------------------------------------------------------------
header "PHASE 1: ALSA Sound Subsystem"

# 1a. Sound cards
if [ -f /proc/asound/cards ]; then
    CARDS_RAW=$(cat /proc/asound/cards)
    # Count non-blank lines that start with a digit
    CARD_COUNT=$(echo "$CARDS_RAW" | grep -cE '^\s*[0-9]' || true)
    info "Sound cards: $CARD_COUNT"
    echo "$CARDS_RAW" | head -8

    if [ "$CARD_COUNT" -ge 1 ]; then
        pass "ALSA sound cards present ($CARD_COUNT)"
    else
        fail "No ALSA sound cards — audio subsystem NOT initialized"
    fi
else
    fail "/proc/asound/cards missing — ALSA unavailable"
fi

# 1b. PCM devices
if [ -f /proc/asound/pcm ]; then
    PCM_RAW=$(cat /proc/asound/pcm)
    PCM_LINES=$(echo "$PCM_RAW" | grep -c 'subdevice' || true)
    info "PCM subdevices: $PCM_LINES"
    echo "$PCM_RAW" | head -20

    if [ "$PCM_LINES" -ge 4 ]; then
        pass "PCM devices sufficient ($PCM_LINES subdevices)"
    elif [ "$PCM_LINES" -ge 1 ]; then
        warn "Only $PCM_LINES PCM subdevice(s) — may be limited"
    else
        fail "No PCM subdevices found"
    fi
else
    warn "/proc/asound/pcm not readable"
fi

# 1c. Kernel sound modules
if command -v lsmod >/dev/null 2>&1; then
    SND_MODS=$(lsmod 2>/dev/null | grep -i snd)
    SND_MOD_COUNT=$(echo "$SND_MODS" | grep -c 'snd' || true)
    info "Loaded snd modules: $SND_MOD_COUNT"
    echo "$SND_MODS" | head -15

    # WCD codec
    if echo "$SND_MODS" | grep -q "snd_soc_wcd938\|snd_soc_wcd"; then
        pass "WCD codec module loaded"
    else
        warn "WCD module not in lsmod (may be built-in)"
    fi

    # Bolero digital codec macros
    if echo "$SND_MODS" | grep -qE "snd_soc_(bolero|rx_macro|wsa_macro|va_macro)"; then
        pass "Bolero digital codec modules loaded"
    else
        warn "Bolero modules not in lsmod (may be built-in)"
    fi
else
    warn "lsmod not available"
fi

# ---------------------------------------------------------------------------
# PHASE 2: EC Reference Path (Hardware AEC)
# ---------------------------------------------------------------------------
header "PHASE 2: EC Reference Path (Hardware AEC)"

# 2a. Tinymix EC controls
EC_CONTROLS=""
if [ "$HAS_TINYMIX" -eq 1 ]; then
    EC_CONTROLS=$("$TINYMIX_BIN" 2>/dev/null | grep -iE 'ec_ref|ec ref|ec_hq|aec|echo' || true)
    EC_CTL_COUNT=$(echo "$EC_CONTROLS" | grep -c . || true)
    info "EC-related mixer controls: $EC_CTL_COUNT"
    echo "$EC_CONTROLS" | head -20

    if [ "$EC_CTL_COUNT" -ge 1 ]; then
        pass "EC mixer controls present"
    else
        warn "No EC-specific mixer controls via tinymix (may use different naming)"
    fi

    # Look for specific EC_REF_HQ path
    EC_HQ=$(echo "$EC_CONTROLS" | grep -i "EC_REF_HQ\|EC HQ\|EC_REF" || true)
    if [ -n "$EC_HQ" ]; then
        info "EC_REF_HQ controls:"
        echo "$EC_HQ"
        pass "EC Reference HQ path controls registered"
    fi
else
    warn "tinymix unavailable — cannot inspect mixer controls"
fi

# 2b. Codec identification via /proc/asound
if [ -f /proc/asound/card0/codec#0 ]; then
    CODEC_LINE=$(head -3 /proc/asound/card0/codec#0 2>/dev/null)
    info "Codec: $CODEC_LINE"
    if echo "$CODEC_LINE" | grep -qi "wcd938"; then
        pass "WCD938x codec confirmed"
    elif echo "$CODEC_LINE" | grep -qi "wcd934"; then
        info "WCD934x codec (SM8250 compatible family)"
        pass "WCD codec confirmed"
    else
        warn "Unexpected codec: $CODEC_LINE"
    fi
elif [ -f /proc/asound/card0/id ]; then
    CID=$(cat /proc/asound/card0/id 2>/dev/null)
    info "Card 0 ID: $CID"
fi

# 2c. sysfs / debugfs
for sp in \
    /sys/module/snd_soc_bolero \
    /sys/module/snd_soc_core \
    /sys/kernel/debug/asoc; do
    if [ -d "$sp" ]; then
        info "Found: $sp"
    fi
done

# ---------------------------------------------------------------------------
# PHASE 3: Audio HAL & Framework
# ---------------------------------------------------------------------------
header "PHASE 3: Audio HAL & Framework"

# 3a. dumpsys audio
if command -v dumpsys >/dev/null 2>&1; then
    # AEC references in audio service
    AEC_DUMP=$(dumpsys audio 2>/dev/null | grep -iE 'aec|echo.?cancel|ec.?ref' || true)
    AEC_DN=$(echo "$AEC_DUMP" | grep -c . || true)

    if [ "$AEC_DN" -ge 1 ]; then
        info "AEC in dumpsys audio ($AEC_DN lines):"
        echo "$AEC_DUMP" | head -10
        pass "Audio framework AEC references present"
    else
        warn "No explicit AEC references in dumpsys audio"
    fi

    # Audio mode
    AMODE=$(dumpsys audio 2>/dev/null | grep -i 'mode:' | head -1)
    [ -n "$AMODE" ] && info "Current: $AMODE"
else
    warn "dumpsys unavailable"
fi

# 3b. Audio HAL .so
HAL_FOUND=0
for pat in \
    /vendor/lib64/hw/audio.primary.*.so \
    /vendor/lib/hw/audio.primary.*.so; do
    _f=$(ls $pat 2>/dev/null | head -1)
    if [ -n "$_f" ]; then
        info "Audio HAL: $_f"
        pass "Audio HAL library present"
        HAL_FOUND=1
        break
    fi
done
[ "$HAL_FOUND" -eq 0 ] && warn "Audio HAL .so not found in standard paths"

# 3c. Audio policy configuration
for apc in \
    /vendor/etc/audio_policy_configuration.xml \
    /vendor/etc/audio/sku_64/audio_policy_configuration.xml \
    /odm/etc/audio_policy_configuration.xml; do
    if [ -f "$apc" ]; then
        info "Found audio policy: $apc"
        EC_IN_APC=$(grep -ciE 'ec_ref|echo_cancel|aec' "$apc" 2>/dev/null || true)
        if [ "$EC_IN_APC" -gt 0 ]; then
            info "EC references in audio policy: $EC_IN_APC"
            pass "Audio policy has EC config"
        else
            info "No explicit EC entries (handled at HAL/driver level)"
        fi
        break
    fi
done

# ---------------------------------------------------------------------------
# PHASE 4: Codec-Level EC Registration
# ---------------------------------------------------------------------------
header "PHASE 4: Codec EC Registration"

# 4a. Card sysfs
if [ -f /sys/class/sound/card0/id ]; then
    CID=$(cat /sys/class/sound/card0/id 2>/dev/null)
    info "card0 sysfs ID: $CID"
    pass "Sound card 0 registered in sysfs"
fi

# 4b. WCD firmware
FW_FOUND=0
for fw_dir in /vendor/firmware /lib/firmware /etc/firmware /vendor/etc; do
    _fw=$(ls "$fw_dir"/wcd* "$fw_dir"/WCD* 2>/dev/null | head -3)
    if [ -n "$_fw" ]; then
        info "WCD firmware in $fw_dir:"
        echo "$_fw"
        pass "WCD firmware files present"
        FW_FOUND=1
        break
    fi
done
[ "$FW_FOUND" -eq 0 ] && info "No standalone WCD firmware files (may be bundled in DT/fallback)"

# ---------------------------------------------------------------------------
# PHASE 5: Voice Call EC Readiness
# ---------------------------------------------------------------------------
header "PHASE 5: Voice Call EC Readiness"

if command -v dumpsys >/dev/null 2>&1; then
    VC_PATH=$(dumpsys audio 2>/dev/null | grep -iE 'voice.?call|IN_CALL|voice_call_rx' || true)
    if [ -n "$VC_PATH" ]; then
        info "Voice call audio paths configured"
        pass "Voice call routing present"
    else
        warn "Voice call paths not visible (may need active call to expose)"
    fi
fi

# ---------------------------------------------------------------------------
# PHASE 6: Audio Loopback Echo Test (Optional)
# ---------------------------------------------------------------------------
header "PHASE 6: Audio Loopback Echo Test"

echo ""
echo "  This test records mic audio while playing a tone through the"
echo "  speaker.  If EC is working, the recording will show LOW echo."
echo "  If EC is broken, the recording will show HIGH echo."
echo ""
echo "  Place the phone on a table, face-down. Keep room quiet."
echo ""
echo "  Run this test? [y/N]: "
read _ans </dev/tty 2>/dev/null || _ans="N"

if echo "$_ans" | grep -qi '^y'; then
    CAN_TEST=0
    if [ "$HAS_TINYCAP" -eq 1 ] && [ "$HAS_TINYPLAY" -eq 1 ]; then
        CAN_TEST=1
    else
        warn "tinycap/tinyplay unavailable — loopback test skipped"
    fi

    if [ "$CAN_TEST" -eq 1 ]; then
        # --- Determine PCM device numbers from /proc/asound/pcm ---
        # On SM8250 with WCD9380:
        #   PCM 0-0: primary playback
        #   PCM 0-1: primary capture (mic)
        #   PCM 0-2: low-latency playback
        #   PCM 0-4: deep-buffer playback
        #   PCM 0-6: compress offload
        # Typical capture = hw:0,0, playback = hw:0,0
        CAP_CARD=0
        CAP_DEV=0
        PLAY_CARD=0
        PLAY_DEV=0

        # Try to find better devices
        if [ -f /proc/asound/pcm ]; then
            # Look for capture-capable device
            CAP_LINE=$(grep -iE 'capture' /proc/asound/pcm | head -1)
            if [ -n "$CAP_LINE" ]; then
                CAP_DEV=$(echo "$CAP_LINE" | grep -oE '[0-9]+-[0-9]+' | head -1 | cut -d- -f2)
                [ -z "$CAP_DEV" ] && CAP_DEV=0
            fi
            PLAY_LINE=$(grep -iE 'playback' /proc/asound/pcm | head -1)
            if [ -n "$PLAY_LINE" ]; then
                PLAY_DEV=$(echo "$PLAY_LINE" | grep -oE '[0-9]+-[0-9]+' | head -1 | cut -d- -f2)
                [ -z "$PLAY_DEV" ] && PLAY_DEV=0
            fi
        fi
        info "Capture: hw:${CAP_CARD},${CAP_DEV}  Play: hw:${PLAY_CARD},${PLAY_DEV}"

        # Step 1: Record baseline (silence)
        echo "  [1/4] Recording baseline silence (${RECORD_SECONDS:-3}s)..."
        "$TINYCAP_BIN" -D "$CAP_CARD" -d "$CAP_DEV" \
            -c 2 -r 48000 -b 16 -t 3 \
            "$TMPDIR/baseline.wav" 2>/dev/null
        BSIZE=$(file_size "$TMPDIR/baseline.wav")
        info "Baseline size: $BSIZE bytes"

        BASELINE_RMS=0
        if [ "$BSIZE" -gt 1000 ] 2>/dev/null; then
            BASELINE_RMS=$(calc_rms "$TMPDIR/baseline.wav" "$BSIZE")
            info "Baseline RMS: $BASELINE_RMS"
        fi

        # Step 2: Generate 440 Hz tone via awk (no python3 needed)
        echo "  [2/4] Generating test tone..."
        awk -v sr=48000 -v hz=440 -v dur=3 -v amp=16000 '
        BEGIN {
            n = sr * dur
            for (i = 0; i < n; i++) {
                v = int(amp * sin(2 * 3.14159265 * hz * i / sr))
                # Write as two channels (stereo), little-endian 16-bit signed
                printf "%c%c", v % 256, int(v / 256) % 256
                printf "%c%c", v % 256, int(v / 256) % 256
            }
        }' > "$TMPDIR/tone.raw" 2>/dev/null

        TONE_SIZE=$(file_size "$TMPDIR/tone.raw")
        info "Tone generated: $TONE_SIZE bytes"

        if [ "$TONE_SIZE" -lt 1000 ]; then
            warn "Tone generation failed — skipping loopback"
        else
            # Step 3: Play tone + record simultaneously
            echo "  [3/4] Playing tone + recording..."
            "$TINYPLAY_BIN" -D "$PLAY_CARD" -d "$PLAY_DEV" \
                -c 2 -r 48000 -b 16 \
                "$TMPDIR/tone.raw" 2>/dev/null &
            PLAY_PID=$!

            # Small delay to let playback start
            sleep 1

            "$TINYCAP_BIN" -D "$CAP_CARD" -d "$CAP_DEV" \
                -c 2 -r 48000 -b 16 -t 3 \
                "$TMPDIR/ec_test.wav" 2>/dev/null
            CAP_DONE=$?

            # Wait for playback to finish
            wait $PLAY_PID 2>/dev/null || true

            EC_SIZE=$(file_size "$TMPDIR/ec_test.wav")
            info "EC test recording: $EC_SIZE bytes"

            if [ "$EC_SIZE" -gt 1000 ] 2>/dev/null; then
                EC_RMS=$(calc_rms "$TMPDIR/ec_test.wav" "$EC_SIZE")
                info "During-playback RMS: $EC_RMS"

                echo "  [4/4] Analyzing..."

                # Threshold: well-functioning EC should keep the mic RMS
                # low even with speaker outputting a tone.
                # These are empirical thresholds for WCD9380 + TFA9874:
                #   < 5000  = EC working well
                #   5000-15000 = partial EC
                #   > 15000 = EC broken
                if [ "$EC_RMS" -lt 5000 ] 2>/dev/null; then
                    pass "Echo RMS LOW ($EC_RMS < 5000) — EC functional"
                elif [ "$EC_RMS" -lt 15000 ] 2>/dev/null; then
                    warn "Echo RMS MEDIUM ($EC_RMS, range 5000-15000) — EC partially working"
                else
                    fail "Echo RMS HIGH ($EC_RMS > 15000) — EC appears BROKEN"
                fi

                # Also report the ratio vs baseline
                if [ "$BASELINE_RMS" -gt 0 ] 2>/dev/null; then
                    RATIO=$((EC_RMS * 100 / BASELINE_RMS))
                    info "Echo/Baseline ratio: ${RATIO}% (${EC_RMS} / ${BASELINE_RMS})"
                fi
            else
                fail "EC test recording failed or too short"
            fi
        fi
    fi
else
    info "Loopback test skipped by user"
fi

# ---------------------------------------------------------------------------
# FINAL REPORT
# ---------------------------------------------------------------------------
header "RESULTS SUMMARY"

echo ""
echo "  Passed:   $PASS / $((PASS + FAIL))"
echo "  Failed:   $FAIL / $((PASS + FAIL))"
echo "  Warnings: $WARN"
echo ""
echo "  ---"
echo "$DETAIL"

if [ "$FAIL" -eq 0 ]; then
    echo "  ========================================================"
    echo "  RESULT:  PASS"
    echo "  ========================================================"
    echo "  Audio EC subsystem appears functional."
    echo "  For definitive validation, make a voice call and ask the"
    echo "  other party if they hear echo."
    echo ""
    exit 0
else
    echo "  ========================================================"
    echo "  RESULT:  FAIL"
    echo "  ========================================================"
    echo "  $FAIL critical check(s) failed."
    echo "  Review the failures above; likely kernel audio config issue."
    echo ""
    exit 1
fi
