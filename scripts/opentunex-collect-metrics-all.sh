#!/bin/bash
# opentunex-collect-metrics-all.sh - Collect all metrics for bottleneck analysis
# Usage: collect-metrics-all.sh --pid <PID> [--duration <SECONDS>]

usage() {
    echo "Usage: $0 --pid <PID> [--duration <SECONDS>]"
    echo "  --pid       Target process ID (required)"
    echo "  --duration  Collection duration in seconds (default: 60)"
    exit 1
}

PID=""
DURATION=60

while [[ $# -gt 0 ]]; do
    case $1 in
        --pid)
            PID="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$PID" ]; then
    echo "Error: --pid is required"
    usage
fi

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Error: PID $PID does not exist or not accessible"
    exit 1
fi

echo "=== All Metrics Collection ==="
echo "PID: $PID"
echo "Duration: $DURATION seconds"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/opentunex-log-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

echo "Log directory: $LOG_DIR"
echo ""

log_phase() {
    local name="$1"
    local log_file="$LOG_DIR/${name}.txt"
    shift
    echo "=== $name === (logging to $log_file)"
    "$@" > "$log_file" 2>&1
    echo "$name completed, log: $log_file"
    echo ""
}

log_phase "phase1-static-info" bash "$SCRIPT_DIR/opentunex-phase1-static-info.sh"

log_phase "phase2.1-global-bottleneck" bash "$SCRIPT_DIR/opentunex-phase2.1-global-bottleneck.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase2.2-top-processes" bash "$SCRIPT_DIR/opentunex-phase2.2-top-processes.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase3.1-hotspot-function" bash "$SCRIPT_DIR/opentunex-phase3.1-hotspot-function.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase3.2-syscall-analysis" bash "$SCRIPT_DIR/opentunex-phase3.2-syscall-analysis.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase4-microarch" bash "$SCRIPT_DIR/opentunex-phase4-microarch.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase5.1-sched-bottleneck" bash "$SCRIPT_DIR/opentunex-phase5.1-sched-bottleneck.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase5.2-lock-bottleneck" bash "$SCRIPT_DIR/opentunex-phase5.2-lock-bottleneck.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase5.3-io-bottleneck" bash "$SCRIPT_DIR/opentunex-phase5.3-io-bottleneck.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase5.4-mem-bottleneck" bash "$SCRIPT_DIR/opentunex-phase5.4-mem-bottleneck.sh" --pid "$PID" --duration "$DURATION"

log_phase "phase5.5-net-bottleneck" bash "$SCRIPT_DIR/opentunex-phase5.5-net-bottleneck.sh" --duration "$DURATION"

echo "=== All Metrics Collection Complete ==="
echo "Logs saved in: $LOG_DIR"