---
name: "opentunex-dynamic-smt-tuning"
description: "动态SMT调优建议。基于瓶颈分析结果，生成设置sched_util_ratio并启用KEEP_ON_CORE特性的调优建议报告，在低负载时智能分配计算资源提升性能。**必须使用此技能**：当瓶颈分析显示CPU利用率低、SMT超线程已启用、需要动态SMT调优时。触发关键词：dynamic_smt_tune、KEEP_ON_CORE、sched_util_ratio、超线程优化、低负载优化、SMT。"
---

# opentunex-dynamic-smt-tuning（动态 SMT 调优）

## 目标

根据分析结果或用户指定参数，安全地启用或回退动态 SMT（同步多线程）配置。核心目标是在系统负载较低时，通过智能分配计算资源来提升系统性能。

**调优原理**：该特性生效分两层：

1. 将 `sched_util_ratio` 写入 `/proc/sys/kernel/sched_util_ratio`，控制调度器利用率比例阈值；
2. 向 `sched_features` 写入 `KEEP_ON_CORE`，启用核心保持策略，减少不必要的线程迁移。

---

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含动态SMT相关分析结论的 `result.md` 文件
- **查找命令示例**：
```bash
# 远端模式: ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name \"result.md\" ..." 在远端执行；本地模式直接执行
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "dynamic_smt\|KEEP_ON_CORE\|sched_util_ratio\|SMT\|超线程" {} \; | head -1)
```
- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/...`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/dynamic-smt-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行**调优命令（遵守 T-01/T-02）：`bash scripts/dynamic_smt_tune.sh ...` 与 `echo X > /sys/...` 等命令出现在生成的脚本/报告中，由**用户确认后在远端服务器上执行**；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| 瓶颈分析结果数据 | 是 | 包含 CPU 使用率、SMT 超线程状态、KEEP_ON_CORE 特性支持的环境检查和适用性评估结论 |

**前置校验**：如果适用性评估结论为"不适用"或"收益有限"，不应执行调优。

如果用户未提供评估结论，应先引导用户完成动态 SMT 适用性评估。

### 来自场景分析 skill 的推荐参数

场景分析 skill 在中间态报告中输出推荐参数，格式如下：

```yaml
dynamic_smt_tune:
  enabled: true
  action: enable         # enable / disable
  threshold: 80          # 0-100 的整数，默认 100
```

### 用户直接提供的参数

| 参数 | 说明 | 必填 | 默认值 |
|------|------|------|--------|
| `action` | 操作类型：`enable` 或 `disable` | 是 | `enable` |
| `threshold` | 利用率阈值百分比（0-100），仅在 `action=enable` 时有效 | 否 | `100` |

---

## 调优参数说明

### sched_util_ratio

| 属性 | 说明 |
|------|------|
| 参数路径 | `/proc/sys/kernel/sched_util_ratio` |
| 取值范围 | 0-100 的整数 |
| 默认值 | 100（表示几乎不做限制） |
| 适用场景 | 系统 CPU 利用率低、希望智能分配计算资源时 |
| 注意事项 | 较低的值（如 50-70）会让调度器更激进地聚集任务到更少的核心上 |

### KEEP_ON_CORE 特性

| 属性 | 说明 |
|------|------|
| 参数路径 | `/sys/kernel/debug/sched/features` 或 `/sys/kernel/debug/sched_features` |
| 启用值 | `KEEP_ON_CORE` |
| 关闭值 | `NO_KEEP_ON_CORE` |
| 默认值 | 取决于内核编译配置 |
| 适用场景 | 与 `sched_util_ratio` 配合使用，在低负载时保持线程在核心上，减少不必要的迁移 |
| 注意事项 | 需内核编译时包含 `KEEP_ON_CORE` 调度特性 |

---

## 技能调用方法

### 基础脚本调用

```bash
# 本地路径：定位基础脚本源文件用（skill 目录在 agent 主机上）；远端模式拷贝目标为远端 ${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/
cd skills/optimization/opentunex-scenario-tuning/opentunex-dynamic-smt-tuning

# 环境检查
bash scripts/dynamic_smt_tune.sh check

# 使能动态SMT（默认阈值 100）
bash scripts/dynamic_smt_tune.sh apply

# 使能动态SMT（指定阈值 80）
bash scripts/dynamic_smt_tune.sh apply 80

# 查看当前状态
bash scripts/dynamic_smt_tune.sh status

# 回退
bash scripts/dynamic_smt_tune.sh rollback
```

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── dynamic_smt_tune.sh    # 基础脚本（从本技能 scripts/ 复制）
```

### 动态参数（用于协调器生成 tuning.sh）

协调器生成 `tuning.sh` 时需要以下参数（由本技能输出契约 `output.summary` 字段提供）：

| 参数 | 含义 | 来源 |
|------|------|------|
| threshold | sched_util_ratio 推荐值 | 瓶颈分析结果 |

### 报告中的脚本路径

- `${WORK_DIR}/tuning/intermediate/dynamic-smt-tuning.md` — 中间态调优建议
- `scripts/dynamic_smt_tune.sh` — 执行脚本（技能内）

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从 &lt;report_dir&gt; 目录读取瓶颈分析报告 result.md。

#### Step 1.2: 前置检查

| 校验项 | 规则 | 失败处理 |
|--------|------|----------|
| root 权限 | `$EUID -eq 0` | 提示错误并退出 |
| `sched_features` 可写 | 探测 `/sys/kernel/debug/sched_features` 和 `/sys/kernel/debug/sched/features` 至少一个可写 | 提示错误并退出 |
| `sched_util_ratio` 可写 | `/proc/sys/kernel/sched_util_ratio` 存在且可写 | 提示错误并退出 |
| `threshold` 合法性 | 0-100 之间的整数 | 提示错误并退出 |

### Phase 2: 生成中间态调优建议

#### 2.1 使能流程（enable）

```
备份 /proc/sys/kernel/sched_util_ratio -> ${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak
    │
    ├── 写入 sched_util_ratio = threshold
    │
    ├── 检查 KEEP_ON_CORE 当前状态
    │       ├── 已启用 → 跳过
    │       └── 未启用 → echo KEEP_ON_CORE > sched_features
    │
    └── 输出: "Enabled dynamic_smt_tune with threshold=XX"
```

#### 2.2 回退流程（disable）

```
关闭 KEEP_ON_CORE 特性
    │   echo NO_KEEP_ON_CORE > sched_features
    │
    ├── 检查 ${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak 是否存在
    │       ├── 存在 → 恢复原始值到 /proc/sys/kernel/sched_util_ratio
    │       └── 不存在 → 跳过
    │
    └── 输出: "Disabled dynamic_smt_tune, restored original sched_util_ratio if backup existed"
```

远端模式：上述 `${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak` 备份文件由生成的 tuning.sh 在远端服务器上创建/写入（用户在远端执行），agent 不得在本地创建这些文件。

#### 2.3 中间态调优建议

依据 `references/intermediate-report-template.md` 模板，生成结构化的中间态调优建议，包含：瓶颈点列表、调优手段、调优步骤命令、预期收益、回滚方案。

### Phase 3: 报告输出

- 输出路径：`<intermediate_path>/dynamic-smt-tuning.md`（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）
- 报告包含调优生效验证命令和期望结果

---

### oeaware 集成（可选）

```
若 oeawarectl 可用:
    enable  → oeawarectl -e dynamic_smt_tune
    disable → oeawarectl -d dynamic_smt_tune
否则 → 执行独立脚本
```

---

## 安全措施

| 措施 | 说明 |
|------|------|
| 文件可写性预检 | 操作前验证 `sched_features` 和 `sched_util_ratio` 可写 |
| 操作前自动备份 | `apply` 时自动备份 `sched_util_ratio` 当前值到 `${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak` |
| 应用阈值 | 将 `threshold` 写入 `/proc/sys/kernel/sched_util_ratio` |
| 执行计划预览 | `apply` 前输出将要执行的操作明细，等待用户确认 `(y/N)` |
| 状态备份 | 记录操作前的 `KEEP_ON_CORE` 状态和 `sched_util_ratio` 值到 `${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/backup_<ts>.lst` |
| 幂等操作 | 若 `KEEP_ON_CORE` 已启用则跳过写入，避免重复操作 |

远端模式：上述备份文件（`sched_util_ratio.bak`、`backup_<ts>.lst`）由生成的 tuning.sh 在远端服务器上创建/写入（用户在远端经 ssh 执行），agent 不得在本地创建这些文件。

---

## 产出

### 执行日志示例

```
=== 动态 SMT 使能 ===
threshold: 80
KEEP_ON_CORE 当前状态: disabled

=== 动态 SMT 执行计划 ===
1. 备份 /proc/sys/kernel/sched_util_ratio -> ${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak
2. 写入 sched_util_ratio = 80
3. 写入 KEEP_ON_CORE -> /sys/kernel/debug/sched_features

确认执行以上操作? (y/N) y

  已备份 sched_util_ratio -> ${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak
  sched_util_ratio = 80
  KEEP_ON_CORE 已启用

Enabled dynamic_smt_tune with threshold=80
```

### 验证命令

```bash
# 检查 sched_util_ratio 当前值
cat /proc/sys/kernel/sched_util_ratio

# 检查 KEEP_ON_CORE 状态
grep -E 'KEEP_ON_CORE|NO_KEEP_ON_CORE' /sys/kernel/debug/sched/features
```

### 回滚方法

```bash
# 通过本 skill 回滚
bash scripts/dynamic_smt_tune.sh rollback

# 或通过 oeaware（如已集成）
bash scripts/dynamic_smt_tune.sh oeaware disable
```

---

## 冲突约束

### 与 sched_util_ratio 相关调优的冲突

KEEP_ON_CORE 与 sched_util_ratio 为配套参数，KEEP_ON_CORE 必须配合 sched_util_ratio 使用才能生效：

| 冲突维度 | 说明 |
|---------|------|
| 依赖关系 | KEEP_ON_CORE 依赖 sched_util_ratio 设定阈值；若 sched_util_ratio 未设置或为 100，KEEP_ON_CORE 几乎无效果 |
| 执行顺序 | 先设置 sched_util_ratio，再启用 KEEP_ON_CORE |
| 回滚顺序 | 先关闭 KEEP_ON_CORE，再恢复 sched_util_ratio |

### 与其他调优方向的协作

| 调优方向 | 冲突关系 | 处理策略 |
|---------|---------|----------|
| NUMA 并行调度 (PARAL) | 无直接冲突 | 可并行调优 |
| 分域调度 (SOFT_DOMAIN) | 无直接冲突 | 可并行调优 |
| 窃取任务 (STEAL) | 无直接冲突 | 可并行调优 |
| Docker 算力统筹 | 无直接冲突 | 可并行调优 |
| 网卡多路径 | 无直接冲突 | 可并行调优 |

### oeaware 集成

```bash
# 通过 oeaware 使能
bash scripts/dynamic_smt_tune.sh oeaware enable 90

# 通过 oeaware 禁用
bash scripts/dynamic_smt_tune.sh oeaware disable
```

生成的 oeaware 配置文件内容：

```yaml
# dynamic_smt 动态 SMT oeaware 插件配置
plugin: dynamic_smt_tune
enabled: true
parameters:
  threshold: 90
```

---

## 与场景分析 skill 的协作

本 skill 接收 `opentunex-dynamic-smt-analysis` 输出的中间态调优建议：

```
瓶颈分析 skill 输出:
  ${WORK_DIR}/tuning/intermediate/dynamic-smt-bottleneck.md
    └─ 推荐参数 (threshold)
          │
          ▼
本 skill:
  解析推荐参数 → 前置检查 → 使能/回退 → 输出执行日志
```

---

## 约束与限制

| 约束项 | 说明 |
|--------|------|
| root 权限 | 写入 `/proc/sys/kernel/sched_util_ratio` 和 `sched_features` 需 root 权限 |
| 内核支持 | 需内核编译时包含 `KEEP_ON_CORE` 调度特性 |
| threshold 范围 | 仅允许 0-100 整数，超出范围将被拒绝 |
| 回滚依赖 | 回退依赖 `apply` 时生成的 `${WORK_DIR}/tuning/opentunex-dynamic-smt-tuning/sched_util_ratio.bak` 备份文件；若无备份则仅关闭 `KEEP_ON_CORE` |

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-dynamic-smt-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
