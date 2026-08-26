#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数解析
# ====================================================================
usage() {
    echo "Usage: $0 [<batch_dir>]"
    echo "  <batch_dir>  批次根目录，默认 ${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/<timestamp>"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "未知选项: $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

# ====================================================================
# 目录与日志准备
# ====================================================================
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/pmu-collection_report.txt"

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/pmu-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] pmu-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] pmu-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始
# ====================================================================
# PMU 采集时长（秒），与 server_data_collector.sh 的 DURATION 对齐
DURATION="${DURATION:-10}"

{
    echo "============================================================"
    echo "PMU 远程访问与 HHA 分析"
    echo "采集时间: $(date)"
    echo "============================================================"
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 1. HHA 设备检测
# --------------------------------------------------------------------
echo "=== 1. HHA 设备检测 ===" | tee -a "$REPORT_FILE"
HHA_DEVICES=$(ls -d /sys/devices/hha* 2>/dev/null || true)
if [ -n "$HHA_DEVICES" ]; then
    echo "$HHA_DEVICES" | tee -a "$REPORT_FILE"
else
    echo "未检测到 HHA 设备" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 2. PMU 事件列表（rx_ops/rx_outer/rx_sccl/uncore）
# --------------------------------------------------------------------
echo "=== 2. PMU 事件列表 (rx_ops/rx_outer/rx_sccl/uncore) ===" | tee -a "$REPORT_FILE"
if command -v perf &>/dev/null; then
    # 使用 grep -m 50 代替 head -50，避免因 head 提前关闭管道导致 SIGPIPE
    perf list 2>/dev/null | grep -iE -m 50 'hha|rx_ops|rx_outer|rx_sccl|uncore' | tee -a "$REPORT_FILE" || true
else
    echo "perf 命令不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 3. perf stat 远程访问统计（使用 DURATION 时长）
# --------------------------------------------------------------------
echo "=== 3. perf stat 远程访问统计 (${DURATION}秒) ===" | tee -a "$REPORT_FILE"

if command -v perf &>/dev/null; then
    # 提取事件名称
    RX_OPS_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_ops' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')
    RX_OUTER_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_outer' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')
    RX_SCCL_EVENT=$(perf list 2>/dev/null | grep -iE 'rx_sccl' | head -1 | awk -F'[' '{print $1}' | awk '{print $1}')

    if [ -n "$RX_OPS_EVENT" ] && [ -n "$RX_OUTER_EVENT" ] && [ -n "$RX_SCCL_EVENT" ]; then
        perf stat -e "$RX_OPS_EVENT" -e "$RX_OUTER_EVENT" -e "$RX_SCCL_EVENT" -a sleep "$DURATION" 2>&1 | tee -a "$REPORT_FILE"
    else
        echo "未找到完整的 PMU 事件 (rx_ops/rx_outer/rx_sccl)" | tee -a "$REPORT_FILE"
    fi
else
    echo "perf 命令不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 4. 换算每秒速率与远程访问占比
# --------------------------------------------------------------------
echo "=== 4. 速率与远程访问占比 ===" | tee -a "$REPORT_FILE"

if [ -f "$REPORT_FILE" ] && command -v perf &>/dev/null && [ -n "${RX_OPS_EVENT:-}" ]; then
    OPS_TOTAL=$(grep -E "$RX_OPS_EVENT" "$REPORT_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")
    OUTER_TOTAL=$(grep -E "$RX_OUTER_EVENT" "$REPORT_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")
    SCCL_TOTAL=$(grep -E "$RX_SCCL_EVENT" "$REPORT_FILE" 2>/dev/null | grep -oE '[0-9,]+' | head -1 | tr -d ',' || echo "0")

    awk -v o="${OPS_TOTAL:-0}" -v x="${OUTER_TOTAL:-0}" -v s="${SCCL_TOTAL:-0}" -v d="$DURATION" \
        'BEGIN {
            if (d <= 0) d = 10
            rps = o / d
            pct = (o > 0) ? (x + s) / o * 100 : 0
            printf "ops_per_sec=%.0f remote_ratio=%.2f%%\n", rps, pct
        }' | tee -a "$REPORT_FILE"
else
    echo "无法计算" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 5. perf list 输出开头（快速预览）
# --------------------------------------------------------------------
echo "=== 5. perf list 输出开头 ===" | tee -a "$REPORT_FILE"
if command -v perf &>/dev/null; then
    # 临时关闭 pipefail，避免 head 提前退出导致 SIGPIPE (141)
    set +o pipefail
    perf list 2>/dev/null | head -20 | tee -a "$REPORT_FILE"
    set -o pipefail
else
    echo "perf 命令不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成
# ====================================================================
echo "[OK] pmu-collection: 采集完成，报告 $REPORT_FILE" >&3