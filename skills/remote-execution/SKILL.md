---
name: remote-execution
description: Remote execution framework for client-server analysis. Provides standardized SSH connection management, command execution patterns, and timeout handling for all skills that need to run commands on remote clients.
---

# Remote Execution Framework

This skill provides standardized client connection and command execution capabilities. It should be referenced by all skills that need to execute commands on remote client machines.

---

## Client Connection and Command Execution

**CRITICAL**: Before all phases, check client connection. The client IP is provided in the user context (e.g., "analyze lock bottleneck on 192.168.1.100"). Extract the IP from user input, do NOT ask user again for IP.

**Check for client connection**:
1. Extract client IP from user context (e.g., from "192.168.1.100" or "root@192.168.1.100" in user input)
2. Test passwordless SSH connection with extracted IP, if successful, continue;
3. If passwordless SSH connection failed, read client auth info (username, password, port) corresponding to the IP in `/opt/opentunex/config/client.yaml`, if not found, ask user to provide auth info and **save it** to `/opt/opentunex/config/client.yaml`;
4. Test if SSH connection works with the given auth info, if connection fails, ask user to provide correct info until SSH connection succeeds, then add local machine's public key to the client to ensure passwordless connection.

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. Use `ssh -q -tt` to remove useless banner.
**CRITICAL**: Must use `ssh -tt` to run command or script: pseudo-terminal is required for perf operation, `ssh -tt` provides such environment and ensures terminal control characters are properly handled. NEVER copy client data to local machine for analysis.
**Execution timeout**: these commands may execute for >5 min, opencode should **extend session TIMEOUT to 300 sec**.

**Example implementation**:
```bash
# Check client connection
ssh ${username}@${ip} echo 'test client connection'

# Execute simple command in client machine
ssh -q -tt ${username}@${ip} 'uname -r'

# Execute complex commands in client machine
scp /tmp/${complex_commands}.sh ${username}@${ip}:/tmp/
ssh -q -tt ${username}@${ip} sh /tmp/${complex_commands}.sh

# Execute perf related command or script
ssh -q -tt ${username}@${ip} 'cd /tmp/ && perf sched record -a -- sleep 15'
ssh -q -tt ${username}@${ip} 'cd /tmp/ && sh analyze_script.sh'
```

**Security notes**:
- ALL DESTRUCTIVE commands should request user's confirmation before execution
- NEVER copy client data to local machine for analysis
- All analysis should be performed on the remote client machine

---

## Usage in Other Skills

To use this skill in other skills, add the following reference at the beginning of the skill:

```markdown
---

## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution

---

## [Continue with your skill-specific phases]
```

This replaces the duplicated Client Connection and Command Execution section in each skill.

---

## Supporting Scripts

### scripts/check_client_connection.sh

A helper script to verify client connectivity:

```bash
#!/bin/bash
# Check client connection helper script
# Usage: check_client_connection.sh <user@host>

REMOTE_HOST=${1:-}

if [ -z "$REMOTE_HOST" ]; then
  echo "Usage: $0 <user@host>"
  exit 1
fi

echo "Checking connection to $REMOTE_HOST..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_HOST" echo 'OK'; then
  echo "Connection successful"
  exit 0
else
  echo "Connection failed"
  exit 1
fi
```

### scripts/execute_remote.sh

A helper script to execute commands on remote client:

```bash
#!/bin/bash
# Execute commands on remote client
# Usage: execute_remote.sh <user@host> <command>

REMOTE_HOST=${1:-}
COMMAND=${2:-}

if [ -z "$REMOTE_HOST" ] || [ -z "$COMMAND" ]; then
  echo "Usage: $0 <user@host> <command>"
  exit 1
fi

ssh -q -tt "$REMOTE_HOST" '$COMMAND'
```

---

## Reference

For detailed information, see [references/remote_execution_guide.md](references/remote_execution_guide.md).
