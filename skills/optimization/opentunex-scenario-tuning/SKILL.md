---
name: "opentunex-scenario-tuning"
description: "场景化调优协调器。基于瓶颈分析层的融合报告，按需调度场景调优指南生成中间态建议，汇总为一份完整的调优建议报告。触发条件：(1)用户请求性能调优、参数优化、配置调整、调优建议；(2)瓶颈分析完成后自动触发；(3)融合报告生成后需要生成调优建议。"
sub_agent_enabled: true
---

# opentunex-scenario-tuning — 场景化调优协调器

> **⛔ 入口门：在执行步骤 2 前，必须确认以下规则：**
> 
> 1. **按调优方向依次读取对应的调优参考指南（tuning-guide.md）**——各指南位于 `references/<调优方向>/` 目录下
> 2. **不得预读取融合报告全文**——仅提取调优方向列表，报告路径写入输入契约，按指南指引逐步读取所需数据
> 3. **每个调优方向独立执行**——遵循各指南的 Phase 1（前提检查）→ Phase 2（生成建议）→ Phase 3（报告输出）流程

## 强制约束

> 本技能遵守 [调优域约束](references/constraints-tuning.md) 中定义的所有执行约束和调优执行约束。

### 数据目录约束

- **读取路径**：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`（最新的融合报告）
- **写入路径**：`${WORK_DIR}/tuning/tuning-report.md`（最终汇总报告）
- **中间态路径**：`${WORK_DIR}/tuning/intermediate/`（各调优方向的中间态建议）

---

## 输入约定

**重要**：调优执行层的数据来源是**瓶颈分析层**的融合分析报告。调优域入口的核心职责是从融合报告中识别调优方向，根据方向路由到对应调优指南，按指南流程生成中间态调优建议后，由入口汇总为一份完整的调优建议报告。

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
| 建议调优方向 | 场景语义描述（如"numa并行感知调度特性优化"） | 作为路由键，匹配调优指南映射表 |
| 调优紧迫度 | P0-Critical/P1-High/P2-Medium/P3-Low | 决定调优建议的优先级排序 |
| 冲突资源 | 涉及相同系统资源的调优方向对 | 决定调优步骤的串行/并行策略 |
| 执行批次 | 按优先级和冲突约束划分的批次 | 指导调优建议的执行计划编排 |

---

## 调优执行流程

### 步骤 0：创建本次调优报告目录【强制】

> **⚠️ 此步骤不可跳过。未创建报告目录将导致后续调优方向的中间态建议无法写入。**

按当前日期时间创建本次调优报告目录。历史报告数据保留，不清空。

```bash
mkdir -p ${WORK_DIR}/tuning/{contracts,intermediate}
```

**验证**：创建后必须确认目录存在：

```bash
ls ${WORK_DIR}/tuning/
```

### 步骤 1：读取融合报告，识别调优方向并过滤

从融合报告中提取调优执行计划，识别需要执行的调优方向。**必须过滤掉不适用和不支持的方向**（遵守 [ST-05 调优方向过滤约束](references/common-constraints.md)），仅保留场景分析结论为"适用"或"建议启用"的调优方向。

| 场景分析结论 | 是否进入调优流程 |
|-------------|----------------|
| 适用 / 建议启用 | ✅ 路由到对应调优指南 |
| 不适用 / 不支持 / 环境不支持 | ❌ 跳过，不路由、不生成建议、不出现在最终报告中 |
| 不需要 / 无需额外操作 / 已启用 | ❌ 跳过，不路由、不生成建议、不出现在最终报告中 |

**读取路径**：`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`

**提取内容**：
1. **调优执行计划**：确定需要执行的调优方向列表及其批次安排
2. **融合瓶颈优先级列表**：获取每个调优方向对应的瓶颈ID、严重度和证据
3. **冲突约束**：获取调优方向之间的资源冲突关系和串行/并行策略

**识别逻辑**：融合报告中的"建议调优方向"字段是场景语义描述（如"numa并行感知调度特性优化"），作为路由键匹配下方调优指南映射表，确定需要读取的调优指南。

### 步骤 2：按调优方向读取对应调优指南

根据步骤1识别的调优方向，匹配调优指南映射表，读取对应调优指南（`tuning-guide.md`），严格遵循指南中的 Phase 1（调优前提检查）→ Phase 2（生成中间态调优建议）→ Phase 3（报告输出）流程生成中间态调优建议。

#### 调优指南映射表

| 调优方向 | 指南路径 | 输入契约路径 | 约束文件 | 输出契约路径 | 中间态建议路径 |
|---------|---------|------------|---------|------------|--------------|
| numa并行感知调度特性优化 | `references/numa-sched-tuning/tuning-guide.md` | [report_dir]/contracts/opentunex-numa-sched-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-numa-sched-tuning-output.yaml | [report_dir]/intermediate/numa-sched-tuning.md |
| 窃取任务调度特性优化 | `references/stealtask-tuning/tuning-guide.md` | [report_dir]/contracts/opentunex-stealtask-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-stealtask-tuning-output.yaml | [report_dir]/intermediate/stealtask-tuning.md |
| Docker算力统筹优化 | `references/docker-coordination-burst-tuning/tuning-guide.md` | [report_dir]/contracts/opentunex-docker-coordination-burst-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-docker-coordination-burst-tuning-output.yaml | [report_dir]/intermediate/docker-coordination-burst-tuning.md |
| 分域调度特性优化 | `references/soft-domain-tuning/tuning-guide.md` | [report_dir]/contracts/opentunex-soft-domain-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-soft-domain-tuning-output.yaml | [report_dir]/intermediate/soft-domain-tuning.md |
| 动态 SMT 调优 | `references/dynamic-smt-tuning/tuning-guide.md` | [report_dir]/contracts/opentunex-dynamic-smt-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-dynamic-smt-tuning-output.yaml | [report_dir]/intermediate/dynamic-smt-tuning.md |
| 网卡多路径调优 | `references/multi-net-path-tuning/tuning-guide.md` | [report_dir]/contracts/opentunex-multi-net-path-tuning-input.yaml | references/constraints-tuning.md + references/common-constraints.md | [report_dir]/contracts/opentunex-multi-net-path-tuning-output.yaml | [report_dir]/intermediate/multi-net-path-tuning.md |

**执行方式**：按调优方向依次读取对应的 `tuning-guide.md`，每个调优方向独立执行：

1. **读取指南**：加载对应 `references/<调优方向>/tuning-guide.md`
2. **Phase 1 - 调优前提检查**：按指南 Step 1.1 从融合报告中提取数据，执行校验逻辑
3. **Phase 2 - 生成中间态调优建议**：按指南模板生成结构化建议，写入中间态路径
4. **Phase 3 - 报告输出**：按指南指定路径写入中间态建议

**执行顺序**：按冲突约束表决定串行/并行策略。涉及相同资源（如 sched_features）的调优方向必须串行执行。

#### 场景化调优

调优方向到指南的完整映射关系参见 [场景调优映射表](references/SKILL_MAPPING.md)。所有调优指南遵守 [场景调优子技能共享约束](references/common-constraints.md)，依据 [中间态建议模板](references/intermediate-report-template.md) 生成中间态建议。

### 错误处理与容错机制

| 异常场景 | 处理策略 |
|---------|---------|
| 融合报告缺失 | 终止流程，提示用户先完成瓶颈分析 |
| 无匹配的调优方向 | 输出"无适用调优方向"结论，终止流程 |
| 单个调优方向执行失败 | 标记为"执行失败"，记录错误原因，继续执行其他调优方向 |
| 调优方向执行超时（默认 300s） | 标记为"超时"，继续执行其他调优方向 |
| 调优方向输出格式异常 | 标记为"结果解析失败"，保留原始输出供人工检查 |
| 所有调优方向均失败 | 输出"所有调优建议生成均失败"结论，列出各方向失败原因 |
| 所有调优方向均不适用 | 在报告中明确说明，建议检查瓶颈分析结果 |

### 调优方向执行状态

每个调优方向执行后应记录以下状态：

| 状态 | 说明 |
|------|------|
| `success` | 执行成功，中间态建议已生成 |
| `failed` | 执行失败，记录错误原因 |
| `timeout` | 执行超时（超过 300 秒） |
| `not_applicable` | 调优方向不适用当前系统 |
| `parse_error` | 执行完成但结果无法解析 |

### 步骤 3：汇总各调优建议，生成一份完整的调优建议报告

**核心**：各调优指南生成的调优建议是中间态数据，最终必须汇总为**一份完整的调优建议报告**。

汇总逻辑：
1. 收集各调优方向的中间态调优建议（从 `${WORK_DIR}/tuning/intermediate/` 读取）
2. 合并总结表，去重并统一编号
3. 合并调优建议，按融合报告的优先级排序
4. 标注各调优方向的执行状态（成功/失败/超时/不适用）

### 异常处理

| 场景 | 处理 |
|------|------|
| 所有调优方向均不适用 | 在报告中明确说明，建议检查瓶颈分析结果 |
| 部分调优方向失败 | 在报告中标注失败状态和原因，不影响成功结果的展示 |
| 所有调优方向均失败 | 输出"所有调优建议生成均失败"结论，列出各方向失败原因 |
| 调优方向超时 | 标注超时状态，建议单独重新执行该调优方向 |

### 步骤 4：生成调优脚本

为每个调优方向生成对应的调优脚本，按调优方向名称建立独立文件夹。

#### 调优脚本组成

调优脚本由两部分组合而成：

1. **基础脚本**：从 `scripts/` 目录对应子目录复制的脚本文件，包含具体的调优操作逻辑（检查、备份、应用、回滚等）
2. **入口脚本 `tuning.sh`**：由大模型根据瓶颈分析结果动态生成的入口脚本，包含针对当前瓶颈的动态参数，负责调用基础脚本执行调优

#### 脚本目录结构

基础脚本存放于 `skills/optimization/opentunex-scenario-tuning/scripts/` 下，按调优方向建立独立文件夹：

```
scripts/
├── docker-coordination-burst-tuning/
│   └── docker_coordination_burst.sh
├── dynamic-smt-tuning/
│   └── dynamic_smt_tune.sh
├── multi-net-path-tuning/
│   └── multi_net_path_tune.sh
├── numa-sched-tuning/
│   └── numa_sched_tune.sh
├── soft-domain-tuning/
│   └── soft_domain_tune.sh
└── stealtask-tuning/
    └── stealtask_tune.sh
```

生成调优脚本包时，每个调优方向在报告目录下建立独立文件夹：

```
<调优方向名称>/
├── tuning.sh              # 入口脚本（动态生成，含动态参数）
└── <基础脚本>             # 从 scripts/ 目录复制
```

示例：

```
numa-sched-tuning/
├── tuning.sh              # 动态生成的入口脚本，含 sched_util_low_pct 等参数
└── numa_sched_tune.sh     # 从 scripts/numa-sched-tuning/ 复制的基础脚本

stealtask-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── stealtask_tune.sh      # 从 scripts/stealtask-tuning/ 复制的基础脚本

docker-coordination-burst-tuning/
├── tuning.sh              # 动态生成的入口脚本，含 ratio、容器ID等参数
└── docker_coordination_burst.sh  # 从 scripts/docker-coordination-burst-tuning/ 复制的基础脚本
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

1. 按调优方向名称在报告目录下创建子目录
2. 从 `scripts/` 对应子目录复制基础脚本到报告目录子目录
3. 根据瓶颈分析结果动态生成入口脚本 `tuning.sh`，填入动态参数
4. 赋予脚本执行权限

### 步骤 5：输出调优建议报告与打包

依据 [最终汇总报告模板](references/tuning-report-template.md) 生成一份完整的调优建议报告，并将报告与调优脚本打包为压缩包。

#### 报告输出约定

- 最终汇总报告：`${WORK_DIR}/tuning/tuning-report.md`
- 调优脚本：`${WORK_DIR}/tuning/<调优方向名称>/`
- 压缩包：`${WORK_DIR}/tuning-package_<YYYYMMDD_HHMMSS>.tar.gz`

#### 目录结构

```
${WORK_DIR}/tuning/
├── tuning-report.md                       # 最终汇总的调优建议报告
├── intermediate/                          # 各调优方向的中间态建议
│   ├── numa-sched-tuning.md
│   ├── stealtask-tuning.md
│   ├── docker-coordination-burst-tuning.md
│   ├── soft-domain-tuning.md
│   ├── dynamic-smt-tuning.md
│   └── multi-net-path-tuning.md
├── numa-sched-tuning/                     # 调优脚本
│   ├── tuning.sh                          # 入口脚本（动态生成）
│   └── numa_sched_tune.sh                 # 基础脚本（复制自 scripts/）
├── stealtask-tuning/
│   ├── tuning.sh
│   └── stealtask_tune.sh
├── docker-coordination-burst-tuning/
│   ├── tuning.sh
│   └── docker_coordination_burst.sh
├── soft-domain-tuning/
│   ├── tuning.sh
│   └── soft_domain_tune.sh
├── dynamic-smt-tuning/
│   ├── tuning.sh
│   └── dynamic_smt_tune.sh
└── multi-net-path-tuning/
    ├── tuning.sh
    └── multi_net_path_tune.sh
${WORK_DIR}/tuning-package_20260511_143022.tar.gz      # 压缩包
```

#### 打包流程

1. 创建批次目录 `${WORK_DIR}/tuning/`
2. 生成调优报告 `tuning-report.md`
3. 按调优方向名称创建子目录，从 `scripts/` 复制基础脚本，生成入口脚本 `tuning.sh`
4. 将整个调优目录打包为 `tuning-package_<timestamp>.tar.gz`

#### 压缩包内容

最终输出为一个按时间戳命名的压缩包，包含调优报告和所有调优脚本：

```
tuning-package_<YYYYMMDD_HHMMSS>.tar.gz
├── tuning-report.md                           # 调优建议报告
├── numa-sched-tuning/                         # 按调优类型划分
│   ├── tuning.sh                              # 入口脚本（动态生成）
│   └── numa_sched_tune.sh                     # 基础脚本（复制）
├── stealtask-tuning/
│   ├── tuning.sh
│   └── stealtask_tune.sh
├── docker-coordination-burst-tuning/
│   ├── tuning.sh
│   └── docker_coordination_burst.sh
├── soft-domain-tuning/
│   ├── tuning.sh
│   └── soft_domain_tune.sh
├── dynamic-smt-tuning/
│   ├── tuning.sh
│   └── dynamic_smt_tune.sh
└── multi-net-path-tuning/
    ├── tuning.sh
    └── multi_net_path_tune.sh
```

## 调优建议报告模板

- **最终汇总报告**：调优域入口依据 [最终汇总报告模板](references/tuning-report-template.md) 生成
- **中间态调优建议**：各调优方向依据 [中间态建议模板](references/intermediate-report-template.md) 生成


---

## 契约输出

输出契约格式参见 [contract-spec.md](references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-scenario-tuning"
input:
  report_dir: "${WORK_DIR}/tuning/<report_timestamp>"
  fusion_report: "${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md"
  work_dir: "${WORK_DIR}/"
output:
  intermediate_path: "${WORK_DIR}/tuning/<report_timestamp>/intermediate/"
constraints_acknowledged: [T-01~T-10, ST-01~ST-05]
```