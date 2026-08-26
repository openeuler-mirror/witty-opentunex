# 场景分析子技能共享约束

所有 `opentunex-scenario-bottleneck` 下的子技能必须遵守以下共享约束。

## SB-01 执行约束

> **⚠️ 每次触发本技能都必须重新从头执行完整分析流程，不得引用历史数据或之前的回答。**
> - 即使系统状态未变化，也必须重新执行所有分析步骤
> - 不得跳过任何分析阶段，不得复用历史分析结果
> - 每次执行都必须创建新的时间戳批次目录，保存完整的分析过程数据
> - 这是强制性要求，无例外情况

## SB-02 数据目录约束

> **⚠️ 所有分析产出必须落入用户指定的工作目录 `WORK_DIR` 内，不得散落到 `/tmp` 或其他系统路径。**

数据来源支持两种模式：

| 模式 | 数据目录 | 说明 |
|------|--------|------|
| 预采集模式 | `${DATA_DIR}` 或 `${WORK_DIR}/` | 用户已预先采集数据，直接指定路径 |
| 按需采集模式 | `${WORK_DIR}/` | 协调器自动调用数据采集技能，数据写入 `${WORK_DIR}/` |

分析数据文件通过协调器传入，位于数据目录下。分析产物按以下路径写入：

| 路径 | 用途 |
|------|------|
| `${DATA_DIR}` 或 `${WORK_DIR}/` | 原始采集数据（预采集或按需采集产出，只读） |
| `${WORK_DIR}/analysis/<skill_name>_collect/result.md` | 场景分析技能写入分析结果 |

## SB-03 数据采集约束

子技能**禁止自行采集数据**，必须基于数据目录中已采集的数据进行分析。

数据采集由协调器统一负责：
- **预采集模式**：协调器直接使用用户指定的已有数据
- **按需采集模式**：协调器在调度子技能前，调用 `opentunex-data-collection` 技能完成数据采集
- **补充采集**：当子技能报告数据缺失且可补充采集时，由协调器触发补充采集，子技能不自行采集

## SB-04 数据缺失处理

当数据目录中缺少必要数据文件时：

1. **可补充采集的维度**：子技能在结果中标注 `DATA_MISSING: <缺失文件列表>`，由协调器判断是否触发补充采集
2. **不可补充采集的维度**（如需要特定时间段的历史数据）：子技能标注数据缺失并说明影响，继续执行可完成的分析部分
3. **关键数据全部缺失**：子技能输出"数据不足，无法完成分析"结论

> 协调器在按需采集模式下，应优先使用一键采集（`server_data_collector.sh`）获取完整数据，减少后续补充采集的需要。

## SB-05 目录创建

目录由瓶颈分析域入口统一创建，本技能无需单独创建：
```bash
mkdir -p ${WORK_DIR}/analysis/<skill_name>_collect
```

## SB-06 环境不支持但场景匹配时的建议输出

> **⚠️ 当检查发现某项场景化优化手段在当前系统中因内核或软件不支持而无法直接实施（内核不支持特性、内核配置未开启、模块不可用、debugfs 不可写等环境约束），但分析表明该特性所针对的瓶颈场景确实存在（其他推荐条件符合）时，子技能不得直接判定为"不适用"并将其过滤，而应将该调优方向作为推荐建议输出，标注环境支持缺口，由调用者自行评估是否手动引入该特性（如升级内核、更换内核版本、加载模块、修改 BIOS 配置、挂载 debugfs 等）。**

### 设计意图

子技能的职责是**识别瓶颈场景并给出调优建议**，而非替调用者决定"当前环境能否实施"。即使当前内核/软件不具备实施条件，只要瓶颈场景真实存在，仍应输出推荐调优建议，让调用者（人工或上层决策器）自行评估：
- 是否值得通过升级内核、更换内核版本、加载缺失模块等方式**手动引入该特性**
- 是否在未来的环境变更中纳入该调优方向
- 当前是否暂缓实施、仅作为观察项

### 前置检查分类

子技能的"环境约束前置检查"须区分两类条件：

| 类别 | 含义 | 处理方式 |
|------|------|---------|
| **硬性不适用** | 特性已启用（无需重复操作）、特性在当前拓扑下无意义（如单 NUMA 节点的跨节点调度）、无收益对象（无目标进程）等 | 命中即输出"不适用"，`applicability = "not_applicable"`，短路终止 |
| **环境不支持**（可恢复） | 内核不支持特性、内核配置未开启、模块不可用、debugfs 未挂载或不可写、硬件能力缺失等 | **不短路**：记录支持缺口，继续评估场景/收益条件，场景匹配时输出推荐建议供调用者评估 |

### 输出规则

当"环境不支持"类条件命中时，**继续执行场景/收益条件评估**，按下表输出：

| 场景条件评估结果 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|---------------|---------|--------------|-----------|------------------------|
| 场景条件满足（存在该特性可缓解的瓶颈） | 收益有限（环境不支持但场景匹配） | `limited_benefit` | 必须显式标注环境支持缺口与引入路径，格式：`[当前系统不支持 X（原因），需手动引入 Y 后方可实施：{升级内核 / 加载模块 / 挂载 debugfs / 修改 BIOS 等}] <原建议操作>` | `low` |
| 场景条件不满足（无瓶颈或收益对象缺失） | 不适用 | `not_applicable` | 填写不适用原因 | `low` |

### 一致性要求

- 同一子技能内，"环境不支持"判断与"场景条件"判断相互独立，前者不得提前终止后者
- `limited_benefit` 的建议正常参与融合流程（不被 excluded 过滤），但 severity 为 `low`，确保不抢占当前可实施的高优先级建议
- 叙述性报告中"综合结论"必须同时体现环境支持缺口、场景匹配状态与手动引入路径，如"收益有限 — 内核不支持 PARAL 特性，但跨 NUMA 远程访问占比 18% > 5%，存在 NUMA 瓶颈，建议升级至支持 PARAL 的内核手动引入该特性后实施"
- suggestion 中必须给出可操作的引入路径（升级内核版本 / 加载模块 / 挂载 debugfs / BIOS 设置等），不得仅写"不支持"而省略引入方式

## 子技能名称与目录映射

| 子技能 | 技能名称 | collect 目录 |
|--------|--------|-------------|
| Docker算力统筹分析 | `opentunex-docker-coordination-burst-analysis` | `opentunex-docker-coordination-burst-analysis_collect` |
| 动态SMT分析 | `opentunex-dynamic-smt-analysis` | `opentunex-dynamic-smt-analysis_collect` |
| numa并行感知调度分析 | `opentunex-numa-sched-analysis` | `opentunex-numa-sched-analysis_collect` |
| 窃取任务调度分析 | `opentunex-stealtask-analysis` | `opentunex-stealtask-analysis_collect` |
| 网卡多路径瓶颈分析 | `opentunex-multi-net-path-analysis` | `opentunex-multi-net-path-analysis_collect` |
| 分域调度分析 | `opentunex-soft-domain-analysis` | `opentunex-soft-domain-analysis_collect` |
| BTB 适用性分析 | `opentunex-btb-analysis` | `opentunex-btb-analysis_collect` |
| copy_from_user 拷贝优化分析 | `opentunex-copy-user-analysis` | `opentunex-copy-user-analysis_collect` |
| hisock 网络加速分析 | `opentunex-hisock-analysis` | `opentunex-hisock-analysis_collect` |