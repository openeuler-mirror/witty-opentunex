---
name: "opentunex-numa-sched-tuning"
description: "numa并行感知调度调优建议。基于瓶颈分析结果，生成启用PARAL特性并设置sched_util_low_pct参数的调优建议报告，减少跨NUMA访问延迟（仅aarch64）。**必须使用此技能**：当瓶颈分析显示NUMA内存不均衡、跨NUMA访问率高、NUMA节点间负载差异大、需要启用PARAL特性时。触发关键词：NUMA、PARAL、sched_util_low_pct、跨NUMA访问、内存不均衡、aarch64架构调度优化、numa并行感知调度。"
---

# NUMA 调度并行调优建议

启用numa并行感知调度特性（PARAL），让线程在同NUMA节点内调度，减少跨NUMA访问延迟。

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含NUMA相关分析结论的 `result.md` 文件
- **查找命令示例**：
```bash
# 远端模式: ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name \"result.md\" ..." 在远端执行；本地模式直接执行
CONCLUSION_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "NUMA\|numa\|PARAL" {} \; | head -1)
```

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/intermediate/` 与 `${WORK_DIR}/tuning/contracts/`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/numa-sched-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/numa-sched-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行**调优命令（遵守 T-01/T-02）：`bash scripts/numa_sched_tune.sh ...` 与 `echo X > /sys/...` 等命令出现在生成的脚本/报告中，由**用户确认后在远端服务器上执行**；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| 瓶颈分析结果数据 | 是 | 包含NUMA相关的环境检查、指标数据和适用性评估结论 |

**前置校验**：如果适用性评估结论为"不适用"或"收益有限"，不应执行调优。

如果用户未提供评估结论，应先引导用户完成numa并行感知调度适用性评估。

---

## 调优参数说明

### sched_util_low_pct

| 项目 | 说明 |
|------|------|
| 参数含义 | 调度器低利用率阈值百分比，控制调度器何时认为CPU利用率较低 |
| 取值范围 | 0-100 |
| 默认值 | 100（推荐） |
| 调优建议 | 设置为100可让调度器更积极地跨CPU调度，配合PARAL特性使用 |
| 适用场景 | NUMA内存不均衡、跨NUMA访问率高 |
| 注意事项 | 仅aarch64架构有效；修改可能影响调度器行为 |

> **⚠️ 参数约束**：当前脚本 `numa_sched_tune.sh` 将 sched_util_low_pct 固定为 100，不支持动态参数传入。如需其他值，需手动修改脚本。

### PARAL 特性

| 项目 | 说明 |
|------|------|
| 特性含义 | numa并行感知调度特性，让线程在同NUMA节点内调度 |
| 启用方式 | 向 sched_features 写入 "PARAL" |
| 禁用方式 | 向 sched_features 写入 "NO_PARAL" |
| 适用架构 | 仅 aarch64 |
| 预期效果 | 减少跨NUMA访问延迟，提升内存带宽利用率 |

---

## 技能调用方法

### 基础脚本调用

本技能依赖 `scripts/numa_sched_tune.sh` 脚本完成调优操作。脚本支持以下操作：

| 操作 | 命令 | 说明 |
|------|------|------|
| 环境检查 | `bash scripts/numa_sched_tune.sh check` | 检查sched_features和sched_util_low_pct文件是否存在且可写 |
| 状态备份 | `bash scripts/numa_sched_tune.sh backup` | 备份当前PARAL状态和sched_util_low_pct值 |
| 应用调优 | `bash scripts/numa_sched_tune.sh apply` | 启用PARAL + 设置sched_util_low_pct=100 |
| 查看状态 | `bash scripts/numa_sched_tune.sh status` | 查看当前PARAL状态和sched_util_low_pct值 |
| 回滚 | `bash scripts/numa_sched_tune.sh rollback` | 恢复最近一次备份的状态 |

> **⚠️ 说明**：调优报告中的"调优步骤"展示独立命令，目的是让用户了解具体做了什么操作、修改了哪些文件。实际调优时用户可使用入口脚本 `tuning.sh`（由用户确认后自行执行），脚本会自动完成环境检查、状态备份、调优执行、验证和回滚，并自适应 sched_features 路径。Agent 不得自动执行调优操作。

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/numa-sched-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── numa_sched_tune.sh     # 基础脚本（从本技能 scripts/ 复制）
```

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# numa并行感知调度调优入口脚本
# 由调优技能根据瓶颈分析动态生成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 参数说明：sched_util_low_pct 固定为100，当前不支持动态参数
PARAL_ENABLE=true

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/numa_sched_tune.sh" check
        ;;
    apply)
        bash "${SCRIPT_DIR}/numa_sched_tune.sh" apply
        ;;
    status)
        bash "${SCRIPT_DIR}/numa_sched_tune.sh" status
        ;;
    rollback)
        bash "${SCRIPT_DIR}/numa_sched_tune.sh" rollback
        ;;
    *)
        echo "用法: $0 {check|apply|status|rollback}"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./numa-sched-tuning/tuning.sh` （相对于调优报告目录）

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从协调器传入的融合报告数据中，查找与 NUMA 调度并行相关的瓶颈分析结论。

**需要提取的数据项**：

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| PARAL 特性支持 | 搜索 "PARAL" 关键词：存在 → 支持；不存在 → 不支持 | 不支持 |
| PARAL 当前状态 | 搜索 "PARAL" 和 "NO_PARAL"：包含 "PARAL" 且不包含 "NO_PARAL" → 已启用；否则 → 未启用 | 未启用 |
| sched_util_low_pct 原始值 | 搜索 "sched_util_low_pct" 后的数值 | 无法获取 |
| NUMA 节点数 | 搜索 "NUMA" 相关描述中的节点数量 | 1 |
| 适用性评估结论 | 搜索 "NUMA" 或 "numa" 相关的适用性评估结论 | 不适用 |

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- CONCLUSION=不适用 → 终止调优
- PARAL_SUPPORT=不支持 → 终止调优
- PARAL_STATUS=已启用 → 终止调优

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| PARAL特性支持 | 支持/不支持 |
| PARAL当前状态 | 已启用/未启用 |
| sched_util_low_pct原始值 | X |

---

### Phase 2: 生成中间态调优建议

依据 [中间态建议模板](../../references/intermediate-report-template.md) 生成报告，按以下要求填充各字段：

#### 2.1 瓶颈点列表填充

从分析结果中提取以下信息填充表格：
- **瓶颈点**：根据NUMA分析结论填写，如"NUMA内存不均衡 / 跨NUMA访问率高"
- **类别**：固定为"调度"
- **严重程度**：根据分析结果中的严重度填写
- **影响描述**：总结跨NUMA访问对性能的影响
- **调优手段**：简短描述，如"启用PARAL特性"
- **调优步骤**：精简操作步骤，如"1.启用PARAL特性 2.设置sched_util_low_pct=100"
- **调优脚本**：填写 `./numa-sched-tuning/tuning.sh`

#### 2.2 调优建议详情填充

**瓶颈证据**：从分析结果中提取NUMA相关的指标数据，如：
- 跨NUMA访问比例
- NUMA节点间内存分配情况
- PARAL特性支持状态

**影响分析**：说明跨NUMA访问对业务的影响，如响应时间、吞吐量等

**调优手段**：与瓶颈点列表中的调优手段一致

**调优步骤**：展示独立命令，让用户了解具体操作：
```bash
# 启用PARAL特性
echo PARAL > /sys/kernel/debug/sched/features
# 设置sched_util_low_pct为100
echo 100 > /proc/sys/kernel/sched_util_low_pct
```

**回滚方法**：展示对应的回滚命令：
```bash
# 禁用PARAL特性
echo NO_PARAL > /sys/kernel/debug/sched/features
# 恢复sched_util_low_pct原始值
echo [原始值] > /proc/sys/kernel/sched_util_low_pct
```

**调优脚本**：填写 `./numa-sched-tuning/tuning.sh apply`

**验证方法**：提供验证命令，确认调优是否生效

---

### Phase 3: 报告输出

将生成的中间态调优建议保存至：（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）
```
${WORK_DIR}/tuning/intermediate/numa-sched-tuning.md
```

**说明**：本技能**仅产出中间态建议**——`${WORK_DIR}/tuning/numa-sched-tuning/` 目录由协调器 `opentunex-scenario-tuning` 在步骤 4 创建（基础脚本从本技能 `scripts/` 复制 + `tuning.sh` 由协调器动态生成）。本技能不创建脚本目录。

**注意**：本文件是中间态数据，最终将由调优域入口汇总为一份完整的调优建议报告。

---

## 产出

| 产出项 | 说明 |
|--------|------|
| 中间态调优建议 | 依据中间态模板生成的结构化报告，写入 `${WORK_DIR}/tuning/intermediate/numa-sched-tuning.md` |
| 调优脚本目录 | 由协调器在步骤 4 创建（`${WORK_DIR}/tuning/numa-sched-tuning/`） |
| 预期收益 | 跨NUMA访问比例降低30%-50%，内存访问延迟降低15%-30% |
| 风险提示 | 仅适用于aarch64架构；sched_util_low_pct修改可能影响调度器行为 |
| 回滚方案 | 由协调器生成的 `./numa-sched-tuning/tuning.sh rollback` 恢复原状态 |

---

## 冲突约束

> **⚠️ 以下冲突约束由调优域入口统一处理，本技能无需处理。**

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|---------|
| numa并行感知调度特性优化 | 窃取任务调度特性优化 | sched_features | 串行：先numa并行感知调度，后窃取任务 |
| numa并行感知调度特性优化 | OS内核CPU调度参数优化 | sched_util_low_pct | 串行：先numa并行感知调度，后OS调度参数 |


---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-numa-sched-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
