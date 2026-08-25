#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数与路径初始化
# ====================================================================
# 用法:
#   collect_process_thread_poll.sh [batch_dir] [duration] [interval]
#   环境变量: WORK_DIR / DURATION / INTERVAL
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
DURATION="${2:-${DURATION:-30}}"
INTERVAL="${3:-${INTERVAL:-2}}"
REPORT_FILE="${BATCH_DIR}/process-thread-poll_report.txt"

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/process-thread-poll_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] process-thread-poll line $LINENO exit $?" >&3' ERR

echo "[BUSY] process-thread-poll 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "线程生命周期轮询采集"
    echo "采集时长: ${DURATION}s, 采样间隔: ${INTERVAL}s"
    echo "============================================================"
    echo ""
} | tee -a "$REPORT_FILE"

# 临时目录与事件日志
TMPD="${BATCH_DIR}/.thread_poll_tmp"
mkdir -p "$TMPD"
EVENT_LOG="$TMPD/events.log"
> "$EVENT_LOG"

# ====================================================================
# 函数：采集当前所有线程快照
# ====================================================================
collect_snapshot() {
    local ts="$1"
    local snap="$TMPD/thread_ts_${ts}.txt"

    echo "=== TIMESTAMP $ts ===" > "$snap"

    for pid_dir in /proc/[0-9]*/task; do
        [ -d "$pid_dir" ] || continue
        for tid_dir in "$pid_dir"/*; do
            [ -d "$tid_dir" ] || continue
            tid=$(basename "$tid_dir")
            comm=$(cat "$tid_dir/comm" 2>/dev/null || echo "?")
            mtime=$(stat -c "%Y" "$tid_dir" 2>/dev/null || echo "0")
            echo "TID=$tid COMM=$comm MTIME=$mtime" >> "$snap"
        done
    done

    echo "$snap"
}

# 函数：从快照中提取 TID 和 mtime
parse_tid_mtime() {
    awk -F'[= ]' '/^TID=/{print $2" "$6}' "$1"
}

# ====================================================================
# 主轮询循环
# ====================================================================
ROUND=0
START_TS=$(date +%s)

echo "[BUSY] process-thread-poll: 轮询 ${DURATION}s (间隔 ${INTERVAL}s)..." >&3

while [ $(( $(date +%s) - START_TS )) -lt "$DURATION" ]; do
    ROUND=$((ROUND + 1))
    CURRENT_TS=$(date +%s)

    # 采集当前快照
    SNAP=$(collect_snapshot "$CURRENT_TS")
    thread_count=$(grep -c '^TID=' "$SNAP" 2>/dev/null || echo 0)
    echo "[BUSY] process-thread-poll: 第 $ROUND 轮 ($CURRENT_TS) — $thread_count 线程" >&3

    CURRENT_TIDS="$TMPD/current_tids.txt"
    parse_tid_mtime "$SNAP" > "$CURRENT_TIDS"

    # 非首轮时进行差异比较
    if [ "$ROUND" -gt 1 ]; then
        PREV_TIDS="$TMPD/prev_tids.txt"

        # 检测退出的线程
        while read -r prev_tid prev_mtime; do
            new_mtime=$(awk -v tid="$prev_tid" '$1 == tid {print $2}' "$CURRENT_TIDS")
            [ -z "$new_mtime" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] THREAD_EXIT TID=$prev_tid" >> "$EVENT_LOG"
        done < "$PREV_TIDS"

        # 检测新建的线程
        while read -r cur_tid cur_mtime; do
            old_mtime=$(awk -v tid="$cur_tid" '$1 == tid {print $2}' "$PREV_TIDS")
            [ -z "$old_mtime" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] THREAD_CREATE TID=$cur_tid" >> "$EVENT_LOG"
        done < "$CURRENT_TIDS"
    fi

    # 保存当前快照为下一轮的"前一次"
    cp "$CURRENT_TIDS" "$TMPD/prev_tids.txt"

    # 若未超时则等待
    if [ $(( $(date +%s) - START_TS )) -lt "$DURATION" ]; then
        sleep "$INTERVAL"
    fi
done

# ====================================================================
# 汇总统计（与 server_data_collector.sh 一致）
# ====================================================================
TOTAL_CREATES=$(grep -c "THREAD_CREATE" "$EVENT_LOG" 2>/dev/null || echo "0")
TOTAL_EXITS=$(grep -c "THREAD_EXIT" "$EVENT_LOG" 2>/dev/null || echo "0")

{
    echo "=== 轮询统计 ==="
    echo "采样轮次: $ROUND"
    echo "线程创建事件: $TOTAL_CREATES 次"
    echo "线程销毁事件: $TOTAL_EXITS 次"
    echo ""
    echo "--- 线程创建事件 (前50条) ---"
    grep "THREAD_CREATE" "$EVENT_LOG" 2>/dev/null | head -50
    echo ""
    echo "--- 线程销毁事件 (前50条) ---"
    grep "THREAD_EXIT" "$EVENT_LOG" 2>/dev/null | head -50
    echo ""
    echo "--- 当前线程总数 ---"
    if [ -f "$CURRENT_TIDS" ]; then
        wc -l < "$CURRENT_TIDS"
    else
        echo "无法获取"
    fi
} | tee -a "$REPORT_FILE"

# 清理临时文件
rm -rf "$TMPD"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Thread Lifecycle Poll Collection Complete"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] process-thread-poll: 采集完成，报告 $REPORT_FILE" >&3
