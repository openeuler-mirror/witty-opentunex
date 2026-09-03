---
name: "opentunex-btb-tuning"
description: "BTB(分支目标缓冲)/TidCMP BIOS调优建议。基于瓶颈分析结果，生成在BIOS中禁用TidCMP消除线程分支预测记录隔离的调优指导报告，提升鲲鹏920新型号处理器上redis/mysql等关键业务的分支预测性能。**必须使用此技能**：当瓶颈分析显示鲲鹏920新型号 + redis/mysql关键进程运行中 + 存在分支预测记录隔离瓶颈、需要禁用TidCMP时。触发关键词：BTB、TidCMP、分支预测、分支预测记录隔离、920新型号、鲲鹏BIOS、BIOS PM Control。"
---

# BTB (TidCMP) 调优建议

在 BIOS 中关闭 TidCMP（线程分支预测记录隔离），消除鲲鹏 920 新型号处理器对 redis/mysql 等关键业务的分支预测隔离开销，提升分支预测命中率与吞吐量。

**调优原理**：鲲鹏 920 新型号处理器在启用 TidCMP 时会对线程的分支预测记录（BTB）进行隔离，导致 redis/mysql 等高频分支预测业务的 BTB 命中率下降。禁用 TidCMP 后，线程共享 BTB 资源，恢复正常的分支预测机制。

> **⚠️ 本调优方向不支持一键使能——需手工进入 BIOS 设置并重启服务器。Agent 仅生成调优指导报告与检查脚本，不自动执行任何修改。**

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含 BTB / TidCMP / 分支预测相关分析结论的 `result.md` 文件
- **查找命令示例**：

```bash
# 远端模式: ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name \"result.md\" ..." 在远端执行；本地模式直接执行
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "TidCMP\|BTB\|分支预测\|is_920_new_model\|bottleneck.*BTB" {} \; | head -1)
```

- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/...`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/btb-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/btb-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行** BIOS 修改与重启（遵守 T-01/T-02/T-04）：`bash scripts/btb_tune.sh check` 仅检查 CPU/进程环境；BIOS 设置修改与服务器重启由**用户在远端服务器上手工完成**；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| BTB/TidCMP 适用性评估结论 | 是 | 确认是否应执行调优。格式：适用/不适用/收益有限 + 原因分析 |
| 关键进程运行状态 | 是 | redis/mysql 是否在运行的判断结果 |
| CPU 型号信息 | 是 | 是否为鲲鹏 920 新型号（dmidecode processor ID 以 "20 D0" 开头） |

**前置校验**：如果适用性评估结论为"不适用"或"收益有限"，不应生成调优建议。

如果用户未提供评估结论，应先引导用户完成 BTB/TidCMP 适用性评估。

---

## 调优参数说明

### TidCMP BIOS 开关

| 项目 | 说明 |
|------|------|
| 含义 | 线程分支预测记录隔离开关，关闭后允许线程共享 BTB 资源 |
| 适用 CPU | 鲲鹏 920 新型号（dmidecode processor ID 以 "20 D0" 开头） |
| 推荐值 | **Disabled**（禁用 TidCMP） |
| 设置路径 | BIOS → `Advanced` → `Power And Performance Configuration` → `CPU PM Control` → `TidCMP` |
| 生效方式 | **保存 BIOS 设置并重启服务器后生效** |
| 风险等级 | 低（仅影响分支预测隔离行为，不影响核心调度） |
| 恢复方式 | 重新进入 BIOS，将 TidCMP 恢复为 `Enabled`，保存并重启 |

> **⚠️ 本调优方向不支持一键使能**——BIOS 设置必须由用户手工操作；agent 不尝试通过任何方式（包括 ipmi、redfish、ssh 进 BIOS）代为设置。

### 验证 BIOS 设置生效

| 检查项 | 命令/方法 | 期望结果 |
|--------|----------|----------|
| CPU 型号仍为 920 新型号 | `dmidecode -t processor \| grep "ID:"` | ID 字段以 "20 D0" 开头 |
| redis/mysql 关键进程仍在运行 | `ps -ef \| grep -E "redis-server\|mysqld"` | 进程存在 |
| 应用业务性能 | 业务监控 QPS/响应时间 | QPS 提升、延迟下降 |

> **说明**：TidCMP 开关无法从操作系统侧读取，只能通过重启后业务表现验证（perf 抓取中 `bhr` 命中率提升、QPS 提升等）。

---

## 技能调用方法

### 基础脚本调用

本技能依赖 `scripts/btb_tune.sh` 脚本完成**环境检查与提示输出**（不做实际修改）。脚本支持以下操作：

| 操作 | 命令 | 说明 |
|------|------|------|
| 环境检查 | `bash scripts/btb_tune.sh check` | 验证 CPU 型号是否为鲲鹏 920 新型号、redis/mysql 关键进程是否运行；输出一份可粘贴到操作员工单的检查报告 |
| 状态查询 | `bash scripts/btb_tune.sh status` | 输出当前 CPU 信息、关键进程、dmidecode ID，便于用户向 BIOS 工程师提单时附上证据 |
| BIOS 设置提示 | `bash scripts/btb_tune.sh guide` | 输出进入 BIOS 并禁用 TidCMP 的完整操作步骤（含菜单路径） |
| 验证检查 | `bash scripts/btb_tune.sh verify` | 重启后运行，输出环境状态 + 验证业务性能提升建议 |

> **⚠️ 说明**：所有脚本操作仅涉及 `dmidecode`/`lscpu`/`ps` 等只读命令，不修改任何系统状态。BIOS 设置必须由用户在服务器本地手工完成；agent 不尝试远程修改 BIOS。

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/btb-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── btb_tune.sh            # 基础脚本（从本技能 scripts/ 复制，只读检查工具）
```

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# BTB / TidCMP 调优入口脚本
# 由调优技能根据瓶颈分析动态生成
# 注意：本技能不修改系统状态，BIOS 设置必须由人工完成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析结果填充）
# CPU_MODEL_DESC: CPU 型号描述，如 "Kunpeng 920 新型号"
# KEY_PROCESS_LIST: 关键进程列表，如 "redis-server,mysqld"
CPU_MODEL_DESC="<CPU_MODEL_DESC>"
KEY_PROCESS_LIST="<KEY_PROCESS_LIST>"

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/btb_tune.sh" check
        ;;
    status)
        bash "${SCRIPT_DIR}/btb_tune.sh" status
        ;;
    guide)
        bash "${SCRIPT_DIR}/btb_tune.sh" guide
        ;;
    verify)
        bash "${SCRIPT_DIR}/btb_tune.sh" verify
        ;;
    *)
        echo "用法: $0 {check|status|guide|verify}"
        echo "  check  - 环境检查（CPU型号 + 关键进程）"
        echo "  status - 状态查询（输出 BIOS 设置工单所需证据）"
        echo "  guide  - 输出 BIOS 设置操作指南"
        echo "  verify - 重启后验证（输出业务表现验证建议）"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./btb-tuning/tuning.sh` （相对于调优报告目录）

> **重要提示**：报告中必须明确告知用户"BIOS 修改不属于脚本执行范围，需由用户在服务器本地手工完成"。

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从协调器传入的融合报告数据中，查找与 BTB/TidCMP 相关的瓶颈分析结论。

**需要提取的数据项**：

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| IS_KUNPENG | 搜索 "Kunpeng" 关键词：存在 → 鲲鹏；不存在 → 非鲲鹏 | 非鲲鹏 |
| IS_920_NEW_MODEL | 搜索 "920新型号\|20 D0" 关键词 | 否 |
| PART_ID | 搜索 `dmidecode.*ID:` 后的十六进制字符串 | 空 |
| REDIS_RUNNING | 搜索 "redis-server" 关键词 | false |
| MYSQL_RUNNING | 搜索 "mysqld\|mariadbd" 关键词 | false |
| 适用性评估结论 | 搜索 "BTB\|TidCMP\|分支预测" 相关的适用性评估结论 | 不适用 |

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- IS_KUNPENG=false → 终止，提示当前非鲲鹏平台，本调优方向不适用
- IS_920_NEW_MODEL=false → 终止，提示当前非鲲鹏 920 新型号，本调优方向不适用
- REDIS_RUNNING=false 且 MYSQL_RUNNING=false → 终止，提示未检测到关键进程，本调优方向无收益对象

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| IS_KUNPENG | 鲲鹏/非鲲鹏 |
| IS_920_NEW_MODEL | 是/否 |
| PART_ID | 20 D0 1F xx ... |
| 关键进程 | redis-server/mysqld（实际列表） |

---

### Phase 2: 生成中间态调优建议

依据 `references/intermediate-report-template.md` 模板生成报告，按以下要求填充各字段：

#### 2.1 瓶颈点列表填充

从分析结果中提取以下信息填充表格：
- **瓶颈点**：根据 BTB/TidCMP 分析结论填写，如"鲲鹏 920 新型号 + redis/mysql 关键业务的分支预测记录隔离"
- **类别**：固定为"BIOS/硬件"
- **严重程度**：根据分析结果中的严重度填写（如 high）
- **影响描述**：总结 TidCMP 隔离对 redis/mysql 分支预测性能的影响
- **调优手段**：简短描述，如"BIOS 禁用 TidCMP"
- **调优步骤**：精简操作步骤，如"1.进入 BIOS 2.导航至 CPU PM Control 3.TidCMP=Disabled 4.保存重启"
- **调优脚本**：填写 `./btb-tuning/tuning.sh`（仅 check/guide/verify，不修改系统）

#### 2.2 调优建议详情填充

**瓶颈证据**：从分析结果中提取 BTB/TidCMP 相关的指标数据，如：
- CPU 型号描述（鲲鹏 920 新型号）
- dmidecode processor ID（以 "20 D0" 开头）
- redis/mysql 关键进程运行情况
- 业务热点中分支预测相关函数（如有）

**影响分析**：说明 TidCMP 隔离对业务的影响，如：
- BTB 命中率下降
- 高频分支预测路径延迟上升
- redis/mysql 吞吐量下降，尾延迟上升

**调优手段**：与瓶颈点列表中的调优手段一致

**调优步骤**：展示**手工操作步骤**（不能使用 shell 命令自动化 BIOS 设置），让用户了解具体操作：

```text
1. 重启服务器，进入 BIOS 设置界面（启动时按 Del/F2 等进入键）
2. 导航至 Advanced → Power And Performance Configuration → CPU PM Control
3. 找到 TidCMP 选项，将值设置为 Disabled
4. 保存 BIOS 设置（Save & Exit），重启服务器
5. 重启后回到操作系统，运行 ./btb-tuning/tuning.sh verify 验证环境
```

**调优脚本**：填写 `./btb-tuning/tuning.sh guide`（仅输出 BIOS 操作指南，不修改 BIOS）

**验证方法**：提供重启后的验证命令，确认业务表现改善：
```bash
# 1. 验证 CPU 型号未变
bash scripts/btb_tune.sh status
# 2. 观察业务 QPS / 延迟变化（业务监控指标）
# 3. 如需量化 BTB 命中变化，可在业务高峰期前后采样 perf stat -e branch-misses
```

**回滚方法**：在 BIOS 中将 TidCMP 恢复为 Enabled，保存并重启：
```text
1. 重启服务器，进入 BIOS 设置界面
2. 导航至 Advanced → Power And Performance Configuration → CPU PM Control
3. 将 TidCMP 选项恢复为 Enabled
4. 保存 BIOS 设置，重启服务器
```

> **特别说明**：本调优的回滚操作与使能操作完全对称，均为 BIOS 手工操作。`tuning.sh` 脚本不提供 BIOS 回滚能力。

---

### Phase 3: 报告输出

将生成的中间态调优建议保存至：（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）

```
${WORK_DIR}/tuning/intermediate/btb-tuning.md
```

同时，在报告目录下创建调优脚本文件夹：

```
${WORK_DIR}/tuning/btb-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── btb_tune.sh            # 复制的基础脚本（只读检查工具）
```

> **⚠️ 职责说明**：上述目录由协调器 `opentunex-scenario-tuning` 在步骤 4 创建，本子技能仅产出中间态建议，不负责脚本部署。

**注意**：本文件是中间态数据，最终将由调优域入口汇总为一份完整的调优建议报告。

---

## 产出

| 产出项 | 说明 |
|--------|------|
| 调优建议报告 | 依据中间态模板生成的结构化报告（含 BIOS 手工操作步骤） |
| 调优脚本文件夹 | 包含 tuning.sh 入口脚本和 btb_tune.sh 基础脚本（仅只读检查） |
| BIOS 操作工单 | 报告中的"调优步骤"节包含完整的 BIOS 菜单路径，可直接交给机房操作员 |
| 预期收益 | redis/mysql 关键业务的 BTB 命中率提升、分支预测延迟降低、QPS 提升 5%-15%（业务相关） |
| 风险提示 | 需重启服务器；BIOS 修改不可由 agent 代为执行 |
| 回滚方案 | 在 BIOS 中恢复 TidCMP=Enabled 并重启 |

---

## 冲突约束

> **⚠️ 以下冲突约束由调优域入口统一处理，本技能无需处理。**

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|----------|
| BTB/TidCMP BIOS 调优 | 分域调度 (SOFT_DOMAIN) | 鲲鹏920 NUMA 调度 | 无冲突，可独立 |
| BTB/TidCMP BIOS 调优 | 窃取任务 (STEAL) | 鲲鹏920 调度特性 | 无冲突，可独立 |

### 与其他调优方向的协作

| 调优方向 | 冲突关系 | 处理策略 |
|---------|---------|----------|
| NUMA 并行调度 (PARAL) | 无冲突 | 可并行 |
| 窃取任务 (STEAL) | 无冲突 | 可并行 |
| 分域调度 (SOFT_DOMAIN) | 无冲突 | 可并行 |
| 动态 SMT (KEEP_ON_CORE) | 无冲突 | 可并行 |
| copy_user 内核补丁 | 无冲突 | 可并行 |
| hisock 网络加速 | 无冲突 | 可并行 |
| Docker 算力统筹 | 无冲突 | 可并行 |
| 网卡多路径 | 无冲突 | 可并行 |

---

## 与场景分析 skill 的协作

本 skill 接收 `opentunex-btb-analysis` 输出的中间态分析结论：

```
瓶颈分析 skill 输出:
  ${WORK_DIR}/analysis/opentunex-btb-analysis_collect/result.md
    ├─ IS_KUNPENG (true/false)
    ├─ IS_920_NEW_MODEL (true/false)
    ├─ PART_ID (dmidecode processor ID)
    ├─ REDIS_RUNNING (true/false)
    ├─ MYSQL_RUNNING (true/false)
    └─ 适用性结论 (applicable / not_applicable / limited_benefit)
          │
          ▼
本 skill:
  解析环境结论 → 前置检查 → 提示 BIOS 操作步骤 → 输出调优报告（手工操作）
```

---

## 约束与限制

| 约束项 | 说明 |
|--------|------|
| 调优前提检查结果 | 鲲鹏平台、920 新型号、redis/mysql 关键进程运行状态 |
| 调优步骤建议 | BIOS 菜单路径 + 操作步骤（不通过 shell 自动执行） |
| 验证方法 | 重启后 CPU 型号 + 关键进程 + 业务指标验证 |
| 回滚方案 | BIOS 反向操作 + 重启 |
| 预期收益 | 消除分支预测记录隔离，关键业务分支预测性能提升 |
| 风险提示 | 需重启服务器；BIOS 设置不可由 agent 代为执行；agent 不会通过 ipmi/redfish/ssh 等方式远程修改 BIOS |
| 回滚方案 | 在 BIOS 中将 TidCMP 恢复为 `Enabled` 并重启 |

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-btb-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-05]
```