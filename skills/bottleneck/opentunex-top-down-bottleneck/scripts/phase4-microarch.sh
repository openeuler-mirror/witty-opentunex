#!/bin/bash
# =============================================================================
# phase4-microarch.sh — Phase 4: Microarchitecture Bottleneck Analysis
# =============================================================================
#
# Usage:
#   bash phase4-microarch.sh --pid <PID> [--duration <SECONDS>]
#
# Parameters:
#   --pid      — Target process ID (required)
#   --duration — Collection duration in seconds (optional, default: 15)
#
# Requires: perf, root privilege. Total runtime: ~3-4 minutes.
# ⚠️ HEAVYWEIGHT: All perf stat groups are serialized — PMU counter
#   multiplexing produces unreliable results if run in parallel.
# ⚠️ Must run AFTER phase3 completes (perf record/strace also use PMU).
#
# Examples:
#   # Collect for PID 12345 with default duration:
#   bash phase4-microarch.sh --pid 12345
#
#   # Collect for PID 12345 for 30 seconds:
#   bash phase4-microarch.sh --pid 12345 --duration 30
#
# Save output to file:
#   bash phase4-microarch.sh --pid 12345 --duration 30 > phase4_result.txt 2>&1
# =============================================================================

DURATION=15
PID=""

parse_param() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pid)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    echo "Error: --pid requires a value" >&2
                    echo "Usage: bash $0 --pid <PID> [--duration <SECONDS>]" >&2
                    exit 1
                fi
                PID="$2"
                shift 2
                ;;
            --duration)
                if [ -z "$2" ] || [[ "$2" == --* ]]; then
                    echo "Error: --duration requires a value" >&2
                    echo "Usage: bash $0 --pid <PID> [--duration <SECONDS>]" >&2
                    exit 1
                fi
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

    if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
        echo "Error: --pid must be a numeric value, got: $PID" >&2
        exit 1
    fi

    if [ ! -d "/proc/$PID" ]; then
        echo "Error: Process with PID $PID does not exist" >&2
        exit 1
    fi

    if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -le 0 ]; then
        echo "Error: --duration must be a positive integer, got: $DURATION" >&2
        exit 1
    fi
}

collect_microarch() {
    echo "============================================================"
    echo "Phase 4: Microarchitecture Bottleneck Analysis (PID=$PID)"
    echo "============================================================"
    echo ""

    if [ ! -d "/proc/$PID" ]; then
        echo "Error: PID $PID has exited before data collection" >&2
        return 1
    fi

    echo "========== CPU Cache and TLB Analysis =========="

    echo "--- Cache Miss Rates and TLB Miss Statistics (15s) ---"
    perf stat -e L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses,dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses -p "$PID" -- sleep "$DURATION" || echo "(Cache/TLB event collection failed or partially unavailable)"

    if [ ! -d "/proc/$PID" ]; then
        echo "Warning: PID $PID has exited, skipping remaining collections" >&2
        return 1
    fi

    echo ""
    echo "========== Pipeline Stall and Branch Prediction Analysis =========="

    echo "--- Pipeline Stall, Branch Prediction and Top-Down Analysis (15s) ---"
    perf stat -e stalled-cycles-frontend,stalled-cycles-backend,branches,branch-misses,cycles,instructions -p "$PID" -- sleep "$DURATION" || echo "(Pipeline/Branch event collection failed or partially unavailable)"

    if [ ! -d "/proc/$PID" ]; then
        echo "Warning: PID $PID has exited, skipping remaining collections" >&2
        return 1
    fi

    echo ""
    echo "========== Cross-SCCL NUMA Analysis (ARM only) =========="

    echo "--- SCCL DRAM Access (15s, tolerate if unavailable) ---"
    perf stat -e remote_access,ll_cache,ll_cache_miss -p "$PID" -- sleep "$DURATION" || echo "(remote_access/ll_cache/ll_cache_miss not available on this platform)"
    echo "Cross-SCCL ratio ≈ remote_access / (remote_access + ll_cache) * 100%"


    echo ""
    echo "============================================================"
    echo "Phase 4: Microarchitecture Bottleneck Analysis Complete (PID=$PID)"
    echo "============================================================"
}

parse_param "$@"
trap 'jobs -p | xargs -r kill 2>/dev/null' EXIT INT TERM
collect_microarch
