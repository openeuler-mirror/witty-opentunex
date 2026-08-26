#!/usr/bin/env bash
# preanalysis.sh - 从已有采集数据文件提取关键字段，生成 preanalysis.json
# 用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]
#   DATA_DIR:   采集批次目录（含 kernel_config_info.txt 等文件）
#   OUTPUT_DIR: JSON 输出目录，默认 ${DATA_DIR}/opentunex-multi-net-path-analysis_collect
# 说明: 本脚本仅解析已有文本文件，不执行 ethtool/sar 等采集命令

set -euo pipefail

RXKB_THRESHOLD=2048

die() { echo "ERROR: $*" >&2; exit 1; }

# ============================================================
# 工具函数
# ============================================================

# 判断是否为虚拟网卡
is_skip_iface() {
    local ifname="$1"
    case "$ifname" in
        lo|IFACE) return 0 ;;
    esac
    [[ "$ifname" == docker* || "$ifname" == veth* || "$ifname" == br-* \
        || "$ifname" == virbr* || "$ifname" == tun* || "$ifname" == tap* ]] && return 0
    return 1
}

# 将十六进制掩码解析为 CPU 编号列表
# 支持短格式 (ff) 和长格式 (00000000,00000001)
parse_affinity_to_cpus() {
    local mask="$1"
    local cpus=()
    local cpu_idx=0
    local -a blocks

    # 长格式：按逗号拆分
    IFS=',' read -ra blocks <<< "$mask"
    for block in "${blocks[@]}"; do
        block=$(echo "$block" | tr -d '[:space:]')
        [[ -z "$block" ]] && continue
        local val
        val=$((16#$block)) 2>/dev/null || val=0
        local bit
        for ((bit=0; bit<32; bit++)); do
            if (( (val >> bit) & 1 )); then
                cpus+=("$cpu_idx")
            fi
            ((cpu_idx++))
        done
    done
    echo "${cpus[@]}"
}

# JSON 转义字符串
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo "$s"
}

# 输出 JSON 数组
json_array() {
    local first=1
    local item
    for item in "$@"; do
        [[ -z "$item" ]] && continue
        if ((first)); then
            printf '"%s"' "$item"
            first=0
        else
            printf ', "%s"' "$item"
        fi
    done
}

# CPU→NUMA 映射（全局，由 build_cpu_to_numa_map 填充）
declare -A CPU_TO_NUMA=()

# 从 numa_cpu_map JSON 构建 CPU→NUMA 映射
# 输入: numa_map_json，格式如 {"node0": [0,1,2,3], "node1": [4,5,6,7]}
build_cpu_to_numa_map() {
    local numa_map_json="$1"
    CPU_TO_NUMA=()
    while IFS= read -r pair; do
        [[ -z "$pair" ]] && continue
        local node_name
        node_name=$(echo "$pair" | grep -oP '"node[0-9]+"' | tr -d '"')
        [[ -z "$node_name" ]] && continue
        local cpus_str
        cpus_str=$(echo "$pair" | grep -oP '\[[\d\s,]+\]' | tr -d '[]')
        [[ -z "$cpus_str" ]] && continue
        local IFS=','
        local cpu_str
        for cpu_str in $cpus_str; do
            cpu_str=$(echo "$cpu_str" | tr -d '[:space:]')
            [[ -z "$cpu_str" ]] && continue
            CPU_TO_NUMA["$cpu_str"]="$node_name"
        done
    done < <(echo "$numa_map_json" | grep -oP '"node[0-9]+":\s*\[[\d\s,]+\]')
}

# ============================================================
# 数据提取函数
# ============================================================

# 支持的网卡多路径模块名列表（按优先级匹配）
# 多数发行版使用 oenetcls；部分定制内核使用 venetcls。
OENETCLS_NAME_CANDIDATES=("oenetcls" "venetcls")

# 在文件中定位指定模块的 modinfo 节内容
# 优先匹配 `--- <name> ---` 标准节；缺失时回退到扫描任何含 filename: 的 oenetcls/venetcls 节
_locate_modinfo_section() {
    local kfile="$1" name="$2"
    local section
    section=$(sed -n "/^--- ${name} ---$/,/^--- /p" "$kfile" 2>/dev/null || true)
    if [[ -n "$section" ]] && echo "$section" | grep -q "filename:"; then
        echo "$section"
        return
    fi
    # 回退：扫描所有同名标题（兼容采集端未严格使用 `--- <name> ---` 命名的情况）
    section=$(grep -A 50 -E "^--- .*${name}.* ---$" "$kfile" 2>/dev/null | sed -n '/filename:/,/^--- /p' | head -50 || true)
    echo "$section"
}

# 探测指定模块是否已加载（依据 /proc/modules 节内容）
_is_module_loaded_in_file() {
    local kfile="$1" name="$2"
    # 节标题可能是 `--- /proc/modules (oenetcls/cpufreq_seep) ---` 或类似变体
    local modules_section
    modules_section=$(sed -n '/^--- .*\/proc\/modules/,/^--- /p' "$kfile" 2>/dev/null || true)
    [[ -z "$modules_section" ]] && return 1
    # 行首为模块名，后接大小、使用计数等数字
    echo "$modules_section" | grep -qE "^${name}[[:space:]]+[0-9]+"
}

extract_oenetcls_info() {
    local kfile="$1"
    local loaded=false available=false
    local detected_name="" candidate section

    if [[ ! -f "$kfile" ]]; then
        echo "false false oenetcls"
        return
    fi

    # 1) 先按优先级匹配已加载的模块（任意一个候选名出现在 /proc/modules 即视为已加载）
    for candidate in "${OENETCLS_NAME_CANDIDATES[@]}"; do
        if _is_module_loaded_in_file "$kfile" "$candidate"; then
            loaded=true
            detected_name="$candidate"
            break
        fi
    done

    # 2) 未加载时按顺序匹配 modinfo 节，寻找第一个有 filename: 输出的模块
    if [[ -z "$detected_name" ]]; then
        for candidate in "${OENETCLS_NAME_CANDIDATES[@]}"; do
            section=$(_locate_modinfo_section "$kfile" "$candidate")
            if [[ -n "$section" ]] && echo "$section" | grep -q "filename:"; then
                available=true
                detected_name="$candidate"
                break
            fi
        done
    else
        # 已加载则必然 available
        available=true
    fi

    # 3) 兜底：若两个候选名都未命中，但文件中含 oenetcls/venetcls 关键字的
    #    modinfo 节（兼容旧采集器使用非标准节标题的情况），尝试最后一次匹配
    if [[ -z "$detected_name" ]]; then
        if grep -qE "^--- .*oenetcls.* ---$" "$kfile" 2>/dev/null \
            || grep -qE "^--- .*venetcls.* ---$" "$kfile" 2>/dev/null; then
            local fallback_section
            fallback_section=$(grep -B1 -A 50 -E "^--- .*(oenetcls|venetcls).* ---$" "$kfile" \
                | grep -E "^--- |filename:" | head -100 || true)
            if echo "$fallback_section" | grep -q "filename:"; then
                available=true
                # 从最近的节标题推断模块名
                detected_name=$(echo "$fallback_section" \
                    | grep -oE "(oenetcls|venetcls)" | head -1 || echo "")
                [[ -z "$detected_name" ]] && detected_name="oenetcls"
            fi
        fi
    fi

    # 4) 完全没有匹配时，默认报告 oenetcls 不可用，便于上层决策
    [[ -z "$detected_name" ]] && detected_name="oenetcls"

    echo "$loaded $available $detected_name"
}

extract_irqbalance() {
    # 返回两行：第1行=状态(active/inactive/unknown)，第2行=检测到的服务名(irqbalance/irqbalance-ng)
    # 服务名由采集器在 --- irqbalance-service --- 节记录，用于在建议中引用正确的 systemctl 单元名
    local kfile="$1"
    local status="unknown"
    local svc_name="irqbalance"
    [[ ! -f "$kfile" ]] && { printf '%s\n%s\n' "$status" "$svc_name"; return; }

    local line
    line=$(sed -n '/^--- irqbalance ---$/{n;p;q}' "$kfile" 2>/dev/null || true)
    line=$(echo "$line" | tr -d '[:space:]')
    case "$line" in
        active)   status="active" ;;
        inactive) status="inactive" ;;
    esac

    # 读取 --- irqbalance-service --- 节记录的服务名（部分 Debian 系统为 irqbalance-ng）
    local svc
    svc=$(sed -n '/^--- irqbalance-service ---$/{n;p;q}' "$kfile" 2>/dev/null || true)
    svc=$(echo "$svc" | tr -d '[:space:]')
    case "$svc" in
        irqbalance|irqbalance-ng) svc_name="$svc" ;;
    esac
    printf '%s\n%s\n' "$status" "$svc_name"
}

extract_numa_info() {
    local sfile="$1"
    local nodes=0
    local cpu_map="{}"
    [[ ! -f "$sfile" ]] && { echo "$nodes"; echo "$cpu_map"; return; }

    # 统计 NUMA 节点数（仅匹配 "node X cpus:" 行，排除 "node X size:" / "node X free:"）
    nodes=$(sed -n '/^--- NUMA Topology ---$/,/^--- /p' "$sfile" | grep -cE '^node [0-9]+ cpus?:' 2>/dev/null || true)
    if ((nodes == 0)); then
        nodes=$(grep -oP 'available:\s+\K\d+' "$sfile" 2>/dev/null || echo "1")
    fi

    # 构建 NUMA CPU 映射
    local -a node_mappings=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^node\ ([0-9]+)\ cpus?:\ (.+)$ ]]; then
            local node_id="${BASH_REMATCH[1]}"
            local cpu_list="${BASH_REMATCH[2]}"
            cpu_list=$(echo "$cpu_list" | tr '\n' ' ')
            local cpus_json
            cpus_json=$(echo "$cpu_list" | tr ' ' '\n' | grep -v '^$' | sed 's/^/"/;s/$/"/' | paste -sd ',' -)
            node_mappings+=("\"node${node_id}\": [${cpus_json}]")
        fi
    done < <(sed -n '/^--- NUMA Topology ---$/,/^--- /p' "$sfile")

    if ((${#node_mappings[@]} > 0)); then
        cpu_map="{"
        local first=1
        for m in "${node_mappings[@]}"; do
            ((first)) && first=0 || cpu_map+=", "
            cpu_map+="$m"
        done
        cpu_map+="}"
    fi

    echo "$nodes"
    echo "$cpu_map"
}

extract_interrupt_overview() {
    local cfile="$1"
    local nfile="${2:-}"
    local overview="无数据"
    local eth_lines=""

    # 优先从 cpu_detail_info.txt 的 /proc/interrupts 节提取
    if [[ -f "$cfile" ]]; then
        eth_lines=$(sed -n '/=== \/proc\/interrupts ===/,/^=== /p' "$cfile" | grep -i 'eth' 2>/dev/null || true)
    fi

    # 回退：从 network_metrics_analysis.txt 的 IRQ Affinity 节提取
    if [[ -z "$eth_lines" && -n "$nfile" && -f "$nfile" ]]; then
        eth_lines=$(grep -iE 'IRQ.*eth|eth.*IRQ' "$nfile" 2>/dev/null | head -20 || true)
    fi

    if [[ -z "$eth_lines" ]]; then
        echo "$overview"
        return
    fi

    # 统计 eth 中断所在的不同 CPU 列（第2列起每列对应一个CPU）
    local non_zero_cpus
    non_zero_cpus=$(echo "$eth_lines" | awk '{
        for(i=2; i<=NF; i++) if($i+0 > 0) c++
    } END { print c+0 }')

    if ((non_zero_cpus <= 2)); then
        overview="集中在少数核心(≤2)"
    elif ((non_zero_cpus <= 4)); then
        overview="分布在${non_zero_cpus}个核心"
    else
        overview="均匀分布在${non_zero_cpus}个核心"
    fi
    echo "$overview"
}

extract_app_info() {
    local data_dir="$1"
    local redis=false nginx=false mysql=false
    local target_pid="null"

    # 同时检查 process_detail_info.txt 和 top_processes.txt
    local combined=""
    local pfile="${data_dir}/process_detail_info.txt"
    local tfile="${data_dir}/top_processes.txt"

    [[ -f "$pfile" ]] && combined+="$(cat "$pfile")"$'\n'
    [[ -f "$tfile" ]] && combined+="$(cat "$tfile")"$'\n'
    [[ -z "$combined" ]] && { echo "$redis $nginx $mysql $target_pid"; return; }

    # 先从进程输出中找 redis/nginx/mysql
    if echo "$combined" | grep -q "redis-server" 2>/dev/null && ! echo "$combined" | grep -q "redis-server.*未运行" 2>/dev/null; then
        redis=true
        target_pid=$(echo "$combined" | grep "redis-server" | grep -oP '\d+' | head -1 || echo "null")
    fi
    if echo "$combined" | grep -q "nginx" 2>/dev/null && ! echo "$combined" | grep -q "nginx.*未运行" 2>/dev/null; then
        nginx=true
        [[ "$target_pid" == "null" ]] && target_pid=$(echo "$combined" | grep "nginx" | grep -oP '\d+' | head -1 || echo "null")
    fi
    if echo "$combined" | grep -q "mysqld\|mysql" 2>/dev/null && ! echo "$combined" | grep -q "mysql.*未运行" 2>/dev/null; then
        mysql=true
        [[ "$target_pid" == "null" ]] && target_pid=$(echo "$combined" | grep -E "mysqld|mysql" | grep -oP '\d+' | head -1 || echo "null")
    fi

    # 回退：从 top / ps 节中按进程名匹配
    if ! $redis && ! $nginx && ! $mysql; then
        if echo "$combined" | grep -qE 'redis-server' 2>/dev/null; then
            redis=true
            target_pid=$(echo "$combined" | grep -E 'redis-server' | grep -oP '^\s*\K\d+' | head -1 || echo "null")
        fi
        if echo "$combined" | grep -qE '\bnginx\b' 2>/dev/null; then
            nginx=true
            [[ "$target_pid" == "null" ]] && target_pid=$(echo "$combined" | grep -E '\bnginx\b' | grep -oP '^\s*\K\d+' | head -1 || echo "null")
        fi
        if echo "$combined" | grep -qE '\bmysqld\b' 2>/dev/null; then
            mysql=true
            [[ "$target_pid" == "null" ]] && target_pid=$(echo "$combined" | grep -E '\bmysqld\b' | grep -oP '^\s*\K\d+' | head -1 || echo "null")
        fi
    fi

    echo "$redis $nginx $mysql $target_pid"
}

# 判断是否为物理网卡名（匹配常见命名模式）
is_physical_nic() {
    local name="$1"
    # Predictable Network Interface Names: en*, wl*, ww*
    # Legacy: eth*, bond*, ib*
    [[ "$name" =~ ^(eth[0-9]|en[opsx][0-9]|bond[0-9]|ib[0-9]|wlan[0-9]|wl[ps][0-9]) ]] && return 0
    return 1
}

# 从 network_metrics_analysis.txt 中提取网卡列表
extract_physical_nics() {
    local nfile="$1"
    [[ ! -f "$nfile" ]] && return

    # 只提取符合网卡命名模式的节标题（排除 "IRQ Affinity"、"sar -n DEV" 等非网卡节）
    grep -oP '(?<=^--- ).*(?= ---$)' "$nfile" 2>/dev/null | while IFS= read -r iface; do
        is_skip_iface "$iface" && continue
        is_physical_nic "$iface" || continue
        echo "$iface"
    done | sort -u
}

# 提取单张网卡的 ntuple 信息
extract_ntuple() {
    local nfile="$1" iface="$2"
    local has_ntuple=false ntuple_fixed="N/A" ntuple_enabled="off"

    # 定位该网卡的 ethtool -k 输出节
    local ethtool_k
    ethtool_k=$(sed -n "/^--- ${iface} ---$/,/^--- /p" "$nfile" | sed -n '/ethtool -k/,/^$/p' 2>/dev/null || true)
    if [[ -z "$ethtool_k" ]]; then
        ethtool_k=$(sed -n "/^--- ${iface} ---$/,/^--- /p" "$nfile" 2>/dev/null || true)
    fi

    local ntuple_line
    ntuple_line=$(echo "$ethtool_k" | grep -iE 'ntuple-filters|ntuple' | head -1 || true)
    if [[ -n "$ntuple_line" ]]; then
        has_ntuple=true
        # 提取 on/off 状态
        if echo "$ntuple_line" | grep -qi '\bon\b'; then
            ntuple_enabled="on"
        else
            ntuple_enabled="off"
        fi
        if echo "$ntuple_line" | grep -q '\[fixed\]'; then
            ntuple_fixed="yes"
        else
            ntuple_fixed="no"
        fi
    fi

    echo "$has_ntuple $ntuple_fixed $ntuple_enabled"
}

# 提取单张网卡的队列信息
extract_queues() {
    local nfile="$1" iface="$2"
    local max_q=0 cur_q=0

    local ethtool_l
    ethtool_l=$(sed -n "/^--- ${iface} ---$/,/^--- /p" "$nfile" | sed -n '/ethtool -l/,/^$/p' 2>/dev/null || true)

    # 单次 awk 解析，同时提取 Combined 的最大和当前值
    # 需正确处理 Pre-set maximums 和 Current hardware settings 两个区块
    local result
    result=$(echo "$ethtool_l" | awk '
        /^Pre-set maximums:/      { sec="max"; next }
        /^Current hardware settings:/ { sec="cur"; next }
        sec=="max" && /^Combined:/   { max_q=$2 }
        sec=="cur" && /^Combined:/   { cur_q=$2 }
        END { print (max_q?max_q:0), (cur_q?cur_q:0) }
    ' 2>/dev/null)
    read -r max_q cur_q <<< "$result"

    # 回退：若 Combined 不存在，用 RX+TX 之和
    if [[ "$max_q" == "0" ]]; then
        max_q=$(echo "$ethtool_l" | awk '
            /^Pre-set maximums:/      { sec="max"; next }
            /^Current hardware settings:/ { sec="cur"; next }
            sec=="max" && /^RX:/      { rx=$2 }
            sec=="max" && /^TX:/      { print rx+$2; exit }
        ' 2>/dev/null)
        max_q=${max_q:-0}
    fi
    if [[ "$cur_q" == "0" ]]; then
        cur_q=$(echo "$ethtool_l" | awk '
            /^Pre-set maximums:/      { sec="max"; next }
            /^Current hardware settings:/ { sec="cur"; next }
            sec=="cur" && /^RX:/      { rx=$2 }
            sec=="cur" && /^TX:/      { print rx+$2; exit }
        ' 2>/dev/null)
        cur_q=${cur_q:-0}
    fi

    max_q=${max_q:-0}
    cur_q=${cur_q:-0}
    echo "$max_q $cur_q"
}

# 提取网卡流量
extract_traffic() {
    local nfile="$1" iface="$2"
    local rxpck=0 rxkb=0

    # 优先从网卡流量采集节提取（尝试多种节定界符）
    local traffic_section
    traffic_section=$(sed -n '/=== 网卡流量采集 ===/,/^=== /p' "$nfile" 2>/dev/null || true)
    if [[ -z "$traffic_section" ]]; then
        traffic_section=$(sed -n '/--- 网卡流量采集 ---/,/^--- /p' "$nfile" 2>/dev/null || true)
    fi
    if [[ -z "$traffic_section" ]]; then
        traffic_section=$(sed -n '/=== sar.*DEV ===/,/^=== /p' "$nfile" 2>/dev/null || true)
    fi
    if [[ -z "$traffic_section" ]]; then
        traffic_section=$(sed -n '/Network Device Stats/,/^=== /p' "$nfile" 2>/dev/null || true)
    fi
    # 最后回退：取整个文件
    [[ -z "$traffic_section" ]] && traffic_section=$(cat "$nfile" 2>/dev/null || true)

    # 尝试 Average 行（多种格式）
    local avg_line
    avg_line=$(echo "$traffic_section" | grep -E '^(Average|平均)[: ]' | grep -F "$iface" | head -1 || true)

    # 也尝试 sar 汇总行（含 IFACE 列的 Average 汇总）
    if [[ -z "$avg_line" ]]; then
        avg_line=$(echo "$traffic_section" | grep -E '^(Average:|平均:)' | grep -F "$iface" | head -1 || true)
    fi

    if [[ -n "$avg_line" ]]; then
        # 按空格分割取 rxpck (第3列) 和 rxkb (第5列)，
        # 注意 12h AM/PM 偏移
        if echo "$avg_line" | awk '{print $2}' | grep -qE '^(AM|PM)$'; then
            read -r _ _ _ rxpck _ rxkb _ <<< "$avg_line"
        else
            read -r _ _ rxpck _ rxkb _ <<< "$avg_line"
        fi
        echo "${rxpck:-0} ${rxkb:-0}"
        return
    fi

    # 尝试 sar 采样行均值（多种时间格式）
    local samples
    # 24h 格式: HH:MM:SS
    samples=$(echo "$traffic_section" | grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2}' | grep -F "$iface" 2>/dev/null || true)
    # 带日期: MM/DD/YYYY HH:MM:SS 或 YYYY-MM-DD HH:MM:SS
    if [[ -z "$samples" ]]; then
        samples=$(echo "$traffic_section" | grep -E '^[0-9]{2}/[0-9]{2}/[0-9]{4}' | grep -F "$iface" 2>/dev/null || true)
    fi
    if [[ -z "$samples" ]]; then
        samples=$(echo "$traffic_section" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -F "$iface" 2>/dev/null || true)
    fi

    if [[ -n "$samples" ]]; then
        local sum_rxpck=0 sum_rxkb=0 cnt=0
        while IFS= read -r line; do
            local fields=($line)
            local iface_col=1 rxpck_col=2 rxkb_col=4
            # 12h 制 AM/PM: 时间 AM/PM IFACE rxpck/s  txpck/s  rxkB/s  txkB/s
            # 24h 制:       时间 IFACE rxpck/s  txpck/s  rxkB/s  txkB/s
            if echo "${fields[1]}" | grep -qE '^(AM|PM)$'; then
                iface_col=2
                rxpck_col=3
                rxkb_col=5
            fi
            [[ "${fields[$iface_col]}" != "$iface" ]] && continue
            local _rxpck=${fields[$rxpck_col]:-0}
            local _rxkb=${fields[$rxkb_col]:-0}
            sum_rxpck=$(awk "BEGIN {print ${sum_rxpck}+${_rxpck}}")
            sum_rxkb=$(awk "BEGIN {print ${sum_rxkb}+${_rxkb}}")
            ((cnt++))
        done <<< "$samples"
        if ((cnt > 0)); then
            rxpck=$(awk "BEGIN {printf \"%.2f\", ${sum_rxpck}/${cnt}}")
            rxkb=$(awk "BEGIN {printf \"%.2f\", ${sum_rxkb}/${cnt}}")
            echo "${rxpck} ${rxkb}"
            return
        fi
    fi

    echo "0 0"
}

# 提取 IRQ 亲和，返回 NUMA span 和标注
extract_irq_numa() {
    local nfile="$1" iface="$2"
    # 使用全局 CPU_TO_NUMA 映射进行 CPU→NUMA 查找

    local numa_span=0
    local annotation=""

    # 定位该网卡的 IRQ Affinity 节
    local irq_section
    irq_section=$(sed -n "/^--- IRQ Affinity.*${iface}/,/^--- /p" "$nfile" 2>/dev/null || true)
    if [[ -z "$irq_section" ]]; then
        irq_section=$(sed -n "/^--- ${iface} ---$/,/^--- /p" "$nfile" | sed -n '/IRQ Affinity/,/^--- /p' 2>/dev/null || true)
    fi
    [[ -z "$irq_section" ]] && { echo "0 "; return; }

    # 收集 IRQ 涉及的所有 NUMA 节点
    local -A numa_hit=()
    while IFS= read -r line; do
        if [[ "$line" =~ IRQ\ [0-9]+:\ ([0-9a-fA-F,]+) ]]; then
            local mask="${BASH_REMATCH[1]}"
            local -a cpus
            read -ra cpus <<< "$(parse_affinity_to_cpus "$mask")"
            # 反查每个 CPU 属于哪个 NUMA 节点
            for cpu in "${cpus[@]}"; do
                local node="${CPU_TO_NUMA[$cpu]:-node0}"
                numa_hit["$node"]=1
            done
        fi
    done <<< "$irq_section"

    numa_span=${#numa_hit[@]}

    if ((numa_span >= 2)); then
        annotation="中断跨NUMA，多路径收益明确"
    elif ((numa_span == 1)); then
        annotation="单NUMA亲和"
    fi

    echo "$numa_span $annotation"
}

# ============================================================
# 调优参数推荐
# ============================================================

# 阈值常量
MIN_QUEUES_FOR_RPS=4    # 单队列数小于该值时考虑加大 rxq_multiplex_limit
LARGE_NUMA_THRESHOLD=4  # NUMA 节点数 ≥ 该值时考虑 cluster 维度策略

# 从 network_metrics_analysis.txt 的 "--- <iface> ---" 节解析网卡驱动名
# 输出: 驱动名（mlx5_core / ixgbe / ...），无法识别时输出 "unknown"
extract_nic_driver() {
    local nfile="$1" iface="$2"
    local driver="unknown"

    [[ ! -f "$nfile" ]] && { echo "$driver"; return; }

    # 优先匹配 `Driver Info:` 块（server_data_collector.sh 格式：driver,version,firmware,bus）
    local driver_block
    driver_block=$(sed -n "/^--- ${iface} ---$/,/^--- /p" "$nfile" 2>/dev/null \
        | sed -n '/^Driver Info:/{n;p;}' | head -1 || true)
    if [[ -n "$driver_block" ]]; then
        # 第一项是 driver 名
        driver=$(echo "$driver_block" | cut -d',' -f1 | tr -d '[:space:]')
        [[ -n "$driver" ]] && { echo "$driver"; return; }
    fi

    # 回退：尝试 ethtool -i 风格输出（filename/version 行之上若有 driver 行）
    driver=$(sed -n "/^--- ${iface} ---$/,/^--- /p" "$nfile" 2>/dev/null \
        | grep -E '^driver:' | head -1 | awk '{print $2}' | tr -d '[:space:]' || true)
    [[ -n "$driver" ]] && { echo "$driver"; return; }

    echo "unknown"
}

# 根据驱动名推断 irqname（用于 /proc/interrupts 中匹配该网卡的中断描述）
# 规则: mlx5* → mlx5_comp；其他 → comp（默认）
infer_irqname() {
    local driver="$1"
    case "$driver" in
        mlx5*) echo "mlx5_comp" ;;
        mlx4*) echo "mlx4_comp" ;;
        ixgbe) echo "ixgbe-*" ;;
        i40e)  echo "i40e-*" ;;
        ice)   echo "ice-*" ;;
        *)     echo "comp" ;;
    esac
}

# 计算推荐参数集
# 输入参数:
#   $1 numa_nodes
#   $2 oenetcls_name
#   $3 apps_redis (true/false)
#   $4 apps_nginx (true/false)
#   $5 apps_mysql (true/false)
#   $6 driver (inferred by first recommended NIC, 或 "unknown")
#   $7 min_max_q (recommended NICs 中最小的 max_q，整数字符串；空表示无推荐网卡)
# 输出: 多行字符串，每行 "key=value"，按调优脚本所需顺序排列
compute_recommended_params() {
    local numa_nodes="$1" mod_name="$2"
    local apps_redis="$3" apps_nginx="$4" apps_mysql="$5"
    local driver="$6" min_max_q="${7:-}"
    local numa_nodes_int=${numa_nodes:-1}

    # ---- module_name ----
    local module_name="$mod_name"

    # ---- ifnames / appname: 留空，由 main() 在拿到 nic_details[] 后填充 ----
    local ifnames=""
    local appname=""

    # ---- appname: 按 redis > nginx > mysql 优先级拼接 ----
    local -a app_list=()
    [[ "$apps_redis" == "true" ]]  && app_list+=("redis-server")
    [[ "$apps_nginx" == "true" ]]  && app_list+=("nginx")
    [[ "$apps_mysql" == "true" ]]  && app_list+=("mysqld")
    if ((${#app_list[@]} > 0)); then
        appname=$(IFS='#'; echo "${app_list[*]}")
    fi

    # ---- mode ----
    # 默认 ntuple (0)；仅当所有推荐网卡 max_q≤1 时退化为 flow (1)
    local mode=0
    if [[ -n "$min_max_q" ]] && (( min_max_q <= 1 )); then
        mode=1
    fi

    # ---- strategy ----
    # 默认缺省策略 (0)；NUMA=2 时考虑 NUMA 均分 (2)；NUMA≥4 时考虑 Cluster 均分 (1)
    local strategy=0
    if (( numa_nodes_int >= LARGE_NUMA_THRESHOLD )); then
        strategy=1   # Cluster 均分
    elif (( numa_nodes_int == 2 )); then
        strategy=2   # NUMA 均分（不同网卡可用同核）
    fi

    # ---- debug ----
    local debug=0

    # ---- match_ip_flag ----
    # 默认关闭；当前数据无目的 IP 分布信息，保持 0
    local match_ip_flag=0

    # ---- irqname ----
    local irqname
    irqname=$(infer_irqname "$driver")

    # ---- rxq_multiplex_limit ----
    # 默认 1；当 max_q 较小（≤ MIN_QUEUES_FOR_RPS）时放大到 4 提升 TCP 流复用
    local rxq_multiplex_limit=1
    if [[ -n "$min_max_q" ]] && (( min_max_q > 0 )) && (( min_max_q <= MIN_QUEUES_FOR_RPS )); then
        rxq_multiplex_limit=4
    fi

    # ---- lo_rps_policy / rps_policy ----
    # 默认 0（关闭）；NUMA≥2 → 1（NUMA 内打散）；NUMA≥4 → 2（cluster 内打散）
    local lo_rps_policy=0 rps_policy=0
    if (( numa_nodes_int >= LARGE_NUMA_THRESHOLD )); then
        lo_rps_policy=2
        rps_policy=2
    elif (( numa_nodes_int >= 2 )); then
        lo_rps_policy=1
        rps_policy=1
    fi

    cat <<EOF
module_name=${module_name}
ifnames=${ifnames}
appname=${appname}
mode=${mode}
strategy=${strategy}
debug=${debug}
match_ip_flag=${match_ip_flag}
irqname=${irqname}
rxq_multiplex_limit=${rxq_multiplex_limit}
lo_rps_policy=${lo_rps_policy}
rps_policy=${rps_policy}
EOF
}

# ============================================================
# 主流程
# ============================================================

main() {
    local DATA_DIR="${1:-}"
    local OUTPUT_DIR="${2:-${DATA_DIR}/opentunex-multi-net-path-analysis_collect}"

    [[ -z "$DATA_DIR" ]] && die "用法: bash preanalysis.sh <DATA_DIR> [OUTPUT_DIR]"
    [[ -d "$DATA_DIR" ]] || die "DATA_DIR 不存在: $DATA_DIR"

    mkdir -p "$OUTPUT_DIR"
    local JSON_FILE="${OUTPUT_DIR}/preanalysis.json"

    local KFILE="${DATA_DIR}/kernel_config_info.txt"
    local SFILE="${DATA_DIR}/static_info.txt"
    local CFILE="${DATA_DIR}/cpu_detail_info.txt"
    local PFILE="${DATA_DIR}/process_detail_info.txt"
    local NFILE="${DATA_DIR}/network_metrics_analysis.txt"

    # ---- 环境信息 ----
    local oenetcls_loaded oenetcls_available oenetcls_name
    read -r oenetcls_loaded oenetcls_available oenetcls_name <<< "$(extract_oenetcls_info "$KFILE")"

    local irqbalance irqbalance_svc
    { read -r irqbalance; read -r irqbalance_svc; } <<< "$(extract_irqbalance "$KFILE")"

    local numa_nodes numa_cpu_map
    { read -r numa_nodes; read -r numa_cpu_map; } <<< "$(extract_numa_info "$SFILE")"
    numa_nodes=${numa_nodes:-1}

    # 构建 CPU→NUMA 映射（供 extract_irq_numa 使用）
    build_cpu_to_numa_map "$numa_cpu_map"

    local interrupt_overview
    interrupt_overview=$(extract_interrupt_overview "$CFILE" "$NFILE")

    local apps_redis apps_nginx apps_mysql target_app_pid
    read -r apps_redis apps_nginx apps_mysql target_app_pid <<< "$(extract_app_info "$DATA_DIR")"

    # ---- 网卡信息 ----
    local -a physical_nics=()
    local -a nic_json_entries=()

    if [[ -f "$NFILE" ]]; then
        while IFS= read -r iface; do
            [[ -z "$iface" ]] && continue
            is_skip_iface "$iface" && continue
            physical_nics+=("$iface")
        done < <(extract_physical_nics "$NFILE")
    fi

    # 如果没有网卡，回退：从 static_info 中推断
    if ((${#physical_nics[@]} == 0)) && [[ -f "$SFILE" ]]; then
        while IFS= read -r iface; do
            [[ -z "$iface" ]] && continue
            is_skip_iface "$iface" && continue
            physical_nics+=("$iface")
        done < <(sed -n '/=== 接口详细状态/,/^=== /p' "$SFILE" \
            | awk '/^[a-z]/ {print $1}' 2>/dev/null || true)
    fi

    for iface in "${physical_nics[@]}"; do
        local has_ntuple ntuple_fixed ntuple_enabled
        read -r has_ntuple ntuple_fixed ntuple_enabled <<< "$(extract_ntuple "$NFILE" "$iface")"

        local max_q cur_q
        read -r max_q cur_q <<< "$(extract_queues "$NFILE" "$iface")"

        local rxpck rxkb
        read -r rxpck rxkb <<< "$(extract_traffic "$NFILE" "$iface")"

        # 计算 multi_path / recommend_enable
        local multi_path=false recommend_enable=false
        if $has_ntuple && [[ "$ntuple_fixed" == "no" ]]; then
            multi_path=true
        fi
        if $multi_path; then
            local max_q_int=${max_q%%.*}
            local rxkb_num=${rxkb:-0}
            if ((max_q_int > 1)); then
                if (( $(awk "BEGIN {print ($rxkb_num > $RXKB_THRESHOLD) ? 1 : 0}") )); then
                    recommend_enable=true
                elif [[ -z "$rxkb" || "$rxkb" == "0" ]]; then
                    # 流量数据缺失 → 视为通过
                    recommend_enable=true
                fi
            fi
        fi

        # IRQ 亲和分析（简化版）
        local numa_span=0 numa_annotation=""
        read -r numa_span numa_annotation <<< "$(extract_irq_numa "$NFILE" "$iface")"

        # 网卡驱动（用于推断 irqname）
        local driver
        driver=$(extract_nic_driver "$NFILE" "$iface")

        # 构建单网卡 JSON 条目
        local entry
        entry=$(cat <<INNEREOF
    {
      "iface": "$iface",
      "has_ntuple": $has_ntuple,
      "ntuple_fixed": "$ntuple_fixed",
      "ntuple_enabled": "$ntuple_enabled",
      "max_q": ${max_q:-0},
      "cur_q": ${cur_q:-0},
      "rxpck": ${rxpck:-0},
      "rxkb": ${rxkb:-0},
      "multi_path": $multi_path,
      "recommend_enable": $recommend_enable,
      "numa_span": ${numa_span:-0},
      "numa_annotation": "$numa_annotation",
      "driver": "$driver"
    }
INNEREOF
)
        nic_json_entries+=("$entry")
    done

    # ---- 构建 JSON ----
    local nics_json=""
    local first=1
    for entry in "${nic_json_entries[@]}"; do
        ((first)) && first=0 || nics_json+=",$'\n'"
        nics_json+="$entry"
    done

    local pnics_json=""
    first=1
    for n in "${physical_nics[@]}"; do
        ((first)) && first=0 || pnics_json+=", "
        pnics_json+="\"$n\""
    done

    # ---- 调优参数推荐 ----
    # 收集 recommend_enable 网卡名（按 # 拼接）和最小 max_q、首个驱动
    local -a rec_ifnames=()
    local rec_min_max_q=""
    local rec_driver="unknown"
    for entry in "${nic_json_entries[@]}"; do
        if echo "$entry" | grep -q '"recommend_enable": true'; then
            local cur_iface cur_max_q cur_driver
            cur_iface=$(echo "$entry" | grep -oP '"iface":\s*"\K[^"]+' | head -1)
            cur_max_q=$(echo "$entry" | grep -oP '"max_q":\s*\K[0-9]+' | head -1)
            cur_driver=$(echo "$entry" | grep -oP '"driver":\s*"\K[^"]+' | head -1)
            [[ -n "$cur_iface" ]] && rec_ifnames+=("$cur_iface")
            if [[ -n "$cur_max_q" ]]; then
                if [[ -z "$rec_min_max_q" ]] || (( cur_max_q < rec_min_max_q )); then
                    rec_min_max_q="$cur_max_q"
                fi
            fi
            if [[ "$rec_driver" == "unknown" && -n "$cur_driver" ]]; then
                rec_driver="$cur_driver"
            fi
        fi
    done
    local rec_ifnames_str=""
    if ((${#rec_ifnames[@]} > 0)); then
        rec_ifnames_str=$(IFS='#'; echo "${rec_ifnames[*]}")
    fi

    # 调用推荐函数得到 key=value 列表
    local param_lines
    param_lines=$(compute_recommended_params \
        "$numa_nodes" "$oenetcls_name" \
        "$apps_redis" "$apps_nginx" "$apps_mysql" \
        "$rec_driver" "$rec_min_max_q")

    # 覆盖 ifnames（compute_recommended_params 留空，由 main 注入）
    local rp_module_name="" rp_ifnames="$rec_ifnames_str" rp_appname=""
    local rp_mode="" rp_strategy="" rp_debug="" rp_match_ip_flag=""
    local rp_irqname="" rp_rxq_multiplex_limit="" rp_lo_rps_policy="" rp_rps_policy=""
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        case "$key" in
            module_name)        rp_module_name="$value" ;;
            ifnames)            rp_ifnames="$value" ;;
            appname)            rp_appname="$value" ;;
            mode)               rp_mode="$value" ;;
            strategy)           rp_strategy="$value" ;;
            debug)              rp_debug="$value" ;;
            match_ip_flag)      rp_match_ip_flag="$value" ;;
            irqname)            rp_irqname="$value" ;;
            rxq_multiplex_limit) rp_rxq_multiplex_limit="$value" ;;
            lo_rps_policy)      rp_lo_rps_policy="$value" ;;
            rps_policy)         rp_rps_policy="$value" ;;
        esac
    done <<< "$param_lines"

    # 转义 appname 中的双引号（用于 JSON 字面量）
    local rp_appname_json
    rp_appname_json=$(json_escape "$rp_appname")

    cat > "$JSON_FILE" <<EOF
{
  "oenetcls": { "loaded": $oenetcls_loaded, "available": $oenetcls_available, "name": "$oenetcls_name" },
  "irqbalance": "$irqbalance",
  "irqbalance_service_name": "$irqbalance_svc",
  "numa_nodes": ${numa_nodes},
  "numa_cpu_map": ${numa_cpu_map},
  "interrupt_overview": "$interrupt_overview",
  "apps": { "redis": $apps_redis, "nginx": $apps_nginx, "mysql": $apps_mysql },
  "target_app_pid": $target_app_pid,
  "physical_nics": [${pnics_json}],
  "nic_details": [
${nics_json}
  ],
  "recommended_params": {
    "module_name": "$rp_module_name",
    "ifnames": "$rp_ifnames",
    "appname": "$rp_appname_json",
    "mode": $rp_mode,
    "strategy": $rp_strategy,
    "debug": $rp_debug,
    "match_ip_flag": $rp_match_ip_flag,
    "irqname": "$rp_irqname",
    "rxq_multiplex_limit": $rp_rxq_multiplex_limit,
    "lo_rps_policy": $rp_lo_rps_policy,
    "rps_policy": $rp_rps_policy
  }
}
EOF

    echo "preanalysis.json 已生成: $JSON_FILE ($(wc -c < "$JSON_FILE") bytes)"
}

main "$@"
