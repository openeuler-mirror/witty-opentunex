#!/bin/bash
# Collect perf scheduling trace data from remote machine via SSH
# Usage: collect_remote_sched_trace.sh <user@host> [duration]

set -e

REMOTE_HOST=${1:-}
DURATION=${2:-30}
WORK_DIR="/tmp/sched_analysis_$(date +%s)"

if [ -z "$REMOTE_HOST" ]; then
  echo "Usage: $0 <user@host> [duration]"
  echo "Example: $0 root@192.168.1.100 30"
  exit 1
fi

echo "=== Remote Scheduling Trace Collection ==="
echo "Remote host: $REMOTE_HOST"
echo "Duration: ${DURATION}s"
echo "Work directory: $WORK_DIR"
echo ""

# Check SSH connection
echo "[1/4] Checking SSH connection..."
ssh -t $REMOTE_HOST "echo 'SSH connection OK'" || {
  echo "Error: SSH connection failed"
  echo "Please ensure:"
  echo "  - SSH is accessible"
  echo "  - Passwordless SSH is configured (ssh-copy-id)"
  exit 1
}
echo "   ✓ SSH connection OK"
echo ""

# Create working directory
echo "[2/4] Creating working directory..."
ssh -t $REMOTE_HOST "mkdir -p $WORK_DIR"
echo "   ✓ Working directory created: $WORK_DIR"
echo ""

# Record perf data
echo "[3/4] Recording perf scheduling data..."
echo "   This will take ${DURATION} seconds..."
echo "   Command: perf sched record -a -e sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new,sched:sched_migrate_task -- sleep ${DURATION}"

ssh -t $REMOTE_HOST "cd $WORK_DIR && perf sched record -a -e sched:sched_switch -e sched:sched_wakeup -e sched:sched_wakeup_new -e sched:sched_migrate_task -- sleep ${DURATION} > /dev/null 2>&1" || {
  echo "Error: perf record failed"
  ssh -t $REMOTE_HOST "rm -rf $WORK_DIR"
  exit 1
}
echo "   ✓ Recording completed"
echo ""

# Check result
echo "[4/4] Checking collected data..."
DATA_SIZE=$(ssh -t $REMOTE_HOST "ls -lh $WORK_DIR/perf.data" | awk '{print \$5}')
echo "   Data size: $DATA_SIZE"
echo ""

# Return data location
echo "=== Collection Complete ==="
echo "Remote data location: $REMOTE_HOST:$WORK_DIR/perf.data"
echo ""
echo "To download the data:"
echo "  scp $REMOTE_HOST:$WORK_DIR/perf.data ./"
echo ""
echo "To analyze on remote machine:"
echo "  ssh -t $REMOTE_HOST 'cd $WORK_DIR && perf sched latency'"
echo "  ssh -t $REMOTE_HOST 'cd $WORK_DIR && perf sched script | head -100'"
echo ""
echo "To cleanup:"
echo "  ssh -t $REMOTE_HOST 'rm -rf $WORK_DIR'"
