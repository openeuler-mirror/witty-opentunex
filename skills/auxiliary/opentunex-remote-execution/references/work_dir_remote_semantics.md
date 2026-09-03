# ${WORK_DIR} 远程语义（Remote ${WORK_DIR} Semantics）

> **English summary**: In remote mode (the user input contains a remote server IP),
> `${WORK_DIR}` is a path **ON THE REMOTE Linux SERVER** — by default
> `/srv/opentunex/<YYYYMMDD_HHMMSS>/` — created once by `witty-opentunex` and passed
> down through every chained skill and sub-agent. **Every** operation that touches
> `${WORK_DIR}` (mkdir / ls / cat / test / write / tar / script execution) is a
> REMOTE operation and MUST go through `opentunex-remote-execution` (ssh). The agent
> host must never have a local directory playing the role of
> `${WORK_DIR}` in remote mode.

---

## 1. 模式判定（每个技能的第一步）

在任何涉及 `${WORK_DIR}` 的操作之前，先判定执行模式：

| 判定条件 | 模式 | `${WORK_DIR}` 含义 | 命令执行方式 |
|---------|------|-------------------|------------|
| 用户输入中包含远端服务器 IP | **远端模式** | 远端 Linux 服务器上的路径 `/srv/opentunex/<YYYYMMDD_HHMMSS>/`（由 `witty-opentunex` 在远端初始化） | 全部通过 `opentunex-remote-execution` 经 ssh 在远端执行 |
| agent 主机就是目标机器（无 IP） | 本地模式 | agent 主机上的本地目录 | 直接本地执行，无需 ssh |

模式由 `witty-opentunex` 在流程开始时确定一次，并作为上下文（`execution_mode`、`user`、`ip`、`${WORK_DIR}`）传递给**每一个**链式调用的技能与子智能体（写入输入契约或子智能体任务描述）。子技能不得自行改判模式。

## 2. 远端模式铁律

1. **`${WORK_DIR}` 只存在于远端。** 禁止在 agent 主机本地 `mkdir` / `cd` / `cat` / `tar` `${WORK_DIR}`——远端模式下任何对 `${WORK_DIR}` 的本地文件操作都是错误。
2. **所有对 `${WORK_DIR}` 的操作都是远端操作**，必须经 `opentunex-remote-execution` 的 ssh 机制执行。远端引号内是 Linux bash（目标机是 Linux，与 agent 主机 OS 无关）。
3. **采集/分析数据不出服务器**：禁止 scp 把远端数据文件拷回 agent 本地分析；需要内容时用远端 `cat` 等命令将输出经 ssh 流回 agent 上下文。
4. **agent 生成的文件（契约、中间态建议、分析报告、调优脚本）**：**直接在远端机器上产出**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传到远端。既有脚本文件的上传仍遵守 scp 纪律（见 `opentunex-remote-execution` SKILL.md，禁止把脚本内容内联进 ssh 执行）。

## 3. 常用操作的远端写法

以下 `ssh` 行均在 agent 主机执行，引号内是远端命令：

```bash
# 创建目录（一次 ssh 建多个）
ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/analysis/contracts ${WORK_DIR}/analysis/opentunex-top-down-bottleneck_collect ..."

# 存在性 / 非空校验
ssh ${user}@${ip} "ls ${WORK_DIR}/collect/ 2>/dev/null | head -20"
ssh ${user}@${ip} "test -s ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md && echo OK || echo MISSING_OR_EMPTY"

# 读取文件内容进 agent 上下文进行分析（数据不落本地）
ssh -q ${user}@${ip} "cat ${WORK_DIR}/collect/global_bottleneck.txt"
# 大文件用远端过滤，只取所需内容
ssh -q ${user}@${ip} "grep -A 20 '建议调优方向' ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"

# 写入 agent 生成的文件：直接在远端机器产出（禁止本地生成后再 scp 上传）
ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/analysis/contracts && cat > ${WORK_DIR}/analysis/contracts/opentunex-top-down-bottleneck-input.yaml <<'EOF'
<agent 撰写的文件内容>
EOF"

# 打包在远端执行，产物留在远端
ssh ${user}@${ip} "cd ${WORK_DIR} && tar czf tuning-package_<YYYYMMDD_HHMMSS>.tar.gz tuning/"

# 执行技能 scripts/ 目录下的脚本：scp 到远端后 ssh 执行（本技能既有规则）
scp <skill>/scripts/<script>.sh ${user}@${ip}:/tmp/
ssh -q -tt ${user}@${ip} "bash /tmp/<script>.sh <参数> -o ${WORK_DIR}/collect"
```

## 4. 与既有规则的关系

- 脚本文件上传纪律（禁止 Read 脚本内容后内联 ssh 执行、scp 字节一致）不变，见 `opentunex-remote-execution` SKILL.md——heredoc 远端落盘仅用于 agent 新撰写的内容（报告/契约/调优脚本），不用于搬运已有文件。
- "NEVER copy client data to local machine for analysis" 不变——第 3 节"读取文件内容"用远端 `cat` 流回上下文，不违反该规则。
- 本地模式（无 IP）不受本文约束，技能内命令可直接在 agent 主机执行。
