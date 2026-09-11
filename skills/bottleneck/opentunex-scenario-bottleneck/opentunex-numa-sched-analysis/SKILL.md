---
name: "opentunex-numa-sched-analysis"
description: "numa并行感知调度分析。检查PARAL特性支持、分析NUMA拓扑与跨节点访问率（PMU HHA优先，vmstat/numastat降级），结合线程创建频率评估调优适用性。触发:NUMA内存不均衡、跨NUMA访问率高、线程高并发创建、NUMA瓶颈。"
---

# NUMA 调度并行分析

分析系统NUMA拓扑和内存访问特征，检查内核sched_features中PARAL特性支持状态，评估numa并行感知调度调优的适用性。

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-numa-sched-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 与 `${DATA_DIR}` 都是**远端服务器上**的路径：
  - `scripts/preanalysis.sh` 远端执行**必须加载并遵循 `opentunex-remote-execution` skill 的执行方式**（`ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-numa-sched-analysis/"` → scp 上传脚本到远端 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-numa-sched-analysis/` → 远端执行`ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-numa-sched-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-numa-sched-analysis_collect"`；session 超时按该 skill 扩展为 1200 秒；**禁止**读取脚本内容后自行合成命令代替执行。**禁止**在 agent 本地执行该脚本或读写本地 `${DATA_DIR}` 路径
  - 读取 `${DATA_DIR}` 下的数据文件：`ssh -q ${user}@${ip} "cat <文件>"` 流回上下文分析，**禁止** scp 拷回本地
  - 写入 result.md / 输出契约到 `${WORK_DIR}/analysis/...`：**直接在远端机器上产出**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <文件>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - "调优步骤推荐"中的命令仅作为报告建议输出，本技能**不执行**；用户确认后由用户在远端服务器上执行
- **本地模式**（execution_mode=local）：脚本与命令直接本地执行。
- 具体写法见 `opentunex-remote-execution` skill（含其 `references/work_dir_remote_semantics.md`）。

---

## 执行流程

本技能的完整执行流程如下，**必须按顺序完成所有步骤，不得在中间步骤终止**：

| 步骤 | 操作 | 产出 |
|------|------|------|
| 1 | 执行 `scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-numa-sched-analysis_collect`（本地模式直接执行；远端模式按 `opentunex-remote-execution` skill 执行方式先 `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-numa-sched-analysis/"`，然后 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-numa-sched-analysis/` 再 `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-numa-sched-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-numa-sched-analysis_collect"`，`preanalysis.json` 生成在**远端**输出目录，禁止在 agent 本地执行） | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-numa-sched-analysis_collect/preanalysis.json"` 流回上下文；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径） | 决策变量值 |
| 3 | 按"决策逻辑"章节依次执行环境与特性前置检查 → 路径 A PMU HHA 判定（或降级到路径 B vmstat/numastat 判定） | 分析结论 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-numa-sched-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。**远端模式**下 `preanalysis.json` 生成在远端服务器输出目录 `${DATA_DIR}/opentunex-numa-sched-analysis_collect/`，步骤 2 必须经 ssh `cat` 流回上下文读取，**禁止**在 agent 本地目录查找或读取该文件。步骤 1 为强制预解析模式：仅当步骤 1 执行失败或 `preanalysis.json` 不存在时才允许进入"数据读取"章节的降级路径，**禁止**跳过步骤 1 直接读取原始数据文件。**预解析模式下禁止直接读取 `scripts/preanalysis.sh` 脚本内容**（不得 Read/cat 脚本文件本身）：本地模式直接执行脚本；远端模式按 `opentunex-remote-execution` skill 执行方式 scp 上传脚本文件到远端后 ssh 执行，无需阅读脚本实现。

---

## 数据读取

> **强制顺序**：本技能提供 `scripts/preanalysis.sh` 脚本对原始采集数据进行预处理。**必须先执行脚本生成 `preanalysis.json` 并基于 JSON 进行分析，禁止跳过预解析模式直接逐文件读取原始数据**。仅当预解析模式失败（脚本执行失败或 `preanalysis.json` 不存在，远端模式经 ssh 在远端确认）后，才允许进入下方降级路径。

NUMA 远程访问瓶颈的判定采用**双路径**：优先使用 PMU HHA 数据（精确），降级使用 vmstat/numastat 数据（近似）。

### 预解析模式（强制首选）：预分析 JSON

1. 执行预处理脚本生成 JSON（远端模式：按 `opentunex-remote-execution` skill 执行方式 scp 上传后 `ssh -q -tt` 在远端执行，见"输入约定"执行模式章节）：
   ```bash
   bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-numa-sched-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-numa-sched-analysis_collect/preanalysis.json`（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-numa-sched-analysis_collect/preanalysis.json"` 流回上下文读取；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径、禁止 scp 拷回本地）

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `hha_available` | HHA_DEVICE | `true` → 可用（路径 A 有效）；`false` → 不可用（降级到路径 B） |
| `ops_per_sec` | OPS_PER_SEC | 整数，HHA 每秒内存操作量 |
| `remote_ratio` | REMOTE_RATIO | 数值百分比，如 `8.50` |
| `thread_create_per_second` | THREAD_CREATE_PER_SECOND | 整数，每秒线程创建数（个/秒）；`null` 或缺失 → 视为无数据，跳过 N4 判定。 |
| `pmu_path_applicable` | PMU_PATH | `true` → 使用 PMU 路径 A；`false` → 降级到路径 B（由脚本预计算） |
| `numa_hit` | NUMA_HIT | 整数，降级路径中 numastat 本地命中数 |
| `numa_miss` | NUMA_MISS | 整数，降级路径中 numastat 远程访问数 |
| `numa_foreign` | NUMA_FOREIGN | 整数，降级路径中 numastat 外部访问数 |
| `remote_access_ratio` | REMOTE_ACCESS_RATIO | 已计算的 `NUMA_MISS / (NUMA_HIT + NUMA_MISS) × 100`（由脚本预计算） |
| `numa_nodes` | NUMA_NODES | 整数，NUMA 节点数量 |
| `paral_support` | PARAL_SUPPORT | `"支持"` / `"不支持"` |
| `paral_enabled` | PARAL_ENABLED | `"已启用"` / `"未启用"` |
| `sched_util_low_pct` | SCHED_UTIL_LOW_PCT | 整数或 `null`（`null` 表示无法获取） |

> **注意**：`pmu_path_applicable` 和 `remote_access_ratio` 已由脚本预计算，可直接用于决策逻辑判定路径 A/B 和 NB2-NB4 阈值比较，无需再手动计算。

### 降级路径：逐文件读取（仅当预解析模式失败后）

> 以下为逐文件读取原始采集数据的解析规则。**仅当预解析模式已执行且确认失败后才可使用**，禁止跳过预解析模式直接进入本路径。仅在以下情况使用：
> - `preanalysis.json` 文件不存在（远端模式：经 `ssh ${user}@${ip} "test -f ${DATA_DIR}/opentunex-numa-sched-analysis_collect/preanalysis.json"` 在远端判断，禁止在 agent 本地查找）
> - 脚本 `preanalysis.sh` 执行失败
>
> **⚠️ 大文件警告**：采集数据文件可能非常大，**禁止**直接 `cat`/Read 整个文件。必须按下方每个指标的提取方法（grep 关键字 / sed 定位节）**定向搜索**目标内容，只读取命中的片段；远端模式经 ssh 在远端执行 grep，只把命中片段流回上下文，禁止把整个文件拉回 agent 本地。

#### 路径 A：PMU HHA 数据（优先，从 `${DATA_DIR}/pmu_info.txt` 读取）

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| HHA_DEVICE | 搜索 "HHA 设备检测" 节中是否有 `/sys/devices/hha*` 路径；搜索 "未检测到 HHA 设备" → 不可用 | 不可用 |
| OPS_PER_SEC | 搜索 `ops_per_sec=` 后的整数，位于 "速率与远程访问占比" 节 | 0 |
| REMOTE_RATIO | 搜索 `remote_ratio=` 后的百分比（如 `8.50%`），取数值部分，位于同一节 | 0 |

**阈值（与参考实现对齐）**：

| 参数 | 默认值 | 含义 |
|------|--------|------|
| OPS_THRESHOLD | 2,000,000 | HHA 每秒内存操作量门槛（次/秒） |
| REMOTE_THRESHOLD | 5% | 远程内存访问占比门槛 |

#### 路径 B：vmstat/numastat 数据（降级，从 `${DATA_DIR}/memory_metrics_analysis.txt` 读取）

当 PMU 数据不可用（无 HHA 设备或 `pmu_info.txt` 中无有效 `ops_per_sec`）时使用此路径。

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| NUMA_HIT | 搜索 `=== NUMA Statistics` 节中 `numa_hit` 行的数字（格式：`numa_hit 123456`） | 0 |
| NUMA_MISS | 同上节中 `numa_miss` 行的数字 | 0 |
| NUMA_FOREIGN | 同上节中 `numa_foreign` 行的数字 | 0 |

计算：`REMOTE_ACCESS_RATIO = NUMA_MISS / (NUMA_HIT + NUMA_MISS) × 100`

**降级路径阈值**（精度低于 PMU，使用更保守的阈值）：

| 参数 | 默认值 | 含义 |
|------|--------|------|
| VMSTAT_REMOTE_HIGH | 30% | vmstat 远端访问率高阈值 |
| VMSTAT_REMOTE_LOW | 10% | vmstat 远端访问率低阈值 |

#### 从 `${DATA_DIR}/static_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| NUMA_NODES | 搜索 `--- NUMA Topology ---` 节中 `node X cpus:` 出现次数；若无，搜索 `NUMA node` 出现次数 | 1 |

#### 从 `${DATA_DIR}/kernel_config_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| PARAL_SUPPORT | 搜索 `=== 调度特性 ===` 节中的 `PARAL` 关键字：出现 `PARAL: present` → 支持且已启用；出现 `PARAL: NOT present` → 需进一步检查 sched_features 原文是否含 `NO_PARAL`（含则支持但未启用，不含则不支持） | 不支持 |
| PARAL_ENABLED | 当 PARAL 存在时：`PARAL: present` → 已启用；sched_features 原文含 `PARAL` 且**不含** `NO_PARAL` → 已启用 | 未启用 |
| SCHED_UTIL_LOW_PCT | 在 `=== 特殊调度参数 ===` 节中，`sched_util_ratio` 行后紧跟一行：若为纯数字（如 `100`）→ 取该值；若为 `sched_util_low_pct: not exist` → 无法获取 | 无法获取 |

---

## 决策逻辑

按以下优先级依次判断，命中即输出。

> **前置检查分类（遵守 SB-06）**：下表中 N1/N3/N4 为"硬性不适用"，命中即短路终止；N2 为"环境不支持"，**不短路**，仅记录支持缺口 `PARAL_UNSUPPORTED_GAP`，继续进入路径 A/B 评估场景瓶颈是否存在。场景条件满足但环境不支持时，按"环境支持缺口处理"输出 `limited_benefit` 建议。

### 环境与特性前置检查

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| N1 | NUMA_NODES ≤ 1 | 不适用 | 单NUMA节点无需调度并行 |
| N2 | PARAL_SUPPORT = 不支持 | 记录 `PARAL_UNSUPPORTED_GAP=true`，**继续评估**（不短路） | 内核不支持 PARAL 特性（环境支持缺口，场景匹配时仍作为建议输出，见 SB-06） |
| N3 | PARAL_ENABLED = 已启用 | 不适用 | PARAL 特性已启用 |
| N4 | THREAD_CREATE_PER_SECOND <= 200 | 不适用 | 线程创建频率太低，无收益 |

### 路径 A：PMU HHA 判定（精确，命中即采用）

> **优先路径**：若使用 `preanalysis.json`，直接检查 `pmu_path_applicable` 字段：`true` → 进入 NA2-Na4 判定；`false` → 降级到路径 B。
>
> **降级路径**：若未使用 `preanalysis.json`，按 NA1 判断 `pmu_info.txt` 是否有效。

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| NA1 | `pmu_info.txt` 无有效数据 | 降级到路径 B | — |
| NA2 | OPS_PER_SEC ≤ OPS_THRESHOLD (200万) | 收益有限 | HHA 每秒操作量 {X} < 2,000,000，未达到远程瓶颈判定门槛 |
| NA3 | OPS_PER_SEC > OPS_THRESHOLD 且 REMOTE_RATIO ≤ REMOTE_THRESHOLD (5%) | 收益有限 | 操作速率达标 ({X}/s) 但远程访问占比 {X}% ≤ 5%，NUMA 本地性良好 |
| NA4 | OPS_PER_SEC > OPS_THRESHOLD 且 REMOTE_RATIO > REMOTE_THRESHOLD (5%) | **适用** | 操作速率 {X}/s > 2,000,000 且远程访问占比 {X}% > 5%，NUMA 内存访问存在瓶颈 |

### 路径 B：vmstat/numastat 判定（降级，仅当路径 A 不可用时使用）

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| NB1 | 无法获取 NUMA_HIT/NUMA_MISS 数据 | 收益有限 | 无法获取远端访问率数据 |
| NB2 | REMOTE_ACCESS_RATIO < VMSTAT_REMOTE_LOW (10%) | 收益有限 | vmstat 远端访问率 {X}% < 10%，NUMA 状态良好（注意：此为降级路径，精度低于 PMU） |
| NB3 | REMOTE_ACCESS_RATIO ≥ VMSTAT_REMOTE_HIGH (30%) | **适用** | vmstat 远端访问率 {X}% ≥ 30%，NUMA 瓶颈明显 |
| NB4 | REMOTE_ACCESS_RATIO ≥ VMSTAT_REMOTE_LOW (10%) | **适用** | vmstat 远端访问率 {X}% ≥ 10%，存在 NUMA 瓶颈（降级路径，建议在支持 HHA 的机型上使用 PMU 精确判定） |

### 环境支持缺口处理（SB-06）

> 当路径 A/B 评估结论为"**适用**"（NA4/NB3/NB4 命中，存在 NUMA 远程访问瓶颈），但前置检查 N2 已记录 `PARAL_UNSUPPORTED_GAP=true`（内核不支持 PARAL 特性）时，**不得直接判为"不适用"**，改按下表输出：

| 条件 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|------|---------|--------------|-----------|------------------------|
| 场景匹配（NA4/NB3/NB4 命中）且 `PARAL_UNSUPPORTED_GAP=true` | 收益有限（环境不支持但场景匹配） | `limited_benefit` | `[当前内核不支持 PARAL 特性，需升级至支持 PARAL 的内核后方可实施] 向 sched_features 写入 PARAL 启用 NUMA 并行感知调度，并设置 sched_util_low_pct=100` | `low` |

**综合结论示例**：`收益有限 — 内核不支持 PARAL 特性，但跨 NUMA 远程访问占比 {X}% > 5% 存在 NUMA 瓶颈，建议升级内核后实施`

### 预期收益（仅当结论为"适用"时填充）

| 结论来源 | 预期收益 |
|---------|---------|
| NA3（PMU 精确判定）  | 跨NUMA访问比例降低30%-50%，内存访问延迟降低15%-30% |
| NB3（vmstat 严重） | 跨NUMA访问比例降低30%-50%，内存访问延迟降低15%-30% |
| NB4（vmstat 存在） | 跨NUMA访问比例降低15%-30%，内存访问延迟降低10%-20% |

---

## 调优步骤推荐

> 以下调优步骤仅在分析结论为"适用"时适用。结论为"不适用"或"收益有限"时不执行调优。
>
> **执行位置说明**：本技能只输出建议，**不执行**调优命令（遵守 T-01/T-02）。远端模式下这些命令的目标机器是远端服务器——用户确认后由用户（或后续调优域技能生成的 tuning.sh）在**远端服务器**上执行；agent 不通过 ssh 代执行调优命令。

### 调优参数

| 参数 | 路径 | 建议值 | 说明 |
|------|------|--------|------|
| PARAL | `/sys/kernel/debug/sched/features` | `PARAL` | NUMA 并行感知调度，让线程在同 NUMA 节点内调度 |
| sched_util_low_pct | `/proc/sys/kernel/sched_util_low_pct` | 100 | 调度器低利用率阈值，配合 PARAL 使用 |

> 仅 aarch64 架构有效。先设置 sched_util_low_pct，再启用 PARAL。

### 使能命令

```bash
# 使用调优脚本（推荐）
bash scripts/numa_sched_tune.sh check    # 环境检查
bash scripts/numa_sched_tune.sh apply    # 启用 PARAL + sched_util_low_pct=100

# 或手动执行
echo 100 > /proc/sys/kernel/sched_util_low_pct
echo PARAL > /sys/kernel/debug/sched/features
```

### 验证命令

```bash
cat /proc/sys/kernel/sched_util_low_pct
grep -E 'PARAL|NO_PARAL' /sys/kernel/debug/sched/features
```

### 回滚命令

```bash
bash scripts/numa_sched_tune.sh rollback
# 或手动: echo NO_PARAL > /sys/kernel/debug/sched/features; 恢复 sched_util_low_pct 原始值
```

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| sched_features | 窃取任务 (STEAL) | 先 PARAL 后 STEAL |
| sched_util_low_pct | OS 内核 CPU 调度参数 | 先 NUMA 调度后 OS 调度参数 |
| sched_features | 分域调度 (SOFT_DOMAIN) | 先 PARAL 后 SOFT_DOMAIN（可叠加） |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-numa-sched-analysis_collect/result.md`（远端模式：**直接在远端机器上产出该文件**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、禁止在 agent 本地创建 `${WORK_DIR}` 目录），格式如下：

```markdown
# numa并行感知调度分析结果

## 1. 环境检查

| 检查项 | 结果 |
|--------|------|
| NUMA_NODES | {N} |
| PARAL_SUPPORT | {支持/不支持} |
| PARAL_STATUS | {已启用/未启用} |

## 2. 关键指标

| 指标 | 值 | 来源 |
|------|-----|------|
| OPS_PER_SEC | {值 或 "N/A（无HHA设备）"} | PMU HHA |
| REMOTE_RATIO | {X}% | {PMU HHA / vmstat 降级} |
| THREAD_CREATE_PER_SECOND | {X} 个/s 或 "无数据" | {线程采样/差分} |
| SCHED_UTIL_LOW_PCT | {值 或 无法获取} | /proc/sys/kernel |

## 3. 适用性评估

| 评估维度 | 结果 | 证据 |
|---------|------|------|
| NUMA拓扑 | ✅/❌ | {N}个NUMA节点 |
| PARAL特性支持 | ✅/❌ | PARAL: {present/NOT present/不支持} |
| PARAL当前状态 | {已启用/未启用} | — |
| 操作速率门槛 | ✅/❌ | {ops值}/s vs 2,000,000 |
| 远端访问占比 | ✅/❌ | {X}% vs {阈值}% |
| 线程创建频率 | ✅/❌ | {X} 个/s vs 200 个/s |

**综合结论**: {适用/不适用/收益有限} — {原因}

**判定路径**: {PMU HHA 精确判定 / vmstat 降级判定}

**预期收益**: {量化收益}

**调优前提**: 仅适用于 aarch64 架构

**回滚参考**: SCHED_UTIL_LOW_PCT_ORIG={原始值}（如有）

## 4. 调优步骤推荐

> 仅在结论为"适用"时适用。

### 调优参数

| 参数 | 建议值 |
|------|--------|
| sched_util_low_pct | 100 |
| PARAL | 启用 |

### 使能命令

```bash
bash scripts/numa_sched_tune.sh apply
```

### 验证

```bash
cat /proc/sys/kernel/sched_util_low_pct
grep PARAL /sys/kernel/debug/sched/features
```

### 回滚

```bash
bash scripts/numa_sched_tune.sh rollback
```
```

## 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "numa_sched_paral",
  "suggestion": "向 sched_features 写入 PARAL 启用 NUMA 并行感知调度，并设置 sched_util_low_pct=100",
  "equivalence_class": "numa_sched_paral",
  "activation_requirement": "immediate",
  "estimated_gain": {
    "primary_metric": "numa_remote_ratio",
    "severity": "high",
    "description": "跨NUMA远程访问比例降低30%-50%，内存访问延迟降低15%-30%"
  },
  "conflicts": [],
  "prerequisites": [],
  "synergy_with": [],
  "scenario_priority": 7,
  "source": "skill_output",
  "cross_skill_relations": {}
}
```

> **字段填充说明**：
> - `applicability`：分析结论为"适用"→ `"applicable"`；"收益有限"→ `"limited_benefit"`；"不适用"→ `"not_applicable"`。映射标准见 [统一映射表](../references/result-template.md#零子技能结论--结构化数据映射统一标准)
> - `estimated_gain.severity`：使用评估矩阵判定（瓶颈严重程度 × 建议匹配效能）→ `high` / `medium` / `low`
> - 若 applicability 为 `"not_applicable"`：`estimated_gain.severity` 设为 `"low"`，`suggestion` 填写不适用/收益有限的原因描述
> - 若 applicability 为 `"limited_benefit"`：`estimated_gain.severity` 设为 `"low"`，正常参与融合流程
> - **环境不支持但场景匹配（SB-06）**：当 `PARAL_UNSUPPORTED_GAP=true` 且 NA4/NB3/NB4 命中时，`applicability` 设为 `"limited_benefit"`，`suggestion` 须以前缀 `[当前内核不支持 PARAL 特性，需升级至支持 PARAL 的内核后方可实施] ` 标注支持缺口
> - activation_requirement 字段保持当前模板中预设的值，无需修改。

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-numa-sched-analysis"
input:
  analysis_dir: "[actual analysis_dir]"
  data_dir: "[actual data_dir]"
  collect_dir: "[actual collect_dir]"
output:
  analysis_report_path: "[actual analysis_report_path]"
constraints_acknowledged: [SB-01~SB-07]
