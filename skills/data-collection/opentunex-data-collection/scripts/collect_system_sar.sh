#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数与路径初始化
# ====================================================================
# 用法:
#   collect_system_sar.sh [batch_dir] [duration] [interval]
#   环境变量: WORK_DIR / DURATION / INTERVAL
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/system-collection_report.txt"
DURATION="${2:-${DURATION:-10}}"
INTERVAL="${3:-${INTERVAL:-1}}"

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/system-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] system-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] system-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "系统详细信息"
    echo "采集时间: $(date)"
    echo "============================================================"
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 系统概况补充
# --------------------------------------------------------------------
echo "=== 系统概况补充 ===" | tee -a "$REPORT_FILE"

echo "--- 启动时间 ---" | tee -a "$REPORT_FILE"
uptime 2>/dev/null | tee -a "$REPORT_FILE" || echo "无法获取" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 虚拟化检测 ---" | tee -a "$REPORT_FILE"
if command -v systemd-detect-virt &>/dev/null; then
    VIRT=$(systemd-detect-virt --vm 2>/dev/null || echo "none")
    if [ "$VIRT" = "none" ]; then
        echo "physical" | tee -a "$REPORT_FILE"
    else
        echo "vm ($VIRT)" | tee -a "$REPORT_FILE"
    fi
else
    if [ -f /sys/class/dmi/id/product_name ]; then
        PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "unknown")
        case "$PRODUCT" in
            *KVM*|*QEMU*|*VMware*|*VirtualBox*|*Xen*)
                echo "vm ($PRODUCT)" | tee -a "$REPORT_FILE"
                ;;
            *)
                echo "physical (product: $PRODUCT)" | tee -a "$REPORT_FILE"
                ;;
        esac
    else
        echo "unknown" | tee -a "$REPORT_FILE"
    fi
fi
echo "" | tee -a "$REPORT_FILE"

echo "--- 当前用户 ---" | tee -a "$REPORT_FILE"
echo "用户: $(whoami), UID: $(id -u), root: $(if [ "$(id -u)" -eq 0 ]; then echo yes; else echo no; fi)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# sar 多维度实时采集
# --------------------------------------------------------------------
echo "=== sar 实时采集 (${DURATION}次, 间隔${INTERVAL}s) ===" | tee -a "$REPORT_FILE"

if command -v sar &>/dev/null; then
    echo "[BUSY] system-collection: sar ${DURATION}次 间隔${INTERVAL}s..." >&3

    TMPD="${BATCH_DIR}/.sar_tmp"
    mkdir -p "$TMPD"
    PIDS=()

    # 定义要采集的 sar 类别（排除已采集的 DEV/EDEV）
    declare -A SAR_MAP=(
        ["cpu"]="-u ${INTERVAL} ${DURATION}"
        ["cpu_all"]="-P ALL ${INTERVAL} ${DURATION}"
        ["memory"]="-r ${INTERVAL} ${DURATION}"
        ["swap"]="-S ${INTERVAL} ${DURATION}"
        ["paging"]="-B ${INTERVAL} ${DURATION}"
        ["io"]="-b ${INTERVAL} ${DURATION}"
        ["sock"]="-n SOCK ${INTERVAL} ${DURATION}"
        ["load"]="-q ${INTERVAL} ${DURATION}"
        ["ctxsw"]="-w ${INTERVAL} ${DURATION}"
        ["task"]="-y ${INTERVAL} ${DURATION}"
        ["hugepages"]="-H ${INTERVAL} ${DURATION}"
        ["intr"]="-I SUM ${INTERVAL} ${DURATION}"
    )

    for name in "${!SAR_MAP[@]}"; do
        (
            sar ${SAR_MAP[$name]} 2>/dev/null > "$TMPD/$name" || true
        ) &
        PIDS+=($!)
    done

    for pid in "${PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    for name in "${!SAR_MAP[@]}"; do
        echo "--- sar ${name} ---" | tee -a "$REPORT_FILE"
        if [ -s "$TMPD/$name" ]; then
            cat "$TMPD/$name" | tee -a "$REPORT_FILE"
        else
            echo "  (无数据)" | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"
    done

    rm -rf "$TMPD"
else
    echo "警告: sar 不可用 (请安装 sysstat)" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# --------------------------------------------------------------------
# sadf 历史数据提取
# --------------------------------------------------------------------
echo "=== sadf 历史数据提取 ===" | tee -a "$REPORT_FILE"
SADF_DAY=$(date '+%d')
SADF_FILE="/var/log/sa/sa${SADF_DAY}"

if command -v sadf &>/dev/null && [ -f "$SADF_FILE" ]; then
    echo "--- CPU 历史 (前3行) ---" | tee -a "$REPORT_FILE"
    sadf -d "$SADF_FILE" -- -u 2>/dev/null | head -3 | tee -a "$REPORT_FILE" || echo "无数据" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "--- 内存历史 (前3行) ---" | tee -a "$REPORT_FILE"
    sadf -d "$SADF_FILE" -- -r 2>/dev/null | head -3 | tee -a "$REPORT_FILE" || echo "无数据" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "--- /var/log/sa 今日文件 ---" | tee -a "$REPORT_FILE"
    find /var/log/sa -name "sa*" -mtime -1 2>/dev/null | tee -a "$REPORT_FILE" || echo "无" | tee -a "$REPORT_FILE"
else
    echo "sadf 不可用或今日数据文件不存在" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# PSI 压力指标补充（cpu, io）
# --------------------------------------------------------------------
echo "=== PSI 压力指标补充 ===" | tee -a "$REPORT_FILE"

echo "--- /proc/pressure/cpu ---" | tee -a "$REPORT_FILE"
cat /proc/pressure/cpu 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- /proc/pressure/io ---" | tee -a "$REPORT_FILE"
cat /proc/pressure/io 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# PSI 内存压力（独立脚本扩展）
# --------------------------------------------------------------------
echo "--- /proc/pressure/memory ---" | tee -a "$REPORT_FILE"
cat /proc/pressure/memory 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 内核版本（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 内核版本 ===" | tee -a "$REPORT_FILE"
uname -r 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "System Detail Info Collection Complete"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] system-collection: 采集完成，报告 $REPORT_FILE" >&3
