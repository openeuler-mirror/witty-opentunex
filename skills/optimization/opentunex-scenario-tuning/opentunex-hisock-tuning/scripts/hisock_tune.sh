#!/bin/bash
# hisock_tune.sh - hisock 网络加速调优辅助工具
# 用法:
#   hisock_tune.sh check                                          环境检查
#   hisock_tune.sh status                                         状态查询（加载前基线）
#   hisock_tune.sh compile <KERNEL_SRC>                           编译 hisock_cmd + bpf.o
#   hisock_tune.sh apply <bpf.o> <cgroup> <ports> <nic>           加载 eBPF 加速
#   hisock_tune.sh unload <cgroup> <nic>                          卸载 eBPF 加速
#   hisock_tune.sh guide                                          输出完整操作指南
#
# 说明: 本脚本由 agent 仅作只读检查与编译辅助；apply/unload 由用户主动执行。

set -euo pipefail

CONFIG_KEY="CONFIG_HISOCK"
HISOCK_SRC_RELATIVE="samples/bpf/hisock"
NF_HOOK_PATTERNS=("nf_hook_slow" "nf_hook_entries" "nf_hook_ops" "nf_hook")

print_section() {
    echo ""
    echo "=== $1 ==="
}

# 探测 CONFIG_HISOCK 是否启用（y/m/n）
detect_hisock_config() {
    local val="N/A"
    local sources=()
    if [[ -r /proc/config.gz ]]; then
        sources+=("zcat /proc/config.gz")
    fi
    if [[ -f "/boot/config-$(uname -r)" ]]; then
        sources+=("cat /boot/config-$(uname -r)")
    fi
    for src in "${sources[@]}"; do
        local cfg=""
        cfg=$(eval "$src" 2>/dev/null | grep -E "^${CONFIG_KEY}=" | head -1 || true)
        if [[ -n "$cfg" ]]; then
            val="${cfg#*=}"
            break
        fi
    done
    echo "$val"
}

# 探测符号是否存在（提示）
detect_nf_hook_symbols() {
    local found=""
    for pat in "${NF_HOOK_PATTERNS[@]}"; do
        if [[ -r /proc/kallsyms ]]; then
            if grep -E "[[:space:]]T ${pat}\$" /proc/kallsyms 2>/dev/null | head -1 >/dev/null; then
                found="${found}${pat},"
                continue
            fi
        fi
        if [[ -f /boot/System.map-$(uname -r) ]]; then
            if grep -E "[[:space:]]T ${pat}\$" /boot/System.map-$(uname -r) 2>/dev/null | head -1 >/dev/null; then
                found="${found}${pat},"
            fi
        fi
    done
    found="${found%,}"
    if [[ -n "$found" ]]; then
        echo "true|$found"
    else
        echo "false|"
    fi
}

# 探测编译工具链
detect_build_deps() {
    local missing=""
    for cmd in make gcc clang; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="${missing}${cmd},"
        fi
    done
    # 检查 kernel-devel / 内核头头
    if [[ ! -d "/lib/modules/$(uname -r)/build" ]] && [[ ! -d "/usr/src/kernels/$(uname -r)" ]]; then
        missing="${missing}kernel-devel,"
    fi
    missing="${missing%,}"
    if [[ -n "$missing" ]]; then
        echo "false|$missing"
    else
        echo "true|"
    fi
}

# 探测主要物理网卡
detect_main_nic() {
    local nic=""
    if command -v ip >/dev/null 2>&1; then
        nic=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -vE '^(lo|virbr|docker|veth|br-)' | head -1 || true)
    fi
    echo "${nic:-N/A}"
}

# 探测 cgroup 路径
detect_cgroup_path() {
    if [[ -d "/sys/fs/cgroup/perf_event" ]]; then
        echo "/sys/fs/cgroup/perf_event"
    elif [[ -d "/sys/fs/cgroup" ]]; then
        echo "/sys/fs/cgroup"
    else
        echo "N/A"
    fi
}

# 探测 hisock_cmd / bpf.o 是否已存在
detect_hisock_artifacts() {
    local paths=(
        "/usr/local/bin/hisock_cmd"
        "/usr/bin/hisock_cmd"
        "/opt/hisock/hisock_cmd"
        "./hisock_cmd"
    )
    for p in "${paths[@]}"; do
        if [[ -x "$p" ]]; then
            echo "found|$p"
            return
        fi
    done
    echo "not_found|"
}

# 探测 hisock_cmd 进程是否运行（用于判断是否已加载）
detect_hisock_running() {
    if ps -ef 2>/dev/null | grep -E "\bhisock_cmd\b" | grep -v grep | head -1 >/dev/null; then
        local line
        line=$(ps -ef 2>/dev/null | grep -E "\bhisock_cmd\b" | grep -v grep | head -1)
        echo "true|$line"
    else
        echo "false|"
    fi
}

# ---------- check ----------
do_check() {
    print_section "hisock 网络加速调优环境检查"

    local hisock_cfg
    hisock_cfg=$(detect_hisock_config)

    local is_nf hs_funcs
    IFS='|' read -r is_nf hs_funcs <<< "$(detect_nf_hook_symbols)"

    local has_deps missing
    IFS='|' read -r has_deps missing <<< "$(detect_build_deps)"

    local main_nic
    main_nic=$(detect_main_nic)

    local cgroup_path
    cgroup_path=$(detect_cgroup_path)

    local art_status art_path
    IFS='|' read -r art_status art_path <<< "$(detect_hisock_artifacts)"

    local pass=true

    echo "1. CONFIG_HISOCK 内核选项"
    if [[ "$hisock_cfg" == "y" ]]; then
        echo "   ✅ CONFIG_HISOCK=y（编译进内核）"
    elif [[ "$hisock_cfg" == "m" ]]; then
        echo "   ⚠️ CONFIG_HISOCK=m（编译为模块，需确认模块加载状态）"
        if command -v lsmod >/dev/null 2>&1 && lsmod 2>/dev/null | grep -qw hisock; then
            echo "      模块已加载"
        else
            echo "      模块未加载：modprobe hisock"
        fi
    else
        echo "   ❌ CONFIG_HISOCK=$hisock_cfg（未启用，hisock 加速不可用）"
        pass=false
    fi

    echo "2. nf_hook 符号检查（提示热点函数）"
    if [[ "$is_nf" == "true" ]]; then
        echo "   ✅ 内核导出符号存在：$hs_funcs"
    else
        echo "   ⚠️ 未找到 nf_hook_* 符号（可能被内联或未导出）"
    fi

    echo "3. 编译工具链"
    if [[ "$has_deps" == "true" ]]; then
        echo "   ✅ 工具链就绪（make/gcc/clang + kernel-devel）"
    else
        echo "   ❌ 缺失依赖：$missing"
        echo "      安装：yum install make gcc clang kernel-devel"
        pass=false
    fi

    echo "4. 网络环境"
    echo "   主网卡：${main_nic}"
    echo "   cgroup 路径：${cgroup_path}"

    echo "5. hisock 工具产物"
    if [[ "$art_status" == "found" ]]; then
        echo "   ✅ 已找到 hisock_cmd：$art_path"
    else
        echo "   ⚠️ 未找到 hisock_cmd 产物，需先编译"
    fi

    echo ""
    if [[ "$pass" == "true" ]]; then
        echo "环境检查通过：建议编译 hisock 工具并加载 eBPF 加速"
        echo "下一步：执行 $0 guide 查看操作指南"
        return 0
    else
        echo "环境检查未通过：当前系统不满足 hisock 调优前置条件"
        return 1
    fi
}

# ---------- status ----------
do_status() {
    print_section "hisock 状态查询（加载前基线）"

    echo "--- 内核版本 ---"
    uname -a

    echo ""
    echo "--- 内核选项 ---"
    echo "CONFIG_HISOCK=$(detect_hisock_config)"

    echo ""
    echo "--- hisock_cmd 进程 ---"
    local run_status run_line
    IFS='|' read -r run_status run_line <<< "$(detect_hisock_running)"
    if [[ "$run_status" == "true" ]]; then
        echo "   ✅ 已运行：$run_line"
    else
        echo "   ❌ 未运行"
    fi

    echo ""
    echo "--- 工具产物 ---"
    local art_status art_path
    IFS='|' read -r art_status art_path <<< "$(detect_hisock_artifacts)"
    echo "${art_status}: ${art_path:-N/A}"

    echo ""
    echo "--- 网络环境 ---"
    echo "主网卡: $(detect_main_nic)"
    echo "cgroup: $(detect_cgroup_path)"

    echo ""
    echo "--- nf_hook 符号 ---"
    local is_nf hs_funcs
    IFS='|' read -r is_nf hs_funcs <<< "$(detect_nf_hook_symbols)"
    echo "${is_nf}: ${hs_funcs:-未找到}"

    echo ""
    echo "提示：将以上输出作为加载前基线，便于加载后对比 nf_hook 占比变化。"
}

# ---------- compile ----------
do_compile() {
    local kernel_src="${1:-}"
    print_section "编译 hisock 工具与 bpf.o"

    if [[ -z "$kernel_src" ]]; then
        echo "用法: $0 compile <KERNEL_SRC>"
        echo "  KERNEL_SRC: 内核源码根目录（必须与运行内核版本一致）"
        return 1
    fi
    if [[ ! -d "$kernel_src" ]]; then
        echo "错误: 内核源码路径不存在：$kernel_src"
        return 1
    fi

    local hisock_dir="${kernel_src}/${HISOCK_SRC_RELATIVE}"
    if [[ ! -d "$hisock_dir" ]]; then
        echo "错误: 内核源码不含 ${HISOCK_SRC_RELATIVE}/ 目录"
        echo "  请确认："
        echo "    1) 内核源码版本 ≥ hisock 引入版本"
        echo "    2) 内核配置 CONFIG_HISOCK 已启用"
        return 1
    fi

    echo "1. 编译 libbpf（hisock 工具依赖）"
    if [[ -d "${kernel_src}/tools/lib/bpf" ]]; then
        make -C "${kernel_src}/tools/lib/bpf" -j"$(nproc)"
    else
        echo "   ⚠️ 未找到 tools/lib/bpf，跳过 libbpf 编译"
    fi

    echo ""
    echo "2. 编译 samples/bpf（生成 hisock_cmd + bpf.o）"
    make -C "${kernel_src}/samples/bpf" -j"$(nproc)"

    echo ""
    echo "3. 验证编译产物"
    if [[ -x "${hisock_dir}/hisock_cmd" ]]; then
        echo "   ✅ hisock_cmd: ${hisock_dir}/hisock_cmd"
    else
        echo "   ❌ hisock_cmd 编译失败"
        return 1
    fi
    if [[ -f "${hisock_dir}/bpf.o" ]]; then
        echo "   ✅ bpf.o: ${hisock_dir}/bpf.o"
    else
        echo "   ❌ bpf.o 编译失败"
        return 1
    fi

    echo ""
    echo "编译完成。下一步：使用 $0 apply 加载 eBPF 加速策略。"
}

# ---------- apply ----------
do_apply() {
    print_section "加载 hisock eBPF 加速策略"

    if [[ $# -lt 4 ]]; then
        echo "用法: $0 apply <BPF_O> <CGROUP_PATH> <PORTS> <NET_DEV>"
        echo "  BPF_O:        编译产物 bpf.o 路径"
        echo "  CGROUP_PATH:  cgroup 路径（如 /sys/fs/cgroup/perf_event/docker/abc）"
        echo "  PORTS:        端口或端口范围（如 6379 或 6379-6380）"
        echo "  NET_DEV:      网卡设备名（如 enp46s0f0np0）"
        return 1
    fi

    local bpf_o="$1"
    local cgroup_path="$2"
    local ports="$3"
    local net_dev="$4"

    # 校验产物
    local hisock_cmd_path=""
    local hisock_dir
    hisock_dir=$(dirname "$bpf_o")
    if [[ -x "${hisock_dir}/hisock_cmd" ]]; then
        hisock_cmd_path="${hisock_dir}/hisock_cmd"
    else
        # 探测系统路径
        for p in "/usr/local/bin/hisock_cmd" "/usr/bin/hisock_cmd" "/opt/hisock/hisock_cmd"; do
            if [[ -x "$p" ]]; then
                hisock_cmd_path="$p"
                break
            fi
        done
    fi
    if [[ -z "$hisock_cmd_path" ]]; then
        echo "错误: 未找到 hisock_cmd（请先执行 $0 compile）"
        return 1
    fi

    if [[ ! -f "$bpf_o" ]]; then
        echo "错误: bpf.o 不存在：$bpf_o"
        return 1
    fi

    if [[ ! -d "$cgroup_path" ]]; then
        echo "警告: cgroup 路径不存在：$cgroup_path（请确认路径）"
    fi

    # 校验网卡
    if [[ ! -d "/sys/class/net/${net_dev}" ]]; then
        echo "错误: 网卡设备不存在：${net_dev}"
        return 1
    fi

    echo "即将执行："
    echo "  $hisock_cmd_path -f \"$bpf_o\" -c \"$cgroup_path\" -p \"$ports\" -i \"$net_dev\""
    echo ""
    echo "⚠️ 本操作会修改 eBPF 程序加载状态，必须由用户在服务器上主动执行。"
    echo "   （本脚本由用户在前台触发；agent 不会通过 ssh 远程执行此命令）"
    echo ""

    # 实际加载（用户主动执行）
    "$hisock_cmd_path" -f "$bpf_o" -c "$cgroup_path" -p "$ports" -i "$net_dev"
    local rc=$?

    echo ""
    if [[ $rc -eq 0 ]]; then
        echo "✅ hisock 加速已加载"
        echo "   验证进程：ps aux | grep hisock_cmd"
    else
        echo "❌ hisock 加速加载失败（rc=$rc）"
        echo "   请检查："
        echo "    1) CONFIG_HISOCK=y 且内核模块已加载（lsmod | grep hisock）"
        echo "    2) cgroup 路径正确且存在"
        echo "    3) 网卡名正确（ip link show）"
        return $rc
    fi
}

# ---------- unload ----------
do_unload() {
    print_section "卸载 hisock eBPF 加速"

    if [[ $# -lt 2 ]]; then
        echo "用法: $0 unload <CGROUP_PATH> <NET_DEV>"
        echo "  CGROUP_PATH:  加载时的 cgroup 路径"
        echo "  NET_DEV:      加载时的网卡设备名"
        return 1
    fi

    local cgroup_path="$1"
    local net_dev="$2"

    # 探测 hisock_cmd 路径
    local hisock_cmd_path=""
    for p in "/usr/local/bin/hisock_cmd" "/usr/bin/hisock_cmd" "/opt/hisock/hisock_cmd"; do
        if [[ -x "$p" ]]; then
            hisock_cmd_path="$p"
            break
        fi
    done
    if [[ -z "$hisock_cmd_path" ]]; then
        echo "错误: 未找到 hisock_cmd（无法卸载）"
        return 1
    fi

    echo "即将执行："
    echo "  $hisock_cmd_path -u -c \"$cgroup_path\" -i \"$net_dev\""
    echo ""

    "$hisock_cmd_path" -u -c "$cgroup_path" -i "$net_dev"
    local rc=$?

    echo ""
    if [[ $rc -eq 0 ]]; then
        echo "✅ hisock 加速已卸载"
    else
        echo "❌ hisock 加速卸载失败（rc=$rc）"
        return $rc
    fi
}

# ---------- guide ----------
do_guide() {
    cat <<'EOF'
=== hisock 网络加速操作指南 ===

【背景】在网络收发包场景中，数据包经过 L2/L3 时 netfilter 钩子（连接跟踪、丢包策略、端口映射等）会引入额外开销。
当 nf_hook* 函数出现在热点调用栈中时，表明 netfilter 处理已成为瓶颈。hisock 通过 eBPF 程序在协议栈入口
将已建链目标数据流直接转发到 TCP 层（收包）或网卡设备（发包），绕过 L2/L3 的 netfilter 开销。

【前置条件】
- 内核启用 CONFIG_HISOCK=y（或 =m + 已加载）
- 内核源码（与运行内核版本一致）
- 编译工具链（make/gcc/clang/kernel-devel）

【操作步骤】

1. 环境检查
   bash scripts/hisock_tune.sh check

2. 编译 hisock 工具（用户主动执行）
   # 进入与运行内核版本一致的内核源码目录
   bash scripts/hisock_tune.sh compile <KERNEL_SRC>
   # 示例：
   bash scripts/hisock_tune.sh compile /usr/src/kernels/$(uname -r)
   # 产物路径: <KERNEL_SRC>/samples/bpf/hisock/{hisock_cmd,bpf.o}

3. 加载 eBPF 加速策略（用户主动执行）
   bash scripts/hisock_tune.sh apply <BPF_O> <CGROUP_PATH> <PORTS> <NET_DEV>
   # 示例：
   bash scripts/hisock_tune.sh apply /usr/src/kernels/$(uname -r)/samples/bpf/hisock/bpf.o \
       /sys/fs/cgroup/perf_event/docker/abc123 6379 enp46s0f0np0

4. 验证热点下降
   perf record -g -- <业务负载>
   perf report | grep nf_hook
   # 期望：nf_hook 占比 < 应用前基线

5. 业务监控验证
   - 观察网络 PPS / 吞吐 / 延迟改善
   - 注意 iptables 规则对非加速流量仍生效

【回滚步骤】

1. 卸载 eBPF 加速（用户主动执行）
   bash scripts/hisock_tune.sh unload <CGROUP_PATH> <NET_DEV>
   # 示例：
   bash scripts/hisock_tune.sh unload /sys/fs/cgroup/perf_event/docker/abc123 enp46s0f0np0

2. 或直接调用 hisock_cmd
   hisock_cmd -u -c <CGROUP_PATH> -i <NET_DEV>

【风险提示】
- eBPF 加载/卸载操作必须由用户在服务器本地主动执行
- agent 不会通过 ssh 远程加载 eBPF 程序
- 若加载失败可立即通过 unload 回滚，不会影响内核
- iptables 规则对非加速流量仍生效，hisock 仅加速指定 cgroup/端口/网卡流量

【验证建议】
- hisock_cmd 进程运行（ps aux | grep hisock_cmd）
- nf_hook 占比下降（perf report | grep nf_hook）
- 业务网络吞吐提升 10%-30%（业务相关）
EOF
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|status|compile|apply|unload|guide}"
    echo "  check                            - 环境检查"
    echo "  status                           - 状态查询（加载前基线）"
    echo "  compile <KERNEL_SRC>             - 编译 hisock_cmd + bpf.o"
    echo "  apply <bpf.o> <cgroup> <ports> <nic> - 加载 eBPF 加速"
    echo "  unload <cgroup> <nic>            - 卸载 eBPF 加速"
    echo "  guide                            - 输出完整操作指南"
    exit 1
fi

command=$1
shift

case "$command" in
    check)    do_check ;;
    status)   do_status ;;
    compile)  do_compile "$@" ;;
    apply)    do_apply "$@" ;;
    unload)   do_unload "$@" ;;
    guide)    do_guide ;;
    *)
        echo "未知命令: $command"
        exit 1
        ;;
esac