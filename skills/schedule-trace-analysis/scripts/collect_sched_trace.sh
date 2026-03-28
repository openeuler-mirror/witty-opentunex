#!/bin/bash
# Process Scheduling Trace Collection Script
# This script collects scheduling trace data for target process analysis

set -e

# Configuration
DURATION=${DURATION:-30}  # Default 30 seconds
TARGET_PID=${1:-""}
OUTPUT_DIR=${OUTPUT_DIR:-"/tmp/sched_trace_$(date +%Y%m%d_%H%M%S)"}
PERF_EVENTS="sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new,sched:sched_migrate_task"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_warn "Not running as root. Some commands may fail."
        return 1
    fi
    return 0
}

# Check perf availability
check_perf() {
    if ! command -v perf &> /dev/null; then
        log_error "perf not found. Please install perf: apt-get install linux-tools-$(uname -r)"
        exit 1
    fi
    log_info "perf version: $(perf --version | head -1)"
}

# Check scheduler stats enabled
check_sched_stats() {
    local sched_stats=$(cat /proc/sys/kernel/sched_schedstats 2>/dev/null || echo "0")
    if [ "$sched_stats" = "0" ]; then
        log_warn "sched_schedstats is disabled. Enabling..."
        if check_root; then
            echo 1 > /proc/sys/kernel/sched_schedstats
            log_info "sched_schedstats enabled"
        else
            log_error "Cannot enable sched_schedstats without root privileges"
            log_error "Please run: echo 1 > /proc/sys/kernel/sched_schedstats"
            exit 1
        fi
    else
        log_info "sched_schedstats is enabled"
    fi
}

# Get process information
get_process_info() {
    local pid=$1

    if [ -z "$pid" ]; then
        log_error "No PID provided"
        exit 1
    fi

    if ! ps -p "$pid" > /dev/null 2>&1; then
        log_error "Process $pid does not exist"
        exit 1
    fi

    log_info "Collecting process information for PID: $pid"

    cat > "${OUTPUT_DIR}/process_info.txt" << EOF
Process Information
==================
PID: $pid
Name: $(ps -p "$pid" -o comm=)
PPID: $(ps -p "$pid" -o ppid=)
Priority: $(ps -p "$pid" -o pri=)
Nice: $(ps -p "$pid" -o ni=)
Policy: $(ps -p "$pid" -o policy=)
RTPRI: $(ps -p "$pid" -o rtprio=)
CPU Affinity: $(taskset -pc "$pid" 2>/dev/null | awk '{print $NF}')
User: $(ps -p "$pid" -o user=)
Started: $(ps -p "$pid" -o lstart=)
Threads: $(ps -p "$pid" -o nlwp=)
EOF

    # Get thread information
    ps -T -p "$pid" > "${OUTPUT_DIR}/threads.txt" 2>/dev/null || true

    # Get scheduler stats
    if [ -f "/proc/$pid/schedstat" ]; then
        cp "/proc/$pid/schedstat" "${OUTPUT_DIR}/schedstat.txt"
    fi

    log_info "Process information saved to ${OUTPUT_DIR}/process_info.txt"
}

# Collect system information
collect_system_info() {
    log_info "Collecting system information"

    # CPU information
    lscpu > "${OUTPUT_DIR}/lscpu.txt" 2>/dev/null || true
    cat /proc/cpuinfo > "${OUTPUT_DIR}/cpuinfo.txt" 2>/dev/null || true

    # Kernel information
    uname -a > "${OUTPUT_DIR}/uname.txt"
    cat /proc/version >> "${OUTPUT_DIR}/uname.txt" 2>/dev/null || true

    # Scheduler configuration
    cat /proc/sys/kernel/sched_*.txt > "${OUTPUT_DIR}/scheduler_config.txt" 2>/dev/null || true

    # NUMA information
    numactl --hardware > "${OUTPUT_DIR}/numa_info.txt" 2>/dev/null || true
    numastat > "${OUTPUT_DIR}/numastat.txt" 2>/dev/null || true

    log_info "System information saved"
}

# Record scheduling trace
record_sched_trace() {
    local pid=$1

    log_info "Starting scheduling trace collection for ${DURATION} seconds"

    if [ -n "$pid" ]; then
        log_info "Target PID: $pid"
        perf sched record -p "$pid" -e $PERF_EVENTS -- sleep "$DURATION" > /dev/null 2>&1
    else
        log_info "Recording system-wide scheduling events"
        perf sched record -a -e $PERF_EVENTS -- sleep "$DURATION" > /dev/null 2>&1
    fi

    if [ ! -f "perf.data" ]; then
        log_error "perf.data not created. Collection failed."
        exit 1
    fi

    local size=$(du -h perf.data | cut -f1)
    log_info "perf.data created: $size"

    # Copy perf.data to output directory
    mv perf.data "${OUTPUT_DIR}/perf.data"

    log_info "Scheduling trace saved to ${OUTPUT_DIR}/perf.data"
}

# Generate preliminary statistics
generate_prelim_stats() {
    log_info "Generating preliminary statistics"

    # Get latency statistics
    perf sched latency -i "${OUTPUT_DIR}/perf.data" > "${OUTPUT_DIR}/sched_latency.txt" 2>&1 || true

    # Get time history
    perf sched timehist -i "${OUTPUT_DIR}/perf.data" > "${OUTPUT_DIR}/sched_timehist.txt" 2>&1 || true

    # Get scheduling map
    perf sched map -i "${OUTPUT_DIR}/perf.data" > "${OUTPUT_DIR}/sched_map.txt" 2>&1 || true

    # Get scheduling script
    perf sched script -i "${OUTPUT_DIR}/perf.data" > "${OUTPUT_DIR}/sched_script.txt" 2>&1 || true

    # Get event count
    local total_events=$(wc -l < "${OUTPUT_DIR}/sched_script.txt")
    log_info "Total events collected: $total_events"

    # Create summary
    cat > "${OUTPUT_DIR}/summary.txt" << EOF
Scheduling Trace Collection Summary
===================================
Collection Time: $(date)
Duration: ${DURATION} seconds
Target PID: ${TARGET_PID:-"System-wide"}
Output Directory: ${OUTPUT_DIR}
Total Events: $total_events
File Size: $(du -h "${OUTPUT_DIR}/perf.data" | cut -f1)

Files Generated:
- process_info.txt: Target process information
- threads.txt: Thread information (if applicable)
- schedstat.txt: Scheduler statistics (if available)
- lscpu.txt: CPU topology
- numa_info.txt: NUMA configuration
- perf.data: Raw scheduling trace
- sched_latency.txt: Scheduling latency analysis
- sched_timehist.txt: Time history of scheduling events
- sched_map.txt: Scheduling map visualization
- sched_script.txt: Detailed scheduling script
EOF

    log_info "Preliminary statistics saved"
}

# Create output directory
create_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [PID] [options]

Arguments:
    PID        Target process PID (optional, system-wide if not specified)

Options:
    -d, --duration SECONDS   Collection duration (default: 60)
    -o, --output DIR         Output directory (default: /tmp/sched_trace_<timestamp>)
    -h, --help               Show this help message

Examples:
    $0 1234                      # Collect for PID 1234
    $0 1234 -d 120               # Collect for 120 seconds
    $0 -d 30 -o /tmp/mytrace     # System-wide collection for 30 seconds

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                TARGET_PID="$1"
                shift
                ;;
        esac
    done

    # Validate duration
    if ! [[ "$DURATION" =~ ^[0-9]+$ ]]; then
        log_error "Invalid duration: $DURATION"
        exit 1
    fi

    if [ "$DURATION" -lt 10 ]; then
        log_warn "Duration too short (<10s), recommended minimum is 30s"
    fi

    if [ "$DURATION" -gt 300 ]; then
        log_warn "Duration long (>300s), may generate large files"
    fi
}

# Main function
main() {
    echo "======================================="
    echo "Process Scheduling Trace Collection"
    echo "======================================="
    echo ""

    parse_args "$@"
    create_output_dir
    check_root
    check_perf
    check_sched_stats
    collect_system_info

    if [ -n "$TARGET_PID" ]; then
        get_process_info "$TARGET_PID"
    fi

    record_sched_trace "$TARGET_PID"
    generate_prelim_stats

    echo ""
    log_info "Collection completed successfully!"
    echo ""
    echo "Output files are in: $OUTPUT_DIR"
    echo ""
    echo "To analyze the collected data:"
    echo "  ./analyze_sched_trace.sh -i $OUTPUT_DIR -p ${TARGET_PID:-all}"
    echo ""
}

# Run main function
main "$@"
