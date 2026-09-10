#!/bin/bash
# =============================================================================
# bottleneck_data_collector.sh - 瓶颈分析专用数据采集脚本
# =============================================================================
# 功能: 简化的服务器数据采集，仅采集瓶颈分析（opentunex-scenario-bottleneck）
#       各 preanalysis.sh 所需的数据文件。
# 用法: ./bottleneck_data_collector.sh -d <持续时间> [-p <进程ID>] [-o <输出目录>]
#
# 本脚本从 server_data_collector.sh 提取并精简，去掉 devkit/微架构/锁跟踪/
# 调度器跟踪/ksys 等瓶颈分析不需要的采集项，仅保留 12 个核心数据文件。
#
# 生成的数据文件（对应 preanalysis.sh 所需）:
#   static_info.txt              - 系统静态信息（CPU/内存/网卡/内核参数等）
#   global_bottleneck.txt        - 全局资源瓶颈指标（CPU/内存/IO/网络）
#   top_processes.txt            - 顶级资源消耗进程
#   hotspot_analysis.txt         - 热点函数分析（perf record/report）
#   syscall_analysis.txt         - 系统调用分析（strace）
#   cpu_detail_info.txt          - CPU 深度信息（/proc/stat 多采样等）
#   kernel_config_info.txt       - 内核配置与诊断信息
#   pmu_info.txt                 - PMU 远程访问与 HHA 分析
#   process_detail_info.txt      - 进程/线程详细信息
#   container_info.txt           - 容器资源监控（CPU/内存/IO 配额）
#   memory_metrics_analysis.txt  - 内存指标深度分析（NUMA/缺页/Swap等）
#   network_metrics_analysis.txt - 网络指标深度分析（网卡配置/IRQ亲和/tcp等）
# =============================================================================

set -o pipefail

# ---- 架构检测 ----
ARCH_TARGET="aarch64"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH_TARGET="x86_64" ;;
    aarch64|arm64) ARCH_TARGET="aarch64" ;;
esac

# ---- 默认参数 ----
DURATION=10
INTERVAL=1
TIMEOUT_DURATION=60
PIDS=""
OUTPUT_DIR=""
CHECK_ONLY=false

# ---- 输出文件变量 ----
STATIC_FILE=""
BOTTLENECK_FILE=""
TOP_PROC_FILE=""
HOTSPOT_ANALYSIS_FILE=""
SYSCALL_FILE=""
IO_METRICS_FILE=""
MEM_METRICS_FILE=""
NET_METRICS_FILE=""
CPU_DETAIL_FILE=""
KERNEL_CONFIG_FILE=""
PMU_INFO_FILE=""
PROCESS_DETAIL_INFO_FILE=""
CONTAINER_FILE=""
ERROR_LOG=""

# ---- 可执行的采集命令（仅瓶颈分析所需） ----
AVAILABLE_COMMANDS=(
    "collect_static_info"
    "collect_global_bottleneck"
    "collect_top_processes"
    "collect_hotspot_analysis"
    "collect_syscall_analysis"
    "collect_io_metrics"
    "collect_mem_metrics"
    "collect_net_metrics"
    "collect_cpu_detail_info"
    "collect_kernel_config_info"
    "collect_process_detail_info"
    "collect_container_info"
)
[[ "${ARCH_TARGET}" = "aarch64" ]] && AVAILABLE_COMMANDS+=("collect_pmu_info")

SELECTED_COMMANDS=()

# ---- 并行分组策略 ----
# 分组原则:
#   Phase 1: 快速静态采集 — 仅读取系统文件，无采样时长，几乎零开销，组内并行
#   Phase 2: 系统级采样   — 低开销系统级工具（vmstat/iostat/sar/mpstat），组内并行
#   Phase 3: 进程/容器深度 — 遍历 /proc 和 cgroup，中等开销，组内并行
#   Phase 4: 独占工具     — perf(PMU硬件计数器互斥)、strace(ptrace高开销)，组内串行
#
# 组间串行确保上一阶段的开销不会干扰下一阶段的测量精度。
PHASE1_CMDS=("collect_static_info" "collect_top_processes" "collect_mem_metrics" "collect_kernel_config_info")
PHASE2_CMDS=("collect_io_metrics" "collect_net_metrics" "collect_cpu_detail_info" "collect_global_bottleneck")
PHASE3_CMDS=("collect_process_detail_info" "collect_container_info")
PHASE4_CMDS=("collect_pmu_info" "collect_hotspot_analysis" "collect_syscall_analysis")

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# 工具函数
# =============================================================================

set_output_file() {
    STATIC_FILE="${OUTPUT_DIR}/static_info.txt"
    BOTTLENECK_FILE="${OUTPUT_DIR}/global_bottleneck.txt"
    TOP_PROC_FILE="${OUTPUT_DIR}/top_processes.txt"
    HOTSPOT_ANALYSIS_FILE="${OUTPUT_DIR}/hotspot_analysis.txt"
    SYSCALL_FILE="${OUTPUT_DIR}/syscall_analysis.txt"
    IO_METRICS_FILE="${OUTPUT_DIR}/io_metrics_analysis.txt"
    MEM_METRICS_FILE="${OUTPUT_DIR}/memory_metrics_analysis.txt"
    NET_METRICS_FILE="${OUTPUT_DIR}/network_metrics_analysis.txt"
    CPU_DETAIL_FILE="${OUTPUT_DIR}/cpu_detail_info.txt"
    KERNEL_CONFIG_FILE="${OUTPUT_DIR}/kernel_config_info.txt"
    PMU_INFO_FILE="${OUTPUT_DIR}/pmu_info.txt"
    PROCESS_DETAIL_INFO_FILE="${OUTPUT_DIR}/process_detail_info.txt"
    CONTAINER_FILE="${OUTPUT_DIR}/container_info.txt"
    ERROR_LOG="$OUTPUT_DIR/err_log.txt"
}

show_usage() {
    cat << EOF
用法: $0 -d <持续时间> [-p <进程ID>] [-o <输出目录>] [-c <采集项目>] [-C] [-h]

瓶颈分析专用数据采集脚本。生成的采集数据文件可供 opentunex-scenario-bottleneck
各 preanalysis.sh 脚本直接解析使用。

参数说明:
    -d <持续时间>    采集数据的持续时间（秒）
    -p <进程ID>      要监控的进程ID（仅一个 PID，禁止逗号分隔多进程）
    -o <输出目录>    数据输出目录（可选，默认自动生成）
    -c <采集项目>    要采集的项目，多个用逗号分隔（可选，默认全部）
    -C              仅执行前置检查，不进行数据采集
    -h              显示此帮助信息

可用的采集项目:
    collect_static_info           - 系统静态信息
    collect_global_bottleneck     - 全局资源瓶颈
    collect_top_processes         - 顶级资源消耗进程
    collect_hotspot_analysis      - 热点函数分析（需指定 -p）
    collect_syscall_analysis      - 系统调用分析（需指定 -p）
    collect_io_metrics            - I/O 指标深度分析
    collect_mem_metrics           - 内存指标深度分析
    collect_net_metrics           - 网络指标深度分析
    collect_cpu_detail_info       - CPU 深度信息
    collect_kernel_config_info    - 内核配置与诊断信息
    collect_process_detail_info   - 进程/线程详细信息
    collect_container_info        - 容器资源监控
    collect_pmu_info              - PMU 远程访问分析（仅 aarch64）

示例:
    $0 -d 10                          # 采集 10 秒，默认所有项目
    $0 -d 60 -p 1234                  # 采集 60 秒，监控进程 1234
    $0 -d 30 -p 1234 -o /tmp/bottleneck_data  # 指定输出目录
    $0 -C                             # 仅前置检查
EOF
}

log_info()    { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}$1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }
log_error()   { echo -e "${RED}$1${NC}"; }

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 $1 未找到，请安装后重试。"
        return 1
    fi
    return 0
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "警告: 脚本未以 root 权限运行。"
        log_warning "某些采集功能可能受限（如 perf、strace、ethtool 等）。"
        log_warning "建议使用 sudo 运行以获得完整数据。"
        echo ""
    fi
}

create_header() {
    for var in STATIC_FILE BOTTLENECK_FILE TOP_PROC_FILE HOTSPOT_ANALYSIS_FILE \
               SYSCALL_FILE IO_METRICS_FILE MEM_METRICS_FILE NET_METRICS_FILE \
               CPU_DETAIL_FILE KERNEL_CONFIG_FILE PMU_INFO_FILE \
               PROCESS_DETAIL_INFO_FILE CONTAINER_FILE; do
        local f="${!var}"
        if [[ -n "$f" ]]; then
            echo "============================================================" > "$f"
            echo "瓶颈分析数据采集 - $(date)" >> "$f"
            echo "采集持续时间: ${DURATION}秒" >> "$f"
            echo "============================================================" >> "$f"
            echo "" >> "$f"
        fi
    done
}

validate_pids() {
    local pids_str="$1"
    # 强约束：-p 只能传一个 PID，禁止逗号分隔多个。
    # SKILL.md 的"取第一个活跃 PID"在此升级为硬校验，避免 agent 误把
    # pgrep 输出的多行（master+worker、多实例）整列传给脚本。
    if [[ "$pids_str" =~ , ]]; then
        log_error "-p 仅支持单个 PID，禁止逗号分隔多个进程。"
        log_error "当前传入: $pids_str"
        log_error "请在调用方先用以下命令取一个活跃 PID（参见 SKILL.md）："
        log_error "    APP_PID=\$(pgrep -a \"\$APP_NAME\" | awk '\$2!=\"Z\" {print \$1; exit}')"
        return 1
    fi
    if [[ ! "$pids_str" =~ ^[0-9]+$ ]]; then
        log_error "无效的 PID: $pids_str（必须是纯数字）"
        return 1
    fi
    return 0
}

validate_output_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        log_warning "输出目录已存在: $dir（已存在文件将被覆盖）"
    else
        mkdir -p "$dir" || { log_error "无法创建输出目录: $dir"; return 1; }
    fi
    return 0
}

validate_collect_commands() {
    local -a requested=("$@")
    for cmd in "${requested[@]}"; do
        local found=false
        for avail in "${AVAILABLE_COMMANDS[@]}"; do
            [[ "$cmd" == "$avail" ]] && { found=true; break; }
        done
        if ! $found; then
            log_error "未知的采集项目: $cmd"
            log_info "可用项目: ${AVAILABLE_COMMANDS[*]}"
            return 1
        fi
    done
    return 0
}

check_commands() {
    log_info "========================================"
    log_info "依赖检查"
    log_info "========================================"
    local missing=()
    for cmd in lscpu dmidecode free vmstat ps ss ip; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warning "缺少以下命令（非关键）: ${missing[*]}"
    else
        log_success "✓ 基础命令检查通过"
    fi
    echo ""
}

parse_arguments() {
    while getopts "d:p:o:c:Ch" opt; do
        case ${opt} in
            d) [[ "$OPTARG" =~ ^[0-9]+$ ]] || { log_error "持续时间必须是数字"; exit 1; }
               DURATION=$OPTARG ;;
            p) PIDS="$OPTARG"
               validate_pids "$PIDS" || exit 1 ;;
            o) OUTPUT_DIR="$OPTARG"
               validate_output_dir "$OUTPUT_DIR" || exit 1
               set_output_file ;;
            c) IFS=',' read -ra SELECTED_COMMANDS <<< "$OPTARG"
               validate_collect_commands "${SELECTED_COMMANDS[@]}" || exit 1 ;;
            C) CHECK_ONLY=true ;;
            h) show_usage; exit 0 ;;
            \?) log_error "无效选项: -$OPTARG"; show_usage; exit 1 ;;
            :) log_error "选项 -$OPTARG 需要参数"; show_usage; exit 1 ;;
        esac
    done

    if [[ "$CHECK_ONLY" = false ]] && [[ -z "$DURATION" ]]; then
        log_error "缺少必需参数: -d <持续时间>"
        exit 1
    fi

    if [[ ${#SELECTED_COMMANDS[@]} -eq 0 ]]; then
        SELECTED_COMMANDS=("${AVAILABLE_COMMANDS[@]}")
    fi

    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="bottleneck_data_${ARCH_TARGET}_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$OUTPUT_DIR" || { log_error "无法创建输出目录: $OUTPUT_DIR"; exit 1; }
        set_output_file
    fi
}

# =============================================================================
# Phase 1: 系统静态信息采集
# =============================================================================

collect_static_info() {
    log_info "执行：系统环境静态信息收集"

    {
        echo "============================================================"
        echo "Phase 1: System Environment Static Information Collection"
        echo "============================================================"
        echo ""

        # ---- Hardware Specifications ----
        echo "========== Hardware Specifications =========="

        echo "--- CPU Model, Sockets, Cores, Threads, Cache ---"
        lscpu 2>/dev/null || true

        echo ""
        echo "--- CPU Processor Info ---"
        dmidecode -t processor 2>/dev/null || true

        echo ""
        echo "--- NUMA Topology ---"
        numactl --hardware 2>/dev/null || true

        echo ""
        echo "--- Memory DIMM Info ---"
        dmidecode -t memory 2>/dev/null | grep -E "Size|Speed|Type|Locator" || true

        echo ""
        echo "--- Physical Memory Summary ---"
        grep -E "MemTotal|SwapTotal|HugePages_Total|HugePages_Free" /proc/meminfo

        echo ""
        echo "--- Disk Devices and Topology ---"
        lsblk -o NAME,SIZE,TYPE,ROTA,MOUNTPOINT 2>/dev/null || true

        echo ""
        echo "--- SCSI Device Info ---"
        cat /proc/scsi/scsi 2>/dev/null || true

        echo ""
        echo "--- NIC Models ---"
        lspci 2>/dev/null | grep -i eth || true

        echo ""
        echo "--- NIC Driver and Firmware ---"
        for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
            echo "=== $iface ==="
            ethtool -i "$iface" 2>/dev/null || true
        done

        echo ""
        echo "--- Hardware Model ---"
        cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true
        dmidecode -t system 2>/dev/null | grep -E "Manufacturer|Product Name|Version" || true

        echo ""
        echo "--- CPU Frequency Scaling ---"
        cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true
        cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || true

        # ---- Software Versions ----
        echo ""
        echo "========== Software Versions =========="

        echo "--- OS Release ---"
        cat /etc/os-release 2>/dev/null || true

        echo ""
        echo "--- Kernel Version ---"
        uname -r && uname -v

        echo ""
        echo "--- GCC Version ---"
        gcc --version 2>/dev/null | head -1 || true

        echo ""
        echo "--- glibc Version ---"
        ldd --version 2>/dev/null | head -1 || true

        # ---- Kernel Boot Parameters ----
        echo ""
        echo "========== Kernel Boot Parameters =========="

        echo "--- Kernel Command Line ---"
        cat /proc/cmdline 2>/dev/null || true

        echo ""
        echo "--- Performance-Related sysctl: vm.* ---"
        sysctl -a 2>/dev/null | grep -E "^vm\.(swappiness|dirty_ratio|dirty_background_ratio|dirty_writeback_centisecs|min_free_kbytes|vfs_cache_pressure|overcommit_memory|overcommit_ratio|nr_hugepages|zone_reclaim_mode|numa_balancing)" || true

        echo ""
        echo "--- Performance-Related sysctl: net.* ---"
        sysctl -a 2>/dev/null | grep -E "^net\.(core\.(somaxconn|netdev_max_backlog|netdev_budget|rmem_max|wmem_max)|ipv4\.(tcp_tw_reuse|tcp_max_syn_backlog|tcp_rmem|tcp_wmem|tcp_syncookies|tcp_fin_timeout|tcp_fastopen))" || true

        echo ""
        echo "--- Performance-Related sysctl: kernel.sched*/numa/threads ---"
        sysctl -a 2>/dev/null | grep -E "^kernel\.(sched_(min_granularity_ns|wakeup_granularity_ns|migration_cost_ns|cfs_bandwidth_slice_us|autogroup_enabled)|numa_balancing|threads-max)" || true

        echo ""
        echo "--- Performance-Related sysctl: fs.* ---"
        sysctl -a 2>/dev/null | grep -E "^fs\.(file-max|aio-max-nr|nr_open|inotify\.)" || true

        echo ""
        echo "--- Performance-Relevant Kernel Modules ---"
        lsmod 2>/dev/null | grep -iE "kvm|nvme|mlx|io_uring|dpdk|vfio|iommu|intel_cstate|intel_uncore|acpi_cpufreq|cpufreq|tuned" || true

        echo ""
        echo "--- Kernel Tickless / nohz / Preempt Config ---"
        cat "/boot/config-$(uname -r)" 2>/dev/null | grep -E "NO_HZ|HZ_1000|PREEMPT" || true

        echo ""
        echo "--- Transparent Hugepage Status ---"
        cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true

        echo ""
        echo "--- I/O Scheduler per Block Device ---"
        for dev in $(ls /sys/block/ 2>/dev/null); do
            echo "$dev: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null)"
        done || true

        echo ""
        echo "--- Default IRQ Affinity ---"
        cat /proc/irq/default_smp_affinity 2>/dev/null || true

        echo ""
        echo "============================================================"
        echo "Phase 1: Static Information Collection Complete"
        echo "============================================================"
    } >> "$STATIC_FILE"

    log_success "√ 系统环境静态信息收集完成"
}

# =============================================================================
# Phase 2.1: 全局资源瓶颈识别
# =============================================================================

collect_global_bottleneck() {
    log_info "执行：全局资源瓶颈识别"

    local bottleneck_success=false
    local temp_file="${BOTTLENECK_FILE}.tmp"

    {
        echo "============================================================"
        echo "Phase 2.1: Global Resource Bottleneck Identification"
        echo "============================================================"
        echo ""

        # ---- CPU ----
        echo "========== CPU Bottleneck Indicators =========="
        if command -v mpstat &>/dev/null; then
            echo "--- CPU Utilization Per Core (5s sample, skip 100% idle) ---"
            mpstat -P ALL 1 5 2>/dev/null | grep 'Average' | awk 'NR==1 || $3=="all" || $NF != "100.00"'
            bottleneck_success=true
        else
            echo "--- CPU Utilization: mpstat not available ---"
        fi
        echo ""

        echo "--- Load Average vs CPU Count ---"
        [ -r /proc/loadavg ] && cat /proc/loadavg && bottleneck_success=true
        echo ""

        echo "--- Context Switches and Interrupts (5s interval) ---"
        if command -v vmstat &>/dev/null; then
            vmstat 5 2 2>/dev/null | awk 'NR<=2{print; next} NR==3{next} {print; exit}'
            bottleneck_success=true
        fi
        echo ""

        echo "--- Top 30 Context Switch Tasks ---"
        if command -v pidstat &>/dev/null; then
            echo "      UID       PID   cswch/s nvcswch/s  Command"
            pidstat -w 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k4 -rn | head -30
            bottleneck_success=true
        fi
        echo ""

        # ---- Memory ----
        echo "========== Memory Bottleneck Indicators =========="
        echo "--- Swap Usage and Pressure ---"
        free -h 2>/dev/null && bottleneck_success=true
        echo ""

        echo "--- Key Swap Metrics ---"
        grep -E "SwapTotal|SwapFree|SwapCached|CommitLimit|Committed_AS" /proc/meminfo 2>/dev/null && bottleneck_success=true
        echo ""

        echo "--- Page Faults - Top 20 by majflt/s ---"
        if command -v pidstat &>/dev/null; then
            echo "      UID       PID  minflt/s  majflt/s     VSZ     RSS   %MEM  Command"
            pidstat -r 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20
            bottleneck_success=true
        fi
        echo ""

        echo "--- Slab Memory Usage ---"
        grep -E "Slab|SReclaimable|SUnreclaim" /proc/meminfo 2>/dev/null && bottleneck_success=true
        echo ""

        # ---- I/O ----
        echo "========== I/O Bottleneck Indicators =========="
        echo "--- Disk Utilization (5s sample, skip 0% util) ---"
        if command -v iostat &>/dev/null; then
            iostat -xz 5 2 2>/dev/null | awk '/^avg-cpu/{report++; if(report==2) print; next} /^Device/{if(report==2) print; next} /^$/{next} /Linux/{next} report==2 {if(/^[[:space:]]*[0-9]/){print; next} if(/^[a-z]/ && $NF+0>0){print; next}}'
            bottleneck_success=true
        fi
        echo ""

        echo "--- Queue Depth (inflight_IO) ---"
        echo "major minor device inflight_IO"
        awk '{print $1, $2, $3, $12}' /proc/diskstats 2>/dev/null && bottleneck_success=true
        echo ""

        echo "--- df -h ---"
        df -h 2>/dev/null
        echo ""

        echo "--- Top 20 I/O Processes by kB_wr/s ---"
        if command -v pidstat &>/dev/null; then
            echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"
            pidstat -d 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20
            bottleneck_success=true
        fi
        echo ""

        # ---- Network ----
        echo "========== Network Bottleneck Indicators =========="
        echo "--- Network Interface Stats (5s sample, skip idle) ---"
        if command -v sar &>/dev/null; then
            sar -n DEV 1 5 2>/dev/null | grep 'Average' | awk 'NR==1 || $5+0>0 || $6+0>0'
            bottleneck_success=true
        fi
        echo ""

        echo "--- Network Error Stats (skip all-zero) ---"
        if command -v sar &>/dev/null; then
            sar -n EDEV 1 5 2>/dev/null | grep 'Average' | awk 'NR==1{print; next} {for(i=3;i<=NF;i++) if($i+0>0){print; next}}'
            bottleneck_success=true
        fi
        echo ""

        echo "--- TCP Retransmissions and Drops (5s delta) ---"
        if command -v nstat &>/dev/null; then
            nstat -az 2>/dev/null | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_before_$$.txt
            sleep 5
            nstat -az 2>/dev/null | grep -E "^(TcpOutSegs|TcpRetransSegs|TcpExtTCPLostRetransmit|TcpExtListenOverflows|TcpExtListenDrops)" | awk '{print $1,$2}' > /tmp/nstat_after_$$.txt
            if [ -s /tmp/nstat_before_$$.txt ] && [ -s /tmp/nstat_after_$$.txt ]; then
                echo "counter delta rate/s"
                join /tmp/nstat_before_$$.txt /tmp/nstat_after_$$.txt | awk -v s=5 '{printf "%-40s %8d %8.1f\n", $1, $3-$2, ($3-$2)/s}'
                bottleneck_success=true
            fi
            rm -f /tmp/nstat_before_$$.txt /tmp/nstat_after_$$.txt
        fi
        echo ""

        echo "--- Connection Backlog ---"
        if command -v ss &>/dev/null; then
            echo "TIME_WAIT connections:"
            ss -tan state time-wait 2>/dev/null | wc -l
            bottleneck_success=true
        fi
        echo ""

        echo "--- Top 10 Ports by Established Connections ---"
        if command -v ss &>/dev/null; then
            echo "count port"
            ss -tn state established 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | sort | uniq -c | sort -rn | head -10
            bottleneck_success=true
        fi
        echo ""

        echo "============================================================"
        echo "Phase 2.1: Global Resource Bottleneck Identification Complete"
        echo "============================================================"
    } >> "$temp_file"

    if [ "$bottleneck_success" = true ]; then
        mv "$temp_file" "$BOTTLENECK_FILE"
        log_success "√ 全局资源瓶颈识别完成"
    else
        rm -f "$temp_file"
        log_warning "全局资源瓶颈识别全部失败"
    fi
}

# =============================================================================
# Phase 2.2: 顶级资源进程识别
# =============================================================================

collect_top_processes() {
    log_info "执行：顶级资源进程识别"

    local temp_file="${TOP_PROC_FILE}.tmp"
    local has_output=false

    {
        echo "============================================================"
        echo "Phase 2.2: Top Resource Process Identification"
        echo "============================================================"
        echo ""

        # Top 20 CPU
        echo "--- Top 20 CPU Processes ---"
        if command -v ps &>/dev/null; then
            ps aux --sort=-%cpu 2>/dev/null | head -20
            has_output=true
        fi
        echo ""

        # Top 20 Memory
        echo "--- Top 20 Memory Processes ---"
        ps aux --sort=-%mem 2>/dev/null | head -20
        echo ""

        # Top 20 I/O (iotop)
        echo "--- Top 20 I/O Processes by iotop ---"
        if command -v iotop &>/dev/null; then
            local iotop_temp=$(mktemp)
            {
                echo "    PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN      IO    COMMAND"
                iotop -oP -b -n 5 -d 1 2>/dev/null | grep -E "^\s*[0-9]" | head -20
            } > "$iotop_temp" 2>/dev/null
            local data_lines=$(grep -c -E "^\s*[0-9]" "$iotop_temp" 2>/dev/null)
            if [ -s "$iotop_temp" ] && [ "${data_lines:-0}" -gt 0 ]; then
                cat "$iotop_temp"
                has_output=true
            else
                echo "  No I/O activity detected (may need root)"
            fi
            rm -f "$iotop_temp"
        fi
        echo ""

        # Top 20 I/O (pidstat)
        echo "--- Top 20 I/O Processes by pidstat (by kB_wr/s) ---"
        if command -v pidstat &>/dev/null; then
            local pidstat_temp=$(mktemp)
            {
                echo "      UID       PID   kB_rd/s   kB_wr/s kB_ccwr/s iodelay  Command"
                pidstat -d 1 5 2>/dev/null | grep 'Average' | grep -v "UID" | sort -k5 -rn | head -20
            } > "$pidstat_temp" 2>/dev/null
            local pdl=$(grep -c -E "^\s*[0-9]" "$pidstat_temp" 2>/dev/null)
            if [ -s "$pidstat_temp" ] && [ "${pdl:-0}" -gt 1 ]; then
                cat "$pidstat_temp"
                has_output=true
            else
                echo "  No I/O activity detected"
            fi
            rm -f "$pidstat_temp"
        fi
        echo ""

        echo "============================================================"
        echo "Phase 2.2: Complete"
        echo "============================================================"
    } >> "$temp_file"

    if [ "$has_output" = true ]; then
        mv "$temp_file" "$TOP_PROC_FILE"
        log_success "√ 顶级资源进程识别完成"
    else
        rm -f "$temp_file"
        log_warning "顶级资源进程识别全部失败"
    fi
}

# =============================================================================
# Phase 3.1: 热点函数分析（需要 PID）
# =============================================================================

collect_hotspot_analysis() {
    if [[ -z "$PIDS" ]]; then
        log_warning "未指定进程，跳过热点函数分析"
        return
    fi

    local hotspot_success=false
    IFS=',' read -ra pid_array <<< "$PIDS"

    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs)
        log_info "执行：热点函数分析 (PID=$single_pid)"

        local temp_file="${HOTSPOT_ANALYSIS_FILE}.tmp.${single_pid}"

        {
            echo "============================================================"
            echo "Phase 3.1: Hotspot Function Analysis (PID=$single_pid)"
            echo "============================================================"
            echo ""
        } > "$temp_file"

        if ! check_command perf; then
            echo "错误: perf 命令未找到" >> "$temp_file"
            rm -f "$temp_file"
            return
        fi

        local perf_success=false
        local perf_data_file="/tmp/perf_bn_${single_pid}.data"

        # perf record (30s)
        echo "--- perf record (30s sampling) ---" >> "$temp_file"
        if timeout 35 perf record -p "$single_pid" -g -o "$perf_data_file" -- sleep 30 2>&1 >> "$temp_file"; then
            echo "perf record 执行成功" >> "$temp_file"
            echo "" >> "$temp_file"

            echo "--- perf report ---" >> "$temp_file"
            if perf report -i "$perf_data_file" --stdio --percent-limit 1 2>&1 >> "$temp_file"; then
                perf_success=true
                echo "" >> "$temp_file"
            fi
            rm -f "$perf_data_file"
        else
            echo "perf record 执行失败 (exit=$?)" >> "$temp_file"
        fi

        if [ "$perf_success" = true ]; then
            hotspot_success=true
            if [ ! -f "$HOTSPOT_ANALYSIS_FILE" ]; then
                cat "$temp_file" > "$HOTSPOT_ANALYSIS_FILE"
            else
                cat "$temp_file" >> "$HOTSPOT_ANALYSIS_FILE"
            fi
            log_success "热点函数分析成功 (PID=$single_pid)"
        else
            log_error "热点函数分析失败 (PID=$single_pid)"
        fi
        rm -f "$temp_file"
    done

    if [ "$hotspot_success" = true ]; then
        echo "" >> "$HOTSPOT_ANALYSIS_FILE"
        echo "============================================================" >> "$HOTSPOT_ANALYSIS_FILE"
        echo "Phase 3.1: Hotspot Function Analysis Complete" >> "$HOTSPOT_ANALYSIS_FILE"
        echo "============================================================" >> "$HOTSPOT_ANALYSIS_FILE"
        log_success "√ 热点函数分析完成"
    else
        log_warning "热点函数分析全部失败"
    fi
}

# =============================================================================
# Phase 3.2: 系统调用分析（需要 PID）
# =============================================================================

collect_syscall_analysis() {
    if [[ -z "$PIDS" ]]; then
        log_warning "未指定进程ID，跳过系统调用分析"
        return
    fi

    local syscall_success=false
    IFS=',' read -ra pid_array <<< "$PIDS"

    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs)
        log_info "执行：系统调用分析 (PID=$single_pid)"

        local temp_file="${SYSCALL_FILE}.tmp.${single_pid}"

        {
            echo "============================================================"
            echo "Phase 3.2: Syscall Analysis (PID=$single_pid)"
            echo "============================================================"
            echo ""
        } > "$temp_file"

        if check_command strace; then
            echo "--- strace -c: Syscall summary ---" >> "$temp_file"
            timeout "$DURATION" strace -p "$single_pid" -c -f >> "$temp_file" 2>&1
            local rc=$?
            if [ $rc -eq 124 ]; then
                echo "" >> "$temp_file"
                echo "strace 执行成功" >> "$temp_file"
                syscall_success=true

                if [ ! -f "$SYSCALL_FILE" ]; then
                    cat "$temp_file" > "$SYSCALL_FILE"
                else
                    cat "$temp_file" >> "$SYSCALL_FILE"
                fi
                log_success "系统调用分析成功 (PID=$single_pid)"
            else
                echo "错误: strace 执行失败 (exit=$rc)" >> "$temp_file"
                log_error "系统调用分析失败 (PID=$single_pid)"
            fi
        else
            echo "错误: strace 命令未找到" >> "$temp_file"
            log_error "strace 命令未找到"
        fi
        rm -f "$temp_file"
    done

    if [ "$syscall_success" = true ]; then
        echo "" >> "$SYSCALL_FILE"
        echo "============================================================" >> "$SYSCALL_FILE"
        echo "Phase 3.2: Syscall Analysis Complete" >> "$SYSCALL_FILE"
        echo "============================================================" >> "$SYSCALL_FILE"
        log_success "√ 系统调用分析完成"
    else
        log_warning "系统调用分析全部失败"
    fi
}

# =============================================================================
# I/O Metrics 深度分析
# =============================================================================

collect_io_metrics() {
    log_info "执行：I/O Metrics 深度分析"

    local io_success=false
    local temp_file="${IO_METRICS_FILE}.tmp"

    {
        echo "============================================================"
        echo "Phase: I/O Metrics for Bottleneck Analysis"
        echo "============================================================"
        echo "采集时间: $(date)"
        echo "持续时间: ${DURATION}秒"
        [[ -n "$PIDS" ]] && echo "目标进程: $PIDS"
        echo ""

        # System Overview
        echo "=== System Overview ==="
        echo "Kernel: $(uname -r)"
        echo "CPU Count: $(nproc)"
        echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
        echo ""
        io_success=true

        # Disk Devices
        echo "=== Disk Devices ==="
        lsblk -d -n -o NAME,SIZE,TYPE 2>/dev/null | grep -E 'disk|nvme' || echo "No disk devices found"
        echo ""

        # I/O Scheduler
        echo "=== I/O Scheduler Configuration ==="
        local sched_ok=false
        for dev in $(lsblk -d -n -o NAME 2>/dev/null | grep -E '^vd|^sd|^nvme' | head -5); do
            if [ -r "/sys/block/$dev/queue/scheduler" ]; then
                echo "--- /dev/$dev ---"
                echo "scheduler: $(grep -o '\[.*\]' /sys/block/$dev/queue/scheduler 2>/dev/null || echo 'N/A')"
                echo "nr_requests: $(cat /sys/block/$dev/queue/nr_requests 2>/dev/null || echo 'N/A')"
                echo "read_ahead_kb: $(cat /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || echo 'N/A')"
                echo "max_sectors_kb: $(cat /sys/block/$dev/queue/max_sectors_kb 2>/dev/null || echo 'N/A')"
                echo "rotational: $(cat /sys/block/$dev/queue/rotational 2>/dev/null || echo 'N/A')"
                echo "nomerges: $(cat /sys/block/$dev/queue/nomerges 2>/dev/null || echo 'N/A')"
                sched_ok=true
            fi
        done
        $sched_ok || echo "No I/O scheduler info available"
        echo ""

        # Memory/Page Cache
        echo "=== Memory/Page Cache Settings ==="
        for setting in vfs_cache_pressure swappiness dirty_background_ratio dirty_ratio dirty_writeback_centisecs dirty_expire_centisecs min_free_kbytes; do
            [ -r "/proc/sys/vm/$setting" ] && echo "$setting: $(cat /proc/sys/vm/$setting 2>/dev/null)"
        done
        echo ""

        # Process I/O (if PID)
        if [[ -n "$PIDS" ]]; then
            IFS=',' read -ra pa <<< "$PIDS"
            for sp in "${pa[@]}"; do
                sp=$(echo "$sp" | xargs)
                if [ -d "/proc/$sp" ]; then
                    echo "=== Process I/O Configuration (PID $sp) ==="
                    echo "--- IO Priority ---"
                    ionice -p $sp 2>&1 || echo "  ionice not available"
                    echo "--- IO Statistics ---"
                    cat "/proc/$sp/io" 2>/dev/null || echo "  /proc/$sp/io not available"
                    echo "--- Open Files Limit ---"
                    [ -r "/proc/$sp/limits" ] && echo "  soft=$(awk '/Max open files/{print $4}' /proc/$sp/limits)  hard=$(awk '/Max open files/{print $5}' /proc/$sp/limits)"
                    [ -d "/proc/$sp/fd" ] && echo "  open_fds=$(ls /proc/$sp/fd/ 2>/dev/null | wc -l)"
                    echo ""
                fi
            done
        fi

        # System-wide I/O Limits
        echo "=== System-wide I/O Limits ==="
        echo "--- AIO Limits ---"
        [ -r /proc/sys/fs/aio-max-nr ] && echo "aio-max-nr: $(cat /proc/sys/fs/aio-max-nr)"
        [ -r /proc/sys/fs/aio-nr ] && echo "aio-nr: $(cat /proc/sys/fs/aio-nr)"
        echo "--- File Handle Limits ---"
        [ -r /proc/sys/fs/file-max ] && echo "file-max: $(cat /proc/sys/fs/file-max)"
        [ -r /proc/sys/fs/file-nr ] && awk '{printf "file-nr: allocated=%s free=%s max=%s\n", $1, $2, $3}' /proc/sys/fs/file-nr
        [ -r /proc/sys/fs/nr_open ] && echo "nr_open: $(cat /proc/sys/fs/nr_open)"
        echo ""

        # Real-time data collection
        echo "=== I/O Performance Data Collection (${DURATION} seconds) ==="
        local VMSTAT_TMP="/tmp/vmstat_io_bn_$$.txt"
        local IOSTAT_TMP="/tmp/iostat_io_bn_$$.txt"
        local realtime_ok=false

        if command -v vmstat &>/dev/null; then
            vmstat 1 "$DURATION" > "$VMSTAT_TMP" 2>&1 &
            local VMSTAT_PID=$!
            wait $VMSTAT_PID 2>/dev/null
            if [ -s "$VMSTAT_TMP" ]; then
                echo "--- VMStat Analysis ---"
                awk 'NR<=2 || /^[[:space:]]*[0-9]/' "$VMSTAT_TMP" | head -15
                echo ""
                realtime_ok=true; io_success=true
            fi
        fi

        if command -v iostat &>/dev/null; then
            iostat -x 1 "$DURATION" > "$IOSTAT_TMP" 2>&1 &
            local IOSTAT_PID=$!
            wait $IOSTAT_PID 2>/dev/null
            if [ -s "$IOSTAT_TMP" ]; then
                echo "--- Disk Utilization Summary ---"
                awk '$1 ~ /^[a-z]/ && $NF+0 > 0 { printf "%-10s util=%s%%  r/s=%s  w/s=%s  rKB/s=%s  wKB/s=%s  await=%s\n", $1, $NF, $2, $9, $3, $10, $5 }' "$IOSTAT_TMP" | head -20
                echo ""
                io_success=true; realtime_ok=true
            fi
        fi

        $realtime_ok || echo "No real-time I/O data collected"
        rm -f "$VMSTAT_TMP" "$IOSTAT_TMP"

        # Filesystem Mount Options
        echo "=== Filesystem Mount Options ==="
        mount 2>/dev/null | grep -E '^/dev| type ext[234]| type xfs| type btrfs' | head -10 || echo "No filesystem mount info"
        echo ""

        echo "=== NFS/CIFS Mount Options ==="
        local nfs_mounts=$(mount 2>/dev/null | grep -E 'type nfs|type cifs' | head -10)
        [ -n "$nfs_mounts" ] && echo "$nfs_mounts" || echo "No NFS/CIFS mounts"
        echo ""

        echo "============================================================"
        echo "I/O Metrics Analysis Complete"
        echo "============================================================"
    } >> "$temp_file"

    if [ "$io_success" = true ]; then
        mv "$temp_file" "$IO_METRICS_FILE"
        log_success "√ I/O Metrics 深度分析完成"
    else
        rm -f "$temp_file"
        log_warning "I/O Metrics 深度分析全部失败"
    fi
}

# =============================================================================
# Memory Metrics 深度分析
# =============================================================================

collect_mem_metrics() {
    log_info "执行：Memory Metrics 深度分析"

    local mem_success=false
    local temp_file="${MEM_METRICS_FILE}.tmp"

    {
        echo "============================================================"
        echo "Phase: Memory Metrics for Bottleneck Analysis"
        echo "============================================================"
        echo "采集时间: $(date)"
        [[ -n "$PIDS" ]] && echo "目标进程: $PIDS"
        echo ""

        echo "=== System Overview ==="
        echo "Kernel: $(uname -r)"
        echo "CPU Count: $(nproc)"
        echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
        echo ""
        mem_success=true

        # PSI
        echo "=== Memory Pressure (PSI) ==="
        [ -r /proc/pressure/mem ] && cat /proc/pressure/mem || echo "/proc/pressure/mem not available"
        echo ""

        # Memory Usage
        echo "=== Memory Usage ==="
        free -h 2>/dev/null && mem_success=true
        echo ""

        # OOM Stats
        echo "=== VM OOM Stats ==="
        grep -E 'oom_kill|pgmajfault' /proc/vmstat 2>/dev/null || echo "No OOM kills recorded"
        echo ""

        # Swap
        echo "=== Swap Configuration ==="
        swapon -s 2>/dev/null || cat /proc/swaps 2>/dev/null || echo "No swap"
        echo ""

        # Slab
        echo "=== Slab Info ==="
        head -30 /proc/slabinfo 2>/dev/null || echo "/proc/slabinfo not readable"
        echo ""

        # Vmalloc
        echo "=== Vmalloc Region ==="
        grep -E "VmallocTotal|VmallocUsed" /proc/meminfo 2>/dev/null
        echo ""

        # Allocation/Reclaim
        echo "=== Memory Allocation/Reclaim Stats ==="
        grep -E "pgfault|pgmajflt|pgalloc|pgfree|pgscank|pgscand|pgsteal|pgrotated" /proc/vmstat 2>/dev/null | head -20
        echo ""

        # Memory Details
        echo "=== Memory Details (meminfo) ==="
        grep -E "Active:|Inactive:|SReclaimable|SUnreclaim|Shmem:|VmallocUsed:|Committed_AS:" /proc/meminfo 2>/dev/null
        echo ""

        # HugePages
        echo "=== HugePages Configuration ==="
        [ -r /proc/sys/vm/nr_hugepages ] && echo "nr_hugepages: $(cat /proc/sys/vm/nr_hugepages)"
        grep -E "HugePages_Total|HugePages_Free|HugePages_Rsvd|Hugepagesize:" /proc/meminfo 2>/dev/null
        [ -r /sys/kernel/mm/transparent_hugepage/enabled ] && echo "transparent_hugepage: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
        echo ""

        # OOM Config
        echo "=== OOM Configuration ==="
        [ -r /proc/sys/vm/oom_kill_allocating_task ] && echo "oom_kill_allocating_task: $(cat /proc/sys/vm/oom_kill_allocating_task)"
        [ -r /proc/sys/vm/oom_dump_tasks ] && echo "oom_dump_tasks: $(cat /proc/sys/vm/oom_dump_tasks)"
        echo ""

        # KSM
        echo "=== KSM Configuration ==="
        if [ -r /sys/kernel/mm/ksm/run ]; then
            echo "ksm.run: $(cat /sys/kernel/mm/ksm/run)"
            echo "ksm.pages_shared: $(cat /sys/kernel/mm/ksm/pages_shared 2>/dev/null || echo 'N/A')"
            echo "ksm.pages_sharing: $(cat /sys/kernel/mm/ksm/pages_sharing 2>/dev/null || echo 'N/A')"
        else
            echo "KSM not available"
        fi
        echo ""

        # NUMA Balancing
        echo "=== NUMA Balancing ==="
        [ -r /proc/sys/kernel/numa_balancing ] && echo "numa_balancing: $(cat /proc/sys/kernel/numa_balancing)" || echo "numa_balancing: N/A"
        echo ""

        # Memory CGroup
        echo "=== Memory CGroup Limits ==="
        if [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
            echo "memory.limit_in_bytes: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
            echo "memory.usage_in_bytes: $(cat /sys/fs/cgroup/memory/memory.usage_in_bytes)"
        elif [ -r /sys/fs/cgroup/memory.max ]; then
            echo "memory.max: $(cat /sys/fs/cgroup/memory.max)"
            echo "memory.current: $(cat /sys/fs/cgroup/memory.current)"
        else
            echo "Memory cgroup not available"
        fi
        echo ""

        # Watermarks
        echo "=== Memory Watermarks ==="
        [ -r /proc/sys/vm/watermark_scale_factor ] && echo "watermark_scale_factor: $(cat /proc/sys/vm/watermark_scale_factor)"
        [ -r /proc/sys/vm/watermark_boost_factor ] && echo "watermark_boost_factor: $(cat /proc/sys/vm/watermark_boost_factor)"
        echo ""

        # Zone Info
        echo "=== Memory Zone Info ==="
        grep -E "Node|zone" /proc/zoneinfo 2>/dev/null | head -30
        echo ""

        # jemalloc
        echo "=== jemalloc Configuration ==="
        if [[ -n "$PIDS" ]]; then
            IFS=',' read -ra pa <<< "$PIDS"
            for sp in "${pa[@]}"; do
                sp=$(echo "$sp" | xargs)
                if [ -r "/proc/$sp/maps" ]; then
                    grep -i jemalloc "/proc/$sp/maps" 2>/dev/null | head -1 && echo "jemalloc detected in PID $sp" || echo "PID $sp does NOT use jemalloc"
                fi
            done
        fi
        echo "MALLOC_ARENA_MAX: ${MALLOC_ARENA_MAX:-not set}"
        echo "MALLOC_CONF: ${MALLOC_CONF:-not set}"
        echo ""

        # NUMA Statistics (system)
        echo "=== NUMA Statistics (system-wide) ==="
        grep -E "numa_hit|numa_miss|numa_foreign|numa_local|numa_other" /proc/vmstat 2>/dev/null | head -20
        echo ""

        # NUMA Statistics (process)
        if [[ -n "$PIDS" ]]; then
            IFS=',' read -ra pa <<< "$PIDS"
            for sp in "${pa[@]}"; do
                sp=$(echo "$sp" | xargs)
                if [ -d "/proc/$sp" ]; then
                    echo "=== Process NUMA Memory (PID: $sp) ==="
                    numastat -p $sp 2>/dev/null || echo "numastat not available"
                    echo ""
                fi
            done
        fi

        # NUMA Node Layout
        echo "=== NUMA Node Layout ==="
        numactl --hardware 2>/dev/null || echo "numactl not available"
        echo ""

        echo "=== NUMA Nodes ==="
        lscpu 2>/dev/null | grep "NUMA" || echo "lscpu not available"
        echo ""

        # Buddy Info
        echo "=== Memory per NUMA Node ==="
        cat /proc/buddyinfo 2>/dev/null || echo "Cannot read /proc/buddyinfo"
        echo ""

        # OOM Events
        echo "=== Recent OOM Events ==="
        dmesg 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10 || journalctl -k 2>/dev/null | grep -iE 'out of memory|oom kill' | tail -10 || echo "No recent OOM events"
        echo ""

        # ---- 完整补充数据 ----
        echo "=== 完整 /proc/meminfo ==="
        cat /proc/meminfo 2>/dev/null
        echo ""

        echo "=== 完整 /proc/vmstat ==="
        cat /proc/vmstat 2>/dev/null
        echo ""

        echo "=== 系统内存页大小 ==="
        getconf PAGE_SIZE 2>/dev/null || echo "获取失败"
        echo ""

        echo "=== 大页目录详情 ==="
        if [ -d /sys/kernel/mm/hugepages ]; then
            for d in /sys/kernel/mm/hugepages/hugepages-*; do
                [ -d "$d" ] && echo "$(basename "$d"): nr_hugepages=$(cat "$d/nr_hugepages" 2>/dev/null), free=$(cat "$d/free_hugepages" 2>/dev/null)"
            done
        fi
        echo ""

        echo "=== NUMA 节点内存详情 ==="
        if [ -d /sys/devices/system/node ]; then
            for node in /sys/devices/system/node/node*; do
                [ -d "$node" ] || continue
                node_name=$(basename "$node")
                echo "--- $node_name ---"
                [ -f "$node/meminfo" ] && grep -E "MemTotal|MemFree|Active|Inactive|Dirty|Writeback|FilePages|Mapped|AnonPages|Shmem|KernelStack|PageTables" "$node/meminfo" 2>/dev/null
            done
        fi
        echo ""

        echo "============================================================"
        echo "Memory Metrics Analysis Complete"
        echo "============================================================"
    } >> "$temp_file"

    if [ "$mem_success" = true ]; then
        mv "$temp_file" "$MEM_METRICS_FILE"
        log_success "√ Memory Metrics 深度分析完成"
    else
        rm -f "$temp_file"
        log_warning "Memory Metrics 深度分析全部失败"
    fi
}

# =============================================================================
# Network Metrics 深度分析
# =============================================================================

collect_net_metrics() {
    log_info "执行：Network Metrics 深度分析"

    local net_success=false
    local temp_file="${NET_METRICS_FILE}.tmp"

    {
        echo "============================================================"
        echo "Phase: Network Metrics for Bottleneck Analysis"
        echo "============================================================"
        echo "采集时间: $(date)"
        echo "持续时间: ${DURATION}秒"
        echo ""

        # Interface List
        echo "=== Network Interfaces ==="
        ip -br link show 2>/dev/null && net_success=true
        echo ""

        # Sysctl Config
        echo "=== Network Sysctl Configuration ==="
        for key in tcp_tw_reuse tcp_timestamps tcp_sack tcp_window_scaling tcp_congestion_control \
                   tcp_rmem tcp_wmem tcp_mem tcp_max_syn_backlog tcp_fin_timeout ip_local_port_range \
                   netdev_max_backlog netdev_budget somaxconn rmem_default rmem_max wmem_default wmem_max; do
            if [ -r "/proc/sys/net/ipv4/${key}" ]; then
                echo "${key}: $(cat /proc/sys/net/ipv4/${key} 2>/dev/null)"
            elif [ -r "/proc/sys/net/core/${key}" ]; then
                echo "${key}: $(cat /proc/sys/net/core/${key} 2>/dev/null)"
            else
                echo "${key}: N/A"
            fi
        done
        net_success=true
        echo ""

        # NIC Configuration
        echo "=== NIC Configuration ==="
        ACTIVE_IFACES=$(ip -br link show 2>/dev/null | awk '$2=="UP" {print $1}' | grep -v lo | head -5)
        if [ -z "$ACTIVE_IFACES" ]; then
            echo "No active network interfaces found"
        else
            for iface in $ACTIVE_IFACES; do
                echo "--- $iface ---"
                if command -v ethtool &>/dev/null; then
                    echo "Link Info:"
                    ethtool "$iface" 2>/dev/null | grep -E "Speed|Duplex|Link detected|Auto-negotiation" | sed 's/^\t*//' || true
                    echo ""
                    echo "Driver Info:"
                    ethtool -i "$iface" 2>/dev/null | grep -E "driver|version|firmware|bus-info" | sed 's/^[^:]*: //' | paste -sd, - || true
                    echo ""
                    echo "[Queue/Channel Configuration]"
                    ethtool -l "$iface" 2>/dev/null || true
                    echo ""
                    echo "[Ring Buffer]"
                    ethtool -g "$iface" 2>/dev/null || true
                    echo ""
                    echo "[Coalesce Settings]"
                    ethtool -c "$iface" 2>/dev/null || true
                    echo ""
                    echo "[Pause Frame]"
                    ethtool -a "$iface" 2>/dev/null || true
                    echo ""
                    echo "[Offload Features]"
                    ethtool -k "$iface" 2>/dev/null | head -30 || true
                    echo ""

                    # IRQ Affinity
                    BUS_INFO=$(ethtool -i "$iface" 2>/dev/null | grep 'bus-info' | awk '{print $2}')
                    if [ -n "$BUS_INFO" ]; then
                        echo "--- IRQ Affinity ---"
                        grep "$BUS_INFO" /proc/interrupts 2>/dev/null | while read -r line; do
                            IRQ=$(echo "$line" | awk '{print $1}' | tr -d ':')
                            AFFINITY=$(cat "/proc/irq/$IRQ/smp_affinity" 2>/dev/null || echo 'N/A')
                            DESC=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
                            echo "IRQ $IRQ: $AFFINITY  ($DESC)"
                        done
                    fi
                fi
                echo ""
            done
            net_success=true
        fi

        # SAR Network Stats
        echo "=== Network Performance Data Collection (${DURATION} seconds) ==="
        ACTIVE_IFACES=$(ip -br link show 2>/dev/null | awk '$2=="UP" && $1!="lo" {print $1}' | head -5 | paste -sd,)
        if command -v sar &>/dev/null && [ -n "$ACTIVE_IFACES" ]; then
            local SAR_DEV_TMP="/tmp/sar_dev_bn_$$.txt"
            local SAR_EDEV_TMP="/tmp/sar_edeve_bn_$$.txt"

            sar -n DEV "$INTERVAL" "$DURATION" --iface="$ACTIVE_IFACES" > "$SAR_DEV_TMP" 2>&1 &
            local SAR_DEV_PID=$!
            sar -n EDEV "$INTERVAL" "$DURATION" --iface="$ACTIVE_IFACES" > "$SAR_EDEV_TMP" 2>&1 &
            local SAR_EDEV_PID=$!
            wait $SAR_DEV_PID $SAR_EDEV_PID 2>/dev/null

            echo "--- Network Device Stats (sar -n DEV) ---"
            [ -s "$SAR_DEV_TMP" ] && tail -n +4 "$SAR_DEV_TMP" || echo "No data"
            echo ""
            echo "--- Network Error Stats (sar -n EDEV) ---"
            [ -s "$SAR_EDEV_TMP" ] && tail -n +4 "$SAR_EDEV_TMP" || echo "No data"
            echo ""
            rm -f "$SAR_DEV_TMP" "$SAR_EDEV_TMP"
            net_success=true
        else
            echo "sar not available or no active interfaces"
            echo ""
        fi

        # Latency Tests
        echo "=== Latency Tests ==="
        GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
        if [ -n "$GATEWAY" ]; then
            echo "Default gateway: $GATEWAY"
            ping -c 5 "$GATEWAY" 2>/dev/null | tail -2 || echo "Gateway ping failed"
        fi
        echo ""
        echo "--- Loopback Latency ---"
        ping -c 5 127.0.0.1 2>/dev/null | tail -2 || echo "Loopback ping failed"
        echo ""

        # TCP Stats
        echo "=== TCP Statistics ==="
        netstat -s 2>/dev/null | sed -n '/^Tcp:/,/^$/p' | head -50 || echo "netstat not available"
        echo ""

        # Socket Summary
        echo "=== Socket Summary ==="
        ss -s 2>/dev/null || echo "ss not available"
        echo ""

        # Socket Memory
        echo "=== Socket Memory ==="
        cat /proc/net/sockstat 2>/dev/null && net_success=true
        echo ""

        # TCP Connection States
        echo "=== TCP Connection States Distribution ==="
        ss -tan 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 || echo "ss not available"
        echo ""

        # Network Queue
        echo "=== Network Queue Statistics ==="
        grep -E "TcpExt|IpExt" /proc/net/netstat 2>/dev/null | head -5 || echo "Cannot read /proc/net/netstat"
        echo ""

        # ---- 补充数据 ----
        echo "=== 接口详细状态 (/sys/class/net) ==="
        for iface_dir in /sys/class/net/*; do
            iface_name=$(basename "$iface_dir")
            echo "$iface_name: ifindex=$(cat "$iface_dir/ifindex" 2>/dev/null) operstate=$(cat "$iface_dir/operstate" 2>/dev/null) carrier=$(cat "$iface_dir/carrier" 2>/dev/null) mtu=$(cat "$iface_dir/mtu" 2>/dev/null) speed=$(cat "$iface_dir/speed" 2>/dev/null) duplex=$(cat "$iface_dir/duplex" 2>/dev/null)"
        done
        echo ""

        echo "=== ip addr show ==="
        ip addr show 2>/dev/null
        echo ""

        echo "=== 路由表 (ip route show) ==="
        ip route show 2>/dev/null
        echo ""

        echo "=== ARP 表 ==="
        arp -n 2>/dev/null || cat /proc/net/arp 2>/dev/null
        echo ""

        echo "=== 网络统计 (netstat -s) 完整版 ==="
        netstat -s 2>/dev/null || { cat /proc/net/netstat 2>/dev/null; cat /proc/net/snmp 2>/dev/null; }
        echo ""

        echo "=== 监听端口 (ss -tlnp) ==="
        ss -tlnp 2>/dev/null
        echo ""

        echo "=== 网卡队列与 RPS 配置 ==="
        for iface_dir in /sys/class/net/*; do
            iface_name=$(basename "$iface_dir")
            if [ "$iface_name" != "lo" ] && [ -d "$iface_dir/queues" ]; then
                rx_count=$(ls -d "$iface_dir/queues/rx-"* 2>/dev/null | wc -l)
                tx_count=$(ls -d "$iface_dir/queues/tx-"* 2>/dev/null | wc -l)
                echo "$iface_name: RX队列=$rx_count, TX队列=$tx_count"
                [ -f "$iface_dir/queues/rx-0/rps_cpus" ] && echo "  RPS cpus (rx-0): $(cat "$iface_dir/queues/rx-0/rps_cpus")"
                [ -f "$iface_dir/queues/rx-0/rps_flow_cnt" ] && echo "  RPS flow_cnt (rx-0): $(cat "$iface_dir/queues/rx-0/rps_flow_cnt")"
            fi
        done
        echo ""

        echo "=== 网卡 ntuple 支持 ==="
        for iface_dir in /sys/class/net/*; do
            iface_name=$(basename "$iface_dir")
            [ "$iface_name" = "lo" ] && continue
            if command -v ethtool &>/dev/null; then
                ntuple_info=$(ethtool -k "$iface_name" 2>/dev/null | grep ntuple || echo 'ntuple: unknown')
                echo "$iface_name: $ntuple_info"
            fi
        done
        echo ""

        echo "=== 网络排队规则 (tc qdisc show) ==="
        tc qdisc show 2>/dev/null
        echo ""

        echo "=== /proc/net/dev ==="
        cat /proc/net/dev 2>/dev/null
        echo ""

        echo "=== 常见进程名列表 (Top 30) ==="
        ps -eo comm --no-headers 2>/dev/null | sort -u | head -30
        echo ""

        echo "============================================================"
        echo "Network Metrics Analysis Complete"
        echo "============================================================"
    } >> "$temp_file"

    rm -f /tmp/sar_*_bn_$$.txt /tmp/ping_*_bn_$$.txt

    if [ "$net_success" = true ]; then
        mv "$temp_file" "$NET_METRICS_FILE"
        log_success "√ Network Metrics 深度分析完成"
    else
        rm -f "$temp_file"
        log_warning "Network Metrics 深度分析全部失败"
    fi
}

# =============================================================================
# CPU 深度信息采集
# =============================================================================

collect_cpu_detail_info() {
    log_info "执行：CPU 深度信息采集"

    {
        echo "============================================================"
        echo "CPU 深度信息采集"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        # Online CPUs
        echo "=== 在线 CPU 核心列表 ==="
        if [ -f /sys/devices/system/cpu/online ]; then
            echo "CPU 在线列表: $(cat /sys/devices/system/cpu/online)"
            COUNT=$(tr ',' '\n' < /sys/devices/system/cpu/online | while read -r r; do
                if [[ "$r" == *-* ]]; then seq "${r%-*}" "${r#*-}" || true
                else echo "$r"; fi
            done | wc -l)
            echo "在线CPU数量: $COUNT"
        else
            echo "在线CPU数量: $(nproc)"
        fi
        echo ""

        # /proc/cpuinfo
        echo "=== /proc/cpuinfo ==="
        cat /proc/cpuinfo 2>/dev/null
        echo ""

        # NUMA sysfs
        echo "=== NUMA 节点 sysfs 详情 ==="
        if [ -d /sys/devices/system/node ]; then
            for node in /sys/devices/system/node/node*; do
                if [ -d "$node" ]; then
                    node_name=$(basename "$node")
                    echo "--- $node_name ---"
                    [ -f "$node/cpulist" ] && echo "CPU列表: $(cat "$node/cpulist")"
                    [ -f "$node/distance" ] && echo "距离: $(cat "$node/distance")"
                fi
            done
            echo ""
            for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
                cpu_name=$(basename "$cpu_dir")
                if [ -f "$cpu_dir/topology/physical_package_id" ]; then
                    echo "$cpu_name socket=$(cat "$cpu_dir/topology/physical_package_id" 2>/dev/null)"
                fi
            done
        fi
        echo ""

        # SMT
        echo "=== SMT 超线程状态 ==="
        [ -f /sys/devices/system/cpu/smt/active ] && echo "SMT active: $(cat /sys/devices/system/cpu/smt/active)" || echo "SMT active: unknown"
        for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
            cpu_name=$(basename "$cpu_dir")
            if [ -f "$cpu_dir/topology/thread_siblings_list" ]; then
                echo "$cpu_name siblings=$(cat "$cpu_dir/topology/thread_siblings_list" 2>/dev/null)"
            fi
        done
        echo ""

        # CPU Frequency
        echo "=== CPU 频率信息 ==="
        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
                if [ -d "$cpu" ]; then
                    cpu_name=$(basename "$(dirname "$cpu")")
                    echo "$cpu_name:"
                    cat "$cpu/scaling_cur_freq" 2>/dev/null | awk '{printf "  当前频率: %s kHz\n", $1}' || true
                    cat "$cpu/cpuinfo_max_freq" 2>/dev/null | awk '{printf "  硬件最大频率: %s kHz\n", $1}' || true
                    cat "$cpu/scaling_governor" 2>/dev/null | awk '{printf "  调频策略: %s\n", $1}' || true
                fi
            done
        fi
        echo ""

        # CPPC
        echo "=== 硬件 CPPC 支持 ==="
        grep -qi "cppc" /proc/cpuinfo 2>/dev/null && echo "yes" || echo "no"
        echo ""

        # /proc/interrupts
        echo "=== /proc/interrupts ==="
        head -20 /proc/interrupts 2>/dev/null
        echo ""

        # /proc/stat
        echo "=== /proc/stat 解析 ==="
        awk '/cpu[0-9]+/ {
            cpu=$1; gsub(/cpu/,"",cpu);
            printf "cpu%-3d user=%-10s nice=%-10s system=%-10s idle=%-10s iowait=%-10s irq=%-8s softirq=%-8s steal=%-8s\n",cpu,$2,$3,$4,$5,$6,$7,$8,$9
        }
        /^cpu / {
            printf "cpu_total user=%-10s nice=%-10s system=%-10s idle=%-10s iowait=%-10s irq=%-8s softirq=%-8s steal=%-8s\n",$2,$3,$4,$5,$6,$7,$8,$9
        }' /proc/stat
        echo ""

        # Multi-sample /proc/stat
        echo "=== /proc/stat 多采样观测 (${DURATION}秒) ==="
        NUM_SAMPLES=$(( DURATION / INTERVAL + 1 ))
        [ "$NUM_SAMPLES" -lt 2 ] && NUM_SAMPLES=2
        for ((i=1; i<=NUM_SAMPLES; i++)); do
            TS_EPOCH=$(date +%s.%N)
            {
                echo "=== SAMPLE $i ==="
                echo "=== TIMESTAMP $TS_EPOCH ==="
                echo "=== HOST_STAT ==="
                grep '^cpu ' /proc/stat
                echo "=== END_HOST_STAT ==="
                echo ""
            }
            if [ "$i" -lt "$NUM_SAMPLES" ]; then
                sleep "$INTERVAL"
            fi
        done
        echo "总轮次: $NUM_SAMPLES"
        echo ""

        echo "============================================================"
        echo "CPU 深度信息采集完成"
        echo "============================================================"
    } >> "$CPU_DETAIL_FILE"

    log_success "√ CPU 深度信息采集完成"
}

# =============================================================================
# 内核配置与诊断信息采集
# =============================================================================

collect_kernel_config_info() {
    log_info "执行：内核深度诊断信息采集"

    {
        echo "============================================================"
        echo "内核深度诊断信息采集"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        # Full sysctl
        echo "=== 全量内核参数 (sysctl -a) ==="
        sysctl -a 2>/dev/null | sort
        echo ""

        # Key network params
        echo "=== 关键内核参数补充 ==="
        echo "--- 网络核心参数 ---"
        sysctl -a 2>/dev/null | grep -E "^net\.core\.|^net\.ipv4\.tcp_|^net\.ipv4\.udp_|^net\.ipv4\.ip_|^net\.nf" || echo "无匹配"
        echo ""
        echo "--- 网络缓冲区 ---"
        sysctl -a 2>/dev/null | grep -E "^net\.core\.(r|w)mem|^net\.core\.netdev|^net\.core\.somaxconn|^net\.core\.optmem" || echo "无匹配"
        echo ""
        echo "--- 用户命名空间限制 ---"
        sysctl -a 2>/dev/null | grep "^user\.max_" || echo "无匹配"
        echo ""

        # Boot params
        echo "=== 内核启动参数特殊项 ==="
        if [ -f /proc/cmdline ]; then
            grep -qo 'xcall' /proc/cmdline 2>/dev/null && echo "xcall: yes" || echo "xcall: no"
            grep -qo 'sched_steal_node_limit' /proc/cmdline 2>/dev/null && echo "sched_steal_node_limit: yes" || echo "sched_steal_node_limit: no"
        fi
        echo ""

        # Scheduler features
        echo "=== 调度特性 ==="
        SCHED_FEAT=""
        [ -f /sys/kernel/debug/sched_features ] && SCHED_FEAT="/sys/kernel/debug/sched_features"
        [ -f /sys/kernel/debug/sched/features ] && SCHED_FEAT="/sys/kernel/debug/sched/features"
        if [ -n "$SCHED_FEAT" ]; then
            cat "$SCHED_FEAT" 2>/dev/null || echo "无法读取"
            [ -w "$SCHED_FEAT" ] && echo "writable" || echo "not writable"
            grep -ow 'SOFT_DOMAIN' "$SCHED_FEAT" >/dev/null 2>&1 && echo "SOFT_DOMAIN: present" || echo "SOFT_DOMAIN: NOT present"
            grep -ow 'KEEP_ON_CORE' "$SCHED_FEAT" >/dev/null 2>&1 && echo "KEEP_ON_CORE: present" || echo "KEEP_ON_CORE: NOT present"
            grep -ow 'PARAL' "$SCHED_FEAT" >/dev/null 2>&1 && echo "PARAL: present" || echo "PARAL: NOT present"
        else
            echo "调度特性文件不可用"
        fi
        echo ""

        # Special sched params
        echo "=== 特殊调度参数 ==="
        cat /proc/sys/kernel/sched_cluster 2>/dev/null || echo "sched_cluster: not exist"
        cat /proc/sys/kernel/sched_util_ratio 2>/dev/null || echo "sched_util_ratio: not exist"
        cat /proc/sys/kernel/sched_util_low_pct 2>/dev/null || echo "sched_util_low_pct: not exist"
        if [ -f /proc/sys/kernel/sched_soft_runtime_ratio ]; then
            echo "Docker CPU Burst: yes, value=$(cat /proc/sys/kernel/sched_soft_runtime_ratio)"
        else
            echo "Docker CPU Burst: no"
        fi
        echo "--- sched_max_steal_count ---"
        sysctl kernel.sched_max_steal_count 2>&1
        echo ""

        # lsmod
        echo "=== 完整内核模块列表 (lsmod) ==="
        lsmod 2>/dev/null
        echo ""

        # Kernel version & config
        echo "=== 内核版本与编译选项 ==="
        uname -a
        cat /proc/version 2>/dev/null
        KERNEL_VER=$(uname -r)
        if [ -f "/boot/config-${KERNEL_VER}" ]; then
            grep -E "CONFIG_IKCONFIG|CONFIG_HZ|CONFIG_PREEMPT|CONFIG_NR_CPUS|CONFIG_HUGETLB|CONFIG_TRANSPARENT|CONFIG_CGROUP|CONFIG_NAMESPACE|CONFIG_SCHED_STEAL|CONFIG_SCHED_SMT|CONFIG_HISOCK" \
                "/boot/config-${KERNEL_VER}" 2>/dev/null
        elif [ -f /proc/config.gz ]; then
            zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_IKCONFIG|CONFIG_HZ|CONFIG_PREEMPT|CONFIG_NR_CPUS|CONFIG_HUGETLB|CONFIG_TRANSPARENT|CONFIG_CGROUP|CONFIG_SCHED_STEAL|CONFIG_SCHED_SMT|CONFIG_HISOCK"
        else
            echo "未找到内核 config 文件"
        fi
        echo ""

        # System diagnostics
        echo "=== 系统诊断 ==="
        echo "--- 内核 taint ---"
        cat /proc/sys/kernel/tainted 2>/dev/null || echo "无法读取"
        echo "(0=未污染)"
        echo ""

        echo "--- 内核 Oops/Panic (dmesg) ---"
        dmesg 2>/dev/null | grep -i -E "Oops|panic|BUG|Call Trace|WARNING" | tail -20
        echo ""

        echo "--- 活跃内核线程 (前20) ---"
        ps -eo pid,comm --no-headers 2>/dev/null | awk '$2 ~ /^\[.*\]$/ {print}' | head -20
        echo ""

        echo "--- 透明大页 defrag ---"
        cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || echo "不可用"
        echo "THP enabled writable: $(test -w /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null && echo writable || echo 'not writable')"
        echo ""

        # Kernel features & modules
        echo "=== 内核特性与模块诊断 ==="
        echo "--- /proc/1/xcall ---"
        test -f /proc/1/xcall && echo "exists"

        echo "--- irqbalance ---"
        _irq_status="unknown"
        _irq_svc="irqbalance"
        if systemctl list-unit-files irqbalance.service 2>/dev/null | grep -q 'irqbalance\.service'; then
            _irq_status=$(systemctl is-active irqbalance 2>/dev/null || echo "inactive")
        elif systemctl list-unit-files irqbalance-ng.service 2>/dev/null | grep -q 'irqbalance-ng\.service'; then
            _irq_status=$(systemctl is-active irqbalance-ng 2>/dev/null || echo "inactive")
            _irq_svc="irqbalance-ng"
        fi
        echo "$_irq_status"
        echo "--- irqbalance-service ---"
        echo "$_irq_svc"

        echo "--- oenetcls ---"
        modinfo oenetcls 2>/dev/null && echo "available"

        echo "--- SMC ---"
        if lsmod 2>/dev/null | grep -qi smc; then
            echo "loaded"
            lsmod 2>/dev/null | grep -i smc
        else
            echo "not loaded"
        fi

        echo "--- ism ---"
        lsmod 2>/dev/null | grep -qi ism && echo "loaded" && lsmod 2>/dev/null | grep -i ism || echo "not loaded"

        echo "--- cpufreq_seep / oenetcls in /proc/modules ---"
        grep -E 'oenetcls|cpufreq_seep' /proc/modules 2>/dev/null || echo "(无匹配)"

        echo "--- xcall_numa 参数 ---"
        ls /proc/sys/kernel/xcall_numa* 2>/dev/null || echo "xcall_numa* not exist"

        echo "--- debugfs 挂载 ---"
        mount 2>/dev/null | grep debugfs || echo "debugfs not mounted"

        echo "--- numafast ---"
        rpm -qa 2>/dev/null | grep numafast || echo "not installed"

        echo "--- ARM SPE ---"
        perf list 2>/dev/null | grep -qi arm_spe && echo "available" || echo "not available"
        echo ""

        # Other diagnostics
        echo "=== 其他系统诊断 ==="
        echo "--- /proc/filesystems ---"
        cat /proc/filesystems 2>/dev/null
        echo ""

        echo "--- SECCOMP 进程 (strict) ---"
        grep -l "Seccomp:.*2" /proc/[0-9]*/status 2>/dev/null | head -5 | while read f; do
            pid=$(echo "$f" | grep -oP '/\K\d+')
            comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "?")
            echo "PID=$pid COMM=$comm SECCOMP=strict"
        done
        echo ""

        echo "--- 文件描述符使用 Top5 ---"
        for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' | head -200); do
            if [ -d "/proc/$pid/fd" ]; then
                comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "?")
                count=$(ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l)
                echo "$pid $comm $count"
            fi
        done 2>/dev/null | sort -t' ' -k3 -rn | head -5
        echo ""

        echo "--- 关键系统服务 PID ---"
        for svc in systemd sshd dmsetup auditd dbus udevd chronyd crond; do
            pids=$(pgrep -x "$svc" 2>/dev/null || echo "")
            [ -n "$pids" ] && echo "$svc: PID=$pids"
        done
        echo ""

        echo "============================================================"
        echo "内核深度诊断信息采集完成"
        echo "============================================================"
    } >> "$KERNEL_CONFIG_FILE"

    log_success "√ 内核深度诊断信息采集完成"
}

# =============================================================================
# PMU 远程访问与 HHA 分析（仅 aarch64）
# =============================================================================

collect_pmu_info() {
    [[ "${ARCH_TARGET}" != "aarch64" ]] && { log_info "非 aarch64 架构，跳过 PMU 分析"; return; }

    log_info "执行：PMU 远程访问与 HHA 分析"

    {
        echo "============================================================"
        echo "PMU 远程访问与 HHA 分析"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        # HHA devices
        echo "=== 1. HHA 设备检测 ==="
        HHA_DEVICES=$(ls -d /sys/devices/hha* 2>/dev/null || true)
        if [ -n "$HHA_DEVICES" ]; then
            echo "$HHA_DEVICES"
        else
            echo "未检测到 HHA 设备"
        fi
        echo ""

        # PMU event list
        echo "=== 2. PMU 事件列表 (rx_ops/rx_outer/rx_sccl/uncore) ==="
        if command -v perf &>/dev/null; then
            set +o pipefail
            perf list 2>/dev/null | grep -iE -m 50 'hha|rx_ops|rx_outer|rx_sccl|uncore' || true
            set -o pipefail
        fi
        echo ""

        # perf stat remote access
        echo "=== 3. perf stat 远程访问统计 (${DURATION}秒) ==="
        if command -v perf &>/dev/null; then
            RX_OPS_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_ops' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')
            RX_OUTER_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_outer' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')
            RX_SCCL_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_sccl' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')

            if [ -n "$RX_OPS_EVENT" ] && [ -n "$RX_OUTER_EVENT" ] && [ -n "$RX_SCCL_EVENT" ]; then
                perf stat -e "$RX_OPS_EVENT" -e "$RX_OUTER_EVENT" -e "$RX_SCCL_EVENT" -a sleep "$DURATION" 2>&1
            else
                echo "未找到完整的 PMU 事件 (rx_ops/rx_outer/rx_sccl)"
            fi
        fi
        echo ""

        # Rate calculation
        echo "=== 4. 速率与远程访问占比 ==="
        if command -v perf &>/dev/null && [ -n "${RX_OPS_EVENT:-}" ]; then
            OPS_TOTAL=$(grep -E "$RX_OPS_EVENT" "$PMU_INFO_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")
            OUTER_TOTAL=$(grep -E "$RX_OUTER_EVENT" "$PMU_INFO_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")
            SCCL_TOTAL=$(grep -E "$RX_SCCL_EVENT" "$PMU_INFO_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")

            awk -v o="${OPS_TOTAL:-0}" -v x="${OUTER_TOTAL:-0}" -v s="${SCCL_TOTAL:-0}" -v d="$DURATION" \
                'BEGIN {
                    if (d <= 0) d = 10
                    rps = o / d
                    pct = (o > 0) ? (x + s) / o * 100 : 0
                    printf "ops_per_sec=%.0f remote_ratio=%.2f%%\n", rps, pct
                }'
        else
            echo "无法计算"
        fi
        echo ""

        # perf list preview
        echo "=== 5. perf list 输出开头 ==="
        if command -v perf &>/dev/null; then
            set +o pipefail
            perf list 2>/dev/null | head -20 || true
            set -o pipefail
        fi
        echo ""

        echo "============================================================"
        echo "PMU 远程访问分析完成"
        echo "============================================================"
    } >> "$PMU_INFO_FILE"

    log_success "√ PMU 远程访问分析完成"
}

# =============================================================================
# 进程/线程详细信息采集
# =============================================================================

collect_process_detail_info() {
    log_info "执行：进程/线程详细信息采集"

    {
        echo "============================================================"
        echo "进程/线程详细信息采集"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        echo "--- 系统整体进程/线程数 ---"
        echo "进程总数: $(ps -e --no-headers 2>/dev/null | wc -l)"
        echo "线程总数: $(ps -eLf --no-headers 2>/dev/null | wc -l)"
        echo ""

        echo "=== 进程状态分布 ==="
        ps -eo stat --no-headers 2>/dev/null | sed 's/\(.\).*/\1/' | sort | uniq -c | sort -rn
        echo ""

        if command -v pidstat &>/dev/null; then
            echo "=== pidstat CPU 采样 (${DURATION}秒) ==="
            pidstat -u 1 "$DURATION" 2>/dev/null || echo "pidstat -u 失败"
            echo ""

            echo "=== pidstat 内存快照 (1秒) ==="
            pidstat -r 1 1 2>/dev/null || echo "pidstat -r 失败"
            echo ""

            echo "=== pidstat I/O 快照 (1秒) ==="
            pidstat -d 1 1 2>/dev/null || echo "pidstat -d 失败"
            echo ""

            echo "=== 线程级 CPU 统计 (pidstat -t -u 1 3) ==="
            pidstat -t -u 1 3 2>/dev/null || echo "线程级 pidstat 不支持"
            echo ""
        fi

        echo "=== 线程最多的进程 (Top 10) ==="
        ps -eo pid,comm,nlwp --sort=-nlwp 2>/dev/null | head -11
        echo ""

        echo "=== Top CPU 进程线程详情 ==="
        TOP_PIDS=$(ps -eo pid --sort=-%cpu --no-headers 2>/dev/null | head -5 | tr '\n' ' ')
        for pid in $TOP_PIDS; do
            if [ -d "/proc/$pid/task" ]; then
                comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "?")
                thread_count=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
                echo "PID=$pid ($comm): $thread_count 线程"
                echo "TID 列表 (前20):"
                ls "/proc/$pid/task/" 2>/dev/null | head -20
                echo ""
            fi
        done

        echo "=== /proc/schedstat (前20行) ==="
        head -20 /proc/schedstat 2>/dev/null || echo "不可用"
        echo ""

        echo "=== 系统 PID/线程限制 ==="
        cat /proc/sys/kernel/pid_max 2>/dev/null | awk '{print "pid_max: " $1}' || echo "pid_max: 不可用"
        cat /proc/sys/kernel/threads-max 2>/dev/null | awk '{print "threads-max: " $1}' || echo "threads-max: 不可用"
        echo ""

        echo "=== 关键进程检查 ==="
        pgrep -a redis-server 2>/dev/null || echo "redis-server 未运行"
        echo ""
    } >> "$PROCESS_DETAIL_INFO_FILE"

    # Thread poll (simplified)
    log_info "执行：线程生命周期轮询 (${DURATION}s)"
    local tmpd="${OUTPUT_DIR}/.thread_poll_tmp"
    mkdir -p "$tmpd"
    local event_log="$tmpd/events.log"
    > "$event_log"

    collect_snapshot() {
        local ts="$1"
        local snap="$tmpd/thread_ts_${ts}.txt"
        echo "=== TIMESTAMP $ts ===" > "$snap"
        for pid_dir in /proc/[0-9]*/task; do
            [ -d "$pid_dir" ] || continue
            for tid_dir in "$pid_dir"/*; do
                [ -d "$tid_dir" ] || continue
                local tid=$(basename "$tid_dir")
                local comm=$(cat "$tid_dir/comm" 2>/dev/null || echo "?")
                local mtime=$(stat -c "%Y" "$tid_dir" 2>/dev/null || echo "0")
                echo "TID=$tid COMM=$comm MTIME=$mtime" >> "$snap"
            done
        done
        echo "$snap"
    }

    local round=0
    local start_ts=$(date +%s)
    local current_tids=""

    while [ $(( $(date +%s) - start_ts )) -lt "$DURATION" ]; do
        round=$((round + 1))
        local current_ts=$(date +%s)
        local snap_file=$(collect_snapshot "$current_ts")
        local thread_count=$(grep -c '^TID=' "$snap_file" 2>/dev/null || echo 0)

        current_tids="$tmpd/current_tids.txt"
        awk -F'[= ]' '/^TID=/{print $2" "$6}' "$snap_file" > "$current_tids"

        if [ "$round" -gt 1 ]; then
            local prev_tids="$tmpd/prev_tids.txt"
            while read -r prev_tid prev_mtime; do
                local new_mtime=$(awk -v tid="$prev_tid" '$1 == tid {print $2}' "$current_tids")
                [ -z "$new_mtime" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] THREAD_EXIT TID=$prev_tid" >> "$event_log"
            done < "$prev_tids"
            while read -r cur_tid cur_mtime; do
                local old_mtime=$(awk -v tid="$cur_tid" '$1 == tid {print $2}' "$prev_tids")
                [ -z "$old_mtime" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] THREAD_CREATE TID=$cur_tid" >> "$event_log"
            done < "$current_tids"
        fi

        cp "$current_tids" "$tmpd/prev_tids.txt"

        if [ $(( $(date +%s) - start_ts )) -lt "$DURATION" ]; then
            sleep "$INTERVAL"
        fi
    done

    {
        echo "=== 轮询统计 ==="
        echo "采样轮次: $round"
        echo "线程创建事件: $(grep -c "THREAD_CREATE" "$event_log" 2>/dev/null || echo 0) 次"
        echo "线程销毁事件: $(grep -c "THREAD_EXIT" "$event_log" 2>/dev/null || echo 0) 次"
        echo ""
        echo "--- 线程创建事件 (前50条) ---"
        grep "THREAD_CREATE" "$event_log" 2>/dev/null | head -50
        echo ""
        echo "--- 线程销毁事件 (前50条) ---"
        grep "THREAD_EXIT" "$event_log" 2>/dev/null | head -50
        echo ""
        echo "--- 当前线程总数 ---"
        if [ -f "$current_tids" ]; then
            wc -l < "$current_tids"
        else
            echo "无法获取"
        fi
    } >> "$PROCESS_DETAIL_INFO_FILE"

    rm -rf "$tmpd"
    log_success "√ 进程/线程详细信息采集完成"
}

# =============================================================================
# 容器资源监控采集
# =============================================================================

collect_container_info() {
    log_info "执行：容器资源监控采集"

    {
        echo "============================================================"
        echo "容器资源监控采集"
        echo "采集时间: $(date)"
        echo "============================================================"
        echo ""

        # ---- cgroup detection ----
        detect_cgroup_version() {
            if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then echo "v2"
            elif [ -f "/sys/fs/cgroup/unified/cgroup.controllers" ]; then echo "v2_unified_mount"
            else echo "v1"; fi
        }
        get_cgroup_root() {
            if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then echo "/sys/fs/cgroup"
            elif [ -f "/sys/fs/cgroup/unified/cgroup.controllers" ]; then echo "/sys/fs/cgroup/unified"
            else echo ""; fi
        }
        CGROUP_VER=$(detect_cgroup_version)
        CGROUP_V2_ROOT=$(get_cgroup_root)
        echo "Cgroup 版本: $CGROUP_VER"
        [ -n "$CGROUP_V2_ROOT" ] && echo "Cgroup v2 根: $CGROUP_V2_ROOT"
        echo ""

        # ---- container ID extraction ----
        extract_container_id() {
            local basename="$1"
            local name="${basename%.scope}"
            case "$name" in
                docker-*) name="${name#docker-}" ;;
                containerd-*) name="${name#containerd-}" ;;
                cri-containerd-*) name="${name#cri-containerd-}" ;;
                libpod-*) name="${name#libpod-}" ;;
            esac
            [ -n "$name" ] && echo "$name" || echo "$basename"
        }

        # ---- cgroup path lookup ----
        get_cgroup_path() {
            local subsys="$1" cid="$2"
            if [ -n "$CGROUP_V2_ROOT" ]; then
                for scope_dir in "${CGROUP_V2_ROOT}/system.slice/${cid}" "${CGROUP_V2_ROOT}/kubepods.slice"/*/"${cid}"; do
                    [ -d "$scope_dir" ] && { echo "$scope_dir"; return 0; }
                done
                while IFS= read -r d; do
                    [ -d "$d" ] && [ "$(basename "$d")" = "$cid" ] && { echo "$d"; return 0; }
                done < <(find "${CGROUP_V2_ROOT}/kubepods.slice" -type d -name "$cid" 2>/dev/null)
                return 0
            fi
            local base="/sys/fs/cgroup/${subsys}"
            [ -d "$base" ] || return 0
            for path in "${base}/docker/${cid}" "${base}/system.slice/${cid}" "${base}/kubepods/${cid}" "${base}/kubepods.slice/${cid}"; do
                [ -d "$path" ] && { echo "$path"; return 0; }
            done
            return 0
        }

        # ---- container discovery ----
        echo "=== 容器发现 ==="
        CONTAINER_IDS=()
        discover_containers() {
            local cids=()
            if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                local base="$CGROUP_V2_ROOT"
                for scope in "$base"/system.slice/docker-*.scope "$base"/system.slice/containerd-*.scope "$base"/system.slice/libpod-*.scope; do
                    [ -d "$scope" ] || continue
                    cids+=("$(basename "$scope")")
                done
                while IFS= read -r d; do
                    [ -d "$d" ] || continue
                    cids+=("$(basename "$d")")
                done < <(find "$base/kubepods.slice" -name "*.scope" -type d 2>/dev/null)
            else
                for subsys in cpu blkio memory; do
                    local base="/sys/fs/cgroup/$subsys"
                    [ -d "$base" ] || continue
                    if [ -d "$base/docker" ]; then
                        for d in "$base/docker"/*/; do
                            [ -d "$d" ] || continue
                            cids+=("$(basename "$d")")
                        done
                    fi
                    for scope in "$base"/system.slice/docker-*.scope "$base"/system.slice/containerd-*.scope "$base"/system.slice/libpod-*.scope; do
                        [ -d "$scope" ] || continue
                        cids+=("$(basename "$scope")")
                    done
                done
            fi
            printf '%s\n' "${cids[@]}" | sort -u
        }

        while IFS= read -r cid; do
            [ -n "$cid" ] && CONTAINER_IDS+=("$cid")
        done < <(discover_containers)

        if [ ${#CONTAINER_IDS[@]} -gt 0 ]; then
            echo "发现 ${#CONTAINER_IDS[@]} 个容器"
            printf '%s\n' "${CONTAINER_IDS[@]}"
        else
            echo "未发现运行中的容器"
        fi
        echo ""

        # Host /proc/stat reference
        echo "## 宿主机 /proc/stat (cpu 行)"
        grep '^cpu ' /proc/stat
        echo ""

        # ---- per-container details ----
        for CID in "${CONTAINER_IDS[@]}"; do
            echo "===== 容器: $CID ====="
            PURE_ID=$(extract_container_id "$CID")
            [ "$PURE_ID" != "$CID" ] && echo "（纯容器 ID: $PURE_ID）"

            CGROUP_CPU_PATH=$(get_cgroup_path cpu "$CID")
            CGROUP_MEM_PATH=$(get_cgroup_path memory "$CID")
            CGROUP_BLKIO_PATH=$(get_cgroup_path blkio "$CID")
            CGROUP_CPUSET_PATH=$(get_cgroup_path cpuset "$CID")
            CGROUP_CPUACCT_PATH=$(get_cgroup_path cpuacct "$CID")

            # CPU limit
            if [ -n "$CGROUP_CPU_PATH" ]; then
                echo "## CPU 限额"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    if [ -f "$CGROUP_CPU_PATH/cpu.max" ]; then
                        read max period < "$CGROUP_CPU_PATH/cpu.max"
                        echo "  cpu.max = $max $period"
                        if [ "$max" != "max" ] && [ "$period" -gt 0 ] 2>/dev/null; then
                            cpus=$(awk -v m="$max" -v p="$period" 'BEGIN { printf "%.2f", m/p }')
                            echo "  可用 CPU 数: $cpus"
                        else
                            echo "  可用 CPU 数: 无限制"
                        fi
                    fi
                    [ -f "$CGROUP_CPU_PATH/cpu.weight" ] && echo "  cpu.weight = $(cat "$CGROUP_CPU_PATH/cpu.weight")"
                else
                    for f in cpu.cfs_period_us cpu.cfs_quota_us cpu.cfs_burst_us cpu.shares cpu.stat; do
                        [ -f "$CGROUP_CPU_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPU_PATH/$f")"
                    done
                    if [ -f "$CGROUP_CPU_PATH/cpu.cfs_period_us" ] && [ -f "$CGROUP_CPU_PATH/cpu.cfs_quota_us" ]; then
                        period=$(cat "$CGROUP_CPU_PATH/cpu.cfs_period_us")
                        quota=$(cat "$CGROUP_CPU_PATH/cpu.cfs_quota_us")
                        if [ "$quota" -gt 0 ] 2>/dev/null; then
                            cpus=$(awk -v q="$quota" -v p="$period" 'BEGIN { if (p>0) printf "%.2f", q/p; else print "无限制" }')
                            echo "  可用 CPU 数: $cpus"
                        else
                            echo "  可用 CPU 数: 无限制 (quota=-1)"
                        fi
                    fi
                fi
            fi
            echo ""

            # CPU usage
            if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                if [ -n "$CGROUP_CPU_PATH" ] && [ -f "$CGROUP_CPU_PATH/cpu.stat" ]; then
                    echo "## CPU 累计使用 (cpu.stat)"
                    cat "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null
                fi
            else
                if [ -n "$CGROUP_CPUACCT_PATH" ] && [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage" ]; then
                    echo "## CPU 累计使用 (cpuacct)"
                    USAGE_NS=$(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage" 2>/dev/null || echo 0)
                    USAGE_S=$(awk -v ns="$USAGE_NS" 'BEGIN { printf "%.3f", ns/1000000000 }')
                    echo "  cpuacct.usage = $USAGE_NS ns ($USAGE_S s)"
                    [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage_percpu" ] && echo "  usage_percpu (ns): $(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage_percpu")"
                fi
            fi
            echo ""

            # NUMA/CPU affinity
            if [ -n "$CGROUP_CPUSET_PATH" ]; then
                echo "## NUMA/CPU 亲和性"
                for f in cpuset.cpus cpuset.mems cpuset.cpus.effective cpuset.mems.effective; do
                    [ -f "$CGROUP_CPUSET_PATH/$f" ] && echo "  $f = $(cat "$CGROUP_CPUSET_PATH/$f")"
                done
            fi
            echo ""

            # Memory
            if [ -n "$CGROUP_MEM_PATH" ]; then
                echo "## 内存配置与使用"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    [ -f "$CGROUP_MEM_PATH/memory.max" ] && echo "  memory.max = $(cat "$CGROUP_MEM_PATH/memory.max")"
                    if [ -f "$CGROUP_MEM_PATH/memory.current" ]; then
                        echo "  memory.current = $(cat "$CGROUP_MEM_PATH/memory.current")"
                    fi
                    [ -f "$CGROUP_MEM_PATH/memory.stat" ] && { echo "  memory.stat (前5行):"; head -5 "$CGROUP_MEM_PATH/memory.stat"; }
                else
                    for f in memory.limit_in_bytes memory.usage_in_bytes memory.stat; do
                        [ -f "$CGROUP_MEM_PATH/$f" ] && echo "  $f = $(head -5 "$CGROUP_MEM_PATH/$f")"
                    done
                fi
            fi
            echo ""

            # blkio
            if [ -n "$CGROUP_BLKIO_PATH" ]; then
                echo "## blkio 限速"
                if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                    [ -f "$CGROUP_BLKIO_PATH/io.max" ] && echo "  io.max = $(cat "$CGROUP_BLKIO_PATH/io.max")"
                else
                    for f in blkio.throttle.read_bps_device blkio.throttle.write_bps_device blkio.throttle.read_iops_device blkio.throttle.write_iops_device; do
                        [ -f "$CGROUP_BLKIO_PATH/$f" ] && echo "  $f = $(head -5 "$CGROUP_BLKIO_PATH/$f")"
                    done
                fi
            fi
            echo ""

            # Tasks
            if [ -n "$CGROUP_CPU_PATH" ]; then
                tasks_file=""
                [ -f "$CGROUP_CPU_PATH/cgroup.threads" ] && tasks_file="$CGROUP_CPU_PATH/cgroup.threads"
                [ -z "$tasks_file" ] && [ -f "$CGROUP_CPU_PATH/tasks" ] && tasks_file="$CGROUP_CPU_PATH/tasks"
                if [ -n "$tasks_file" ]; then
                    TASK_COUNT=$(wc -l < "$tasks_file" 2>/dev/null || echo 0)
                    echo "## 任务列表"
                    echo "  线程总数: $TASK_COUNT"
                    echo "  前20个TID映射:"
                    head -20 "$tasks_file" 2>/dev/null | while read tid; do
                        comm=$(cat "/proc/$tid/comm" 2>/dev/null || echo "?")
                        tpid=$(awk '/^Tgid:/{print $2}' "/proc/$tid/status" 2>/dev/null || echo "?")
                        echo "    TID=$tid COMM=$comm PID=$tpid"
                    done || true
                fi
            fi
            echo ""
        done

        # ---- Docker metadata ----
        if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
            echo "## Docker Daemon 信息"
            docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Cgroup Driver|Cgroup Version|Total Memory|Operating System" || true
            echo ""
            for CID in "${CONTAINER_IDS[@]}"; do
                PURE_ID=$(extract_container_id "$CID")
                echo "## 容器元数据 (ID: $PURE_ID)"
                if docker inspect "$PURE_ID" >/dev/null 2>&1; then
                    docker inspect "$PURE_ID" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)[0]
name = data.get('Name', '?').lstrip('/')
s = data.get('State', {})
print(f'Name: {name}')
print(f'Image: {data.get(\"Config\", {}).get(\"Image\", \"?\")}')
print(f'Status: {s.get(\"Status\", \"?\")}')
hc = data.get('HostConfig', {})
print(f'CpuQuota: {hc.get(\"CpuQuota\", \"N/A\")}')
print(f'CpuPeriod: {hc.get(\"CpuPeriod\", \"N/A\")}')
print(f'CpuShares: {hc.get(\"CpuShares\", \"N/A\")}')
print(f'NanoCpus: {hc.get(\"NanoCpus\", \"N/A\")}')
print(f'CpusetCpus: {hc.get(\"CpusetCpus\", \"N/A\")}')
print(f'Memory: {hc.get(\"Memory\", \"N/A\")}')
" 2>/dev/null || {
                        echo "python 解析失败，回退原始输出"
                        docker inspect "$PURE_ID" 2>/dev/null || true
                    }
                fi
                echo ""
            done
        fi

        # ---- Multi-sample CPU observation ----
        if [ ${#CONTAINER_IDS[@]} -gt 0 ]; then
            OBS_WINDOW=${DURATION:-10}
            SAMP_INT=${INTERVAL:-2}
            NUM_SAMPLES=$(( OBS_WINDOW / SAMP_INT + 1 ))
            [ "$NUM_SAMPLES" -lt 2 ] && NUM_SAMPLES=2

            echo "## 容器 CPU 多采样观测 (${OBS_WINDOW}s, ${SAMP_INT}s 间隔)"
            for ((i=1; i<=NUM_SAMPLES; i++)); do
                TS_EPOCH=$(date +%s.%N)
                echo "=== SAMPLE $i ==="
                echo "=== TIMESTAMP $TS_EPOCH ==="
                for CID in "${CONTAINER_IDS[@]}"; do
                    CGROUP_CPU_PATH=$(get_cgroup_path cpu "$CID")
                    USAGE_NS="0"; PERIOD_US="0"; QUOTA_US="0"; SOFT_QUOTA=0
                    if [ "$CGROUP_VER" = "v2" ] || [ "$CGROUP_VER" = "v2_unified_mount" ]; then
                        if [ -n "$CGROUP_CPU_PATH" ]; then
                            if [ -f "$CGROUP_CPU_PATH/cpu.max" ]; then
                                read max period < "$CGROUP_CPU_PATH/cpu.max" 2>/dev/null || true
                                PERIOD_US="$period"; QUOTA_US="$max"
                                if [ "$max" != "max" ] && [ "$period" -gt 0 ] 2>/dev/null; then
                                    [ -f "$CGROUP_CPU_PATH/cpu.max.burst" ] && {
                                        BURST_US=$(cat "$CGROUP_CPU_PATH/cpu.max.burst" 2>/dev/null || echo 0)
                                        [ -n "$BURST_US" ] && [ "$BURST_US" -gt 0 ] 2>/dev/null && SOFT_QUOTA=1
                                    }
                                fi
                            fi
                            if [ -f "$CGROUP_CPU_PATH/cpu.stat" ]; then
                                usec=$(awk '/^usage_usec /{print $2}' "$CGROUP_CPU_PATH/cpu.stat" 2>/dev/null || echo 0)
                                [ -n "$usec" ] && USAGE_NS=$(( usec * 1000 ))
                            fi
                        fi
                    else
                        CGROUP_CPUACCT_PATH=$(get_cgroup_path cpuacct "$CID")
                        if [ -n "$CGROUP_CPU_PATH" ]; then
                            [ -f "$CGROUP_CPU_PATH/cpu.cfs_period_us" ] && PERIOD_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_period_us")
                            [ -f "$CGROUP_CPU_PATH/cpu.cfs_quota_us" ] && QUOTA_US=$(cat "$CGROUP_CPU_PATH/cpu.cfs_quota_us")
                            [ -f "$CGROUP_CPU_PATH/cpu.soft_quota" ] && SOFT_QUOTA=$(cat "$CGROUP_CPU_PATH/cpu.soft_quota")
                        fi
                        if [ -n "$CGROUP_CPUACCT_PATH" ] && [ -f "$CGROUP_CPUACCT_PATH/cpuacct.usage" ]; then
                            USAGE_NS=$(cat "$CGROUP_CPUACCT_PATH/cpuacct.usage" 2>/dev/null || echo 0)
                        fi
                    fi
                    echo "--- CONTAINER ---"
                    echo "id=$CID"
                    echo "cfs_period_us=${PERIOD_US:-0}"
                    echo "cfs_quota_us=${QUOTA_US:-0}"
                    echo "cpuacct_usage=${USAGE_NS:-0}"
                    echo "soft_quota=$SOFT_QUOTA"
                    echo "timestamp=$TS_EPOCH"
                    echo "--- END CONTAINER ---"
                done
                echo ""
                if [ "$i" -lt "$NUM_SAMPLES" ]; then
                    sleep "$SAMP_INT"
                fi
            done
        fi
    } >> "$CONTAINER_FILE"

    log_success "√ 容器资源监控采集完成"
}

# =============================================================================
# 并行分组执行辅助函数
# =============================================================================

# 每隔 30 秒输出一条进度提示，用于执行时间较长的阶段。
# 需以后台方式启动（&），并在阶段结束时 kill 对应 PID。
# 参数: $1=阶段名称, $2=阶段开始时间(epoch 秒)
progress_ticker() {
    local phase_name="$1"
    local start_ts="$2"
    while true; do
        sleep 30
        local elapsed=$(( $(date +%s) - start_ts ))
        log_info "  [进度] ${phase_name} 仍在采集中，已耗时 ${elapsed} 秒 ..."
    done
}

# 从当前选中的采集命令中筛选出属于指定 phase 的命令，并行执行
run_phase_parallel() {
    local phase_name="$1"
    shift
    local -a phase_cmds=("$@")
    local -a to_run=()

    for pc in "${phase_cmds[@]}"; do
        for sc in "${SELECTED_COMMANDS[@]}"; do
            [[ "$pc" == "$sc" ]] && { to_run+=("$pc"); break; }
        done
    done

    if [[ ${#to_run[@]} -eq 0 ]]; then
        return
    fi

    log_info "--- ${phase_name} (组内并行) ---"
    local -a pids=()
    for cmd in "${to_run[@]}"; do
        log_info "  启动: $cmd"
        $cmd &
        pids+=($!)
    done

    # 启动进度提示（每 30 秒输出一次），阶段结束后停止
    local phase_start=$(date +%s)
    progress_ticker "$phase_name" "$phase_start" &
    local ticker_pid=$!

    # 等待所有后台任务完成，收集每个任务的退出状态
    local failed=0
    local i=0
    for cmd in "${to_run[@]}"; do
        wait "${pids[$i]}" 2>/dev/null
        local rc=$?
        if [[ $rc -ne 0 ]]; then
            log_warning "  $cmd 退出码=$rc"
            failed=$((failed + 1))
        fi
        i=$((i + 1))
    done

    # 停止进度提示
    kill "$ticker_pid" 2>/dev/null
    wait "$ticker_pid" 2>/dev/null

    if [[ $failed -gt 0 ]]; then
        log_warning "--- ${phase_name} 完成 (${failed}/${#to_run[@]} 失败) ---"
    else
        log_success "--- ${phase_name} 完成 ---"
    fi
    echo ""
}

# 从当前选中的采集命令中筛选出属于指定 phase 的命令，串行执行
# 用于 perf/strace 等独占硬件资源的工具
run_phase_serial() {
    local phase_name="$1"
    shift
    local -a phase_cmds=("$@")
    local -a to_run=()

    for pc in "${phase_cmds[@]}"; do
        for sc in "${SELECTED_COMMANDS[@]}"; do
            [[ "$pc" == "$sc" ]] && { to_run+=("$pc"); break; }
        done
    done

    if [[ ${#to_run[@]} -eq 0 ]]; then
        return
    fi

    log_info "--- ${phase_name} (独占资源，串行) ---"

    # 启动进度提示（每 30 秒输出一次），阶段结束后停止
    local phase_start=$(date +%s)
    progress_ticker "$phase_name" "$phase_start" &
    local ticker_pid=$!

    for cmd in "${to_run[@]}"; do
        log_info "  执行: $cmd"
        $cmd || log_warning "  $cmd 退出码=$?"
    done

    # 停止进度提示
    kill "$ticker_pid" 2>/dev/null
    wait "$ticker_pid" 2>/dev/null

    log_success "--- ${phase_name} 完成 ---"
    echo ""
}

# =============================================================================
# 主流程
# =============================================================================

main() {
    parse_arguments "$@"

    if [[ "$CHECK_ONLY" = true ]]; then
        log_info "========================================"
        log_info "前置检查模式"
        log_info "========================================"
        echo ""
        check_root
        check_commands
        echo ""
        log_info "========================================"
        log_info "前置检查完成"
        log_info "========================================"
        log_success "✓ 基础依赖已检查，可以开始数据采集"
        echo ""
        log_info "使用以下命令开始数据采集:"
        echo "  $0 -d <持续时间> [-p <进程ID>]"
        echo ""
        echo "示例:"
        echo "  $0 -d 10                  # 默认采集10秒"
        echo "  $0 -d 60 -p 1234          # 采集60秒，监控进程1234"
        exit 0
    fi

    log_info "========================================"
    log_info "瓶颈分析数据采集开始"
    log_info "========================================"
    log_info "采集持续时间: ${DURATION}秒"
    log_info "采样间隔: ${INTERVAL}秒"
    log_info "输出目录: ${OUTPUT_DIR}"
    [[ -n "$PIDS" ]] && log_info "监控进程: $PIDS"
    log_info "采集项目: ${SELECTED_COMMANDS[*]}"
    echo ""

    check_root
    create_header
    check_commands

    # ---- 分阶段并行执行 ----
    # Phase 1: 快速静态采集 (组内并行, ~5s)
    run_phase_parallel "Phase 1/4: 快速静态采集" "${PHASE1_CMDS[@]}"

    # Phase 2: 系统级采样 (组内并行, 持续 ${DURATION}s)
    run_phase_parallel "Phase 2/4: 系统级采样 (${DURATION}s)" "${PHASE2_CMDS[@]}"

    # Phase 3: 进程/容器深度采集 (组内并行, 持续 ${DURATION}s)
    run_phase_parallel "Phase 3/4: 进程容器深度采集 (${DURATION}s)" "${PHASE3_CMDS[@]}"

    # Phase 4: 独占工具采集 (组内串行 — perf PMU/strace ptrace 互斥)
    run_phase_serial "Phase 4/4: 独占工具采集" "${PHASE4_CMDS[@]}"

    # 总结
    echo ""
    log_info "========================================"
    log_info "采集总结"
    log_info "========================================"
    echo "数据采集完成时间: $(date)"
    echo "采集持续时间: ${DURATION}秒"
    [[ -n "$PIDS" ]] && echo "监控进程: $PIDS"
    echo ""

    echo "生成的文件:"
    local num=0
    for var in STATIC_FILE BOTTLENECK_FILE TOP_PROC_FILE HOTSPOT_ANALYSIS_FILE \
               SYSCALL_FILE IO_METRICS_FILE MEM_METRICS_FILE NET_METRICS_FILE \
               CPU_DETAIL_FILE KERNEL_CONFIG_FILE PMU_INFO_FILE \
               PROCESS_DETAIL_INFO_FILE CONTAINER_FILE; do
        local f="${!var}"
        if [ -f "$f" ]; then
            num=$((num + 1))
            local sz=$(du -h "$f" 2>/dev/null | cut -f1)
            echo "  $num. $f ($sz)"
        fi
    done
    echo ""

    log_success "瓶颈分析数据采集完成！"
}

# 执行主函数
main "$@"