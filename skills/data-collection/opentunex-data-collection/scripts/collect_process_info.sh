#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数与路径初始化
# ====================================================================
# 用法:
#   collect_process_info.sh [batch_dir] [duration]
#   环境变量: WORK_DIR / DURATION
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/process-collection_report.txt"
DURATION="${2:-${DURATION:-5}}"
INTERVAL=1

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/process-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] process-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] process-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "进程/线程详细信息采集"
    echo "采集时间: $(date)"
    echo "============================================================"
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 系统整体进程/线程数
# --------------------------------------------------------------------
echo "--- 系统整体进程/线程数 ---" | tee -a "$REPORT_FILE"
echo "进程总数: $(ps -e --no-headers 2>/dev/null | wc -l)" | tee -a "$REPORT_FILE"
echo "线程总数: $(ps -eLf --no-headers 2>/dev/null | wc -l)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 进程状态分布
# --------------------------------------------------------------------
echo "=== 进程状态分布 ===" | tee -a "$REPORT_FILE"
ps -eo stat --no-headers 2>/dev/null | sed 's/\(.\).*/\1/' | sort | uniq -c | sort -rn | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# pidstat 系列采集（若可用）
# --------------------------------------------------------------------
if command -v pidstat &>/dev/null; then
    echo "[BUSY] process-collection: pidstat ${DURATION}s..." >&3

    # pidstat CPU 采样
    echo "=== pidstat CPU 采样 (${DURATION}秒) ===" | tee -a "$REPORT_FILE"
    pidstat -u "$INTERVAL" "$DURATION" 2>/dev/null | tee -a "$REPORT_FILE" || echo "pidstat -u 失败" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    # pidstat 内存快照
    echo "=== pidstat 内存快照 (1秒) ===" | tee -a "$REPORT_FILE"
    pidstat -r 1 1 2>/dev/null | tee -a "$REPORT_FILE" || echo "pidstat -r 失败" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    # pidstat I/O 快照
    echo "=== pidstat I/O 快照 (1秒) ===" | tee -a "$REPORT_FILE"
    pidstat -d 1 1 2>/dev/null | tee -a "$REPORT_FILE" || echo "pidstat -d 失败" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    # 线程级 CPU 统计
    echo "=== 线程级 CPU 统计 (pidstat -t -u 1 3) ===" | tee -a "$REPORT_FILE"
    pidstat -t -u 1 3 2>/dev/null | tee -a "$REPORT_FILE" || echo "线程级 pidstat 不支持" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
else
    echo "警告: pidstat 不可用 (请安装 sysstat)" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# --------------------------------------------------------------------
# 线程最多的进程 (Top 10)
# --------------------------------------------------------------------
echo "=== 线程最多的进程 (Top 10) ===" | tee -a "$REPORT_FILE"
ps -eo pid,comm,nlwp --sort=-nlwp 2>/dev/null | head -11 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Top CPU 进程线程详情
# --------------------------------------------------------------------
echo "=== Top CPU 进程线程详情 ===" | tee -a "$REPORT_FILE"
TOP_PIDS=$(ps -eo pid --sort=-%cpu --no-headers 2>/dev/null | head -5 | tr '\n' ' ')
for pid in $TOP_PIDS; do
    if [ -d "/proc/$pid/task" ]; then
        comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "?")
        thread_count=$(ls "/proc/$pid/task" 2>/dev/null | wc -l)
        echo "PID=$pid ($comm): $thread_count 线程" | tee -a "$REPORT_FILE"
        echo "TID 列表 (前20):" | tee -a "$REPORT_FILE"
        ls "/proc/$pid/task/" 2>/dev/null | head -20 | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
done

# --------------------------------------------------------------------
# /proc/schedstat
# --------------------------------------------------------------------
echo "=== /proc/schedstat (前20行) ===" | tee -a "$REPORT_FILE"
head -20 /proc/schedstat 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 系统 PID/线程限制
# --------------------------------------------------------------------
echo "=== 系统 PID/线程限制 ===" | tee -a "$REPORT_FILE"
cat /proc/sys/kernel/pid_max 2>/dev/null | awk '{print "pid_max: " $1}' | tee -a "$REPORT_FILE" || echo "pid_max: 不可用" | tee -a "$REPORT_FILE"
cat /proc/sys/kernel/threads-max 2>/dev/null | awk '{print "threads-max: " $1}' | tee -a "$REPORT_FILE" || echo "threads-max: 不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 关键进程检查
# --------------------------------------------------------------------
echo "=== 关键进程检查 ===" | tee -a "$REPORT_FILE"
pgrep -a redis-server 2>/dev/null | tee -a "$REPORT_FILE" || echo "redis-server 未运行" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 系统负载（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 系统负载 (/proc/loadavg) ===" | tee -a "$REPORT_FILE"
cat /proc/loadavg 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Top CPU 进程快照（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== Top CPU 进程快照 ===" | tee -a "$REPORT_FILE"
ps -eo pid,comm,%cpu,%mem,rss,vsz --sort=-%cpu 2>/dev/null | head -16 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 上下文切换统计（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 上下文切换统计 (pidstat -w 1 1) ===" | tee -a "$REPORT_FILE"
if command -v pidstat &>/dev/null; then
    pidstat -w 1 1 2>/dev/null | tee -a "$REPORT_FILE" || echo "上下文切换统计不支持" | tee -a "$REPORT_FILE"
else
    echo "pidstat 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Process Detail Info Collection Complete"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] process-collection: 采集完成，报告 $REPORT_FILE" >&3
