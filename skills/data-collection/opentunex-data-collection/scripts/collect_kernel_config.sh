#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数与路径初始化
# ====================================================================
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/kernel-collection_report.txt"

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/kernel-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] kernel-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] kernel-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "内核深度诊断信息采集"
    echo "采集时间: $(date)"
    echo "============================================================"
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 全量内核参数 (sysctl -a)
# --------------------------------------------------------------------
echo "=== 全量内核参数 (sysctl -a) ===" | tee -a "$REPORT_FILE"
if command -v sysctl &>/dev/null; then
    echo "[BUSY] kernel-collection: sysctl -a..." >&3
    sysctl -a 2>/dev/null | sort | tee -a "$REPORT_FILE"
else
    echo "sysctl 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 关键内核参数补充
# --------------------------------------------------------------------
echo "=== 关键内核参数补充 ===" | tee -a "$REPORT_FILE"

echo "--- 网络核心参数 ---" | tee -a "$REPORT_FILE"
sysctl -a 2>/dev/null | grep -E "^net\.core\.|^net\.ipv4\.tcp_|^net\.ipv4\.udp_|^net\.ipv4\.ip_|^net\.nf" | tee -a "$REPORT_FILE" || echo "无匹配" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 网络缓冲区 ---" | tee -a "$REPORT_FILE"
sysctl -a 2>/dev/null | grep -E "^net\.core\.(r|w)mem|^net\.core\.netdev|^net\.core\.somaxconn|^net\.core\.optmem" | tee -a "$REPORT_FILE" || echo "无匹配" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 用户命名空间限制 ---" | tee -a "$REPORT_FILE"
sysctl -a 2>/dev/null | grep "^user\.max_" | tee -a "$REPORT_FILE" || echo "无匹配" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 内核启动参数特殊项
# --------------------------------------------------------------------
echo "=== 内核启动参数特殊项 ===" | tee -a "$REPORT_FILE"
if [ -f /proc/cmdline ]; then
    cat /proc/cmdline | tee -a "$REPORT_FILE"
    grep -qo 'xcall' /proc/cmdline 2>/dev/null \
        && echo "xcall: yes" | tee -a "$REPORT_FILE" \
        || echo "xcall: no" | tee -a "$REPORT_FILE"
    grep -qo 'sched_steal_node_limit' /proc/cmdline 2>/dev/null \
        && echo "sched_steal_node_limit: yes" | tee -a "$REPORT_FILE" \
        || echo "sched_steal_node_limit: no" | tee -a "$REPORT_FILE"
else
    echo "/proc/cmdline 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 调度特性
# --------------------------------------------------------------------
echo "=== 调度特性 ===" | tee -a "$REPORT_FILE"
SCHED_FEAT=""
[ -f /sys/kernel/debug/sched_features ] && SCHED_FEAT="/sys/kernel/debug/sched_features"
[ -f /sys/kernel/debug/sched/features ] && SCHED_FEAT="/sys/kernel/debug/sched/features"
if [ -n "$SCHED_FEAT" ]; then
    cat "$SCHED_FEAT" 2>/dev/null | tee -a "$REPORT_FILE" || echo "无法读取" | tee -a "$REPORT_FILE"
    [ -w "$SCHED_FEAT" ] && echo "writable" | tee -a "$REPORT_FILE" || echo "not writable" | tee -a "$REPORT_FILE"
    grep -ow 'SOFT_DOMAIN' "$SCHED_FEAT" >/dev/null 2>&1 && echo "SOFT_DOMAIN: present" | tee -a "$REPORT_FILE" || echo "SOFT_DOMAIN: NOT present" | tee -a "$REPORT_FILE"
    grep -ow 'KEEP_ON_CORE' "$SCHED_FEAT" >/dev/null 2>&1 && echo "KEEP_ON_CORE: present" | tee -a "$REPORT_FILE" || echo "KEEP_ON_CORE: NOT present" | tee -a "$REPORT_FILE"
    grep -ow 'PARAL' "$SCHED_FEAT" >/dev/null 2>&1 && echo "PARAL: present" | tee -a "$REPORT_FILE" || echo "PARAL: NOT present" | tee -a "$REPORT_FILE"
else
    echo "调度特性文件不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 特殊调度参数
# --------------------------------------------------------------------
echo "=== 特殊调度参数 ===" | tee -a "$REPORT_FILE"
cat /proc/sys/kernel/sched_cluster 2>/dev/null | tee -a "$REPORT_FILE" || echo "sched_cluster: not exist" | tee -a "$REPORT_FILE"
cat /proc/sys/kernel/sched_util_ratio 2>/dev/null | tee -a "$REPORT_FILE" || echo "sched_util_ratio: not exist" | tee -a "$REPORT_FILE"
cat /proc/sys/kernel/sched_util_low_pct 2>/dev/null | tee -a "$REPORT_FILE" || echo "sched_util_low_pct: not exist" | tee -a "$REPORT_FILE"
if [ -f /proc/sys/kernel/sched_soft_runtime_ratio ]; then
    echo "Docker CPU Burst: yes, value=$(cat /proc/sys/kernel/sched_soft_runtime_ratio)" | tee -a "$REPORT_FILE"
else
    echo "Docker CPU Burst: no" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 完整内核模块列表 (lsmod)
# --------------------------------------------------------------------
echo "=== 完整内核模块列表 (lsmod) ===" | tee -a "$REPORT_FILE"
lsmod 2>/dev/null | tee -a "$REPORT_FILE" || echo "lsmod 不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 内核版本与编译选项
# --------------------------------------------------------------------
echo "=== 内核版本与编译选项 ===" | tee -a "$REPORT_FILE"
uname -a | tee -a "$REPORT_FILE"
cat /proc/version 2>/dev/null | tee -a "$REPORT_FILE"
KERNEL_VER=$(uname -r)
if [ -f /boot/config-${KERNEL_VER} ]; then
    grep -E "CONFIG_IKCONFIG|CONFIG_HZ|CONFIG_PREEMPT|CONFIG_NR_CPUS|CONFIG_HUGETLB|CONFIG_TRANSPARENT|CONFIG_CGROUP|CONFIG_NAMESPACE|CONFIG_SCHED_STEAL|CONFIG_SCHED_SMT" \
        /boot/config-${KERNEL_VER} 2>/dev/null | tee -a "$REPORT_FILE"
elif [ -f /proc/config.gz ]; then
    zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_IKCONFIG|CONFIG_HZ|CONFIG_PREEMPT|CONFIG_NR_CPUS|CONFIG_HUGETLB|CONFIG_TRANSPARENT|CONFIG_CGROUP|CONFIG_NAMESPACE|CONFIG_SCHED_STEAL|CONFIG_SCHED_SMT" | tee -a "$REPORT_FILE"
else
    echo "未找到内核 config 文件" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 系统诊断
# --------------------------------------------------------------------
echo "=== 系统诊断 ===" | tee -a "$REPORT_FILE"

echo "--- 内核 taint ---" | tee -a "$REPORT_FILE"
cat /proc/sys/kernel/tainted 2>/dev/null | tee -a "$REPORT_FILE" || echo "无法读取" | tee -a "$REPORT_FILE"
echo "(0=未污染)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 内核 Oops/Panic (dmesg) ---" | tee -a "$REPORT_FILE"
if command -v dmesg &>/dev/null; then
    dmesg 2>/dev/null | grep -i -E "Oops|panic|BUG|Call Trace|WARNING" | tail -20 | tee -a "$REPORT_FILE"
else
    echo "dmesg 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

echo "--- 活跃内核线程 (前20) ---" | tee -a "$REPORT_FILE"
ps -eo pid,comm --no-headers 2>/dev/null | awk '$2 ~ /^\[.*\]$/ {print}' | head -20 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 透明大页 defrag ---" | tee -a "$REPORT_FILE"
cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "THP enabled writable: $(test -w /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null && echo writable || echo 'not writable')" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 内核特性与模块诊断
# --------------------------------------------------------------------
echo "=== 内核特性与模块诊断 ===" | tee -a "$REPORT_FILE"

echo "--- /proc/1/xcall ---" | tee -a "$REPORT_FILE"
test -f /proc/1/xcall && echo "exists" | tee -a "$REPORT_FILE" || echo "not exist" | tee -a "$REPORT_FILE"

echo "--- irqbalance ---" | tee -a "$REPORT_FILE"
# 部分系统（如某些 Debian 衍生版）服务名为 irqbalance-ng，需同时检查两个服务名
_irq_status="unknown"
_irq_svc="irqbalance"
if systemctl list-unit-files irqbalance.service 2>/dev/null | grep -q 'irqbalance\.service'; then
    _irq_status=$(systemctl is-active irqbalance 2>/dev/null || echo "inactive")
    _irq_svc="irqbalance"
elif systemctl list-unit-files irqbalance-ng.service 2>/dev/null | grep -q 'irqbalance-ng\.service'; then
    _irq_status=$(systemctl is-active irqbalance-ng 2>/dev/null || echo "inactive")
    _irq_svc="irqbalance-ng"
fi
echo "$_irq_status" | tee -a "$REPORT_FILE"
echo "--- irqbalance-service ---" | tee -a "$REPORT_FILE"
echo "$_irq_svc" | tee -a "$REPORT_FILE"

echo "--- oenetcls ---" | tee -a "$REPORT_FILE"
modinfo oenetcls 2>/dev/null | tee -a "$REPORT_FILE" && echo "available" | tee -a "$REPORT_FILE" || echo "not found" | tee -a "$REPORT_FILE"

echo "--- SMC ---" | tee -a "$REPORT_FILE"
if lsmod 2>/dev/null | grep -qi smc; then
    echo "loaded" | tee -a "$REPORT_FILE"
    lsmod 2>/dev/null | grep -i smc | tee -a "$REPORT_FILE"
else
    echo "not loaded" | tee -a "$REPORT_FILE"
fi

echo "--- ism ---" | tee -a "$REPORT_FILE"
lsmod 2>/dev/null | grep -qi ism && echo "loaded" | tee -a "$REPORT_FILE" && lsmod 2>/dev/null | grep -i ism | tee -a "$REPORT_FILE" || echo "not loaded" | tee -a "$REPORT_FILE"

echo "--- cpufreq_seep / oenetcls in /proc/modules ---" | tee -a "$REPORT_FILE"
grep -E 'oenetcls|cpufreq_seep' /proc/modules 2>/dev/null | tee -a "$REPORT_FILE" || echo "(无匹配)" | tee -a "$REPORT_FILE"

echo "--- xcall_numa 参数 ---" | tee -a "$REPORT_FILE"
ls /proc/sys/kernel/xcall_numa* 2>/dev/null | tee -a "$REPORT_FILE" || echo "xcall_numa* not exist" | tee -a "$REPORT_FILE"

echo "--- debugfs 挂载 ---" | tee -a "$REPORT_FILE"
mount 2>/dev/null | grep debugfs | tee -a "$REPORT_FILE" || echo "debugfs not mounted" | tee -a "$REPORT_FILE"

echo "--- numafast ---" | tee -a "$REPORT_FILE"
rpm -qa 2>/dev/null | grep numafast | tee -a "$REPORT_FILE" || echo "not installed" | tee -a "$REPORT_FILE"

echo "--- ARM SPE ---" | tee -a "$REPORT_FILE"
perf list 2>/dev/null | grep -qi arm_spe && echo "available" | tee -a "$REPORT_FILE" || echo "not available" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 其他系统诊断
# --------------------------------------------------------------------
echo "=== 其他系统诊断 ===" | tee -a "$REPORT_FILE"

echo "--- /proc/filesystems ---" | tee -a "$REPORT_FILE"
cat /proc/filesystems 2>/dev/null | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- SECCOMP 进程 (strict) ---" | tee -a "$REPORT_FILE"
grep -l "Seccomp:.*2" /proc/[0-9]*/status 2>/dev/null | head -5 | while read f; do
    pid=$(echo "$f" | grep -oP '/\K\d+')
    comm=$(cat /proc/$pid/comm 2>/dev/null || echo "?")
    echo "PID=$pid COMM=$comm SECCOMP=strict"
done | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 文件描述符使用 Top5 ---" | tee -a "$REPORT_FILE"
for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' | head -200); do
    if [ -d "/proc/$pid/fd" ]; then
        comm=$(cat /proc/$pid/comm 2>/dev/null || echo "?")
        count=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l)
        echo "$pid $comm $count"
    fi
done 2>/dev/null | sort -t' ' -k3 -rn | head -5 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "--- 关键系统服务 PID ---" | tee -a "$REPORT_FILE"
for svc in systemd sshd dmsetup auditd dbus udevd chronyd crond; do
    if command -v pgrep &>/dev/null; then
        pids=$(pgrep -x "$svc" 2>/dev/null || echo "")
        [ -n "$pids" ] && echo "$svc: PID=$pids" | tee -a "$REPORT_FILE"
    fi
done
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "内核深度诊断信息采集完成"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] kernel-collection: 采集完成，报告 $REPORT_FILE" >&3
