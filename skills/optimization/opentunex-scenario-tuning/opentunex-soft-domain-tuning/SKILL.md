---
name: "opentunex-soft-domain-tuning"
description: "分域调度调优建议。基于瓶颈分析结果，生成启用SOFT_DOMAIN特性并配置cgroup软调度域参数的调优建议报告，降低跨NUMA调度与访存抖动（仅aarch64）。**必须使用此技能**：当瓶颈分析显示NUMA拓扑适合分域调度、存在小配额多实例容器/跨NUMA进程、需要启用SOFT_DOMAIN特性时。触发关键词：SOFT_DOMAIN、soft_domain、分域调度、软调度域、跨NUMA漫游、NUMA亲和、cgroup软域。"
---

# opentunex-soft-domain-tuning（分域调度）

## 目标

根据场景分析 skill 的输出（推荐参数）或用户直接提供的参数，安全地启用或回退 `soft_domain` 软调度域配置，将目标容器/进程限制在指定的软调度域内，降低跨 NUMA 调度与访存带来的抖动。

**调优原理**：该特性生效分两层：

1. 打开内核调度特性中的 `SOFT_DOMAIN` 总开关；
2. 对目标 cgroup 写入 `cpu.soft_domain_nr_cpu`（软域 CPU 宽度）和 `cpu.soft_domain`（目标 NUMA，从 1 开始编号）。

---

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含分域调度相关分析结论的 `result.md` 文件
- **查找命令示例**：
```bash
# 远端模式: ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name \"result.md\" ..." 在远端执行；本地模式直接执行
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "SOFT_DOMAIN\|soft_domain\|软调度域\|跨NUMA漫游\|NUMA亲和" {} \; | head -1)
```
- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/...`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/soft-domain-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/soft-domain-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行**调优命令（遵守 T-01/T-02）：`bash scripts/soft_domain_tune.sh ...` 与 `echo X > /sys/...` 等命令出现在生成的脚本/报告中，由**用户确认后在远端服务器上执行**；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| 瓶颈分析结果数据 | 是 | 包含 SOFT_DOMAIN 特性支持、NUMA 拓扑、容器/进程部署场景的环境检查、指标数据和适用性评估结论 |

**前置校验**：如果适用性评估结论为"不适用"、"收益有限"或"已启用"，不应执行调优。

如果用户未提供评估结论，应先引导用户完成分域调度适用性评估。

### 来自场景分析 skill 的推荐参数

场景分析 skill（如 `opentunex-soft-domain-analysis`）在中间态报告中输出推荐参数，格式如下：

---

## 调优参数说明

### SOFT_DOMAIN 特性开关

| 属性 | 说明 |
|------|------|
| 参数路径 | `/sys/kernel/debug/sched/features` |
| 启用值 | `SOFT_DOMAIN` |
| 关闭值 | `NO_SOFT_DOMAIN` |
| 默认值 | 取决于内核编译配置 |
| 适用场景 | aarch64 架构、NUMA 拓扑适合分域调度时 |
| 注意事项 | 需确认内核支持；写入前需验证文件存在且可写 |

### cpu.soft_domain_nr_cpu

| 属性 | 说明 |
|------|------|
| 参数路径 | `/sys/fs/cgroup/cpu/<container>/cpu.soft_domain_nr_cpu` |
| 取值范围 | `0 ~ 单 NUMA CPU 数`，0 表示使用容器配额自动计算 |
| 默认值 | 0（自动计算） |
| 适用场景 | 需要限制容器在指定 NUMA 节点的 CPU 数量时 |
| 注意事项 | docker 模式需容器有 CPU quota 配置 |

### cpu.soft_domain

| 属性 | 说明 |
|------|------|
| 参数路径 | `/sys/fs/cgroup/cpu/<container>/cpu.soft_domain` |
| 取值范围 | 1 ~ NUMA 节点数（从 1 开始编号） |
| 默认值 | 1（默认绑定 NUMA 节点 1） |
| 适用场景 | 指定容器绑定到哪个 NUMA 节点 |
| 注意事项 | 仅 aarch64 架构可用；需确认目标 NUMA 存在且在线 |

---

## 技能调用方法

### 基础脚本调用

```bash
# 本地路径：定位基础脚本源文件用（skill 目录在 agent 主机上）；远端模式拷贝目标为远端 ${WORK_DIR}/tuning/soft-domain-tuning/
cd skills/optimization/opentunex-scenario-tuning/opentunex-soft-domain-tuning

# 环境检查
bash scripts/soft_domain_tune.sh check docker myapp-SC
bash scripts/soft_domain_tune.sh check process "redis-*"

# 备份
bash scripts/soft_domain_tune.sh backup docker myapp

# 应用调优（CPU_NUM=0 时使用容器配额值）
bash scripts/soft_domain_tune.sh apply docker myapp          # 自动计算配额 CPU 数
bash scripts/soft_domain_tune.sh apply docker myapp 8        # 指定 8 核软域
bash scripts/soft_domain_tune.sh apply process "redis-*" 8   # 进程模式需指定 cp_num

# 查看状态
bash scripts/soft_domain_tune.sh status docker
bash scripts/soft_domain_tune.sh status process "redis-*"

# 回滚
bash scripts/soft_domain_tune.sh rollback
```

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/soft-domain-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── soft_domain_tune.sh    # 基础脚本（从本技能 scripts/ 复制）
```

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# 分域调度调优入口脚本
# 由调优技能根据瓶颈分析动态生成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析报告中的"调优参数推荐"节填充，必须使用分析结果中的实际值，不得使用占位符）
# RECOMMENDED_MODE: 来源为分析报告的 "RECOMMENDED_MODE" 字段 — docker 或 process
#   容器模式（S2 适用）→ docker；进程模式（S3 适用）→ process
# RECOMMENDED_WHITELIST: 来源为分析报告的 "RECOMMENDED_WHITELIST" 字段
#   容器模式 → 小配额容器名用 | 拼接（如 "mysql-ks|redis-ks"）
#   进程模式 → 目标进程名（如 "mysqld"）
# RECOMMENDED_CPU_NUM: 软域 CPU 宽度，0 表示使用容器配额自动计算
# RECOMMENDED_NUMA_ID: 目标 NUMA 节点 ID（从 1 开始编号），默认为 1
MODE="<RECOMMENDED_MODE>"
WHITELIST="<RECOMMENDED_WHITELIST>"
CPU_NUM="<RECOMMENDED_CPU_NUM>"
NUMA_ID="${RECOMMENDED_NUMA_ID:-1}"

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/soft_domain_tune.sh" check "${MODE}" "${WHITELIST}"
        ;;
    backup)
        bash "${SCRIPT_DIR}/soft_domain_tune.sh" backup "${MODE}" "${WHITELIST}"
        ;;
    apply)
        bash "${SCRIPT_DIR}/soft_domain_tune.sh" apply "${MODE}" "${WHITELIST}" "${CPU_NUM}"
        ;;
    status)
        bash "${SCRIPT_DIR}/soft_domain_tune.sh" status "${MODE}"
        ;;
    rollback)
        bash "${SCRIPT_DIR}/soft_domain_tune.sh" rollback
        ;;
    oeaware)
        bash "${SCRIPT_DIR}/soft_domain_tune.sh" oeaware "${2:-enable}" "${WHITELIST}" "${CPU_NUM}"
        ;;
    *)
        echo "用法: $0 {check|backup|apply|status|rollback|oeaware}"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./soft-domain-tuning/tuning.sh` （相对于调优报告目录）

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据并提取推荐参数

从 `result.md` 中读取瓶颈分析报告。**必须优先解析"## 5. 调优参数推荐"节中的字段**：

| 需要提取的字段 | 提取方法 | 默认值 |
|--------------|---------|--------|
| `RECOMMENDED_MODE` | 搜索 `RECOMMENDED_MODE` 行，取值 `docker` 或 `process` | —（**必填，缺失则报错**） |
| `RECOMMENDED_WHITELIST` | 搜索 `RECOMMENDED_WHITELIST` 行，取 `|` 分隔的容器名 或 单个进程名 | —（**必填，缺失则报错**） |

> **⚠️ `RECOMMENDED_MODE` 决定检查模式**：`docker` → 调用 `check docker "<whitelist>"`；`process` → 调用 `check process "<whitelist>"`。不得从 whitelist 值中自行判断模式。

#### Step 1.2: 参数校验

| 校验项 | 规则 | 失败处理 |
|--------|------|----------|
| `cpu_num` 范围 | `0 ~ 单 NUMA CPU 数`（通过 `lscpu` 或 `numactl` 获取） | 提示错误并退出 |
| 内核支持 | `sched_features` 文件中包含 `SOFT_DOMAIN` 关键字 | 提示"内核不支持"并退出 |
| `sched_features` 可写 | 测试文件存在且有写权限 | 提示错误并退出 |
| Docker 模式 | `docker ps` 中至少一个容器名匹配 `whitelist`；其 cgroup 下 `cpu.soft_domain` / `cpu.soft_domain_nr_cpu` 存在且可写 | 提示错误并退出 |
| Process 模式 | `ps` 中至少一个进程 `comm` 匹配 `whitelist`；根 cgroup `tasks` 可写 | 提示错误并退出 |

### Phase 2: 生成中间态调优建议

#### 2.1 使能流程（enable）

```
开启 SOFT_DOMAIN 总开关（若已开启则跳过）
    │
    ├── mode=docker
    │       │
    │       ├── 遍历所有匹配 whitelist 的容器
    │       ├── 读取 cpu.cfs_quota_us / cpu.cfs_period_us 计算配额 CPU 数
    │       ├── 若用户指定 cpu_num > 0，以指定值为准
    │       ├── 若未指定且无配额，跳过该容器
    │       ├── cpu_num 不超过单 NUMA CPU 限制
    │       ├── 写入 cpu.soft_domain_nr_cpu = nr_cpu
    │       └── 写入 cpu.soft_domain = 1（默认 NUMA=1，可后续扩展负载均衡策略）
    │
    └── mode=process
            │
            ├── 创建 /sys/fs/cgroup/cpu/soft_domain_<safe_name>
            ├── 写入 cpu.soft_domain_nr_cpu = cpu_num
            ├── 写入 cpu.soft_domain = 1
            └── 将所有匹配 PID 写入 cgroup 的 tasks 文件
```

#### 2.2 回退流程（rollback）

```
清空所有已修改的 cgroup 文件（写入 0）
    │
    ├── Docker 容器：遍历所有容器，写入 cpu.soft_domain=0, cpu.soft_domain_nr_cpu=0
    │
    ├── Process cgroup：将 PID 迁回根 cgroup (/sys/fs/cgroup/cpu/tasks)，删除 soft_domain_* 目录
    │
    └── 可选：关闭 SOFT_DOMAIN 总开关（写入 NO_SOFT_DOMAIN）
```

#### 2.3 中间态调优建议

依据 `references/intermediate-report-template.md` 模板，生成结构化的中间态调优建议，包含：瓶颈点列表、调优手段、调优步骤命令、预期收益、回滚方案。

### Phase 3: 报告输出

将生成的中间态调优建议保存至：（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）
```
${WORK_DIR}/tuning/intermediate/soft-domain-tuning.md
```

同时，在报告目录下创建调优脚本文件夹：
```
${WORK_DIR}/tuning/soft-domain-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── soft_domain_tune.sh    # 复制的基础脚本
```

> **⚠️ 职责说明**：上述目录由协调器 `opentunex-scenario-tuning` 在步骤 4 创建，本子技能仅产出中间态建议，不负责脚本部署。

---

## 安全措施

| 措施 | 说明 |
|------|------|
| 文件可写性预检 | 所有操作前通过 `test_cgroup_writable()` 测试目标文件存在并可写，失败则中止并提示 |
| 执行计划预览 | `apply` 前输出将要执行的操作明细（目标容器/进程列表、写入的值），等待用户确认 `(y/N)` |
| 操作前自动备份 | `apply` 在用户确认后自动执行 `backup`，保存当前 sched_features 状态和 cgroup 值到 `${WORK_DIR}/tuning/opentunex-soft-domain-tuning/backup_<ts>.lst` |
| 回滚脚本生成 | `apply` 成功后自动生成 `${WORK_DIR}/tuning/opentunex-soft-domain-tuning/rollback_soft_domain.sh`，可独立执行回滚 |
| 只改目标范围 | `rollback` 仅清空受影响的 cgroup 文件，不触碰无关配置 |

远端模式：上述备份/回滚文件（`backup_<ts>.lst`、`rollback_soft_domain.sh`）由生成的 tuning.sh / soft_domain_tune.sh 在远端服务器上创建/写入（用户在远端经 ssh 执行），agent 不得在本地创建这些文件。

---

## 产出

### 执行日志示例

```
=== 分域调度预检 ===
模式: docker
匹配模式: myapp
CPU宽度: 0 (0=使用配额值)
目标NUMA: 1
单NUMA CPU数: 64

1. 启用 SOFT_DOMAIN 总开关
2. 配置 Docker 容器 cgroup:
  myapp-prod(abc123def): nr_cpu=4, numa=1
  myapp-staging(def456abc): nr_cpu=4, numa=1

确认执行以上操作? (y/N) y

=== 执行调优 ===
1. 启用 SOFT_DOMAIN 总开关
   SOFT_DOMAIN 已启用，跳过
2. 配置 cgroup 软调度域参数
  myapp-prod(abc123def): soft_domain=1, nr_cpu=4
  myapp-staging(def456abc): soft_domain=1, nr_cpu=4
回滚脚本已生成: ${WORK_DIR}/tuning/opentunex-soft-domain-tuning/rollback_soft_domain.sh
  操作完成: enable docker mode, 3 containers configured

回滚方法: bash ${WORK_DIR}/tuning/opentunex-soft-domain-tuning/rollback_soft_domain.sh
```

### 回滚方法提示

```
1. 使用自动生成的回滚脚本：
   bash ${WORK_DIR}/tuning/opentunex-soft-domain-tuning/rollback_soft_domain.sh

2. 或通过本 skill 的 rollback 命令：
   bash scripts/soft_domain_tune.sh rollback

3. 或通过 oeaware（如已集成）：
   bash scripts/soft_domain_tune.sh oeaware rollback
```

---

## 冲突约束

### 与 NUMA 并行调度 (PARAL) 的冲突

SOFT_DOMAIN 与 PARAL 均为 NUMA 相关的调度特性：

| 冲突维度 | 说明 |
|---------|------|
| 作用范围 | SOFT_DOMAIN 作用于 cgroup 级软调度域，PARAL 作用于全局并行感知调度 |
| 冲突场景 | 若已启用 PARAL，SOFT_DOMAIN 可叠加启用进一步增强 NUMA 亲和控制 |
| 执行顺序 | 建议先启用 PARAL（全局并行感知），再启用 SOFT_DOMAIN（细粒度分域） |
| 回滚顺序 | 先回滚 SOFT_DOMAIN，再回滚 PARAL |

### 与其他调优方向的协作

| 调优方向 | 冲突关系 | 处理策略 |
|---------|---------|----------|
| 窃取任务 (STEAL) | 无直接冲突 | 可并行调优 |
| 动态 SMT (KEEP_ON_CORE) | 无直接冲突 | 可并行调优 |
| sched_util_ratio | 无直接冲突 | 可并行调优 |
| Docker 算力统筹 | 无直接冲突 | 可并行调优 |
| 网卡多路径 | 无直接冲突 | 可并行调优 |

### oeaware 集成

```bash
# 生成 /etc/oeAware/plugin/soft_domain.yaml 并使能
bash scripts/soft_domain_tune.sh oeaware enable myapp 0

# 禁用并删除配置
bash scripts/soft_domain_tune.sh oeaware rollback
```

生成的 oeaware 配置文件内容：

```yaml
# soft_domain 分域调度 oeaware 插件配置
plugin: soft_domain_tune
enabled: true
parameters:
  mode: "docker"
  whitelist: "myapp"
  cpu_num: 0
  numa_id: 1
```

---

## 与场景分析 skill 的协作

本 skill 接收 `opentunex-soft-domain-analysis` 输出的中间态调优建议：

```
瓶颈分析 skill 输出:
  ${WORK_DIR}/tuning/intermediate/soft-domain-bottleneck.md
    └─ 推荐参数 (mode, whitelist, cpu_num)
          │
          ▼
本 skill:
  解析推荐参数 → 参数校验 → 使能/回退 → 输出执行日志
```

---

## 约束与限制

| 约束项 | 说明 |
|--------|------|
| 调优前提检查结果 | SOFT_DOMAIN 支持状态、架构、NUMA 拓扑、候选容器/进程列表 |
| 调优步骤建议 | 启用 SOFT_DOMAIN 总开关 + 配置 cgroup 软调度域参数的具体命令（含实际 cgroup 路径） |
| 验证方法 | 调优生效验证命令和期望结果 |
| 回滚方案 | 逐步骤回滚命令 + 一键回滚脚本 |
| 冲突分析 | 与其他调优方向的资源冲突和执行策略 |
| 预期收益 | 跨 NUMA 调度比例降低 30%-50%，尾延迟抖动降低 20%-40% |
| 风险提示 | 仅适用于 aarch64 架构；需确认内核支持 SOFT_DOMAIN；docker 模式需容器有 CPU quota 配置 |
| 回滚方案 | 执行 `./soft-domain-tuning/tuning.sh rollback` 恢复原状态 |

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-soft-domain-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
