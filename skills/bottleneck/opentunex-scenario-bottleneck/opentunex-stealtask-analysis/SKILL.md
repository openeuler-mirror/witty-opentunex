---
name: "opentunex-stealtask-analysis"
description: "窃取任务调度分析。检查CONFIG_SCHED_STEAL与STEAL特性支持、分析CPU负载与调度特征、评估调优适用性。触发:CPU高负载、负载不均衡、调度优化。"
---

# 窃取任务调度分析

分析系统CPU负载状态和调度特征，检查内核是否支持窃取任务（stealtask）特性，评估窃取任务调优的适用性。

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-stealtask-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 与 `${DATA_DIR}` 都是**远端服务器上**的路径：
  - `scripts/preanalysis.sh` 远端执行**必须加载并遵循 `opentunex-remote-execution` skill 的执行方式**（`ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-stealtask-analysis/"` → scp 上传脚本到远端 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-stealtask-analysis/` → 远端执行`ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-stealtask-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-stealtask-analysis_collect"`；session 超时按该 skill 扩展为 1200 秒；**禁止**读取脚本内容后自行合成命令代替执行。**禁止**在 agent 本地执行该脚本或读写本地 `${DATA_DIR}` 路径
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
| 1 | 执行 `scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-stealtask-analysis_collect`（本地模式直接执行；远端模式按 `opentunex-remote-execution` skill 执行方式先 `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-stealtask-analysis/"`，然后 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-stealtask-analysis/` 再 `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-stealtask-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-stealtask-analysis_collect"`，`preanalysis.json` 生成在**远端**输出目录，禁止在 agent 本地执行） | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-stealtask-analysis_collect/preanalysis.json"` 流回上下文；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径） | 决策变量值 |
| 3 | 按"决策逻辑"章节依次执行 S1→S6 判定 | 分析结论 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-stealtask-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。**远端模式**下 `preanalysis.json` 生成在远端服务器输出目录 `${DATA_DIR}/opentunex-stealtask-analysis_collect/`，步骤 2 必须经 ssh `cat` 流回上下文读取，**禁止**在 agent 本地目录查找或读取该文件。步骤 1 为强制预解析模式：仅当步骤 1 执行失败或 `preanalysis.json` 不存在时才允许进入"数据读取"章节的降级路径，**禁止**跳过步骤 1 直接读取原始数据文件。**预解析模式下禁止直接读取 `scripts/preanalysis.sh` 脚本内容**（不得 Read/cat 脚本文件本身）：本地模式直接执行脚本；远端模式按 `opentunex-remote-execution` skill 执行方式 scp 上传脚本文件到远端后 ssh 执行，无需阅读脚本实现。

---

## 数据读取

> **强制顺序**：本技能提供 `scripts/preanalysis.sh` 脚本对原始采集数据进行预处理。**必须先执行脚本生成 `preanalysis.json` 并基于 JSON 进行分析，禁止跳过预解析模式直接逐文件读取原始数据**。仅当预解析模式失败（脚本执行失败或 `preanalysis.json` 不存在，远端模式经 ssh 在远端确认）后，才允许进入下方降级路径。

### 预解析模式（强制首选）：预分析 JSON

1. 执行预处理脚本生成 JSON（远端模式：按 `opentunex-remote-execution` skill 执行方式 scp 上传后 `ssh -q -tt` 在远端执行，见"输入约定"执行模式章节）：
   ```bash
   bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-stealtask-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-stealtask-analysis_collect/preanalysis.json`（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-stealtask-analysis_collect/preanalysis.json"` 流回上下文读取；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径、禁止 scp 拷回本地）

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `config_sched_steal` | CONFIG_SCHED_STEAL | `"已启用"` / `"未启用"` |
| `steal_support` | STEAL_SUPPORT | `"支持"` / `"不支持"` |
| `steal_enabled` | STEAL_ENABLED | `"已启用"` / `"未启用"` |
| `cmdline_steal_node_limit` | CMDLINE_STEAL_NODE_LIMIT | `"已配置"` / `"未配置"` |
| `steal_version` | STEAL_VERSION | `"旧版本"` / `"新版本"` / `"未知"`（通过 `sched_max_steal_count` sysctl 是否存在判断） |
| `cpu_usage` | CPU_USAGE | 数值百分比，如 `75.50` |
| `cpu_imbalance` | CPU_IMBALANCE | 数值百分比，如 `35.20`，max(核心使用率) − min(核心使用率)（由脚本预计算） |
| `cs_rate` | CS_RATE | 整数，vmstat cs 列平均值 |

> **注意**：`cpu_imbalance` 已由脚本基于各核心 mpstat Average 行预计算，可直接用于 S4/S5/S6 判定，无需再手动计算。

### 降级路径：逐文件读取（仅当预解析模式失败后）

> 以下为逐文件读取原始采集数据的解析规则。**仅当预解析模式已执行且确认失败后才可使用**，禁止跳过预解析模式直接进入本路径。仅在以下情况使用：
> - `preanalysis.json` 文件不存在（远端模式：经 `ssh ${user}@${ip} "test -f ${DATA_DIR}/opentunex-stealtask-analysis_collect/preanalysis.json"` 在远端判断，禁止在 agent 本地查找）
> - 脚本 `preanalysis.sh` 执行失败
>
> **⚠️ 大文件警告**：采集数据文件可能非常大，**禁止**直接 `cat`/Read 整个文件。必须按下方每个指标的提取方法（grep 关键字 / sed 定位节）**定向搜索**目标内容，只读取命中的片段；远端模式经 ssh 在远端执行 grep，只把命中片段流回上下文，禁止把整个文件拉回 agent 本地。

#### 从 `${DATA_DIR}/kernel_config_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| CONFIG_SCHED_STEAL | 搜索 "CONFIG_SCHED_STEAL=y" → 已启用；否则搜索 "sched_steal_node_limit:" 看是否为 yes | 未启用 |
| STEAL_SUPPORT | 搜索 "STEAL" 关键字：出现 "STEAL" 或 "NO_STEAL" → 支持；均不出现 → 不支持 | 不支持 |
| STEAL_ENABLED | 搜索 sched_features 内容：出现 "STEAL" 且无 "NO_" 前缀 → 已启用 | 未启用 |
| CMDLINE_STEAL_NODE_LIMIT | 搜索 "sched_steal_node_limit:"：值为 yes → 已配置；否则 → 未配置 | 未配置 |
| STEAL_VERSION | 搜索 `sched_max_steal_count` sysctl 输出：能正常输出数值 → 旧版本；报错 "unknown key" 或无法访问 → 新版本 | 未知 |

#### 从 `${DATA_DIR}/global_bottleneck.txt` 读取（若缺数据则回退到 `${DATA_DIR}/cpu_detail_info.txt`）

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| CPU_USAGE | 从 "各核心利用率 (mpstat)" 节中找 `Average: all` 行，100 − idle% = 使用率；若无，从 "/proc/stat 多采样" 节中取 `cpu ` 行计算 (delta_total − delta_idle) / delta_total × 100 | 0 |
| CPU_IMBALANCE | 从 mpstat 各核心 Average 行中，max(使用率) − min(使用率) | 0 |
| CS_RATE | vmstat 输出中 cs 列平均值 | 0 |

**阈值参数**：

| 参数 | 默认值 | 含义 |
|------|--------|------|
| CPU_HIGH | 70% | CPU 高负载阈值 |
| CPU_LOW | 40% | CPU 低负载阈值 |
| IMBALANCE | 30% | 负载不均衡阈值 |

---

## 决策逻辑

按以下优先级依次判断，命中即输出：

> **前置检查分类（遵守 SB-06）**：S2 为"硬性不适用"（特性已启用），命中即短路终止；S1 为"环境不支持"（内核未启用 CONFIG_SCHED_STEAL），**不短路**，仅记录支持缺口 `STEAL_UNSUPPORTED_GAP=true`，继续评估 S3-S6 场景条件。场景条件满足但环境不支持时，按"环境支持缺口处理"输出 `limited_benefit` 建议。

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| S1 | CONFIG_SCHED_STEAL = 未启用 | 记录 `STEAL_UNSUPPORTED_GAP=true`，**继续评估**（不短路） | 内核不支持 CONFIG_SCHED_STEAL（环境支持缺口，场景匹配时仍作为建议输出，见 SB-06） |
| S2 | STEAL_ENABLED = 已启用 | 不适用 | STEAL 特性已启用 |
| S3 | CPU_USAGE < CPU_LOW | 收益有限 | CPU 负载较低 |
| S4 | CPU_USAGE ≥ CPU_HIGH 且 CPU_IMBALANCE ≥ IMBALANCE 且 !STEAL_ENABLED | **适用** | 高负载+不均衡，收益高 |
| S5 | CPU_USAGE ≥ CPU_LOW 且 CPU_IMBALANCE ≥ IMBALANCE 且 !STEAL_ENABLED | **适用** | 存在不均衡，有收益 |
| S6 | CPU_USAGE ≥ CPU_HIGH 但 CPU_IMBALANCE < IMBALANCE | 收益有限 | 负载已均衡 |

### 环境支持缺口处理（SB-06）

> 当 S4/S5 命中（高负载+不均衡，存在窃取任务调优场景），但前置检查 S1 已记录 `STEAL_UNSUPPORTED_GAP=true`（内核未启用 CONFIG_SCHED_STEAL）时，**不得直接判为"不适用"**，改按下表输出：

| 条件 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|------|---------|--------------|-----------|------------------------|
| 场景匹配（S4/S5 命中）且 `STEAL_UNSUPPORTED_GAP=true` | 收益有限（环境不支持但场景匹配） | `limited_benefit` | `[当前内核未启用 CONFIG_SCHED_STEAL，需更换至支持 SCHED_STEAL 的内核后方可实施] <按版本选择启用方式：旧版本 grub.cfg 添加 sched_steal_node_limit 并重启后 echo STEAL；新版本直接 echo STEAL>` | `low` |

**综合结论示例**：`收益有限 — 内核未启用 CONFIG_SCHED_STEAL，但 CPU 使用率 {X}% ≥ {HIGH}% 且不均衡度 {X}% ≥ 30%，存在调度不均衡瓶颈，建议更换内核后实施`

### 预期收益（仅当结论为"适用"时填充）

| 结论来源 | 预期收益 |
|---------|---------|
| S4（高负载+不均衡） | CPU资源利用率提升10%-20%，负载均衡速度提升30%-50% |
| S5（存在不均衡） | CPU资源利用率提升5%-15%，负载均衡速度提升15%-30% |

### 版本判定与启用方式（仅当结论为"适用"时填充）

> STEAL 特性在不同内核版本上有不同的启用方式。通过检查 `sched_max_steal_count` sysctl 是否可用来判断版本。

| 版本 | 判定方式 | 启用步骤 |
|------|---------|---------|
| 旧版本 | `sysctl kernel.sched_max_steal_count` 可输出数值 | ① 在 grub.cfg 中添加 `sched_steal_node_limit=<NUMA 节点数>` 启动项参数；② 重启宿主机；③ `echo STEAL > /sys/kernel/debug/sched/features` |
| 新版本（宿主机级别） | `sysctl kernel.sched_max_steal_count` 报错 `unknown key` | `echo STEAL > /sys/kernel/debug/sched/features`（无需额外参数，立即生效） |
| 新版本（容器级别 group_steal） | 同上 + 容器场景 | ① 在 grub.cfg 中添加 `group_steal` 启动项参数；② 重启宿主机；③ `echo STEAL > /sys/kernel/debug/sched/features`；④ `echo 1 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task` |

**恢复方法**：

| 版本 | 恢复步骤 |
|------|---------|
| 旧版本 | ① 删除 grub.cfg 中的 `sched_steal_node_limit`；② 重启宿主机；③ `echo NO_STEAL > /sys/kernel/debug/sched/features` |
| 新版本（宿主机级别） | `echo NO_STEAL > /sys/kernel/debug/sched/features` |
| 新版本（容器级别） | ① 删除 grub.cfg 中的 `group_steal`；② 重启宿主机；③ `echo NO_STEAL > /sys/kernel/debug/sched/features`；④ `echo 0 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task` |

### 容器级 stealtask 触发条件（仅当结论为"适用"且有分析数据时判定）

> `group_steal` 是容器粒度的 steal_task 控制，仅在"存在运行中容器 且 需要差异化控制"时才推荐容器级别。

| 场景 | 判定条件 | 推荐模式 | 理由 |
|------|---------|---------|------|
| 宿主机级别 | 结论为"适用"且 `CONTAINER_COUNT = 0` 或无容器数据 | 宿主机模式（旧版本/新版本） | 无容器或无法获取容器信息，全体宿主机进程统一启用 steal |
| 容器级别 (group_steal) | 结论为"适用"且 `STEAL_VERSION = 新版本` 且 `CONTAINER_COUNT > 0` 且用户关注特定容器 | 容器模式（group_steal） | 仅对指定 cgroup 开启 steal_task，避免影响其他容器 |
| 宿主机级别（有容器，无差异化需求） | 结论为"适用"且 `CONTAINER_COUNT > 0` 但无需按容器区分 | 宿主机模式 | 所有进程（含容器内进程）统一使用 steal，简单高效 |

> **默认策略**：当 `CONTAINER_COUNT > 0` 且为**新版本**内核时，应同时输出宿主机和容器两种启用路径，由用户根据实际需求选择。旧版本内核不支持 `cpu.steal_task` cgroup 接口。

---

## 调优步骤推荐

> **执行位置说明**：本技能只输出建议，**不执行**调优命令（遵守 T-01/T-02）。远端模式下这些命令的目标机器是远端服务器——用户确认后由用户（或后续调优域技能生成的 tuning.sh）在**远端服务器**上执行；agent 不通过 ssh 代执行调优命令。

> 以下调优步骤仅在分析结论为"适用"时适用。结论为"不适用"或"收益有限"时不执行调优。

### 调优参数

| 参数 | 路径 | 建议值 | 说明 |
|------|------|--------|------|
| STEAL | `/sys/kernel/debug/sched/features` | `STEAL` | 窃取任务调度，允许跨 NUMA 节点窃取空闲任务 |
| sched_steal_node_limit | 内核启动参数 (grub.cfg) | NUMA 节点数 | 旧版本内核需配置，限制窃取范围 |
| group_steal | 内核启动参数 (grub.cfg) | 启用 | 容器场景需配置，支持 cgroup 级别窃取 |
| cpu.steal_task | `/sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task` | 1 | 新版本容器场景，cgroup 级别控制窃取 |

### 使能命令

**宿主机级别（新版本内核，即时生效）**：
```bash
# 使用调优脚本（推荐）
bash scripts/stealtask_tune.sh check    # 环境检查
bash scripts/stealtask_tune.sh apply    # 宿主机模式

# 或手动执行
echo STEAL > /sys/kernel/debug/sched/features
```

**宿主机级别（旧版本内核，需重启）**：
```bash
# 1. 修改 grub.cfg 添加启动参数
#    在内核启动行添加: sched_steal_node_limit=<NUMA节点数>
# 2. 重启系统
# 3. 重启后启用 STEAL
echo STEAL > /sys/kernel/debug/sched/features
```

**容器级别（新版本内核，需重启）**：
```bash
# 1. 修改 grub.cfg 添加启动参数: group_steal
# 2. 重启系统
# 3. 重启后启用 STEAL + 容器 cgroup
echo STEAL > /sys/kernel/debug/sched/features
echo 1 > /sys/fs/cgroup/cpu/<container_cgroup>/cpu.steal_task
```

### 验证命令

```bash
grep -E 'STEAL|NO_STEAL' /sys/kernel/debug/sched/features
cat /proc/cmdline | grep -E 'sched_steal_node_limit|group_steal'
# 容器场景:
cat /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task
```

### 回滚命令

```bash
bash scripts/stealtask_tune.sh rollback
# 或手动: echo NO_STEAL > /sys/kernel/debug/sched/features
# 容器: echo 0 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task
# 注意: grub.cfg 中的启动参数需手动移除并重启才能完全回滚
```

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| sched_features | NUMA 并行调度 (PARAL) | 先 PARAL 后 STEAL |
| sched_features | 动态 SMT (KEEP_ON_CORE) | 无冲突，可并行 |
| sched_features | 分域调度 (SOFT_DOMAIN) | 先 SOFT_DOMAIN 后 STEAL |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-stealtask-analysis_collect/result.md`（远端模式：**直接在远端机器上产出该文件**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、禁止在 agent 本地创建 `${WORK_DIR}` 目录），格式如下：

```markdown
# 窃取任务调度分析结果

## 1. 环境检查

| 检查项 | 结果 |
|--------|------|
| CONFIG_SCHED_STEAL | {启用/未启用} |
| STEAL_SUPPORT | {支持/不支持} |
| STEAL_STATUS | {已启用/未启用} |
| CMDLINE_STEAL_NODE_LIMIT | {已配置/未配置} |
| STEAL_VERSION | {旧版本/新版本/未知} |

## 2. CPU负载与调度指标

| 指标 | 值 |
|------|-----|
| CPU_USAGE | {X}% |
| CPU_IMBALANCE | {X}% |
| CS_RATE | {X} |

## 3. 适用性评估

| 评估维度 | 结果 | 证据 |
|---------|------|------|
| 内核CONFIG支持 | ✅/❌ | CONFIG_SCHED_STEAL={y/n} |
| STEAL特性支持 | ✅/❌ | sched_features支持状态 |
| STEAL当前状态 | {已启用/未启用} | — |
| CPU负载水平 | {高/中/低} | 使用率 {X}% |
| 负载均衡度 | {均衡/不均衡} | 不均衡度 {X}% |

**综合结论**: {适用/不适用/收益有限} — {原因}

**预期收益**: {量化收益或无}

**调优前提**: 仅适用于 aarch64 架构

## 4. 调优步骤推荐

> 仅在结论为"适用"时适用。

### 启用模式

{宿主机模式 / 容器模式 / 宿主机+容器模式}

### 使能命令

```bash
# 宿主机模式
bash scripts/stealtask_tune.sh apply

# 容器模式（需先在 grub.cfg 添加 group_steal 并重启）
bash scripts/stealtask_tune.sh apply --container <cgroup_path>
```

### 验证

```bash
grep STEAL /sys/kernel/debug/sched/features
```

### 回滚

```bash
bash scripts/stealtask_tune.sh rollback
```

## 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "stealtask_steal",
  "suggestion": "根据内核版本选择启用方式：旧版本在 grub.cfg 添加 sched_steal_node_limit=<NUMA节点数> 并重启后 echo STEAL > sched_features；新版本直接 echo STEAL > sched_features 即可（容器场景需额外 grub.cfg 添加 group_steal 并重启后 echo 1 > cpu.steal_task）",
  "equivalence_class": "stealtask_steal",
  "activation_requirement": "{immediate / system_reboot}（根据 STEAL_VERSION 动态填充：新版本→immediate；旧版本或容器 group_steal 场景→system_reboot）",
  "estimated_gain": {
    "primary_metric": "cpu_imbalance",
    "severity": "high",
    "description": "CPU资源利用率提升10%-20%，负载均衡速度提升30%-50%"
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
> - `applicability`：分析结论为"适用"→ `"applicable"`；"收益有限"→ `"limited_benefit"`；"不适用"→ `"not_applicable"`。映射标准见 [统一映射表](../references/result-template.md#零子技能结论--结构化数据映射统一标准)
> - `activation_requirement`：根据 STEAL_VERSION 动态填充。新版本（宿主机级别）→ `"immediate"`；旧版本或容器 group_steal 场景（需修改 grub.cfg 并重启）→ `"system_reboot"`
> - `estimated_gain.severity`：使用评估矩阵判定（瓶颈严重程度 × 建议匹配效能）→ `high` / `medium` / `low`
> - 若 applicability 为 `"not_applicable"`：`estimated_gain.severity` 设为 `"low"`，`suggestion` 填写不适用/收益有限的原因描述
> - 若 applicability 为 `"limited_benefit"`：`estimated_gain.severity` 设为 `"low"`，正常参与融合流程
> - **环境不支持但场景匹配（SB-06）**：当 `STEAL_UNSUPPORTED_GAP=true` 且 S4/S5 命中时，`applicability` 设为 `"limited_benefit"`，`suggestion` 须以前缀 `[当前内核未启用 CONFIG_SCHED_STEAL，需更换至支持 SCHED_STEAL 的内核后方可实施] ` 标注支持缺口
> - `activation_requirement`：根据 STEAL_VERSION 动态填充（见上方说明），无需手动修改模板。
```

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-stealtask-analysis"
input:
  analysis_dir: "[actual analysis_dir]"
  data_dir: "[actual data_dir]"
  collect_dir: "[actual collect_dir]"
output:
  analysis_report_path: "[actual analysis_report_path]"
constraints_acknowledged: [SB-01~SB-07]
