---
name: "opentunex-copy-user-tuning"
description: "copy_from_user 内核补丁调优建议。基于瓶颈分析结果，生成应用PR #22481内核补丁并启用CONFIG_ARM64_COPY_FROM_USER_OPT编译选项的调优指导报告，使用ldp/ldtp双字加载替代ldtr单寄存器指令，提升ARM64 Hisilicon CPU上数据拷贝热路径的内存带宽利用率。**必须使用此技能**：当瓶颈分析显示__arch_copy_to_user/__arch_copy_from_user热点占比高、存在>4KB大块读写、ARM64 Hisilicon支持CPU (partID > 0xd02) 时。触发关键词：copy_from_user、copy_to_user、__arch_copy、ldp、ldtp、LSUI、PR #22481、CONFIG_ARM64_COPY_FROM_USER_OPT、用户态拷贝热路径。"
---

# copy_from_user 内核补丁调优建议

应用 Hisilicon 内核补丁（PR #22481）启用 `CONFIG_ARM64_COPY_FROM_USER_OPT` 编译选项，使用 `ldp`/`ldtp` 双字加载指令替代默认的 `ldtr` 单寄存器搬运指令，提升 ARM64 Hisilicon CPU 在大规模数据拷贝场景下的内存带宽利用率。

**调优原理**：

| CPU 类型 | partID 范围 | 优化路径 |
|---------|-----------|---------|
| Hisilicon 优化 CPU（LINXICORE9100、HIP11、HIP12） | `partID > 0xd02`（>3330） | 大拷贝（≥4KB）切换到 `ldp` 双字加载指令 |
| 支持 FEAT_LSUI 的 ARMv8.9 CPU | — | 直接使用 `ldtp` 非特权双字加载，size 不受限 |

> **⚠️ 本调优方向不支持一键使能——需手工下载并应用内核补丁、修改编译配置、重编内核并重启。Agent 仅生成调优指导报告与检查脚本，不自动执行内核修改或重启。**

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含 copy_from_user / `__arch_copy` / ldp / ldtp 相关分析结论的 `result.md` 文件
- **查找命令示例**：

```bash
# 远端模式: ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name \"result.md\" ..." 在远端执行；本地模式直接执行
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "__arch_copy\|copy_from_user\|copy_to_user\|ldp\|ldtp\|LSUI\|CONFIG_ARM64_COPY_FROM_USER_OPT" {} \; | head -1)
```

- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/...`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/copy-user-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/copy-user-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行** 内核补丁应用 / 编译配置修改 / 内核重编 / 系统重启（遵守 T-01/T-02/T-04）：`bash scripts/copy_user_tune.sh check` 仅检查 CPU/内核/热点环境；补丁应用、内核编译、配置修改、服务器重启由**用户在远端服务器上手工完成**；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| copy_from_user 适用性评估结论 | 是 | 确认是否应执行调优。格式：适用/不适用/收益有限 + 原因分析 |
| CPU 架构与型号 | 是 | ARM64 + Hisilicon 支持 CPU（partID > 0xd02） |
| 热点函数信息 | 是 | `__arch_copy_to_user` / `__arch_copy_from_user` 占比与命中函数 |
| 大块读写信息 | 是 | 是否存在 size > 4KB 的拷贝调用 |

**前置校验**：如果适用性评估结论为"不适用"或"收益有限（环境不支持）"，不应生成调优建议。

如果用户未提供评估结论，应先引导用户完成 copy_from_user 优化适用性评估。

---

## 调优参数说明

### CONFIG_ARM64_COPY_FROM_USER_OPT 内核编译选项

| 项目 | 说明 |
|------|------|
| 含义 | 启用 `__arch_copy_from_user` 的 ldp/ldtp 双字加载优化 |
| 适用内核 | openEuler 内核（已加入 openeuler_defconfig） |
| 推荐值 | `CONFIG_ARM64_COPY_FROM_USER_OPT=y` |
| 设置方式 | 在内核源码 `.config` 中设置（或通过 `make menuconfig`） |
| 生效方式 | **重编内核并重启系统后生效** |
| 风险等级 | 中（涉及内核重编与系统重启） |
| 恢复方式 | 重新编译不含该选项的内核，或从 grub 启动菜单选择旧内核 |

### 内核补丁 PR #22481

| 项目 | 说明 |
|------|------|
| 补丁地址 | https://atomgit.com/openeuler/kernel/pull/22481 |
| 内容 | 引入 Hisilicon ldp/ldtp 双字加载路径，仅在支持的 CPU + size ≥ 4KB 时启用 |
| 适用内核 | openEuler kernel（已合入主干）；其他内核需 cherry-pick 或自行移植 |
| 风险等级 | 中（修改内核源码） |
| 恢复方式 | 移除补丁 + 重编内核；或从 grub 启动菜单选择旧内核 |

### 验证补丁/编译生效

| 检查项 | 命令/方法 | 期望结果 |
|--------|----------|----------|
| 内核选项已编译 | `grep CONFIG_ARM64_COPY_FROM_USER_OPT /boot/config-$(uname -r)` | `CONFIG_ARM64_COPY_FROM_USER_OPT=y` |
| 指令替换生效 | `perf record -g -- <业务负载> && perf script \| grep -E 'ldp\|ldtp'` | `__arch_copy_to_user`/`__arch_copy_from_user` 内出现 `ldp`/`ldtp` |
| 业务性能 | 业务监控 QPS / 延迟 | 拷贝密集场景 QPS 提升、延迟下降 |

> **说明**：最终确认以业务表现和 `ldp`/`ldtp` 指令出现为准；config 项出现仅表示编译选项启用，不保证运行时实际生效（需运行时分支命中）。

---

## 技能调用方法

### 基础脚本调用

本技能依赖 `scripts/copy_user_tune.sh` 脚本完成**环境检查与提示输出**（不做实际修改）。脚本支持以下操作：

| 操作 | 命令 | 说明 |
|------|------|------|
| 环境检查 | `bash scripts/copy_user_tune.sh check` | 验证 CPU 架构、partID、内核选项、热点函数 |
| 状态查询 | `bash scripts/copy_user_tune.sh status` | 输出当前 CPU/内核/补丁状态，作为补丁应用前后对比基线 |
| 补丁与编译指南 | `bash scripts/copy_user_tune.sh guide` | 输出应用补丁 + 修改编译选项 + 重编内核的完整步骤 |
| 验证检查 | `bash scripts/copy_user_tune.sh verify` | 重启后运行，输出内核选项验证 + 业务表现验证建议 |

> **⚠️ 说明**：所有脚本操作仅涉及 `lscpu`/`uname`/`grep`/`cat`/`dmesg` 等只读命令，不修改任何系统状态。内核补丁应用与重编必须由用户在服务器本地手工完成；agent 不尝试远程修改内核源码或触发内核重编。

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/copy-user-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── copy_user_tune.sh      # 基础脚本（从本技能 scripts/ 复制，只读检查工具）
```

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# copy_from_user 优化调优入口脚本
# 由调优技能根据瓶颈分析动态生成
# 注意：本技能不修改系统状态，内核补丁应用与重编必须由人工完成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析结果填充）
# CPU_MODEL_DESC: CPU 型号描述，如 "Kunpeng 920 (partID=0xd02)"
# PATCH_URL: 内核补丁地址，默认 PR #22481
# HOTSPOT_FUNCS: 命中的拷贝函数列表，如 "__arch_copy_from_user,__arch_copy_to_user"
# HOTSPOT_PERCENT: 热点占比
CPU_MODEL_DESC="<CPU_MODEL_DESC>"
PATCH_URL="<PATCH_URL>"
HOTSPOT_FUNCS="<HOTSPOT_FUNCS>"
HOTSPOT_PERCENT="<HOTSPOT_PERCENT>"

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/copy_user_tune.sh" check
        ;;
    status)
        bash "${SCRIPT_DIR}/copy_user_tune.sh" status
        ;;
    guide)
        bash "${SCRIPT_DIR}/copy_user_tune.sh" guide
        ;;
    verify)
        bash "${SCRIPT_DIR}/copy_user_tune.sh" verify
        ;;
    *)
        echo "用法: $0 {check|status|guide|verify}"
        echo "  check  - 环境检查（CPU架构 + partID + 内核选项 + 热点）"
        echo "  status - 状态查询（输出补丁应用前基线）"
        echo "  guide  - 输出补丁应用 + 重编内核操作指南"
        echo "  verify - 重启后验证（输出内核选项验证 + 业务表现建议）"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./copy-user-tuning/tuning.sh` （相对于调优报告目录）

> **重要提示**：报告中必须明确告知用户"内核补丁应用与重编不属于脚本执行范围，需由用户在服务器本地手工完成"。

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从协调器传入的融合报告数据中，查找与 copy_from_user 优化相关的瓶颈分析结论。

**需要提取的数据项**：

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| IS_ARM64 | 搜索 "ARM64\|aarch64" 关键词 | 否 |
| IS_HISILICON_SUPPORTED_CPU | 搜索 "Hisilicon\|partID > 0xd02" 关键词 | 否 |
| PART_ID_HEX | 搜索 "partID\|CPU part" 后的十六进制字符串 | 空 |
| IS_COPY_USER_HOTSPOT | 搜索 `__arch_copy` 关键词 | false |
| COPY_USER_FUNCS | 搜索 `__arch_copy_to_user` / `__arch_copy_from_user` 命中函数列表 | 空 |
| HOTSPOT_PERCENT | 搜索 "热点占比\|hotspot_percent" 后数值 | 0 |
| LARGE_COPY_DETECTED | 搜索 "LARGE_COPY\|>4KB" 关键词 | false |
| MAX_COPY_SIZE | 搜索 "MAX_COPY_SIZE" 后数值 | 0 |
| 适用性评估结论 | 搜索 "copy_from_user\|copy_user_opt" 相关的适用性评估结论 | 不适用 |

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- IS_ARM64=false → 终止，提示当前非 ARM64 架构，本调优方向不适用
- IS_HISILICON_SUPPORTED_CPU=false → 终止，提示当前 CPU 非支持的 Hisilicon 型号（partID ≤ 0xd02），本调优方向不适用
- IS_COPY_USER_HOTSPOT=false → 终止，提示未检测到 `__arch_copy` 热点，本调优方向无收益对象
- LARGE_COPY_DETECTED=false 且 hotspot 占比 < 3% → 终止（收益有限），提示 Hisilicon 路径仅对 ≥4KB 生效或热点占比过低

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| IS_ARM64 | 是/否 |
| PART_ID_HEX | 0xd02 / 0xd03 / ... |
| IS_HISILICON_SUPPORTED_CPU | 是/否 |
| 热点函数 | __arch_copy_from_user,__arch_copy_to_user |
| 热点占比 | 5.2% |
| 大块读写 | 是/否 |

---

### Phase 2: 生成中间态调优建议

依据 `references/intermediate-report-template.md` 模板生成报告，按以下要求填充各字段：

#### 2.1 瓶颈点列表填充

从分析结果中提取以下信息填充表格：
- **瓶颈点**：根据 copy_from_user 分析结论填写，如"ARM64 Hisilicon CPU + `__arch_copy_from_user` 热点 + 大块读写(>4KB)"
- **类别**：固定为"内核/内存"
- **严重程度**：根据分析结果中的严重度填写（high / medium / low）
- **影响描述**：总结 `__arch_copy` 在大块拷贝场景下的指令发射密度与带宽利用率
- **调优手段**：简短描述，如"应用内核补丁 PR #22481 启用 ldp/ldtp 双字加载"
- **调优步骤**：精简操作步骤，如"1.下载补丁 2.设置 CONFIG_ARM64_COPY_FROM_USER_OPT=y 3.重编内核 4.重启"
- **调优脚本**：填写 `./copy-user-tuning/tuning.sh`（仅 check/guide/verify，不修改内核）

#### 2.2 调优建议详情填充

**瓶颈证据**：从分析结果中提取 copy_from_user 相关的指标数据，如：
- CPU 型号与 partID
- `__arch_copy_from_user`/`__arch_copy_to_user` 热点占比
- 大块读写（>4KB）调用次数与最大 size
- 当前内核版本与 config 选项

**影响分析**：说明默认 `ldtr` 单寄存器搬运在大块拷贝场景下的影响：
- 指令发射密度高，CPU 微架构利用不足
- 内核拷贝密集业务（redis/rocksdb/网络协议栈）带宽下降
- 业务监控 QPS/延迟受影响

**调优手段**：与瓶颈点列表中的调优手段一致

**调优步骤**：展示**手工操作步骤**（不能使用 shell 命令自动化内核重编），让用户了解具体操作：

```text
1. 拉取 openEuler 内核源码（或在已有内核源码目录下）
   git clone https://gitee.com/openeuler/kernel.git
   cd kernel
   git checkout <目标内核版本分支>

2. 应用 PR #22481 补丁
   curl -L https://atomgit.com/openeuler/kernel/pull/22481.patch -o /tmp/22481.patch
   git am /tmp/22481.patch
   # 若 patch 已合入主干可跳过此步

3. 设置内核编译选项
   # 方法 A：编辑 .config 直接追加
   echo "CONFIG_ARM64_COPY_FROM_USER_OPT=y" >> .config
   # 方法 B：通过 menuconfig 勾选
   make menuconfig
   # 路径: Kernel Features → Enable ARM64 copy from user optimization

4. 编译并安装内核
   make -j$(nproc)          # 编译
   make modules_install     # 安装内核模块
   make install             # 安装内核到 /boot 并更新 grub
   # 或使用 rpm 包构建：make rpm-pkg

5. 重启系统加载新内核
   reboot

6. 重启后回到新内核，运行 ./copy-user-tuning/tuning.sh verify 验证
```

**调优脚本**：填写 `./copy-user-tuning/tuning.sh guide`（仅输出补丁应用与重编指南，不修改内核）

**验证方法**：提供重启后的验证命令，确认补丁/选项生效：
```bash
# 1. 验证内核选项已编译
grep CONFIG_ARM64_COPY_FROM_USER_OPT /boot/config-$(uname -r)
# 2. 验证运行时指令替换
perf record -g -- <业务负载>
perf script | grep -E '__arch_copy_(to|from)_user' | grep -E 'ldp|ldtp'
# 3. 观察业务 QPS / 延迟变化
```

**回滚方法**：通过 grub 启动菜单选择旧内核启动，并重编不含该补丁/选项的内核：
```text
1. 重启服务器，在 grub 启动菜单（启动时按 Esc/Shift）选择旧内核
2. 或在旧内核环境下，重新编译不含 PR #22481 / CONFIG_ARM64_COPY_FROM_USER_OPT 的内核并安装
```

> **特别说明**：本调优的回滚操作主要依赖 grub 启动菜单选择旧内核；`tuning.sh` 脚本不提供内核回滚能力。

---

### Phase 3: 报告输出

将生成的中间态调优建议保存至：（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）

```
${WORK_DIR}/tuning/intermediate/copy-user-tuning.md
```

同时，在报告目录下创建调优脚本文件夹：

```
${WORK_DIR}/tuning/copy-user-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── copy_user_tune.sh      # 复制的基础脚本（只读检查工具）
```

> **⚠️ 职责说明**：上述目录由协调器 `opentunex-scenario-tuning` 在步骤 4 创建，本子技能仅产出中间态建议，不负责脚本部署。

**注意**：本文件是中间态数据，最终将由调优域入口汇总为一份完整的调优建议报告。

---

## 产出

| 产出项 | 说明 |
|--------|------|
| 调优建议报告 | 依据中间态模板生成的结构化报告（含内核补丁应用与重编手工步骤） |
| 调优脚本文件夹 | 包含 tuning.sh 入口脚本和 copy_user_tune.sh 基础脚本（仅只读检查） |
| 补丁工单 | 报告中的"调优步骤"节包含完整的补丁地址与重编步骤，可直接交给内核维护工程师 |
| 预期收益 | `__arch_copy` 函数在 ≥4KB 拷贝场景下指令发射密度下降，内存带宽利用率提升，业务 QPS 提升 5%-20%（业务相关） |
| 风险提示 | 需重编内核与重启；补丁应用与重编不可由 agent 代为执行 |
| 回滚方案 | grub 启动菜单选择旧内核，或重编不含补丁的内核 |

---

## 冲突约束

> **⚠️ 以下冲突约束由调优域入口统一处理，本技能无需处理。**

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|----------|
| copy_from_user 内核补丁 | hisock 网络加速 | 不同层级优化 | 无冲突，可并行 |
| copy_from_user 内核补丁 | 内核重编操作 | 内核版本 | 串行：先 copy_user 补丁，后其他内核编译类操作 |

### 与其他调优方向的协作

| 调优方向 | 冲突关系 | 处理策略 |
|---------|---------|----------|
| NUMA 并行调度 (PARAL) | 无冲突 | 可并行 |
| 窃取任务 (STEAL) | 无冲突 | 可并行 |
| 分域调度 (SOFT_DOMAIN) | 无冲突 | 可并行 |
| 动态 SMT (KEEP_ON_CORE) | 无冲突 | 可并行 |
| BTB/TidCMP BIOS 调优 | 无冲突（均为不同优化层） | 可并行 |
| hisock 网络加速 | 无冲突（不同层级） | 可并行 |
| Docker 算力统筹 | 无冲突 | 可并行 |
| 网卡多路径 | 无冲突 | 可并行 |

---

## 与场景分析 skill 的协作

本 skill 接收 `opentunex-copy-user-analysis` 输出的中间态分析结论：

```
瓶颈分析 skill 输出:
  ${WORK_DIR}/analysis/opentunex-copy-user-analysis_collect/result.md
    ├─ IS_ARM64 (true/false)
    ├─ PART_ID_HEX (e.g. 0xd02)
    ├─ IS_HISILICON_SUPPORTED_CPU (true/false)
    ├─ IS_COPY_USER_HOTSPOT (true/false)
    ├─ HOTSPOT_PERCENT (e.g. 5.2)
    ├─ LARGE_COPY_DETECTED (true/false)
    ├─ MAX_COPY_SIZE (e.g. 65536)
    └─ 适用性结论 (applicable / not_applicable / limited_benefit)
          │
          ▼
本 skill:
  解析环境结论 → 前置检查 → 提示补丁/重编步骤 → 输出调优报告（手工操作）
```

---

## 约束与限制

| 约束项 | 说明 |
|--------|------|
| 调优前提检查结果 | ARM64 架构、partID > 0xd02、热点存在、大块读写（>4KB） |
| 调优步骤建议 | 补丁地址 + 编译选项 + 重编内核步骤（不通过 shell 自动执行） |
| 验证方法 | 重启后内核选项验证 + perf 指令验证 + 业务指标验证 |
| 回滚方案 | grub 启动菜单选择旧内核 |
| 预期收益 | 大块拷贝场景下指令发射密度下降，内存带宽利用率提升 |
| 风险提示 | 需重编内核与重启；补丁应用与重编不可由 agent 代为执行；agent 不会通过 ssh 远程修改内核源码或触发内核重编 |
| 回滚方案 | grub 启动菜单选择旧内核，或重编不含该补丁/选项的内核 |

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-copy-user-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-05]
```