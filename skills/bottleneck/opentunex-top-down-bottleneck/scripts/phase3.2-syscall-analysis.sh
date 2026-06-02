#!/bin/bash
# =============================================================================
# phase3.2-syscall-analysis.sh — Phase 3.2: Syscall Analysis
# =============================================================================
#
# Usage:
#   bash phase3.2-syscall-analysis.sh --pid <PID> [--duration <SECONDS>]
#
# Parameters:
#   --pid      — Target process ID (required)
#   --duration — Collection duration in seconds (optional, default: 10)
#
# Requires: strace, root privilege. Total runtime: depends on duration.
# ⚠️ HEAVYWEIGHT: Must run AFTER phase3.1 completes. Do NOT run concurrently
#   with perf record/perf stat on the same PID.
# ⚠️ strace -c (aggregate summary) and strace -T (per-call latency) are
#   serialized here — they cannot be combined in one invocation (-T has no
#   effect with -c).
# ⚠️ strace -c -f shows per-syscall aggregate counts/times/errors across all
#   threads. strace -T -f shows wall-clock time spent in each individual
#   syscall invocation, useful for outlier latency analysis.
#
# Examples:
#   # Collect for PID 12345 with default duration:
#   bash phase3.2-syscall-analysis.sh --pid 12345
#
#   # Collect for PID 12345 for 20 seconds:
#   bash phase3.2-syscall-analysis.sh --pid 12345 --duration 20
#
# Save output to file:
#   bash phase3.2-syscall-analysis.sh --pid 12345 --duration 20 > phase3.2_result.txt 2>&1
# =============================================================================

DURATION=10
PID=""

parse_param() {
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
                echo "Usage: bash $0 --pid <PID> [--duration <SECONDS>]" >&2
                exit 1
                ;;
        esac
    done

    if [ -z "$PID" ]; then
        echo "Error: --pid is required" >&2
        echo "Usage: bash $0 --pid <PID> [--duration <SECONDS>]" >&2
        exit 1
    fi
}

collect_syscall_analysis() {
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
        awk 'NF>=2 && $NF~/\.[0-9]+$/ {t=$NF; gsub(/[<>]/,"",t); print t, $0}' \
            /tmp/strace_T_phase3_2.log 2>/dev/null | \
            sort -k1 -rn 2>/dev/null | head -20
        rm -f /tmp/strace_T_phase3_2.log
    fi

    echo ""
    echo "============================================================"
    echo "Phase 3.2: Syscall Analysis Complete (PID=$PID)"
    echo "============================================================"
}

parse_param "$@"
collect_syscall_analysis
