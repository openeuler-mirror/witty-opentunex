#!/bin/bash
# multi_net_path_tune.sh - 网卡多路径调优工具
# 用法:
#   multi_net_path_tune.sh check          检查环境
#   multi_net_path_tune.sh backup         备份当前状态
#   multi_net_path_tune.sh apply <ifnames> <appname> [mode strategy debug match_ip_flag irqname rxq_multiplex_limit lo_rps_policy rps_policy]
#                                         应用调优（全部参数可选，未传则使用 defaults）
#   multi_net_path_tune.sh status         查看当前状态
#   multi_net_path_tune.sh rollback       用最近一次备份回滚
#
# 完整 modprobe 参数顺序（与模块参数一致）：
#   mode, appname, ifname, strategy, debug, match_ip_flag, irqname,
#   rxq_multiplex_limit, lo_rps_policy, rps_policy

set -euo pipefail

BACKUP_DIR="/var/tmp/multi_net_path_backups"
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%s).lst"

# 网卡多路径特性模块名。
# 大多数内核命名为 oenetcls；部分内核（如特定厂商定制）命名为 venetcls。
# 运行时通过 resolve_module_name 自动识别并缓存到 MODULE_NAME。
MODULE_NAME=""

# 按优先级识别 oenetcls/venetcls 模块名并缓存到 MODULE_NAME
# 优先匹配已加载的模块；未加载时匹配 modinfo 可用的模块；都失败则默认 oenetcls
resolve_module_name() {
    if [ -n "$MODULE_NAME" ]; then
        return
    fi

    local name
    # 1) 优先匹配已加载模块（/sys/module 与 lsmod）
    for name in oenetcls venetcls; do
        if [ -d "/sys/module/${name}" ] || lsmod 2>/dev/null | grep -q "^${name} "; then
            MODULE_NAME="$name"
            return
        fi
    done

    # 2) 未加载时按顺序匹配 modinfo 可用的模块
    for name in oenetcls venetcls; do
        if modinfo "$name" &>/dev/null; then
            MODULE_NAME="$name"
            return
        fi
    done

    # 3) 默认 oenetcls（脚本将依据 unavailable 状态终止调优）
    MODULE_NAME="oenetcls"
}

# 返回当前模块的统计文件路径（/proc/net/<MODULE_NAME>/stats）
get_stats_path() {
    resolve_module_name
    echo "/proc/net/${MODULE_NAME}/stats"
}

init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

get_oenetcls_state() {
    resolve_module_name
    local name="$MODULE_NAME"

    # 方式一：检查 /sys/module/<name> 目录是否存在（最可靠）
    if [ -d "/sys/module/${name}" ]; then
        echo "loaded"
        return
    fi

    # 方式二：lsmod 查找
    if lsmod 2>/dev/null | grep -q "^${name} "; then
        echo "loaded"
        return
    fi

    # 方式三：modinfo 检查模块是否可用
    if modinfo "$name" &>/dev/null; then
        echo "available"
        return
    fi

    echo "unavailable"
}

get_irqbalance_state() {
    if systemctl is-active irqbalance 2>/dev/null | grep -q '^active$'; then
        echo "active"
    else
        echo "inactive"
    fi
}

get_physical_nics() {
    local nics=""
    for iface_dir in /sys/class/net/*; do
        local iface
        iface=$(basename "$iface_dir")
        [ "$iface" = "lo" ] && continue
        [[ "$iface" =~ ^(veth|docker|br-|virbr|cali|flannel|tunl|kube-) ]] && continue
        local dev_path
        dev_path=$(readlink -f "$iface_dir" 2>/dev/null || echo "")
        if echo "$dev_path" | grep -q '/virtual/'; then
            continue
        fi
        nics="${nics} ${iface}"
    done
    echo "$nics" | xargs
}

get_ntuple_on_count() {
    local count=0
    for iface_dir in /sys/class/net/*; do
        local iface
        iface=$(basename "$iface_dir")
        [ "$iface" = "lo" ] && continue
        [[ "$iface" =~ ^(veth|docker|br-|virbr|cali|flannel|tunl|kube-) ]] && continue
        if command -v ethtool &>/dev/null; then
            if ethtool -k "$iface" 2>/dev/null | grep -qi 'ntuple-filters: on'; then
                ((count++))
            fi
        fi
    done
    echo "$count"
}

get_numa_node_count() {
    if command -v numactl &>/dev/null; then
        numactl --hardware 2>/dev/null | grep -c '^node ' || echo "1"
    else
        lscpu 2>/dev/null | grep "NUMA node(s)" | awk '{print $3}' || echo "1"
    fi
}

# ---------- check ----------
do_check() {
    local errors=0

    echo "=== 环境检查 ==="

    # 必须在父 shell 中解析模块名（get_oenetcls_state 跑在子 shell，
    # 内部对 MODULE_NAME 的赋值不会回传）
    resolve_module_name
    local oenetcls_state
    oenetcls_state=$(get_oenetcls_state)
    echo "${MODULE_NAME} 模块: ${oenetcls_state}"
    if [ "$oenetcls_state" = "unavailable" ]; then
        echo "错误: ${MODULE_NAME} 模块不可用，内核不支持" >&2
        echo "       已依次检测: oenetcls 与 venetcls，均不可用" >&2
        errors=1
    fi

    local irqbalance_state
    irqbalance_state=$(get_irqbalance_state)
    echo "irqbalance 状态: ${irqbalance_state}"

    local physical_nics
    physical_nics=$(get_physical_nics)
    echo "物理网卡: ${physical_nics:-无}"

    local ntuple_count
    ntuple_count=$(get_ntuple_on_count)
    echo "ntuple 支持网卡数: ${ntuple_count}"

    local numa_nodes
    numa_nodes=$(get_numa_node_count)
    echo "NUMA 节点数: ${numa_nodes}"

    if [ "$errors" -gt 0 ]; then
        exit 1
    fi
    echo "环境检查通过"
}

# ---------- backup ----------
do_backup() {
    init_backup_dir
    echo "备份当前状态到 ${BACKUP_FILE}"

    # 必须在父 shell 中解析模块名
    resolve_module_name
    local oenetcls_state
    oenetcls_state=$(get_oenetcls_state)
    local irqbalance_state
    irqbalance_state=$(get_irqbalance_state)

    echo "oenetcls_state=${oenetcls_state}" > "$BACKUP_FILE"
    echo "irqbalance_state=${irqbalance_state}" >> "$BACKUP_FILE"
    # 记录实际使用的模块名（兼容旧备份文件无此字段）
    echo "module_name=${MODULE_NAME}" >> "$BACKUP_FILE"

    if [ "$oenetcls_state" = "loaded" ]; then
        local ifname_info
        ifname_info=$(cat "/sys/module/${MODULE_NAME}/parameters/ifname" 2>/dev/null || echo "")
        local appname_info
        appname_info=$(cat "/sys/module/${MODULE_NAME}/parameters/appname" 2>/dev/null || echo "")
        echo "ifname=${ifname_info}" >> "$BACKUP_FILE"
        echo "appname=${appname_info}" >> "$BACKUP_FILE"
    fi

    echo "  ${MODULE_NAME} 状态: ${oenetcls_state}"
    echo "  irqbalance 状态: ${irqbalance_state}"
    echo "备份完成"
}

# ---------- apply ----------
# 参数（按位置传，缺省使用模块默认值）:
#   $1 ifnames                  必填，# 拼接的网卡列表
#   $2 appname                  可选，目标应用名（# 拼接多应用），空 = 全局使能
#   $3 mode                     可选，0=ntuple, 1=flow（默认 0）
#   $4 strategy                 可选，0/1/2/3（默认 0）
#   $5 debug                    可选，0/1（默认 0）
#   $6 match_ip_flag            可选，0/1（默认 0）
#   $7 irqname                  可选，中断描述匹配串（默认 comp）
#   $8 rxq_multiplex_limit      可选，1~64（默认 1）
#   $9 lo_rps_policy            可选，0/1/2（默认 0）
#   ${10} rps_policy            可选，0/1/2（默认 0）
do_apply() {
    local ifnames="${1:-}"
    local appname="${2:-}"
    local mode="${3:-}"
    local strategy="${4:-}"
    local debug="${5:-}"
    local match_ip_flag="${6:-}"
    local irqname="${7:-}"
    local rxq_multiplex_limit="${8:-}"
    local lo_rps_policy="${9:-}"
    local rps_policy="${10:-}"

    if [ -z "$ifnames" ]; then
        echo "错误: 缺少网卡参数 (ifname)" >&2
        echo "用法: $0 apply <ifnames> <appname> [mode strategy debug match_ip_flag irqname rxq_multiplex_limit lo_rps_policy rps_policy]" >&2
        echo "示例: $0 apply \"eth0#eth1\" redis-server 0 0 0 0 comp 1 0 0" >&2
        echo "      $0 apply \"eth0#eth1\"           \"\" # 对所有应用使能" >&2
        exit 1
    fi

    if [ -z "$appname" ]; then
        echo "注意: 未指定应用名，将对所有应用使能网卡多路径特性"
    fi

    # 必须在父 shell 中解析模块名
    resolve_module_name
    local oenetcls_state
    oenetcls_state=$(get_oenetcls_state)

    if [ "$oenetcls_state" = "loaded" ]; then
        echo "警告: ${MODULE_NAME} 模块已加载，跳过加载步骤"
        echo "当前参数:"
        cat "/sys/module/${MODULE_NAME}/parameters/ifname" 2>/dev/null || echo "  无法读取 ifname"
        cat "/sys/module/${MODULE_NAME}/parameters/appname" 2>/dev/null || echo "  无法读取 appname"
        exit 0
    fi

    do_backup

    echo "=== 应用调优 ==="

    local irqbalance_state
    irqbalance_state=$(get_irqbalance_state)

    echo "1. 停止 irqbalance"
    if [ "$irqbalance_state" = "active" ]; then
        systemctl stop irqbalance 2>/dev/null || echo "  警告: 无法停止 irqbalance"
        echo "  irqbalance 已停止"
    else
        echo "  irqbalance 未运行，跳过"
    fi

    # 组装 modprobe 命令参数（仅传非空的，以尊重模块默认值）
    local -a mp_args=("ifname=${ifnames}")
    [ -n "$appname" ] && mp_args+=("appname=${appname}")
    [ -n "$mode" ] && mp_args+=("mode=${mode}")
    [ -n "$strategy" ] && mp_args+=("strategy=${strategy}")
    [ -n "$debug" ] && mp_args+=("debug=${debug}")
    [ -n "$match_ip_flag" ] && mp_args+=("match_ip_flag=${match_ip_flag}")
    [ -n "$irqname" ] && mp_args+=("irqname=${irqname}")
    [ -n "$rxq_multiplex_limit" ] && mp_args+=("rxq_multiplex_limit=${rxq_multiplex_limit}")
    [ -n "$lo_rps_policy" ] && mp_args+=("lo_rps_policy=${lo_rps_policy}")
    [ -n "$rps_policy" ] && mp_args+=("rps_policy=${rps_policy}")

    echo "2. 加载 ${MODULE_NAME} 模块 (参数: ${mp_args[*]})"
    local load_ok=0
    if modprobe "${MODULE_NAME}" "${mp_args[@]}" 2>&1; then
        load_ok=1
    fi

    if [ "$load_ok" -eq 1 ]; then
        echo "  ${MODULE_NAME} 模块加载成功"
        # 验证加载后状态
        local verify_state
        verify_state=$(get_oenetcls_state)
        if [ "$verify_state" != "loaded" ]; then
            echo "  警告: 状态检测异常，当前状态=${verify_state}" >&2
        fi
    else
        echo "错误: ${MODULE_NAME} 模块加载失败" >&2
        # 重新组装便于手工复制（带引号）
        local quoted_args=""
        for a in "${mp_args[@]}"; do
            case "$a" in
                ifname=*|appname=*|irqname=*) quoted_args+=" ${a%%=*}=\"${a#*=}\"" ;;
                *) quoted_args+=" $a" ;;
            esac
        done
        echo "尝试手动加载: modprobe ${MODULE_NAME}${quoted_args}" >&2
        exit 1
    fi

    echo "调优已生效"
}

# ---------- status ----------
do_status() {
    echo "=== 当前状态 ==="

    # 必须在父 shell 中解析模块名
    resolve_module_name
    local oenetcls_state
    oenetcls_state=$(get_oenetcls_state)
    echo "${MODULE_NAME} 模块: ${oenetcls_state}"

    if [ "$oenetcls_state" = "loaded" ]; then
        echo "模块参数:"
        cat "/sys/module/${MODULE_NAME}/parameters/ifname" 2>/dev/null | awk '{print "  ifname=" $0}' || echo "  ifname=无法读取"
        cat "/sys/module/${MODULE_NAME}/parameters/appname" 2>/dev/null | awk '{print "  appname=" $0}' || echo "  appname=无法读取"

        local stats_path
        stats_path=$(get_stats_path)
        if [ -f "$stats_path" ]; then
            echo "统计信息:"
            cat "$stats_path" 2>/dev/null || echo "  无法读取"
        fi
    fi

    local irqbalance_state
    irqbalance_state=$(get_irqbalance_state)
    echo "irqbalance 状态: ${irqbalance_state}"

    echo ""
    echo "--- 网卡中断分布 ---"
    if [ -f /proc/interrupts ]; then
        grep -E '^\s+[0-9]+:' /proc/interrupts 2>/dev/null | grep -iE 'eth|ens|enp' | head -10 || echo "  无 eth 网卡中断信息"
    fi

    echo ""
    echo "--- NUMA 拓扑 ---"
    if command -v numactl &>/dev/null; then
        numactl --hardware 2>/dev/null || echo "  不可用"
    else
        lscpu 2>/dev/null | grep "NUMA" || echo "  不可用"
    fi
}

# ---------- rollback ----------
do_rollback() {
    local latest
    latest=$(ls -t "${BACKUP_DIR}"/backup_*.lst 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        echo "错误: 未找到备份文件" >&2
        exit 1
    fi
    echo "使用备份文件: ${latest}"

    local oenetcls_state
    oenetcls_state=$(grep ^oenetcls_state= "$latest" | cut -d= -f2-)
    local irqbalance_state
    irqbalance_state=$(grep ^irqbalance_state= "$latest" | cut -d= -f2-)
    # 兼容旧备份文件：没有 module_name 字段时默认 oenetcls
    local backup_module_name
    backup_module_name=$(grep ^module_name= "$latest" | cut -d= -f2-)
    if [ -z "$backup_module_name" ]; then
        backup_module_name="oenetcls"
    fi

    # 以本机当前实际加载的模块名进行回滚（覆盖 oenetcls/venetcls 两种命名）
    resolve_module_name
    local current_oenetcls
    current_oenetcls=$(get_oenetcls_state)

    echo "1. 卸载 ${MODULE_NAME} 模块（当前状态: ${current_oenetcls}，备份记录: ${backup_module_name}）"
    if [ "$current_oenetcls" = "loaded" ]; then
        # 检查模块引用计数
        local refcnt
        refcnt=$(cat "/sys/module/${MODULE_NAME}/refcnt" 2>/dev/null || echo "0")
        echo "  模块引用计数: ${refcnt}"

        local unloaded=0
        # 方式一：尝试 rmmod
        if rmmod "${MODULE_NAME}" 2>/dev/null; then
            unloaded=1
            echo "  ${MODULE_NAME} 模块已卸载 (rmmod)"
        fi

        # 方式二：modprobe -r（处理依赖）
        if [ "$unloaded" -eq 0 ]; then
            if modprobe -r "${MODULE_NAME}" 2>/dev/null; then
                unloaded=1
                echo "  ${MODULE_NAME} 模块已卸载 (modprobe -r)"
            fi
        fi

        # 方式三：force rmmod
        if [ "$unloaded" -eq 0 ]; then
            echo "  尝试强制卸载..."
            if rmmod -f "${MODULE_NAME}" 2>/dev/null; then
                unloaded=1
                echo "  ${MODULE_NAME} 模块已强制卸载 (rmmod -f)"
            fi
        fi

        # 最终验证
        local final_state
        final_state=$(get_oenetcls_state)
        if [ "$final_state" != "loaded" ]; then
            echo "  ✓ 卸载成功，当前状态: ${final_state}"
        else
            echo "  错误: 无法卸载 ${MODULE_NAME} 模块，请手动卸载" >&2
            echo "  尝试: sudo rmmod ${MODULE_NAME} 或 sudo modprobe -r ${MODULE_NAME}" >&2
        fi
    else
        echo "  ${MODULE_NAME} 未加载，跳过"
    fi

    echo "2. 恢复 irqbalance 状态 = ${irqbalance_state}"
    if [ "$irqbalance_state" = "active" ]; then
        systemctl start irqbalance 2>/dev/null || echo "  警告: 无法启动 irqbalance"
        echo "  irqbalance 已启动"
    else
        echo "  irqbalance 保留停止状态"
    fi

    echo "回滚完成"
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|backup|apply|status|rollback} [参数...]"
    echo ""
    echo "命令:"
    echo "  check                                                检查调优环境"
    echo "  backup                                               备份当前状态"
    echo "  apply <ifnames> <appname> [mode strategy debug match_ip_flag irqname rxq_multiplex_limit lo_rps_policy rps_policy]"
    echo "                                                       应用调优"
    echo "                                                       示例: apply \"eth0#eth1\" redis-server 0 0 0 0 comp 1 0 0"
    echo "                                                       例2: apply \"eth0#eth1\" \"\"      # 对所有应用使能"
    echo "  status                                               查看当前状态"
    echo "  rollback                                             用最近一次备份回滚"
    exit 1
fi

command=$1
shift

case "$command" in
    check)    do_check ;;
    backup)   do_backup ;;
    apply)    do_apply "$@" ;;
    status)   do_status ;;
    rollback) do_rollback ;;
    *)
        echo "未知命令: $command"
        echo "可用命令: check, backup, apply, status, rollback"
        exit 1
        ;;
esac