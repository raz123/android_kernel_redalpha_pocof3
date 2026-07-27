#!/usr/bin/env bash
set -euo pipefail

# Repeatable Poco F3 MGLRU before/after benchmark.
#
# Workload:
#   1. Five cold launches of Android Settings while idle.
#   2. Five cold launches while resident tmpfs and CPU workers create
#      reclaim pressure.
#
# Pressure resources live below /data/local/tmp and are removed by the EXIT
# trap. No persistent VM setting is changed.

usage() {
    cat <<'EOF'
Usage: mglru-benchmark.sh [options]

Options:
  --label NAME          Result label (default: timestamp)
  --output DIR          Exact result directory (overrides --label)
  --serial SERIAL       adb device serial
  --samples N           Launch samples per phase (default: 5)
  --pressure-mb N       Resident tmpfs size (default: 1536)
  --cpu-workers N       Busy-loop workers (default: 6)
  --settle-seconds N    Idle wait between phases (default: 5)
  -h, --help            Show this help

Example:
  tools/mglru-benchmark.sh --label b276 --output diagnostics/mglru-benchmark-b276
EOF
}

SERIAL=""
LABEL="$(date +%Y%m%d-%H%M%S)"
OUTPUT=""
SAMPLES=5
PRESSURE_MB=1536
CPU_WORKERS=6
SETTLE_SECONDS=5

while [ "$#" -gt 0 ]; do
    case "$1" in
        --label)
            LABEL="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --serial)
            SERIAL="$2"
            shift 2
            ;;
        --samples)
            SAMPLES="$2"
            shift 2
            ;;
        --pressure-mb)
            PRESSURE_MB="$2"
            shift 2
            ;;
        --cpu-workers)
            CPU_WORKERS="$2"
            shift 2
            ;;
        --settle-seconds)
            SETTLE_SECONDS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$SAMPLES:$PRESSURE_MB:$CPU_WORKERS:$SETTLE_SECONDS" in
    *[!0-9:]*)
        echo "numeric options must be non-negative integers" >&2
        exit 2
        ;;
esac
[ "$SAMPLES" -gt 0 ] || { echo "samples must be greater than zero" >&2; exit 2; }
[ "$PRESSURE_MB" -gt 0 ] || { echo "pressure-mb must be greater than zero" >&2; exit 2; }
[ "$CPU_WORKERS" -gt 0 ] || { echo "cpu-workers must be greater than zero" >&2; exit 2; }

ADB=(adb)
[ -n "$SERIAL" ] && ADB+=(-s "$SERIAL")

if [ -z "$OUTPUT" ]; then
    OUTPUT="diagnostics/mglru-benchmark-$LABEL"
fi
mkdir -p "$OUTPUT"

adb_shell() {
    "${ADB[@]}" shell "$@"
}

adb_root() {
    "${ADB[@]}" shell su -c "$1"
}

snapshot() {
    local name="$1"
    {
        echo "host_timestamp=$(date -u +%Y%m%dT%H%M%SZ)"
        echo "kernel:"
        adb_shell uname -a
        echo "slot:"
        adb_shell getprop ro.boot.slot_suffix
        echo "lru_gen:"
        adb_shell sh -c 'cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null; cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null'
        echo "vm_controls:"
        adb_shell sh -c 'cat /proc/sys/vm/swappiness 2>/dev/null; cat /proc/sys/vm/watermark_scale_factor 2>/dev/null; cat /proc/sys/vm/min_free_kbytes 2>/dev/null'
        echo "meminfo:"
        adb_shell sh -c 'grep -E "^(MemTotal|MemFree|MemAvailable|Active|Inactive|Active[(]anon[)]|Inactive[(]anon[)]|Active[(]file[)]|Inactive[(]file[)]|SwapTotal|SwapFree|Shmem):" /proc/meminfo'
        echo "swaps:"
        adb_shell cat /proc/swaps
        echo "psi_memory:"
        adb_shell cat /proc/pressure/memory
        echo "vmstat:"
        adb_shell sh -c 'grep -E "^(pgscan_kswapd|pgsteal_kswapd|pgscan_direct|pgsteal_direct|pswpin|pswpout|oom_kill|workingset_refault|workingset_activate|workingset_restore|pgdemote|pgpromote) " /proc/vmstat'
    } > "$OUTPUT/$name.txt"
}

launch_once() {
    local phase="$1"
    local iteration="$2"
    local result total wait

    adb_shell am force-stop com.android.settings
    sleep 1
    result="$("${ADB[@]}" shell am start -W -a android.settings.SETTINGS 2>&1 | tr -d '\r')"
    total="$(printf '%s\n' "$result" | awk '/^TotalTime:/{print $2; exit}')"
    wait="$(printf '%s\n' "$result" | awk '/^WaitTime:/{print $2; exit}')"
    [ -n "$total" ] || total=0
    [ -n "$wait" ] || wait=0

    {
        echo "ITERATION $iteration $(date +%s)"
        printf '%s\n' "$result"
        echo "Complete"
    } >> "$OUTPUT/$phase-launch.txt"
    printf '%s\t%s\t%s\n' "$phase" "$iteration" "$total" >> "$OUTPUT/launch-times.tsv"
    printf '%s\t%s\t%s\n' "$phase" "$iteration" "$wait" >> "$OUTPUT/wait-times.tsv"
    echo "$phase $iteration: TotalTime=$total""ms WaitTime=$wait""ms"
}

PRESSURE_DIR="/data/local/tmp/mglru-benchmark-$$"
PRESSURE_ACTIVE=0

stop_pressure() {
    if [ "$PRESSURE_ACTIVE" -eq 1 ]; then
        echo "Stopping temporary pressure workload"
        adb_root "if [ -f '$PRESSURE_DIR/pids' ]; then while read p; do kill \$p 2>/dev/null || true; done < '$PRESSURE_DIR/pids'; fi; umount '$PRESSURE_DIR' 2>/dev/null || true; rm -rf '$PRESSURE_DIR'"
        PRESSURE_ACTIVE=0
    fi
}
trap stop_pressure EXIT INT TERM

start_pressure() {
    local output
    echo "Starting $PRESSURE_MB""MiB tmpfs and $CPU_WORKERS"" CPU workers"
    output="$(adb_root "rm -rf '$PRESSURE_DIR'; mkdir -p '$PRESSURE_DIR'; mount -t tmpfs -o size=$PRESSURE_MB""m mglru_benchmark '$PRESSURE_DIR'; dd if=/dev/zero of='$PRESSURE_DIR/pressure.bin' bs=1M count=$PRESSURE_MB >/dev/null 2>&1; sync; i=0; while [ \$i -lt $CPU_WORKERS ]; do (while :; do :; done) & echo \$! >> '$PRESSURE_DIR/pids'; i=\$((i+1)); done; echo READY" 2>&1)"
    printf '%s\n' "$output" > "$OUTPUT/pressure-start.txt"
    printf '%s\n' "$output" | grep -q READY || {
        echo "Could not start root pressure workload:" >&2
        printf '%s\n' "$output" >&2
        exit 1
    }
    PRESSURE_ACTIVE=1
}

summarize_file() {
    local input="$1"
    local output="$2"
    awk -F '\t' '
        NR == 1 { next }
        {
            phase=$1; value=$3 + 0
            count[phase]++
            sum[phase]+=value
            if (!(phase in min) || value < min[phase]) min[phase]=value
            if (!(phase in max) || value > max[phase]) max[phase]=value
        }
        END {
            for (phase in count)
                printf "%s\t%d\t%.1f\t%d\t%d\n", phase, count[phase], sum[phase]/count[phase], min[phase], max[phase]
        }
    ' "$input" | sort > "$output"
}

summarize() {
    summarize_file "$OUTPUT/launch-times.tsv" "$OUTPUT/launch-summary.tsv"
    summarize_file "$OUTPUT/wait-times.tsv" "$OUTPUT/wait-summary.tsv"

    {
        echo "MGLRU benchmark: $LABEL"
        echo
        echo "Workload: $SAMPLES cold Settings launches per phase; pressure=$PRESSURE_MB""MiB tmpfs, cpu_workers=$CPU_WORKERS."
        echo "All pressure resources were temporary and cleaned by the script."
        echo
        echo "TotalTime summary (phase, samples, mean_ms, min_ms, max_ms):"
        sed 's/^/  /' "$OUTPUT/launch-summary.tsv"
        echo
        echo "WaitTime summary (phase, samples, mean_ms, min_ms, max_ms):"
        sed 's/^/  /' "$OUTPUT/wait-summary.tsv"
        echo
        awk -F '\t' '
            $1 == "baseline" { idle=$3 }
            $1 == "pressure" { pressure=$3 }
            END {
                if (idle > 0 && pressure > 0)
                    printf "Pressure mean TotalTime delta: %.1f%%\n", ((pressure-idle)/idle)*100
            }
        ' "$OUTPUT/launch-summary.tsv"
    } > "$OUTPUT/summary.txt"
}

echo "Checking adb target"
"${ADB[@]}" get-state >/dev/null
adb_shell sh -c 'su -c id >/dev/null'

printf 'phase\titeration\tms\n' > "$OUTPUT/launch-times.tsv"
printf 'phase\titeration\tms\n' > "$OUTPUT/wait-times.tsv"

snapshot before
echo "Settling for $SETTLE_SECONDS""s before idle phase"
sleep "$SETTLE_SECONDS"
for i in $(seq 1 "$SAMPLES"); do
    launch_once baseline "$i"
    sleep 2
done
snapshot after-baseline

start_pressure
snapshot pressure-start
sleep 2
for i in $(seq 1 "$SAMPLES"); do
    snapshot "pressure-before-$i"
    launch_once pressure "$i"
    snapshot "pressure-after-$i"
    sleep 2
done
stop_pressure
sleep "$SETTLE_SECONDS"
snapshot after

summarize
echo
cat "$OUTPUT/summary.txt"
echo
echo "Results: $OUTPUT"
