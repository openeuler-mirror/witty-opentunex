#!/bin/bash
# =============================================================================
# phase3.1-hotspot-function.sh — Phase 3.1: Hotspot Function Analysis
# =============================================================================
# Usage: bash phase3.1-hotspot-function.sh --pid <PID> [--duration <SECONDS>]
# Parameters:
#   --pid      — Target process ID (required)
#   --duration — Collection duration in seconds (optional, default: 15)
# Requires: perf, root privilege. Total runtime: ~30-45 seconds (single 99Hz 15s record).
# ⚠️ HEAVYWEIGHT: Do NOT run concurrently with strace or other perf commands
#   on the same PID.
# =============================================================================

DURATION=15
PID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pid)
            PID="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: bash phase3.1-hotspot-function.sh --pid <PID> [--duration <SECONDS>]" >&2
            exit 1
            ;;
    esac
done

if [ -z "$PID" ]; then
    echo "Error: --pid is required" >&2
    echo "Usage: bash phase3.1-hotspot-function.sh --pid <PID> [--duration <SECONDS>]" >&2
    exit 1
fi

echo "============================================================"
echo "Phase 3.1: Hotspot Function Analysis (PID=$PID)"
echo "============================================================"
echo ""

echo "--- perf record (99Hz, ${DURATION}s sampling) ---"
perf record -F 99 -p "$PID" -g -o /tmp/perf_phase3_1.data -- sleep "$DURATION"

echo ""
echo "--- perf report ---"
perf report -i /tmp/perf_phase3_1.data --stdio --percent-limit 1

echo ""
echo "--- Generating flamegraph ---"
if command -v stackcollapse-perf.pl >/dev/null 2>&1 && command -v flamegraph.pl >/dev/null 2>&1; then
    perf script -i /tmp/perf_phase3_1.data | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl > /tmp/flamegraph_phase3_1.svg 2>/dev/null \
        && echo "Flamegraph saved to /tmp/flamegraph_phase3_1.svg" \
        || echo "Flamegraph generation failed"
else
    echo "Flamegraph generation skipped (stackcollapse-perf.pl / flamegraph.pl not installed)"
    echo "To install:"
    echo "  curl -k -o /usr/local/bin/stackcollapse-perf.pl https://raw.githubusercontent.com/brendangregg/FlameGraph/master/stackcollapse-perf.pl"
    echo "  curl -k -o /usr/local/bin/flamegraph.pl https://raw.githubusercontent.com/brendangregg/FlameGraph/master/flamegraph.pl"
    echo "  chmod +x /usr/local/bin/stackcollapse-perf.pl /usr/local/bin/flamegraph.pl"
fi

echo ""
echo "============================================================"
echo "Phase 3.1: Hotspot Function Analysis Complete (PID=$PID)"
echo "Data file: /tmp/perf_phase3_1.data"
echo "============================================================"

