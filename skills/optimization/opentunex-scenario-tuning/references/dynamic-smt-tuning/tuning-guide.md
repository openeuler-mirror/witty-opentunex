# 动态 SMT 调优指南

## 目标

根据分析结果或用户指定参数，安全地启用或回退动态 SMT（同步多线程）配置。核心目标是在系统负载较低时，通过智能分配计算资源来提升系统性能。

**调优原理**：该特性生效分两层：

1. 将 `sched_util_ratio` 写入 `/proc/sys/kernel/sched_util_ratio`，控制调度器利用率比例阈值；
2. 向 `sched_features` 写入 `KEEP_ON_CORE`，启用核心保持策略，减少不必要的线程迁移。

---

## 强制约束

> 本指南遵守 [场景调优子技能共享约束](../common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本指南依据 [中间态建议模板](../intermediate-report-template.md) 生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含动态SMT相关分析结论的 `result.md` 文件
- **查找命令示例**：
```bash
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "dynamic_smt\|KEEP_ON_CORE\|sched_util_ratio\|SMT\|超线程" {} \; | head -1)
```
- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

## 输入约定

本指南的数据来源是**瓶颈分析结果**。

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
cd skills/optimization/opentunex-scenario-tuning

# 环境检查
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh check

# 使能动态SMT（默认阈值 100）
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh apply

# 使能动态SMT（指定阈值 80）
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh apply 80

# 查看当前状态
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh status

# 回退
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh rollback
```

---

## tuning.sh 动态生成说明

### 生成目的

生成一份独立的、可执行的 `tuning.sh` 调优脚本，供用户或 oeaware 插件在实际环境中执行。

### 生成流程

1. 读取瓶颈分析结果中的推荐参数（threshold）
2. 校验参数有效性（root 权限、sched_features 可写、sched_util_ratio 可写、threshold 范围）
3. 生成包含完整调优、验证、回滚逻辑的 bash 脚本

### 报告中的脚本路径

- `${WORK_DIR}/tuning/intermediate/dynamic-smt-tuning.md` — 中间态调优建议
- `scripts/dynamic-smt-tuning/dynamic_smt_tune.sh` — 执行脚本

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从 <report_dir> 目录读取瓶颈分析报告 result.md。

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

#### 2.3 中间态调优建议

依据 [中间态建议模板](../intermediate-report-template.md) 模板，生成结构化的中间态调优建议，包含：瓶颈点列表、调优手段、调优步骤命令、预期收益、回滚方案。

### Phase 3: 报告输出

- 输出路径：`<intermediate_path>/dynamic-smt-tuning.md`
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
# 通过本指南脚本回滚
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh rollback

# 或通过 oeaware（如已集成）
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh oeaware disable
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
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh oeaware enable 90

# 通过 oeaware 禁用
bash scripts/dynamic-smt-tuning/dynamic_smt_tune.sh oeaware disable
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

本指南接收 `opentunex-dynamic-smt-analysis` 输出的中间态调优建议：

```
瓶颈分析 skill 输出:
  ${WORK_DIR}/tuning/intermediate/dynamic-smt-bottleneck.md
    └─ 推荐参数 (threshold)
          │
          ▼
本指南:
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

输出契约格式参见 [contract-spec.md](../contract-spec.md)，本指南特有字段：

```yaml
skill_name: "opentunex-dynamic-smt-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
```