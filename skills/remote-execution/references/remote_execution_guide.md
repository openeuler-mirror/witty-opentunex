# Remote Execution Guide

This guide provides detailed information about remote execution patterns used across all skills.

## Connection Workflow

### Step 1: Extract Client IP from Context

The client IP is provided in user input. Examples:
- "analyze lock bottleneck on 192.168.1.100"
- "check performance on root@192.168.1.100"
- "benchmark 10.0.0.50"

Extract the IP automatically, do NOT ask user for IP.

### Step 2: Test Passwordless SSH

```bash
# Try direct connection with keys
ssh -o ConnectTimeout=5 -o BatchMode=yes ${username}@${ip} echo 'OK'
```

If successful, proceed to command execution.

### Step 3: Handle Authentication Failure

If passwordless SSH fails:

1. Read from `/opt/opentunex/config/client.yaml`:
```yaml
clients:
  192.168.1.100:
    username: root
    password: xxx
    port: 22
```

2. If not found, ask user for credentials

3. Save to yaml file for future use

4. Test SSH with password

5. If successful, setup passwordless access:
```bash
ssh-copy-id ${username}@${ip}
```

### Step 4: Verify Connection

Final verification:
```bash
ssh ${username}@${ip} echo 'Connection verified'
```

## Command Execution Patterns

### Simple Commands

```bash
# Single command
ssh -q -tt ${username}@${ip} 'uname -r'

# Multiple commands
ssh -q -tt ${username}@${ip} 'cd /tmp && ls -la'
```

### Complex Commands

For complex operations with pipes, quotes, or long scripts:

```bash
# Create script locally
cat > /tmp/analyze.sh << 'SCRIPT'
#!/bin/bash
# Complex analysis commands
vmstat 1 10 > vmstat.log
pidstat -w 1 10 > pidstat.log
SCRIPT

# Copy to remote
scp /tmp/analyze.sh ${username}@${ip}:/tmp/

# Execute on remote
ssh -q -tt ${username}@${ip} 'sh /tmp/analyze.sh'
```

### Perf Commands

Perf requires pseudo-terminal for proper operation:

```bash
# Perf sched recording
ssh -q -tt ${username}@${ip} 'cd /tmp && perf sched record -a -- sleep 15'

# Perf analysis
ssh -q -tt ${username}@${ip} 'cd /tmp && perf sched latency'
```

### Data Collection

Collect data on remote, analyze on remote, never copy back:

```bash
# Collect
ssh -q -tt ${username}@${ip} 'cd /tmp && perf sched record -a -- sleep 30'

# Analyze on remote (no scp of perf.data)
ssh -q -tt ${username}@${ip} 'cd /tmp && perf sched latency > sched_latency.txt'
ssh -q -tt ${username}@${ip} 'cat /tmp/sched_latency.txt'

# For large data, use remote filtering
ssh -q -tt ${username}@${ip} 'cd /tmp && perf sched timehist | head -100'
```

## Timeout Handling

### Long Running Commands

Extend timeout to 300+ seconds:

```bash
# With explicit timeout
timeout 300 ssh -q -tt ${username}@${ip} 'perf sched record -a -- sleep 60'
```

### Background Execution

For very long operations:

```bash
# Start in background
ssh -q -tt ${username}@${ip} 'nohup sh long_task.sh > /tmp/output.log 2>&1 &'

# Check status later
ssh -q -tt ${username}@{ip} 'ps aux | grep long_task'
```

## Security Considerations

1. **Destructive Commands**: Always request user confirmation
   ```bash
   # WRONG - no confirmation
   ssh ${ip} 'rm -rf /var/log/*'

   # RIGHT - with confirmation
   echo "Confirm: Delete /var/log/* on ${ip}? (yes/no)"
   # Wait for confirmation
   ssh ${ip} 'rm -rf /var/log/*'
   ```

2. **Data Privacy**: Never copy sensitive data to local machine
   ```bash
   # WRONG
   scp ${username}@${ip}:/tmp/core.gz ./

   # RIGHT - analyze on remote
   ssh ${ip} 'gdb -ex "bt" -ex "quit" /tmp/core.gz'
   ```

3. **Credentials**: Store in secure location
   - Use `/opt/opentunex/config/client.yaml` (already configured)
   - Never hardcode passwords in scripts

## Error Handling

### Connection Errors

```bash
ssh -q -tt ${username}@${ip} 'command' 2>&1
if [ $? -ne 0 ]; then
  echo "Command failed on remote"
  # Handle error
fi
```

### Timeout Errors

```bash
timeout 60 ssh -q -tt ${username}@${ip} 'long_command'
if [ $? -eq 124 ]; then
  echo "Command timed out"
fi
```

## Best Practices

1. **Always use `-tt`** for perf/trace commands
2. **Never use `ssh` without flags** for important commands
3. **Use `ssh -q`** to suppress banner messages
4. **Keep scripts on remote** to avoid SCP issues
5. **Analyze remotely** - never copy large data back
6. **Extend timeout** for collection commands (300 sec)
7. **Request confirmation** for destructive operations
