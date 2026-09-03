---
name: "opentunex-dynamic-smt-analysis"
description: "动态SMT适用性分析。分析CPU使用率与SMT超线程状态，评估是否需要启用动态SMT调优。当涉及超线程干扰、CPU利用率低、SMT超线程优化、dynamic_smt_tune、功耗优化、低负载场景优化时，必须使用本技能。"
---

# 动态 SMT 调优分析

分析系统 CPU 负载与 SMT 状态，评估是否需要启用动态 SMT 调优（`dynamic_smt_tune`）。

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-dynamic-smt-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 与 `${DATA_DIR}` 都是**远端服务器上**的路径：
  - `scripts/preanalysis.sh` 远端执行**必须加载并遵循 `opentunex-remote-execution` skill 的执行方式**（`ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-dynamic-smt-analysis/"` → scp 上传脚本到远端 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-dynamic-smt-analysis/` → 远端执行`ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-dynamic-smt-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect"`；session 超时按该 skill 扩展为 1200 秒；**禁止**读取脚本内容后自行合成命令代替执行。**禁止**在 agent 本地执行该脚本或读写本地 `${DATA_DIR}` 路径
  - 读取 `${DATA_DIR}` 下的数据文件：`ssh -q ${user}@${ip} "cat <文件>"` 流回上下文分析，**禁止** scp 拷回本地
  - 写入 result.md / 输出契约到 `${WORK_DIR}/analysis/...`：**直接在远端机器上产出**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <文件>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - 本技能输出的调优/使能命令（echo > /sys/...、tune 脚本调用等）仅作为报告建议，**不执行**；用户确认后由用户在远端服务器上执行
- **本地模式**（execution_mode=local）：脚本与命令直接本地执行。
- 具体写法见 `opentunex-remote-execution` skill（含其 `references/work_dir_remote_semantics.md`）。

---

## 执行流程

本技能的完整执行流程如下，**必须按顺序完成所有步骤，不得在中间步骤终止**：

| 步骤 | 操作 | 产出 |
|------|------|------|
| 1 | 执行 `scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect`（本地模式直接执行；远端模式按 `opentunex-remote-execution` skill 执行方式先 `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-dynamic-smt-analysis/"`，然后 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-dynamic-smt-analysis/` 再 `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-dynamic-smt-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect"`，`preanalysis.json` 生成在**远端**输出目录，禁止在 agent 本地执行） | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect/preanalysis.json"` 流回上下文；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径） | 决策变量值 |
| 3 | 按"决策逻辑"章节执行判定 | 分析结论 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-dynamic-smt-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。**远端模式**下 `preanalysis.json` 生成在远端服务器输出目录 `${DATA_DIR}/opentunex-dynamic-smt-analysis_collect/`，步骤 2 必须经 ssh `cat` 流回上下文读取，**禁止**在 agent 本地目录查找或读取该文件。步骤 1 为强制预解析模式：仅当步骤 1 执行失败或 `preanalysis.json` 不存在时才允许进入"数据读取"章节的降级路径，**禁止**跳过步骤 1 直接读取原始数据文件。**预解析模式下禁止直接读取 `scripts/preanalysis.sh` 脚本内容**（不得 Read/cat 脚本文件本身）：本地模式直接执行脚本；远端模式按 `opentunex-remote-execution` skill 执行方式 scp 上传脚本文件到远端后 ssh 执行，无需阅读脚本实现。

---

## 数据读取

> **强制顺序**：本技能提供 `scripts/preanalysis.sh` 脚本对原始采集数据进行预处理。**必须先执行脚本生成 `preanalysis.json` 并基于 JSON 进行分析，禁止跳过预解析模式直接逐文件读取原始数据**。仅当预解析模式失败（脚本执行失败或 `preanalysis.json` 不存在，远端模式经 ssh 在远端确认）后，才允许进入下方降级路径。

### 预解析模式（强制首选）：预分析 JSON

1. 执行预处理脚本生成 JSON（远端模式：按 `opentunex-remote-execution` skill 执行方式 scp 上传后 `ssh -q -tt` 在远端执行，见"输入约定"执行模式章节）：
   ```bash
   bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-dynamic-smt-analysis_collect/preanalysis.json`（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect/preanalysis.json"` 流回上下文读取；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径、禁止 scp 拷回本地）

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `cpu_usage` | CPU_USAGE | 数值百分比，如 `65.30`（由脚本基于 /proc/stat 多采样预计算） |
| `smt_active` | SMT_ACTIVE | `"已启用"` / `"未启用"` / `"未知"` |
| `sched_support` | SCHED_SUPPORT | `"支持"` / `"不支持"` / `"未知"`（KEEP_ON_CORE 特性） |

> **注意**：`cpu_usage` 已由脚本基于 /proc/stat 相邻采样预计算（多组取平均），可直接用于决策逻辑阈值比较，无需再手动计算。

### 降级路径：逐文件读取（仅当预解析模式失败后）

> 以下为逐文件读取原始采集数据的解析规则。**仅当预解析模式已执行且确认失败后才可使用**，禁止跳过预解析模式直接进入本路径。仅在以下情况使用：
> - `preanalysis.json` 文件不存在（远端模式：经 `ssh ${user}@${ip} "test -f ${DATA_DIR}/opentunex-dynamic-smt-analysis_collect/preanalysis.json"` 在远端判断，禁止在 agent 本地查找）
> - 脚本 `preanalysis.sh` 执行失败
>
> **⚠️ 大文件警告**：采集数据文件可能非常大，**禁止**直接 `cat`/Read 整个文件。必须按下方每个指标的提取方法（grep 关键字 / sed 定位节）**定向搜索**目标内容，只读取命中的片段；远端模式经 ssh 在远端执行 grep，只把命中片段流回上下文，禁止把整个文件拉回 agent 本地。

#### 从 `${DATA_DIR}/cpu_detail_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| CPU_USAGE | 从 "/proc/stat 多采样" 节中取相邻 `cpu ` 行计算：(delta_total − delta_idle) / delta_total × 100，多组取平均 | 0 |
| SMT_ACTIVE | 搜索 "SMT active:" 行，值为 1 → 已启用，0 → 未禁用，unknown → 未知 | 未知 |

**CPU 使用率计算方法**：`cpu ` 行中字段顺序为 user, nice, system, idle, iowait, irq, softirq, steal。total = 前8个字段之和，idle_total = idle + iowait。相邻两个采样的 delta_total != 0 时 utilization = (delta_total − delta_idle) / delta_total × 100。

#### 从 `${DATA_DIR}/kernel_config_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| SCHED_SUPPORT | 搜索 "KEEP_ON_CORE": "present" → 支持；"NOT present" → 不支持；搜索 "NO_KEEP_ON_CORE" 也视为支持 | 未知 |

**阈值参数**：

| 参数 | 默认值 | 含义 |
|------|--------|------|
| THRESHOLD | 80% | CPU 使用率高负载阈值 |

---

## 决策逻辑

> **前置检查分类（遵守 SB-06）**：场景条件为 `CPU_USAGE < THRESHOLD`（低负载，存在超线程干扰优化空间）。`SMT_ACTIVE ≠ 已启用` 与 `SCHED_SUPPORT ≠ 支持` 均为"环境不支持"类条件，**不短路**：当场景条件满足但环境不支持时，输出 `limited_benefit` 建议并标注支持缺口，而非直接判为"不启用"。

```
IF CPU_USAGE ≥ THRESHOLD:
    结论 = "不需要启用动态 SMT"（高负载无收益，运行时条件）
    原因 = "CPU 使用率 {X}% ≥ {THRESHOLD}%，高负载下应保持最大并行能力"
ELSE:  # 场景条件满足：低负载，存在动态 SMT 调优空间
    记录支持缺口：
      SMT_GAP   = (SMT_ACTIVE ≠ 已启用) ? "SMT 未启用" : null
      SCHED_GAP = (SCHED_SUPPORT ≠ 支持) ? "内核不支持 KEEP_ON_CORE 调度特性" : null
    IF SMT_GAP = null AND SCHED_GAP = null:
        结论 = "建议启用 dynamic_smt_tune"（适用）
        原因 = "CPU 使用率 {X}% < {THRESHOLD}%，系统负载低，且 SMT 已启用、内核调度特性支持，满足动态 SMT 调优条件"
    ELSE:
        # 场景匹配但环境不支持（SB-06）：仍作为建议输出
        结论 = "收益有限（环境不支持但场景匹配）"
        原因 = "CPU 使用率 {X}% < {THRESHOLD}%，系统负载低存在动态 SMT 调优场景，但 [逐条列出 SMT_GAP/SCHED_GAP]，需 [启用 SMT / 升级至支持 KEEP_ON_CORE 的内核] 后方可实施"
```

---

## 调优步骤推荐

> **执行位置说明**：本技能只输出建议，**不执行**调优命令（遵守 T-01/T-02）。远端模式下这些命令的目标机器是远端服务器——用户确认后由用户（或后续调优域技能生成的 tuning.sh）在**远端服务器**上执行；agent 不通过 ssh 代执行调优命令。

> 以下调优步骤仅在分析结论为"建议启用"时适用。结论为"不需要启用"或"收益有限"时不执行调优。

### 调优参数

| 参数 | 路径 | 建议值 | 说明 |
|------|------|--------|------|
| sched_util_ratio | `/proc/sys/kernel/sched_util_ratio` | 80-100（默认100） | 调度器利用率比例阈值，较低值让调度器更激进地聚集任务 |
| KEEP_ON_CORE | `/sys/kernel/debug/sched/features` | `KEEP_ON_CORE` | 核心保持策略，减少不必要的线程迁移 |

> 两个参数必须配合使用：先设置 sched_util_ratio，再启用 KEEP_ON_CORE。

### 使能命令

```bash
# 使用调优脚本（推荐）
bash scripts/dynamic_smt_tune.sh check     # 环境检查
bash scripts/dynamic_smt_tune.sh apply     # 默认阈值 100
bash scripts/dynamic_smt_tune.sh apply 80  # 指定阈值 80

# 或手动执行
echo 80 > /proc/sys/kernel/sched_util_ratio
echo KEEP_ON_CORE > /sys/kernel/debug/sched/features
```

### 验证命令

```bash
cat /proc/sys/kernel/sched_util_ratio
grep -E 'KEEP_ON_CORE|NO_KEEP_ON_CORE' /sys/kernel/debug/sched/features
```

### 回滚命令

```bash
bash scripts/dynamic_smt_tune.sh rollback
# 或手动: echo NO_KEEP_ON_CORE > /sys/kernel/debug/sched/features; 恢复 sched_util_ratio 原始值
```

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| sched_features | NUMA 并行调度 (PARAL) | 先 PARAL 后 KEEP_ON_CORE |
| sched_features | 窃取任务 (STEAL) | 无冲突，可并行 |
| sched_features | 分域调度 (SOFT_DOMAIN) | 无冲突，可并行 |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-dynamic-smt-analysis_collect/result.md`（远端模式：**直接在远端机器上产出该文件**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、禁止在 agent 本地创建 `${WORK_DIR}` 目录），格式如下：

```markdown
## 动态 SMT 调优分析结论

**结论**：{结论}

**原因**：{原因}

## 评估摘要

| 指标 | 观测值 | 阈值 | 状态 |
|------|--------|------|------|
| CPU 使用率 | {X}% | {THRESHOLD}% | {高负载/低负载} |
| SMT 启用状态 | {已启用/未禁用/未知} | 必须启用 | ✅/❌ |
| 调度特性支持 | {支持/不支持/未知} | 必须支持 | ✅/❌ |

## 调优步骤推荐

> 仅在结论为"建议启用"时适用。

### 调优参数

| 参数 | 建议值 |
|------|--------|
| sched_util_ratio | {threshold} |
| KEEP_ON_CORE | 启用 |

### 使能命令

```bash
# 使用调优脚本
bash scripts/dynamic_smt_tune.sh apply {threshold}

# 或手动执行
echo {threshold} > /proc/sys/kernel/sched_util_ratio
echo KEEP_ON_CORE > /sys/kernel/debug/sched/features
```

### 验证

```bash
cat /proc/sys/kernel/sched_util_ratio
grep KEEP_ON_CORE /sys/kernel/debug/sched/features
```

### 回滚

```bash
bash scripts/dynamic_smt_tune.sh rollback
```
```

## 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "dynamic_smt",
  "suggestion": "写入 sched_util_ratio=<threshold> 到 /proc/sys/kernel/sched_util_ratio，再向 sched_features 写入 KEEP_ON_CORE",
  "equivalence_class": "dynamic_smt",
  "activation_requirement": "immediate",
  "estimated_gain": {
    "primary_metric": "cpu_usage",
    "severity": "high",
    "description": "低负载场景下减少超线程干扰，提升单线程性能10%-25%"
  },
  "conflicts": [],
  "prerequisites": [],
  "synergy_with": [],
  "scenario_priority": 4,
  "source": "skill_output",
  "cross_skill_relations": {}
}
```

> **字段填充说明**：
> - `applicability`：分析结论为"建议启用"→ `"applicable"`；"不需要启用"（CPU 高负载等运行时条件）→ `"limited_benefit"`；"收益有限（环境不支持但场景匹配）"（低负载但 SMT 未启用 / 内核不支持）→ `"limited_benefit"`
> - 映射标准见 [统一映射表](../references/result-template.md#零子技能结论--结构化数据映射统一标准)
> - `estimated_gain.severity`：使用评估矩阵判定（瓶颈严重程度 × 建议匹配效能）→ `high` / `medium` / `low`
> - 若 applicability 为 `"not_applicable"`：`estimated_gain.severity` 设为 `"low"`，`suggestion` 填写不启用的原因描述
> - 若 applicability 为 `"limited_benefit"`：`estimated_gain.severity` 设为 `"low"`，正常参与融合流程
> - **环境不支持但场景匹配（SB-06）**：当 `CPU_USAGE < THRESHOLD` 但 `SMT_GAP` 或 `SCHED_GAP` 非空时，`applicability` 设为 `"limited_benefit"`，`suggestion` 须以前缀 `[当前系统不支持（SMT 未启用 / 内核不支持 KEEP_ON_CORE），需启用 SMT / 升级内核后方可实施] ` 标注支持缺口
> - activation_requirement 字段保持当前模板中预设的值，无需修改。

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-dynamic-smt-analysis"
input:
  analysis_dir: "[actual analysis_dir]"
  data_dir: "[actual data_dir]"
  collect_dir: "[actual collect_dir]"
output:
  analysis_report_path: "[actual analysis_report_path]"
constraints_acknowledged: [SB-01~SB-07]
