#!/bin/bash
# =============================================================================
# phase3.1-hotspot-function.sh — Phase 3.1: Hotspot Function Analysis
# =============================================================================
#
# Usage:
#   bash phase3.1-hotspot-function.sh --pid <PID> [--duration <SECONDS>]
#
# Parameters:
#   --pid      — Target process ID (required)
#   --duration — Collection duration in seconds (optional, default: 15)
#
# Requires: perf, root privilege. Total runtime: ~30-45 seconds (single 99Hz 15s record).
# ⚠️ HEAVYWEIGHT: Do NOT run concurrently with strace or other perf commands
#   on the same PID.
#
# Examples:
#   # Collect for PID 12345 with default duration:
#   bash phase3.1-hotspot-function.sh --pid 12345
#
#   # Collect for PID 12345 for 30 seconds:
#   bash phase3.1-hotspot-function.sh --pid 12345 --duration 30
#
# Save output to file:
#   bash phase3.1-hotspot-function.sh --pid 12345 --duration 30 > phase3.1_result.txt 2>&1
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

collect_hotspot_function() {
    echo "============================================================"
    echo "Phase 3.1: Hotspot Function Analysis (PID=$PID)"
    echo "============================================================"
    echo ""

    if [ ! -d "/proc/$PID" ]; then
        echo "Error: PID $PID has exited before data collection" >&2
        return 1
    fi

    echo "--- perf record (99Hz, ${DURATION}s sampling) ---"
    perf record -F 99 -p "$PID" -g -o /tmp/perf_phase3_1.data -- sleep "$DURATION" || {
        echo "Warning: perf record failed (PID may have exited)" >&2
    rm -f /tmp/perf_phase3_1.data /tmp/flamegraph_phase3_1.svg 2>/dev/null
        return 1
    }

    echo ""
    echo "--- perf report ---"
    if [ -f /tmp/perf_phase3_1.data ] && [ -s /tmp/perf_phase3_1.data ]; then
        PAGER=cat perf report -i /tmp/perf_phase3_1.data --stdio --percent-limit 1
    else
        echo "(perf data file missing or empty, skipping report)"
    fi

    echo ""
    echo "--- Generating flamegraph ---"
    if command -v stackcollapse-perf.pl >/dev/null 2>&1 && command -v flamegraph.pl >/dev/null 2>&1; then
        PAGER=cat perf script -i /tmp/perf_phase3_1.data | stackcollapse-perf.pl 2>/dev/null | flamegraph.pl > /tmp/flamegraph_phase3_1.svg 2>/dev/null \
            && echo "Flamegraph saved to /tmp/flamegraph_phase3_1.svg" \
            || echo "Flamegraph generation failed"
    else
        echo "Flamegraph generation skipped (stackcollapse-perf.pl / flamegraph.pl not installed)"
        echo "To install:"
        echo "  curl -k -o /usr/local/bin/stackcollapse-perf.pl https://raw.githubusercontent.com/brendangregg/FlameGraph/master/stackcollapse-perf.pl"
        echo "  curl -k -o /usr/local/bin/flamegraph.pl https://raw.githubusercontent.com/brendangregg/FlameGraph/master/flamegraph.pl"
        echo "  chmod +x /usr/local/bin/stackcollapse-perf.pl /usr/local/bin/flamegraph.pl"
    fi

    rm -f /tmp/perf_phase3_1.data 2>/dev/null
    echo ""
    echo "============================================================"
    echo "Phase 3.1: Hotspot Function Analysis Complete (PID=$PID)"
    echo "============================================================"
}

parse_param "$@"
trap 'rm -f /tmp/perf_phase3_1.data /tmp/flamegraph_phase3_1.svg 2>/dev/null' EXIT INT TERM
collect_hotspot_function
