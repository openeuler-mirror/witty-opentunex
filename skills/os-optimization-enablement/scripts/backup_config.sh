#!/bin/bash
BACKUP_DIR="/opt/opentunex/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

sysctl -a > "$BACKUP_DIR/sysctl_current.txt"
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.backup" 2>/dev/null || true
cp /etc/sysctl.d/*.conf "$BACKUP_DIR/" 2>/dev/null || true

cat /proc/cmdline > "$BACKUP_DIR/cmdline.txt"
cat /proc/sys/vm/* > "$BACKUP_DIR/vm_params.txt"

for dev in /sys/block/*/queue/scheduler; do
    dev_name=$(basename $(dirname $dev))
    cat "$dev" > "$BACKUP_DIR/scheduler_${dev_name}.txt"
done

cat > "$BACKUP_DIR/backup_manifest.txt" << 'EOF'
Backup Date: $(date)
Backup Type: Pre-optimization
Backup Files:
- sysctl_current.txt
- sysctl.conf.backup
- sysctl.d/*
- cmdline.txt
- vm_params.txt
- scheduler_*.txt
EOF

echo "Backup completed. Files stored in: $BACKUP_DIR"
