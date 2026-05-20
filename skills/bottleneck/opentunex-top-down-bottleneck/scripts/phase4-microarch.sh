#!/bin/bash
# =============================================================================
# phase4-microarch.sh — Phase 4: Microarchitecture Bottleneck Analysis
# =============================================================================
# Usage: bash phase4-microarch.sh --pid <PID> [--duration <SECONDS>]
# Parameters:
#   --pid      — Target process ID (required)
#   --duration — Collection duration in seconds (optional, default: 15)
# Requires: perf, root privilege. Total runtime: ~3-4 minutes.
# ⚠️ HEAVYWEIGHT: All perf stat groups are serialized — PMU counter
#   multiplexing produces unreliable results if run in parallel.
# ⚠️ Must run AFTER phase3 completes (perf record/strace also use PMU).
# =============================================================================

DURATION=15
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

collect_microarch() {
    echo "============================================================"
    echo "Phase 4: Microarchitecture Bottleneck Analysis (PID=$PID)"
    echo "============================================================"
    echo ""

    echo "========== CPU Cache and TLB Analysis =========="

    echo "--- Cache Miss Rates and TLB Miss Statistics (15s) ---"
    perf stat -e L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses -p "$PID" -- sleep "$DURATION" || true

    echo ""
    echo "========== Pipeline Stall and Branch Prediction Analysis =========="

    echo "--- Pipeline Stall, Branch Prediction and Top-Down Analysis (15s) ---"
    perf stat -e stalled-cycles-frontend,stalled-cycles-backend,branches,branch-misses,cycles,instructions -p "$PID" -- sleep "$DURATION"

    echo ""
    echo "========== Cross-SCCL NUMA Analysis (ARM only) =========="

    echo "--- SCCL DRAM Access (15s, tolerate if unavailable) ---"
    perf stat -e remote_access,ll_cache_miss -p "$PID" -- sleep "$DURATION" || echo "(remote_access/ll_cache_miss not available on this platform)"
    echo "Cross-SCCL ratio = remote_access / (remote_access + ll_cache_miss) * 100%"


    echo ""
    echo "============================================================"
    echo "Phase 4: Microarchitecture Bottleneck Analysis Complete (PID=$PID)"
    echo "============================================================"
}

parse_param "$@"
collect_microarch
