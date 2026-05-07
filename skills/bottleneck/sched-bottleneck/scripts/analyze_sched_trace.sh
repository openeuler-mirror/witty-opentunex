#!/bin/bash
# Process Scheduling Trace Analysis Script
# This script analyzes scheduling trace data collected by collect_sched_trace.sh

set -e

# Configuration
INPUT_DIR=${1:-""}
TARGET_PID=${2:-""}
OUTPUT_DIR=${OUTPUT_DIR:-""}

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 <input_dir> [PID] [options]

Arguments:
    input_dir        Directory containing collected trace data
    PID              Target process PID (optional, 'all' for system-wide)

Options:
    -o, --output DIR         Output directory for analysis results
    -d, --duration SECONDS   Collection duration (for frequency calc)
    -h, --help               Show this help message

Examples:
    $0 /tmp/sched_trace_20231201_120000 1234
    $0 /tmp/sched_trace_20231201_120000
    $0 /tmp/sched_trace_20231201_120000 all -o /tmp/analysis

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
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
                shift
                ;;
        esac
    done

    # Set output directory
    if [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="${INPUT_DIR}/analysis"
    fi
    mkdir -p "$OUTPUT_DIR"
}

# Validate input directory
validate_input() {
    if [ -z "$INPUT_DIR" ]; then
        log_error "Input directory not specified"
        print_usage
        exit 1
    fi

    if [ ! -d "$INPUT_DIR" ]; then
        log_error "Input directory does not exist: $INPUT_DIR"
        exit 1
    fi

    if [ ! -f "${INPUT_DIR}/perf.data" ]; then
        log_error "perf.data not found in input directory"
        exit 1
    fi

    log_info "Input directory: $INPUT_DIR"
    log_info "Output directory: $OUTPUT_DIR"
}

# Get collection duration from data
get_duration() {
    if [ -z "$DURATION" ]; then
        # Try to get duration from summary
        if [ -f "${INPUT_DIR}/summary.txt" ]; then
            DURATION=$(grep "Duration:" "${INPUT_DIR}/summary.txt" | awk '{print $2}')
        fi

        # If still not set, default to 60
        if [ -z "$DURATION" ]; then
            DURATION=60
            log_warn "Duration not specified, using default: ${DURATION}s"
        fi
    fi

    log_info "Collection duration: ${DURATION} seconds"
}

# Analyze scheduling out frequency
analyze_sched_out_frequency() {
    log_section "Analyzing Scheduling Out Frequency"

    local perf_data="${INPUT_DIR}/perf.data"
    local target="$TARGET_PID"

    if [ -z "$target" ] || [ "$target" = "all" ]; then
        log_info "Analyzing all processes..."
        perf sched latency -i "$perf_data" --sort max | head -50 > "${OUTPUT_DIR}/sched_out_all.txt"
        cat "${OUTPUT_DIR}/sched_out_all.txt"

        log_info "Top 20 processes by sched_out count:"
        perf sched script -i "$perf_data" | grep "sched_switch" | \
            awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
            sort | uniq -c | sort -rn | head -20 > "${OUTPUT_DIR}/sched_out_count.txt"
        cat "${OUTPUT_DIR}/sched_out_count.txt"
    else
        log_info "Analyzing target PID: $target"

        # Count sched_out events for target
        local sched_out_count=$(perf sched script -i "$perf_data" | \
            grep "sched_switch.*prev_pid=$target" | wc -l)

        local frequency=$(echo "scale=2; $sched_out_count / $DURATION" | bc)

        cat > "${OUTPUT_DIR}/sched_out_target.txt" << EOF
Target Process Scheduling Out Analysis
=======================================
Target PID: $target
Sched Out Events: $sched_out_count
Collection Duration: $DURATION seconds
Frequency: $frequency events/second
EOF

        cat "${OUTPUT_DIR}/sched_out_target.txt"

        # Get average sched_out frequency for system
        local total_events=$(perf sched script -i "$perf_data" | wc -l)
        local system_avg=$(echo "scale=2; $total_events / $DURATION" | bc)

        log_info "System average: $system_avg events/second"
        log_info "Target frequency: $frequency events/second"

        local ratio=$(echo "scale=2; $frequency / $system_avg" | bc 2>/dev/null || echo "0")
        log_info "Ratio: ${ratio}x system average"

        # Compare with other processes
        log_info "Comparison with top 10 processes:"
        perf sched script -i "$perf_data" | grep "sched_switch" | \
            awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
            sort | uniq -c | sort -rn | head -10 > "${OUTPUT_DIR}/sched_out_comparison.txt"
        cat "${OUTPUT_DIR}/sched_out_comparison.txt"
    fi
}

# Analyze scheduling in latency
analyze_sched_in_latency() {
    log_section "Analyzing Scheduling In Latency"

    local perf_data="${INPUT_DIR}/perf.data"
    local target="$TARGET_PID"

    if [ -n "$target" ] && [ "$target" != "all" ]; then
        log_info "Analyzing latency for target PID: $target"

        # Get latency statistics
        perf sched latency -i "$perf_data" -p "$target" > "${OUTPUT_DIR}/latency_target.txt" 2>&1 || true

        # Extract latency values
        perf sched timehist -i "$perf_data" | grep " $target " > "${OUTPUT_DIR}/timehist_target.txt" 2>&1 || true

        if [ -f "${OUTPUT_DIR}/timehist_target.txt" ] && [ -s "${OUTPUT_DIR}/timehist_target.txt" ]; then
            log_info "Latency Statistics:"

            # Calculate average latency
            local avg_latency=$(awk '{sum+=$8; count++} END {if(count>0) print sum/count; else print 0}' "${OUTPUT_DIR}/timehist_target.txt")
            log_info "  Average: ${avg_latency} ms"

            # Calculate percentiles
            awk '{print $8}' "${OUTPUT_DIR}/timehist_target.txt" | sort -n | awk '
            BEGIN { count=0 }
            { vals[count++]=$1 }
            END {
                if (count > 0) {
                    print "  P50:", vals[int(count*0.5)] " ms"
                    print "  P90:", vals[int(count*0.9)] " ms"
                    print "  P95:", vals[int(count*0.95)] " ms"
                    print "  P99:", vals[int(count*0.99)] " ms"
                    print "  Max:", vals[count-1] " ms"
                }
            }'

            # Count outliers
            local outliers=$(awk '$8 > 100000 {count++} END {print count+0}' "${OUTPUT_DIR}/timehist_target.txt")
            log_info "  Outliers (>100ms): $outliers"

            # Latency histogram
            awk '{latency=$8; bucket=int(latency/1000); freq[bucket]++} END {
                print "Latency Distribution:"
                for (b in freq) {
                    if (b < 50) printf("  %d-%d ms: %d\n", b*1000, (b+1)*1000, freq[b])
                }
            }' "${OUTPUT_DIR}/timehist_target.txt"
        else
            log_warn "No latency data found for PID $target"
        fi
    else
        log_info "Analyzing latency for all processes..."

        perf sched latency -i "$perf_data" --sort max | head -30 > "${OUTPUT_DIR}/latency_all.txt"
        cat "${OUTPUT_DIR}/latency_all.txt"

        log_info "Top 10 processes by max latency:"
        perf sched latency -i "$perf_data" --sort max | head -10
    fi
}

# Analyze preempting tasks (global perspective)
analyze_preemptors() {
    log_section "Analyzing Preempting Tasks (Global Perspective)"

    local perf_data="${INPUT_DIR}/perf.data"
    local target="$TARGET_PID"

    log_info "Global CPU time distribution:"
    perf sched latency -i "$perf_data" | awk '/^[0-9]/ {print $1, $2, $6, $7, $8}' | \
        sort -k5 -rn | head -20 > "${OUTPUT_DIR}/cpu_time_distribution.txt"
    cat "${OUTPUT_DIR}/cpu_time_distribution.txt"

    if [ -n "$target" ] && [ "$target" != "all" ]; then
        log_info ""
        log_info "Analyzing preemptors for target PID: $target"

        # Find tasks that run immediately before target becomes runnable
        log_info "Top preemptors by frequency:"
        perf sched script -i "$perf_data" | grep -B 1 "sched_switch.*next_pid=$target" | \
            grep "prev_pid=" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
            sort | uniq -c | sort -rn | head -20 > "${OUTPUT_DIR}/preemptors_frequency.txt"
        cat "${OUTPUT_DIR}/preemptors_frequency.txt"

        # Get detailed preemptor information
        log_info ""
        log_info "Preemptor details (top 10):"
        head -10 "${OUTPUT_DIR}/preemptors_frequency.txt" | awk '{print $2}' | while read pid; do
            if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
                local comm=$(ps -p "$pid" -o comm=)
                local pcpu=$(ps -p "$pid" -o pcpu=)
                local pmem=$(ps -p "$pid" -o pmem=)
                local pri=$(ps -p "$pid" -o pri=)

                # Get global CPU share
                local cpu_share=$(grep "^ *$pid " "${OUTPUT_DIR}/cpu_time_distribution.txt" | awk '{print $5}' || echo "0")

                echo "PID $pid ($comm): CPU%=$pcpu, Mem%=$pmem, Pri=$pri, Global Share=$cpu_share"
            fi
        done

        # Categorize preemptors
        log_info ""
        log_info "Preemptor categories:"
        cat > "${OUTPUT_DIR}/preemptor_analysis.txt" << EOF
Kernel Tasks
------------
$(perf sched script -i "$perf_data" | grep -B 1 "sched_switch.*next_pid=$target" | \
    grep "prev_pid=" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
    while read pid; do
        if [ -n "$pid" ]; then
            local comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "N/A")
            if [[ "$comm" == \[*\] ]]; then
                echo "$pid ($comm)"
            fi
        fi
    done | sort | uniq -c | sort -rn)

System Services
---------------
$(perf sched script -i "$perf_data" | grep -B 1 "sched_switch.*next_pid=$target" | \
    grep "prev_pid=" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
    while read pid; do
        if [ -n "$pid" ]; then
            local comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "N/A")
            if [[ "$comm" == "systemd" || "$comm" == "sshd" || "$comm" == "cron" || "$comm" == "rsyslog" ]]; then
                echo "$pid ($comm)"
            fi
        fi
    done | sort | uniq -c | sort -rn)

Other Applications
------------------
$(perf sched script -i "$perf_data" | grep -B 1 "sched_switch.*next_pid=$target" | \
    grep "prev_pid=" | awk -F'prev_pid=' '{print $2}' | awk '{print $1}' | \
    while read pid; do
        if [ -n "$pid" ]; then
            local comm=$(ps -p "$pid" -o comm= 2>/dev/null || echo "N/A")
            if [[ "$comm" != \[*\] ]] && [[ "$comm" != "systemd" && "$comm" != "sshd" && "$comm" != "cron" && "$comm" != "rsyslog" ]]; then
                echo "$pid ($comm)"
            fi
        fi
    done | sort | uniq -c | sort -rn | head -10)
EOF
        cat "${OUTPUT_DIR}/preemptor_analysis.txt"
    fi
}

# Generate comprehensive report
generate_report() {
    log_section "Generating Comprehensive Report"

    local report_file="${OUTPUT_DIR}/analysis_report.md"

    cat > "$report_file" << 'HEADER'
# Process Scheduling Trace Analysis Report

## Analysis Summary
HEADER

    # Add timestamp
    echo "- **Analysis Time**: $(date)" >> "$report_file"
    echo "- **Input Directory**: $INPUT_DIR" >> "$report_file"
    echo "- **Target PID**: ${TARGET_PID:-"System-wide"}" >> "$report_file"
    echo "- **Collection Duration**: ${DURATION} seconds" >> "$report_file"

    # Add key findings
    cat >> "$report_file" << 'SECTION'

## Key Findings

### 1. Scheduling Out Frequency
SECTION

    if [ -f "${OUTPUT_DIR}/sched_out_target.txt" ]; then
        cat "${OUTPUT_DIR}/sched_out_target.txt" >> "$report_file"
    else
        echo "Analysis not performed for specific target" >> "$report_file"
    fi

    cat >> "$report_file" << 'SECTION'

### 2. Scheduling In Latency
SECTION

    if [ -f "${OUTPUT_DIR}/timehist_target.txt" ] && [ -s "${OUTPUT_DIR}/timehist_target.txt" ]; then
        echo '```' >> "$report_file"
        awk '{sum+=$8; count++} END {if(count>0) print "Average Latency:", sum/count, "ms"}' "${OUTPUT_DIR}/timehist_target.txt" >> "$report_file"
        awk '{print $8}' "${OUTPUT_DIR}/timehist_target.txt" | sort -n | awk '
        BEGIN { count=0 }
        { vals[count++]=$1 }
        END {
            if (count > 0) {
                print "P50:", vals[int(count*0.5)], "ms"
                print "P90:", vals[int(count*0.9)], "ms"
                print "P95:", vals[int(count*0.95)], "ms"
                print "P99:", vals[int(count*0.99)], "ms"
                print "Max:", vals[count-1], "ms"
            }
        }' >> "$report_file"
        echo '```' >> "$report_file"
    else
        echo "Analysis not performed for specific target" >> "$report_file"
    fi

    cat >> "$report_file" << 'SECTION'

### 3. Global CPU Time Distribution
SECTION

    if [ -f "${OUTPUT_DIR}/cpu_time_distribution.txt" ]; then
        echo '```' >> "$report_file"
        head -20 "${OUTPUT_DIR}/cpu_time_distribution.txt" >> "$report_file"
        echo '```' >> "$report_file"
    fi

    cat >> "$report_file" << 'SECTION'

### 4. Preempting Tasks Analysis
SECTION

    if [ -f "${OUTPUT_DIR}/preemptors_frequency.txt" ]; then
        echo '```' >> "$report_file"
        cat "${OUTPUT_DIR}/preemptors_frequency.txt" >> "$report_file"
        echo '```' >> "$report_file"
    fi

    cat >> "$report_file" << 'SECTION'

## Detailed Analysis

### Scheduling Out Frequency
SECTION

    if [ -f "${OUTPUT_DIR}/sched_out_comparison.txt" ]; then
        echo '```' >> "$report_file"
        cat "${OUTPUT_DIR}/sched_out_comparison.txt" >> "$report_file"
        echo '```' >> "$report_file"
    fi

    cat >> "$report_file" << 'SECTION'

### Preemptor Categories
SECTION

    if [ -f "${OUTPUT_DIR}/preemptor_analysis.txt" ]; then
        echo '```' >> "$report_file"
        cat "${OUTPUT_DIR}/preemptor_analysis.txt" >> "$report_file"
        echo '```' >> "$report_file"
    fi

    cat >> "$report_file" << 'FOOTER'

## Files Generated
- sched_out_target.txt: Target process scheduling out statistics
- timehist_target.txt: Target process latency time history
- latency_target.txt: Target process latency analysis
- cpu_time_distribution.txt: Global CPU time distribution
- preemptors_frequency.txt: Preemptor frequency analysis
- preemptor_analysis.txt: Preemptor categorization

## Next Steps
1. Review key findings and identify abnormal patterns
2. Investigate top preemptors for potential optimization
3. Consider priority adjustments if warranted
4. Evaluate CPU affinity and NUMA placement
5. Validate findings with targeted testing
FOOTER

    log_info "Report generated: $report_file"
}

# Main function
main() {
    echo "======================================="
    echo "Process Scheduling Trace Analysis"
    echo "======================================="
    echo ""

    parse_args "$@"
    validate_input
    get_duration

    analyze_sched_out_frequency
    analyze_sched_in_latency
    analyze_preemptors
    generate_report

    echo ""
    log_info "Analysis completed successfully!"
    echo ""
    echo "Results saved in: $OUTPUT_DIR"
    echo "Report: ${OUTPUT_DIR}/analysis_report.md"
    echo ""
}

# Run main function
main "$@"
