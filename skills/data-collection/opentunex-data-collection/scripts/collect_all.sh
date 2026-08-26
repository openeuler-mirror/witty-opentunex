#!/bin/bash
set -euo pipefail

# ====================================================================
# 数据采集编排脚本 — 支持单项或全量采集
# ====================================================================
# 用法:
#   collect_all.sh [batch_dir] [items] [duration] [interval]
#
# 参数:
#   batch_dir  批次目录 (默认 ${WORK_DIR}/collect/)
#   items      采集项，all (默认) 或逗号分隔列表:
#              cpu mem io net process system kernel container pmu
#              process-thread-poll (可选, 进程线程轮询)
#   duration   采集时长 (默认 10)
#   interval   采集间隔 (默认 1)
#
# 环境变量:
#   WORK_DIR / DURATION / INTERVAL / ITEMS
#
# 输出:
#   各采集脚本直接写入 ${batch_dir}/<item>-collection_report.txt
#   本脚本不读取或改写采集内容，仅负责调度。
# ====================================================================

# 定位采集脚本目录 (本脚本与其他采集脚本同位于 opentunex-data-collection/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
ITEMS="${2:-${ITEMS:-all}}"
DURATION="${3:-${DURATION:-10}}"
INTERVAL="${4:-${INTERVAL:-1}}"

mkdir -p "$BATCH_DIR"

# --------------------------------------------------------------------
# 采集项 -> 脚本路径 映射
# --------------------------------------------------------------------
declare -A SCRIPT_MAP=(
    ["cpu"]="$SCRIPT_DIR/collect_cpu_info.sh"
    ["mem"]="$SCRIPT_DIR/collect_mem_info.sh"
    ["io"]="$SCRIPT_DIR/collect_io_info.sh"
    ["net"]="$SCRIPT_DIR/collect_net_info.sh"
    ["process"]="$SCRIPT_DIR/collect_process_info.sh"
    ["process-thread-poll"]="$SCRIPT_DIR/collect_process_thread_poll.sh"
    ["system"]="$SCRIPT_DIR/collect_system_sar.sh"
    ["kernel"]="$SCRIPT_DIR/collect_kernel_config.sh"
    ["container"]="$SCRIPT_DIR/collect_container_info.sh"
    ["pmu"]="$SCRIPT_DIR/collect_pmu_info.sh"
)

# 采集项 -> 报告文件名 映射
declare -A REPORT_MAP=(
    ["cpu"]="cpu-collection_report.txt"
    ["mem"]="mem-collection_report.txt"
    ["io"]="io-collection_report.txt"
    ["net"]="net-collection_report.txt"
    ["process"]="process-collection_report.txt"
    ["process-thread-poll"]="process-thread-poll_report.txt"
    ["system"]="system-collection_report.txt"
    ["kernel"]="kernel-collection_report.txt"
    ["container"]="container-collection_report.txt"
    ["pmu"]="pmu-collection_report.txt"
)

# 并行组定义 (避免过多监控工具同时运行影响测量精度)
#   1: cpu mem io      (并行)
#   2: net process     (并行)
#   3: system          (并行)
#   serial: kernel container
#   independent: pmu process-thread-poll
declare -A PARALLEL_GROUP=(
    ["cpu"]="1"
    ["mem"]="1"
    ["io"]="1"
    ["net"]="2"
    ["process"]="2"
    ["system"]="3"
    ["kernel"]="serial"
    ["container"]="serial"
    ["pmu"]="independent"
    ["process-thread-poll"]="independent"
)

# 全量采集默认项 (不含可选的 process-thread-poll)
ALL_ITEMS=(cpu mem io net process system kernel container pmu)

# --------------------------------------------------------------------
# 解析采集项列表
# --------------------------------------------------------------------
if [ "$ITEMS" = "all" ]; then
    SELECTED=("${ALL_ITEMS[@]}")
else
    IFS=',' read -ra SELECTED <<< "$ITEMS"
fi

VALID_ITEMS=()
for item in "${SELECTED[@]}"; do
    item="$(echo "$item" | tr -d '[:space:]')"
    if [ -z "${SCRIPT_MAP[$item]:-}" ]; then
        echo "[WARN] 未知采集项: $item (跳过)" >&2
        continue
    fi
    if [ ! -f "${SCRIPT_MAP[$item]}" ]; then
        echo "[WARN] 脚本不存在: ${SCRIPT_MAP[$item]} (跳过)" >&2
        continue
    fi
    VALID_ITEMS+=("$item")
done

if [ ${#VALID_ITEMS[@]} -eq 0 ]; then
    echo "[FAIL] 没有有效的采集项" >&2
    exit 1
fi

echo "[BUSY] 数据采集开始 → $BATCH_DIR" >&2
echo "[BUSY] 采集项: ${VALID_ITEMS[*]}" >&2
echo "[BUSY] 时长: ${DURATION}s, 间隔: ${INTERVAL}s" >&2

# --------------------------------------------------------------------
# 执行单个采集脚本
# --------------------------------------------------------------------
run_script() {
    local item="$1"
    local script="${SCRIPT_MAP[$item]}"
    echo "[BUSY] $item: 开始采集..." >&2
    if bash "$script" "$BATCH_DIR" "$DURATION" "$INTERVAL"; then
        echo "[OK] $item: 采集完成" >&2
    else
        echo "[FAIL] $item: 采集失败 (继续其他项)" >&2
    fi
}

# 按并行组执行 (组内并行, 组间串行)
for group_id in 1 2 3; do
    pids=()
    has_items=false
    for item in "${VALID_ITEMS[@]}"; do
        if [ "${PARALLEL_GROUP[$item]}" = "$group_id" ]; then
            run_script "$item" &
            pids+=($!)
            has_items=true
        fi
    done
    if [ "$has_items" = "true" ]; then
        for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    fi
done

# 串行执行
for item in "${VALID_ITEMS[@]}"; do
    if [ "${PARALLEL_GROUP[$item]}" = "serial" ]; then
        run_script "$item"
    fi
done

# 独立执行
for item in "${VALID_ITEMS[@]}"; do
    if [ "${PARALLEL_GROUP[$item]}" = "independent" ]; then
        run_script "$item"
    fi
done

# --------------------------------------------------------------------
# 汇总
# --------------------------------------------------------------------
echo "" >&2
echo "============================================================" >&2
echo "数据采集完成"
echo "批次目录: $BATCH_DIR" >&2
echo "============================================================" >&2
echo "采集报告:" >&2
for item in "${VALID_ITEMS[@]}"; do
    report="${BATCH_DIR}/${REPORT_MAP[$item]}"
    if [ -f "$report" ]; then
        size=$(wc -c < "$report" 2>/dev/null || echo "?")
        echo "  [OK] ${REPORT_MAP[$item]} (${size} bytes)" >&2
    else
        echo "  [MISS] ${REPORT_MAP[$item]}" >&2
    fi
done
