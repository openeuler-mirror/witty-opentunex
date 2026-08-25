#!/bin/bash
set -euo pipefail

# ====================================================================
# 参数初始化
# ====================================================================
# 用法:
#   collect_io_info.sh [batch_dir] [duration] [pids]
#   环境变量: WORK_DIR / DURATION / PIDS
DEFAULT_TS=$(date +%Y%m%d_%H%M%S)
BATCH_DIR="${1:-${WORK_DIR:-/srv/opentunex/${DEFAULT_TS}}/collect/}"
REPORT_FILE="${BATCH_DIR}/io-collection_report.txt"
DURATION="${2:-${DURATION:-5}}"
INTERVAL=1
PIDS="${PIDS:-}"

# ====================================================================
# 目录与日志准备
# ====================================================================
mkdir -p "$BATCH_DIR"
> "$REPORT_FILE"
LOG_DIR="${WORK_DIR:-/srv/opentunex/$(date +%Y%m%d_%H%M%S)}/collect/collect_log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/io-collection_$(date '+%Y%m%d_%H%M%S').log"

exec 3>&1
exec >"$LOG_FILE" 2>&1

trap 'echo "[FAIL] io-collection line $LINENO exit $?" >&3' ERR
echo "[BUSY] io-collection 开始采集 → $BATCH_DIR" >&3

# ====================================================================
# 必要命令检查
# ====================================================================
command -v iostat &>/dev/null || {
    echo "[FAIL] iostat 未安装"
    exit 1
}
command -v vmstat &>/dev/null || echo "[WARN] vmstat 未安装"
command -v pidstat &>/dev/null || echo "[WARN] pidstat 未安装"

# ====================================================================
# 采集开始 — 头部块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "Phase: I/O Metrics for Bottleneck Analysis"
    echo "============================================================"
    echo "采集时间: $(date)"
    echo "持续时间: ${DURATION}秒"
    if [ -n "$PIDS" ]; then
        echo "目标进程: $PIDS"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 1. System Overview
# --------------------------------------------------------------------
echo "=== System Overview ===" | tee -a "$REPORT_FILE"
echo "Kernel: $(uname -r)" | tee -a "$REPORT_FILE"
echo "CPU Count: $(nproc)" | tee -a "$REPORT_FILE"
echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 2. Disk Devices
# --------------------------------------------------------------------
echo "=== Disk Devices ===" | tee -a "$REPORT_FILE"
if lsblk -d -n -o NAME,SIZE,TYPE 2>/dev/null | grep -E 'disk|nvme' | tee -a "$REPORT_FILE"; then
    echo "✓ Disk devices collected" | tee -a "$REPORT_FILE"
else
    echo "⚠ No disk devices found or lsblk not available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 3. I/O Scheduler Configuration
# --------------------------------------------------------------------
echo "=== I/O Scheduler Configuration ===" | tee -a "$REPORT_FILE"
scheduler_collected=false
for dev in $(lsblk -d -n -o NAME 2>/dev/null | grep -E '^vd|^sd|^nvme' | head -5); do
    if [ -r "/sys/block/$dev/queue/scheduler" ]; then
        echo "--- /dev/$dev ---" | tee -a "$REPORT_FILE"
        echo "scheduler: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null | grep -o '\[.*\]' || echo 'N/A')" | tee -a "$REPORT_FILE"
        echo "nr_requests: $(cat /sys/block/$dev/queue/nr_requests 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
        echo "read_ahead_kb: $(cat /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
        echo "max_sectors_kb: $(cat /sys/block/$dev/queue/max_sectors_kb 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
        echo "rotational: $(cat /sys/block/$dev/queue/rotational 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
        echo "nomerges: $(cat /sys/block/$dev/queue/nomerges 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
        scheduler_collected=true
    fi
done
[ "$scheduler_collected" = false ] && echo "⚠ No I/O scheduler information available (可能需要 root 权限)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 4. Memory/Page Cache Settings
# --------------------------------------------------------------------
echo "=== Memory/Page Cache Settings ===" | tee -a "$REPORT_FILE"
mem_settings_collected=false
for setting in vfs_cache_pressure swappiness dirty_background_ratio dirty_ratio dirty_writeback_centisecs dirty_expire_centisecs min_free_kbytes; do
    if [ -r "/proc/sys/vm/$setting" ]; then
        echo "$setting: $(cat /proc/sys/vm/$setting 2>/dev/null || echo 'N/A')" | tee -a "$REPORT_FILE"
        mem_settings_collected=true
    fi
done
[ "$mem_settings_collected" = false ] && echo "⚠ Memory settings not accessible (可能需要 root 权限)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 5. Process I/O Configuration（如果指定了 PID）
# --------------------------------------------------------------------
if [ -n "$PIDS" ]; then
    IFS=',' read -ra pid_array <<< "$PIDS"
    for single_pid in "${pid_array[@]}"; do
        single_pid=$(echo "$single_pid" | xargs)
        if [ -d "/proc/$single_pid" ]; then
            echo "=== Process I/O Configuration (PID $single_pid) ===" | tee -a "$REPORT_FILE"

            echo "--- IO Priority ---" | tee -a "$REPORT_FILE"
            ionice -p "$single_pid" 2>&1 | tee -a "$REPORT_FILE" || echo "  ionice not available or permission denied" | tee -a "$REPORT_FILE"

            echo "--- IO Statistics ---" | tee -a "$REPORT_FILE"
            if [ -f "/proc/$single_pid/io" ]; then
                cat "/proc/$single_pid/io" 2>/dev/null | tee -a "$REPORT_FILE" || echo "  /proc/$single_pid/io not available (可能需要 root 权限)" | tee -a "$REPORT_FILE"
            else
                echo "  /proc/$single_pid/io not available" | tee -a "$REPORT_FILE"
            fi

            echo "--- Open Files Limit ---" | tee -a "$REPORT_FILE"
            if [ -r "/proc/$single_pid/limits" ]; then
                soft=$(awk '/Max open files/ {print $4}' /proc/$single_pid/limits 2>/dev/null)
                hard=$(awk '/Max open files/ {print $5}' /proc/$single_pid/limits 2>/dev/null)
                echo "  soft=$soft  hard=$hard" | tee -a "$REPORT_FILE"
            else
                echo "  Cannot read process limits (可能需要 root 权限)" | tee -a "$REPORT_FILE"
            fi

            if [ -d "/proc/$single_pid/fd" ]; then
                fd_count=$(ls /proc/$single_pid/fd/ 2>/dev/null | wc -l)
                [ "$fd_count" -gt 0 ] && echo "  open_fds=$fd_count" | tee -a "$REPORT_FILE"
            fi
            echo "" | tee -a "$REPORT_FILE"
        else
            echo "=== Process PID=$single_pid does not exist ===" | tee -a "$REPORT_FILE"
            echo "" | tee -a "$REPORT_FILE"
        fi
    done
fi

# --------------------------------------------------------------------
# 6. System-wide I/O Limits
# --------------------------------------------------------------------
echo "=== System-wide I/O Limits ===" | tee -a "$REPORT_FILE"

echo "--- AIO Limits ---" | tee -a "$REPORT_FILE"
if [ -r "/proc/sys/fs/aio-max-nr" ]; then
    echo "aio-max-nr: $(cat /proc/sys/fs/aio-max-nr 2>/dev/null)" | tee -a "$REPORT_FILE"
else
    echo "aio-max-nr: N/A (不可访问)" | tee -a "$REPORT_FILE"
fi
if [ -r "/proc/sys/fs/aio-nr" ]; then
    echo "aio-nr: $(cat /proc/sys/fs/aio-nr 2>/dev/null)" | tee -a "$REPORT_FILE"
else
    echo "aio-nr: N/A (不可访问)" | tee -a "$REPORT_FILE"
fi
# AIO 使用率检查
if [ -r /proc/sys/fs/aio-max-nr ] && [ -r /proc/sys/fs/aio-nr ]; then
    max=$(cat /proc/sys/fs/aio-max-nr 2>/dev/null)
    cur=$(cat /proc/sys/fs/aio-nr 2>/dev/null)
    if [ -n "$max" ] && [ -n "$cur" ] && [ "$max" -gt 0 ]; then
        pct=$((cur * 100 / max))
        [ "$pct" -gt 80 ] && echo "  WARNING: AIO usage at ${pct}%" | tee -a "$REPORT_FILE"
    fi
fi

echo "--- File Handle Limits ---" | tee -a "$REPORT_FILE"
[ -r "/proc/sys/fs/file-max" ] && echo "file-max: $(cat /proc/sys/fs/file-max 2>/dev/null)" | tee -a "$REPORT_FILE"
if [ -r "/proc/sys/fs/file-nr" ]; then
    awk '{printf "file-nr:  allocated=%s  free=%s  max=%s\n", $1, $2, $3}' /proc/sys/fs/file-nr 2>/dev/null | tee -a "$REPORT_FILE"
fi
[ -r "/proc/sys/fs/nr_open" ] && echo "nr_open: $(cat /proc/sys/fs/nr_open 2>/dev/null)" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 7. 磁盘累计统计 + 挂载使用率（独立脚本扩展）
# --------------------------------------------------------------------
echo "=== /proc/diskstats ===" | tee -a "$REPORT_FILE"
cat /proc/diskstats 2>/dev/null | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "=== Disk Usage (df -h) ===" | tee -a "$REPORT_FILE"
df -h 2>/dev/null | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 8. I/O Performance Data Collection（后台持续采集）
# --------------------------------------------------------------------
echo "=== I/O Performance Data Collection (${DURATION} seconds) ===" | tee -a "$REPORT_FILE"
echo "[BUSY] io-collection: 后台采集 ${DURATION}s..." >&3

TMPD="${BATCH_DIR}/.io_tmp"
mkdir -p "$TMPD"
TMP_VMSTAT="$TMPD/vmstat"
TMP_IOSTAT="$TMPD/iostat_x"
TMP_PIDSTAT="$TMPD/pidstat"

# 启动后台任务
VMSTAT_PID=""
IOSTAT_PID=""
PIDSTAT_PID=""
if command -v vmstat &>/dev/null; then
    vmstat ${INTERVAL} ${DURATION} > "${TMP_VMSTAT}" 2>&1 &
    VMSTAT_PID=$!
else
    echo "⚠ vmstat command not found" | tee -a "$REPORT_FILE"
fi

if command -v iostat &>/dev/null; then
    iostat -x ${INTERVAL} ${DURATION} > "${TMP_IOSTAT}" 2>&1 &
    IOSTAT_PID=$!
else
    echo "⚠ iostat command not found (install sysstat package)" | tee -a "$REPORT_FILE"
fi

if command -v pidstat &>/dev/null && pidstat -d 1 1 &>/dev/null 2>&1; then
    pidstat -d ${INTERVAL} ${DURATION} > "${TMP_PIDSTAT}" 2>&1 &
    PIDSTAT_PID=$!
fi

# 等待所有后台任务完成
set +e
for pid in ${VMSTAT_PID} ${IOSTAT_PID} ${PIDSTAT_PID:-}; do
    [ -n "$pid" ] && wait "$pid" 2>/dev/null
done
set -e

# VMStat 输出
if [ -s "${TMP_VMSTAT}" ]; then
    echo "--- VMStat Analysis ---" | tee -a "$REPORT_FILE"
    cat "${TMP_VMSTAT}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
else
    echo "⚠ VMStat data collection failed" | tee -a "$REPORT_FILE"
fi

# iostat 输出
if [ -s "${TMP_IOSTAT}" ]; then
    echo "--- Disk Utilization Summary ---" | tee -a "$REPORT_FILE"
    cat "${TMP_IOSTAT}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"

    echo "--- I/O Pattern Analysis (Sequential vs Random) ---" | tee -a "$REPORT_FILE"
    awk '$1 ~ /^[a-z]/ && (($4+0)>0 || ($5+0)>0) {
        ratio = ($4+$5)/($4+$5+$6+$7+0.1)*100
        printf "  %s: merge=%.1f%%  avg_req=%d sect  pattern=", $1, ratio, $8
        if (ratio > 30 && $8 > 32) print "SEQUENTIAL"
        else if (ratio < 10 && $8 < 16) print "RANDOM"
        else print "MIXED"
    }' "${TMP_IOSTAT}" | head -10 | tee -a "$REPORT_FILE" || true
    echo "" | tee -a "$REPORT_FILE"
else
    echo "⚠ iostat data collection failed" | tee -a "$REPORT_FILE"
fi

# pidstat 输出（独立脚本扩展）
if [ -s "${TMP_PIDSTAT}" ]; then
    echo "--- Process I/O Statistics (pidstat) ---" | tee -a "$REPORT_FILE"
    cat "${TMP_PIDSTAT}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

rm -rf "$TMPD"

# --------------------------------------------------------------------
# 9. Filesystem Mount Options
# --------------------------------------------------------------------
echo "=== Filesystem Mount Options ===" | tee -a "$REPORT_FILE"
if mount 2>/dev/null | grep -E '^/dev| type ext[234]| type xfs| type btrfs' | head -10 | tee -a "$REPORT_FILE"; then
    :
else
    echo "⚠ No filesystem mount information available" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# --------------------------------------------------------------------
# 10. NFS/CIFS Mount Options
# --------------------------------------------------------------------
echo "=== NFS/CIFS Mount Options ===" | tee -a "$REPORT_FILE"
nfs_mounts=$(mount 2>/dev/null | grep -E 'type nfs|type cifs' | awk 'NR<=10') || true
if [ -n "$nfs_mounts" ]; then
    echo "$nfs_mounts" | tee -a "$REPORT_FILE"
else
    echo "No NFS/CIFS mounts found" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# ====================================================================
# 完成 — 结尾块（与 server_data_collector.sh 一致）
# ====================================================================
{
    echo "============================================================"
    echo "I/O Metrics Analysis Complete"
    echo "============================================================"
} | tee -a "$REPORT_FILE"
echo "[OK] io-collection: 采集完成，报告 $REPORT_FILE" >&3
