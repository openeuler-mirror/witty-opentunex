---
name: "opentunex-bottleneck-analysis"
description: "瓶颈分析域入口。编排通用分析与场景化分析并行执行，对结果交叉验证、优先级排序和冲突消解，输出融合报告。当用户提到CPU高、内存不足、磁盘慢、IO等待高、锁竞争、调度延迟、性能瓶颈、瓶颈定位、系统变慢等关键词时必须使用。注意：若存在`witty-opentunex`技能，则【强制】使用`witty-opentunex`技能。"
sub_agent_enabled: true
constraints_file: "references/constraints-bottleneck.md"
---

# 瓶颈分析域入口技能

> **⛔ 入口门：在执行任何操作前，必须确认以下4条规则。违反任何一条即为本技能的执行失败：**
> 
> 1. **本技能必须尝试通过子智能体工具启动分析**——不得在当前上下文中直接读取采集数据并分析。通用分析（top-down-bottleneck）和场景化分析（scenario-bottleneck）应通过子智能体工具启动独立上下文执行。如果子智能体工具不可用或能力不足（如无法写文件），才允许降级模式，但必须标注 `execution_mode: "degraded"` 并记录降级原因。
> 2. **在启动子智能体之前，不得读取任何采集数据文件**——数据路径写入输入契约，由子智能体自行读取。"数据已在上下文中"不是跳过子智能体的理由。
> 3. **本技能的职责是调度编排和融合**——不负责分析逻辑。正确流程：创建目录 → 写契约 → 启动子智能体 → 校验输出 → 融合报告。
> 4. **路径不匹配不是豁免条款**——无论数据在哪个目录（用户指定目录或 `${WORK_DIR}`），都必须走完整协议流程。数据路径只是输入契约中的一个字段，路径差异不影响执行步骤。不得因"路径不是标准路径"而跳过任何步骤。

承接数据采集层输出的结构化指标，通过子智能体编排通用分析与场景化分析并行执行，对结果融合后输出报告。

## 强制约束

### 职责边界

- 编排通用分析与场景化分析**并行**执行，不可串行替代
- 对两类分析结果进行融合（交叉验证、优先级排序、冲突消解）
- 输出结构化融合报告
- **不负责**数据采集和调优执行

### 数据目录

- 写入：`${WORK_DIR}/analysis/<skill>_collect/`
- 读取：`${WORK_DIR}/analysis/<skill>_collect/`
- 读取采集数据：`${WORK_DIR}/collect/`（数据采集阶段 `bottleneck_data_collector.sh -o ${WORK_DIR}/collect` 的产物；用户指定 DATA_DIR 时优先）
- 分析结果在所有子智能体执行完毕且融合报告生成后写入分析目录

### 执行模式与 `${WORK_DIR}` 语义（核心）

- **远端模式**（用户输入含远端 IP，由 `witty-opentunex` 判定并传递）：`${WORK_DIR}` 是**远端服务器上**的路径（`/srv/opentunex/<YYYYMMDD_HHMMSS>/`）。本技能中所有对 `${WORK_DIR}` 的操作（mkdir/ls/写契约/读契约/读数据/写报告）都必须在**远端**执行——通过 `opentunex-remote-execution` 的 ssh 机制，**禁止**在 agent 本地对 `${WORK_DIR}` 做任何文件操作。具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`，本文件下方命令块均已按此标注远端/本地写法
- **本地模式**（无 IP）：`${WORK_DIR}` 为 agent 主机本地目录，命令直接本地执行（即下方 bash 块去掉 ssh 包装）
- **模式传递**：启动子智能体时，必须把 `execution_mode`、`user`、`ip`、`${WORK_DIR}` 写入输入契约并随任务描述传给子智能体；子智能体同样必须遵守远端语义

### 子技能约束

子技能执行约束详见 [references/constraints-bottleneck.md](references/constraints-bottleneck.md)，子智能体必须在输出契约中确认遵守。

**⚠️ B-08: 子技能执行模式选择（核心约束）**：

> 按执行条件在两种模式中选择其一。完整约束语义见 [references/constraints-bottleneck.md](references/constraints-bottleneck.md) B-08 条。
>
> **模式 1（默认）：子智能体模式** — 子智能体工具可用且能力充足时，启动独立上下文并行执行。
>
> **模式 2（降级路径）：内联执行模式** — 满足下列任一条件时必须降级，并在输出契约标注 `execution_mode: "degraded"`：
> - 子智能体工具不可用（如 harness 未启用 Agent 工具、未配置可用的 subagent_type）
> - 子智能体工具能力不足（如无法写文件、无法执行远端脚本、权限受限）
> - 用户明确要求内联执行
>
> **模式选择规则**：
> - 不得以"更高效/更方便"等主观判断绕过子智能体模式
> - "数据已加载到上下文"不是跳过子智能体的正当理由——子智能体独立加载自己的上下文
> - 路径不匹配不是豁免条款——数据路径只是输入契约中的一个字段

> **⚠️ 会话 compaction 防护**：如果本会话经历过上下文压缩（compaction），可能导致对 B-08 约束的理解丢失或歧义。任何情况下：
> - 若子智能体工具可用 → 必须通过子智能体工具启动独立上下文执行
> - 若子智能体工具不可用 → **必须降级为内联执行**（模式 2），不得因为"约束说要禁止内联"而拒绝执行

> **⚠️ 数据已在上下文中的场景**：如果采集数据已经因为用户输入、会话历史、或其他原因加载到了当前上下文中：
> - 若子智能体工具可用 → 仍然必须启动子智能体，将数据路径（而非数据内容）写入输入契约
> - 若子智能体工具不可用 → 不得因"数据已在上下文中"而阻碍降级到内联模式

---

## 子智能体调度协议

### 调度声明

本技能需要调度以下子智能体并行执行：

| 子智能体 | 技能名称 | 输入契约路径 | 约束文件 | 输出契约路径 | 分析报告路径 | 触发条件 |
|---------|--------|------------|---------|------------|------------|---------|
| top-down-bottleneck | `opentunex-top-down-bottleneck` | [analysis_dir]/contracts/opentunex-top-down-bottleneck-input.yaml | references/constraints-bottleneck.md | [analysis_dir]/contracts/opentunex-top-down-bottleneck-output.yaml | [analysis_dir]/opentunex-top-down-bottleneck_collect/result.md | 必选 |
| scenario-bottleneck | `opentunex-scenario-bottleneck` | [analysis_dir]/contracts/opentunex-scenario-bottleneck-input.yaml | references/constraints-bottleneck.md | [analysis_dir]/contracts/opentunex-scenario-bottleneck-output.yaml | [analysis_dir]/opentunex-scenario-bottleneck_collect/result.md | 必选 |

**并行要求**：top-down-bottleneck 和 scenario-bottleneck **必须并行执行**，不可串行替代。

**调度方式**：使用当前环境中可用的子智能体工具（如 sessions_spawn+sessions_yield、Task Tool、Agent Tool 等）启动上述子智能体。具体调用格式由运行时环境决定，本技能不限定。

**子智能体任务描述**（传入子智能体的指令）：
> 读取技能定义 [技能名称]，读取输入契约 [输入契约路径]，读取约束文件 [约束文件路径]，执行技能定义中的步骤，写入输出契约 [输出契约路径]，写入分析报告 [分析报告路径]

### 降级模式（仅在子智能体工具不可用时使用）

降级模式**不是首选执行路径**，仅在子智能体工具不可用或启动失败时使用：

降级执行时必须：
- 在输出契约中标注 `execution_mode: "degraded"` 并记录降级原因
- 逐个读取子技能的 SKILL.md，每次只加载一个，执行完毕后释放上下文再加载下一个
- 仍须遵守所有约束和契约输出要求

### 二级子智能体嵌套

通用分析子智能体在 G-Phase 5 深度分析时，可继续启动二级子智能体。最大嵌套深度为 2 级。

```
analysis 入口
  ├── [一级子智能体] top-down-bottleneck（通用分析）
  │     └── G-Phase 5: 启动二级子智能体
  │           ├── [二级子智能体] io-bottleneck
  │           ├── [二级子智能体] mem-bottleneck
  │           └── ...
  └── [一级子智能体] scenario-bottleneck（场景化分析）
        ├── [二级子智能体] numa-sched-analysis
        ├── [二级子智能体] stealtask-analysis
        └── ...
```

---

## 输入约定

数据来源：**数据采集层**

**数据读取路径**：数据采集阶段的产出目录，`WORK_DIR` 变量指向工作目录根，数据文件位于 `${WORK_DIR}/collect/` 下（用户通过 DATA_DIR 指定预采集目录时优先使用 DATA_DIR）。

| 数据类别 | 必需 | 采集内容 | 对应文件（`${WORK_DIR}/collect/` 下） |
|---------|------|---------|-----------|
| 系统环境静态信息 | 是 | 硬件规格、软件版本、内核参数 | `static_info.txt`、`kernel_config_info.txt` |
| 全局资源瓶颈识别 | 是 | CPU/内存/IO/网络指标 | `global_bottleneck.txt`、`cpu_detail_info.txt`、`memory_metrics_analysis.txt`、`io_metrics_analysis.txt`、`network_metrics_analysis.txt` |
| 高资源消耗进程列表 | 是 | Top CPU/内存/IO进程 | `top_processes.txt`、`process_detail_info.txt` |

**数据路径优先级**：

| 优先级 | 来源 | 路径 |
|--------|------|------|
| 1 | 用户指定 | 用户提供的工作目录（`WORK_DIR`），数据文件位于根目录下 |
| 2 | 兜底 | 提示用户使用一键采集脚本生成数据 |

---

## 执行步骤

### 步骤 0：创建瓶颈分析所需目录【强制】

**远端模式**（`${WORK_DIR}` 是远端路径，经 ssh 在远端创建，一次 ssh 建完）：

```bash
ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/analysis/contracts \
  ${WORK_DIR}/analysis/opentunex-top-down-bottleneck_collect \
  ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect \
  ${WORK_DIR}/analysis/opentunex-numa-sched-analysis_collect \
  ${WORK_DIR}/analysis/opentunex-stealtask-analysis_collect \
  ${WORK_DIR}/analysis/opentunex-dynamic-smt-analysis_collect \
  ${WORK_DIR}/analysis/opentunex-docker-coordination-burst-analysis_collect \
  ${WORK_DIR}/analysis/opentunex-soft-domain-analysis_collect \
  ${WORK_DIR}/analysis/opentunex-multi-net-path-analysis_collect"
```

**本地模式**（agent 主机即目标机，直接本地执行）：

```bash
mkdir -p ${WORK_DIR}/analysis/contracts
mkdir -p ${WORK_DIR}/analysis/opentunex-top-down-bottleneck_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-numa-sched-analysis_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-stealtask-analysis_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-dynamic-smt-analysis_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-docker-coordination-burst-analysis_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-soft-domain-analysis_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-multi-net-path-analysis_collect
mkdir -p ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect
```

> **远端模式禁止**：在 agent 本地（如 Windows）`mkdir ${WORK_DIR}/...`——`${WORK_DIR}` 只存在于远端。

#### 步骤 0 完成检查清单【不可跳过】

在进入步骤 1 前，必须确认以下各项：

- [ ] **已重新读取约束文件** `references/constraints-bottleneck.md`（防止会话 compaction 后 B-08 语义丢失）
- [ ] 批次目录已创建：`${WORK_DIR}/analysis/contracts/` 存在
- [ ] 数据目录已确认：用户指定的 `WORK_DIR` 存在且包含采集数据文件
- [ ] **尚未读取任何采集数据文件**（数据由子智能体自行读取，主智能体不预加载）
- [ ] 准备好写入输入契约并启动子智能体

> **⚠️ 关键时序约束（仅在子智能体工具可用时生效）**：主智能体在启动子智能体之前**不得读取采集数据文件**。数据由子智能体在独立上下文中自行读取。如果主智能体提前读取了数据，"数据在手"的可及性会压制子智能体调度的动机，导致违反 B-08 模式 1 约束。若子智能体工具不可用/能力不足，应主动落地降级模式（模式 2），不受本时序约束限制。

### 步骤 1：写入输入契约并启动子智能体【纯调度阶段，禁止读取数据】

> **⚠️ B-08 执行纪律检查点**：
> 
> 在执行本步骤前，自问以下问题：
> - 我是否已经读取了采集数据文件？若是子智能体工具可用 → **停止**，你已经违反了 B-08 约束；若是子智能体工具不可用 → 属于降级模式，应在输出契约标注 `execution_mode: "degraded"`
> - 我是否正打算先看一下数据再决定怎么分析？若是子智能体工具可用 → **停止**，数据由子智能体读取
> - 我是否觉得"数据都在手边了，直接分析更快"？若是子智能体工具可用 → **这正是 B-08 要防止的可及性偏差**；若是子智能体工具不可用 → 应当主动落地降级模式
> - 数据路径不是 `${WORK_DIR}/` → **路径不匹配不是豁免条款**，把实际路径写入输入契约的 data_dir 字段即可
> - 我是否检测到子智能体工具不可用/能力不足？若是 → **必须降级为内联模式**，按 B-08 模式 2 执行
> 
> **正确做法**：只写契约路径（data_dir 填实际路径），不读数据内容。spawn 子智能体，让它们自己读数据。

#### 1.1 校验数据可用性（仅检查目录存在性，禁止读取文件内容）

```bash
# ✅ 允许：检查目录是否存在（远端模式经 ssh 在远端执行）
ssh ${user}@${ip} "ls ${WORK_DIR}/ && ls ${WORK_DIR}/collect/"

# ❌ 禁止：读取任何数据文件内容（子智能体工具可用时，违反 B-08 模式 1）
# 远端模式: ssh ${user}@${ip} "cat ${WORK_DIR}/collect/global_bottleneck.txt"  ← 违反 B-08
# 本地模式: cat ${WORK_DIR}/collect/global_bottleneck.txt  ← 违反 B-08
# 注：子智能体工具不可用/能力不足时，应落地 B-08 模式 2 的降级路径
```

数据不完整时提示数据采集层补充。

#### 1.2 写入输入契约

契约文件本身也要写入 `${WORK_DIR}`（远端路径）。**远端模式**：先用 Write 工具在 agent 本地写契约文件，再 `scp` 上传到远端对应路径；**本地模式**：直接写到 `${WORK_DIR}/analysis/contracts/`。

**写入通用分析输入契约**：

```yaml
contract_type: "input"
skill_name: "opentunex-top-down-bottleneck"
timestamp: "<timestamp>"
input:
  analysis_dir: "${WORK_DIR}/analysis"
  data_dir: "${WORK_DIR}/collect"   # 数据采集阶段产出目录；用户指定 DATA_DIR 时填实际路径
  work_dir: "${WORK_DIR}/"
  collect_dir: "opentunex-top-down-bottleneck_collect"
execution_context:
  execution_mode: "remote" | "local"   # 远端模式必填 remote
  user: "<远端用户名，默认 root>"        # 远端模式必填
  ip: "<远端服务器 IP>"                  # 远端模式必填
constraints_file: "references/constraints-bottleneck.md"
```

**写入场景化分析输入契约**：

```yaml
contract_type: "input"
skill_name: "opentunex-scenario-bottleneck"
timestamp: "<timestamp>"
input:
  analysis_dir: "${WORK_DIR}/analysis"
  data_dir: "${WORK_DIR}/collect"   # 数据采集阶段产出目录；用户指定 DATA_DIR 时填实际路径
  work_dir: "${WORK_DIR}/"
execution_context:
  execution_mode: "remote" | "local"
  user: "<远端用户名，默认 root>"
  ip: "<远端服务器 IP>"
constraints_file: "references/constraints-bottleneck.md"
```

**子智能体任务描述必须包含执行模式上下文**：`execution_mode=remote（user、ip 如上），${WORK_DIR} 为远端路径，所有对 ${WORK_DIR} 的读写经 opentunex-remote-execution 在远端执行，见 references/work_dir_remote_semantics.md`。

**并行启动两个子智能体**（同一轮中同时启动）：

```
启动子智能体执行通用瓶颈分析：
- 加载技能定义：opentunex-top-down-bottleneck/SKILL.md
- 读取输入契约：[analysis_dir]/contracts/opentunex-top-down-bottleneck-input.yaml
- 读取约束文件：references/constraints-bottleneck.md
- 子智能体自行读取采集数据：${WORK_DIR}/collect（远端模式经 ssh 读取，禁止 scp 拷回本地）
- 执行六阶段分析（G-Phase 1~6）
- G-Phase 5 按需启动二级子智能体执行深度分析
- 写入输出契约：[analysis_dir]/contracts/opentunex-top-down-bottleneck-output.yaml
- 写入分析报告：[analysis_dir]/opentunex-top-down-bottleneck_collect/result.md

启动子智能体执行场景化瓶颈协调分析：
- 加载技能定义：opentunex-scenario-bottleneck/SKILL.md
- 读取输入契约：[analysis_dir]/contracts/opentunex-scenario-bottleneck-input.yaml
- 读取约束文件：references/constraints-bottleneck.md
- 子智能体自行读取采集数据：${WORK_DIR}/collect（远端模式经 ssh 读取，禁止 scp 拷回本地）
- 全量调度所有场景分析子技能并行执行
- 各子技能自行判断适用性，分析报告写入对应 _collect 目录
- 写入输出契约：[analysis_dir]/contracts/opentunex-scenario-bottleneck-output.yaml
- 写入融合报告：[analysis_dir]/opentunex-scenario-bottleneck_collect/result.md
```

#### 强制并行检查清单

| # | 检查项 | 通过条件 | 未通过处理 |
|---|--------|---------|-----------|
| C-1 | 通用分析分支已启动 | 子智能体已启动 | 不得跳过 |
| C-2 | 场景化分析分支已启动 | 子智能体已启动 | 不得跳过 |
| C-3 | 两者并行确认 | 两个子智能体在同一轮中同时启动 | 串行启动必须重新并行启动 |
| C-4 | 批次目录已创建 | `${WORK_DIR}/analysis/` 存在 | 回到步骤0 |

**G-Phase 5 深度分析路由规则**（由通用分析子智能体内部调度）：

| 识别的瓶颈类型 | 深度分析方向 | 关键阈值 |
|---------------|------------|---------|
| 磁盘IO饱和 | 磁盘IO与块设备深度分析 | %util > 90% |
| CPU iowait升高 | 磁盘IO与块设备深度分析 | %iowait > 20% |
| 内存压力 | 内存与NUMA深度分析 | SwapUsed > 50% |
| NUMA失衡 | 内存与NUMA深度分析 | remote/local > 2:1 |
| 网络重传 | 网络协议栈深度分析 | Retrans > 2% |
| 连接耗尽 | 网络协议栈深度分析 | TIME_WAIT > 5000 |
| 高上下文切换 + futex等待 | 锁竞争与同步深度分析 | cs/s > 50000 |
| 调度延迟异常 | 调度行为追踪分析 | delay > 100ms |
| 应用层热点 | 应用层工作负载深度分析 | %usr > 80% |

### 步骤 2：等待子智能体完成，校验输出契约【输出校验门】

> **⚠️ 本步骤是输出校验门——如果子智能体输出契约文件不存在，融合阶段无法继续。这阻止了跳过子智能体后试图直接融合的死胡同。**

1. 等待所有子智能体执行完成
2. 读取各子智能体的输出契约，确认 status 和 constraints_acknowledged（**远端模式**：契约在远端，经 ssh 读取——`ssh -q ${user}@${ip} "cat ${WORK_DIR}/analysis/contracts/<name>-output.yaml"`，**禁止** scp 拷回本地）
3. **校验门检查**：

| # | 校验项 | 通过条件 | 未通过处理 |
|---|--------|---------|-----------|
| G-1 | 通用分析输出契约存在 | `[analysis_dir]/contracts/opentunex-top-down-bottleneck-output.yaml` 文件存在 | 等待或重试子智能体 |
| G-2 | 场景化分析输出契约存在 | `[analysis_dir]/contracts/opentunex-scenario-bottleneck-output.yaml` 文件存在 | 等待或重试子智能体 |
| G-3 | 通用分析状态为 success | output.yaml 中 status=success | 检查错误原因，必要时重试 |
| G-4 | 场景化分析状态为 success | output.yaml 中 status=success | 检查错误原因，必要时重试 |
| G-5 | 约束已确认 | constraints_acknowledged 包含 B-01~B-08 | 拒绝接受未确认约束的输出 |
| G-6 | 场景化融合报告存在 | `[analysis_dir]/opentunex-scenario-bottleneck_collect/result.md` 或输出契约 `report_path` 字段指向的文件存在 | 等待或重试子智能体 |

**如果校验门未通过，不得进入步骤 3 融合阶段。**

### 步骤 3：结果融合

读取各子智能体的分析报告，按需加载融合逻辑执行五阶段融合。

> **远端模式**：报告在远端 `${WORK_DIR}` 下，经 ssh 读取内容（`ssh -q ${user}@${ip} "cat <报告路径>"`），禁止 scp 拷回本地；融合报告写入 `${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md` 时同样在远端落盘（本地 Write → scp 上传，或短内容远端 cat 落盘）。详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

**报告定位**：

| 报告来源 | 定位方式 | 典型路径 |
|---------|---------|---------|
| 通用分析 | 已知路径 | `[analysis_dir]/opentunex-top-down-bottleneck_collect/result.md` |
| 场景化分析（已融合） | 输出契约 `report_path` | `[analysis_dir]/opentunex-scenario-bottleneck_collect/result.md` |

> **场景分析报告已是融合后的结果**：场景协调器（Phase 2）已按 [场景融合规则](../opentunex-scenario-bottleneck/references/fusion-rules.md) 完成等价组聚合、冲突消解、依赖检查和策略过滤，输出包含 `primary_plan`、`extended_plan`、`excluded` 的结构化融合报告。域融合以此为输入，不做重新裁决，仅做跨域交叉验证和优先级排序。

融合逻辑按需读取：[references/fusion-logic.md](references/fusion-logic.md)

| 阶段 | 目标 |
|------|------|
| F-Phase 1 | 数据完整性校验：验证两份报告关键字段齐全 |
| F-Phase 2 | 交叉验证与矛盾消解：识别覆盖关系，消解矛盾冲突 |
| F-Phase 3 | 优先级排序：按 P0-Critical → P1-High → P2-Medium → P3-Low 排序 |
| F-Phase 4 | 调优方向与冲突约束：归类调优方向，识别资源冲突 |
| F-Phase 5 | 融合报告生成：输出完整融合报告 |

### 步骤 3.5：无瓶颈确认【显式步骤】

> **⚠️ 融合完成后，必须显式确认是否存在瓶颈。此步骤不可跳过。**

**无瓶颈判定条件**（以下全部满足时判定为"无瓶颈"）：
- 融合瓶颈优先级列表中无 P0-Critical 和 P1-High 级别项
- 所有场景分析结论均为"不适用"
- 通用分析未发现资源饱和或严重性能问题

| 判定结果 | 处理 |
|---------|------|
| 存在瓶颈 | 继续步骤4，正常交付融合报告 |
| 无瓶颈 | 在融合报告中明确标注"**当前系统无显著性能瓶颈**" |
| 不确定 | 标注"**瓶颈证据不充分**"，列出需要补充的数据 |

### 步骤 4：交付融合报告

- 融合报告路径：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`
- 报告输出格式按需读取：[references/fusion-report-template.md](references/fusion-report-template.md)

### 步骤 5：链式触发调优域【不可跳过】

> **⚠️ 流程衔接约束**：瓶颈分析域不是终点，而是调优域的前置。用户请求"分析瓶颈并给出调优建议"时，瓶颈分析完成后必须自动触发调优域，不得在交付融合报告后停止。

**触发条件判断**：

| 步骤3.5判定结果 | 是否触发调优域 | 说明 |
|----------------|--------------|------|
| 存在瓶颈 | **必须触发** | 融合报告包含调优方向，调优域据此生成建议 |
| 无瓶颈 | 不触发 | 报告已标注"当前系统无显著性能瓶颈"，无需调优 |
| 不确定 | **建议触发** | 报告标注"瓶颈证据不充分"，调优域可给出预防性建议 |

**触发方式**：

读取调优域入口技能定义 [../../optimization/opentunex-performance-tuning/SKILL.md](../../optimization/opentunex-performance-tuning/SKILL.md)，按其步骤执行调优流程。融合报告路径 `${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md` 作为调优域的数据输入。

**如果当前环境支持子智能体工具**：可通过子智能体工具启动调优域入口技能，将融合报告路径传入。

**如果当前环境不支持子智能体工具**：在当前上下文中读取调优域入口 SKILL.md 并执行其步骤。

---

## 按需加载资源

| 资源 | 路径/技能名称 | 何时读取 |
|------|------|---------|
| 结果融合逻辑 | [references/fusion-logic.md](references/fusion-logic.md) | 执行结果融合时 |
| 融合报告输出模板 | [references/fusion-report-template.md](references/fusion-report-template.md) | 生成融合报告时 |
| 契约文件规范 | [references/contract-spec.md](references/contract-spec.md) | 查看契约文件格式规范时 |
| 瓶颈分析域约束 | [references/constraints-bottleneck.md](references/constraints-bottleneck.md) | 查看完整约束列表时 |
| 数据采集域入口 | `opentunex-data-collection`技能 | 数据缺失需触发采集时 |
| 调优执行域入口 | `opentunex-performance-tuning`技能 | 步骤5链式触发调优域时 |

---

## 错误处理与降级

| 场景 | 处理方式 |
|------|---------|
| 子智能体启动失败 | 在契约文件中标记 status=failed，尝试重试一次 |
| 数据采集层输入缺失 | 提示数据采集层补充采集，不跳过分析 |
| 通用分析某阶段失败 | 标注失败阶段，继续后续阶段 |
| 场景分析执行异常 | 标注异常场景，继续其他场景分析 |
| 融合输入数据不完整 | 记录缺失项，向用户说明 |
| 交叉验证出现不可消解矛盾 | 标记为"待确认"，由用户决策 |
| 调优方向冲突无法自动消解 | 标记为"需人工确认" |
| 约束确认缺失 | 主智能体拒绝接受未确认约束的输出契约 |
