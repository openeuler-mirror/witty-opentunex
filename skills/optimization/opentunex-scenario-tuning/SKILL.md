---
name: "opentunex-scenario-tuning"
description: "场景化调优协调器。基于瓶颈分析层的融合报告，按需调度场景调优技能生成中间态建议，汇总为一份完整的调优建议报告。触发条件：(1)用户请求性能调优、参数优化、配置调整、调优建议；(2)瓶颈分析完成后自动触发；(3)融合报告生成后需要生成调优建议。"
sub_agent_enabled: true
---

# opentunex-scenario-tuning — 场景化调优协调器

> **⛔ 入口门：在执行步骤 2 调度前，必须确认以下规则：**
> 
> 1. **场景调优子技能必须尝试通过子智能体工具启动**——不得在当前上下文中直接读取子技能 SKILL.md 并内联执行
> 2. **在启动子智能体之前，不得预读取融合报告全文**——仅提取调优方向列表，报告路径写入输入契约，由子智能体自行读取
> 3. **如果子智能体工具不可用或能力不足，才允许降级模式**，但必须标注 `execution_mode: "degraded"` 并记录降级原因

## 强制约束

> 本技能遵守 [调优域约束](references/constraints-tuning.md) 中定义的所有执行约束和调优执行约束。

### 数据目录约束

- **读取路径**：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`（最新的融合报告）
- **写入路径**：`${WORK_DIR}/tuning/tuning-report.md`（最终汇总报告）
- **中间态路径**：`${WORK_DIR}/tuning/intermediate/`（各调优技能的中间态建议）

### 执行模式与 `${WORK_DIR}` 语义（核心）

- **远端模式**（用户输入含远端 IP，由 `witty-opentunex` 判定并传递）：`${WORK_DIR}` 是**远端服务器上**的路径。本技能中所有对 `${WORK_DIR}` 的操作（mkdir/ls/读融合报告/读契约/写契约/写报告/复制脚本）都必须在**远端**执行——经 `opentunex-remote-execution` 的 ssh 机制，**禁止**在 agent 本地（如 Windows）对 `${WORK_DIR}` 做任何文件操作。具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`，下方命令块已标注远端/本地写法
- **本地模式**（无 IP）：`${WORK_DIR}` 为 agent 主机本地目录，命令直接本地执行
- **模式传递**：启动子智能体时，必须把 `execution_mode`、`user`、`ip`、`${WORK_DIR}` 写入输入契约并随任务描述传给子智能体；子智能体同样遵守远端语义
- 本技能生成的调优脚本与调优命令**不自动执行**（遵守 T-01/T-02，由用户确认后执行）；远端模式下脚本部署到远端 `${WORK_DIR}/tuning/...`，由用户在**远端服务器**上运行

---

## 输入约定

**重要**：调优执行层的数据来源是**瓶颈分析层**的融合分析报告。调优域入口的核心职责是从融合报告中识别调优方向，根据方向路由到对应调优技能，各技能生成中间态调优建议后，由入口汇总为一份完整的调优建议报告。

**核心输入数据**：

| 数据类别 | 必需 | 内容说明 |
|---------|------|---------|
| 融合瓶颈优先级列表 | 是 | 按P0-Critical→P3-Low排序的瓶颈清单，包含瓶颈ID、来源、瓶颈类型、严重度、证据摘要、建议调优方向、调优紧迫度 |
| 调优执行计划 | 是 | 分批次的调优方向调用计划，包含调优方向描述、对应瓶颈ID列表、预期收益、风险等级 |
| 冲突约束 | 是 | 调优方向之间的资源冲突关系和串行/并行执行策略 |
| 交叉验证结果 | 否 | 通用分析与场景分析之间的覆盖关系和矛盾消解结论，辅助理解瓶颈上下文 |
| 执行摘要 | 否 | 融合报告的总体概览，包含瓶颈总数和建议调优项数 |

**融合报告关键格式**（由瓶颈分析融合技能生成）：

| 字段 | 说明 | 调优域使用方式 |
|------|------|--------------|
| 建议调优方向 | 场景语义描述（如"numa并行感知调度特性优化"） | 作为路由键，匹配调优技能映射表 |
| 调优紧迫度 | P0-Critical/P1-High/P2-Medium/P3-Low | 决定调优建议的优先级排序 |
| 冲突资源 | 涉及相同系统资源的调优方向对 | 决定调优步骤的串行/并行策略 |
| 执行批次 | 按优先级和冲突约束划分的批次 | 指导调优建议的执行计划编排 |

---

## 调优执行流程

### 步骤 0：创建本次调优报告目录【强制】

> **⚠️ 此步骤不可跳过。未创建报告目录将导致后续调优技能的中间态建议无法写入。**

按当前日期时间创建本次调优报告目录。历史报告数据保留，不清空。

**远端模式**（`${WORK_DIR}` 是远端路径，经 ssh 在远端创建并验证）：

```bash
ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/tuning/contracts ${WORK_DIR}/tuning/intermediate"
ssh ${user}@${ip} "ls ${WORK_DIR}/tuning/"
```

**本地模式**（agent 主机即目标机）：

```bash
mkdir -p ${WORK_DIR}/tuning/{contracts,intermediate}
```

**验证**：创建后必须确认目录存在：

```bash
ls ${WORK_DIR}/tuning/
```

> **远端模式禁止**：在 agent 本地（如 Windows）`mkdir ${WORK_DIR}/...`——`${WORK_DIR}` 只存在于远端。

### 步骤 1：读取融合报告，识别调优方向并过滤

从融合报告中提取调优执行计划，识别需要执行的调优方向。**必须过滤掉不适用和不支持的方向**（遵守 [ST-05 调优方向过滤约束](references/common-constraints.md)），仅保留场景分析结论为"适用"或"建议启用"的调优方向。

| 场景分析结论 | 是否进入调优流程 |
|-------------|----------------|
| 适用 / 建议启用 | ✅ 路由到调优子技能 |
| 不适用 / 不支持 / 环境不支持 | ❌ 跳过，不路由、不生成建议、不出现在最终报告中 |
| 不需要 / 无需额外操作 / 已启用 | ❌ 跳过，不路由、不生成建议、不出现在最终报告中 |

**读取路径**：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`（远端模式经 ssh 在远端读取，禁止 scp 拷回本地：`ssh -q ${user}@${ip} "cat <该路径>"`）

**提取内容**：
1. **调优执行计划**：确定需要执行的调优方向列表及其批次安排
2. **融合瓶颈优先级列表**：获取每个调优方向对应的瓶颈ID、严重度和证据
3. **冲突约束**：获取调优方向之间的资源冲突关系和串行/并行策略

**识别逻辑**：融合报告中的"建议调优方向"字段是场景语义描述（如"numa并行感知调度特性优化"），作为路由键匹配下方调优技能映射表，确定需要调用的调优技能。

### 步骤 2：按调优方向路由到对应调优技能

根据步骤1识别的调优方向，匹配调优技能映射表，调用对应调优技能。各调优技能从瓶颈分析结果中读取所需数据，判断是否适用，生成各自的中间态调优建议。

#### 二级子智能体调度声明

| 子智能体                             | 技能名称                                         | 输入契约路径 | 约束文件 | 输出契约路径 | 中间态建议路径 |
|----------------------------------|----------------------------------------------|------------|---------|------------|--------------|
| numa-sched-tuning                | `opentunex-numa-sched-tuning`                | [report_dir]/contracts/opentunex-numa-sched-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-numa-sched-tuning-output.yaml | [report_dir]/intermediate/numa-sched-tuning.md |
| stealtask-tuning                 | `opentunex-stealtask-tuning`                 | [report_dir]/contracts/opentunex-stealtask-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-stealtask-tuning-output.yaml | [report_dir]/intermediate/stealtask-tuning.md |
| docker-coordination-burst-tuning | `opentunex-docker-coordination-burst-tuning` | [report_dir]/contracts/opentunex-docker-coordination-burst-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-docker-coordination-burst-tuning-output.yaml | [report_dir]/intermediate/docker-coordination-burst-tuning.md |
| soft-domain-tuning               | `opentunex-soft-domain-tuning`               | [report_dir]/contracts/opentunex-soft-domain-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-soft-domain-tuning-output.yaml | [report_dir]/intermediate/soft-domain-tuning.md |
| dynamic-smt-tuning               | `opentunex-dynamic-smt-tuning`               | [report_dir]/contracts/opentunex-dynamic-smt-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-dynamic-smt-tuning-output.yaml | [report_dir]/intermediate/dynamic-smt-tuning.md |
| multi-net-path-tuning            | `opentunex-multi-net-path-tuning`            | [report_dir]/contracts/opentunex-multi-net-path-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-multi-net-path-tuning-output.yaml | [report_dir]/intermediate/multi-net-path-tuning.md |
| btb-tuning                       | `opentunex-btb-tuning`                       | [report_dir]/contracts/opentunex-btb-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-btb-tuning-output.yaml | [report_dir]/intermediate/btb-tuning.md |
| copy-user-tuning                 | `opentunex-copy-user-tuning`                 | [report_dir]/contracts/opentunex-copy-user-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-copy-user-tuning-output.yaml | [report_dir]/intermediate/copy-user-tuning.md |
| hisock-tuning                    | `opentunex-hisock-tuning`                    | [report_dir]/contracts/opentunex-hisock-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-hisock-tuning-output.yaml | [report_dir]/intermediate/hisock-tuning.md |

**调度方式**：使用当前环境中可用的子智能体工具（如 sessions_spawn+sessions_yield、Task Tool、Agent Tool 等）启动上述子智能体。具体调用格式由运行时环境决定，本技能不限定。

**子智能体任务描述**（传入子智能体的指令）：
> 读取技能定义 [技能名称]，读取输入契约 [输入契约路径]，读取约束文件 [约束文件路径]，执行技能定义中的步骤，写入输出契约 [输出契约路径]，写入中间态建议 [中间态建议路径]。**执行上下文**：execution_mode=remote（或 local）；远端模式时 ${user}@${ip} 为远端连接信息，${WORK_DIR} 为远端路径，所有对 ${WORK_DIR} 的读写经 opentunex-remote-execution 在远端执行（见 references/work_dir_remote_semantics.md），禁止在 agent 本地操作 ${WORK_DIR}。

#### 降级模式（仅在子智能体工具不可用时使用）

降级模式**不是首选执行路径**，仅在子智能体工具不可用或启动失败时使用：

降级执行时必须：
- 在输出契约中标注 `execution_mode: "degraded"` 并记录降级原因
- 逐个读取子技能的 SKILL.md，每次只加载一个，执行完毕后释放上下文再加载下一个
- 仍须遵守所有约束和契约输出要求

#### 场景化调优

调优方向到子技能的完整映射关系参见 [场景调优映射表](references/SKILL_MAPPING.md)。所有子技能遵守 [场景调优子技能共享约束](references/common-constraints.md)，依据 [中间态建议模板](references/intermediate-report-template.md) 生成中间态建议。

### 错误处理与容错机制

| 异常场景 | 处理策略 |
|---------|---------|
| 融合报告缺失 | 终止流程，提示用户先完成瓶颈分析 |
| 无匹配的调优方向 | 输出"无适用调优方向"结论，终止流程 |
| 单个子技能执行失败 | 标记为"执行失败"，记录错误原因，继续执行其他子技能 |
| 子技能执行超时（默认 300s） | 标记为"超时"，继续执行其他子技能 |
| 子技能输出格式异常 | 标记为"结果解析失败"，保留原始输出供人工检查 |
| 所有子技能均失败 | 输出"所有调优建议生成均失败"结论，列出各子技能失败原因 |
| 所有子技能均不适用 | 在报告中明确说明，建议检查瓶颈分析结果 |

### 子技能执行状态

每个子技能执行后应记录以下状态：

| 状态 | 说明 |
|------|------|
| `success` | 执行成功，中间态建议已生成 |
| `failed` | 执行失败，记录错误原因 |
| `timeout` | 执行超时（超过 300 秒） |
| `not_applicable` | 调优方向不适用当前系统 |
| `parse_error` | 执行完成但结果无法解析 |

### 步骤 3：汇总各调优建议，生成一份完整的调优建议报告

**核心**：各调优技能生成的调优建议是中间态数据，最终必须汇总为**一份完整的调优建议报告**。

汇总逻辑：
1. 收集各调优技能的中间态调优建议（从 `${WORK_DIR}/tuning/intermediate/` 读取；**远端模式**经 ssh 读取：`ssh -q ${user}@${ip} "cat ${WORK_DIR}/tuning/intermediate/<skill-name>.md"`，禁止 scp 拷回本地）
2. 合并总结表，去重并统一编号
3. 合并调优建议，按融合报告的优先级排序
4. 标注各子技能的执行状态（成功/失败/超时/不适用）

### 异常处理

| 场景 | 处理 |
|------|------|
| 所有调优方向均不适用 | 在报告中明确说明，建议检查瓶颈分析结果 |
| 部分子技能失败 | 在报告中标注失败状态和原因，不影响成功结果的展示 |
| 所有子技能均失败 | 输出"所有调优建议生成均失败"结论，列出各子技能失败原因 |
| 子技能超时 | 标注超时状态，建议单独重新执行该子技能 |

### 步骤 4：生成调优脚本【强制】

> **⛔ 步骤 4 是强制步骤，不可跳过。** 任何"primary_plan"或"extended_plan"适用方向都必须生成调优脚本目录（包含 `tuning.sh` 入口脚本和从子技能复制的**基础脚本**）。**`sub_skills_skipped` / `not_applicable` 方向不得生成脚本**。
>
> **职责归属**：本步骤由 `opentunex-scenario-tuning` 协调器统一负责。子技能不再负责创建脚本目录——子技能只输出中间态建议与输出契约，不写脚本。**子技能输出契约中"未生成调优脚本目录"属于正常设计**，不是异常。

为每个适用调优方向（`primary_plan` / `extended_plan`）生成对应的调优脚本，按调优技能名称建立独立文件夹。

#### 调优脚本组成

调优脚本由两部分组合而成：

1. **基础脚本**：从对应子技能 `opentunex-<调优技能名称>/scripts/` 目录直接复制的脚本文件，包含具体的调优操作逻辑（检查、备份、应用、回滚等）
2. **入口脚本 `tuning.sh`**：由大模型根据瓶颈分析结果动态生成的入口脚本，包含针对当前瓶颈的动态参数，负责调用基础脚本执行调优

#### 脚本目录结构

每个调优类型按调优技能名称建立独立文件夹，包含入口脚本和基础脚本：

```
<调优技能名称>/
├── tuning.sh              # 入口脚本（动态生成，含动态参数）
├── <基础脚本1>            # 从对应子技能 opentunex-<调优技能名称>/scripts/ 目录复制
└── <基础脚本2>            # 从对应子技能 opentunex-<调优技能名称>/scripts/ 目录复制
```

示例：

```
opentunex-numa-sched-tuning/
├── tuning.sh              # 动态生成的入口脚本，含 sched_util_low_pct 等参数
└── numa_sched_tune.sh     # 从 opentunex-numa-sched-tuning/scripts/ 复制的基础脚本

opentunex-stealtask-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── stealtask_tune.sh      # 从 opentunex-stealtask-tuning/scripts/ 复制的基础脚本

opentunex-docker-coordination-burst-tuning/
├── tuning.sh              # 动态生成的入口脚本，含 ratio、容器ID等参数
└── docker_coordination_burst.sh  # 从 opentunex-docker-coordination-burst-tuning/scripts/ 复制的基础脚本
```

#### 入口脚本 tuning.sh 说明

入口脚本 `tuning.sh` 是动态生成的，其特点：

- **动态参数**：包含大模型根据瓶颈分析结果确定的调优参数（如 sched_util_low_pct=100、ratio=20、容器ID列表等）
- **调用基础脚本**：通过调用同目录下的基础脚本执行实际的调优操作
- **统一接口**：支持 `check`、`apply`、`rollback` 等标准操作

入口脚本模板：

```bash
#!/bin/bash
# [调优方向] 入口脚本
# 由大模型根据瓶颈分析动态生成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析结果填充）
# [参数定义，如：UTIL_LOW_PCT=100]

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

#### 生成流程

> **远端模式**：脚本目录是远端 `${WORK_DIR}/tuning/<调优技能名称>/`——先在 agent 本地用 Write 工具生成 `tuning.sh`，与对应子技能 `opentunex-<调优技能名称>/scripts/` 下的基础脚本一并 `scp` 上传到远端路径，并在远端 `chmod +x`；**禁止**在 agent 本地创建 `${WORK_DIR}/tuning/...` 目录树。脚本不自动执行，由用户在远端服务器上运行（遵守 T-01/T-02）。

1. **遍历适用方向**：读取各子技能输出契约的 `output.summary.plan` 字段，筛选出 `primary_plan` 和 `extended_plan` 的调优方向作为脚本生成清单。`sub_skills_skipped` 列表中的方向不生成脚本
2. **建立脚本源映射**：对每个适用方向，记录其对应的子技能名称、入口脚本名（`<skill-name>/`）、基础脚本名（从子技能 `scripts/` 目录枚举）
3. **创建子目录**：按调优技能名称在报告目录下创建子目录（远端模式经 ssh：`ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/tuning/<调优技能名称>"`）
4. **复制基础脚本**：从对应子技能 `opentunex-<调优技能名称>/scripts/` 目录复制基础脚本到子目录（远端模式：`scp opentunex-<调优技能名称>/scripts/<基础脚本> ${user}@${ip}:${WORK_DIR}/tuning/<调优技能名称>/`）
5. **动态生成入口脚本**：根据瓶颈分析结果动态生成入口脚本 `tuning.sh`，填入动态参数（远端模式：本地 Write 后 scp 上传到远端子目录）
6. **赋予脚本执行权限**：在 agent 本地创建的 `tuning.sh` 必须在 Write 时设置 `chmod +x`；远端复制的脚本与本地 scp 上传的脚本在远端执行权限（远端模式：`ssh ${user}@${ip} "chmod +x ${WORK_DIR}/tuning/<调优技能名称>/*.sh"`）

#### 步骤 4 完成校验【不可跳过】

完成脚本生成后，必须对每个适用方向做以下校验：

| # | 校验项 | 通过条件 |
|---|--------|---------|
| S-1 | 子目录存在 | `${WORK_DIR}/tuning/<调优技能名称>/` 目录存在 |
| S-2 | 入口脚本存在 | `${WORK_DIR}/tuning/<调优技能名称>/tuning.sh` 文件存在且可执行 |
| S-3 | 基础脚本存在 | `${WORK_DIR}/tuning/<调优技能名称>/<基础脚本>` 文件存在 |
| S-4 | 脚本路径一致 | `tuning-report.md` 中"调优脚本"列的相对路径（如 `./btb-tuning/tuning.sh`）能在目录下找到对应文件 |

**校验失败处理**：任一适用方向的 S-1 / S-2 / S-3 不通过，必须修复后重新校验；不得进入步骤 5。

### 步骤 5：输出调优建议报告

依据 [最终汇总报告模板](references/tuning-report-template.md) 生成一份完整的调优建议报告。

#### 报告输出约定

- 最终汇总报告：`${WORK_DIR}/tuning/tuning-report.md`
- 调优脚本：`${WORK_DIR}/tuning/<调优技能名称>/`

**远端模式**：以上均为远端路径。报告文件本地 Write 后 scp 上传到远端。

#### 目录结构

```
${WORK_DIR}/tuning/
├── tuning-report.md                       # 最终汇总的调优建议报告
├── intermediate/                          # 各调优技能的中间态建议
│   ├── os-performance-optimization.md
│   ├── application-optimization.md
│   ├── numa-sched-tuning.md
│   ├── stealtask-tuning.md
│   └── docker-coordination-burst-tuning.md
├── numa-sched-tuning/                     # 调优脚本
│   ├── tuning.sh                          # 入口脚本（动态生成）
│   └── numa_sched_tune.sh                 # 基础脚本（复制）
├── stealtask-tuning/
│   ├── tuning.sh
│   └── stealtask_tune.sh
├── docker-coordination-burst-tuning/
│   ├── tuning.sh
│   └── docker_coordination_burst.sh
├── btb-tuning/                               # BIOS 手工操作（无系统修改）
│   ├── tuning.sh
│   └── btb_tune.sh                          # 只读检查工具
├── copy-user-tuning/                         # 内核补丁应用 + 重编（无系统修改）
│   ├── tuning.sh
│   └── copy_user_tune.sh                    # 只读检查工具
└── hisock-tuning/                            # 编译 + eBPF 加载
    ├── tuning.sh
    └── hisock_tune.sh                       # 含 compile/apply/unload（用户主动执行）
```

## 调优建议报告模板

- **最终汇总报告**：调优域入口依据 [最终汇总报告模板](references/tuning-report-template.md) 生成
- **中间态调优建议**：各调优技能依据 [中间态建议模板](references/intermediate-report-template.md) 生成


---

## 契约输出

输出契约格式参见 [contract-spec.md](references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-scenario-tuning"
input:
  report_dir: "${WORK_DIR}/tuning/"
  fusion_report: "${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"
  work_dir: "${WORK_DIR}/"
execution_context:
  execution_mode: "remote" | "local"
  user: "<远端用户名，默认 root>"
  ip: "<远端服务器 IP>"
output:
  intermediate_path: "${WORK_DIR}/tuning/intermediate/"
constraints_acknowledged: [T-01~T-10, ST-01~ST-05]
```
