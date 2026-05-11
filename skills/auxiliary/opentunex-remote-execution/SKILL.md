---
name: remote-execution
description: Remote execution framework for client-server analysis. Provides standardized SSH connection management, command execution patterns, and timeout handling for all skills that need to run commands on remote clients.
---

# Remote Execution Framework

This skill provides standardized client connection and command execution capabilities. It should be referenced by all skills that need to execute commands on remote client machines.

---

## Client Connection Setup

**CRITICAL**: Before all phases, check client connection. The client IP is provided in the user context (e.g., "analyze lock bottleneck on 192.168.1.100"). Extract the IP from user input, do NOT ask user again for IP.

**setup client connection**:
1. Extract client IP from user context (e.g., from "192.168.1.100" or "root@192.168.1.100" in user input)
2. Test passwordless SSH connection with extracted IP, if successful, setup done;
3. setup passwordless SSH connection
    3.1 read client auth info (username, password, port) corresponding to the IP in `/opt/opentunex/config/client.yaml`
      - if found, test if SSH connection works with the given auth info
      - if not found or connection test fails, ask user to provide correct auth info, and append auth info to `/opt/opentunex/config/client.yaml`
    3.2 generate public key for local machine if not existing, add public key to the client to ensure passwordless connection.

## Remote Command Execution Guide

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. Use `ssh -q -tt` to remove useless banner.
**CRITICAL**: Must use `ssh -tt` to run command or script: pseudo-terminal is required for perf operation, `ssh -tt` provides such environment and ensures terminal control characters are properly handled. NEVER copy client data to local machine for analysis.
**Execution timeout**: these commands may execute for >5 min, opencode should **extend session TIMEOUT to 300 sec**.

**Example implementation**:
```bash
# Check client connection
ssh -o ConnectTimeout=5 ${username}@${ip} echo 'test client connection'

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

## Reference

For detailed information, see [references/remote_execution_guide.md](references/remote_execution_guide.md).
