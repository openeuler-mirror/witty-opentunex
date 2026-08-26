#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数与路径初始化
# ====================================================================
# 用法:
#   collect_net_info.sh [batch_dir] [duration] [pids]
#   环境变量: WORK_DIR / DURATION / PIDS
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/net-collection_report.txt"
DURATION="${2:-${DURATION:-5}}"
INTERVAL=1
PIDS="${PIDS:-}"

mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"

LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/net-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] net-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] net-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Phase: Network Metrics for Bottleneck Analysis"
    echo "============================================================"
    echo "采集时间: $(date)"
    echo "持续时间: ${DURATION}秒"
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Network Interfaces
# --------------------------------------------------------------------
echo "=== Network Interfaces ===" | tee -a "$REPORT_FILE"
if command -v ip &>/dev/null; then
    ip -br link show 2>/dev/null | tee -a "$REPORT_FILE" || echo "Cannot get network interface list" | tee -a "$REPORT_FILE"
else
    echo "ip 命令不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Network Sysctl Configuration
# --------------------------------------------------------------------
echo "=== Network Sysctl Configuration ===" | tee -a "$REPORT_FILE"
for key in tcp_tw_reuse tcp_timestamps tcp_sack tcp_window_scaling tcp_congestion_control \
           tcp_rmem tcp_wmem tcp_mem tcp_max_syn_backlog tcp_fin_timeout ip_local_port_range \
           netdev_max_backlog netdev_budget somaxconn rmem_default rmem_max wmem_default wmem_max; do
    if [ -r "/proc/sys/net/ipv4/${key}" ] 2>/dev/null; then
        echo "${key}: $(cat /proc/sys/net/ipv4/${key} 2>/dev/null)" | tee -a "$REPORT_FILE"
    elif [ -r "/proc/sys/net/core/${key}" ] 2>/dev/null; then
        echo "${key}: $(cat /proc/sys/net/core/${key} 2>/dev/null)" | tee -a "$REPORT_FILE"
    else
        if [[ "$key" == "tcp_congestion_control" ]]; then
            if [ -r "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
                echo "${key}: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)" | tee -a "$REPORT_FILE"
            fi
        else
            echo "${key}: N/A" | tee -a "$REPORT_FILE"
        fi
    fi
done
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# NIC Configuration（仅显示UP状态的接口）
# --------------------------------------------------------------------
echo "=== NIC Configuration ===" | tee -a "$REPORT_FILE"
ACTIVE_IFACES=""
if command -v ip &>/dev/null; then
    ACTIVE_IFACES=$(ip -br link show 2>/dev/null | awk '$2=="UP" {print $1}' | grep -v lo | head -5)
fi

if [ -z "$ACTIVE_IFACES" ]; then
    echo "No active network interfaces found (excluding lo)" | tee -a "$REPORT_FILE"
else
    for iface in $ACTIVE_IFACES; do
        echo "--- $iface ---" | tee -a "$REPORT_FILE"

        if command -v ethtool &>/dev/null; then
            echo "Link Info:" | tee -a "$REPORT_FILE"
            ethtool "$iface" 2>/dev/null | grep -E "Speed|Duplex|Link detected|Auto-negotiation" | sed 's/^\t*//' | tee -a "$REPORT_FILE"

            echo "" | tee -a "$REPORT_FILE"
            echo "Driver Info:" | tee -a "$REPORT_FILE"
            ethtool -i "$iface" 2>/dev/null | grep -E "driver|version|firmware|bus-info" | sed 's/^[^:]*: //' | paste -sd, - | tee -a "$REPORT_FILE"

            echo "" | tee -a "$REPORT_FILE"
            echo "[Queue/Channel Configuration]" | tee -a "$REPORT_FILE"
            ethtool -l "$iface" 2>/dev/null | tee -a "$REPORT_FILE"

            echo "" | tee -a "$REPORT_FILE"
            echo "[Ring Buffer]" | tee -a "$REPORT_FILE"
            ethtool -g "$iface" 2>/dev/null | tee -a "$REPORT_FILE"

            echo "" | tee -a "$REPORT_FILE"
            echo "[Coalesce Settings]" | tee -a "$REPORT_FILE"
            ethtool -c "$iface" 2>/dev/null | tee -a "$REPORT_FILE"

            echo "" | tee -a "$REPORT_FILE"
            echo "[Pause Frame]" | tee -a "$REPORT_FILE"
            ethtool -a "$iface" 2>/dev/null | tee -a "$REPORT_FILE"

            echo "" | tee -a "$REPORT_FILE"
            echo "[Offload Features]" | tee -a "$REPORT_FILE"
            ethtool -k "$iface" 2>/dev/null | head -30 | tee -a "$REPORT_FILE"

            # IRQ 亲和性
            BUS_INFO=$(ethtool -i "$iface" 2>/dev/null | grep 'bus-info' | awk '{print $2}')
            if [ -n "$BUS_INFO" ]; then
                echo "" | tee -a "$REPORT_FILE"
                echo "--- IRQ Affinity ---" | tee -a "$REPORT_FILE"
                grep "$BUS_INFO" /proc/interrupts 2>/dev/null | while read -r line; do
                    IRQ=$(echo "$line" | awk '{print $1}' | tr -d ':')
                    AFFINITY=$(cat /proc/irq/$IRQ/smp_affinity 2>/dev/null || echo 'N/A')
                    DESC=$(echo "$line" | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
                    echo "IRQ $IRQ: $AFFINITY  ($DESC)" | tee -a "$REPORT_FILE"
                done
            fi
        else
            echo "ethtool not available for detailed NIC info" | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"
    done
fi

# --------------------------------------------------------------------
# Network Performance Data Collection（sar 后台持续采集）
# --------------------------------------------------------------------
echo "=== Network Performance Data Collection (${DURATION} seconds) ===" | tee -a "$REPORT_FILE"
echo "[BUSY] net-collection: sar ${DURATION}s..." >&3

if command -v ip &>/dev/null; then
    ACTIVE_IFACES=$(ip -br link show 2>/dev/null | awk '$2=="UP" && $1!="lo" {print $1}' | head -5 | paste -sd,)
fi

TMPD="${BATCH_DIR}/.net_tmp"
mkdir -p "$TMPD"
SAR_DEV_TMP="$TMPD/sar_dev.txt"
SAR_EDEV_TMP="$TMPD/sar_edeve.txt"

if command -v sar &>/dev/null; then
    if [ -n "$ACTIVE_IFACES" ]; then
        sar -n DEV $INTERVAL $DURATION --iface="$ACTIVE_IFACES" > "$SAR_DEV_TMP" 2>&1 &
        SAR_DEV_PID=$!
        sar -n EDEV $INTERVAL $DURATION --iface="$ACTIVE_IFACES" > "$SAR_EDEV_TMP" 2>&1 &
        SAR_EDEV_PID=$!

        wait $SAR_DEV_PID $SAR_EDEV_PID 2>/dev/null || true

        echo "--- Network Device Stats (sar -n DEV) ---" | tee -a "$REPORT_FILE"
        if [ -f "$SAR_DEV_TMP" ] && [ -s "$SAR_DEV_TMP" ]; then
            tail -n +4 "$SAR_DEV_TMP" | tee -a "$REPORT_FILE"
        else
            echo "No data collected" | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"

        echo "--- Network Error Stats (sar -n EDEV) ---" | tee -a "$REPORT_FILE"
        if [ -f "$SAR_EDEV_TMP" ] && [ -s "$SAR_EDEV_TMP" ]; then
            tail -n +4 "$SAR_EDEV_TMP" | tee -a "$REPORT_FILE"
        else
            echo "No data collected" | tee -a "$REPORT_FILE"
        fi
        echo "" | tee -a "$REPORT_FILE"
    else
        echo "No active network interfaces for sar monitoring" | tee -a "$REPORT_FILE"
        echo "" | tee -a "$REPORT_FILE"
    fi
else
    echo "sar not available (install sysstat package)" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

rm -rf "$TMPD"

# --------------------------------------------------------------------
# Latency Tests
# --------------------------------------------------------------------
echo "=== Latency Tests ===" | tee -a "$REPORT_FILE"
GATEWAY=""
if command -v ip &>/dev/null; then
    GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1)
fi

if [ -n "$GATEWAY" ]; then
    echo "Default gateway: $GATEWAY" | tee -a "$REPORT_FILE"
    if ping -c 5 "$GATEWAY" 2>/dev/null | tail -2 | tee -a "$REPORT_FILE"; then
        :
    else
        echo "Gateway ping failed" | tee -a "$REPORT_FILE"
    fi
else
    echo "No default gateway found" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

echo "--- Loopback Latency Test ---" | tee -a "$REPORT_FILE"
if ping -c 5 127.0.0.1 2>/dev/null | tail -2 | tee -a "$REPORT_FILE"; then
    :
else
    echo "Loopback ping failed" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# TCP Statistics
# --------------------------------------------------------------------
echo "=== TCP Statistics ===" | tee -a "$REPORT_FILE"
if command -v netstat &>/dev/null; then
    netstat -s 2>/dev/null | sed -n '/^Tcp:/,/^$/p' | head -50 | tee -a "$REPORT_FILE" || echo "netstat command failed" | tee -a "$REPORT_FILE"
else
    echo "netstat not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Socket Summary
# --------------------------------------------------------------------
echo "=== Socket Summary ===" | tee -a "$REPORT_FILE"
if command -v ss &>/dev/null; then
    ss -s 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "ss not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Socket Memory
# --------------------------------------------------------------------
echo "=== Socket Memory ===" | tee -a "$REPORT_FILE"
if [ -r /proc/net/sockstat ]; then
    cat /proc/net/sockstat 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "Cannot read /proc/net/sockstat" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# TCP Connection States Distribution
# --------------------------------------------------------------------
echo "=== TCP Connection States Distribution ===" | tee -a "$REPORT_FILE"
if command -v ss &>/dev/null; then
    ss -tan 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -10 | tee -a "$REPORT_FILE"
else
    echo "ss not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Network Queue Statistics
# --------------------------------------------------------------------
echo "=== Network Queue Statistics ===" | tee -a "$REPORT_FILE"
if [ -r /proc/net/netstat ]; then
    echo "--- TCP Queue Info ---" | tee -a "$REPORT_FILE"
    cat /proc/net/netstat 2>/dev/null | grep -E "TcpExt|IpExt" | head -5 | tee -a "$REPORT_FILE"
else
    echo "Cannot read /proc/net/netstat" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# Network Optimization Recommendations
# --------------------------------------------------------------------
echo "=== Network Optimization Recommendations ===" | tee -a "$REPORT_FILE"

# 检查 TCP 内存压力
if [ -r /proc/sys/net/ipv4/tcp_mem ]; then
    tcp_mem=$(cat /proc/sys/net/ipv4/tcp_mem 2>/dev/null)
    if [ -n "$tcp_mem" ]; then
        low_pressure=$(echo "$tcp_mem" | awk '{print $1}')
        pressure=$(echo "$tcp_mem" | awk '{print $2}')
        if [ -n "$pressure" ] && [ -n "$low_pressure" ] && [ "$pressure" -gt "$((low_pressure * 2))" ] 2>/dev/null; then
            echo "⚠ WARNING: TCP memory under pressure. Consider increasing tcp_mem or reducing connections." | tee -a "$REPORT_FILE"
        fi
    fi
fi

# 检查 TIME_WAIT 连接数
if command -v ss &>/dev/null; then
    timewait_count=$(ss -tan 2>/dev/null | grep -c TIME-WAIT || echo 0)
    if [ -n "$timewait_count" ]; then
        if [ "$timewait_count" -gt 10000 ] 2>/dev/null; then
            echo "⚠ WARNING: High number of TIME_WAIT connections ($timewait_count). Consider adjusting tcp_tw_reuse and tcp_fin_timeout." | tee -a "$REPORT_FILE"
        elif [ "$timewait_count" -gt 5000 ] 2>/dev/null; then
            echo "ℹ INFO: Moderate TIME_WAIT connections ($timewait_count). Consider optimizing if sustained." | tee -a "$REPORT_FILE"
        fi
    fi
fi

# 检查端口范围
if [ -r /proc/sys/net/ipv4/ip_local_port_range ]; then
    port_range=$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null)
    if [ -n "$port_range" ]; then
        start_port=$(echo "$port_range" | awk '{print $1}')
        end_port=$(echo "$port_range" | awk '{print $2}')
        total_ports=$((end_port - start_port + 1))
        if command -v ss &>/dev/null; then
            used_ports=$(ss -tan 2>/dev/null | grep -c "ESTAB\|TIME_WAIT" || echo 0)
            if [ -n "$used_ports" ] && [ -n "$total_ports" ] && [ "$used_ports" -gt "$((total_ports * 80 / 100))" ] 2>/dev/null; then
                echo "⚠ WARNING: Port range nearly exhausted (${used_ports}/${total_ports} used). Consider widening ip_local_port_range." | tee -a "$REPORT_FILE"
            fi
        fi
    fi
fi

# 检查网卡队列配置
if command -v ethtool &>/dev/null && [ -n "$ACTIVE_IFACES" ]; then
    for iface in $ACTIVE_IFACES; do
        combined=$(ethtool -l "$iface" 2>/dev/null | grep -A5 "Current" | grep Combined | awk '{print $2}')
        if [ -n "$combined" ] && [ "$combined" -eq 1 ] 2>/dev/null; then
            echo "ℹ INFO: Interface $iface has only 1 combined queue. Consider increasing for better SMP performance." | tee -a "$REPORT_FILE"
            break
        fi
    done
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 接口详细状态（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 接口详细状态 (/sys/class/net) ===" | tee -a "$REPORT_FILE"
for iface_dir in /sys/class/net/*; do
    iface_name=$(basename "$iface_dir")
    ifindex=$(cat "$iface_dir/ifindex" 2>/dev/null || echo "N/A")
    operstate=$(cat "$iface_dir/operstate" 2>/dev/null || echo "N/A")
    carrier=$(cat "$iface_dir/carrier" 2>/dev/null || echo "N/A")
    mtu=$(cat "$iface_dir/mtu" 2>/dev/null || echo "N/A")
    speed=$(cat "$iface_dir/speed" 2>/dev/null || echo "N/A")
    duplex=$(cat "$iface_dir/duplex" 2>/dev/null || echo "N/A")
    echo "$iface_name: ifindex=$ifindex operstate=$operstate carrier=$carrier mtu=$mtu speed=$speed duplex=$duplex" | tee -a "$REPORT_FILE"
done
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# ip addr show（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== ip addr show ===" | tee -a "$REPORT_FILE"
if command -v ip &>/dev/null; then
    ip addr show 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "ip 命令不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 路由表（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 路由表 (ip route show) ===" | tee -a "$REPORT_FILE"
if command -v ip &>/dev/null; then
    ip route show 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "ip 命令不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# ARP 表（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== ARP 表 ===" | tee -a "$REPORT_FILE"
arp -n 2>/dev/null | tee -a "$REPORT_FILE" || cat /proc/net/arp 2>/dev/null | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 网络统计（netstat -s）完整版（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 网络统计 (netstat -s) 完整版 ===" | tee -a "$REPORT_FILE"
if command -v netstat &>/dev/null; then
    netstat -s 2>/dev/null | tee -a "$REPORT_FILE"
else
    cat /proc/net/netstat 2>/dev/null | tee -a "$REPORT_FILE"
    cat /proc/net/snmp 2>/dev/null | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 监听端口（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 监听端口 (ss -tlnp) ===" | tee -a "$REPORT_FILE"
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | tee -a "$REPORT_FILE"
else
    echo "ss 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 网卡队列与 RPS 配置（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 网卡队列与 RPS 配置 ===" | tee -a "$REPORT_FILE"
for iface_dir in /sys/class/net/*; do
    iface_name=$(basename "$iface_dir")
    if [ "$iface_name" != "lo" ] && [ -d "$iface_dir/queues" ]; then
        rx_count=$(ls -d "$iface_dir/queues/rx-"* 2>/dev/null | wc -l)
        tx_count=$(ls -d "$iface_dir/queues/tx-"* 2>/dev/null | wc -l)
        echo "$iface_name: RX队列=$rx_count, TX队列=$tx_count" | tee -a "$REPORT_FILE"
        if [ -f "$iface_dir/queues/rx-0/rps_cpus" ]; then
            echo "  RPS cpus (rx-0): $(cat "$iface_dir/queues/rx-0/rps_cpus")" | tee -a "$REPORT_FILE"
        fi
        if [ -f "$iface_dir/queues/rx-0/rps_flow_cnt" ]; then
            echo "  RPS flow_cnt (rx-0): $(cat "$iface_dir/queues/rx-0/rps_flow_cnt")" | tee -a "$REPORT_FILE"
        fi
    fi
done
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 网卡 ntuple 支持（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 网卡 ntuple 支持 ===" | tee -a "$REPORT_FILE"
for iface_dir in /sys/class/net/*; do
    iface_name=$(basename "$iface_dir")
    [ "$iface_name" = "lo" ] && continue
    if command -v ethtool &>/dev/null; then
        ntuple_info=$(ethtool -k "$iface_name" 2>/dev/null | grep ntuple || echo 'ntuple: unknown')
        echo "$iface_name: $ntuple_info" | tee -a "$REPORT_FILE"
    fi
done
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 网络排队规则（tc qdisc）（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 网络排队规则 (tc qdisc show) ===" | tee -a "$REPORT_FILE"
if command -v tc &>/dev/null; then
    tc qdisc show 2>/dev/null | tee -a "$REPORT_FILE" || echo "注意: tc 不可用" | tee -a "$REPORT_FILE"
else
    echo "注意: tc 不可用" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# /proc/net/dev 原始统计（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== /proc/net/dev ===" | tee -a "$REPORT_FILE"
cat /proc/net/dev 2>/dev/null | tee -a "$REPORT_FILE" || echo "不可用" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 常见进程名列表（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== 常见进程名列表 (Top 30) ===" | tee -a "$REPORT_FILE"
ps -eo comm --no-headers 2>/dev/null | sort -u | awk 'NR<=30'| tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Network Metrics Analysis Complete"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] net-collection: 采集完成，报告 $REPORT_FILE" >&3
