---
name: fusion-logic
description: 瓶颈分析结果融合逻辑定义
---

# 结果融合逻辑

通用分析与场景化分析完成后，必须进行结果融合。融合包含五个阶段。

## 前置：子技能结论→统一术语映射

各子技能使用各自的结论术语输出，融合阶段需根据语义映射为以下统一术语。

| 统一术语 | 含义 | 对应动作 |
|---------|------|---------|
| **适用** | 存在可调优瓶颈，优化后预期有显著收益 | 进入调优列表，分配严重度 |
| **收益有限** | 存在轻微问题但优化收益有限，或已正确配置 | 记录但不进入调优列表 |
| **不适用** | 环境不支持或无瓶颈 | 不进入调优列表 |

> **映射原则**：根据子技能原始结论的语义直接映射。例如"建议启用"→适用，"不建议启用"→收益有限，"环境不支持"→不适用。

## F-Phase 1: 数据完整性校验

> **输入说明**：域融合的两个输入分别为：
> - **通用分析报告**：`[analysis_dir]/opentunex-top-down-bottleneck_collect/result.md`
> - **场景分析融合报告**：`[analysis_dir]/opentunex-scenario-bottleneck_collect/result.md`（已是场景协调器 Phase 2 融合后的报告，非各子技能的原始输出）
>
> 场景分析融合报告已经过等价组聚合、冲突消解、依赖检查和策略过滤（按 [场景融合规则](../../opentunex-scenario-bottleneck/references/fusion-rules.md) 执行），包含 `primary_plan`、`extended_plan`、`excluded` 等结构化结论。域融合同样遵循这些融合决策，不做重新裁决。

验证两份输入报告的完整性，确保融合所需的关键字段齐全。

### 通用分析报告校验

| 校验项 | 必需 | 说明 |
|--------|------|------|
| 瓶颈ID列表 | 是 | 每个瓶颈有唯一标识 |
| 瓶颈类型 | 是 | CPU/内存/IO/网络/锁/调度等 |
| 严重度 | 是 | P0-Critical/P1-High/P2-Medium/P3-Low |
| 证据 | 是 | 具体指标值和阈值对比 |
| 影响进程 | 否 | 但强烈建议提供 |

### 场景分析融合报告校验

> 以下校验基于场景融合报告的 **主推荐方案 (primary_plan)** 和 **场景分析汇总** 模块。

| 校验项 | 必需 | 说明 |
|--------|------|------|
| 融合概览 | 是 | 输入技能数、提取建议数、等价组数、采纳/排除数 |
| 场景分析汇总表 | 是 | 每个场景的ID、状态、适用性、严重度、关键发现 |
| 主推荐方案 (primary_plan) | 是 | 融合后保留的最终调优建议集合（含建议ID、等价类、调优操作、预期收益） |
| 扩展方案 (extended_plan) | 否 | 额外的增强建议（若有） |
| 被排除项 | 是 | 各建议被排除的原因（冲突、依赖、策略过滤、场景不适用） |

### 缺失处理

如果任一报告缺失关键字段：记录缺失项，向用户说明，请求补充或确认是否继续（缺失部分标记为"未知"）。

---

## F-Phase 1.5: 通用分析建议结构化（LLM 提取）

> **背景**：通用分析子技能（io/mem/net/lock/schedule/application）输出自然语言报告和调优建议，不含结构化字段（id、equivalence_class、estimated_gain 等）。本阶段由大模型读取通用分析报告中的建议文本，按 [规则融合方案](../../../../docs/规则融合方案.md) 定义的字段格式转换为结构化建议，使其能与场景化分析的结构化结果一同参与后续融合流程。

### 输入

通用分析报告 `[analysis_dir]/opentunex-top-down-bottleneck_collect/result.md` 中的"调优建议"章节。

### 输出

一组结构化建议对象，每项包含以下字段：

| 字段 | 填充规则 |
|------|---------|
| `id` | 格式 `general_<子系统>_<序号>`，如 `general_mem_01`、`general_sched_02` |
| `suggestion` | 从报告原文中提取的具体调优操作描述，保留原命令和参数 |
| `equivalence_class` | 大模型根据建议的核心目的命名，kebab-case 格式，如 `memory-hugepage-tlb`。若无已知替代方案，填入自己的 `id` |
| `activation_requirement` | 大模型根据建议涉及的操作判定：写入 procfs/sysfs → `immediate`；需 systemctl reload → `service_reload`；需重启业务进程 → `business_restart`；需重启系统 → `system_reboot` |
| `estimated_gain` | `primary_metric` 取自通用分析瓶颈指标（如 `mem_usage`、`io_latency`、`sched_latency`）；`severity` 根据瓶颈严重度对照矩阵判定；`description` 从原文中提取或由大模型基于证据概括 |
| `conflicts` | 大模型基于 Linux 内核领域知识，识别与已知场景化建议可能冲突的操作，填入对应 `id` 列表。若不确定，留空 `[]` |
| `prerequisites` | 大模型判定是否有必须前置的操作，如先设置全局参数再启用特性 |
| `synergy_with` | 大模型根据领域知识标注协同增强的其他建议 `id` |
| `scenario_priority` | 固定为 `0`（通用分析建议不做场景加权） |
| `source` | 固定为 `llm_knowledge` |

### 数量约束

通用分析每个子技能（io/mem/net/lock/schedule/application）至多提取 **3 条** 结构化建议，总条数控制在 **15 条以内**。若有更多建议，优先保留严重度高的。

### 与融合流程的衔接

本阶段产出的结构化建议作为 F-Phase 2 交叉验证的通用分析侧输入，与场景融合报告的 `primary_plan` 建议一同参与后续的覆盖关系分析、矛盾消解、优先级排序和冲突约束识别。

> **重要**：`source=llm_knowledge` 的建议在等价组择优中排序靠后（`skill_output` 优先），但这不影响其参与交叉验证和优先级排序——仅当与 `skill_output` 建议在同一等价组时才需要排队。

---

## F-Phase 2: 交叉验证与矛盾消解

> **输入**：F-Phase 1.5 产出的通用分析结构化建议（`source=llm_knowledge`）和场景分析融合报告（primary_plan + 场景分析汇总）。
> 场景融合报告内部已完成等价组聚合、冲突消解和依赖检查（按 [场景融合规则](../../opentunex-scenario-bottleneck/references/fusion-rules.md)），域融合不做重新裁决，仅做跨域交叉验证。

### 覆盖关系分析

以通用分析瓶颈为基准，逐一与场景融合报告中的 primary_plan 建议进行覆盖关系判定：

| 关系类型 | 说明 | 示例 |
|---------|------|------|
| 场景补充 | 场景融合 primary_plan 中的建议对应通用分析未覆盖的特定领域 | 通用分析发现内存压力大，场景融合 primary_plan 含 numa_sched_paral 建议 |
| 通用覆盖 | 通用分析瓶颈的根因已被场景融合 primary_plan 对应的建议所涵盖 | 通用分析发现CPU负载高，场景融合 primary_plan 含 stealtask_steal 建议 |
| 矛盾冲突 | 通用分析结论与场景融合 primary_plan 的结论不一致 | 通用分析认为CPU负载均衡，场景融合 primary_plan 却推荐窃取任务调优 |
| 独立发现 | 通用分析瓶颈与场景融合 primary_plan 的建议分别针对不同维度 | 通用分析发现IO瓶颈，场景融合 primary_plan 含 numa_sched_paral 建议 |

### 矛盾消解规则

> 矛盾仅指通用分析结论与场景融合 primary_plan 之间不一致的情况。场景融合内部的冲突已由场景协调器处理（见 excluded 列表），域融合不再重新判决。

1. **数据优先**：以具体指标数据为准，而非定性结论
2. **场景优先**：在场景特定领域（如NUMA调度、窃取任务、动态SMT等），场景融合的结论优先级高于通用分析。场景融合已通过多子技能交叉验证，结论置信度更高
3. **互补整合**：如果两份报告从不同角度描述同一问题（覆盖关系为"通用覆盖"或"场景补充"），整合为更完整的描述，不做取舍
4. **标记存疑**：如果无法消解，标记为"待确认"并列出双方证据，由人工决策
5. **已排除项尊重**：场景融合报告 excluded 列表中的项（含冲突消解、依赖不满足、策略过滤排除的建议），域融合直接继承该排除结论，不纳入交叉验证范围

---

## F-Phase 3: 优先级排序

> 将通用分析瓶颈列表与场景融合 primary_plan 建议合并为统一的瓶颈-建议清单，按以下规则排序。
>
> **排序策略**：采用多级排序键（`scenario_priority` → `severity` → `activation_requirement` → `source`），在此基础上叠加域融合特有规则。

### 统一优先级框架

| 优先级 | 定义 | 调优紧迫度 |
|--------|------|-----------|
| P0-Critical | 资源饱和导致系统不可用或严重降质 | 立即调优 |
| P1-High | 显著性能瓶颈，有明确证据和优化方向 | 优先调优 |
| P2-Medium | 性能劣化但系统仍可用，需评估收益 | 按序调优 |
| P3-Low | 次优状态，优化收益有限 | 监控即可 |

### 优先级调整规则

以下规则用于调整合并清单中各项目的优先级，按**多级排序 → 域级修正**两步执行：

#### 步骤 1：多级排序确定基准优先级

> 与场景内融合排序策略一致，对每个项目按以下排序键确定 P0-P3 基准级别。场景 primary_plan 建议已携带完整字段，通用分析瓶颈由 LLM 按等价字段补齐。

| 排序键 | 字段 | 对基准优先级的影响 |
|--------|------|-------------------|
| 第一键 | `scenario_priority` | 数值大者优先，用于确定 P0-P3 基准。≥8 → P0 基线；5-7 → P1 基线；1-4 → P2 基线；0（含通用分析默认）→ P3 基线 |
| 第二键 | `estimated_gain.severity` | `high` → 在 scenario_priority 基线上升一级；`medium` → 维持基线；`low` → 降一级 |
| 第三键 | `activation_requirement` | `immediate`/`service_reload` → 不调整；`business_restart` → 降半级（如 P1 降为 P1/P2 边界，取低）；`system_reboot`/`hardware_change` → 降一级；`none` → 降一级（纯观察建议） |
| 第四键 | `source` | `manual`/`skill_output` → 不调整；`llm_knowledge` → 降半级（通用分析 LLM 即时生成的建议可信度较低） |

> **通用分析瓶颈的字段补齐**：通用分析建议的 `scenario_priority` 默认为 0，`activation_requirement` 由 LLM 根据建议内容判断，`source` 标记为 `llm_knowledge`。

#### 步骤 2：域融合特有修正

> 在多级排序确定的基准优先级之上，叠加以下域融合规则：

1. **通用+场景双重确认**：如果通用分析瓶颈和场景融合 primary_plan 中的建议指向同一瓶颈方向，该方向综合优先级提升一级（P3→P2，P2→P1，P1→P0）
2. **场景高收益保持**：场景融合 primary_plan 中 `estimated_gain.severity` 为 `high` 的建议，优先级不低于 P1-High
3. **通用Critical不降级**：通用分析标记为 P0-Critical 的瓶颈，即使场景融合 primary_plan 未覆盖，优先级保持不变
4. **场景已排除项**：场景融合报告 excluded 列表中的建议（含场景不适用、冲突排除、依赖不满足、策略过滤），不进入合并清单
5. **场景 extended_plan**：扩展方案中的建议纳入 P3-Low 级别，作为可选的增强项

#### 规则叠加顺序

> 先执行步骤 1 多级排序确定基准，再按步骤 2 规则 1-5 编号顺序叠加修正。规则 2 设最低优先级下限，规则 1 在此基础上提升一级。例如：
> - 场景建议 `scenario_priority=7`、`severity=high`、`activation=immediate`、`source=skill_output` → 步骤1 排序为 P0（P1 基线 + severity=high 升一级），被通用分析双重确认（规则1）→ **P0-Critical**
> - 通用分析瓶颈 `scenario_priority=0`、`severity=medium`、`activation=immediate`、`source=llm_knowledge` → 步骤1 排序为 P3（P3 基线，llm_knowledge 降半级→P3），被场景双重确认（规则1）→ **P2-Medium**
> - 场景建议 `scenario_priority=6`、`severity=high`、`activation=system_reboot`、`source=skill_output` → 步骤1 排序为 P1（P1 基线→severity=high 升一级→P0→system_reboot 降一级→P1），规则2 触发（severity=high→≥P1）→ 最终 **P1-High**

---

## F-Phase 4: 调优方向与冲突约束

> **定位**：本阶段处理跨域冲突（通用分析调优方向 vs 场景融合 primary_plan 建议）。场景内部冲突已由场景融合（fusion-rules.md）处理，域融合直接继承其 excluded 和 primary_plan 结论。

### 调优方向归类

| 瓶颈类型 | 调优方向描述 | 调优域分类 |
|---------|------------|-----------|
| CPU计算/上下文切换 | OS内核CPU调度参数优化 | 通用调优 |
| 内存压力/碎片 | OS内存管理参数优化 | 通用调优 |
| 磁盘IO | OS磁盘IO调度参数优化 | 通用调优 |
| 网络栈 | OS网络协议栈参数优化 | 通用调优 |
| 锁竞争 | OS锁与同步机制优化 | 通用调优 |
| 调度延迟 | OS调度行为参数优化 | 通用调优 |
| 应用层 | 应用配置与运行参数优化 | 通用调优 |
| numa并行感知调度适用 | numa并行感知调度特性优化 | 场景调优 |
| 窃取任务适用 | 窃取任务调度特性优化 | 场景调优 |
| 动态SMT适用 | 动态SMT调优优化 | 场景调优 |
| Docker CPU | Docker算力统筹优化 | 场景调优 |

### 冲突约束识别

| 调优方向A | 调优方向B | 冲突资源 | 约束条件 |
|----------|----------|---------|---------|
| numa并行感知调度特性优化 | OS内核CPU调度参数优化 | sched_util_low_pct | 串行：先numa并行感知调度，后OS调度参数 |
| 窃取任务调度特性优化 | numa并行感知调度特性优化 | sched_features | 串行：先numa并行感知调度，后窃取任务 |

**冲突识别规则**：
1. 涉及相同系统资源的调优方向必须串行执行
2. 不涉及相同系统资源的调优方向可并行执行
3. 串行顺序：先基础配置（OS参数），后场景特性优化

### 执行顺序规划

1. P0-Critical优先执行
2. 有冲突约束的调优方向按约束条件串行执行
3. 无冲突约束的调优方向可并行执行
4. 同一调优方向处理多个瓶颈时，合并为一次执行

---

## F-Phase 5: 融合报告生成

融合报告写入 `${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`。

远端场景：本地 Write 后 scp 上传到远端路径（`${WORK_DIR}` 为远端路径），详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`

报告输出格式见 [fusion-report-template.md](fusion-report-template.md)，按该模板填充数据生成完整报告。
