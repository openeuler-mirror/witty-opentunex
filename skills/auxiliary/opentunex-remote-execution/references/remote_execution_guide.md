# Remote Execution Guide

This guide provides guide about remote execution.

## Handle Authentication Failure

1. read auth info file from `/opt/opentunex/config/client.yaml`:
```yaml
clients:
  192.168.1.100:
    username: root
    password: xxx
    port: 22
```

2. ask user for credentials

## setup passwordless access

1. check ssh key
```bash
cat ~/.ssh/*.pub 2>/dev/null || echo "NO_KEY"
```

2. generate ssh key
```bash
ssh-keygen
```

3. copy ssh key to remote
```bash
ssh-copy-id ${username}@${ip}
```

4. Verify Connection

```bash
ssh ${username}@${ip} echo 'Connection verified'
```

## File Upload Discipline (CRITICAL)

To deliver a local file to the client, ALWAYS use one of:

```bash
# Option A: scp then ssh-execute (preferred when the remote copy should persist)
scp <local> ${username}@${ip}:/tmp/<name>
ssh -q -tt ${username}@${ip} 'sh /tmp/<name>'

# Option B: stream-and-execute (no remote copy retained)
ssh -q -tt ${username}@${ip} 'bash -s' < <local>
```

NEVER read the file's content with the Read tool and inline it into an ssh command via heredoc / `echo >` / `printf >` / `tee`. This wastes tokens, fails on binary files, breaks on shell metacharacters (`$`, `\`, backticks, quotes), and produces a remote file that is not byte-identical to the source.

Heredocs are fine for *authoring a local script file before scp* — they are NOT for transporting file content across the SSH boundary.

## Command Execution Patterns

### Simple Commands

```bash
# Single command
ssh -q -tt ${username}@${ip} 'uname -r'

# Multiple commands
ssh -q -tt ${username}@${ip} 'cd /tmp && ls -la'
```

### Commands That Won't Fit In ssh (Fallback)

ssh direct execution is the default path. Reach for this fallback only when a command cannot be expressed inside a single ssh argv — argv length limits, hostile quoting, deeply nested escapes, etc.

When the fallback applies: **author the script locally as a file, then deliver it to the client with scp — never with an ssh inline write.**

```bash
# 1) Author the script as a local file. Heredoc here writes to LOCAL disk, not across SSH.
cat > /tmp/analyze.sh << 'SCRIPT'
#!/bin/bash
# Complex analysis commands
vmstat 1 10 > vmstat.log
pidstat -w 1 10 > pidstat.log
SCRIPT

# 2) Deliver it to the client with scp (the ONLY supported transport mechanism)
scp /tmp/analyze.sh ${username}@${ip}:/tmp/

# 3) Execute it on the client
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

Extend timeout to 1200+ seconds:

```bash
# With explicit timeout
timeout 1200 ssh -q -tt ${username}@${ip} 'perf sched record -a -- sleep 60'
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
timeout 1200 ssh -q -tt ${username}@${ip} 'long_command'
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
6. **Extend timeout** for collection commands (1200 sec)
7. **Request confirmation** for destructive operations
