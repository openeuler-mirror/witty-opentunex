#!/bin/bash
# =============================================================================
# phase4-microarch.sh — Phase 4: Microarchitecture Bottleneck Analysis
# =============================================================================
# Usage: bash phase4-microarch.sh <PID>
# Parameters:
#   PID  — Target process ID (required)
# Requires: perf, root privilege. Total runtime: ~3-4 minutes.
# ⚠️ HEAVYWEIGHT: All perf stat groups are serialized — PMU counter
#   multiplexing produces unreliable results if run in parallel.
# ⚠️ Must run AFTER phase3 completes (perf record/strace also use PMU).
# =============================================================================

set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: bash phase4-microarch.sh <PID>" >&2
    exit 1
fi

PID="$1"
DUR=15

echo "============================================================"
echo "Phase 4: Microarchitecture Bottleneck Analysis (PID=$PID)"
echo "============================================================"
echo ""

# ---- CPU Cache Analysis ----
echo "========== CPU Cache Analysis =========="

echo "--- Cache Miss Rates (15s) ---"
perf stat -e L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses -p "$PID" -- sleep "$DUR"

echo ""
echo "--- TLB Miss Statistics (15s, tolerate if unavailable) ---"
perf stat -e dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses -p "$PID" -- sleep "$DUR" || true

# ---- Branch Prediction and Pipeline Analysis ----
echo ""
echo "========== Branch Prediction and Pipeline Analysis =========="

echo "--- Branch Misprediction Rate (15s, tolerate if unavailable) ---"
perf stat -e branches,branch-misses -p "$PID" -- sleep "$DUR" || true

echo ""
echo "--- Pipeline Stall Analysis (15s) ---"
perf stat -e stalled-cycles-frontend,stalled-cycles-backend,cycles,instructions -p "$PID" -- sleep "$DUR"

# ---- NUMA SCCL Analysis (ARM only) ----
echo ""
echo "========== Cross-SCCL NUMA Analysis (ARM only) =========="

echo "--- SCCL DRAM Access (15s, tolerate if unavailable) ---"
perf stat -e remote_access,ll_cache_miss -p "$PID" -- sleep "$DUR" || echo "(remote_access/ll_cache_miss not available on this platform)"
echo "Cross-SCCL ratio = remote_access / (remote_access + ll_cache_miss) * 100%"

# ---- Top-Down Microarchitecture Analysis ----
echo ""
echo "========== Top-Down Microarchitecture Analysis =========="

echo "--- Portable Pipeline Metrics (15s) ---"
perf stat -e cycles,instructions -p "$PID" -- sleep "$DUR"


echo "============================================================"
echo "Phase 4: Microarchitecture Bottleneck Analysis Complete (PID=$PID)"
echo "============================================================"

