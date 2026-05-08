#!/bin/bash
# =============================================================================
# phase3.2-syscall-analysis.sh — Phase 3.2: Syscall Analysis
# =============================================================================
# Usage: bash phase3.2-syscall-analysis.sh <PID>
# Parameters:
#   PID  — Target process ID (required)
# Requires: strace, root privilege. Total runtime: depends on target process activity.
# ⚠️ HEAVYWEIGHT: Must run AFTER phase3.1 completes. Do NOT run concurrently
#   with perf record/perf stat on the same PID.
# ⚠️ strace -c and strace -T share the same ptrace attachment — they are
#   serialized within this script.
# =============================================================================

set -euo pipefail

if [ -z "${1:-}" ]; then
    echo "Usage: bash phase3.2-syscall-analysis.sh <PID>" >&2
    exit 1
fi

PID="$1"

echo "============================================================"
echo "Phase 3.2: Syscall Analysis (PID=$PID)"
echo "============================================================"
echo ""

echo "--- strace -c: Syscall summary with counts and errors ---"
timeout 15 strace -p "$PID" -c -f

echo ""
echo "============================================================"
echo "Phase 3.2: Syscall Analysis Complete (PID=$PID)"
echo "============================================================"

