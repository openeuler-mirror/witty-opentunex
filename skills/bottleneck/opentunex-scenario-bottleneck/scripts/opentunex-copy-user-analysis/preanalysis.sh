#!/usr/bin/env bash
# preanalysis.sh - 从已有采集数据文件提取 copy_from_user 优化分析所需关键字段，生成 preanalysis.json
# 用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]
#   DATA_DIR:   采集批次目录（含 static_info.txt、cpu_info.txt、hotspot_analysis.txt 等）
#   OUTPUT_DIR: JSON 输出目录，默认 ${DATA_DIR}/opentunex-copy-user-analysis_collect
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

# 将十六进制 partID 转为十进制，用于与阈值 0xd02 比较
# 输入示例: "0xd02" / "0xD02" / "d02" / "D02"
hex_to_dec() {
    local h="$1"
    # 去除 0x/0X 前缀
    h="${h#[0xX]}"
    h="${h#[X]}"
    # 转大写后转十进制
    echo "ibase=16; $(echo "$h" | tr '[:lower:]' '[:upper:]')" | bc 2>/dev/null || echo "0"
}

# ============================================================
# 数据提取函数
# ============================================================

# 从 static_info.txt / cpu_info.txt 提取 CPU 信息
# ARCH: aarch64/arm64 才支持
# PART_ID_HEX: ARM CPU part ID（十六进制），如 0xd02、0xd01
# IS_ARM64: 是否为 ARM64 架构
# PART_ID_DEC: partID 十进制值，用于与阈值比较（> 0xd02 = 3330）
# IS_HISILICON_SUPPORTED_CPU: 是否为支持的 Hisilicon CPU（partID > 0xd02）
extract_cpu_info() {
    local data_dir="$1"
    local arch=""
    local part_id_hex=""
    local is_arm64=false
    local part_id_dec=0
    local is_hisilicon_supported=false

    local sfile=""
    if [[ -f "${data_dir}/static_info.txt" ]]; then
        sfile="${data_dir}/static_info.txt"
    elif [[ -f "${data_dir}/cpu_info.txt" ]]; then
        sfile="${data_dir}/cpu_info.txt"
    elif [[ -f "${data_dir}/cpu_detail_info.txt" ]]; then
        sfile="${data_dir}/cpu_detail_info.txt"
    fi

    if [[ -z "$sfile" ]]; then
        echo "$arch $part_id_hex $is_arm64 $part_id_dec $is_hisilicon_supported"
        return
    fi

    # ARCH: 从 uname -m 或 lscpu 输出提取
    arch=$(grep -iE '^\s*Architecture:|^\s*arch:' "$sfile" 2>/dev/null | head -1 | sed 's/^[[:space:]]*[Aa]rchitecture:[[:space:]]*//I' | sed 's/^[[:space:]]*arch:[[:space:]]*//I' | sed 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' || true)
    if [[ -z "$arch" ]]; then
        # 尝试从包含 aarch64/arm64/x86_64 的行提取
        if grep -qiE 'aarch64|arm64' "$sfile" 2>/dev/null; then
            arch="aarch64"
        elif grep -qiE 'x86_64|amd64' "$sfile" 2>/dev/null; then
            arch="x86_64"
        fi
    fi
    [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && is_arm64=true

    # PART_ID_HEX: 从 /proc/cpuinfo 或 lscpu 的 CPU part 字段提取
    # /proc/cpuinfo 格式: "CPU part : 0xd02"
    # lscpu 输出可能包含 "Model:" 字段
    part_id_hex=$(grep -iE '^\s*CPU part\s*:' "$sfile" 2>/dev/null | head -1 | sed 's/^[[:space:]]*CPU part[[:space:]]*:[[:space:]]*//I' | sed 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' || true)
    if [[ -z "$part_id_hex" ]]; then
        part_id_hex=$(grep -iE '^\s*Model:\s*0x' "$sfile" 2>/dev/null | head -1 | sed 's/^[[:space:]]*Model:[[:space:]]*//I' | sed 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' || true)
    fi

    # 转为十进制
    if [[ -n "$part_id_hex" ]]; then
        part_id_dec=$(hex_to_dec "$part_id_hex")
    fi

    # IS_HISILICON_SUPPORTED_CPU: partID > 0xd02 (3330)
    # 支持 LINXICORE9100、HIP11、HIP12 等，对应 partID > 0xd02
    if [[ "$is_arm64" == "true" ]] && [[ "$part_id_dec" -gt 3330 ]] 2>/dev/null; then
        is_hisilicon_supported=true
    fi

    echo "$arch $part_id_hex $is_arm64 $part_id_dec $is_hisilicon_supported"
}

# 从 hotspot_analysis.txt / cpu_detail_info.txt 提取热点函数信息
# IS_COPY_USER_HOTSPOT: 是否检测到 __arch_copy_to_user/__arch_copy_from_user 热点
# COPY_USER_FUNC_HITS: 命中的函数名（可能多个，逗号分隔）
# COPY_USER_HOTSPOT_PERCENT: 热点占比（如 5.2），用于评估收益严重度
extract_hotspot_info() {
    local data_dir="$1"
    local is_copy_user_hotspot=false
    local copy_user_funcs=""
    local hotspot_percent=0

    local hfile=""
    if [[ -f "${data_dir}/hotspot_analysis.txt" ]]; then
        hfile="${data_dir}/hotspot_analysis.txt"
    elif [[ -f "${data_dir}/hotspot_function_analysis.txt" ]]; then
        hfile="${data_dir}/hotspot_function_analysis.txt"
    elif [[ -f "${data_dir}/perf_report.txt" ]]; then
        hfile="${data_dir}/perf_report.txt"
    fi

    if [[ -z "$hfile" ]]; then
        echo "$is_copy_user_hotspot $copy_user_funcs $hotspot_percent"
        return
    fi

    # 搜索 __arch_copy_to_user / __arch_copy_from_user 函数
    local matched_lines=""
    if grep -qiE '__arch_copy_to_user|__arch_copy_from_user' "$hfile" 2>/dev/null; then
        is_copy_user_hotspot=true
        # 提取命中的函数名（去重）
        copy_user_funcs=$(grep -oiE '__arch_copy_(to|from)_user' "$hfile" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
        # 提取占比百分比（perf report 的 Overhead 列）
        local pct=""
        pct=$(grep -iE '__arch_copy_(to|from)_user' "$hfile" 2>/dev/null | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+%?$/ || $i ~ /^[0-9]+%?$/){print $i; break}}' | sed 's/%//' || true)
        if [[ -n "$pct" ]]; then
            hotspot_percent="$pct"
        fi
    fi

    echo "$is_copy_user_hotspot $copy_user_funcs $hotspot_percent"
}

# 从 syscall_analysis.txt / io_metrics_analysis.txt 提取 read/write size 信息
# 采集脚本 perf trace -e pread64,pwrite64 的输出会记录每次调用的 size
# LARGE_COPY_DETECTED: 是否检测到 size > 4KB 的读写
# MAX_COPY_SIZE: 最大单次读写 size（字节）
# LARGE_COPY_COUNT: size > 4KB 的调用次数
extract_copy_size_info() {
    local data_dir="$1"
    local large_copy_detected=false
    local max_copy_size=0
    local large_copy_count=0

    local cfile=""
    if [[ -f "${data_dir}/syscall_analysis.txt" ]]; then
        cfile="${data_dir}/syscall_analysis.txt"
    elif [[ -f "${data_dir}/io_metrics_analysis.txt" ]]; then
        cfile="${data_dir}/io_metrics_analysis.txt"
    elif [[ -f "${data_dir}/perf_trace.txt" ]]; then
        cfile="${data_dir}/perf_trace.txt"
    fi

    if [[ -z "$cfile" ]]; then
        echo "$large_copy_detected $max_copy_size $large_copy_count"
        return
    fi

    # 解析 perf trace 输出中的 pread64/pwrite64 调用 size
    # perf trace 输出格式示例:
    #   1234.567 pread64(fd: 5, buf: 0x..., count: 8192, pos: ...) = 8192
    #   1234.567 pwrite64(fd: 5, buf: 0x..., count: 4096, pos: ...) = 4096
    # 提取 count 字段值
    local sizes=""
    sizes=$(grep -iE 'pread64|pwrite64' "$cfile" 2>/dev/null | grep -oiE 'count:[[:space:]]*[0-9]+' | sed 's/[^0-9]//g' || true)

    if [[ -n "$sizes" ]]; then
        local max_size=0
        local count_large=0
        while read -r sz; do
            [[ -z "$sz" ]] && continue
            if [[ "$sz" -gt "$max_size" ]] 2>/dev/null; then
                max_size="$sz"
            fi
            if [[ "$sz" -gt 4096 ]] 2>/dev/null; then
                count_large=$((count_large + 1))
            fi
        done <<< "$sizes"
        max_copy_size="$max_size"
        large_copy_count="$count_large"
        if [[ "$count_large" -gt 0 ]]; then
            large_copy_detected=true
        fi
    fi

    echo "$large_copy_detected $max_copy_size $large_copy_count"
}

# ============================================================
# 主流程
# ============================================================

main() {
    local DATA_DIR="${1:-}"
    local OUTPUT_DIR="${2:-${DATA_DIR}/opentunex-copy-user-analysis_collect}"

    [[ -z "$DATA_DIR" ]] && die "用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]"
    [[ -d "$DATA_DIR" ]] || die "DATA_DIR 不存在: $DATA_DIR"

    mkdir -p "$OUTPUT_DIR"
    local JSON_FILE="${OUTPUT_DIR}/preanalysis.json"

    # ---- 从 static_info.txt / cpu_info.txt 提取 CPU 信息 ----
    local arch part_id_hex is_arm64 part_id_dec is_hisilicon_supported
    read -r arch part_id_hex is_arm64 part_id_dec is_hisilicon_supported <<< "$(extract_cpu_info "$DATA_DIR")"

    # ---- 从 hotspot_analysis.txt 提取热点函数信息 ----
    local is_copy_user_hotspot copy_user_funcs hotspot_percent
    read -r is_copy_user_hotspot copy_user_funcs hotspot_percent <<< "$(extract_hotspot_info "$DATA_DIR")"

    # ---- 从 syscall_analysis.txt 提取读写 size 信息 ----
    local large_copy_detected max_copy_size large_copy_count
    read -r large_copy_detected max_copy_size large_copy_count <<< "$(extract_copy_size_info "$DATA_DIR")"

    # ---- 构建 JSON ----
    cat > "$JSON_FILE" <<EOF
{
  "arch": "$(json_escape "$arch")",
  "is_arm64": ${is_arm64},
  "part_id_hex": "$(json_escape "$part_id_hex")",
  "part_id_dec": ${part_id_dec},
  "is_hisilicon_supported_cpu": ${is_hisilicon_supported},
  "is_copy_user_hotspot": ${is_copy_user_hotspot},
  "copy_user_funcs": "$(json_escape "$copy_user_funcs")",
  "hotspot_percent": ${hotspot_percent},
  "large_copy_detected": ${large_copy_detected},
  "max_copy_size": ${max_copy_size},
  "large_copy_count": ${large_copy_count}
}
EOF

    echo "preanalysis.json 已生成: $JSON_FILE ($(wc -c < "$JSON_FILE") bytes)"
}

main "$@"
