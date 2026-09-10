---
name: "opentunex-docker-coordination-burst-tuning"
description: "Docker算力统筹调优建议。基于瓶颈分析结果，生成启用sched_soft_runtime_ratio并设置容器cpu.soft_quota=1的调优建议报告，让高负载容器在宿主机空闲时借用额外CPU时间片提升突发性能。触发:Docker CPU限流、容器CPU瓶颈、容器突发负载、cfs_burst、sched_soft_runtime_ratio。"
---

# Docker 算力统筹调优建议

当系统有空闲 CPU 资源时，让高负载 Docker 容器"借用"额外时间片，提升突发性能。通过设置全局内核参数 `sched_soft_runtime_ratio` 并启用容器的 cgroup `cpu.soft_quota`，允许容器临时突破硬限制。

**调优原理**：`sched_soft_runtime_ratio` 控制调度器允许任务超出其硬配额的比例（百分比）。当宿主机有空闲 CPU 时，设置 `cpu.soft_quota=1` 的容器可以临时使用超出 `cpu.cfs_quota_us` 限制的 CPU 时间，上限为 `quota * (1 + ratio/100)`。

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

---

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| Docker算力统筹适用性评估结论 | 是 | 确认是否应执行调优。格式：建议启用/不建议启用/无需启用/环境不支持 + 原因分析 |
| 建议操作容器列表 | 否 | 瓶颈分析中识别出的建议启用 burst 的容器 ID 列表 |

**前置校验**：如果适用性评估结论为"不建议启用"、"无需启用"或"环境不支持"，不应执行调优，应向用户说明原因。

如果用户未提供评估结论，应先引导用户完成 Docker 算力统筹适用性评估。

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/...`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/docker-coordination-burst-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/docker-coordination-burst-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行**调优命令（遵守 T-01/T-02）：`bash scripts/docker_coordination_burst.sh ...` 与 `echo X > /sys/...` 等命令出现在生成的脚本/报告中，由**用户确认后在远端服务器上执行**；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 调优参数说明

### sched_soft_runtime_ratio

| 属性 | 说明 |
|------|------|
| 参数路径 | `/proc/sys/kernel/sched_soft_runtime_ratio` |
| 取值范围 | 0-100 的整数 |
| 默认值 | 0（不启用） |
| 适用场景 | 宿主机有空闲 CPU、部分容器 CPU 使用率接近硬配额上限时 |
| 注意事项 | 仅在宿主机空闲时生效，不影响其他容器硬配额保障 |

### cpu.soft_quota

| 属性 | 说明 |
|------|------|
| 参数路径 | `/sys/fs/cgroup/cpu/<container>/cpu.soft_quota` |
| 取值范围 | 0（关闭）或 1（启用） |
| 默认值 | 0 |
| 适用场景 | 容器 CPU 使用率频繁达到硬配额上限，宿主机有空闲 CPU 时 |
| 注意事项 | 需先设置全局 `sched_soft_runtime_ratio` |

---

## 技能调用方法

### 基础脚本调用

```bash
# 本地路径：定位基础脚本源文件用（skill 目录在 agent 主机上）；远端模式拷贝目标为远端 ${WORK_DIR}/tuning/docker-coordination-burst-tuning/
cd skills/optimization/opentunex-scenario-tuning/opentunex-docker-coordination-burst-tuning

# 环境检查与备份
bash scripts/docker_coordination_burst.sh check
bash scripts/docker_coordination_burst.sh backup

# 对所有容器应用调优
bash scripts/docker_coordination_burst.sh apply

# 对指定容器应用调优
bash scripts/docker_coordination_burst.sh apply 20 <container_id> [container_id ...]

# 查看状态
bash scripts/docker_coordination_burst.sh status

# 回滚
bash scripts/docker_coordination_burst.sh rollback
```

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/docker-coordination-burst-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── docker_coordination_burst.sh  # 基础脚本（从本技能 scripts/ 复制）
```

### 动态参数（用于协调器生成 tuning.sh）

协调器生成 `tuning.sh` 时需要以下参数（由本技能输出契约 `output.summary` 字段提供）：

| 参数 | 含义 | 来源 |
|------|------|------|
| ratio | sched_soft_runtime_ratio 推荐值 | 瓶颈分析结果 |
| container_ids | 容器 ID 列表 | 瓶颈分析结果 |

### 报告中的脚本路径

- `${WORK_DIR}/tuning/intermediate/docker-coordination-burst-tuning.md` — 中间态调优建议
- `scripts/docker_coordination_burst.sh` — 执行脚本（技能内）

---

## 调优执行流程

### Phase 1: 调优前提检查

### Step 1.1: 读取分析结果数据

从协调器传入的融合报告数据中，查找与 Docker 算力统筹相关的瓶颈分析结论。

**需要提取的数据项**：

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| 内核 burst 支持 | 搜索 "sched_soft_runtime_ratio" 关键词：存在 → 支持；不存在 → 不支持 | 不支持 |
| 宿主机负载状态 | 搜索 "宿主机" 和 "负载" 相关描述：包含 "低负载"/"空闲" → 低负载；包含 "高负载" → 高负载 | 高负载 |
| 建议启用结论 | 搜索 "Docker Coordination Burst" 或 "docker-coordination-burst" 相关的适用性评估结论 | 不建议启用 |
| 建议操作容器列表 | 搜索推荐启用 burst 的容器 ID 列表 | 空 |

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- 结论=环境不支持 → 终止调优，提示内核不支持 `sched_soft_runtime_ratio`
- 结论=不建议启用 → 终止调优，提示宿主机负载高不适合
- 结论=无需启用 → 终止调优，提示当前状态良好
- 结论=无需额外操作 → 终止调优，提示所有高负载容器已启用 burst

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| 内核 burst 支持 | 支持/不支持 |
| 宿主机负载状态 | 高负载/低负载 |
| 建议操作容器数 | N |

---

## Phase 2: 调优建议报告生成

**目标**：依据瓶颈分析结果，生成完整的 Docker 算力统筹调优建议报告。

**报告模板**：依据 [中间态建议模板](../../references/intermediate-report-template.md) 生成报告。

### 2.1 报告内容

#### 2.1.1 系统瓶颈摘要

| 编号 | 瓶颈点 | 类别 | 严重程度 | 影响描述 |
|------|--------|------|----------|----------|
| BN-001 | 容器 CPU 受限，宿主机有空闲算力 | 容器 | 高 | 容器因 CPU 硬配额限制无法利用宿主机空闲 CPU，突发性能受限 |

#### 2.1.2 调优建议详情

**瓶颈证据**：
- [从分析结果中提取的宿主机 CPU 使用率和容器 CPU 使用率数据]
- 宿主机 CPU 负载低（如：≤45%），有空闲算力
- 部分容器 CPU 使用率接近或达到硬配额上限（如：>95%）

**调优步骤**：

> **⚠️ 以下调优脚本供用户参考，由用户确认后自行执行。Agent 不得自动执行调优操作。**
> 脚本自动完成环境检查、状态备份、调优执行、验证和回滚，并自适应探测容器 cgroup 路径。

##### 步骤 0: 环境检查与状态备份

```bash
bash scripts/docker_coordination_burst.sh check
bash scripts/docker_coordination_burst.sh backup
```

##### 步骤 1: 设置全局 sched_soft_runtime_ratio 并启用容器 soft_quota

| 项目 | 内容 |
|------|------|
| 调优方法 | 设置全局 `sched_soft_runtime_ratio` + 为容器启用 `cpu.soft_quota=1` |
| 当前值 | ratio=[从系统读取]，soft_quota=0（未启用） |
| 建议值 | ratio=20, soft_quota=1 |
| 预期效果 | 高负载容器在宿主机空闲时可临时突破硬配额上限，提升突发性能 |
| 风险等级 | 低（仅在宿主机空闲时生效，不影响其他容器硬配额保障） |

**建议操作命令**（需用户确认后执行）：

对所有容器：
```bash
bash scripts/docker_coordination_burst.sh apply
```

对指定容器（替换 `<container_id>` 为实际 ID）：
```bash
bash scripts/docker_coordination_burst.sh apply 20 <container_id> [container_id ...]
```

**验证方法**：
```bash
bash scripts/docker_coordination_burst.sh status
```

**期望验证结果**：

| 验证项 | 期望值 |
|--------|--------|
| sched_soft_runtime_ratio | 20 |
| 目标容器 cpu.soft_quota | 1 |

**回滚方法**：
```bash
bash scripts/docker_coordination_burst.sh rollback
```

**执行顺序说明**：先设置全局 `sched_soft_runtime_ratio`，再为容器启用 `cpu.soft_quota`。如果容器 `cpu.soft_quota` 设置失败，不影响全局参数（全局参数单独回滚）。

#### 2.1.3 执行计划

| 批次 | 调优步骤 | 前置条件 | 验证检查点 |
|------|---------|---------|-----------|
| 批次1 | 设置全局 sched_soft_runtime_ratio=20 | 内核支持 sched_soft_runtime_ratio | ratio=20 |
| 批次2 | 为目标容器启用 cpu.soft_quota=1 | 全局 ratio 已设置 | 目标容器 soft_quota=1 |

#### 2.1.4 风险提示与回滚方案

| 调优步骤 | 风险等级 | 回滚方法 |
|---------|---------|---------|
| 设置 sched_soft_runtime_ratio | 低 | `bash scripts/docker_coordination_burst.sh rollback` |
| 启用容器 soft_quota | 低 | `bash scripts/docker_coordination_burst.sh rollback` |

**回滚顺序**：脚本自动按序恢复（先容器 soft_quota，后全局 ratio）。

### Phase 3: 报告输出

- 输出路径：`<intermediate_path>/docker-coordination-burst-tuning.md`（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）
- 报告包含调优生效验证命令和期望结果

---

## 冲突约束

### 冲突分析

| 调优步骤A | 调优步骤B | 冲突资源 | 执行策略 |
|----------|----------|---------|---------|
| Docker 算力统筹调优 | OS内核CPU调度参数优化 | sched_soft_runtime_ratio | 串行：先 Docker 算力统筹，后 OS 调度参数 |

### 与其他调优方向的协作

| 调优方向 | 冲突关系 | 处理策略 |
|---------|---------|----------|
| NUMA 并行调度 (PARAL) | 无直接冲突 | 可并行调优 |
| 分域调度 (SOFT_DOMAIN) | 无直接冲突 | 可并行调优 |
| 窃取任务 (STEAL) | 无直接冲突 | 可并行调优 |
| 动态 SMT (KEEP_ON_CORE) | 无直接冲突 | 可并行调优 |
| 网卡多路径 | 无直接冲突 | 可并行调优 |

---

## 产出

本技能产出以下信息，写入 `${WORK_DIR}/tuning/intermediate/docker-coordination-burst-tuning.md`：（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）

| 产出项 | 说明 |
|--------|------|
| 调优前提检查结果 | 内核支持状态、宿主机负载状态、建议操作容器列表 |
| 调优步骤建议 | 全局 ratio 设置 + 容器 soft_quota 启用的具体命令（含实际 cgroup 路径） |
| 验证方法 | 调优生效验证命令和期望结果 |
| 回滚方案 | 逐步骤回滚命令 + 一键回滚脚本 |
| 冲突分析 | 与其他调优方向的资源冲突和执行策略 |

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-docker-coordination-burst-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
