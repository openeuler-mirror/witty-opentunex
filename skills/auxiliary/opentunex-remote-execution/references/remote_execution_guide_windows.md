# Remote Execution Guide (Windows Agent Host)

This guide is the **Windows-specific companion** to `remote_execution_guide.md`.
Load this file ONLY when SKILL.md's platform detection confirmed the agent host is
Windows. The remote client is still expected to be Linux — everything inside the
`ssh user@ip '...'` quote runs on the remote and is unaffected by the agent host
OS. This guide fixes the commands that the **agent itself runs on its local
Windows box** (key setup, file authoring, timeout, return-code checks, etc.).

> **Conventions used in this file**
>
> - `# LOCAL` — runs on the Windows agent host. Must use PowerShell or `cmd.exe`
>   compatible syntax. NEVER use bash-only features here (heredoc, `[ $? ]`,
>   `2>/dev/null`, `nohup`, `ssh-copy-id`, `timeout`, glob with `~/.ssh/*.pub`).
> - `# REMOTE` — runs INSIDE the ssh session on the Linux client. Plain bash /
>   Linux utilities are fine. Treat the inside-quote text as Linux shell source.
> - PowerShell is the preferred LOCAL shell. Git Bash snippets are shown only
>   when the agent explicitly runs under Git Bash / WSL — detect this before
>   trusting `cat`, `~/.ssh`, or heredocs.
> - When in doubt, prefer **double quotes** for `ssh user@ip "..."` arguments on
>   Windows because PowerShell treats single quotes as literal strings (so
>   `ssh ip 'uname -r'` becomes `ssh ip "'uname -r'"` and the remote gets a
>   malformed command). Use single quotes inside ONLY when the remote command
>   itself contains `$` and you need to suppress local variable expansion.

---

## 1. Platform Probe (run first)

Before trusting any of the snippets below, confirm what shell is actually
available on this Windows host. The agent's "default" shell depends on how it
was launched, and assumptions here cause the worst retry cascades.

```powershell
# LOCAL — PowerShell
$shell = if ($env:SHELL) { $env:SHELL } else { "powershell" }
Write-Host "Detected shell: $shell"
Write-Host "OS: $($env:OS)"
Write-Host "Has OpenSSH client: $((Get-Command ssh.exe -ErrorAction SilentlyContinue) -ne $null)"
Write-Host "Has ssh-copy-id (Git Bash only): $((Get-Command ssh-copy-id -ErrorAction SilentlyContinue) -ne $null)"
Write-Host "Has coreutils timeout: $((Get-Command timeout.exe -ErrorAction SilentlyContinue) -ne $null)"
```

If `ssh.exe` is missing, STOP and report: "OpenSSH client is not installed on
this Windows host. Install it via Settings → Apps → Optional Features → OpenSSH
Client, or use Git Bash / WSL."

---

## 2. Direct SSH Connection Test (RUN FIRST)

On Windows, users typically configure SSH private key authentication on the
agent host **before** using the agent to connect to target Linux servers. The
first step is to directly test the SSH connection with the extracted IP —
**skip the config-file lookup and key-generation flow** that the Linux guide
uses. If the connection fails, tell the user to configure their SSH key and
retry; do NOT attempt to set up keys automatically.

```powershell
# LOCAL — PowerShell
# $user and $ip were extracted from the user context (e.g., "root@192.168.1.100"
# or "analyze lock bottleneck on 192.168.1.100"). Default $user to "root" if
# only an IP was given.

# Test SSH connection with key-based auth (BatchMode=yes disables password prompt)
ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${user}@${ip} "echo 'SSH_CONNECTION_OK'"
if ($LASTEXITCODE -eq 0) {
    Write-Host "SSH key-based authentication to ${user}@${ip} succeeded."
    # Connection is ready — proceed to command execution.
} else {
    Write-Host "SSH_CONNECTION_FAILED (exit code: $LASTEXITCODE)"
    Write-Host ""
    Write-Host "SSH key-based authentication to ${user}@${ip} failed."
    Write-Host "Please configure your SSH private key, then retry the operation:"
    Write-Host ""
    Write-Host "  1. Generate an SSH key pair (if you don't have one):"
    Write-Host "     ssh-keygen -t ed25519 -f `"$env:USERPROFILE\.ssh\id_ed25519`" -N '""'"
    Write-Host ""
    Write-Host "  2. Copy your public key to the target server:"
    Write-Host "     type `"$env:USERPROFILE\.ssh\id_ed25519.pub`" | ssh ${user}@${ip} `"mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`""
    Write-Host ""
    Write-Host "  3. Or use ssh-copy-id if available (Git Bash / WSL):"
    Write-Host "     ssh-copy-id ${user}@${ip}"
    Write-Host ""
    Write-Host "After configuring the SSH key, retry the operation."
    exit 1
}
```

**Why this order:** On Windows, SSH keys are typically configured once by the
user and then reused across all sessions. Automatically reading config files or
generating keys is unnecessary and risks overwriting the user's existing setup.
A direct `BatchMode=yes` test tells you immediately whether the connection is
ready — if it fails, the user knows exactly what to fix.

**If the connection test fails, STOP here.** Do NOT fall through to the
password-based auth flow or attempt to read `/opt/opentunex/config/client.yaml`
(that path does not exist on Windows). Do NOT attempt to generate keys or copy
them to the remote automatically. The sections below (§3) on key setup are
reference material for when the user explicitly asks for help configuring keys;
they are not part of the automatic connection setup flow.

`-o StrictHostKeyChecking=accept-new` prevents the host-key prompt on first
connection while still protecting against host-key changes (unlike
`StrictHostKeyChecking=no` which disables verification entirely).

---

## 3. SSH Key Setup Reference (manual — only when user asks for help)

The subsections below are **reference material** for when the user explicitly
asks "how do I configure my SSH key?" after the connection test in §2 failed.
Do NOT run these steps automatically — the direct connection test in §2 is the
only automatic step in the Windows connection flow.

### 3.1 Check for an existing key

The Linux guide uses `cat ~/.ssh/*.pub` which fails on PowerShell (no `cat`,
no tilde expansion, no `2>/dev/null`). Replace with:

```powershell
# LOCAL — PowerShell
$sshDir = Join-Path $env:USERPROFILE ".ssh"
$pubKeys = @()
if (Test-Path $sshDir) {
    $pubKeys = Get-ChildItem -Path $sshDir -Filter "*.pub" -File -ErrorAction SilentlyContinue
}
if ($pubKeys.Count -eq 0) {
    Write-Host "NO_KEY"
    # fall through to 3.2
} else {
    $pubKeys | ForEach-Object { Write-Host "Found: $($_.FullName)" }
}
```

### 3.2 Generate a key if missing

`ssh-keygen` ships with Windows 10+ OpenSSH but is NOT on PATH by default. Two
paths:

```powershell
# LOCAL — PowerShell (preferred — uses Windows ssh-keygen.exe)
$sshKeygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
if (-not $sshKeygen) {
    $sshKeygen = Get-ChildItem "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -ErrorAction SilentlyContinue
}
if ($sshKeygen) {
    & $sshKeygen -t ed25519 -f "$env:USERPROFILE\.ssh\id_ed25519" -N '""'
} else {
    Write-Host "ssh-keygen not found. Install OpenSSH Client or use Git Bash."
}
```

```bash
# LOCAL — Git Bash / WSL fallback
[ -f ~/.ssh/id_ed25519.pub ] || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

### 3.3 Copy the public key to the remote (THE BIG ONE)

`ssh-copy-id` is a Linux/Unix shell script. **Windows OpenSSH does NOT include
it.** The previous Linux guide assumed it was always available — on Windows the
agent will hit "command not found" and burn several turns trying to install it
or rewrite it from scratch. Use this native replacement instead:

```powershell
# LOCAL — PowerShell — drop-in replacement for `ssh-copy-id user@ip`
$pubKeyPath = Join-Path $env:USERPROFILE ".ssh\id_ed25519.pub"
if (-not (Test-Path $pubKeyPath)) {
    $pubKeyPath = Join-Path $env:USERPROFILE ".ssh\id_rsa.pub"
}
$pubKey = Get-Content $pubKeyPath -Raw
$pubKey = $pubKey.Trim()  # strip trailing newline, ssh heredoc would break otherwise

# IMPORTANT: quote the key with single quotes inside the remote command so
# bash doesn't try to interpret any shell metacharacters in the key body.
ssh ${user}@${ip} "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

If `ssh-copy-id` IS present (e.g. agent runs under Git Bash), it's fine to use
it — the snippet above only matters when it's missing. Detect first.

### 3.4 Verify the connection

```powershell
# LOCAL — PowerShell
ssh -o ConnectTimeout=5 -o BatchMode=yes ${user}@${ip} "echo 'Connection verified'"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Passwordless auth failed; check authorized_keys on remote."
}
```

`-o BatchMode=yes` is critical on Windows: it disables the password prompt so a
failure surfaces as a non-zero exit code instead of hanging the agent waiting
for keyboard input that will never come.

---

## 4. File Upload Discipline (CRITICAL)

This section is **identical in spirit** to the Linux guide — never inline a
file's content into an ssh command — but the LOCAL-side transport differs.

```powershell
# LOCAL — PowerShell — Option A: scp then ssh-execute (preferred)
scp <local> ${user}@${ip}:/tmp/<name>
ssh -q -tt ${user}@${ip} "sh /tmp/<name>"
```

```powershell
# LOCAL — PowerShell — Option B: stream-and-execute via pipe (no remote copy)
# The `< <local>` bash redirection does NOT exist in PowerShell. Use Get-Content.
Get-Content -Raw <local> | ssh -q -tt ${user}@${ip} "bash -s"
```

```bash
# LOCAL — Git Bash fallback (only if agent shell is Git Bash)
ssh -q -tt ${user}@${ip} 'bash -s' < <local>
```

**Heredoc is FORBIDDEN on the LOCAL side for authoring transport files.**
PowerShell has no bash heredoc. The right way to create a script to scp is:

1. Use the Write tool to author `/tmp/<name>.sh` on the LOCAL disk, OR
2. Use PowerShell `Set-Content -Path <path> -Value @" ... "@` (string literal,
   not heredoc).

NEVER read a file with the Read tool and paste its contents into an
`ssh user@ip "..."` invocation — same problem as on Linux (token waste,
metacharacter breakage, binary files, byte-identical output lost).

---

## 5. Command Execution Patterns

Every example in this section puts the LOCAL command on the agent host and the
REMOTE command inside the ssh quote. The remote side is Linux — leave it as
plain bash. Only the LOCAL wrappers change.

### 5.1 Simple commands

```powershell
# LOCAL + REMOTE — PowerShell wrapper, Linux command inside
ssh -q -tt ${user}@${ip} "uname -r"
ssh -q -tt ${user}@${ip} "cat /proc/cpuinfo | head -20"
```

Prefer **double quotes** on the outer ssh call to avoid PowerShell's
single-quote-is-literal trap. If the remote command contains a literal `$`
that should NOT be expanded by PowerShell, escape it as `` `$_ `` or switch
to single quotes and accept that the command itself becomes a literal —
better to use a temp file in that case.

### 5.2 Complex commands that won't fit in one ssh argv

The fallback path is the same as Linux (author the script locally, scp it,
ssh-execute), but the LOCAL authoring step changes:

```powershell
# LOCAL — PowerShell — author the script (NO heredoc!)
$script = @'
#!/bin/bash
vmstat 1 10 > vmstat.log
pidstat -w 1 10 > pidstat.log
'@
$localPath = Join-Path $env:TEMP "analyze.sh"
Set-Content -Path $localPath -Value $script -Encoding utf8 -NoNewline
```

```powershell
# LOCAL — PowerShell — deliver and execute
scp $localPath ${user}@${ip}:/tmp/
ssh -q -tt ${user}@${ip} "sh /tmp/analyze.sh"
```

`$env:TEMP` is the Windows equivalent of `/tmp` — it expands to something
like `C:\Users\<user>\AppData\Local\Temp\`. Do NOT hard-code `C:\Users\...`;
the user profile may live on a different drive.

### 5.3 perf commands

perf runs on the REMOTE (Linux), so the LOCAL shell does not matter for the
command itself. Only the ssh invocation matters, and double quotes work fine:

```powershell
# LOCAL — PowerShell — wrapper; REMOTE — Linux perf command
ssh -q -tt ${user}@${ip} "cd /tmp && perf sched record -a -- sleep 15"
ssh -q -tt ${user}@${ip} "cd /tmp && perf sched latency"
```

`-tt` (force TTY allocation) is required on Windows for the same reason as
Linux: perf wants a controlling terminal. Some Windows ssh clients also need
`-T` to disable pseudo-tty allocation for non-perf commands — test on your
target server.

---

## 6. Timeout Handling

`timeout.exe` is **not** part of Windows OpenSSH. The Linux guide's `timeout
1200 ssh ...` snippet will fail with "command not found". Two replacements:

### 6.1 PowerShell job with Wait-Job (preferred — works everywhere)

```powershell
# LOCAL — PowerShell — replacement for `timeout 1200 ssh -q -tt ${ip} '...'`
$remoteCmd = "perf sched record -a -- sleep 60"
$job = Start-Job -ScriptBlock {
    param($u, $i, $c)
    ssh -q -tt "${u}@${i}" $c
} -ArgumentList ${user}, ${ip}, $remoteCmd

$completed = Wait-Job $job -Timeout 1200
if (-not $completed) {
    Stop-Job $job
    Remove-Job $job -Force
    Write-Host "TIMED OUT after 1200s"
    exit 124
} else {
    Receive-Job $job
    Remove-Job $job -Force
}
```

The exit code 124 is preserved intentionally — the Linux guide's timeout-error
handler at line 184 keys off 124, so keeping the convention lets the same
upstream logic apply.

### 6.2 Install coreutils timeout (cleanest, but requires user action)

```powershell
# LOCAL — PowerShell — only if user agrees to install chocolatey/scoop
# After install, the original Linux-style `timeout 1200 ssh ...` works:
#   timeout 1200 ssh -q -tt ${user}@${ip} "perf sched record -a -- sleep 60"
choco install -y coreutils    # or: scoop install coreutils
```

Mention this as an OPTION, not a requirement — most agents should not silently
install software. The PowerShell job pattern in 6.1 covers the case without
any install.

---

## 7. Background Execution

`nohup ... &` is a Linux background-process idiom and runs **on the REMOTE**
in the snippets below. That's fine — the remote is Linux. The only thing to
watch on the LOCAL side is quoting:

```powershell
# LOCAL + REMOTE — Linux nohup runs on the client; Windows shell only wraps it
ssh -q -tt ${user}@${ip} "nohup sh /tmp/long_task.sh > /tmp/output.log 2>&1 &"
ssh -q -tt ${user}@${ip} "ps aux | grep long_task"
```

If you need to verify status from PowerShell instead of from bash:

```powershell
# LOCAL — PowerShell — native equivalent of `ps aux | grep long_task` (REMOTE)
ssh -q -tt ${user}@${ip} "ps -ef | grep [l]ong_task"
```

The `[l]ong_task` trick avoids the grep itself matching the pattern — same
trick works on Linux, no Windows-specific reason to use it, but worth knowing
when porting scripts.

---

## 8. Security Considerations

Identical to the Linux guide in intent. The only Windows-specific wrinkle is
how confirmation prompts should be presented — PowerShell `Read-Host` instead
of `read`:

```powershell
# LOCAL — PowerShell — confirm before destructive remote ops
$cmd = "rm -rf /var/log/app.log"
$confirm = Read-Host "Confirm destructive op '$cmd' on ${ip}? Type 'yes' to proceed"
if ($confirm -ne "yes") {
    Write-Host "Aborted by user"
    exit 1
}
ssh -q -tt ${user}@${ip} $cmd
```

Everything else in the security section (no copying data back, no destructive
ops without user OK, no hardcoded passwords) applies unchanged.

---

## 9. Error Handling

### 9.1 Connection errors

```powershell
# LOCAL — PowerShell — check ssh exit code
ssh -q -tt ${user}@${ip} "command" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Command failed on remote (exit $LASTEXITCODE)"
    # handle / retry / report
}
```

Note: `$LASTEXITCODE` is set by the LAST external program PowerShell ran —
always check it immediately after the ssh call, before any other command
overwrites it.

### 9.2 Timeout errors (PowerShell job variant)

```powershell
# LOCAL — PowerShell — see section 6.1
# Job timeout check:
if (-not $completed) {
    Write-Host "Command timed out"   # exit code 124 was already set above
}
```

### 9.3 Distinguishing "ssh failed" from "remote command failed"

`ssh` returns:
- exit 255 → ssh itself failed (network, auth, host key). Connection issue.
- exit 0..254 → remote command ran; that number is the remote command's exit
  code. Application issue.

PowerShell's `$LASTEXITCODE` gives you this directly, but agents sometimes
confuse the two. When reporting failures, say which category it is.

---

## 10. Best Practices (Windows-specific)

1. **Always use `-o BatchMode=yes`** when verifying passwordless auth. Without
   it, ssh will hang on a password prompt and the agent will waste turns
   waiting for input.
2. **Prefer double quotes** around the remote command argument to
   `ssh user@ip "..."`. PowerShell's single-quote semantics will silently
   break the remote invocation.
3. **No heredoc on the LOCAL side.** Use the Write tool or PowerShell
   `Set-Content -Value @" ... "@`. Heredoc-isms in PowerShell either error
   out or behave as a here-string literal that never gets executed.
4. **No `ssh-copy-id` on plain Windows OpenSSH.** Use the manual
   `echo 'pubkey' >> authorized_keys` pattern from §3.3.
5. **No `timeout` on plain Windows.** Use the Wait-Job pattern from §6.1.
6. **No `2>/dev/null`** on LOCAL commands — PowerShell suppresses errors via
   `-ErrorAction SilentlyContinue` instead.
7. **No `~/.ssh` tilde on LOCAL** without confirming the shell is Git Bash.
   PowerShell expands `~` in some contexts but not others; use
   `$env:USERPROFILE\.ssh` for reliability.
8. **Profile paths differ.** Use `$env:USERPROFILE`, `$env:TEMP`,
   `$env:APPDATA` — never hard-code `C:\Users\<name>\...`.
9. **Verify OpenSSH is installed** before any ssh call (§1). Most
   `command not found` failures on Windows trace back to OpenSSH not being
   installed, not to a typo.
10. **Test exit codes immediately** after ssh — `$LASTEXITCODE` is volatile
    and gets overwritten by the next external command.