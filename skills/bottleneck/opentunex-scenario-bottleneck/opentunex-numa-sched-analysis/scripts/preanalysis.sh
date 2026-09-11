#!/usr/bin/env bash
# preanalysis.sh - 从已有采集数据文件提取 numa-sched-analysis 所需关键字段，生成 preanalysis.json
# 用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]
#   DATA_DIR:   采集批次目录（含 pmu_info.txt 等文件）
#   OUTPUT_DIR: JSON 输出目录，默认 ${DATA_DIR}/opentunex-numa-sched-analysis_collect
# 说明: 本脚本仅解析已有文本文件，不执行任何采集命令

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# ============================================================
# 工具函数
# ============================================================

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}

# ============================================================
# 数据提取函数
# ============================================================

# 从 pmu_info.txt 提取 HHA 数据
extract_pmu_info() {
    local pfile="$1"
    local hha_available=false
    local ops_per_sec=0
    local remote_ratio=0
    local pmu_path_applicable=false

    [[ ! -f "$pfile" ]] && { echo "$hha_available $ops_per_sec $remote_ratio $pmu_path_applicable"; return; }

    # 提取 ops_per_sec（不依赖 /sys/devices/hha* 路径，各平台路径不同）
    local ops_line
    ops_line=$(grep -oE 'ops_per_sec=[0-9]+' "$pfile" 2>/dev/null | head -1 | sed 's/ops_per_sec=//' || true)
    if [[ -n "$ops_line" ]]; then
        ops_per_sec=$ops_line
    fi

    # 提取 remote_ratio
    local ratio_line
    ratio_line=$(grep -oE 'remote_ratio=[0-9.]+' "$pfile" 2>/dev/null | head -1 | sed 's/remote_ratio=//' || true)
    if [[ -n "$ratio_line" ]]; then
        remote_ratio=$ratio_line
    fi

    # HHA 可用判定：以 ops_per_sec > 0 为准（不依赖设备路径字符串）
    if (( ops_per_sec > 0 )); then
        hha_available=true
        pmu_path_applicable=true
    fi

    echo "$hha_available $ops_per_sec $remote_ratio $pmu_path_applicable"
}

# 从 memory_metrics_analysis.txt 提取 vmstat/numastat 数据
extract_vmstat_info() {
    local mfile="$1"
    local numa_hit=0
    local numa_miss=0
    local numa_foreign=0
    local remote_access_ratio=0

    [[ ! -f "$mfile" ]] && { echo "$numa_hit $numa_miss $numa_foreign $remote_access_ratio"; return; }

    # 搜索 NUMA Statistics 节
    # 注意：sed 范围模式 /start/,/end/ 中，结束正则 /^=== / 会匹配节标题自身
    # （=== NUMA Statistics === 以 "=== " 开头），导致只捕获标题行，数据行被丢弃
    # 改用 awk：找到标题行后设标志，遇到下一个节标题时退出，两标题之间即为数据
    local numa_section
    numa_section=$(awk '/^=== NUMA Statistics ===$/{found=1; next} found && /^=== /{exit} found{print}' "$mfile" 2>/dev/null || true)
    # 也尝试 --- NUMA Statistics --- 定界符
    if [[ -z "$numa_section" ]]; then
        numa_section=$(awk '/^--- NUMA Statistics ---$/{found=1; next} found && /^--- /{exit} found{print}' "$mfile" 2>/dev/null || true)
    fi
    # 回退：搜索整个文件中 numastat 相关行
    if [[ -z "$numa_section" ]]; then
        numa_section=$(grep -E 'numa_hit|numa_miss|numa_foreign' "$mfile" 2>/dev/null || true)
    fi

    if [[ -n "$numa_section" ]]; then
        numa_hit=$(echo "$numa_section" | grep -oE 'numa_hit[[:space:]]+[0-9]+' | head -1 | sed 's/numa_hit[[:space:]]*//' || echo "0")
        numa_miss=$(echo "$numa_section" | grep -oE 'numa_miss[[:space:]]+[0-9]+' | head -1 | sed 's/numa_miss[[:space:]]*//' || echo "0")
        numa_foreign=$(echo "$numa_section" | grep -oE 'numa_foreign[[:space:]]+[0-9]+' | head -1 | sed 's/numa_foreign[[:space:]]*//' || echo "0")
    fi

    # 计算 REMOTE_ACCESS_RATIO = NUMA_MISS / (NUMA_HIT + NUMA_MISS) × 100
    local total=$((numa_hit + numa_miss))
    if ((total > 0)); then
        remote_access_ratio=$(awk "BEGIN {printf \"%.2f\", ${numa_miss}/${total}*100}")
    fi

    echo "$numa_hit $numa_miss $numa_foreign $remote_access_ratio"
}

# 从 static_info.txt 提取 NUMA 节点数
extract_numa_nodes() {
    local sfile="$1"
    local nodes=1

    [[ ! -f "$sfile" ]] && { echo "$nodes"; return; }

    # 仅匹配 "node X cpus:" 行，排除 "node X size:" / "node X free:"
    nodes=$(awk '/^--- NUMA Topology ---$/{found=1; next} found && /^--- /{exit} found{print}' "$sfile" | grep -cE '^node [0-9]+ cpus?:' 2>/dev/null || true)
    if ((nodes == 0)); then
        nodes=$(grep -oE 'available:[[:space:]]+[0-9]+' "$sfile" 2>/dev/null | head -1 | sed 's/available:[[:space:]]*//' || true)
        nodes=${nodes:-1}
    fi
    echo "$nodes"
}

# 从 process_detail_info.txt 提取线程创建频率
# 期望数据格式：thread_create_per_second=<整数>（个/秒），由数据采集器
# collect_process_detail_info 在 5 秒窗口内对 /proc/stat 的 processes 字段
# （实际为 fork+clone 累计值）做差分后输出；缺失或采样失败时输出
extract_thread_create_per_second() {
    local pdfile="$1"
    local rate="null"

    if [[ -f "$pdfile" ]]; then
        local val
        val=$(grep -oE 'thread_create_per_second=[0-9]+' "$pdfile" 2>/dev/null | head -1 | sed 's/thread_create_per_second=//' || true)
        [[ -n "$val" ]] && rate="$val"
    fi

    echo "$rate"
}

# 从 kernel_config_info.txt 提取 PARAL 信息
extract_paral_info() {
    local kfile="$1"
    local paral_support="不支持"
    local paral_enabled="未启用"
    local sched_util_low_pct="null"

    [[ ! -f "$kfile" ]] && { echo "$paral_support $paral_enabled $sched_util_low_pct"; return; }

    # 提取调度特性节
    local sched_section
    sched_section=$(awk '/^=== 调度特性 ===$/{found=1; next} found && /^=== /{exit} found{print}' "$kfile" 2>/dev/null || true)

    # PARAL 支持检测
    if echo "$sched_section" | grep -q "PARAL: present" 2>/dev/null; then
        paral_support="支持"
        paral_enabled="已启用"
    elif echo "$sched_section" | grep -q "PARAL" 2>/dev/null; then
        paral_support="支持"
        # 检查是否含 NO_PARAL
        if echo "$sched_section" | grep -q "NO_PARAL" 2>/dev/null; then
            paral_enabled="未启用"
        elif echo "$sched_section" | grep -q "PARAL" 2>/dev/null; then
            # 含 PARAL 但不含 NO_PARAL → 已启用
            paral_enabled="已启用"
        fi
    fi

    # SCHED_UTIL_LOW_PCT 提取
    # 格式：在"特殊调度参数"节中，sched_util_ratio 行后紧跟一行
    local special_section
    special_section=$(awk '/^=== 特殊调度参数 ===$/{found=1; next} found && /^=== /{exit} found{print}' "$kfile" 2>/dev/null || true)
    if [[ -n "$special_section" ]]; then
        # 尝试提取数字
        local pct_val
        pct_val=$(echo "$special_section" | grep -oE 'sched_util_low_pct[=:][[:space:]]*[0-9]+' 2>/dev/null | head -1 | sed 's/sched_util_low_pct[=:][[:space:]]*//' || true)
        if [[ -z "$pct_val" ]]; then
            # 尝试 sched_util_ratio 相邻行
            pct_val=$(echo "$special_section" | grep -A1 'sched_util_ratio' | tail -1 | grep -oE '^[[:space:]]*[0-9]+' | head -1 | sed 's/^[[:space:]]*//' || true)
        fi
        if [[ -n "$pct_val" ]]; then
            sched_util_low_pct="$pct_val"
        fi
    fi

    echo "$paral_support $paral_enabled $sched_util_low_pct"
}

# ============================================================
# 主流程
# ============================================================

main() {
    local DATA_DIR="${1:-}"
    local OUTPUT_DIR="${2:-${DATA_DIR}/opentunex-numa-sched-analysis_collect}"

    [[ -z "$DATA_DIR" ]] && die "用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]"
    [[ -d "$DATA_DIR" ]] || die "DATA_DIR 不存在: $DATA_DIR"

    mkdir -p "$OUTPUT_DIR"
    local JSON_FILE="${OUTPUT_DIR}/preanalysis.json"

    local PFILE="${DATA_DIR}/pmu_info.txt"
    local MFILE="${DATA_DIR}/memory_metrics_analysis.txt"
    local SFILE="${DATA_DIR}/static_info.txt"
    local KFILE="${DATA_DIR}/kernel_config_info.txt"
    local PDFILE="${DATA_DIR}/process_detail_info.txt"

    # ---- PMU HHA 数据 ----
    local hha_available ops_per_sec remote_ratio pmu_path_applicable
    read -r hha_available ops_per_sec remote_ratio pmu_path_applicable <<< "$(extract_pmu_info "$PFILE")"

    # ---- vmstat/numastat 数据 ----
    local numa_hit numa_miss numa_foreign remote_access_ratio
    read -r numa_hit numa_miss numa_foreign remote_access_ratio <<< "$(extract_vmstat_info "$MFILE")"

    # ---- NUMA 节点数 ----
    local numa_nodes
    numa_nodes=$(extract_numa_nodes "$SFILE")

    # ---- 线程创建频率（来自 process_detail_info.txt） ----
    local thread_create_per_second
    thread_create_per_second=$(extract_thread_create_per_second "$PDFILE")

    # ---- PARAL 信息 ----
    local paral_support paral_enabled sched_util_low_pct
    read -r paral_support paral_enabled sched_util_low_pct <<< "$(extract_paral_info "$KFILE")"

    # ---- 构建 JSON ----
    # 兼容 thread_create_per_second 为 null 的情况（数据缺失 → SKILL.md N4 跳过）
    local tcr_json
    if [[ "$thread_create_per_second" == "null" || -z "$thread_create_per_second" ]]; then
        tcr_json="null"
    else
        tcr_json="${thread_create_per_second}"
    fi

    cat > "$JSON_FILE" <<EOF
{
  "hha_available": $hha_available,
  "ops_per_sec": ${ops_per_sec},
  "remote_ratio": ${remote_ratio},
  "thread_create_per_second": ${tcr_json},
  "pmu_path_applicable": $pmu_path_applicable,
  "numa_hit": ${numa_hit},
  "numa_miss": ${numa_miss},
  "numa_foreign": ${numa_foreign},
  "remote_access_ratio": ${remote_access_ratio},
  "numa_nodes": ${numa_nodes},
  "paral_support": "$(json_escape "$paral_support")",
  "paral_enabled": "$(json_escape "$paral_enabled")",
  "sched_util_low_pct": $sched_util_low_pct
}
EOF

    echo "preanalysis.json 已生成: $JSON_FILE ($(wc -c < "$JSON_FILE") bytes)"
}

main "$@"
