#!/bin/bash
# collect_io_metrics.sh - Collect I/O metrics for bottleneck analysis
# Usage: collect_io_metrics.sh [--pid <PID>] [--duration <SECONDS>]

DURATION=15
TARGET_PID=""
INTERVAL=1

parse_param() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pid)
                TARGET_PID="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: bash $0 [--pid <PID>] [--duration <SECONDS>]" >&2
                exit 1
                ;;
        esac
    done
}

collect_io_metrics() {
    echo "=== I/O Metrics Collection ==="
    echo "Duration: $DURATION seconds"
    if [ -n "$TARGET_PID" ]; then
        echo "Target PID: $TARGET_PID"
    fi
    echo ""

    echo "=== System Overview ==="
    uname -r
    echo "CPU Count: $(nproc)"
    echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
    echo ""

    echo "=== Disk Devices ==="
    lsblk -d -n -o NAME,SIZE,TYPE | grep -E 'disk|nvme'
    echo ""

    echo "=== I/O Scheduler Configuration ==="
    for dev in $(lsblk -d -n -o NAME | grep -E '^vd|^sd|^nvme' | head -5); do
        echo "--- /dev/$dev ---"
        echo "scheduler: $(cat /sys/block/$dev/queue/scheduler 2>/dev/null | grep -o '\[.*\]' || echo 'N/A')"
        echo "nr_requests: $(cat /sys/block/$dev/queue/nr_requests 2>/dev/null || echo 'N/A')"
        echo "read_ahead_kb: $(cat /sys/block/$dev/queue/read_ahead_kb 2>/dev/null || echo 'N/A')"
        echo "max_sectors_kb: $(cat /sys/block/$dev/queue/max_sectors_kb 2>/dev/null || echo 'N/A')"
        echo "timeout: $(cat /sys/block/$dev/queue/timeout 2>/dev/null || echo 'N/A')"
        echo "rotational: $(cat /sys/block/$dev/queue/rotational 2>/dev/null || echo 'N/A')"
        echo "add_random: $(cat /sys/block/$dev/queue/add_random 2>/dev/null || echo 'N/A')"
        echo "rq_affinity: $(cat /sys/block/$dev/queue/rq_affinity 2>/dev/null || echo 'N/A')"
        echo "nomerges: $(cat /sys/block/$dev/queue/nomerges 2>/dev/null || echo 'N/A')"
        echo ""
    done

    echo "=== Memory/Page Cache Settings ==="
    echo "vfs_cache_pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
    echo "swappiness: $(cat /proc/sys/vm/swappiness)"
    echo "dirty_background_ratio: $(cat /proc/sys/vm/dirty_background_ratio)"
    echo "dirty_ratio: $(cat /proc/sys/vm/dirty_ratio)"
    echo "dirty_writeback_centisecs: $(cat /proc/sys/vm/dirty_writeback_centisecs)"
    echo "dirty_expire_centisecs: $(cat /proc/sys/vm/dirty_expire_centisecs)"
    echo "min_free_kbytes: $(cat /proc/sys/vm/min_free_kbytes)"
    echo "page-cluster: $(cat /proc/sys/vm/page-cluster)"
    echo "overcommit_memory: $(cat /proc/sys/vm/overcommit_memory)"
    echo "overcommit_ratio: $(cat /proc/sys/vm/overcommit_ratio)"
    echo "oom_dump_tasks: $(cat /proc/sys/vm/oom_dump_tasks)"
    echo ""

    if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
        echo "=== Process I/O Configuration (PID $TARGET_PID) ==="

        echo "--- IO Priority ---"
        ionice -p $TARGET_PID 2>/dev/null || echo "  ionice not available"

        echo "--- IO Statistics ---"
        if [ -f /proc/$TARGET_PID/io ]; then
            cat /proc/$TARGET_PID/io | while IFS=: read key val; do
                printf "  %-25s %s\n" "$key" "${val# }"
            done
        else
            echo "  /proc/$TARGET_PID/io not available"
        fi

        echo "--- Open Files Limit ---"
        soft=$(awk '/Max open files/ {print $4}' /proc/$TARGET_PID/limits)
        hard=$(awk '/Max open files/ {print $5}' /proc/$TARGET_PID/limits)
        echo "  soft=$soft  hard=$hard"

        fd_count=$(ls /proc/$TARGET_PID/fd/ 2>/dev/null | wc -l)
        [ "$fd_count" -gt 0 ] && echo "  open_fds=$fd_count"

        echo "--- cgroup IO Throttling ---"
        cg_path=$(awk -F: '/blkio/ {print $3}' /proc/$TARGET_PID/cgroup 2>/dev/null)
        if [ -n "$cg_path" ]; then
            cg_base="/sys/fs/cgroup/blkio${cg_path}"
            cg_base=$(echo "$cg_base" | sed 's#//#/#')
            throttled=0
            for throttle in read_bps_device write_bps_device read_iops_device write_iops_device; do
                f="${cg_base}/blkio.throttle.${throttle}"
                if [ -f "$f" ] && [ -s "$f" ]; then
                    echo "  $throttle: $(tr '\n' ' ' < "$f")"
                    throttled=1
                fi
            done
            v2_base="/sys/fs/cgroup${cg_path}"
            v2_base=$(echo "$v2_base" | sed 's#//#/#')
            if [ -f "${v2_base}/io.max" ] && [ -s "${v2_base}/io.max" ]; then
                echo "  io.max: $(tr '\n' ' ' < "${v2_base}/io.max")"
                throttled=1
            fi
            [ $throttled -eq 0 ] && echo "  No IO throttling configured for this process"
        else
            echo "  Process not in blkio cgroup"
        fi

        echo ""
    fi

    echo "=== System-wide I/O Limits ==="
    echo "--- AIO Limits ---"
    echo "aio-max-nr: $(cat /proc/sys/fs/aio-max-nr 2>/dev/null || echo 'N/A')"
    echo "aio-nr:     $(cat /proc/sys/fs/aio-nr 2>/dev/null || echo 'N/A')"
    if [ -r /proc/sys/fs/aio-max-nr ] && [ -r /proc/sys/fs/aio-nr ]; then
        max=$(cat /proc/sys/fs/aio-max-nr)
        cur=$(cat /proc/sys/fs/aio-nr)
        if [ "$max" -gt 0 ]; then
            pct=$((cur * 100 / max))
            [ "$pct" -gt 80 ] && echo "  WARNING: AIO usage at ${pct}% — consider increasing aio-max-nr"
        fi
    fi

    echo "--- File Handle Limits ---"
    echo "file-max: $(cat /proc/sys/fs/file-max 2>/dev/null || echo 'N/A')"
    awk '{printf "file-nr:  allocated=%s  free=%s  max=%s\n", $1, $2, $3}' /proc/sys/fs/file-nr 2>/dev/null

    echo "--- Per-process FD Limit ---"
    echo "nr_open: $(cat /proc/sys/fs/nr_open 2>/dev/null || echo 'N/A')"

    echo "--- Inotify Limits ---"
    echo "max_user_watches: $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 'N/A')"
    echo "max_user_instances: $(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 'N/A')"
    echo ""
    echo "=== cgroup IO Weight ==="
    cgroup_found=0
    if [ -f /sys/fs/cgroup/blkio/blkio.weight ]; then
        echo "blkio.weight: $(cat /sys/fs/cgroup/blkio/blkio.weight 2>/dev/null)"
        cgroup_found=1
    fi
    if [ -f /sys/fs/cgroup/io.weight ]; then
        echo "io.weight: $(cat /sys/fs/cgroup/io.weight 2>/dev/null)"
        cgroup_found=1
    fi
    [ $cgroup_found -eq 0 ] && echo "IO weight not configured (neither cgroup v1 blkio nor v2 io controller)"
    echo ""

    echo "=== Filesystem Mount Options ==="
    mount | grep -E '^/dev| type ext[234]| type xfs| type btrfs' | head -10
    echo ""

    echo "=== NFS Mount Options ==="
    nfs_mounts=$(mount | grep -E 'type nfs|type cifs' | head -10)
    if [ -n "$nfs_mounts" ]; then
        echo "$nfs_mounts"
    else
        echo "No NFS/CIFS mounts found"
    fi
    echo ""

    echo "=== ext4 Journal Configuration ==="
    ext4_found=0
    for fs in $(mount | grep 'type ext4' | awk '{print $1}' | head -5); do
        echo "--- $fs ---"
        if command -v tune2fs &> /dev/null; then
            journal_info=$(tune2fs -l $fs 2>/dev/null | grep -iE '^Journal|^Commit' || true)
            if [ -n "$journal_info" ]; then
                echo "$journal_info"
            else
                echo "  No journal info available (tune2fs may need root)"
            fi
        else
            echo "  tune2fs not available"
        fi
        ext4_found=1
    done
    [ $ext4_found -eq 0 ] && echo "No ext4 filesystems found"
    echo ""

    echo "=== Disk IRQ Affinity ==="
    for dev in $(lsblk -d -n -o NAME | grep -E '^vd|^sd|^nvme' | head -5); do
        echo "--- /dev/$dev ---"
        found=0

        for irq_dir in /sys/block/$dev/device/msi_irqs /sys/block/$dev/device/../msi_irqs /sys/block/$dev/device/../../msi_irqs; do
            [ ! -d "$irq_dir" ] && continue
            count=0
            for irq_file in "$irq_dir"/*; do
                [ ! -f "$irq_file" ] && continue
                irq_num=$(basename "$irq_file")
                [ "$irq_num" = "msi" ] && continue
                affinity="N/A"
                [ -f "/proc/irq/$irq_num/smp_affinity" ] && affinity=$(cat "/proc/irq/$irq_num/smp_affinity")
                echo "  IRQ $irq_num: affinity=$affinity"
                found=1
                count=$((count + 1))
                [ $count -ge 8 ] && break
            done
            [ $found -eq 1 ] && break
        done

        if [ $found -eq 0 ]; then
            pci_bdf=""
            path=$(readlink -f /sys/block/$dev/device 2>/dev/null)
            while [ "$path" != "/" ] && [ "$path" != "." ] && [ -z "$pci_bdf" ]; do
                if echo "$(basename "$path")" | grep -qE '^0000:'; then
                    pci_bdf="$path"
                    break
                fi
                path=$(dirname "$path")
            done
            if [ -n "$pci_bdf" ] && [ -d "$pci_bdf/msi_irqs" ]; then
                count=0
                for irq_file in "$pci_bdf/msi_irqs"/*; do
                    [ -f "$irq_file" ] || continue
                    irq_num=$(basename "$irq_file")
                    affinity="N/A"
                    [ -f "/proc/irq/$irq_num/smp_affinity" ] && affinity=$(cat "/proc/irq/$irq_num/smp_affinity")
                    echo "  MSI IRQ $irq_num: affinity=$affinity"
                    found=1
                    count=$((count + 1))
                    [ $count -ge 8 ] && break
                done
            fi
            if [ $found -eq 0 ] && [ -n "$pci_bdf" ] && [ -f "$pci_bdf/irq" ]; then
                irq_num=$(cat "$pci_bdf/irq")
                affinity="N/A"
                [ -f "/proc/irq/$irq_num/smp_affinity" ] && affinity=$(cat "/proc/irq/$irq_num/smp_affinity")
                echo "  PCI IRQ $irq_num: affinity=$affinity"
                found=1
            fi
        fi

        if [ $found -eq 0 ]; then
            driver_path=$(readlink -f /sys/block/$dev/device/driver 2>/dev/null)
            if [ -n "$driver_path" ]; then
                drv=$(basename "$driver_path")
                grep -i "$drv" /proc/interrupts 2>/dev/null | head -8 | while read line; do
                    irq_num=$(echo "$line" | awk '{print $1}' | tr -d ':')
                    irq_name=$(echo "$line" | awk '{print $NF}')
                    affinity="N/A"
                    [ -f "/proc/irq/$irq_num/smp_affinity" ] && affinity=$(cat "/proc/irq/$irq_num/smp_affinity")
                    echo "  IRQ $irq_num ($irq_name): affinity=$affinity"
                done
                found=1
            fi
        fi

        [ $found -eq 0 ] && echo "  No IRQ affinity info available"
    done
    echo ""

    echo "=== blk-mq Configuration ==="
    for dev in $(lsblk -d -n -o NAME | grep -E '^vd|^sd|^nvme' | head -5); do
        if [ -d /sys/block/$dev/mq ]; then
            echo "--- /dev/$dev ---"
            echo "mq_queues: $(ls /sys/block/$dev/mq/ 2>/dev/null | wc -w)"
            nr_tags=$(cat /sys/block/$dev/mq/0/nr_reserved_tags 2>/dev/null)
            [ -n "$nr_tags" ] && echo "nr_reserved_tags: $nr_tags"
            numa=$(cat /sys/block/$dev/device/numa_node 2>/dev/null)
            [ -n "$numa" ] && echo "numa_node: $numa"
        fi
    done
    echo ""

    echo "=== Extended Disk Stats (/proc/diskstats) ==="
    awk '$3 !~ /[0-9]$/ && $3 !~ /^loop|^ram/ {print}' /proc/diskstats | head -20
    echo ""

    echo "=== IO Throttling (cgroup blkio) ==="
    if [ -f /sys/fs/cgroup/blkio/blkio.throttle.read_bps_device ]; then
        throttle_r=$(cat /sys/fs/cgroup/blkio/blkio.throttle.read_bps_device 2>/dev/null)
        throttle_w=$(cat /sys/fs/cgroup/blkio/blkio.throttle.write_bps_device 2>/dev/null)
        if [ -n "$throttle_r" ] || [ -n "$throttle_w" ]; then
            [ -n "$throttle_r" ] && echo "read_bps:  $throttle_r"
            [ -n "$throttle_w" ] && echo "write_bps: $throttle_w"
        else
            echo "No IO throttling configured"
        fi
    else
        echo "IO throttling not available (blkio cgroup v1 not mounted)"
    fi
    echo ""

    if command -v lvs &> /dev/null; then
        echo "=== LVM Logical Volumes ==="
        lvs 2>/dev/null
        echo ""
        echo "=== LVM Volume Groups ==="
        vgs 2>/dev/null
        echo ""
    fi

    if [ -f /proc/mdstat ]; then
        echo "=== MD RAID Status ==="
        cat /proc/mdstat 2>/dev/null
        echo ""
    fi

    echo "=== Initial VMStat (1 sample) ==="
    vmstat 1 1
    echo ""

    echo "=== IOStat Extended Stats (1 sample) ==="
    if command -v iostat &> /dev/null; then
        iostat -x 1 1
    else
        echo "iostat not available (install sysstat)"
    fi
    echo ""

    echo "=== Starting Background Collection (${DURATION}s) ==="

    vmstat $INTERVAL $DURATION > /tmp/vmstat_output.txt &
    VMSTAT_PID=$!

    if command -v iostat &> /dev/null; then
        iostat -x $INTERVAL $DURATION > /tmp/iostat_output.txt 2>&1 &
        IOSTAT_PID=$!
    else
        echo "iostat not available" > /tmp/iostat_output.txt
        IOSTAT_PID=""
    fi

    if command -v pidstat &> /dev/null; then
        pidstat -d $INTERVAL $DURATION > /tmp/pidstat_d_output.txt 2>&1 &
        PIDSTAT_PID=$!
    fi

    if command -v mpstat &> /dev/null; then
        mpstat -P ALL $INTERVAL $DURATION > /tmp/mpstat_output.txt 2>&1 &
        MPSTAT_PID=$!
    fi

    wait $VMSTAT_PID
    [ -n "$IOSTAT_PID" ] && wait $IOSTAT_PID
    [ -n "$PIDSTAT_PID" ] && wait $PIDSTAT_PID
    [ -n "$MPSTAT_PID" ] && wait $MPSTAT_PID

    echo "Collection complete."
    echo ""

    echo "=== Collected Data Summary ==="
    echo ""
    echo "--- VMStat Summary ---"
    awk 'NR<=2 || /^[[:space:]]*[0-9]/' /tmp/vmstat_output.txt | head -15
    echo ""

    echo "--- I/O Wait Analysis ---"
    if [ -f /tmp/mpstat_output.txt ]; then
        mpstat_iowait=$(awk '$3 ~ /^[0-9]+$/ && $6 > 10 {printf "CPU %s: iowait %s%%\n", $3, $6}' /tmp/mpstat_output.txt | sort -t: -k2 -rn | head -10)
        if [ -n "$mpstat_iowait" ]; then
            echo "$mpstat_iowait"
        else
            echo "No CPUs with iowait > 10%"
        fi
    fi
    echo ""

    echo "--- Disk Utilization Summary ---"
    if [ -f /tmp/iostat_output.txt ]; then
        disk_util=$(awk '$1 ~ /^[a-z]/ && $NF+0 > 0 {
            printf "%-10s util=%s%%  r/s=%s  w/s=%s  rKB/s=%s  wKB/s=%s  await=%s\n", $1, $NF, $2, $9, $3, $10, $5
        }' /tmp/iostat_output.txt | head -20)
        if [ -n "$disk_util" ]; then
            echo "$disk_util"
        else
            echo "No disk I/O activity detected during monitoring period"
        fi
    fi
    echo ""

    echo "--- I/O Pattern Analysis (Sequential vs Random) ---"
    echo "High rrqm/s+wrqm/s + large avgrq-sz = Sequential"
    echo "Low/No merge + small avgrq-sz = Random"
    if [ -f /tmp/iostat_output.txt ]; then
        io_pattern=$(awk '$1 ~ /^[a-z]/ && (($4+0)>0 || ($5+0)>0 || ($11+0)>0 || ($12+0)>0) {
            ratio = ($4+$5)/($4+$5+$6+$7+0.1)*100
            printf "  %s: merge=%.1f%%  avg_req=%d sect  pattern=", $1, ratio, $8
            if (ratio > 30 && $8 > 32) print "SEQUENTIAL"
            else if (ratio < 10 && $8 < 16) print "RANDOM"
            else print "MIXED"
        }' /tmp/iostat_output.txt | head -10)
        if [ -n "$io_pattern" ]; then
            echo "$io_pattern"
        else
            echo "No I/O operations during monitoring period"
        fi
    fi
    echo ""

    echo "--- Top I/O Processes ---"
    if [ -f /tmp/pidstat_d_output.txt ]; then
        awk 'NF==9 && $4 ~ /^[0-9]+$/ && ($5+$6+0)>0 {
            printf "  PID=%s  rd=%s kB/s  wr=%s kB/s  iodelay=%s  cmd=%s\n", $4, $5, $6, $8, $9
        }' /tmp/pidstat_d_output.txt | sort -t'=' -k4 -rn 2>/dev/null | head -10
        if ! awk 'NF==9 && $4 ~ /^[0-9]+$/ && ($5+$6+0)>0 {found=1; exit} END {exit !found}' /tmp/pidstat_d_output.txt; then
            echo "  No process I/O activity detected"
        fi
    fi
    echo ""

    rm -f /tmp/vmstat_output.txt /tmp/iostat_output.txt /tmp/pidstat_d_output.txt /tmp/mpstat_output.txt
}

parse_param "$@"
collect_io_metrics
