#!/bin/bash
# Memory stress script to create memory bottleneck scenario
# Run in background to create persistent memory pressure

MEMORY_STRESS_SIZE=${1:-2048}  # MB, default 2GB

echo "Starting memory stress with ${MEMORY_STRESS_SIZE}MB..."

# Allocate memory in chunks and touch it to ensure it's actually used
python3 << EOF &
import subprocess
import time
import os

# Allocate and stress memory
size_mb = ${MEMORY_STRESS_SIZE}
chunk_size = 100  # MB per chunk

allocated = []
for i in range(size_mb // chunk_size):
    try:
        # Create a memory allocation
        data = bytearray(chunk_size * 1024 * 1024)
        # Touch all pages to ensure they're allocated
        for j in range(0, len(data), 4096):
            data[j] = 1
        allocated.append(data)
        print(f"Allocated {len(allocated) * chunk_size} MB so far...")
        time.sleep(0.1)
    except MemoryError:
        print("Memory allocation failed - system under memory pressure")
        break

print(f"Total allocated: {len(allocated) * chunk_size} MB")
print("Keeping memory allocated...")

# Keep the process alive
try:
    while True:
        time.sleep(60)
        # Periodically touch memory to prevent swapping
        for data in allocated:
            data[0] = data[0]
except:
    pass
EOF

MEM_PID=$!
echo $MEM_PID > /tmp/mem_stress_pid

# Also create some swap pressure with stress-ng alternative
if command -v stress-ng &> /dev/null; then
    stress-ng --vm 2 --vm-bytes ${MEMORY_STRESS_SIZE}M --timeout 999999s &
    echo $! > /tmp/stress_vm_pid
else
    # Fallback: use dd to create memory pressure via cache
    (
        while true; do
            dd if=/dev/zero of=/tmp/memstress bs=1M count=500 2>/dev/null
            sync
            rm -f /tmp/memstress
            sleep 5
        done
    ) &
    echo $! > /tmp/dd_stress_pid
fi

echo "Memory stress started"
echo "PIDs: $(cat /tmp/mem_stress_pid), $(cat /tmp/stress_vm_pid 2>/dev/null || echo 'n/a'), $(cat /tmp/dd_stress_pid 2>/dev/null || echo 'n/a')"