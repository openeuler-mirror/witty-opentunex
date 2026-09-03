---
name: "opentunex-soft-domain-analysis"
description: "分域调度分析。检查SOFT_DOMAIN特性支持、分析NUMA拓扑与容器/进程部署场景，评估soft_domain调优的适用性。触发:NUMA节点>1、小配额多实例容器、跨NUMA调度抖动。"
---

# 分域调度分析

分析系统 NUMA 拓扑和容器/进程部署场景，检查内核 sched_features 中 SOFT_DOMAIN 特性支持状态，评估分域调度（soft_domain）调优的适用性。

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-soft-domain-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 与 `${DATA_DIR}` 都是**远端服务器上**的路径：
  - `scripts/preanalysis.sh` 远端执行**必须加载并遵循 `opentunex-remote-execution` skill 的执行方式**（`ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-soft-domain-analysis/"` → scp 上传脚本到远端 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-soft-domain-analysis/` → 远端执行`ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-soft-domain-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-soft-domain-analysis_collect"`；session 超时按该 skill 扩展为 1200 秒；**禁止**读取脚本内容后自行合成命令代替执行。**禁止**在 agent 本地执行该脚本或读写本地 `${DATA_DIR}` 路径
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
| 1 | 执行 `scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-soft-domain-analysis_collect`（本地模式直接执行；远端模式按 `opentunex-remote-execution` skill 执行方式先 `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-soft-domain-analysis/"`，然后 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-soft-domain-analysis/` 再 `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-soft-domain-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-soft-domain-analysis_collect"`，`preanalysis.json` 生成在**远端**输出目录，禁止在 agent 本地执行） | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-soft-domain-analysis_collect/preanalysis.json"` 流回上下文；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径） | 决策变量值 |
| 3 | 按"决策逻辑"章节依次执行环境约束前置检查 → NUMA 拓扑检查 → 场景模式判定 | 分析结论 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-soft-domain-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。**远端模式**下 `preanalysis.json` 生成在远端服务器输出目录 `${DATA_DIR}/opentunex-soft-domain-analysis_collect/`，步骤 2 必须经 ssh `cat` 流回上下文读取，**禁止**在 agent 本地目录查找或读取该文件。步骤 1 为强制预解析模式：仅当步骤 1 执行失败或 `preanalysis.json` 不存在时才允许进入"数据读取"章节的降级路径，**禁止**跳过步骤 1 直接读取原始数据文件。**预解析模式下禁止直接读取 `scripts/preanalysis.sh` 脚本内容**（不得 Read/cat 脚本文件本身）：本地模式直接执行脚本；远端模式按 `opentunex-remote-execution` skill 执行方式 scp 上传脚本文件到远端后 ssh 执行，无需阅读脚本实现。

---

## 数据读取

> **强制顺序**：本技能提供 `scripts/preanalysis.sh` 脚本对原始采集数据进行预处理。**必须先执行脚本生成 `preanalysis.json` 并基于 JSON 进行分析，禁止跳过预解析模式直接逐文件读取原始数据**。仅当预解析模式失败（脚本执行失败或 `preanalysis.json` 不存在，远端模式经 ssh 在远端确认）后，才允许进入下方降级路径。

### 预解析模式（强制首选）：预分析 JSON

1. 执行预处理脚本生成 JSON（远端模式：按 `opentunex-remote-execution` skill 执行方式 scp 上传后 `ssh -q -tt` 在远端执行，见"输入约定"执行模式章节）：
   ```bash
   bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-soft-domain-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-soft-domain-analysis_collect/preanalysis.json`（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-soft-domain-analysis_collect/preanalysis.json"` 流回上下文读取；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径、禁止 scp 拷回本地）

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `arch` | ARCH | 字符串：`"aarch64"` / `"x86_64"` / ... |
| `numa_nodes` | NUMA_NODES | 整数，NUMA 节点数量 |
| `cpu_per_numa` | CPU_PER_NUMA | 整数，每个 NUMA 节点的 CPU 数量 |
| `kernel_ver` | KERNEL_VER | 字符串，内核版本号 |
| `soft_domain_exist` | SOFT_DOMAIN_EXIST | `"存在"` / `"不存在"` |
| `soft_domain_enabled` | SOFT_DOMAIN_ENABLED | `"已启用"` / `"未启用"` |
| `sched_features_writable` | SCHED_FEATURES_WRITABLE | `"可写"` / `"不可写"` |
| `debugfs_mounted` | DEBUGFS_MOUNTED | `"已挂载"` / `"未挂载"` |
| `container_count` | CONTAINER_COUNT | 整数，容器数量 |
| `small_quota_instances` | SMALL_QUOTA_INSTANCES | 整数，小配额容器数量 |
| `container_quota_list` | CONTAINER_QUOTA_LIST | 数组，每个元素含 `name`（容器名）、`quota_cpus`（配额 CPU 数）、`is_small`（是否小配额） |
| `target_pid` | TARGET_PID | 整数或 `null` |
| `target_cpus_allowed` | TARGET_CPUS_ALLOWED | 字符串或 `"null"`，如 `"0-3,8-11"` |
| `target_cpu_affinity_span` | TARGET_CPU_AFFINITY_SPAN | 整数，CPU 亲和跨越的 NUMA 节点数（由脚本预计算） |
| `numa_cpu_map` | NUMA_CPU_MAP | `{"node0": [0,1,...], "node1": [2,3,...]}` |

> **注意**：`target_cpu_affinity_span` 已由脚本基于 `numa_cpu_map` 预计算，可直接用于决策逻辑 S3/S4 判定，无需再手动计算。

### 降级路径：逐文件读取（仅当预解析模式失败后）

> 以下为逐文件读取原始采集数据的解析规则。**仅当预解析模式已执行且确认失败后才可使用**，禁止跳过预解析模式直接进入本路径。仅在以下情况使用：
> - `preanalysis.json` 文件不存在（远端模式：经 `ssh ${user}@${ip} "test -f ${DATA_DIR}/opentunex-soft-domain-analysis_collect/preanalysis.json"` 在远端判断，禁止在 agent 本地查找）
> - 脚本 `preanalysis.sh` 执行失败
>
> **⚠️ 大文件警告**：采集数据文件可能非常大，**禁止**直接 `cat`/Read 整个文件。必须按下方每个指标的提取方法（grep 关键字 / sed 定位节）**定向搜索**目标内容，只读取命中的片段；远端模式经 ssh 在远端执行 grep，只把命中片段流回上下文，禁止把整个文件拉回 agent 本地。

#### 从 `${DATA_DIR}/static_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| ARCH | 搜索 `Architecture:` 后的值（如 `aarch64`），位于 "--- System Info ---" 或 `uname -m` 输出节 | x86_64 |
| NUMA_NODES | 搜索 `--- NUMA Topology ---` 节中 `node X cpus:` 出现次数；若无，搜索 `NUMA node(s)` 后的数字 | 1 |
| CPU_PER_NUMA | 搜索 `--- NUMA Topology ---` 节中第一个 `node X cpus:` 的 CPU 编号个数；若无，用 `CPU(s)` / NUMA_NODES 估算 | 0 |
| KERNEL_VER | 搜索 `Kernel:` 或 `uname -r` 输出的内核版本号 | — |
| NUMA_CPU_MAP | 搜索 `--- NUMA Topology ---` 节，从 `numactl --hardware` 输出中解析 `node X cpus: Y Z ...` 行，建立 `NUMA节点 → [cpu列表]` 的映射 | 空映射 |

#### 从 `${DATA_DIR}/kernel_config_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| SOFT_DOMAIN_EXIST | 搜索 `=== 调度特性 ===` 节中 `SOFT_DOMAIN` 关键字：出现 `SOFT_DOMAIN` 词 → 存在；未出现 → 不存在 | 不存在 |
| SOFT_DOMAIN_ENABLED | 当 SOFT_DOMAIN 存在时：出现 `SOFT_DOMAIN` 且**不含** `NO_SOFT_DOMAIN` → 已启用；含 `NO_SOFT_DOMAIN` → 未启用 | 未启用 |
| SCHED_FEATURES_WRITABLE | 搜索 `sched_features 可写` 或类似描述（存在 `/sys/kernel/debug/sched/features` 且可写） | 不可写 |
| DEBUGFS_MOUNTED | 搜索 `debugfs` 挂载信息（通常含 `debugfs` 关键字），或确认 `/sys/kernel/debug/` 目录存在且 `/sys/kernel/debug/sched/features` 路径可访问 | 未挂载 |

#### 从 `${DATA_DIR}/docker_info.txt` 或 `${DATA_DIR}/container_info.txt` 读取

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| CONTAINER_COUNT | 统计 `docker ps` 输出中容器行数（排除表头） | 0 |
| CONTAINER_QUOTA_LIST | 搜索每个容器的 CPU 配额：`docker inspect` 输出中 `NanoCpus`、`CpuQuota`/`CpuPeriod` 组 | — |
| SMALL_QUOTA_INSTANCES | 统计配额 CPU 数 ≤ CPU_PER_NUMA 的容器数量 | 0 |

**配额 CPU 数计算规则**：
- `NanoCpus` 存在：`quota_cpus = NanoCpus / 1e9`
- `CpuQuota`/`CpuPeriod` 存在：`quota_cpus = CpuQuota / CpuPeriod`
- `cpuset` 存在：`quota_cpus = cpuset 指定的 CPU 数`
- 无任何配额信息：`quota_cpus = ∞`（视为不受限，不计入小配额）

#### 从 `${DATA_DIR}/top_processes.txt` 或 `${DATA_DIR}/process_info.txt` 读取（process 模式）

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| TARGET_PID | 用户指定的目标进程 PID，或从进程中搜索用户关注的关键进程 | — |
| TARGET_CPUS_ALLOWED | 搜索目标进程的 `Cpus_allowed_list` | — |
| TARGET_CPU_AFFINITY_SPAN | 统计 `Cpus_allowed_list` 跨越的 NUMA 节点数 | 1 |

### 用户输入

| 输入项 | 必需 | 说明 |
|--------|------|------|
| USER_FOCUS_CONTAINERS | 否 | 用户关注的容器名称模式（如 `redis*`、`mysql*`） |
| USER_FOCUS_PROCESSES | 否 | 用户关注的进程名（如 `mysqld`、`redis-server`） |
| LATENCY_SENSITIVE | 否 | 用户是否明确标注为尾延迟敏感型业务（默认 `false`） |

---

## 决策逻辑

按以下优先级依次判断，命中即输出。

> **前置检查分类（遵守 SB-06）**：E4 为"硬性不适用"（特性已启用），命中即短路；E1/E2/E3 为"环境不支持"（架构不符、特性不存在、debugfs 不可写），**不短路**，仅记录支持缺口 `SOFT_DOMAIN_UNSUPPORTED_GAP`（含具体缺口原因），继续评估 NUMA 拓扑与场景模式。场景条件满足但环境不支持时，按"环境支持缺口处理"输出 `limited_benefit` 建议。

### 环境约束前置检查

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| E1 | ARCH ≠ aarch64 | 记录 `SOFT_DOMAIN_UNSUPPORTED_GAP+="架构非 aarch64"`，**继续评估**（不短路） | 非 aarch64 架构，soft_domain 仅适用于 aarch64（环境支持缺口，场景匹配时仍作为建议输出，见 SB-06） |
| E2 | SOFT_DOMAIN_EXIST = 不存在 | 记录 `SOFT_DOMAIN_UNSUPPORTED_GAP+="内核未包含 SOFT_DOMAIN 特性"`，**继续评估**（不短路） | 内核调度特性中未包含 SOFT_DOMAIN（环境支持缺口） |
| E3 | DEBUGFS_MOUNTED = 未挂载 或 SCHED_FEATURES_WRITABLE = 不可写 | 记录 `SOFT_DOMAIN_UNSUPPORTED_GAP+="debugfs 不可写"`，**继续评估**（不短路） | 无法通过 debugfs 修改 sched_features（环境支持缺口，可通过挂载 debugfs 修复） |
| E4 | SOFT_DOMAIN_ENABLED = 已启用 | 不适用 | SOFT_DOMAIN 已启用，无需再调优 |

### NUMA 拓扑检查

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| N1 | NUMA_NODES ≤ 1 | 不适用 | 单 NUMA 节点无跨节点调度问题 |
| N2 | CPU_PER_NUMA ≤ 0 | 收益有限 | 无法确定每节点 CPU 数，不足以评估小配额场景 |

### 场景模式判定

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| S1 | CONTAINER_COUNT > 0 且 SMALL_QUOTA_INSTANCES ≤ 0 | 收益有限 | 容器存在但无小配额实例，跨 NUMA 调度影响有限 |
| S2 | CONTAINER_COUNT > 0 且 SMALL_QUOTA_INSTANCES ≥ 2 | **适用（容器模式）** | 存在 {N} 个小配额多实例容器运行在 {M} NUMA 节点上，跨 NUMA 调度可能导致性能抖动 |
| S3 | CONTAINER_COUNT = 0 且 TARGET_PID 有值 且 TARGET_CPU_AFFINITY_SPAN > 1 | **适用（进程模式）** | 目标进程跨越 {N} 个 NUMA 节点运行，存在跨 NUMA 调度可能 |
| S4 | CONTAINER_COUNT = 0 且 TARGET_PID 有值 且 TARGET_CPU_AFFINITY_SPAN ≤ 1 | 收益有限 | 目标进程仅运行在单 NUMA 节点，无跨节点调度问题 |
| S5 | CONTAINER_COUNT = 0 且 TARGET_PID 无值 | 收益有限 | 无容器且未指定目标进程，缺少场景触发条件 |

### 环境支持缺口处理（SB-06）

> 当 S2/S3 命中（多 NUMA + 小配额多实例容器 / 跨 NUMA 进程，存在跨 NUMA 调度瓶颈场景），但前置检查 E1/E2/E3 已记录 `SOFT_DOMAIN_UNSUPPORTED_GAP`（非空）时，**不得直接判为"不适用"**，改按下表输出：

| 条件 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|------|---------|--------------|-----------|------------------------|
| 场景匹配（S2/S3 命中）且 `SOFT_DOMAIN_UNSUPPORTED_GAP` 非空 | 收益有限（环境不支持但场景匹配） | `limited_benefit` | `[当前系统不支持（{SOFT_DOMAIN_UNSUPPORTED_GAP 具体原因}），需 {升级至 aarch64 + 支持 SOFT_DOMAIN 的内核 / 挂载 debugfs} 后方可实施] 写入 SOFT_DOMAIN 到 sched_features 总开关，对目标容器或进程 cgroup 写入 cpu.soft_domain_nr_cpu=<配额核数> 和 cpu.soft_domain=<NUMA编号>` | `low` |

**综合结论示例**：`收益有限 — 内核未包含 SOFT_DOMAIN 特性，但存在 {N} 个小配额多实例容器跨 {M} NUMA 节点运行，存在跨 NUMA 调度抖动瓶颈，建议升级内核后实施`

### 收益评估（仅当结论为"适用"时填充）

| 结论来源 | 适用场景 | 预期收益 |
|---------|---------|---------|
| S2（容器模式） | 多实例小配额容器 + 多 NUMA | 减少跨 NUMA 调度开销，降低尾延迟抖动 30%-50%；提高容器内 CPU 亲和性和缓存命中率 |
| S3（进程模式） | 单进程跨 NUMA + 多 NUMA | 减少跨 NUMA 调度开销，降低内存访问延迟 10%-20% |

### 特殊建议（仅当结论为"适用"时追加）

| 条件 | 建议 |
|------|------|
| LATENCY_SENSITIVE = true | 尾延迟敏感业务强烈建议启用 soft_domain，优先在低负载时段操作 |
| sched_features 含 `NO_SOFT_DOMAIN` | 需通过 debugfs 移除 `NO_SOFT_DOMAIN`：`echo SOFT_DOMAIN > /sys/kernel/debug/sched/features` |

---

## 调优步骤推荐

> **执行位置说明**：本技能只输出建议，**不执行**调优命令（遵守 T-01/T-02）。远端模式下这些命令的目标机器是远端服务器——用户确认后由用户（或后续调优域技能生成的 tuning.sh）在**远端服务器**上执行；agent 不通过 ssh 代执行调优命令。

> 以下调优步骤仅在分析结论为"适用"时适用。结论为"不适用"或"收益有限"时不执行调优。

### 调优参数

| 参数 | 路径 | 建议值 | 说明 |
|------|------|--------|------|
| SOFT_DOMAIN | `/sys/kernel/debug/sched/features` | `SOFT_DOMAIN` | 分域调度总开关 |
| cpu.soft_domain_nr_cpu | `/sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain_nr_cpu` | 容器配额核数 | cgroup 级别，限制分域内 CPU 数量 |
| cpu.soft_domain | `/sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain` | NUMA 节点编号 | cgroup 级别，指定分域所在 NUMA 节点 |

> 仅 aarch64 架构有效。需 debugfs 可写。先启用总开关，再配置 cgroup 参数。

### 使能命令

```bash
# 使用调优脚本（推荐）
bash scripts/soft_domain_tune.sh check                        # 环境检查
bash scripts/soft_domain_tune.sh backup                      # 备份当前配置
bash scripts/soft_domain_tune.sh apply                       # 宿主机模式
bash scripts/soft_domain_tune.sh apply docker "container-a|container-b"  # 容器模式
bash scripts/soft_domain_tune.sh apply process <pid>         # 进程模式

# 或手动执行
# 1. 启用总开关
echo SOFT_DOMAIN > /sys/kernel/debug/sched/features
# 2. 容器模式: 对每个目标容器 cgroup 写入参数
echo <quota_cpus> > /sys/fs/cgroup/cpu/<container>/cpu.soft_domain_nr_cpu
echo <numa_node_id> > /sys/fs/cgroup/cpu/<container>/cpu.soft_domain
# 3. 进程模式: 对目标进程 cgroup 写入参数
echo <cpu_span> > /sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain_nr_cpu
echo <numa_node_id> > /sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain
```

### 验证命令

```bash
grep -E 'SOFT_DOMAIN|NO_SOFT_DOMAIN' /sys/kernel/debug/sched/features
cat /sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain_nr_cpu
cat /sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain
```

### 回滚命令

```bash
bash scripts/soft_domain_tune.sh rollback
# 或手动: 清除 cgroup 参数 + echo NO_SOFT_DOMAIN > /sys/kernel/debug/sched/features
```

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| sched_features | NUMA 并行调度 (PARAL) | 先 PARAL 后 SOFT_DOMAIN（可叠加） |
| sched_features | 窃取任务 (STEAL) | 先 SOFT_DOMAIN 后 STEAL |
| cgroup | Docker 协调突发 (cpu.soft_quota) | 无冲突，不同 cgroup 参数 |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-soft-domain-analysis_collect/result.md`（远端模式：**直接在远端机器上产出该文件**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、禁止在 agent 本地创建 `${WORK_DIR}` 目录），格式如下：

```markdown
# 分域调度分析结果

## 1. 环境检查

| 检查项 | 结果 |
|--------|------|
| ARCH | {aarch64/x86_64/...} |
| KERNEL_VER | {内核版本} |
| SOFT_DOMAIN_EXIST | {存在/不存在} |
| SOFT_DOMAIN_ENABLED | {已启用/未启用} |
| DEBUGFS_MOUNTED | {已挂载/未挂载} |
| SCHED_FEATURES_WRITABLE | {可写/不可写} |

## 2. NUMA 拓扑

| 指标 | 值 |
|------|-----|
| NUMA_NODES | {N} |
| CPU_PER_NUMA | {N} |

## 3. 场景特征

| 指标 | 值 |
|------|-----|
| CONTAINER_COUNT | {N} |
| SMALL_QUOTA_INSTANCES | {N} |
| TARGET_PID | {PID 或 "未指定"} |
| TARGET_CPU_AFFINITY_SPAN | {N} |
| LATENCY_SENSITIVE | {true/false} |

### 容器配额详情（如适用）

| 容器名 | 配额 CPU 数 | 小配额判定 |
|--------|-----------|-----------|
| {容器名} | {N} | ✅/❌ |

## 4. 适用性评估

| 评估维度 | 结果 | 证据 |
|---------|------|------|
| aarch64架构 | ✅/❌ | ARCH={值} |
| SOFT_DOMAIN特性存在 | ✅/❌ | sched_features 含/不含 SOFT_DOMAIN |
| SOFT_DOMAIN当前状态 | {已启用/未启用} | — |
| debugfs可写 | ✅/❌ | — |
| 多NUMA节点 | ✅/❌ | {N}个NUMA节点 |
| 小配额多实例 | ✅/❌ | {N}个容器配额≤{每节点CPU数} |
| 跨NUMA亲和性 | ✅/❌ | Cpus_allowed_list 跨越 {N} 个NUMA节点 |

**综合结论**: {适用/不适用/收益有限} — {原因}

**适用场景**: {容器模式/进程模式}

**预期收益**: {量化收益}

**建议操作**:
{操作步骤}

**调优前提**: 仅适用于 aarch64 架构，需 debugfs 可写

**回滚参考**: SOFT_DOMAIN_ORIG={NO_SOFT_DOMAIN 或 SOFT_DOMAIN}（记录原始状态）

## 5. 调优步骤推荐

> 仅在结论为"适用"时适用。

### 启用模式

{容器模式 / 进程模式}

### 使能命令

```bash
# 容器模式
bash scripts/soft_domain_tune.sh apply docker "{RECOMMENDED_WHITELIST}"

# 进程模式
bash scripts/soft_domain_tune.sh apply process <pid>
```

### 验证

```bash
grep SOFT_DOMAIN /sys/kernel/debug/sched/features
cat /sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain_nr_cpu
cat /sys/fs/cgroup/cpu/<cgroup>/cpu.soft_domain
```

### 回滚

```bash
bash scripts/soft_domain_tune.sh rollback
```

> **输出格式**：在报告末尾以独立段落输出，供调优技能解析：
>
> ```
> **RECOMMENDED_MODE**: docker
> **RECOMMENDED_WHITELIST**: mysql-ks|redis-ks
> ```

## 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "soft_domain",
  "suggestion": "写入 SOFT_DOMAIN 到 sched_features 总开关，对目标容器或进程 cgroup 写入 cpu.soft_domain_nr_cpu=<配额核数> 和 cpu.soft_domain=<NUMA编号>",
  "equivalence_class": "soft_domain",
  "activation_requirement": "immediate",
  "estimated_gain": {
    "primary_metric": "tail_latency_jitter",
    "severity": "high",
    "description": "减少跨NUMA调度开销，降低尾延迟抖动30%-50%；提高容器内CPU亲和性和缓存命中率"
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
> - **环境不支持但场景匹配（SB-06）**：当 `SOFT_DOMAIN_UNSUPPORTED_GAP` 非空且 S2/S3 命中时，`applicability` 设为 `"limited_benefit"`，`suggestion` 须以前缀 `[当前系统不支持（{具体缺口原因}），需 {升级内核 / 挂载 debugfs} 后方可实施] ` 标注支持缺口
> - activation_requirement 字段保持当前模板中预设的值，无需修改。
```

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-soft-domain-analysis"
input:
  analysis_dir: "[actual analysis_dir]"
  data_dir: "[actual data_dir]"
  collect_dir: "[actual collect_dir]"
output:
  analysis_report_path: "[actual analysis_report_path]"
constraints_acknowledged: [SB-01~SB-07]
