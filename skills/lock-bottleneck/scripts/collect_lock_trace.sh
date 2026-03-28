#!/bin/bash
# Collect OS lock trace data from remote machine via SSH
# Usage: collect_lock_trace.sh <user@host> [duration]

set -e

REMOTE_HOST=${1:-}
DURATION=${2:-30}
WORK_DIR="/tmp/lock_analysis_$(date +%s)"

if [ -z "$REMOTE_HOST" ]; then
  echo "Usage: $0 <user@host> [duration]"
  echo "Example: $0 root@192.168.1.100 30"
  exit 1
fi

echo "=== Remote Lock Trace Collection ==="
echo "Remote host: $REMOTE_HOST"
echo "Duration: ${DURATION}s"
echo "Work directory: $WORK_DIR"
echo ""

# Check SSH connection
echo "[1/5] Checking SSH connection..."
ssh -t $REMOTE_HOST "echo 'SSH connection OK'" || {
  echo "Error: SSH connection failed"
  echo "Please ensure:"
  echo "  - SSH is accessible"
  echo "  - Passwordless SSH is configured (ssh-copy-id)"
  exit 1
}
echo "   SSH connection OK"
echo ""

# Create working directory
echo "[2/5] Creating working directory..."
ssh -t $REMOTE_HOST "mkdir -p $WORK_DIR"
echo "   Working directory created: $WORK_DIR"
echo ""

# Record perf data with futex and scheduling events
echo "[3/5] Recording perf lock and scheduling data..."
echo "   This will take ${DURATION} seconds..."
echo "   Command: perf record -a -e syscalls:sys_enter_futex -e syscalls:sys_exit_futex -e sched:sched_switch -e sched:sched_wakeup -- sleep ${DURATION}"

ssh -t $REMOTE_HOST "cd $WORK_DIR && perf record -a -e syscalls:sys_enter_futex -e syscalls:sys_exit_futex -e sched:sched_switch -e sched:sched_wakeup -e sched:sched_wakeup_new -e sched:sched_migrate_task -- sleep ${DURATION} > /dev/null 2>&1" || {
  echo "Error: perf record failed"
  ssh -t $REMOTE_HOST "rm -rf $WORK_DIR"
  exit 1
}
echo "   Recording completed"
echo ""

# Collect system state
echo "[4/5] Collecting system state..."

# Collect vmstat baseline
ssh -t $REMOTE_HOST "vmstat 1 ${DURATION} > $WORK_DIR/vmstat.log" &

# Collect pidstat
ssh -t $REMOTE_HOST "pidstat -w 1 ${DURATION} > $WORK_DIR/pidstat.log" &

# Collect process state
ssh -t $REMOTE_HOST "ps -eo pid,comm,state,wchan:32,cmd > $WORK_DIR/process_state.log" &

# Collect softirqs
ssh -t $REMOTE_HOST "cat /proc/softirqs > $WORK_DIR/softirqs.log" &

# Collect locks
ssh -t $REMOTE_HOST "cat /proc/locks > $WORK_DIR/locks.log" &

wait
echo "   System state collected"
echo ""

# Check result
echo "[5/5] Checking collected data..."
DATA_SIZE=$(ssh -t $REMOTE_HOST "ls -lh $WORK_DIR/perf.data" | awk '{print \$5}')
echo "   Data size: $DATA_SIZE"
echo ""

# Return data location
echo "=== Collection Complete ==="
echo "Remote data location: $REMOTE_HOST:$WORK_DIR/"
echo ""
echo "To analyze on remote machine:"
echo "  ssh -t $REMOTE_HOST 'cd $WORK_DIR && perf sched latency'"
echo "  ssh -t $REMOTE_HOST 'cd $WORK_DIR && perf sched timehist | head -100'"
echo "  ssh -t $REMOTE_HOST 'cd $WORK_DIR && perf script | grep futex | head -100'"
echo ""
echo "To analyze lock contention:"
echo "  ssh -t $REMOTE_HOST 'cd $WORK_DIR && sh analyze_lock_contention.sh'"
echo ""
echo "To cleanup:"
echo "  ssh -t $REMOTE_HOST 'rm -rf $WORK_DIR'"
