---
name: "opentunex-scenario-bottleneck"
description: "场景化瓶颈分析协调器。基于数据采集层提供的系统指标，串行调用所有场景分析技能并汇总结果。触发：瓶颈分析流程中场景化分析阶段。"
sub_agent_enabled: false
---

# opentunex-scenario-bottleneck — 场景化瓶颈分析协调器

> **⛔ 入口门：在执行 Phase 1 调度前，必须确认以下规则：**
>
> 1. **严格串行调用子技能（唯一执行方式）**——必须按调度声明表格的顺序，**每轮只加载一个子技能并执行其完整流程**；一个子技能的全部产出（输入/输出契约、分析报告）落盘后，才能开始加载下一个子技能。**禁止**一次性加载多个子技能后批量调度，**禁止**通过子智能体工具（Task Tool / Agent Tool / sessions\_spawn 等）并发启动多个子技能，**禁止**在当前上下文内联执行任何子技能的分析逻辑
> 2. **协调器禁止直接读取采集数据文件开始分析**——调用子技能之前不得预读取采集数据；数据路径只写入输入契约，由子技能自行读取。协调器对数据目录只允许做存在性检查（远端 `ls`/`test`），**禁止** `cat`/Read 数据文件内容

纯协调器，职责：

1. **严格串行**调度所有场景分析技能：按调度声明表格顺序，**逐个加载并调用**每个子技能；当前子技能完整产出后再加载下一个，**不做批量加载、不做并发调度、不做选择性跳过**
2. 汇总结果，保留各子技能原始结论术语

**不执行分析逻辑，不直接读取采集数据文件内容（仅允许存在性检查），不通过子智能体并发调度，不一次性加载多个子技能后批量操作。**

## 强制约束

> 本技能遵守 [瓶颈分析域约束](references/constraints-bottleneck.md) 中定义的所有执行约束和数据目录约定。

***

## 输入约定

在调度本技能之前已经采集好了性能数据，本技能只需要将上下文里的性能数据采集文件目录，在调度子技能时传递下去，不关心数据文件的采集。**禁止**直接读取数据文件。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`），由 `opentunex-bottleneck-analysis` 主智能体传入。
- **远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径。路径检查（`ls`）、按需采集（调用 `opentunex-data-collection` 组合 `opentunex-remote-execution`）、融合报告等文件产出都必须经 ssh 在远端执行：报告/契约等文件**直接在远端机器上产出**，**禁止**先在 agent 本地生成再 scp 上传，**禁止**在 agent 本地（如 Windows）创建或读写 `${WORK_DIR}`。具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，直接执行。
- **模式传递**：调用子技能时必须把 `execution_mode`/`user`/`ip`/`${WORK_DIR}` 写入输入契约并随任务描述传递，子技能不得自行改判模式。

### 路径解析

```
用户指定了 DATA_DIR？
  ├── 是 → 检查路径是否存在（远端模式经 ssh: ssh ${user}@${ip} "ls ${DATA_DIR}")
  │       ├── 存在 → 预采集模式，使用 DATA_DIR
  │       └── 不存在 → 提示路径无效，终止流程
  └── 否 → 检查 ${WORK_DIR}/ 下是否有采集数据（远端模式经 ssh 检查 ${WORK_DIR}/collect/）
          ├── 有 → 预采集模式，使用 ${WORK_DIR}/
          └── 无 → 提示无数据，终止流程
```

> **路径优先级**：`DATA_DIR`（用户指定） > `${WORK_DIR}/`

### 数据缺失处理

| 场景 | 处理 |
|------|------|
| 用户指定路径不存在 | 终止流程，提示检查路径 |

***

## Phase 1: 全量调度场景分析技能

**目标**：按调度声明表格顺序**串行调用**所有场景分析技能，不根据数据选择性跳过。

**设计原则**：场景分析技能自身包含完整的环境检查和适用性评估，协调器无需预判场景是否适用，应全量调度，由各技能自行输出结论。这确保：

- 不遗漏任何潜在的场景瓶颈
- 协调器逻辑与场景解耦，新增场景时无需修改调度逻辑
- 各技能原子化，可独立运行

### 子技能调度声明

| 子技能标识                              | 技能名称                                           | 输入契约路径                                                                             | 约束文件                                              | 输出契约路径                                                                              | 分析报告路径                                                                           |
| ---------------------------------- |------------------------------------------------| ---------------------------------------------------------------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| numa-sched-analysis                | `opentunex-numa-sched-analysis`                | \[analysis\_dir]/contracts/opentunex-numa-sched-analysis-input.yaml                | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-numa-sched-analysis-output.yaml                | \[analysis\_dir]/opentunex-numa-sched-analysis\_collect/result.md                |
| stealtask-analysis                 | `opentunex-stealtask-analysis`                 | \[analysis\_dir]/contracts/opentunex-stealtask-analysis-input.yaml                 | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-stealtask-analysis-output.yaml                 | \[analysis\_dir]/opentunex-stealtask-analysis\_collect/result.md                 |
| dynamic-smt-analysis               | `opentunex-dynamic-smt-analysis`               | \[analysis\_dir]/contracts/opentunex-dynamic-smt-analysis-input.yaml               | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-dynamic-smt-analysis-output.yaml               | \[analysis\_dir]/opentunex-dynamic-smt-analysis\_collect/result.md               |
| docker-coordination-burst-analysis | `opentunex-docker-coordination-burst-analysis` | \[analysis\_dir]/contracts/opentunex-docker-coordination-burst-analysis-input.yaml | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-docker-coordination-burst-analysis-output.yaml | \[analysis\_dir]/opentunex-docker-coordination-burst-analysis\_collect/result.md |
| soft-domain-analysis               | `opentunex-soft-domain-analysis`               | \[analysis\_dir]/contracts/opentunex-soft-domain-analysis-input.yaml               | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-soft-domain-analysis-output.yaml               | \[analysis\_dir]/opentunex-soft-domain-analysis\_collect/result.md               |
| multi-net-path-analysis            | `opentunex-multi-net-path-analysis`            | \[analysis\_dir]/contracts/opentunex-multi-net-path-analysis-input.yaml            | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-multi-net-path-analysis-output.yaml            | \[analysis\_dir]/opentunex-multi-net-path-analysis\_collect/result.md            |
| btb-analysis                       | `opentunex-btb-analysis`                       | \[analysis\_dir]/contracts/opentunex-btb-analysis-input.yaml                       | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-btb-analysis-output.yaml                       | \[analysis\_dir]/opentunex-btb-analysis\_collect/result.md                       |
| copy-user-analysis                 | `opentunex-copy-user-analysis`                 | \[analysis\_dir]/contracts/opentunex-copy-user-analysis-input.yaml                 | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-copy-user-analysis-output.yaml                 | \[analysis\_dir]/opentunex-copy-user-analysis\_collect/result.md                 |
| hisock-analysis                    | `opentunex-hisock-analysis`                    | \[analysis\_dir]/contracts/opentunex-hisock-analysis-input.yaml                    | constraints-bottleneck.md + common-constraints.md | \[analysis\_dir]/contracts/opentunex-hisock-analysis-output.yaml                    | \[analysis\_dir]/opentunex-hisock-analysis\_collect/result.md                    |

**调度方式**：**严格串行**——按调度声明表格的顺序，每轮只加载一个子技能 SKILL.md 并调用其完整流程；该子技能的全部产出（输入/输出契约 + 分析报告）写入磁盘后，再加载并调用下一个子技能。**禁止**一次性将多个子技能 SKILL.md 同时加载到当前上下文，**禁止**通过子智能体工具（Task Tool / Agent Tool / sessions\_spawn 等）并发启动多个子技能，**禁止**在当前上下文内联执行任何子技能的分析逻辑。9 个子技能一个都不能跳过、不能批量执行。

**子技能任务描述**（按调度声明表格逐行使用）：

> 读取技能定义 \[技能名称]，读取输入契约 \[输入契约路径]，读取约束文件 \[约束文件路径]，执行技能定义中的步骤，写入输出契约 \[输出契约路径]，写入分析报告 \[分析报告路径]。**执行上下文**：execution_mode=remote（或 local）；远端模式时 ${user}@${ip} 为远端连接信息，${WORK_DIR} 为远端路径，所有对 ${WORK_DIR} 的读写经 opentunex-remote-execution 在远端执行（见 references/work_dir_remote_semantics.md），禁止在 agent 本地操作 ${WORK_DIR}。

**全量调度**：所有 9 个子技能均需串行调用，不做选择性过滤、不做并发执行。场景分析技能自身包含完整的环境检查和适用性评估，由各技能自行输出结论。

### 串行调用执行规则

串行调用是**唯一**的执行方式，不存在并发或降级分支。执行时必须遵守：

- **一次只加载一个子技能**：当前轮只读取一个子技能 SKILL.md 并执行其完整流程，禁止一次性读取多个子技能 SKILL.md
- **完成后再加载下一个**：当前子技能的全部产出（输入/输出契约 + 分析报告）写入磁盘后，才能开始读取下一个子技能 SKILL.md
- **禁止并发调度**：禁止通过任何子智能体工具（Task Tool / Agent Tool / sessions\_spawn 等）同时启动多个子技能
- **禁止内联执行**：禁止在当前上下文中读取子技能 SKILL.md 后直接执行其分析逻辑
- **禁止读取采集数据**：协调器不读取任何采集数据文件内容（仅允许存在性检查）；数据文件的读取只能发生在子技能执行流程内

**串行调用任务描述模板**（按调度声明表格逐行使用）：

> 读取技能定义 \[技能名称]，读取输入契约 \[输入契约路径]，读取约束文件 \[约束文件路径]，执行技能定义中的步骤，写入输出契约 \[输出契约路径]，写入分析报告 \[分析报告路径]。**执行上下文**：execution_mode=remote（或 local）；远端模式时 ${user}@${ip} 为远端连接信息，${WORK_DIR} 为远端路径，所有对 ${WORK_DIR} 的读写经 opentunex-remote-execution 在远端执行（见 references/work_dir_remote_semantics.md），禁止在 agent 本地操作 ${WORK_DIR}。

### 错误处理与容错机制

| 异常场景             | 处理策略                       |
| ---------------- | -------------------------- |
| 单个子技能执行失败        | 标记为"执行失败"，记录错误原因，继续执行其他子技能 |
| 子技能执行超时（默认 300s） | 标记为"超时"，继续执行其他子技能          |
| 所有子技能均失败         | 输出"所有场景分析均失败"结论，列出各子技能失败原因 |

### 子技能执行状态

每个子技能执行后应记录以下状态：

| 状态            | 说明             |
| ------------- | -------------- |
| `success`     | 执行成功，结果已汇总     |
| `failed`      | 执行失败，记录错误原因    |
| `timeout`     | 执行超时（超过 300 秒） |
| `parse_error` | 执行完成但结果无法解析    |

***

## Phase 2: 结果融合

> **目标**：在所有子技能完成分析后，提取各报告的 `## 结构化数据` 区块，按 [references/fusion-rules.md](references/fusion-rules.md) 规则进行等价组聚合、组内择优、冲突消解、依赖检查、策略过滤，最终输出一份统一的融合报告。

**输出模板**：[references/output-template.md](references/output-template.md)

### 2.1 前置条件

启动前必须确认：

- 所有子技能已执行完毕（Phase 1 完成）
- 每个成功子技能已生成 `[analysis_dir]/<skill_name>_collect/result.md`
- 每个成功报告末尾包含 `## 结构化数据` 区块（JSON 格式，符合 [融合数据格式](references/fusion-rules.md#一结构化数据字段定义)）

### 2.2 融合执行

按 [references/fusion-rules.md](references/fusion-rules.md) 的流程执行：

1. **提取叙述性字段**（优先于融合步骤 1）：扫描每个成功子技能 result.md 的分析结论区块，按 [references/result-template.md](references/result-template.md) 规则提取 **综合结论**、**预期收益**、**建议操作**，填充融合报告"场景分析汇总"表的基础数据
2. **收集与标准化**：扫描每个成功子技能报告的 `## 结构化数据` 区块，提取 JSON 数据；补齐默认字段（`conflicts`→`[]`、`scenario_priority`→`0`、`source`→`"skill_output"`）；将 `applicability` 为 `not_applicable` 的建议直接归入 excluded（场景不适用）；将来源为 `llm_knowledge` 的临时建议归入 supplementary；构建全局冲突图和依赖图
3. **等价组划分**：按 `equivalence_class` 字段分组
4. **组内择优排序**：按 `scenario_priority` → `severity` → `activation_requirement` → `source` 四级排序
5. **构建初始选中集 S**：取每组排名第一的建议
6. **冲突消解**：按组内择优相同排序键消解冲突，从备选递补
7. **依赖检查**：检查 `prerequisites`，级联移除依赖不满足的建议
8. **会话策略过滤**：应用可选的 `no_reboot`、`min_gain_severity` 等策略
9. **生成扩展方案**：从各替代组的剩余备选及原本被排除但不引入新冲突的建议中，选取无冲突、依赖满足的增强建议
10. **编排执行顺序**：按依赖拓扑 + 生效成本排序
11. **输出融合报告**：按 [references/output-template.md](references/output-template.md) 格式输出

### 2.3 融合报告产出

融合报告写入 `${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`（**远端模式**：报告文件**直接在远端机器上产出**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成报告文件再 scp 上传、禁止在 agent 本地目录写入该路径），严格遵循 [references/output-template.md](references/output-template.md) 格式输出，10 个模块的字段来源如下：

#### 字段映射表（result.md → 融合报告 "场景分析汇总"）

| 融合报告列 | 数据来源                               | 提取规则                                                                                     |
| ------------------ | ---------------------------------- | ---------------------------------------------------------------------------------------- |
| **ID**             | 协调器分配                              | 按 S-001, S-002, ... 编号                                                                   |
| **场景**             | 子技能 name 字段                        | 取 SKILL.md 头部的 `name` 或目录名                                                               |
| **状态**             | Phase 1 执行状态                       | `success` / `failed` / `timeout` / `parse_error`                                         |
| **适用性**            | 结构化数据 `applicability`              | `applicable`→"适用"、`limited_benefit`→"收益有限"、`not_applicable`→"不适用"                        |
| **严重度**            | 结构化数据 `estimated_gain.severity`    | 按 fusion-rules.md §1.12 映射：`high`→P1-High、`medium`→P2-Medium、`low`→P3-Low                |
| **关键发现**           | result.md 叙述性分析                    | 提取 **综合结论** 行中 `—` 之后的瓶颈现象描述（降级：使用结构化数据 `estimated_gain.primary_metric` + `description`） |
| **预期收益**           | 结构化数据 `estimated_gain.description` | 直接引用（降级：result.md **预期收益** 行）                                                            |
| **建议调优方向**         | 结构化数据 `suggestion`                 | 直接引用（降级：result.md **建议操作** 行）                                                            |

#### 报告包含的 10 个模块

- 融合概览（输入技能数、提取建议数、等价组数、采纳/排除数）
- 场景分析汇总表（按上述字段映射填充）
- 主推荐方案（primary\_plan）：融合后保留的最终调优建议集合
- 等价组详情（每组内排序结果与采纳/备选说明）
- 被排除项：冲突消解/依赖检查/策略过滤中被排除的建议及原因
- 跨技能协同关系：`synergy_with` 字段的协同增强标记
- 扩展方案（extended\_plan）
- 执行顺序（implementation\_order）：按依赖拓扑和生效方式排序
- 实施建议（风险提示 + supplementary）
- 异常与遗漏（执行异常 + 未覆盖方向）

***

## 操作说明

- 纯协调器，不执行分析逻辑；按需采集模式下可调用数据采集技能。远端模式下对 `${WORK_DIR}` 的文件操作（路径检查、报告落盘）经 `opentunex-remote-execution` 的 ssh 在远端执行，不在 agent 本地操作
- 全量调度所有场景分析技能，不做选择性过滤
- 串行调用模式：**禁止**一次性加载多个子技能 SKILL.md；必须按调度声明表格顺序，一个一个加载并调用，每个子技能全部产出（输入/输出契约 + 分析报告）写入磁盘后才能开始下一个；**禁止**通过子智能体工具并发启动、**禁止**在当前上下文内联执行子技能的分析逻辑
- 支持两种数据获取模式：预采集模式（用户提供数据）和按需采集模式（自动调用数据采集技能）
- 通过目录结构动态发现场景分析技能，新增场景时只需创建新的 `opentunex-*` 子目录
- 单个子技能失败不影响其他子技能执行，所有结果（含失败）均汇总到报告中
- 严重度分级使用统一术语：P0-Critical / P1-High / P2-Medium / P3-Low

***

## 契约输出

输出契约格式参见 [contract-spec.md](references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-scenario-bottleneck"
input:
  analysis_dir: "${WORK_DIR}/analysis"
  data_dir: "${DATA_DIR 或 WORK_DIR}/collect"
  work_dir: "${WORK_DIR}/"
  data_mode: "pre_collected / on_demand"
execution_context:
  execution_mode: "remote" | "local"
  user: "<远端用户名，默认 root>"
  ip: "<远端服务器 IP>"
output:
  report_path: "${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"
  sub_reports: "${WORK_DIR}/analysis/"
constraints_acknowledged: [B-01~B-08, SB-01~SB-07]
```

