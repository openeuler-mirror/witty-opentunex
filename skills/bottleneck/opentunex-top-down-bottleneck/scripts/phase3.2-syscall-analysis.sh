#!/bin/bash
# =============================================================================
# phase3.2-syscall-analysis.sh — Phase 3.2: Syscall Analysis
# =============================================================================
# Usage: bash phase3.2-syscall-analysis.sh --pid <PID> [--duration <SECONDS>]
# Parameters:
#   --pid      — Target process ID (required)
#   --duration — Collection duration in seconds (optional, default: 10)
# Requires: strace, root privilege. Total runtime: depends on duration.
# ⚠️ HEAVYWEIGHT: Must run AFTER phase3.1 completes. Do NOT run concurrently
#   with perf record/perf stat on the same PID.
# ⚠️ strace -c (aggregate summary) and strace -T (per-call latency) are
#   serialized here — they cannot be combined in one invocation (-T has no
#   effect with -c).
# ⚠️ strace -c -f shows per-syscall aggregate counts/times/errors across all
#   threads. strace -T -f shows wall-clock time spent in each individual
#   syscall invocation, useful for outlier latency analysis.
# =============================================================================

DURATION=10
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
            echo "Usage: bash phase3.2-syscall-analysis.sh --pid <PID> [--duration <SECONDS>]" >&2
            exit 1
            ;;
    esac
done

if [ -z "$PID" ]; then
    echo "Error: --pid is required" >&2
    echo "Usage: bash phase3.2-syscall-analysis.sh --pid <PID> [--duration <SECONDS>]" >&2
    exit 1
fi

echo "============================================================"
echo "Phase 3.2: Syscall Analysis (PID=$PID)"
echo "============================================================"
echo ""

echo "--- strace -c -f: Aggregate syscall summary (counts, errors, times) ---"
timeout "$DURATION" strace -p "$PID" -c -f

echo ""
echo "--- strace -T -f: Per-call latency sample (${DURATION}s, top slowest) ---"
timeout "$DURATION" strace -p "$PID" -T -f -o /tmp/strace_T_phase3_2.log 2>&1 || true
if [ -f /tmp/strace_T_phase3_2.log ]; then
    # Extract syscall name and timing, show top 20 slowest calls
    awk 'NF>=2 && $NF~/\.[0-9]+$/ {t=$NF; gsub(/[<>]/,"",t); print t, $0}' \
        /tmp/strace_T_phase3_2.log 2>/dev/null | \
        sort -k1 -rn 2>/dev/null | head -20
    rm -f /tmp/strace_T_phase3_2.log
fi

echo ""
echo "============================================================"
echo "Phase 3.2: Syscall Analysis Complete (PID=$PID)"
echo "============================================================"

