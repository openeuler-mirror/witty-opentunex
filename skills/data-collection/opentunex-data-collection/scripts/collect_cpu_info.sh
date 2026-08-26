#!/bin/bash
set -euo pipefail

OBSERVATION_WINDOW=10
SAMPLE_INTERVAL=2

usage() {
    echo "Usage: $0 [--no-multi] [-w <observation_window_sec>] [-i <sample_interval_sec>] [<batch_dir>]"
    echo "  --no-multi  跳过末尾的多采样 /proc/stat 观测窗口"
    echo "  -w  多采样观测窗口总时长（秒），默认 10"
    echo "  -i  多采样间隔（秒），默认 2"
    echo "  <batch_dir>  批次根目录，默认 ${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/<timestamp>"
    exit 1
}

SKIP_MULTI=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-multi) SKIP_MULTI=1; shift ;;
        -w) OBSERVATION_WINDOW="$2"; shift 2 ;;
        -i) SAMPLE_INTERVAL="$2"; shift 2 ;;
        -h) usage ;;
        --) shift; break ;;
        -*) echo "未知选项: $1"; usage ;;
        *) break ;;
    esac
done

DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/cpu-collection_report.txt"

if ! [[ "$OBSERVATION_WINDOW" =~ ^[0-9]+$ ]] || [ "$OBSERVATION_WINDOW" -lt 2 ]; then
    echo "错误: 观测窗口至少 2 秒"
    exit 1
fi
if ! [[ "$SAMPLE_INTERVAL" =~ ^[0-9]+$ ]] || [ "$SAMPLE_INTERVAL" -lt 1 ]; then
    echo "错误: 采样间隔至少 1 秒"
    exit 1
fi

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/cpu-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1
trap 'echo "[FAIL] cpu-collection line $LINENO exit $?" >&3' ERR

echo "[BUSY] cpu-collection 开始采集 → $BATCH_DIR" >&3

# --- 开始采集 ---
{
    echo "============================================================"
    echo "CPU 深度信息采集"
    echo "采集时间: $(date)"
    echo "============================================================"
    echo ""
} | tee -a "$REPORT_FILE"

# 1. CPU 架构与型号（独立脚本扩展）
echo "=== CPU 架构与型号 ===" | tee -a "$REPORT_FILE"
if command -v lscpu &>/dev/null; then
    lscpu | tee -a "$REPORT_FILE"
else
    echo "警告: lscpu 不可用" | tee -a "$REPORT_FILE"
    grep -m1 "model name" /proc/cpuinfo 2>/dev/null | tee -a "$REPORT_FILE" || echo "无法获取CPU型号信息" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 2. 在线 CPU 核心列表
echo "=== 在线 CPU 核心列表 ===" | tee -a "$REPORT_FILE"
if [ -f /sys/devices/system/cpu/online ]; then
    echo "CPU 在线列表: $(cat /sys/devices/system/cpu/online)" | tee -a "$REPORT_FILE"
    COUNT=$(tr ',' '\n' < /sys/devices/system/cpu/online | while read -r r; do
        if [[ "$r" == *-* ]]; then
            seq "${r%-*}" "${r#*-}" || true
        else
            echo "$r"
        fi
    done | wc -l)
    echo "在线CPU数量: $COUNT" | tee -a "$REPORT_FILE"
else
    echo "警告: /sys/devices/system/cpu/online 不存在" | tee -a "$REPORT_FILE"
    echo "在线CPU数量: $(nproc)" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 3. /proc/cpuinfo
echo "=== /proc/cpuinfo ===" | tee -a "$REPORT_FILE"
cat /proc/cpuinfo | tee -a "$REPORT_FILE" || true
echo "" | tee -a "$REPORT_FILE"

# 4. NUMA 节点 sysfs 详情
echo "=== NUMA 节点 sysfs 详情 ===" | tee -a "$REPORT_FILE"
if [ -d /sys/devices/system/node ]; then
    NODE_COUNT=$(ls -d /sys/devices/system/node/node* 2>/dev/null | wc -l)
    echo "NUMA 节点数量: $NODE_COUNT" | tee -a "$REPORT_FILE"
    for node in /sys/devices/system/node/node*; do
        if [ -d "$node" ]; then
            node_name=$(basename "$node")
            echo "--- $node_name ---" | tee -a "$REPORT_FILE"
            [ -f "$node/cpulist" ] && echo "CPU列表: $(cat "$node/cpulist")" | tee -a "$REPORT_FILE"
            [ -f "$node/distance" ] && echo "距离: $(cat "$node/distance")" | tee -a "$REPORT_FILE"
        fi
    done
    echo "" | tee -a "$REPORT_FILE"
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        cpu_name=$(basename "$cpu_dir")
        if [ -f "$cpu_dir/topology/physical_package_id" ]; then
            socket_id=$(cat "$cpu_dir/topology/physical_package_id" 2>/dev/null || echo '?')
            echo "$cpu_name socket=$socket_id" | tee -a "$REPORT_FILE"
        fi
    done
    ONLINE_COUNT=$(nproc 2>/dev/null || echo "1")
    if [ "$NODE_COUNT" -gt 0 ] 2>/dev/null; then
        echo "单NUMA节点CPU数(估计): $(( ONLINE_COUNT / NODE_COUNT ))" | tee -a "$REPORT_FILE"
    fi
else
    echo "警告: /sys/devices/system/node 不存在" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 独立脚本扩展：numactl --hardware
if command -v numactl &>/dev/null; then
    echo "--- numactl --hardware ---" | tee -a "$REPORT_FILE"
    numactl --hardware 2>&1 | tee -a "$REPORT_FILE" || true
    echo "" | tee -a "$REPORT_FILE"
else
    echo "注意: numactl 未安装" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 5. 各核心利用率 (mpstat)（独立脚本扩展）
MPSTAT_DURATION=5
MPSTAT_INTERVAL=1
echo "[BUSY] cpu-collection: mpstat ${MPSTAT_DURATION}s..." >&3
echo "=== 各核心利用率 (mpstat) ===" | tee -a "$REPORT_FILE"
if command -v mpstat &>/dev/null; then
    mpstat -P ALL $MPSTAT_INTERVAL $MPSTAT_DURATION | tee -a "$REPORT_FILE" || true
else
    echo "警告: mpstat 不可用 (请安装 sysstat)" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 6. /proc/stat 解析
echo "=== /proc/stat 解析 ===" | tee -a "$REPORT_FILE"
awk '/cpu[0-9]+/ {
    cpu=$1; gsub(/cpu/,"",cpu);
    printf "cpu%-3d user=%-10s nice=%-10s system=%-10s idle=%-10s iowait=%-10s irq=%-8s softirq=%-8s steal=%-8s\n",cpu,$2,$3,$4,$5,$6,$7,$8,$9
}
/^cpu / {
    printf "cpu_total user=%-10s nice=%-10s system=%-10s idle=%-10s iowait=%-10s irq=%-8s softirq=%-8s steal=%-8s\n",$2,$3,$4,$5,$6,$7,$8,$9
}' /proc/stat | tee -a "$REPORT_FILE" || true
echo "" | tee -a "$REPORT_FILE"

# 7. SMT 超线程状态
echo "=== SMT 超线程状态 ===" | tee -a "$REPORT_FILE"
if [ -f /sys/devices/system/cpu/smt/active ]; then
    echo "SMT active: $(cat /sys/devices/system/cpu/smt/active)" | tee -a "$REPORT_FILE"
else
    echo "SMT active: unknown" | tee -a "$REPORT_FILE"
fi
for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
    cpu_name=$(basename "$cpu_dir")
    if [ -f "$cpu_dir/topology/thread_siblings_list" ]; then
        siblings=$(cat "$cpu_dir/topology/thread_siblings_list" 2>/dev/null || echo '?')
        echo "$cpu_name siblings=$siblings" | tee -a "$REPORT_FILE"
    fi
done
echo "" | tee -a "$REPORT_FILE"

# 8. CPU 频率信息
echo "=== CPU 频率信息 ===" | tee -a "$REPORT_FILE"
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        if [ -d "$cpu" ]; then
            cpu_name=$(basename "$(dirname "$cpu")")
            echo "$cpu_name:" | tee -a "$REPORT_FILE"
            cat "$cpu/scaling_cur_freq" 2>/dev/null | awk '{printf "  当前频率: %s kHz\n", $1}' | tee -a "$REPORT_FILE" || true
            cat "$cpu/scaling_max_freq" 2>/dev/null | awk '{printf "  最大频率: %s kHz\n", $1}' | tee -a "$REPORT_FILE" || true
            cat "$cpu/cpuinfo_max_freq" 2>/dev/null | awk '{printf "  硬件最大频率: %s kHz\n", $1}' | tee -a "$REPORT_FILE" || true
            cat "$cpu/scaling_min_freq" 2>/dev/null | awk '{printf "  最小频率: %s kHz\n", $1}' | tee -a "$REPORT_FILE" || true
            cat "$cpu/scaling_governor" 2>/dev/null | awk '{printf "  调频策略: %s\n", $1}' | tee -a "$REPORT_FILE" || true
        fi
    done
else
    echo "注意: cpufreq 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 独立脚本扩展：CPU 标称频率
echo "--- CPU 标称频率 ---" | tee -a "$REPORT_FILE"
lscpu 2>/dev/null | grep -i "MHz" | tee -a "$REPORT_FILE" || \
    grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -5 | tee -a "$REPORT_FILE" || true
echo "" | tee -a "$REPORT_FILE"

# 独立脚本扩展：cpufreq_seep 模块
echo "--- cpufreq_seep 模块 ---" | tee -a "$REPORT_FILE"
if modinfo cpufreq_seep 2>/dev/null; then
    echo "available" | tee -a "$REPORT_FILE"
else
    echo "not found" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 9. 硬件 CPPC 支持
echo "=== 硬件 CPPC 支持 ===" | tee -a "$REPORT_FILE"
if grep -qi "cppc" /proc/cpuinfo 2>/dev/null; then
    echo "yes" | tee -a "$REPORT_FILE"
else
    echo "no" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 10. /proc/interrupts
echo "=== /proc/interrupts ===" | tee -a "$REPORT_FILE"
head -20 /proc/interrupts | tee -a "$REPORT_FILE" || true
echo "" | tee -a "$REPORT_FILE"

# 独立脚本扩展：软中断分布
echo "=== /proc/softirqs ===" | tee -a "$REPORT_FILE"
cat /proc/softirqs | tee -a "$REPORT_FILE" || true
echo "" | tee -a "$REPORT_FILE"

# 11. /proc/stat 多采样观测
if [ "$SKIP_MULTI" -eq 0 ]; then
    NUM_SAMPLES=$(( OBSERVATION_WINDOW / SAMPLE_INTERVAL + 1 ))
    [ "$NUM_SAMPLES" -lt 2 ] && NUM_SAMPLES=2

    echo "[BUSY] cpu-collection: 多采样 ${OBSERVATION_WINDOW}s..." >&3
    echo "=== /proc/stat 多采样观测 (${OBSERVATION_WINDOW}秒) ===" | tee -a "$REPORT_FILE"

    for ((i=1; i<=NUM_SAMPLES; i++)); do
        TS_EPOCH=$(date +%s.%N)
        {
            echo "=== SAMPLE $i ==="
            echo "=== TIMESTAMP $TS_EPOCH ==="
            echo "=== HOST_STAT ==="
            grep '^cpu ' /proc/stat
            echo "=== END_HOST_STAT ==="
            echo ""
        } | tee -a "$REPORT_FILE"

        if [ "$i" -lt "$NUM_SAMPLES" ]; then
            sleep "$SAMPLE_INTERVAL"
        fi
    done
    echo "总轮次: $NUM_SAMPLES" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# 完成
echo "[OK] cpu-collection: 采集完成，报告 $REPORT_FILE" >&3