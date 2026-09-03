---
name: opentunex-remote-execution
description: Remote execution framework for client-server analysis. Provides standardized SSH connection management, command execution patterns, and timeout handling for all skills that need to run commands on remote clients.
---

# Remote Execution Framework

This skill provides standardized client connection and command execution capabilities. It should be referenced by all skills that need to execute commands on remote client machines.

**The remote client is expected to be Linux regardless of the agent host OS.** Only the commands the agent itself runs on its local machine differ between platforms. Branches below pick the right guide file for those LOCAL commands.

**Remote `${WORK_DIR}` semantics**: when the analysis target is a remote server, `${WORK_DIR}` (initialized by `witty-opentunex` as `/srv/opentunex/<YYYYMMDD_HHMMSS>/`) is a path ON THE REMOTE server. Every operation touching it must go through this skill's ssh mechanism. All skills that consume `${WORK_DIR}` MUST also load [references/work_dir_remote_semantics.md](references/work_dir_remote_semantics.md).

---

## Platform Detection (RUN THIS FIRST)

Before doing anything else, determine which platform the agent host runs on, then load the matching reference guide. Skipping this step is the #1 cause of retry cascades on Windows — the Linux guide hard-codes paths and commands (`/opt/opentunex/...`, `ssh-copy-id`, `timeout`, heredoc) that do not exist on Windows and the agent will burn many attempts trying to invent workarounds.

Run this single check, then read the indicated guide before proceeding:

```bash
# Cross-shell detection — works in PowerShell, Git Bash, and native bash.
# - WINDIR is set by Windows for all child processes (incl. Git Bash).
# - OS=Windows_NT is set by Git Bash. On native Linux/macOS, OS is unset
#   or is "Linux"/"Darwin".
if [ -n "$WINDIR" ] || { [ -n "$OS" ] && echo "$OS" | grep -qi "windows"; }; then
    echo "WINDOWS"
else
    echo "LINUX"
fi
```

```powershell
# PowerShell-native equivalent (preferred on Windows hosts)
if ($env:OS -match "Windows") { "WINDOWS" } else { "LINUX" }
```

**After detection:**
- `WINDOWS` → load `references/remote_execution_guide_windows.md` and follow IT for every LOCAL command in the rest of this skill.
- `LINUX` (or `Darwin` / anything else) → load `references/remote_execution_guide.md`. Behavior is unchanged from previous versions of this skill.

Both reference files share the same conceptual structure (auth → key setup → file upload → command patterns → timeout → security → errors), so once you have picked the right one you can map sections 1:1 between them. The Windows guide exists specifically to handle the LOCAL-side syntax differences (PowerShell vs bash) and to fix the Linux-only commands that fail outright on Windows.

---

## Client Connection Setup

**CRITICAL**: Before all phases, check client connection. The client IP is provided in the user context (e.g., "analyze lock bottleneck on 192.168.1.100"). Extract the IP from user input, do NOT ask user again for IP.

**setup client connection**:
1. Extract client IP from user context (e.g., from "192.168.1.100" or "root@192.168.1.100" in user input). Default username to "root" if only an IP was given.
2. Test passwordless SSH connection with extracted IP, if successful, setup done;
3. If passwordless SSH connection test fails, ask user to provide correct auth info, generate public key if not existing, and copy public key to the client to ensure passwordless connection.

## Remote Command Execution Guide

**Command execution**: all commands for client should be executed via `ssh`, considering the limits of ssh, allow converting commands to bash script and scp to client and execute if needed. Use `ssh -q -tt` to remove useless banner.

**Decision rule (which mechanism to pick)**:

1. **Input is a path to a script file** (`.sh` / `.bash` / `.py` …) **that already exists locally** → **MUST** `scp` it to `/tmp/<name>` on the client, then `ssh -q -tt` to execute it. **This is the ONLY valid path for script files — never treat a script file reference as a command string.**
2. **Input is a command string that references a script path on the remote** (e.g., `bash scripts/collect_all.sh ...`) → **CHECK first** whether the script exists on the remote. If it does NOT exist on the remote (the common case), fall back to rule 1: scp the local script to the remote first, then execute.
3. **Input is a pure command string** (e.g., `uname -r`, `cat /proc/cpuinfo` — no local script file involved) → `ssh -q -tt ${user}@${ip} '<command>'` directly. Use quotes / `bash -c` to handle pipes and quoting; do NOT author a brand-new local file just to relay a one-off command.
4. **Fallback** ONLY when ssh really cannot carry the command (argv length limits, hostile quoting / nested escapes) → author the script locally and use the scp+ssh path.

**Script-vs-command discrimination (CRITICAL)**:
- If the input contains a reference to a local script file path (e.g., `bash scripts/collect_all.sh`, `bash ./server_data_collector.sh`), and that script exists on the LOCAL agent host → it is a **script file input**, not a command string. Use rule 1.
- If the input contains a reference to a script file path but the script does NOT exist locally → it may be a reference to a remote script. Check if it exists on the remote via `ssh user@ip "test -f <path>"`. If it does, use rule 3 (remote command). If it doesn't, report the error.
- **The agent MUST NOT** read a script file's content with the Read tool, then synthesize equivalent commands to execute via `ssh user@ip "<commands>"`. This bypasses the script's error handling, output format, and edge-case logic, producing data that is incompatible with downstream consumers.

**File upload discipline (CRITICAL)**: To deliver a local file to the client, ALWAYS use one of:
- `scp <local> ${user}@${ip}:/tmp/<name>` then `ssh -q -tt ${user}@${ip} sh /tmp/<name>` (preferred — remote copy persists)
- `ssh -q -tt ${user}@${ip} 'bash -s' < <local>` (stream-and-execute — no remote copy)

NEVER read the file's content with the Read tool and inline it into an ssh command via heredoc / `echo >` / `printf >` / `tee`. This wastes tokens, fails on binary files, breaks on shell metacharacters (`$`, `\`, backticks, quotes), and produces a remote file that is not byte-identical to the source.

**CRITICAL**: Must use `ssh -tt` to run command or script: pseudo-terminal is required for perf operation, `ssh -tt` provides such environment and ensures terminal control characters are properly handled. NEVER copy client data to local machine for analysis.
**Execution timeout**: these commands may execute for >20 min, opencode should **extend session TIMEOUT to 1200 sec**.

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

> **About the examples above:** the commands inside `ssh user@ip '...'` quotes
> are REMOTE-side — they run on the Linux client and are correct on both agent
> platforms. The lines that run on the LOCAL agent host (here: the `scp` of a
> file from `/tmp/...`) are shown in Linux form for brevity. When the agent
> host is Windows, translate `/tmp` to `$env:TEMP`, single quotes to double
> quotes (PowerShell single-quote semantics), and `ssh-copy-id` to the manual
> `echo pubkey >> authorized_keys` pattern. The exact LOCAL-side commands live
> in the platform-specific reference guide picked by the Platform Detection
> section above.

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

**Remote mode `${WORK_DIR}` semantics**: if the analysis target is a remote server,
load `opentunex-remote-execution/references/work_dir_remote_semantics.md` and follow it:
`${WORK_DIR}` is a REMOTE path; every command touching it runs via ssh, never locally.

---

## [Continue with your skill-specific phases]
```

This replaces the duplicated Client Connection and Command Execution section in each skill.

---

## Reference

Pick the guide that matches the platform detected at the top of this skill:

- **Linux / macOS agent host** → [references/remote_execution_guide.md](references/remote_execution_guide.md)
- **Windows agent host** → [references/remote_execution_guide_windows.md](references/remote_execution_guide_windows.md)

If the platform detection snippet above reports `WINDOWS`, do NOT read the Linux guide — its `/opt/...` paths, `ssh-copy-id`, heredoc examples, and `timeout` invocations will fail on Windows and waste attention on retry loops.
