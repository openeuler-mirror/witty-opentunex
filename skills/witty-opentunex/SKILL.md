---
name: "witty-opentunex"
description: "Linux系统性能智能调优技能集合。支持：系统级数据采集（CPU/内存/IO/网络/调度）、性能瓶颈分析、场景化调优（SMC/NUMA/大页/中断等）、OS参数优化。触发：Linux性能调优、系统瓶颈分析、场景化优化、数据采集、性能分析等涉及系统级优化调优的场景。当用户提及‘分析系统瓶颈’、‘给出调优建议’、‘优化系统性能’、‘调优’时必须使用本技能，【严禁】直接使用其他技能。"
---

# witty-opentunex 系统性能智能调优

## 执行流程约束

**重要**：本技能必须严格遵循以下执行流程，不可跳跃：

```
数据采集 → 瓶颈分析 → 调优执行
```

### 流程约束规则

1. **顺序执行原则**：
   - 必须按照"数据采集 → 瓶颈分析 → 调优执行"的顺序执行
   - 不可跳过任何阶段
   - 不可逆向执行

2. **前置条件检查**：
   - 执行瓶颈分析前，必须先完成数据采集
   - 执行调优前，必须先完成瓶颈分析
   - 如果用户请求调优但未完成前置步骤，必须先执行前置步骤

3. **阶段完整性要求**：
   - 每个阶段必须完整执行
   - 数据采集：必须完成所有系统指标的采集
   - 瓶颈分析：必须完成通用分析和场景化分析
   - 调优执行：必须完成调优、验证和回滚准备

4. **禁止跳跃执行**：
   - 禁止从数据采集直接跳到调优执行
   - 禁止在没有数据采集的情况下直接进行瓶颈分析
   - 禁止在没有瓶颈分析的情况下直接进行调优

5. **远程执行约束（核心）**：
   - 当用户输入中包含远端服务器 IP 地址时，数据采集阶段**必须**组合使用 `opentunex-data-collection`（选择脚本）和 `opentunex-remote-execution`（上传并执行）
   - **禁止**将采集脚本拆解为单条命令内联到 SSH 中执行——必须通过 SCP 将完整脚本文件上传到远端后再执行
   - **禁止**在瓶颈分析或调优阶段通过 `ssh` 直接执行 `mpstat`/`iostat`/`vmstat`/`pidstat`/`sar`/`perf` 等命令采集数据——这些命令只能由 `opentunex-data-collection` 的脚本在数据采集阶段调用
   - 瓶颈分析阶段的 `opentunex-top-down-bottleneck` 技能中 Phase 2-4 的内联命令仅为**分析参考**，实际执行时必须通过 `opentunex-remote-execution` 的 SCP+SSH 机制上传对应脚本后执行
   - **`${WORK_DIR}` 远程语义（核心）**：当用户输入含远端 IP 时，`${WORK_DIR}` 是**远端服务器上**的路径（`/srv/opentunex/<YYYYMMDD_HHMMSS>/`），agent 主机本地不存在该目录。全流程（数据采集/瓶颈分析/调优执行）中所有对 `${WORK_DIR}` 的操作——mkdir/ls/cat/写契约/写报告/打包/执行脚本——都必须经 `opentunex-remote-execution` 的 ssh 机制在**远端**执行，**禁止**在 agent 本地对 `${WORK_DIR}` 做任何文件操作。具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`，各链式调用的技能与子智能体必须同样遵守
   - **模式传递**：远端/本地模式由本技能在流程开始时判定（见"技能调用顺序"章节的 `${WORK_DIR}` 初始化），并通过输入契约或子智能体任务描述传递给所有链式调用的技能与子智能体，子技能不得自行改判模式

### 数据来源约束（核心）

**禁止在瓶颈分析和调优执行阶段自行采集数据**：

- **数据采集是唯一允许生成采集数据的阶段**，由 `opentunex-data-collection` 子技能负责；其余阶段只能消费采集阶段的产出
- 进入瓶颈分析阶段后，agent 必须**直接读取**数据采集阶段产出的文件作为分析输入，**禁止**调用任何采集脚本（如 `bottleneck_data_collector.sh` / `collect_*.sh`），也**禁止**通过 `top` / `iostat` / `sar` / `vmstat` / `mpstat` / `pidstat` / `perf` 等命令临时读取系统数据
- 进入调优执行阶段后，agent 必须**直接读取**瓶颈分析阶段产出的报告作为调优输入，**禁止**回退到数据采集
- "想再确认一下数据"、"担心数据不够新"、"想再补一项指标"等动机都不是重新采集的正当理由——这些都应通过回到数据采集阶段、由 `opentunex-data-collection` 重新执行解决，而不是在当前阶段动手

**为什么这样约束**：
- 数据采集和瓶颈分析职责分离，agent 同时承担两个职责会导致分析时混入新数据，破坏时间窗口的一致性
- 子技能有自己的数据契约（`${WORK_DIR}` 路径约定），agent 自行采集会绕过契约，产生路径不一致问题
- 重新采集会重复执行耗时的脚本（典型场景 60s+），显著拉长整体流程

**如果数据缺失或不完整**：
- 必须**返回数据采集阶段**，重新调用 `opentunex-data-collection` 子技能补采
- **禁止**在瓶颈分析或调优阶段尝试自行补采
- **禁止**跳过缺失数据继续推进（除非瓶颈分析子技能明确允许）

### 产出文件约束（核心）

**三个阶段是文件驱动的串联——下游阶段的输入 = 上游阶段的产出文件。每一阶段产出文件全部就位，是进入下一阶段的硬性前置条件。**

**三个阶段的产出文件清单**：

| 阶段 | 子技能 | 必须产出的文件                | 路径                                                                                                                                                    |
|-----|-------|------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| 阶段1 - 数据采集 | `opentunex-data-collection` | 性能数据采集文件               | `${WORK_DIR}/collect`下的数据文件                                                                                                                           |
| 阶段2 - 瓶颈分析 | `opentunex-bottleneck-analysis` | (a) 通用分析报告；(b) 场景化融合报告 | (a) `${WORK_DIR}/analysis/opentunex-top-down-bottleneck_collect/result.md`；(b) `${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md` |
| 阶段3 - 调优执行 | `opentunex-performance-tuning` | 调优建议报告 + 打包            | `${WORK_DIR}/tuning/tuning-report.md` 与 `${WORK_DIR}/tuning-package_<YYYYMMDD_HHMMSS>.tar.gz`                                                         |

**阶段切换前的强制验证（不可跳过）**：

进入下一阶段前，agent 必须对上一阶段的产出文件执行存在性 + 非空校验，任一缺失即视为本阶段失败。

**远端模式（用户输入含 IP）**：`${WORK_DIR}` 是远端路径，校验命令必须经 `opentunex-remote-execution` 在远端执行——推荐将校验逻辑写成脚本后 scp 到远端执行（跨平台最稳健，避免引号转义问题）：

```bash
# 本地（agent 主机）：用 Write 工具写 validate_stage1.sh，内容为：
#   #!/bin/bash
#   WD="${1:?}"
#   for f in static_info.txt global_bottleneck.txt top_processes.txt cpu_detail_info.txt \
#            kernel_config_info.txt process_detail_info.txt container_info.txt \
#            memory_metrics_analysis.txt network_metrics_analysis.txt io_metrics_analysis.txt; do
#       test -s "$WD/collect/$f" || echo "MISSING_OR_EMPTY: $f"
#   done
#   test -s "$WD/analysis/opentunex-top-down-bottleneck_collect/result.md" || echo "MISSING_OR_EMPTY: top-down report"
#   test -s "$WD/analysis/opentunex-scenario-bottleneck_collect/result.md" || echo "MISSING_OR_EMPTY: scenario report"
#   test -s "$WD/tuning/tuning-report.md" || echo "MISSING_OR_EMPTY: tuning report"
#   ls "$WD"/tuning-package_*.tar.gz >/dev/null 2>&1 || echo "MISSING: tuning package tarball"
scp validate_stage1.sh ${user}@${ip}:/tmp/
ssh -q ${user}@${ip} "bash /tmp/validate_stage1.sh ${WORK_DIR}"
```

单条校验也可以用远端命令直接执行（bash 本地侧示例；Windows PowerShell 本地侧按 `opentunex-remote-execution` 的平台指南翻译，`\$` 改为 `` `$ ``）：

```bash
# 阶段1 → 阶段2 前：校验采集文件就位（必需 10 个文件）
ssh -q ${user}@${ip} "cd ${WORK_DIR}/collect && for f in static_info.txt global_bottleneck.txt top_processes.txt cpu_detail_info.txt kernel_config_info.txt process_detail_info.txt container_info.txt memory_metrics_analysis.txt network_metrics_analysis.txt io_metrics_analysis.txt; do test -s \$f || echo MISSING_OR_EMPTY: \$f; done"
# 条件文件（未指定 -p 或非 aarch64 时缺失属正常，仅告警）：hotspot_analysis.txt syscall_analysis.txt pmu_info.txt

# 阶段2 → 阶段3 前：校验分析报告就位
ssh -q ${user}@${ip} "test -s ${WORK_DIR}/analysis/opentunex-top-down-bottleneck_collect/result.md && test -s ${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md && echo ANALYSIS_OK || echo MISSING_OR_EMPTY"

# 阶段3 完成时：校验调优产物就位
ssh -q ${user}@${ip} "test -s ${WORK_DIR}/tuning/tuning-report.md && ls ${WORK_DIR}/tuning-package_*.tar.gz >/dev/null 2>&1 && echo TUNING_OK || echo MISSING"
```

**本地模式（无 IP）**：命令直接在 agent 主机执行（去掉 ssh 包装，其余同上）。

**校验失败的处理**：
- **禁止**跳过缺失文件继续推进下一阶段——下游会因缺少输入而失败，或基于"读到空/读到占位文件"产出错误结果
- **禁止**用占位/草稿/模板文件替代真实产出
- 必须**返回上一阶段重新执行**；若重试后仍失败，向用户报告失败原因与缺失的文件清单，由用户决策
- 校验命令必须实际运行并检查返回值，**不允许**靠"我记得文件存在"或"上一轮日志显示文件已写"等推断

**为什么这样约束**：
- 子技能之间靠文件传递数据——任何一个文件丢失/为空/路径错位，下游要么报错要么静默读到错误内容（这是最难发现的失败模式）
- 子技能自身有输出契约校验，但只能保证"自己写出了契约文件"，无法保证"上一阶段真的给我留了能读的内容"；本技能作为编排入口，需要从全流程视角把住文件串联不断裂
- 静默丢失（脚本失败但 agent 继续推进）是常见 bug 模式——必须显式断言存在性和非空

### 异常处理

- 如果用户请求跳跃执行，必须提示用户并引导执行完整流程
- 如果前置步骤未完成，必须先执行前置步骤
- 如果用户坚持跳跃执行，必须明确警告风险并记录
- 如果数据缺失或不完整，必须返回数据采集阶段重新采集，不得自行补采
- 如果上一阶段产出文件缺失或为空，必须返回上一阶段重新执行，不得静默跳过

---

## 大类技能导航

根据任务类型，选择对应的大类技能：

| 大类 | 包含能力 | 技能名称                                                                       |
|------|---------|----------------------------------------------------------------------------|
| 数据采集 | 系统环境信息采集、CPU/内存/IO/网络/调度资源指标采集、Top进程识别、基准测试执行、性能基线建立 | `opentunex-data-collection`         |
| 瓶颈分析 | 自顶向下瓶颈分析、IO/内存/网络/锁/调度专项瓶颈分析、应用层瓶颈分析、场景化分析（SMC等） | `opentunex-bottleneck-analysis` |
| 调优执行 | OS参数优化、应用级优化、场景化调优（SMC等）、优化执行+验证+回滚 | `opentunex-performance-tuning`   |

---

## 执行流程示例

### 示例1：完整流程执行

用户请求："帮我优化系统性能"

**执行流程**：
1. **数据采集阶段**：调用 `opentunex-data-collection` 技能，采集系统指标，产出采集文件（默认位于 `${WORK_DIR}/collect/`）
   - **如果是远端目标**：先调用 `opentunex-remote-execution` 建立 SSH 连接，远端 `mkdir -p ${WORK_DIR}/collect`，SCP 上传采集脚本到远端（如 `/tmp/`），再 SSH 执行脚本（`-o ${WORK_DIR}/collect`，数据落盘远端）
2. **瓶颈分析阶段**：调用 `opentunex-bottleneck-analysis` 技能，**直接读取阶段1的采集文件**进行分析，禁止重新采集。远端执行时，分析命令通过 `opentunex-remote-execution` 的 SCP+SSH 机制执行
3. **调优执行阶段**：调用 `opentunex-performance-tuning` 技能，**直接读取阶段2的分析报告**执行调优，禁止重新采集

### 示例2：用户请求跳跃执行

用户请求："直接帮我调优SMC"

**正确处理**：
```
检测到用户请求调优，但未完成前置步骤。

根据执行流程约束，必须先完成：
1. 数据采集（采集系统指标和SMC环境信息）
2. 瓶颈分析（分析SMC适用性和瓶颈）

是否开始执行完整流程？
```

### 示例3：部分流程执行

用户请求："帮我分析系统瓶颈"

**正确处理**：
```
检测到用户请求瓶颈分析。

检查前置条件：是否已完成数据采集？
- 如果已完成：直接执行瓶颈分析
- 如果未完成：先执行数据采集，再执行瓶颈分析
```

---

## 技能调用顺序

### ${WORK_DIR} 初始化（流程第一步，先于阶段1）【强制】

执行前先生成 `${WORK_DIR}` 值给全流程使用：

1. **模式判定**：用户输入中是否包含远端服务器 IP？
2. **远端模式（含 IP）**：
   - `${WORK_DIR}` = 远端服务器上的 `/srv/opentunex/<YYYYMMDD_HHMMSS>/`（当前日期时间）
   - 经 `opentunex-remote-execution` 在**远端**创建：`ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/collect ${WORK_DIR}/analysis ${WORK_DIR}/tuning"`
   - `${WORK_DIR}` **只存在于远端**。agent 主机（如 Windows）本地**禁止**创建或使用同名目录
   - 全流程所有对 `${WORK_DIR}` 的操作（mkdir/ls/cat/写契约/写报告/打包/执行脚本）都必须经 `opentunex-remote-execution` 的 ssh 机制在远端执行，具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`
3. **本地模式（无 IP）**：`${WORK_DIR}` = 当前 agent 会话的工作目录，命令直接本地执行
4. **模式传递【强制】**：判定的模式（`execution_mode`、`user`、`ip`、`${WORK_DIR}` 值）必须传递给所有链式调用的技能与子智能体（写入输入契约或子智能体任务描述）。子技能不得自行改判模式，也不得把 `${WORK_DIR}` 当成本地目录使用

### 阶段1：数据采集

**触发条件**：用户请求性能优化、数据采集、系统监控等

**调用技能**：`opentunex-data-collection`

**远程执行要求**：当分析目标为远端服务器时（用户输入含 IP），**必须**组合使用 `opentunex-remote-execution` 技能：
1. 先在远端创建输出目录：`ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/collect"`
2. 再通过 SCP 将 `opentunex-data-collection/scripts/` 下的脚本文件（`bottleneck_data_collector.sh`）上传到远端（如 `/tmp/`）
3. 再通过 SSH 在远端执行脚本，`-o` 指向远端 `${WORK_DIR}/collect`
4. **禁止**将脚本内容拆解为单条命令（mpstat/iostat/vmstat 等）直接 SSH 执行
5. `${WORK_DIR}` 是远端路径——采集数据直接落盘远端，**禁止**在 agent 本地创建 `${WORK_DIR}` 或把数据拷回本地

**产出**：系统指标数据、环境信息、性能基线

**强制要求**：该阶段执行完成后【禁止】直接分析数据采集文件，【必须】在检查产出文件正常后，直接进入**阶段2**调用`opentunex-bottleneck-analysis`技能

### 阶段2：瓶颈分析

**触发条件**：数据采集完成，用户请求瓶颈分析

**前置条件**：数据采集已完成

**禁止**：进入该阶段后禁止直接读取数据文件，**必须**直接加载`opentunex-bottleneck-analysis`技能，严格按该技能的说明执行。

**调用技能**：`opentunex-bottleneck-analysis`

**产出**：瓶颈分析报告、调优建议

**强制要求**：该阶段执行完成后【禁止】直接给出调优建议或者执行调优，【必须】在检查产出文件正常后，直接进入**阶段3**调用`opentunex-performance-tuning`技能

### 阶段3：调优执行

**触发条件**：瓶颈分析完成，用户请求调优

**前置条件**：瓶颈分析已完成

**禁止**：进入该阶段后禁止直接读取数据分析报告，**必须**直接加载`opentunex-performance-tuning`技能，严格按该技能的说明执行。

**调用技能**：`opentunex-performance-tuning`

**产出**：调优执行结果、验证报告、回滚方案

---

## 操作说明

- 始终检查前置条件，确保流程完整性
- 如果用户请求跳跃执行，必须提示并引导执行完整流程
- 每个阶段完成后，明确告知用户下一阶段
- 保持流程的严格性，确保调优的有效性和安全性

---

## 阶段3完成后总结输出模板【强制】

阶段3调优执行完成后，向用户输出的总结性内容**必须**严格遵循固定模板，禁止自由发挥、禁止增删章节、禁止改写表头。

**完整模板与硬性约束见** [references/summary-output-template.md](references/summary-output-template.md)

**模板核心要点速览**：

- **模板来源**：从阶段3产出的调优报告 `${WORK_DIR}/tuning/tuning-report.md` 中提取关键信息（报告基本信息、瓶颈与调优手段总结表、瓶颈证据/影响分析），按固定结构组织后输出
- **远端模式**：`${WORK_DIR}` 是远端路径，所有读取（`cat`、`grep`）必须经 `opentunex-remote-execution` 的 ssh 在远端执行，禁止 scp 拷回本地
- **章节固定**：3个一级章节必须全部出现（执行概要 / 核心瓶颈与调优建议 / 下一步操作），顺序不可调换
- **核心瓶颈章节子结构**：包含「2.1 瓶颈与调优手段总览」总表 + 「2.2 调优建议详情」逐瓶颈详情（每个瓶颈含 2 个固定子标题：瓶颈证据 / 影响分析）

详细字段填充规则、表格表头、失败降级文案以 references/summary-output-template.md 为准。
