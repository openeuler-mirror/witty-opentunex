#!/usr/bin/env bash
# preanalysis.sh - 从已有采集数据文件提取 hisock 加速分析所需关键字段，生成 preanalysis.json
# 用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]
#   DATA_DIR:   采集批次目录（含 hotspot_analysis.txt、network_metrics_analysis.txt 等）
#   OUTPUT_DIR: JSON 输出目录，默认 ${DATA_DIR}/opentunex-hisock-analysis_collect
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

# 从 hotspot_analysis.txt 提取热点函数调用栈信息
# IS_NF_HOOK_HOTSPOT: 调用栈中是否包含 nf_hook* 函数
# NF_HOOK_FUNCS: 命中的 nf_hook 函数名列表（逗号分隔）
# NF_HOOK_PERCENT: nf_hook 热点占比
extract_hotspot_info() {
    local data_dir="$1"
    local is_nf_hook_hotspot=false
    local nf_hook_funcs=""
    local nf_hook_percent=0

    local hfile=""
    if [[ -f "${data_dir}/hotspot_analysis.txt" ]]; then
        hfile="${data_dir}/hotspot_analysis.txt"
    elif [[ -f "${data_dir}/hotspot_function_analysis.txt" ]]; then
        hfile="${data_dir}/hotspot_function_analysis.txt"
    elif [[ -f "${data_dir}/perf_report.txt" ]]; then
        hfile="${data_dir}/perf_report.txt"
    fi

    if [[ -z "$hfile" ]]; then
        echo "$is_nf_hook_hotspot $nf_hook_funcs $nf_hook_percent"
        return
    fi

    # 搜索调用栈中的 nf_hook* 函数
    # nf_hook_slow、nf_hook_entries、nf_hook_ops 等
    if grep -qiE 'nf_hook' "$hfile" 2>/dev/null; then
        is_nf_hook_hotspot=true
        # 提取命中的 nf_hook 函数名（去重）
        nf_hook_funcs=$(grep -oiE 'nf_hook[a-zA-Z0-9_]*' "$hfile" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
        # 提取占比百分比（perf report 的 Overhead 列）
        local pct=""
        pct=$(grep -iE 'nf_hook' "$hfile" 2>/dev/null | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+%?$/ || $i ~ /^[0-9]+%?$/){print $i; break}}' | sed 's/%//' || true)
        if [[ -n "$pct" ]]; then
            nf_hook_percent="$pct"
        fi
    fi

    echo "$is_nf_hook_hotspot $nf_hook_funcs $nf_hook_percent"
}

# 从 network_metrics_analysis.txt / net_info.txt 提取网络信息
# NET_DEV_NAME: 主要网卡设备名（如 enp46s0f0np0）
# CGROUP_PATH: cgroup 路径（从进程信息推断，如 /sys/fs/cgroup/perf_event/）
# LISTEN_PORTS: 监听端口号列表（逗号分隔）
extract_net_info() {
    local data_dir="$1"
    local net_dev_name=""
    local cgroup_path=""
    local listen_ports=""

    # 网卡设备名：从网络指标或静态信息中提取
    local nfile=""
    if [[ -f "${data_dir}/network_metrics_analysis.txt" ]]; then
        nfile="${data_dir}/network_metrics_analysis.txt"
    elif [[ -f "${data_dir}/net_info.txt" ]]; then
        nfile="${data_dir}/net_info.txt"
    elif [[ -f "${data_dir}/net_metrics_analysis.txt" ]]; then
        nfile="${data_dir}/net_metrics_analysis.txt"
    fi

    if [[ -n "$nfile" ]]; then
        # 提取主要物理网卡名（排除 lo/virbr/docker 等虚拟网卡）
        net_dev_name=$(grep -iE '^\s*(enp|eth|ens|enP)' "$nfile" 2>/dev/null | head -1 | awk '{print $1}' | sed 's/:.*//' || true)
        if [[ -z "$net_dev_name" ]]; then
            # 降级：从 ip link 输出提取
            net_dev_name=$(grep -iE 'link/ether' "$nfile" 2>/dev/null | head -1 | awk '{print $2}' | sed 's/:.*//' || true)
        fi
    fi

    # cgroup 路径：检查默认路径是否存在
    if [[ -d "/sys/fs/cgroup/perf_event" ]]; then
        cgroup_path="/sys/fs/cgroup/perf_event"
    elif [[ -d "/sys/fs/cgroup" ]]; then
        cgroup_path="/sys/fs/cgroup"
    fi

    # 监听端口：从网络信息或进程信息中提取
    local pfile=""
    if [[ -f "${data_dir}/process_detail_info.txt" ]]; then
        pfile="${data_dir}/process_detail_info.txt"
    elif [[ -f "${data_dir}/process_info.txt" ]]; then
        pfile="${data_dir}/process_info.txt"
    fi

    if [[ -n "$pfile" ]]; then
        # 提取常见服务端口（redis:6379, mysql:3306 等）
        listen_ports=$(grep -oiE '(redis|mysql|postgres|nginx|httpd|memcached|etcd)[^[:space:]]*' "$pfile" 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//' || true)
    fi

    echo "$(json_escape "$net_dev_name") $(json_escape "$cgroup_path") $(json_escape "$listen_ports")"
}

# 从 static_info.txt / kernel_config_info.txt 提取内核特性支持信息
# IS_HISOCK_SUPPORTED: 是否支持 hisock（检查内核配置 CONFIG_HISOCK=y）
# KERNEL_VERSION: 内核版本
extract_kernel_info() {
    local data_dir="$1"
    local is_hisock_supported=false
    local kernel_version=""

    local kfile=""
    if [[ -f "${data_dir}/kernel_config_info.txt" ]]; then
        kfile="${data_dir}/kernel_config_info.txt"
    elif [[ -f "${data_dir}/static_info.txt" ]]; then
        kfile="${data_dir}/static_info.txt"
    fi

    if [[ -z "$kfile" ]]; then
        echo "$is_hisock_supported $(json_escape "$kernel_version")"
        return
    fi

    # 内核版本
    kernel_version=$(grep -iE '^\s*kernel:|^\s*Kernel Release:' "$kfile" 2>/dev/null | head -1 | sed 's/^[[:space:]]*[Kk]ernel[[:space:]]*\(Release\)\?:[[:space:]]*//I' | sed 's/[[:space:]]*$//' || true)
    if [[ -z "$kernel_version" ]]; then
        kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    fi

    # hisock 支持：检查内核配置 CONFIG_HISOCK=y
    if grep -qiE 'CONFIG_HISOCK=y' "$kfile" 2>/dev/null; then
        is_hisock_supported=true
    fi

    echo "$is_hisock_supported $(json_escape "$kernel_version")"
}

# ============================================================
# 主流程
# ============================================================

main() {
    local DATA_DIR="${1:-}"
    local OUTPUT_DIR="${2:-${DATA_DIR}/opentunex-hisock-analysis_collect}"

    [[ -z "$DATA_DIR" ]] && die "用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]"
    [[ -d "$DATA_DIR" ]] || die "DATA_DIR 不存在: $DATA_DIR"

    mkdir -p "$OUTPUT_DIR"
    local JSON_FILE="${OUTPUT_DIR}/preanalysis.json"

    # ---- 从 hotspot_analysis.txt 提取热点函数信息 ----
    local is_nf_hook_hotspot nf_hook_funcs nf_hook_percent
    read -r is_nf_hook_hotspot nf_hook_funcs nf_hook_percent <<< "$(extract_hotspot_info "$DATA_DIR")"

    # ---- 从 network_metrics_analysis.txt 提取网络信息 ----
    local net_dev_name cgroup_path listen_ports
    read -r net_dev_name cgroup_path listen_ports <<< "$(extract_net_info "$DATA_DIR")"

    # ---- 从 kernel_config_info.txt 提取内核特性支持 ----
    local is_hisock_supported kernel_version
    read -r is_hisock_supported kernel_version <<< "$(extract_kernel_info "$DATA_DIR")"

    # ---- 构建 JSON ----
    cat > "$JSON_FILE" <<EOF
{
  "is_nf_hook_hotspot": ${is_nf_hook_hotspot},
  "nf_hook_funcs": "$(json_escape "$nf_hook_funcs")",
  "nf_hook_percent": ${nf_hook_percent},
  "net_dev_name": "$(json_escape "$net_dev_name")",
  "cgroup_path": "$(json_escape "$cgroup_path")",
  "listen_ports": "$(json_escape "$listen_ports")",
  "is_hisock_supported": ${is_hisock_supported},
  "kernel_version": "$(json_escape "$kernel_version")"
}
EOF

    echo "preanalysis.json 已生成: $JSON_FILE ($(wc -c < "$JSON_FILE") bytes)"
}

main "$@"
