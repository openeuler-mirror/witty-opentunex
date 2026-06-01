#!/bin/bash
# =============================================================================
# phase2.2-top-processes.sh — Phase 2.2: Top Resource Process Identification
# =============================================================================
# Usage: bash phase2.2-top-processes.sh
# No parameters required. iotop requires root.
# =============================================================================


collect_top_processes() {
    echo "============================================================"
    echo "Phase 2.2: Top Resource Process Identification"
    echo "============================================================"
    echo ""

    echo "--- Top 20 CPU Processes ---"
    ps aux --sort=-%cpu | head -20

    echo ""
    echo "--- Top 20 Memory Processes ---"
    ps aux --sort=-%mem | head -20

    echo ""
    echo "--- Top 20 I/O Processes by iotop (requires root) ---"
    { echo "    PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN      IO    COMMAND"; iotop -oP -b -n 5 -d 1 | grep -E "^\s*[0-9]" | head -20; } || true

    echo ""
    echo "--- Top 20 I/O Processes by pidstat (by kB_wr/s) ---"
    { echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"; pidstat -d 1 5 | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20; }

    echo ""
    echo "============================================================"
    echo "Phase 2.2: Top Resource Process Identification Complete"
    echo "============================================================"
}

parse_param "$@"
collect_top_processes
