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

echo "--- Cache Miss Rates (30s) ---"
perf stat -e cache-references,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses -p "$PID" -- sleep "$DUR"

echo ""
echo "--- TLB Miss Statistics (30s, tolerate if unavailable) ---"
perf stat -e dTLB-load-misses,iTLB-load-misses -p "$PID" -- sleep "$DUR" || true

# ---- Branch Prediction and Pipeline Analysis ----
echo ""
echo "========== Branch Prediction and Pipeline Analysis =========="

echo "--- Branch Misprediction Rate (30s, tolerate if unavailable) ---"
perf stat -e branches,branch-misses -p "$PID" -- sleep "$DUR" || true

echo ""
echo "--- Pipeline Stall Analysis (30s) ---"
perf stat -e stalled-cycles-frontend,stalled-cycles-backend,cycles,instructions -p "$PID" -- sleep "$DUR"

# ---- Top-Down Microarchitecture Analysis ----
echo ""
echo "========== Top-Down Microarchitecture Analysis =========="

echo "--- Portable Pipeline Metrics (30s) ---"
perf stat -e cycles,instructions -p "$PID" -- sleep "$DUR"

echo ""
echo "--- Intel uops Metrics (30s, tolerate if unavailable) ---"
perf stat -e uops_executed,uops_retired -p "$PID" -- sleep "$DUR" || true

echo ""
echo "--- Intel pmu-tools Top-Down (tolerate if not installed) ---"
toplev -p "$PID" --sleep "$DUR" || true

# ---- Memory Bandwidth and NUMA ----
echo ""
echo "========== Memory Bandwidth and NUMA =========="

echo "--- NUMA Locality (30s, tolerate if unavailable) ---"
perf stat -e node_loads,node_stores,local_loads,remote_loads -p "$PID" -- sleep "$DUR" || true

echo ""
echo "============================================================"
echo "Phase 4: Microarchitecture Bottleneck Analysis Complete (PID=$PID)"
echo "============================================================"

