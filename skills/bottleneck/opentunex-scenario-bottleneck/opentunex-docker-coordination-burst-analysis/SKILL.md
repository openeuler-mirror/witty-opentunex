---
name: "opentunex-docker-coordination-burst-analysis"
description: "Docker算力统筹适用性分析。分析宿主机CPU负载与容器CPU使用率，判断是否需要为CPU受限容器启用算力统筹（Coordination Burst）。当涉及容器性能、Docker CPU限流、容器CPU瓶颈、cfs_burst、容器CPU配额不足、宿主机有空闲算力等场景时，必须使用本技能。"
---

# Docker Coordination Burst 分析

分析宿主机 CPU 负载、内核 burst 支持能力以及各容器的 CPU 使用与软配额状态，判断是否需要为高负载容器启用 Docker Coordination Burst（CPU burst），并给出具体操作建议。

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-docker-coordination-burst-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 与 `${DATA_DIR}` 都是**远端服务器上**的路径：
  - `scripts/preanalysis.sh` 远端执行**必须加载并遵循 `opentunex-remote-execution` skill 的执行方式**（`ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-docker-coordination-burst-analysis/"` → scp 上传脚本到远端 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-docker-coordination-burst-analysis/` → 远端执行`ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-docker-coordination-burst-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect"`；session 超时按该 skill 扩展为 1200 秒；**禁止**读取脚本内容后自行合成命令代替执行。**禁止**在 agent 本地执行该脚本或读写本地 `${DATA_DIR}` 路径
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
| 1 | 执行 `scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect`（本地模式直接执行；远端模式按 `opentunex-remote-execution` skill 执行方式先 `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-docker-coordination-burst-analysis/"`，然后 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-docker-coordination-burst-analysis/` 再 `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-docker-coordination-burst-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect"`，`preanalysis.json` 生成在**远端**输出目录，禁止在 agent 本地执行） | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect/preanalysis.json"` 流回上下文；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径） | 决策变量值 |
| 3 | 按"决策逻辑"章节依次执行 B1→B6 判定 | 分析结论 + 容器级明细 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-docker-coordination-burst-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。**远端模式**下 `preanalysis.json` 生成在远端服务器输出目录 `${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect/`，步骤 2 必须经 ssh `cat` 流回上下文读取，**禁止**在 agent 本地目录查找或读取该文件。步骤 1 为强制预解析模式：仅当步骤 1 执行失败或 `preanalysis.json` 不存在时才允许进入"数据读取"章节的降级路径，**禁止**跳过步骤 1 直接读取原始数据文件。**预解析模式下禁止直接读取 `scripts/preanalysis.sh` 脚本内容**（不得 Read/cat 脚本文件本身）：本地模式直接执行脚本；远端模式按 `opentunex-remote-execution` skill 执行方式 scp 上传脚本文件到远端后 ssh 执行，无需阅读脚本实现。

---

## 数据读取

> **强制顺序**：本技能提供 `scripts/preanalysis.sh` 脚本对原始采集数据进行预处理。**必须先执行脚本生成 `preanalysis.json` 并基于 JSON 进行分析，禁止跳过预解析模式直接逐文件读取原始数据**。仅当预解析模式失败（脚本执行失败或 `preanalysis.json` 不存在，远端模式经 ssh 在远端确认）后，才允许进入下方降级路径。

### 预解析模式（强制首选）：预分析 JSON

1. 执行预处理脚本生成 JSON（远端模式：按 `opentunex-remote-execution` skill 执行方式 scp 上传后 `ssh -q -tt` 在远端执行，见"输入约定"执行模式章节）：
   ```bash
   bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect/preanalysis.json`（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect/preanalysis.json"` 流回上下文读取；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径、禁止 scp 拷回本地）

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `host_cpu_util` | HOST_CPU_UTIL | 数值百分比，如 `32.50`（由脚本基于 /proc/stat 多采样预计算） |
| `host_ncpus` | HOST_NCPUS | 整数，宿主机 CPU 数量 |
| `burst_support` | BURST_SUPPORT | `"支持"` / `"不支持"` |
| `container_count` | CONTAINER_COUNT | 整数，运行中容器数量 |
| `containers[].id` | — | 容器短 ID（前 12 位） |
| `containers[].full_id` | — | 容器完整 ID |
| `containers[].cpu_usage` | 容器使用率 | 百分比数值（由脚本基于首尾采样 cpuacct_usage 差值预计算） |
| `containers[].cpu_limit` | CPU 限制 | 核数（cfs_quota_us / cfs_period_us，回退 host_ncpus） |
| `containers[].soft_quota` | 软配额状态 | `"已启用"` / `"未启用"` |
| `containers[].classification` | 容器分类 | `"建议对象"` / `"已启用 burst"` / `"低负载"`（由脚本预计算） |

> **注意**：容器的 `cpu_usage` 和 `classification` 已由脚本基于首尾采样预计算，可直接用于 B4/B5/B6 判定，无需再手动解析 container_info.txt 的 SAMPLE 块。

### 降级路径：逐文件读取（仅当预解析模式失败后）

> 以下为逐文件读取原始采集数据的解析规则。**仅当预解析模式已执行且确认失败后才可使用**，禁止跳过预解析模式直接进入本路径。仅在以下情况使用：
> - `preanalysis.json` 文件不存在（远端模式：经 `ssh ${user}@${ip} "test -f ${DATA_DIR}/opentunex-docker-coordination-burst-analysis_collect/preanalysis.json"` 在远端判断，禁止在 agent 本地查找）
> - 脚本 `preanalysis.sh` 执行失败
>
> **⚠️ 大文件警告**：采集数据文件可能非常大，**禁止**直接 `cat`/Read 整个文件。必须按下方每个指标的提取方法（grep 关键字 / sed 定位节）**定向搜索**目标内容，只读取命中的片段；远端模式经 ssh 在远端执行 grep，只把命中片段流回上下文，禁止把整个文件拉回 agent 本地。

#### 从 `${DATA_DIR}/cpu_detail_info.txt` 读取

| 指标              | 提取方法                                                                                         | 默认值 |
| --------------- | -------------------------------------------------------------------------------------------- | --- |
| HOST\_CPU\_UTIL | 从 "/proc/stat 多采样" 节中取相邻 `cpu `  行计算 (delta\_total − delta\_idle) / delta\_total × 100，多组取平均 | 0   |
| HOST\_NCPUS     | 搜索 "在线CPU数量" 行的数字；若无，搜索 "processor 数量" 行                                                     | 1   |

#### 从 `${DATA_DIR}/kernel_config_info.txt` 读取

| 指标             | 提取方法                                                                                            | 默认值 |
| -------------- | ----------------------------------------------------------------------------------------------- | --- |
| BURST\_SUPPORT | 搜索 "Docker CPU Burst: yes" → 支持；搜索 "sched\_soft\_runtime\_ratio" 且值不为 "not exist" → 支持；其余 → 不支持 | 不支持 |

#### 从 `${DATA_DIR}/container_info.txt` 读取

从 "容器 CPU 多采样观测" 节中逐采样提取每个容器的数据。每个采样块格式：

```
=== SAMPLE <N> ===
=== TIMESTAMP <epoch> ===
--- CONTAINER ---
id=<full_container_id>
cfs_period_us=<value>
cfs_quota_us=<value>
cpuacct_usage=<value>
soft_quota=<0|1>
timestamp=<epoch>
--- END CONTAINER ---
```

**容器 CPU 使用率计算**：对每个容器，取首尾采样的 `cpuacct_usage` 差值除以时间间隔得实际用量。CPU 限制 = `cfs_quota_us / cfs_period_us`（若 cfs\_quota\_us > 0），否则为 HOST\_NCPUS。使用率 = 实际用量 / (CPU 限制 × 时间间隔) × 100。

**阈值参数**：

| 参数                   | 默认值 | 含义         |
| -------------------- | --- | ---------- |
| HOST\_THRESHOLD      | 45% | 宿主机负载高/低阈值 |
| CONTAINER\_THRESHOLD | 95% | 容器高负载阈值    |

---

## 决策逻辑

按以下优先级依次判断，命中即输出：

> **前置检查分类（遵守 SB-06）**：B2 为"硬性不适用"（无运行中容器，无收益对象），命中即短路；B1 为"环境不支持"（内核未提供 sched_soft_runtime_ratio），**不短路**，仅记录支持缺口 `BURST_UNSUPPORTED_GAP=true`，继续评估 B3-B6 场景条件。场景条件满足但环境不支持时，按"环境支持缺口处理"输出 `limited_benefit` 建议。

| 优先级 | 条件                                                                                  | 结论                                        |
| --- | ----------------------------------------------------------------------------------- | ----------------------------------------- |
| B1  | BURST\_SUPPORT = 不支持                                                                | 记录 `BURST_UNSUPPORTED_GAP=true`，**继续评估**（不短路） — 内核未提供 sched\_soft\_runtime\_ratio（环境支持缺口，场景匹配时仍作为建议输出，见 SB-06） |
| B2  | 无运行中容器（采样中无 CONTAINER 块）                                                            | 无运行中的容器，无需启用                              |
| B3  | HOST\_CPU\_UTIL > HOST\_THRESHOLD                                                   | 不建议启用 — 宿主机负载高，不适合调度突发流量                  |
| B4  | HOST\_CPU\_UTIL ≤ HOST\_THRESHOLD 且存在 soft\_quota=0 且使用率 > CONTAINER\_THRESHOLD 的容器 | **建议启用** — 宿主机负载低，存在未启用 burst 的高负载容器      |
| B5  | HOST\_CPU\_UTIL ≤ HOST\_THRESHOLD 且所有高负载容器已启用 burst（soft\_quota=1）                  | 无需额外操作 — 已正确配置                            |
| B6  | HOST\_CPU\_UTIL ≤ HOST\_THRESHOLD 且所有容器使用率 ≤ CONTAINER\_THRESHOLD                   | 无需启用 — 无高负载容器                             |

### 环境支持缺口处理（SB-06）

> 当 B4 命中（宿主机负载低且存在未启用 burst 的高负载容器，存在算力统筹调优场景），但前置检查 B1 已记录 `BURST_UNSUPPORTED_GAP=true`（内核未提供 sched_soft_runtime_ratio）时，**不得直接判为"环境不支持"**，改按下表输出：

| 条件 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|------|---------|--------------|-----------|------------------------|
| 场景匹配（B4 命中）且 `BURST_UNSUPPORTED_GAP=true` | 收益有限（环境不支持但场景匹配） | `limited_benefit` | `[当前内核未提供 sched_soft_runtime_ratio，需升级至支持 CPU Burst 的内核后方可实施] 设置全局 sched_soft_runtime_ratio=20，对高负载容器写入 cpu.soft_quota=1` | `low` |

**综合结论示例**：`收益有限 — 内核未提供 sched_soft_runtime_ratio，但宿主机负载 {X}% ≤ {THRESHOLD}% 且存在未启用 burst 的高负载容器（使用率 {X}% > 95%），存在 CPU 限流瓶颈，建议升级内核后实施`

---

## 调优步骤推荐

> **执行位置说明**：本技能只输出建议，**不执行**调优命令（遵守 T-01/T-02）。远端模式下这些命令的目标机器是远端服务器——用户确认后由用户（或后续调优域技能生成的 tuning.sh）在**远端服务器**上执行；agent 不通过 ssh 代执行调优命令。

> 以下调优步骤仅在分析结论为"建议启用"时适用。结论为"不建议启用"或"收益有限"时不执行调优。

### 调优参数

| 参数 | 路径 | 建议值 | 说明 |
|------|------|--------|------|
| sched_soft_runtime_ratio | `/proc/sys/kernel/sched_soft_runtime_ratio` | 20 | 全局参数，控制突发调度运行时间比例 |
| cpu.soft_quota | `/sys/fs/cgroup/cpu/<container>/cpu.soft_quota` | 1 | 容器级别，启用 CPU Burst 突发配额 |

> 先设置全局参数 sched_soft_runtime_ratio，再对每个目标容器启用 cpu.soft_quota。

### 使能命令

```bash
# 使用调优脚本（推荐）
bash scripts/docker_coordination_burst.sh check    # 环境检查
bash scripts/docker_coordination_burst.sh backup   # 备份当前配置
bash scripts/docker_coordination_burst.sh apply    # 自动检测高负载容器并启用

# 或手动执行
# 1. 设置全局参数
echo 20 > /proc/sys/kernel/sched_soft_runtime_ratio
# 2. 对每个目标容器启用 burst
echo 1 > /sys/fs/cgroup/cpu/<container>/cpu.soft_quota
```

### 验证命令

```bash
cat /proc/sys/kernel/sched_soft_runtime_ratio
for c in /sys/fs/cgroup/cpu/docker/*/; do echo "$c: soft_quota=$(cat $c/cpu.soft_quota 2>/dev/null)"; done
```

### 回滚命令

```bash
bash scripts/docker_coordination_burst.sh rollback
# 或手动: 恢复 sched_soft_runtime_ratio 原始值; 对容器设置 cpu.soft_quota=0
```

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| sched_soft_runtime_ratio | 全局 CPU 调度参数 | 无冲突，独立参数 |
| cpu.soft_quota | 分域调度 (cpu.soft_domain) | 无冲突，不同 cgroup 参数 |
| sched_features | NUMA/STEAL/SOFT_DOMAIN | 无冲突，独立参数 |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-docker-coordination-burst-analysis_collect/result.md`（远端模式：**直接在远端机器上产出该文件**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、禁止在 agent 本地创建 `${WORK_DIR}` 目录），格式如下：

```markdown
## Docker Coordination Burst 分析结论

**结论**：{结论}

**原因**：{原因}

## 评估摘要

| 指标 | 观测值 | 阈值 | 状态 |
|------|--------|------|------|
| 宿主机 CPU 使用率 | {X}% | {HOST_THRESHOLD}% | {高负载/低负载} |
| 内核 burst 支持 | {支持/不支持} | 必须支持 | ✅/❌ |
| 检测到容器数 | {N} | >0 | {有/无} |

## 容器级评估明细

| 容器 ID（短） | CPU 使用率 | CPU 限制（核） | 软配额 | 分类 |
|---------------|-----------|---------------|--------|------|
| {short_id} | {X}% | {limit} | {已启用/未启用} | {建议对象/已启用 burst/低负载} |

## 调优步骤推荐

> 仅在结论为"建议启用"时适用。

### 调优参数

| 参数 | 建议值 |
|------|--------|
| sched_soft_runtime_ratio | 20 |
| cpu.soft_quota | 1（每个目标容器） |

### 使能命令

```bash
bash scripts/docker_coordination_burst.sh apply
```

### 验证

```bash
cat /proc/sys/kernel/sched_soft_runtime_ratio
cat /sys/fs/cgroup/cpu/<container>/cpu.soft_quota
```

### 回滚

```bash
bash scripts/docker_coordination_burst.sh rollback
```
```

**注意**：当 B3 命中（不建议启用）时，仍应展示容器级评估明细，仅不输出建议操作。

## 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "docker_coordination_burst",
  "suggestion": "设置全局 sched_soft_runtime_ratio=20，对高负载容器写入 cpu.soft_quota=1",
  "equivalence_class": "docker_coordination_burst",
  "activation_requirement": "immediate",
  "estimated_gain": {
    "primary_metric": "container_cpu_throttle",
    "severity": "high",
    "description": "容器CPU限流现象减少50%-80%，突发请求响应延迟降低30%-50%"
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
> - `applicability`：分析结论为"建议启用"→ `"applicable"`；"不建议启用"（宿主机负载高等运行时条件）→ `"limited_benefit"`；"收益有限（环境不支持但场景匹配）"（B4 命中但 BURST 不支持）→ `"limited_benefit"`；"无需启用/无运行中容器"→ `"not_applicable"`
> - 映射标准见 [统一映射表](../references/result-template.md#零子技能结论--结构化数据映射统一标准)
> - `estimated_gain.severity`：使用评估矩阵判定（瓶颈严重程度 × 建议匹配效能）→ `high` / `medium` / `low`
> - 若 applicability 为 `"not_applicable"`：`estimated_gain.severity` 设为 `"low"`，`suggestion` 填写不适用/不支持的原因描述
> - 若 applicability 为 `"limited_benefit"`：`estimated_gain.severity` 设为 `"low"`，正常参与融合流程
> - **环境不支持但场景匹配（SB-06）**：当 `BURST_UNSUPPORTED_GAP=true` 且 B4 命中时，`applicability` 设为 `"limited_benefit"`，`suggestion` 须以前缀 `[当前内核未提供 sched_soft_runtime_ratio，需升级至支持 CPU Burst 的内核后方可实施] ` 标注支持缺口
> - activation_requirement 字段保持当前模板中预设的值，无需修改。

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-docker-coordination-burst-analysis"
input:
  analysis_dir: "[actual analysis_dir]"
  data_dir: "[actual data_dir]"
  collect_dir: "[actual collect_dir]"
output:
  analysis_report_path: "[actual analysis_report_path]"
constraints_acknowledged: [SB-01~SB-07]
