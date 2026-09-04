#!/bin/bash
# copy_user_tune.sh - copy_from_user 内核补丁调优辅助工具
# 用法:
#   copy_user_tune.sh check    环境检查（CPU架构 + partID + 内核选项 + 热点）
#   copy_user_tune.sh status   状态查询（输出补丁应用前基线）
#   copy_user_tune.sh guide    输出补丁应用 + 重编内核操作指南
#   copy_user_tune.sh verify   重启后验证（输出内核选项验证 + 业务表现建议）
#
# 说明: 本脚本仅做只读检查，不修改任何系统状态。
#       内核补丁应用与重编必须由用户在服务器本地手工完成。

set -euo pipefail

CONFIG_KEY="CONFIG_ARM64_COPY_FROM_USER_OPT"
KERNEL_CONFIG_PATHS=("/boot/config-$(uname -r)" "/proc/config.gz")
PATCH_URL_DEFAULT="https://atomgit.com/openeuler/kernel/pull/22481"
HOTSPOT_PATTERNS=("__arch_copy_to_user" "__arch_copy_from_user")
SUPPORTED_PARTID_THRESHOLD_DEC=3330  # 0xd02

print_section() {
    echo ""
    echo "=== $1 ==="
}

# 探测 CPU 架构
detect_arch() {
    local arch=""
    arch=$(uname -m 2>/dev/null || true)
    if [[ -z "$arch" && -f /proc/cpuinfo ]]; then
        arch=$(grep -iE '^[[:space:]]*Architecture' /proc/cpuinfo | head -1 | awk '{print $2}' || true)
    fi
    echo "${arch:-unknown}"
}

# 探测 CPU partID（十六进制）
detect_part_id_hex() {
    local v=""
    if [[ -f /proc/cpuinfo ]]; then
        v=$(grep -iE '^[[:space:]]*CPU part[[:space:]]*:' /proc/cpuinfo 2>/dev/null | head -1 | sed 's/^[[:space:]]*CPU part[[:space:]]*:[[:space:]]*//I' | tr '[:upper:]' '[:lower:]' || true)
    fi
    if [[ -z "$v" ]] && command -v lscpu >/dev/null 2>&1; then
        v=$(lscpu 2>/dev/null | grep -iE '^Model:' | head -1 | sed 's/^[[:space:]]*Model:[[:space:]]*//I' | tr '[:upper:]' '[:lower:]' || true)
    fi
    echo "${v:-N/A}"
}

# 十六进制转十进制
hex_to_dec() {
    local h="$1"
    h="${h#0x}"
    h="${h#0X}"
    local d
    d=$(awk -v h="$h" 'BEGIN { print strtonum("0x" h) }' 2>/dev/null)
    if [[ -n "$d" ]]; then
        echo "$d"
        return
    fi
    printf '%d' "0x${h^^}" 2>/dev/null || echo "0"
}

# 探测是否为 Hisilicon 支持 CPU
is_hisilicon_supported() {
    local part_hex="$1"
    if [[ "$part_hex" == "N/A" ]] || [[ -z "$part_hex" ]]; then
        echo "false|${part_hex}|0"
        return
    fi
    local dec
    dec=$(hex_to_dec "$part_hex")
    if [[ "$dec" -gt "$SUPPORTED_PARTID_THRESHOLD_DEC" ]]; then
        echo "true|${part_hex}|${dec}"
    else
        echo "false|${part_hex}|${dec}"
    fi
}

# 检测内核选项是否已编译
detect_config_option() {
    local cfg=""
    for p in "${KERNEL_CONFIG_PATHS[@]}"; do
        if [[ "$p" == *.gz ]] && [[ -f "$p" ]]; then
            cfg=$(zcat "$p" 2>/dev/null | grep -E "^${CONFIG_KEY}=" | head -1 || true)
        elif [[ -f "$p" ]]; then
            cfg=$(grep -E "^${CONFIG_KEY}=" "$p" 2>/dev/null | head -1 || true)
        fi
        if [[ -n "$cfg" ]]; then break; fi
    done
    echo "${cfg:-N/A}"
}

# 探测运行时热点函数（仅在可读取 perf 数据时尝试）
detect_hotspot_presence() {
    local found=""
    for pat in "${HOTSPOT_PATTERNS[@]}"; do
        # 从 /proc/kallsyms 中查找符号存在性（运行时）
        if [[ -r /proc/kallsyms ]]; then
            if grep -E "[[:space:]]${pat}\$" /proc/kallsyms 2>/dev/null | head -1 | grep -v ' T ' >/dev/null; then
                # 非文本段，可能是内联/未导出
                :
            fi
            if grep -E "[[:space:]]T ${pat}\$" /proc/kallsyms 2>/dev/null | head -1 >/dev/null; then
                found="${found}${pat},"
                continue
            fi
        fi
        # 退而求其次，搜索 System.map
        if [[ -f /boot/System.map-$(uname -r) ]]; then
            if grep -E "[[:space:]]T ${pat}\$" /boot/System.map-$(uname -r) 2>/dev/null | head -1 >/dev/null; then
                found="${found}${pat},"
                continue
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

# ---------- check ----------
do_check() {
    print_section "copy_from_user 内核补丁调优环境检查"

    local arch part_hex is_hs part_hex_out part_dec is_hs_out
    arch=$(detect_arch)
    part_hex=$(detect_part_id_hex)
    IFS='|' read -r is_hs part_hex_out part_dec <<< "$(is_hisilicon_supported "$part_hex")"

    local is_arm64=false
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        is_arm64=true
    fi

    local cfg
    cfg=$(detect_config_option)

    local is_hotspot hs_funcs
    IFS='|' read -r is_hotspot hs_funcs <<< "$(detect_hotspot_presence)"

    local pass=true

    echo "1. CPU 架构检测"
    if [[ "$is_arm64" == "true" ]]; then
        echo "   ✅ 当前为 ARM64 架构（arch=$arch）"
    else
        echo "   ❌ 当前非 ARM64 架构（arch=$arch）"
        pass=false
    fi

    echo "2. Hisilicon 支持 CPU 检测"
    if [[ "$is_hs" == "true" ]]; then
        echo "   ✅ 当前为 Hisilicon 支持 CPU（partID=$part_hex_out, 十进制=$part_dec > 3330）"
    else
        echo "   ❌ 当前 CPU 非 Hisilicon 支持型号（partID=$part_hex_out, 十进制=$part_dec ≤ 3330）"
        pass=false
    fi

    echo "3. 运行时符号检查（提示热点函数是否可被采集）"
    if [[ "$is_hotspot" == "true" ]]; then
        echo "   ✅ 内核导出符号存在：$hs_funcs"
    else
        echo "   ⚠️ 未在运行时符号表中找到 __arch_copy_to_user/__arch_copy_from_user（可能被内联）"
        echo "      提示：性能影响需通过 perf 采集热点函数占比确认"
    fi

    echo "4. 内核编译选项检测"
    if [[ "$cfg" == "${CONFIG_KEY}=y" ]]; then
        echo "   ✅ 内核已编译 CONFIG_ARM64_COPY_FROM_USER_OPT=y（已应用补丁）"
    elif [[ "$cfg" == "${CONFIG_KEY}=n" || "$cfg" == "${CONFIG_KEY}=m" ]]; then
        echo "   ⚠️ 内核未启用该选项（$cfg），需重编内核启用"
    else
        echo "   ⚠️ 内核选项不可读（$cfg，可能运行的内核未导出 /proc/config.gz）"
        echo "      提示：建议重编内核并启用 CONFIG_ARM64_COPY_FROM_USER_OPT=y"
    fi

    echo ""
    if [[ "$pass" == "true" ]]; then
        echo "环境检查通过：建议应用内核补丁 + 启用 CONFIG_ARM64_COPY_FROM_USER_OPT"
        echo "下一步：执行 $0 guide 查看补丁应用与重编操作指南"
        return 0
    else
        echo "环境检查未通过：当前系统不满足 copy_from_user 调优前置条件"
        return 1
    fi
}

# ---------- status ----------
do_status() {
    print_section "copy_from_user 状态查询（补丁应用前后基线对比）"

    echo "--- 内核版本 ---"
    uname -a

    echo ""
    echo "--- CPU 架构与 partID ---"
    echo "arch:    $(detect_arch)"
    local part_hex
    part_hex=$(detect_part_id_hex)
    echo "partID:  ${part_hex}"
    if [[ "$part_hex" != "N/A" ]]; then
        local dec
        dec=$(hex_to_dec "$part_hex")
        echo "         (十进制=${dec})"
    fi

    echo ""
    echo "--- 内核编译选项 ---"
    echo "$(detect_config_option)"

    echo ""
    echo "--- 当前内核是否已加载补丁（CONFIG_ARM64_COPY_FROM_USER_OPT=y 视作已加载） ---"
    local cfg
    cfg=$(detect_config_option)
    if [[ "$cfg" == "${CONFIG_KEY}=y" ]]; then
        echo "   ✅ 补丁已生效"
    else
        echo "   ❌ 补丁尚未生效（需应用 PR #22481 并重编内核）"
    fi

    echo ""
    echo "--- 运行时符号 ---"
    local is_hotspot hs_funcs
    IFS='|' read -r is_hotspot hs_funcs <<< "$(detect_hotspot_presence)"
    echo "热点符号：${hs_funcs:-未找到（可能被内联）}"

    echo ""
    echo "提示：将以上输出作为补丁应用前的基线，便于应用后对比。"
}

# ---------- guide ----------
do_guide() {
    cat <<'EOF'
=== copy_from_user 内核补丁应用 + 重编内核操作指南 ===

【背景】在大规模数据拷贝场景（网络收发包、文件 I/O）中，__arch_copy_from_user 是内核关键热路径。
当前内核使用 ldtr 单寄存器指令逐字节或逐字节搬运，在 Hisilicon ARM64 CPU 上无法充分利用加载指令带宽。
应用优化补丁 PR #22481 后：
- Hisilicon CPU（LINXICORE9100、HIP11、HIP12，partID > 0xd02）：大拷贝（≥4KB）切换到 ldp 双字加载
- 支持 FEAT_LSUI 的 CPU（ARMv8.9）：直接使用 ldtp 非特权双字加载，size 不再受限

【补丁地址】
https://atomgit.com/openeuler/kernel/pull/22481

【操作步骤】

1. 拉取 openEuler 内核源码
   git clone https://gitee.com/openeuler/kernel.git
   cd kernel
   git checkout <目标内核版本分支>      # 与当前生产内核版本一致

2. 应用 PR #22481 补丁（若尚未合入主干）
   curl -L https://atomgit.com/openeuler/kernel/pull/22481.patch -o /tmp/22481.patch
   git am /tmp/22481.patch
   # 若提示冲突需手动解决冲突（参考 patch 上下文）

3. 设置内核编译选项
   # 方法 A：直接编辑 .config
   echo "CONFIG_ARM64_COPY_FROM_USER_OPT=y" >> .config

   # 方法 B：通过 menuconfig
   make menuconfig
   # 路径: General setup → Kernel Features → Enable ARM64 copy from user optimization

   # 方法 C：通过 oldconfig 自动应用 .config 变更
   make oldconfig

4. 编译并安装内核
   make -j$(nproc)              # 编译（耗时较长，建议 nproc 全核并行）
   make modules_install         # 安装内核模块到 /lib/modules/$(uname -r)+xxx
   make install                 # 安装内核到 /boot 并更新 grub 启动菜单
   # 或构建 rpm 包：make rpm-pkg，安装生成的 rpm 后重启

5. 重启系统加载新内核
   reboot
   # 重启后在 grub 菜单确认选择了新内核（部分场景需手工选择）

6. 重启后回到操作系统
   ./copy-user-tuning/tuning.sh verify

【回滚步骤】

1. 重启服务器，在 grub 启动菜单（启动时按 Esc/Shift）选择旧内核
2. 或在旧内核环境下：
   a) 重新编译不含 PR #22481 / CONFIG_ARM64_COPY_FROM_USER_OPT 的内核
   b) make install 安装新内核
   c) reboot

【风险提示】
- 涉及内核重编与系统重启，请在业务低峰期执行
- 内核补丁应用与重编不可由 agent 远程代为执行，必须由内核维护工程师操作
- 内核重编可能需要 30-60 分钟（取决于 CPU 核数和配置）
- 强烈建议先在测试环境验证补丁稳定性

【验证建议】
- 重启后内核版本保持不变（uname -r 检查）
- grep CONFIG_ARM64_COPY_FROM_USER_OPT /boot/config-$(uname -r) 显示 =y
- perf 抓取热点，__arch_copy_to_user / __arch_copy_from_user 内出现 ldp/ldtp 指令
- 业务监控 QPS / 延迟改善
EOF
}

# ---------- verify ----------
do_verify() {
    print_section "copy_from_user 重启后验证"

    local arch part_hex
    arch=$(detect_arch)
    part_hex=$(detect_part_id_hex)

    echo "1. CPU 架构与 partID 未变"
    echo "   arch=${arch}, partID=${part_hex}"

    echo "2. 内核编译选项验证"
    local cfg
    cfg=$(detect_config_option)
    if [[ "$cfg" == "${CONFIG_KEY}=y" ]]; then
        echo "   ✅ 内核已编译 CONFIG_ARM64_COPY_FROM_USER_OPT=y"
    else
        echo "   ❌ 内核未启用该选项（当前：$cfg）"
        echo "      请按 guide 操作重新编译内核"
        return 1
    fi

    echo "3. 运行时指令替换验证"
    echo "   采集业务负载并查看 __arch_copy 函数内指令："
    echo "     perf record -g -- <业务负载>"
    echo "     perf script | grep -E '__arch_copy_(to|from)_user' | grep -E 'ldp|ldtp'"
    echo "   若出现 ldp/ldtp 指令 → 优化路径已生效"

    echo "4. 业务表现验证建议"
    echo "   - 观察业务监控指标：QPS / 响应时间 / 错误率（与重启前对比）"
    echo "   - 量化大块 IO 性能（压测 read/write）："
    echo "       fio -ioengine=libaio -bs=64k -size=1g -rw=randrw -filename=/tmp/test"
    echo "   - 若有性能回归（QPS 下降 > 10%），请按 guide 中的回滚步骤恢复"

    echo ""
    echo "提示：最终确认以业务指标和 ldp/ldtp 指令出现为准。"
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|status|guide|verify}"
    echo "  check  - 环境检查（CPU架构 + partID + 内核选项 + 热点）"
    echo "  status - 状态查询（输出补丁应用前基线）"
    echo "  guide  - 输出补丁应用 + 重编内核操作指南"
    echo "  verify - 重启后验证（输出内核选项验证 + 业务表现建议）"
    exit 1
fi

command=$1
shift

case "$command" in
    check)    do_check ;;
    status)   do_status ;;
    guide)    do_guide ;;
    verify)   do_verify ;;
    *)
        echo "未知命令: $command"
        exit 1
        ;;
esac