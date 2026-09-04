#!/bin/bash
# btb_tune.sh - BTB/TidCMP 调优辅助工具
# 用法:
#   btb_tune.sh check    环境检查（CPU型号 + 关键进程）
#   btb_tune.sh status   状态查询（输出 BIOS 设置工单所需证据）
#   btb_tune.sh guide    输出 BIOS 设置操作指南
#   btb_tune.sh verify   重启后验证（输出业务表现验证建议）
#
# 说明: 本脚本仅做只读检查，不修改任何系统状态。
#       BIOS 设置必须由用户在服务器本地手工完成。

set -euo pipefail

KUNPENG_KEYWORDS=("Kunpeng" "kunpeng" "920")
KEY_PROCESS_PATTERNS=("redis-server" "mysqld" "mariadbd")

print_section() {
    echo ""
    echo "=== $1 ==="
}

# 探测 CPU 型号
detect_kunpeng() {
    if command -v lscpu >/dev/null 2>&1; then
        if lscpu 2>/dev/null | grep -qiE 'Kunpeng|kunpeng'; then
            echo "true"
            return
        fi
    fi
    if [[ -f /proc/cpuinfo ]]; then
        if grep -qiE 'Kunpeng|kunpeng' /proc/cpuinfo 2>/dev/null; then
            echo "true"
            return
        fi
    fi
    echo "false"
}

# 探测是否为 920 新型号（dmidecode ID 以 "20 D0" 开头）
detect_920_new_model() {
    local part_id=""
    if command -v dmidecode >/dev/null 2>&1; then
        part_id=$(dmidecode -t processor 2>/dev/null | grep -iE '^\s*ID:' | head -1 | sed 's/^[[:space:]]*ID:[[:space:]]*//I' | sed 's/[[:space:]]*$//' || true)
    fi
    if [[ -n "$part_id" ]] && echo "$part_id" | grep -qiE '^20[[:space:]]+D0'; then
        echo "true|$part_id"
    else
        echo "false|${part_id:-N/A}"
    fi
}

# 探测关键进程
detect_key_processes() {
    local found=""
    for pat in "${KEY_PROCESS_PATTERNS[@]}"; do
        if ps -ef 2>/dev/null | grep -E "\b${pat}\b" | grep -vq grep; then
            found="${found}${pat},"
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
    print_section "BTB/TidCMP 调优环境检查"

    local is_kunpeng is_920 part_id is_key key_procs
    is_kunpeng=$(detect_kunpeng)
    IFS='|' read -r is_920 part_id <<< "$(detect_920_new_model)"
    IFS='|' read -r is_key key_procs <<< "$(detect_key_processes)"

    local pass=true

    echo "1. CPU 平台检测"
    if [[ "$is_kunpeng" == "true" ]]; then
        echo "   ✅ 当前为鲲鹏平台"
    else
        echo "   ❌ 当前非鲲鹏平台（BTB/TidCMP 仅鲲鹏有效）"
        pass=false
    fi

    echo "2. CPU 型号检测"
    if [[ "$is_920" == "true" ]]; then
        echo "   ✅ 当前为鲲鹏 920 新型号（dmidecode ID=$part_id）"
    else
        echo "   ❌ 当前 CPU 型号不在 TidCMP 优化支持列表（dmidecode ID=$part_id）"
        pass=false
    fi

    echo "3. 关键进程检测"
    if [[ "$is_key" == "true" ]]; then
        echo "   ✅ 检测到关键进程：$key_procs"
    else
        echo "   ❌ 未检测到 redis-server/mysqld 关键进程"
        pass=false
    fi

    echo ""
    if [[ "$pass" == "true" ]]; then
        echo "环境检查通过：建议在 BIOS 中禁用 TidCMP"
        echo "下一步：执行 $0 guide 查看 BIOS 设置操作指南"
        return 0
    else
        echo "环境检查未通过：当前系统不满足 BTB/TidCMP 调优前置条件"
        return 1
    fi
}

# ---------- status ----------
do_status() {
    print_section "BTB/TidCMP 状态查询（BIOS 设置工单所需证据）"

    echo "--- CPU 信息 ---"
    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep -iE 'Model name|Vendor ID|Architecture' | head -5
    fi

    echo ""
    echo "--- dmidecode processor ID ---"
    if command -v dmidecode >/dev/null 2>&1; then
        dmidecode -t processor 2>/dev/null | grep -iE '^\s*ID:' | head -1
    else
        echo "dmidecode 命令不可用"
    fi

    echo ""
    echo "--- 关键进程 ---"
    for pat in "${KEY_PROCESS_PATTERNS[@]}"; do
        local lines
        lines=$(ps -ef 2>/dev/null | grep -E "\b${pat}\b" | grep -v grep || true)
        if [[ -n "$lines" ]]; then
            echo "$lines" | head -5
        fi
    done

    echo ""
    echo "提示：将以上输出附在 BIOS 设置工单中，便于 BIOS 工程师核对型号。"
}

# ---------- guide ----------
do_guide() {
    cat <<'EOF'
=== BTB/TidCMP BIOS 设置操作指南 ===

【背景】鲲鹏 920 新型号处理器在启用 TidCMP 时会对线程的分支预测记录（BTB）进行隔离，
导致 redis/mysql 等关键业务的分支预测命中率下降。禁用 TidCMP 后，线程共享 BTB 资源，
可显著提升关键业务的分支预测性能。

【操作步骤】

1. 重启服务器，进入 BIOS 设置界面
   - 不同机型进入键不同，常见为 Del / F2 / F10，请在屏幕启动提示出现时按下
   - 部分 IPMI/远程控制台需要在带外管理界面重启

2. 导航至 BIOS 菜单路径：
   Advanced
     → Power And Performance Configuration
       → CPU PM Control
         → TidCMP

3. 将 TidCMP 设置为 Disabled

4. 保存 BIOS 设置（Save & Exit Setup 或按 F10），重启服务器

5. 重启后回到操作系统，运行 tuning.sh verify 验证环境

【回滚步骤】

1. 重启服务器，进入 BIOS 设置界面
2. 导航至 Advanced → Power And Performance Configuration → CPU PM Control
3. 将 TidCMP 设置为 Enabled
4. 保存 BIOS 设置，重启服务器

【风险提示】
- 涉及服务器重启，请在业务低峰期执行
- BIOS 设置不可由 agent 远程代为执行，必须由机房操作员或现场工程师操作
- 若对 BIOS 不熟悉，请联系服务器厂商技术支持

【验证建议】
- 重启后 CPU 型号保持不变（鲲鹏 920 新型号）
- redis/mysql 关键进程已自动拉起（受 systemd/supervisord 管理时）
- 业务监控 QPS 提升 5%-15%、响应延迟下降
- perf stat -e branch-misses 采样对比，分支预测未命中率应下降
EOF
}

# ---------- verify ----------
do_verify() {
    print_section "BTB/TidCMP 重启后验证"

    local is_kunpeng is_920 part_id is_key key_procs
    is_kunpeng=$(detect_kunpeng)
    IFS='|' read -r is_920 part_id <<< "$(detect_920_new_model)"
    IFS='|' read -r is_key key_procs <<< "$(detect_key_processes)"

    echo "1. CPU 型号未变检查"
    if [[ "$is_920" == "true" ]]; then
        echo "   ✅ 当前 CPU 仍为鲲鹏 920 新型号（dmidecode ID=$part_id）"
    else
        echo "   ❌ 当前 CPU 型号异常（dmidecode ID=$part_id），请检查"
    fi

    echo "2. 关键进程已恢复"
    if [[ "$is_key" == "true" ]]; then
        echo "   ✅ 检测到关键进程：$key_procs"
    else
        echo "   ⚠️ 未检测到关键进程（$key_procs），请检查进程拉起配置"
    fi

    echo "3. 业务表现验证建议"
    echo "   - 观察业务监控指标：QPS / 响应时间 / 错误率（与重启前对比）"
    echo "   - 量化分支预测变化（业务高峰期前后采样）："
    echo "       perf stat -e branch-misses -p <业务进程 PID> sleep 30"
    echo "   - 若有性能回归（QPS 下降 > 10%），请按 guide 中的回滚步骤恢复"

    echo ""
    echo "提示：TidCMP 开关无法从操作系统侧读取，最终确认以业务指标为准。"
}

# ---------- 主入口 ----------
if [ $# -lt 1 ]; then
    echo "用法: $0 {check|status|guide|verify}"
    echo "  check  - 环境检查（CPU型号 + 关键进程）"
    echo "  status - 状态查询（输出 BIOS 设置工单所需证据）"
    echo "  guide  - 输出 BIOS 设置操作指南"
    echo "  verify - 重启后验证（输出业务表现验证建议）"
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