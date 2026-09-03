---
name: "opentunex-performance-tuning"
description: "调优执行大类。基于融合分析报告的调优执行计划，调度各调优技能，汇总建议生成一份完整的调优建议报告。触发条件：(1)用户请求性能调优、参数优化、配置调整、调优建议；(2)瓶颈分析完成后自动触发；(3)融合报告生成后需要生成调优建议。"
sub_agent_enabled: true
constraints_file: "references/constraints-tuning.md"
---

# 调优执行域入口技能

> **⛔ 入口门：在执行任何操作前，必须确认以下4条规则。违反任何一条即为本技能的执行失败：**
> 
> 1. **本技能必须尝试通过子智能体工具启动调优**——不得在当前上下文中直接读取融合报告并手写调优建议。各调优技能应通过子智能体工具启动独立上下文执行。如果子智能体工具不可用或能力不足（如无法写文件），才允许降级模式，但必须标注 `execution_mode: "degraded"` 并记录降级原因。
> 2. **在启动子智能体之前，不得读取融合报告全文**——仅提取调优方向列表用于路由，报告路径写入输入契约，由子智能体自行读取。"数据已在上下文中"不是跳过子智能体的理由。
> 3. **本技能的职责是调度编排和汇总**——不负责调优逻辑。正确流程：创建目录 → 写契约 → 启动子智能体 → 校验输出 → 汇总报告。
> 4. **路径不匹配不是豁免条款**——无论融合报告在哪个目录（`${WORK_DIR}/analysis/` 或用户自定义路径），都必须走完整协议流程。数据路径只是输入契约中的一个字段，路径差异不影响执行步骤。不得因"路径不是标准路径"而跳过任何步骤。

基于融合分析报告的调优执行计划，通过子智能体调度各调优技能，汇总建议生成一份完整的调优建议报告。

## 强制约束

### 正确职责

调优技能的正确职责：依据瓶颈分析结果 → 生成中间态调优建议 → 由调优域入口汇总为一份完整报告 → **由用户确认后再执行**

### 数据目录

- 读取：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`
- 写入：`${WORK_DIR}/tuning/tuning-report.md`
- 中间态：`${WORK_DIR}/tuning/intermediate/`
- 融合报告缺失时，必须提醒用户需要先完成瓶颈分析流程

### 执行模式与 `${WORK_DIR}` 语义（核心）

- **远端模式**（用户输入含远端 IP，由 `witty-opentunex` 判定并传递）：`${WORK_DIR}` 是**远端服务器上**的路径。本技能中所有对 `${WORK_DIR}` 的操作（mkdir/ls/读融合报告/读契约/写契约/写报告/复制脚本/打包）都必须在**远端**执行——经 `opentunex-remote-execution` 的 ssh 机制，**禁止**在 agent 本地（如 Windows）对 `${WORK_DIR}` 做任何文件操作。具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`，下方命令块已标注远端/本地写法
- **本地模式**（无 IP）：`${WORK_DIR}` 为 agent 主机本地目录，命令直接本地执行
- **模式传递**：启动子智能体时，必须把 `execution_mode`、`user`、`ip`、`${WORK_DIR}` 写入输入契约并随任务描述传给子智能体；子智能体同样遵守远端语义
- 注意：本技能生成的调优脚本与调优命令**不自动执行**（遵守 T-01/T-02，由用户确认后执行）；远端模式下脚本部署到远端 `${WORK_DIR}/tuning/...`，由用户在**远端服务器**上运行

### 子技能约束

子技能执行约束（含禁止项 T-01~T-10）详见 [references/constraints-tuning.md](references/constraints-tuning.md)，子智能体必须在输出契约中确认遵守。

**⚠️ T-10: 禁止内联执行子技能（核心约束）**：

> 调度声明中列出的子智能体必须尝试通过子智能体工具启动独立上下文执行，禁止在当前上下文中内联读取子技能 SKILL.md 直接执行。完整约束语义见 [references/constraints-tuning.md](references/constraints-tuning.md) T-10 条。
>
> 核心要点：
> - 如果子智能体工具不可用或能力不足（如无法写文件），才允许降级模式，但必须标注 `execution_mode: "degraded"` 并记录降级原因
> - **严禁在子智能体工具可用时主动选择降级模式，即使认为内联执行更高效或更方便**
> - **"数据已加载到上下文"不是跳过子智能体的正当理由——这正是 T-10 要防止的可及性偏差**
> - **路径不匹配不是豁免条款**——数据路径只是输入契约中的一个字段，路径差异不影响执行步骤

> **⚠️ 会话 compaction 防护**：如果本会话经历过上下文压缩（compaction），可能导致对 T-10 约束的理解丢失或歧义。任何情况下，"子智能体不能内联执行"的含义是**必须通过子智能体工具启动独立上下文**，而不是"不执行子智能体、直接在当前上下文合成结果"。

> **⚠️ 数据已在上下文中的场景**：如果融合报告已经因为用户输入、会话历史、或其他原因加载到了当前上下文中，**仍然必须启动子智能体**。正确做法是将报告路径（而非报告内容）写入输入契约，让子智能体在独立上下文中重新读取报告文件。主智能体不得因为"报告已经在上下文中"就跳过子智能体调度——上下文隔离和并行能力的价值不依赖于数据是否已加载。

---

## 子智能体调度协议

### 调度声明

本技能需要调度以下子智能体（按需调度，仅根据融合报告明确指定的调优方向启动）。**场景化调优子技能（numa-sched-tuning / stealtask-tuning / docker-coordination-burst-tuning / soft-domain-tuning / dynamic-smt-tuning / multi-net-path-tuning）不再由本入口直接调用，统一委派给 `opentunex-scenario-tuning` 协调器在其子智能体上下文中调度。本入口禁止再直接调用这 6 个子技能。**

| 子智能体                                | 技能名称                                            | 输入契约路径                                                                          | 约束文件 | 输出契约路径                                                                           | 中间态建议路径                                                          |
|-------------------------------------|-------------------------------------------------|---------------------------------------------------------------------------------|---------|----------------------------------------------------------------------------------|------------------------------------------------------------------|
| os-performance-optimization         | `opentunex-os-performance-optimization`         | [report_dir]/contracts/opentunex-os-performance-optimization-input.yaml         | references/constraints-tuning.md | [report_dir]/contracts/opentunex-os-performance-optimization-output.yaml         | [report_dir]/intermediate/os-performance-optimization.md         |
| application-optimization            | `opentunex-application-optimization`            | [report_dir]/contracts/opentunex-application-optimization-input.yaml            | references/constraints-tuning.md | [report_dir]/contracts/opentunex-application-optimization-output.yaml            | [report_dir]/intermediate/application-optimization.md            |
| inference-core-binding-optimization | `opentunex-inference-core-binding-optimization` | [report_dir]/contracts/opentunex-inference-core-binding-optimization-input.yaml | references/constraints-tuning.md | [report_dir]/contracts/opentunex-inference-core-binding-optimization-output.yaml | [report_dir]/intermediate/inference-core-binding-optimization.md |
| **scenario-tuning（协调器）**           | `opentunex-scenario-tuning`                     | [report_dir]/contracts/opentunex-scenario-tuning-input.yaml                     | references/constraints-tuning.md + opentunex-scenario-tuning/references/common-constraints.md | [report_dir]/contracts/opentunex-scenario-tuning-output.yaml                     | [report_dir]/intermediate/&lt;scenario-skill&gt;.md（由协调器在其内部按需生成） |

> **scenario-tuning 行说明**：
> - 该行必须通过子智能体工具启动一个 `opentunex-scenario-tuning` 子智能体；由该子智能体在其独立上下文中调度下属 6 个场景化调优子技能（numa-sched-tuning / stealtask-tuning / docker-coordination-burst-tuning / soft-domain-tuning / dynamic-smt-tuning / multi-net-path-tuning）
> - 本入口**禁止**再直接调用这 6 个子技能
> - scenario-tuning 子智能体写出场景化中间态建议到 `${WORK_DIR}/tuning/intermediate/`（与本入口的路径一致），由本入口在步骤 3 汇总阶段统一读取
> - scenario-tuning 子智能体还需在其 `output.contract` 中确认 ST-01~ST-05 约束已遵守
> - **硬依赖**：若 `opentunex-scenario-tuning` 不在技能注册表或启动失败，本流程直接终止并报错，不进入降级路径

**调度方式**：使用当前环境中可用的子智能体工具（如 sessions_spawn+sessions_yield、Task Tool、Agent Tool 等）启动上述子智能体。具体调用格式由运行时环境决定，本技能不限定。

**子智能体任务描述**（传入子智能体的指令）：
> 读取技能定义 [技能名称]，读取输入契约 [输入契约路径]，读取约束文件 [约束文件路径]，执行技能定义中的步骤，写入输出契约 [输出契约路径]，写入中间态建议 [中间态建议路径]

### 降级模式（仅在子智能体工具不可用时使用）

降级模式**不是首选执行路径**，仅在子智能体工具不可用或启动失败时使用：

降级执行时必须：
- 在输出契约中标注 `execution_mode: "degraded"` 并记录降级原因
- 逐个读取子技能的 SKILL.md，每次只加载一个，执行完毕后释放上下文再加载下一个
- 仍须遵守所有约束和契约输出要求

---

## 调度清单

### 通用调优

| 子技能 | 路径 | 调优方向 |
|--------|------|---------|
| OS性能优化 | opentunex-os-performance-optimization/SKILL.md | CPU/内存/IO/网络参数 |
| 应用优化 | opentunex-application-optimization/SKILL.md | 应用配置与运行参数 |

### 场景化调优

> **⚠️ 场景化调优已重构**：原 6 个场景化子技能（NUMA / 窃取任务 / Docker算力 / 分域调度 / 动态SMT / 网卡多路径）现在统一由 `opentunex-scenario-tuning` 协调器调度，本入口不再直接调用这些子技能。

| 子技能 | 路径 | 调优方向 |
|--------|------|---------|
| 场景化调优协调器 | opentunex-scenario-tuning/SKILL.md | 统一调度 6 个场景化调优子技能（NUMA / 窃取任务 / Docker算力 / 分域调度 / 动态SMT / 网卡多路径） |
| 推理绑核优化 | opentunex-inference-core-binding-optimization/SKILL.md | 推理核心绑核 |

### 调优方向路由映射

> **⚠️ 路由映射表保留全部 12 个调优方向，用于从融合报告中识别调优方向——但场景化方向的"路由到的子技能"列已统一改为 `scenario-tuning`，表示该方向由 `opentunex-scenario-tuning` 协调器统一调度，本入口不再直接调用其下属子技能。

| 融合报告中的调优方向描述 | 路由到的子技能 |
|------------------------|--------------|
| OS内核CPU调度参数优化 | os-performance-optimization |
| OS内存管理参数优化 | os-performance-optimization |
| OS磁盘IO调度参数优化 | os-performance-optimization |
| OS网络协议栈参数优化 | os-performance-optimization |
| 应用配置与运行参数优化 | application-optimization |
| numa并行感知调度特性优化 | scenario-tuning（→ numa-sched-tuning） |
| 窃取任务调度特性优化 | scenario-tuning（→ stealtask-tuning） |
| Docker算力统筹优化 | scenario-tuning（→ docker-coordination-burst-tuning） |
| 推理核心绑核优化 | inference-core-binding-optimization |
| 分域调度soft_domain特性优化 | scenario-tuning（→ soft-domain-tuning） |
| 动态SMT调度特性优化 | scenario-tuning（→ dynamic-smt-tuning） |
| 网卡多路径中断亲和优化 | scenario-tuning（→ multi-net-path-tuning） |

### 冲突约束

> **⚠️ 冲突域说明**：
> - **跨域冲突**（如 numa↔OS-CPU）：涉及本入口直接调度的子技能（os-performance-optimization）与场景化协调器（scenario-tuning）之间——由**本入口在顶层调度阶段**负责串行处理
> - **域内冲突**（如 stealtask↔numa）：完全发生在 scenario-tuning 协调器下属 6 个子技能之间——由 `opentunex-scenario-tuning` 在其内部调度时负责串行处理（本入口无需关心）

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 | 冲突域 |
|----------|----------|---------|---------|-------|
| numa并行感知调度特性优化 | OS内核CPU调度参数优化 | sched_util_low_pct | 串行：先 scenario-tuning（含 numa），后 os-performance-optimization | 跨域（本入口处理） |
| 窃取任务调度特性优化 | numa并行感知调度特性优化 | sched_features | 串行：先 numa，后 stealtask（在 scenario-tuning 内部完成） | 域内（scenario-tuning 处理） |

---

## 执行步骤

### 步骤 0：创建调优报告目录与契约目录【强制】

**远端模式**（`${WORK_DIR}` 是远端路径，经 ssh 在远端创建）：

```bash
ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/tuning/contracts ${WORK_DIR}/tuning/intermediate"
```

**本地模式**（agent 主机即目标机）：

```bash
mkdir -p ${WORK_DIR}/tuning/{contracts,intermediate}
```

> **远端模式禁止**：在 agent 本地（如 Windows）`mkdir ${WORK_DIR}/...`——`${WORK_DIR}` 只存在于远端。

#### 步骤 0 完成检查清单【不可跳过】

在进入步骤 1 前，必须确认以下各项：

- [ ] **已重新读取约束文件** `references/constraints-tuning.md`（防止会话 compaction 后 T-10 语义丢失）
- [ ] 调优报告目录已创建：`${WORK_DIR}/tuning/contracts/` 与 `${WORK_DIR}/tuning/intermediate/` 存在
- [ ] 融合报告已确认存在：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md` 存在
- [ ] **尚未读取融合报告内容**（调优方向由子智能体自行读取融合报告后判断）
- [ ] 准备好写入输入契约并启动子智能体
- [ ] `opentunex-scenario-tuning` 技能可用性已确认（在技能注册表中存在；若启动失败，流程将直接终止，无降级路径）

> **⚠️ 关键时序约束**：主智能体在启动子智能体之前**不得读取融合报告全文**。融合报告路径写入输入契约，由子智能体在独立上下文中自行读取。如果主智能体提前读取了融合报告，"数据在手"的可及性会压制子智能体调度的动机，导致违反 T-10 约束。

### 步骤 1：识别调优方向并启动子智能体【调度阶段，限制数据读取范围】

> **⚠️ T-10 执行纪律检查点**：
> 
> 在执行本步骤前，自问以下问题：
> - 我是否已经读取了融合报告全文？如果是 → **停止**，你已经违反了 T-10 约束
> - 我是否正打算先看完整报告再决定怎么调优？如果是 → **停止**，只读调优方向列表
> - 我是否觉得"数据都在手边了，直接写调优建议更快"？如果是 → **这正是 T-10 要防止的可及性偏差**
> - 融合报告路径不是 `${WORK_DIR}/analysis/` → **路径不匹配不是豁免条款**，把实际路径写入输入契约的 fusion_report 字段即可
> 
> **正确做法**：只读调优方向列表，写契约路径（fusion_report 填实际路径），spawn 子智能体，让它们自己读融合报告全文。

#### 1.1 识别调优方向（仅读取调优方向列表，禁止读取瓶颈详情和证据）

**读取路径**：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`（远端模式经 ssh 在远端读取，禁止 scp 拷回本地）

```bash
# ✅ 允许：只提取调优方向列表（通常在报告末尾的"建议调优方向"章节）
# 远端模式: ssh -q ${user}@${ip} "grep -A 20 '建议调优方向' ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"
# 本地模式: grep -A 20 "建议调优方向" result.md

# ❌ 禁止：读取完整融合报告
# cat result.md  ← 违反 T-10
# 读取所有瓶颈详情和证据数据  ← 违反 T-10
```

**仅提取**：调优方向列表（用于路由到子技能），不读取瓶颈详情和证据数据。

**识别逻辑**：融合报告中的"建议调优方向"字段作为路由键，匹配调度清单中的路由映射表。

#### 1.2 写入输入契约并启动子智能体

对每个调优方向，先写入输入契约，再启动子智能体。

**通用调优 / 推理绑核子技能的输入契约模板**（契约文件写入 `${WORK_DIR}/tuning/contracts/`——远端模式：本地 Write 后 scp 上传到远端路径）：

```yaml
contract_type: "input"
skill_name: "<skill-name>"
timestamp: "<timestamp>"
input:
  report_dir: "${WORK_DIR}/tuning/"
  fusion_report: "${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"
  intermediate_path: "intermediate/<skill-name>.md"
execution_context:
  execution_mode: "remote" | "local"
  user: "<远端用户名，默认 root>"
  ip: "<远端服务器 IP>"
constraints_file: "references/constraints-tuning.md"
```

**scenario-tuning 协调器的输入契约模板**（注意该行启动的是协调器，不是 6 个场景化子技能本身）：

```yaml
contract_type: "input"
skill_name: "opentunex-scenario-tuning"
timestamp: "<timestamp>"
input:
  report_dir: "${WORK_DIR}/tuning/"
  fusion_report: "${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"
  intermediate_dir: "${WORK_DIR}/tuning/intermediate/"
  requested_directions:
    - "<从融合报告中提取的场景化方向列表，如 numa并行感知调度特性优化、窃取任务调度特性优化…>"
  conflict_constraints:
    - "跨域冲突由本入口负责；域内冲突由 scenario-tuning 内部处理"
execution_context:
  execution_mode: "remote" | "local"
  user: "<远端用户名，默认 root>"
  ip: "<远端服务器 IP>"
constraints_file: "references/constraints-tuning.md"
extra_constraints:
  - "opentunex-scenario-tuning/references/common-constraints.md"
```

**子智能体任务描述必须包含执行模式上下文**：`execution_mode=remote（user、ip 如上），${WORK_DIR} 为远端路径，所有对 ${WORK_DIR} 的读写经 opentunex-remote-execution 在远端执行，见 references/work_dir_remote_semantics.md`。

**调度策略**：

- **按需生成**：仅根据融合报告明确指定的调优方向调度子智能体
- **按批次建议**：融合报告已包含冲突检测和执行顺序，按批次调度
- **冲突串行**：有冲突约束的调优方向按约束条件串行调度子智能体
- **无冲突并行**：不涉及相同系统资源的调优方向可并行调度子智能体
- **scenario-tuning 与通用调优的调度顺序**：
  - 默认情况下 `scenario-tuning` 与 3 个非场景子技能（os-performance-optimization / application-optimization / inference-core-binding-optimization）之间**并行**
  - 例外：当融合报告同时标注 `numa并行感知调度特性优化` 与 `OS内核CPU调度参数优化` 时（跨域冲突 `sched_util_low_pct`），按冲突表策略**先启动 scenario-tuning（含 numa），待其完成后再启动 `opentunex-os-performance-optimization`**
  - 域内冲突（如 stealtask ↔ numa 的 `sched_features`）由 `scenario-tuning` 在其内部串行处理，本入口无需关心

### 步骤 2：等待子智能体完成，校验输出契约【输出校验门】

> **⚠️ 本步骤是输出校验门——如果子智能体输出契约文件不存在，汇总阶段无法继续。这阻止了跳过子智能体后试图直接手写中间态的死胡同。**

1. 等待所有子智能体执行完成
2. 读取各子智能体的输出契约，确认 status 和 constraints_acknowledged（**远端模式**：契约在远端，经 ssh 读取——`ssh -q ${user}@${ip} "cat ${WORK_DIR}/tuning/contracts/<name>-output.yaml"`，**禁止** scp 拷回本地）
3. **校验门检查**：

| # | 校验项 | 通过条件 | 未通过处理 |
|---|--------|---------|-----------|
| G-1 | 各调优子智能体输出契约存在 | `[report_dir]/contracts/<skill-name>-output.yaml` 文件存在（含 scenario-tuning） | 等待或重试子智能体 |
| G-2 | 各调优子智能体状态为 success | output.yaml 中 status=success | 检查错误原因，必要时重试；scenario-tuning 失败时**直接终止流程**，不进入降级路径 |
| G-3 | 中间态建议文件存在 | `${WORK_DIR}/tuning/intermediate/` 下至少有 3 个非场景子技能 + 0 个或多个场景子技能的中间态文件（场景化中间态由 scenario-tuning 在其内部写出） | 等待或重试子智能体 |
| G-4 | 约束已确认 | 通用子技能 constraints_acknowledged 包含 T-01~T-10；scenario-tuning 子智能体还需包含 ST-01~ST-05 | 拒绝接受未确认约束的输出 |

**scenario-tuning 子智能体的硬依赖行为**：

- 若 `[report_dir]/contracts/opentunex-scenario-tuning-output.yaml` 不存在或 `status != success`，校验门 G-1 / G-2 不通过，**本流程直接终止**并提示用户：
  > "场景化调优协调器 (`opentunex-scenario-tuning`) 执行失败，请检查该技能是否已在技能注册表中注册、约束文件是否齐全、`execution_mode`/`user`/`ip` 是否正确传入。"
- 不进入降级路径（不直接调用 6 个场景化子技能作为替代）
- 已完成的非场景子技能结果可在错误信息中保留作为部分产出，但不写入最终 `tuning-report.md`

**如果校验门未通过，不得进入步骤 3 汇总阶段。**

### 步骤 3：汇总中间态建议

1. 收集各调优技能的中间态调优建议（从 `${WORK_DIR}/tuning/intermediate/` 读取；**远端模式**经 ssh 读取：`ssh -q ${user}@${ip} "cat ${WORK_DIR}/tuning/intermediate/<skill-name>.md"`，禁止 scp 拷回本地）
2. 合并总结表，去重并统一编号
3. 合并调优建议，按融合报告的优先级排序

### 步骤 4：生成调优脚本

为每个调优方向生成对应的调优脚本，按调优技能名称建立独立文件夹。

> **远端模式**：调优脚本与基础脚本最终部署到**远端** `${WORK_DIR}/tuning/<调优技能名称>/`——先用 Write 工具在 agent 本地生成 `tuning.sh`，与技能 `scripts/` 下的基础脚本一并 `scp` 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}/tuning/...` 目录树。脚本不自动执行，由用户在远端服务器上运行（遵守 T-01/T-02）。

#### 脚本目录结构

```
<调优技能名称>/
├── tuning.sh              # 入口脚本（动态生成，含动态参数）
└── <基础脚本>             # 从技能 scripts/ 目录复制
```

#### 入口脚本模板

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析结果填充）

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/[基础脚本名]" check
        ;;
    apply)
        bash "${SCRIPT_DIR}/[基础脚本名]" apply [动态参数]
        ;;
    rollback)
        bash "${SCRIPT_DIR}/[基础脚本名]" rollback
        ;;
    *)
        echo "用法: $0 {check|apply|rollback}"
        exit 1
        ;;
esac
```

### 步骤 5：输出调优建议报告与打包

依据 [最终汇总报告模板](references/tuning-report-template.md) 生成一份完整的调优建议报告。

#### 报告输出约定

- 最终汇总报告：`${WORK_DIR}/tuning/tuning-report.md`
- 中间态建议：`${WORK_DIR}/tuning/intermediate/`
- 调优脚本：`${WORK_DIR}/tuning/<调优技能名称>/`
- 压缩包：`${WORK_DIR}/tuning-package_<YYYYMMDD_HHMMSS>.tar.gz`
- 契约文件：`${WORK_DIR}/tuning/contracts/`

**远端模式**：以上均为远端路径。报告文件本地 Write 后 scp 上传到远端；压缩包在**远端**打包：

```bash
# 远端打包（${WORK_DIR} 为远端路径，tar 在远端执行，产物留在远端）
ssh ${user}@${ip} "cd ${WORK_DIR} && tar czf tuning-package_<YYYYMMDD_HHMMSS>.tar.gz tuning/"
```

禁止在 agent 本地对 `${WORK_DIR}` 执行 tar/mkdir/cat 等操作。

---

## 按需加载资源

| 资源 | 路径/技能名称 | 何时读取 |
|------|-----------|---------|
| 调优场景映射 | [scenario/SKILL_MAPPING.md](scenario/SKILL_MAPPING.md) | 查看完整调优方向映射时 |
| 最终汇总报告模板 | [references/tuning-report-template.md](references/tuning-report-template.md) | 生成最终报告时 |
| 中间态建议模板 | [references/intermediate-report-template.md](references/intermediate-report-template.md) | 各调优技能生成中间态建议时 |
| 契约文件规范 | [references/contract-spec.md](references/contract-spec.md) | 查看契约文件格式规范时 |
| 调优域约束 | [references/constraints-tuning.md](references/constraints-tuning.md) | 查看完整约束列表时 |
| 瓶颈分析域入口 | `opentunex-bottleneck-analysis`技能 | 需要先完成瓶颈分析时 |

---

## 错误处理与降级

| 场景 | 处理方式 |
|------|---------|
| 子智能体启动失败 | 在契约文件中标记 status=failed，尝试重试一次 |
| 融合报告缺失 | 提醒用户需要先完成瓶颈分析流程 |
| 调优技能执行异常 | 标注异常项，继续其他调优技能 |
| 中间态建议格式不符 | 要求子智能体重新生成，或手动修正 |
| 约束确认缺失 | 主智能体拒绝接受未确认约束的输出契约 |
