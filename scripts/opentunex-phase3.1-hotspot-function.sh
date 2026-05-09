#!/bin/bash
# =============================================================================
# phase3.1-hotspot-function.sh — Phase 3.1: Hotspot Function Analysis
# =============================================================================
# Usage: bash phase3.1-hotspot-function.sh <PID>
# Parameters:
#   PID  — Target process ID (required)
# Requires: perf, root privilege. Total runtime: ~60-90 seconds.
# ⚠️ HEAVYWEIGHT: Do NOT run concurrently with strace or other perf commands
#   on the same PID.
# =============================================================================


if [ -z "${1:-}" ]; then
    echo "Usage: bash phase3.1-hotspot-function.sh <PID>" >&2
    exit 1
fi

PID="$1"

echo "============================================================"
echo "Phase 3.1: Hotspot Function Analysis (PID=$PID)"
echo "============================================================"
echo ""

echo "--- perf record (15s sampling) ---"
perf record -p "$PID" -g -o /tmp/perf_phase3_1.data -- sleep 15

echo ""
echo "--- perf report ---"
perf report -i /tmp/perf_phase3_1.data --stdio --percent-limit 1

echo ""
echo "--- perf record for flamegraph (59Hz, 15s) ---"
perf record -F 59 -p "$PID" -g -o /tmp/perf_phase3_1_fg.data -- sleep 15
echo ""
echo "--- Generating flamegraph ---"
if command -v stackcollapse-perf.pl >/dev/null 2>&1 && command -v flamegraph.pl >/dev/null 2>&1; then
    perf script -i /tmp/perf_phase3_1_fg.data | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl > /tmp/flamegraph_phase3_1.svg 2>/dev/null \
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
echo "Data files: /tmp/perf_phase3_1.data, /tmp/perf_phase3_1_fg.data"
echo "============================================================"

