# 窃取任务调优指南

启用窃取任务（stealtask）调度特性，让空闲CPU主动从繁忙CPU拉取任务，提升多核负载均衡效率。

**调优原理**：窃取任务是一种轻量级调度特性，通过向sched_features写入STEAL启用。启用后，空闲CPU可以主动从其他CPU的运行队列中"窃取"任务，提高任务调度成功率和CPU资源利用率。

## 强制约束

> 本指南遵守 [场景调优子技能共享约束](../common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本指南依据 [中间态建议模板](../intermediate-report-template.md) 生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含窃取任务调度相关分析结论的 `result.md` 文件
- **查找命令示例**：
```bash
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "STEAL\|stealtask\|窃取" {} \; | head -1)
```

---

## 输入约定

本指南的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| 瓶颈分析结果数据 | 是 | 包含窃取任务相关的环境检查、指标数据和适用性评估结论 |

**前置校验**：如果适用性评估结论为"不适用"或"收益有限"，不应生成调优建议。

如果用户未提供评估结论，应先引导用户完成窃取任务适用性评估。

---

## 调优参数说明

### STEAL 特性

| 项目 | 说明 |
|------|------|
| 特性含义 | 窃取任务调度特性，让空闲CPU主动从繁忙CPU的运行队列中拉取任务 |
| 启用方式 | 向 sched_features 写入 "STEAL"（所有版本通用） |
| 禁用方式 | 向 sched_features 写入 "NO_STEAL"（所有版本通用） |
| 适用架构 | 仅 aarch64 |
| 预期效果 | 提升多核负载均衡效率，提高任务调度成功率 |
| 前置条件 | 内核需启用 CONFIG_SCHED_STEAL 配置 |

### 版本判定

> STEAL 特性在不同内核版本上有不同的启用参数。通过 `sched_max_steal_count` sysctl 是否可用来判断版本：
> - **旧版本**：`sysctl kernel.sched_max_steal_count` 能正常输出数值
> - **新版本**：`sysctl kernel.sched_max_steal_count` 报错 `error: "kernel.sched_max_steal_count" is an unknown key`

### 旧版本参数（sched_steal_node_limit）

| 项目 | 说明 |
|------|------|
| 参数含义 | 限制 STEAL 特性跨 NUMA 节点窃取任务的范围 |
| 配置方式 | 在 `/boot/efi/EFI/openEuler/grub.cfg` 中添加启动项参数 `sched_steal_node_limit=<NUMA 节点数>` |
| 生效方式 | 需**重启宿主机**生效 |
| 风险等级 | 中（需重启） |
| 恢复方式 | 删除 grub.cfg 中的 `sched_steal_node_limit` 参数，重启宿主机 |

### 新版本（无需额外参数）

| 项目 | 说明 |
|------|------|
| 说明 | 新版本仅需启用 STEAL 即可，无需额外配置范围限制参数 |
| 启用方式 | `echo STEAL > /sys/kernel/debug/sched/features` |
| 生效方式 | **立即生效**，无需重启 |
| 风险等级 | 低 |
| 恢复方式 | `echo NO_STEAL > /sys/kernel/debug/sched/features` |

### 容器级别（group_steal，仅新版本支持）

| 项目 | 说明 |
|------|------|
| 特性含义 | 按 cgroup 粒度控制 steal_task 特性的启用 |
| 配置方式 | ① 在 `/boot/efi/EFI/openEuler/grub.cfg` 中添加启动项参数 `group_steal`；② 重启宿主机；③ `echo 1 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task` |
| 生效方式 | **宿主机级需重启**，**容器级立即生效** |
| 风险等级 | 中（需重启） |
| 恢复方式 | ① 删除 grub.cfg 中的 `group_steal` 参数；② 重启宿主机；③ `echo 0 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task` |

> **⚠️ 参数约束**：当前脚本 `stealtask_tune.sh` 不自动修改 cmdline/grub.cfg 参数，仅输出提示。如需配置旧版本 `sched_steal_node_limit` 或容器 `group_steal`，需手动修改并重启。

---

## 技能调用方法

### 基础脚本调用

本指南依赖 `scripts/stealtask-tuning/stealtask_tune.sh` 脚本完成调优操作。脚本支持以下操作：

| 操作 | 命令 | 说明 |
|------|------|------|
| 环境检查 | `bash scripts/stealtask-tuning/stealtask_tune.sh check` | 检查sched_features文件是否存在且可写 |
| 状态备份 | `bash scripts/stealtask-tuning/stealtask_tune.sh backup` | 备份当前STEAL状态和cmdline配置 |
| 应用调优 | `bash scripts/stealtask-tuning/stealtask_tune.sh apply` | 启用STEAL特性（cmdline需手动配置） |
| 查看状态 | `bash scripts/stealtask-tuning/stealtask_tune.sh status` | 查看当前STEAL状态和cmdline配置 |
| 回滚 | `bash scripts/stealtask-tuning/stealtask_tune.sh rollback` | 恢复最近一次备份的状态 |

> **⚠️ 说明**：调优报告中的"调优步骤"展示独立命令，目的是让用户了解具体做了什么操作、修改了哪些文件。实际执行时建议使用入口脚本 `tuning.sh`，脚本会自动完成环境检查、状态备份、调优执行、验证和回滚，并自适应 sched_features 路径。

---

## tuning.sh 动态生成说明

### 生成目的

根据最新的调优报告规范，每个调优方向的脚本需要组织为独立文件夹，包含：
- **入口脚本 `tuning.sh`**：动态生成，包含针对当前瓶颈的动态参数
- **基础脚本**：从 `scripts/` 目录复制的原始脚本

### 生成流程

1. **创建调优技能文件夹**：在报告输出目录下创建 `stealtask-tuning/` 文件夹
2. **复制基础脚本**：将 `scripts/stealtask-tuning/stealtask_tune.sh` 复制到该文件夹
3. **生成入口脚本 `tuning.sh`**：根据当前瓶颈分析结果，动态生成入口脚本

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# 窃取任务调优入口脚本
# 由调优技能根据瓶颈分析动态生成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 参数说明：STEAL特性无动态参数，启用即可
# sched_steal_node_limit: 需手动配置cmdline（仅部分内核需要）

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" check
        ;;
    apply)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" apply
        ;;
    status)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" status
        ;;
    rollback)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" rollback
        ;;
    container-apply)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" container-apply "$2"
        ;;
    container-rollback)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" container-rollback "$2"
        ;;
    container-status)
        bash "${SCRIPT_DIR}/stealtask_tune.sh" container-status "${2:-}"
        ;;
    *)
        echo "用法: $0 {check|apply|status|rollback|container-apply|container-rollback|container-status} [cgroup]"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./stealtask-tuning/tuning.sh` （相对于调优报告目录）

---

## 调优建议生成流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

```bash
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "STEAL\|stealtask\|窃取" {} \; | head -1)
if [ -n "$RESULT_FILE" ]; then
    cat "$RESULT_FILE"
```

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- CONCLUSION=不适用 → 终止
- CONFIG_SCHED_STEAL=未启用 → 终止，提示内核不支持
- STEAL_STATUS=已启用 → 终止，提示特性已启用

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| CONFIG_SCHED_STEAL | 启用/未启用 |
| STEAL特性支持 | 支持/不支持 |
| STEAL当前状态 | 已启用/未启用 |
| sched_steal_node_limit | 已配置/未配置 |
| STEAL内核版本 | 旧版本/新版本/未知 |

#### Step 1.2: 版本判定

> 通过瓶颈分析报告中 `STEAL_VERSION` 字段（或手动执行 `sysctl kernel.sched_max_steal_count`）确定内核版本类别：
> - **旧版本**：需配置 `sched_steal_node_limit` cmdline 参数 + 重启
> - **新版本**：直接 `echo STEAL > sched_features`，无需额外参数，无需重启
> - **新版本 + 容器**：可额外配置 `group_steal` cmdline 参数 + 重启 + cgroup cpu.steal_task

| 版本 | sched_steal_count 存在？ | 配置参数 | 是否需重启 |
|------|------------------------|---------|-----------|
| 旧版本 | 存在 | `sched_steal_node_limit=<N>` cmdline | ✅ 需重启 |
| 新版本（宿主机） | 不存在 | 无（仅 `echo STEAL > sched_features`） | ❌ 无需重启 |
| 新版本（容器） | 不存在 | `group_steal` cmdline + `cpu.steal_task=1` cgroup | ✅ 宿主机需重启 |

#### Step 1.3: 容器级 stealtask 触发判定

> 容器级别 `group_steal` 仅在**存在运行中容器且为新版本内核**时才有意义。根据分析报告中的 `CONTAINER_COUNT` 和 `STEAL_VERSION` 判断：

| 条件 | 推荐模式 | 说明 |
|------|---------|------|
| `CONTAINER_COUNT = 0` 或无容器数据 | 宿主机模式 | 无容器环境，统一启用宿主机级 steal |
| `CONTAINER_COUNT > 0` 且 `STEAL_VERSION = 新版本` 且用户关注特定容器 | 容器模式 (group_steal) | 仅对指定 cgroup 开启 steal_task，避免影响其他容器 |
| `CONTAINER_COUNT > 0` 但无差异化需求 | 宿主机模式（优先） | 所有进程统一使用 steal，简单高效；容器模式作为备选 |
| `STEAL_VERSION = 旧版本` | 宿主机模式 | 旧版本不支持 `cpu.steal_task` cgroup 接口 |

> **输出策略**：当 `CONTAINER_COUNT > 0` 且为**新版本**时，调优建议中应同时展示宿主机和容器两种启用路径，供用户根据实际场景选择。

---

### Phase 2: 生成中间态调优建议

依据 [中间态建议模板](../intermediate-report-template.md) 模板生成报告，按以下要求填充各字段：

#### 2.1 瓶颈点列表填充

从分析结果中提取以下信息填充表格：
- **瓶颈点**：根据窃取任务分析结论填写，如"CPU高负载下负载均衡效率低"
- **类别**：固定为"调度"
- **严重程度**：根据分析结果中的严重度填写
- **影响描述**：总结CPU负载不均衡对性能的影响
- **调优手段**：简短描述，如"启用STEAL特性"
- **调优步骤**：精简操作步骤，如"1.启用STEAL特性"
- **调优脚本**：填写 `./stealtask-tuning/tuning.sh`

#### 2.2 调优建议详情填充

**瓶颈证据**：从分析结果中提取窃取任务相关的指标数据，如：
- CPU负载不均衡程度
- 任务调度成功率
- STEAL特性支持状态

**影响分析**：说明CPU负载不均衡对业务的影响，如响应时间、吞吐量等

**调优手段**：与瓶颈点列表中的调优手段一致

**调优步骤**：根据 STEAL_VERSION 和可用场景选择命令。实际报告按以下结构填充：

---

**主方案**（根据 STEAL_VERSION 选择）：

**所有版本通用**：
```bash
# 启用STEAL特性（所有版本均需执行）
echo STEAL > /sys/kernel/debug/sched/features
```

**旧版本额外步骤**：
```bash
# 1. 编辑 /boot/efi/EFI/openEuler/grub.cfg，在启动项参数中添加 sched_steal_node_limit=4
# 2. 重启宿主机
```

**新版本（宿主机级别）额外步骤**：
```bash
# 新版本无需额外参数，只需启用 STEAL 即可
echo STEAL > /sys/kernel/debug/sched/features
```

---

**备选方案（容器级别 group_steal）**：

> **⚠️ 必须遵守**：仅当 `CONTAINER_COUNT > 0` 且 `STEAL_VERSION = 新版本` 时，报告中**必须**附加此备选方案小节。当用户关注特定容器的隔离调优、不希望影响宿主机其他进程时，可选择此备选方案替代宿主机级别方案。

```bash
# 1. 编辑 /boot/efi/EFI/openEuler/grub.cfg，在启动项参数中添加 group_steal
# 2. 重启宿主机
# 3. 对目标 cgroup 使能 steal_task
echo 1 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task
```

**备选方案调优脚本**：`./stealtask-tuning/tuning.sh container-apply <cgroup>`

---

**回滚方法**：根据实际执行的方案展示对应回滚命令。

**主方案回滚**：

**所有版本通用**：
```bash
# 禁用STEAL特性
echo NO_STEAL > /sys/kernel/debug/sched/features
```

**旧版本额外回滚**：
```bash
# 删除 grub.cfg 中的 sched_steal_node_limit 参数，重启宿主机
```

**备选方案回滚（容器级别）**：

> 仅当报告包含备选方案时展示此节。

```bash
# 关闭 cgroup cpu.steal_task
echo 0 > /sys/fs/cgroup/cpu/<cgroup>/cpu.steal_task
# 删除 grub.cfg 中的 group_steal 参数，重启宿主机
```

**备选方案回滚脚本**：`./stealtask-tuning/tuning.sh container-rollback <cgroup>`

---

**调优脚本**：填写 `./stealtask-tuning/tuning.sh apply`

**验证方法**：提供验证命令，确认调优是否生效

**条件性说明**：根据 STEAL_VERSION 选择对应版本的主方案。旧版本需重启，新版本宿主机级别无需重启。当 `CONTAINER_COUNT > 0` 且 `STEAL_VERSION = 新版本` 时，必须在报告中附加备选方案（容器级别 group_steal），供用户根据场景选用。

---

### Phase 3: 报告输出

将生成的中间态调优建议保存至：
```
${WORK_DIR}/tuning/intermediate/stealtask-tuning.md
```
**说明**：协调器将中间态建议写入 `${WORK_DIR}/tuning/intermediate/`，因此可通过 `${WORK_DIR}/tuning/intermediate/stealtask-tuning.md` 读取结果。

同时，在报告目录下创建调优脚本文件夹：
```
${WORK_DIR}/tuning/stealtask-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── stealtask_tune.sh      # 复制的基础脚本
```

**注意**：本文件是中间态数据，最终将由调优域入口汇总为一份完整的调优建议报告。

---

## 产出

| 产出项 | 说明 |
|--------|------|
| 调优建议报告 | 依据中间态模板生成的结构化报告 |
| 调优脚本文件夹 | 包含 tuning.sh 入口脚本和 stealtask_tune.sh 基础脚本 |
| 预期收益 | CPU资源利用率提升10%-20%，负载均衡速度提升30%-50% |
| 风险提示 | 仅适用于aarch64架构；部分内核需配置cmdline后重启 |
| 回滚方案 | 执行 `./stealtask-tuning/tuning.sh rollback` 恢复原状态 |

---

## 冲突约束

> **⚠️ 以下冲突约束由调优域入口统一处理，本指南无需处理。**

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|---------|
| 窃取任务调度特性优化 | numa并行感知调度特性优化 | sched_features | 串行：先numa并行感知调度，后窃取任务 |


---

## 契约输出

输出契约格式参见 [contract-spec.md](../contract-spec.md)，本指南特有字段：

```yaml
skill_name: "opentunex-stealtask-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
```