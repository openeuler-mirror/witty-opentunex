---
name: "opentunex-hisock-tuning"
description: "hisock 网络加速调优建议。基于瓶颈分析结果，生成编译内核samples/bpf下的hisock工具并加载eBPF加速策略的调优指导报告，绕过L2/L3 netfilter开销提升网络收发包吞吐。**必须使用此技能**：当瓶颈分析显示调用栈中存在nf_hook*热点、内核已启用CONFIG_HISOCK、存在高频netfilter瓶颈时。触发关键词：hisock、nf_hook、netfilter、eBPF加速、L2/L3绕过、hisock_cmd、bpf.o、连接跟踪加速、网络协议栈绕过。"
---

# hisock 网络加速调优建议

编译内核 `samples/bpf/hisock` 下的 `hisock_cmd` 控制程序与 `bpf.o` 加速字节码，使用 `hisock_cmd` 加载 eBPF 加速策略，将已建链目标数据流绕过 L2/L3 netfilter 钩子（连接跟踪、丢包策略、端口映射等），直接转发到 TCP 层（收包）或网卡设备（发包），降低网络协议栈开销。

**调优原理**：在网络收发包场景中，数据包经过数据链路层（L2）和网络层（L3）时，netfilter 钩子会引入额外开销。当 `nf_hook*` 函数出现在热点调用栈中时，表明 netfilter 处理已成为瓶颈。hisock 通过 eBPF 程序在协议栈入口将已建链目标数据流直接转发，绕过 L2/L3 的 netfilter 开销。

> **⚠️ 本调优方向不支持一键使能——需手工在内核源码目录编译 samples/bpf 工具，并由用户确认后加载 eBPF 策略。Agent 仅生成调优指导报告与编译辅助脚本，不自动执行内核编译或加载 eBPF。**

## 强制约束

> 本技能遵守 [场景调优子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本技能依据 `references/intermediate-report-template.md` 模板生成结构化的中间态调优建议。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含 hisock / nf_hook / netfilter 相关分析结论的 `result.md` 文件
- **查找命令示例**：

```bash
# 远端模式: ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name \"result.md\" ..." 在远端执行；本地模式直接执行
RESULT_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "hisock\|nf_hook\|netfilter\|bpf.o\|hisock_cmd" {} \; | head -1)
```

- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 是**远端服务器上**的路径：
  - 读取融合报告/分析结果：经 ssh 在远端读取（`ssh -q ${user}@${ip} "grep/cat <远端文件>"`），**禁止** scp 拷回本地；下方 `find ${WORK_DIR}/analysis/ ...` 等命令在远端模式下必须写为 `ssh ${user}@${ip} "find ${WORK_DIR}/analysis/ -name result.md ..."` 形式
  - 写入中间态建议/契约到 `${WORK_DIR}/tuning/...`：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端路径；**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - **本技能不创建脚本目录**：本技能仅产出中间态建议（`${WORK_DIR}/tuning/intermediate/hisock-tuning.md`）与输出契约；调优脚本目录 `${WORK_DIR}/tuning/hisock-tuning/` 由协调器 `opentunex-scenario-tuning` 在步骤 4 统一创建（从本技能 `scripts/` 复制基础脚本 + 生成 `tuning.sh`）。本技能**不再**负责脚本部署与入口脚本生成
  - 本技能**不执行** 内核 samples/bpf 编译 / eBPF 加载 / 内核模块挂载（遵守 T-01/T-02）：`bash scripts/hisock_tune.sh check` 仅检查内核配置、热点与编译依赖；`compile` 子命令需用户主动执行；`apply` 子命令加载 eBPF 也必须由用户在远端服务器上手工执行；agent 不通过 ssh 代执行
- **本地模式**（execution_mode=local）：`${WORK_DIR}` 为 agent 本地目录，脚本部署与文件操作为本地操作。
- 具体写法见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 输入约定

本技能的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| hisock 适用性评估结论 | 是 | 确认是否应执行调优。格式：适用/不适用/收益有限 + 原因分析 |
| 内核特性支持 | 是 | 内核是否启用 CONFIG_HISOCK |
| 热点函数信息 | 是 | `nf_hook*` 热点占比与命中函数 |
| 网络环境信息 | 否 | 主要物理网卡、cgroup 路径、监听端口等，用于 eBPF 加载参数 |

**前置校验**：如果适用性评估结论为"不适用"或"收益有限（环境不支持）"，不应生成调优建议。

如果用户未提供评估结论，应先引导用户完成 hisock 适用性评估。

---

## 调优参数说明

### CONFIG_HISOCK 内核选项

| 项目 | 说明 |
|------|------|
| 含义 | 启用 hisock 网络加速特性 |
| 适用内核 | openEuler 内核 |
| 推荐值 | `CONFIG_HISOCK=y`（编译进内核）或 `CONFIG_HISOCK=m`（编译为模块） |
| 启用方式 | 内核编译时启用 |
| 生效方式 | 重启系统加载含该选项的内核后生效 |
| 风险等级 | 中（需内核编译） |
| 恢复方式 | 重编不含该选项的内核并重启，或从 grub 启动菜单选择旧内核 |

### hisock_cmd 与 bpf.o

| 项目 | 说明 |
|------|------|
| 含义 | hisock 控制工具与 eBPF 加速字节码 |
| 来源 | 内核源码 `samples/bpf/hisock/` 目录 |
| 编译方式 | `make -C tools/lib/bpf -j$(nproc) && make -C samples/bpf -j$(nproc)` |
| 路径 | `samples/bpf/hisock/hisock_cmd`、`samples/bpf/hisock/bpf.o` |
| 风险等级 | 低（用户态工具，失败不影响内核） |
| 恢复方式 | `hisock_cmd -u` 卸载 eBPF |

### hisock_cmd 加载参数

| 参数 | 说明 | 必填 | 示例 |
|------|------|------|------|
| `-f <bpf.o>` | eBPF 字节码路径 | 是 | `./bpf.o` |
| `-c <cgroup路径>` | 加速的 cgroup 路径 | 是 | `/sys/fs/cgroup/perf_event/docker/abc123` |
| `-p <端口范围>` | 加速的端口（或端口范围） | 是 | `6379` 或 `6379-6380` |
| `-i <网卡设备>` | 加速的网卡名 | 是 | `enp46s0f0np0` |
| `-u` | 卸载已加载的加速 | 卸载时用 | — |

### 验证生效

| 检查项 | 命令/方法 | 期望结果 |
|--------|----------|----------|
| hisock_cmd 进程运行 | `ps aux \| grep hisock_cmd` | 进程存在 |
| nf_hook 热点占比下降 | `perf report \| grep nf_hook` | 占比 < 应用前基线 |
| 业务网络性能 | 业务监控 吞吐 / 丢包率 | 吞吐提升、丢包率下降 |

---

## 技能调用方法

### 基础脚本调用

本技能依赖 `scripts/hisock_tune.sh` 脚本完成**环境检查、编译辅助、加载/卸载**操作（其中 apply/unload 必须由用户主动触发）：

| 操作 | 命令 | 说明 |
|------|------|------|
| 环境检查 | `bash scripts/hisock_tune.sh check` | 验证 CONFIG_HISOCK、nf_hook 热点、编译工具链、cgroup 路径 |
| 状态查询 | `bash scripts/hisock_tune.sh status` | 输出当前内核选项、热点占比、网卡/cgroup/监听端口，作为加载前基线 |
| 编译辅助 | `bash scripts/hisock_tune.sh compile <内核源码路径>` | 在用户提供的内核源码目录下编译 hisock_cmd 与 bpf.o（用户主动执行） |
| 加载 eBPF | `bash scripts/hisock_tune.sh apply <bpf.o路径> <cgroup> <端口> <网卡>` | 加载 eBPF 加速策略（用户主动执行） |
| 卸载 eBPF | `bash scripts/hisock_tune.sh unload <cgroup> <网卡>` | 卸载已加载的加速（用户主动执行） |
| 操作指南 | `bash scripts/hisock_tune.sh guide` | 输出完整编译 + 加载操作指南 |

> **⚠️ 说明**：`compile`、`apply`、`unload` 子命令会修改系统状态（编译产物 / 加载 eBPF / 卸载 eBPF），必须由用户在远端服务器上手工运行；agent 不通过 ssh 代执行。

---

## tuning.sh 动态生成说明（参考：协调器执行）

> **⚠️ 职责说明**：本节为协调器 `opentunex-scenario-tuning` 生成入口脚本时使用的参考模板。**本子技能不执行此步骤**——脚本目录与 `tuning.sh` 由协调器统一创建（见协调器 SKILL.md 步骤 4）。本节保留是为了让子技能输出契约中的 `output.summary` 字段能准确说明脚本模板与基础脚本名，方便协调器引用。

### 入口脚本目录结构

协调器会按以下结构创建脚本目录：

```
${WORK_DIR}/tuning/hisock-tuning/
├── tuning.sh              # 入口脚本（动态生成）
└── hisock_tune.sh         # 基础脚本（从本技能 scripts/ 复制，含 check/compile/apply/unload）
```

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# hisock 网络加速调优入口脚本
# 由调优技能根据瓶颈分析动态生成
# 注意：本脚本只做环境检查与状态查询，apply/unload 必须由用户主动执行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析结果填充，必须使用分析结果中的实际值）
# KERNEL_SRC: 内核源码路径（用于编译 hisock 工具），用户需提供
# BPF_O: 编译产物 bpf.o 的目标路径（默认与 hisock_cmd 同目录）
# RECOMMENDED_CGROUP: 推荐的 cgroup 路径（来自分析结果）
# RECOMMENDED_PORTS: 推荐的端口范围（来自分析结果）
# RECOMMENDED_NIC: 推荐的网卡设备（来自分析结果）
KERNEL_SRC="<KERNEL_SRC>"
BPF_O="<BPF_O_PATH>"
RECOMMENDED_CGROUP="<RECOMMENDED_CGROUP>"
RECOMMENDED_PORTS="<RECOMMENDED_PORTS>"
RECOMMENDED_NIC="<RECOMMENDED_NIC>"

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/hisock_tune.sh" check
        ;;
    status)
        bash "${SCRIPT_DIR}/hisock_tune.sh" status
        ;;
    compile)
        # 编译 hisock 工具与 bpf.o（用户主动执行）
        bash "${SCRIPT_DIR}/hisock_tune.sh" compile "${KERNEL_SRC}"
        ;;
    apply)
        # 加载 eBPF 加速策略（用户主动执行，需先完成 compile）
        if [[ -z "${BPF_O}" || -z "${RECOMMENDED_CGROUP}" || -z "${RECOMMENDED_PORTS}" || -z "${RECOMMENDED_NIC}" ]]; then
            echo "错误: 缺少动态参数（BPF_O/RECOMMENDED_CGROUP/RECOMMENDED_PORTS/RECOMMENDED_NIC）"
            exit 1
        fi
        bash "${SCRIPT_DIR}/hisock_tune.sh" apply "${BPF_O}" "${RECOMMENDED_CGROUP}" "${RECOMMENDED_PORTS}" "${RECOMMENDED_NIC}"
        ;;
    unload)
        # 卸载 eBPF 加速（用户主动执行）
        bash "${SCRIPT_DIR}/hisock_tune.sh" unload "${RECOMMENDED_CGROUP}" "${RECOMMENDED_NIC}"
        ;;
    guide)
        bash "${SCRIPT_DIR}/hisock_tune.sh" guide
        ;;
    *)
        echo "用法: $0 {check|status|compile|apply|unload|guide}"
        echo "  check   - 环境检查（CONFIG_HISOCK + 热点 + 编译依赖）"
        echo "  status  - 状态查询（输出加载前基线）"
        echo "  compile - 编译 hisock_cmd + bpf.o（用户主动执行）"
        echo "  apply   - 加载 eBPF 加速（用户主动执行）"
        echo "  unload  - 卸载 eBPF 加速（用户主动执行）"
        echo "  guide   - 输出完整操作指南"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./hisock-tuning/tuning.sh` （相对于调优报告目录）

> **重要提示**：报告中必须明确告知用户"编译与 eBPF 加载操作不属于 agent 自动执行范围，必须由用户在服务器本地手工完成"。

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从协调器传入的融合报告数据中，查找与 hisock 网络加速相关的瓶颈分析结论。

**需要提取的数据项**：

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| IS_HISOCK_SUPPORTED | 搜索 "CONFIG_HISOCK" 关键词 | false |
| IS_NF_HOOK_HOTSPOT | 搜索 `nf_hook` 关键词 | false |
| NF_HOOK_FUNCS | 搜索 `nf_hook*` 命中函数列表 | 空 |
| NF_HOOK_PERCENT | 搜索 "热点占比\|hotspot_percent" 后数值 | 0 |
| NET_DEV_NAME | 搜索 "NET_DEV_NAME\|网卡设备" 关键词 | 空 |
| CGROUP_PATH | 搜索 "CGROUP_PATH\|cgroup" 关键词 | 空 |
| LISTEN_PORTS | 搜索 "LISTEN_PORTS\|监听端口" 关键词 | 空 |
| 适用性评估结论 | 搜索 "hisock" 相关的适用性评估结论 | 不适用 |

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- IS_HISOCK_SUPPORTED=false → 终止，提示当前内核未启用 CONFIG_HISOCK，本调优方向不适用
- IS_NF_HOOK_HOTSPOT=false → 终止，提示未检测到 nf_hook 热点，本调优方向无收益对象
- NF_HOOK_PERCENT < 1% → 警告（建议保留热路径），但仍可继续（用户决定）
- RECOMMENDED_CGROUP=空 或 RECOMMENDED_PORTS=空 或 RECOMMENDED_NIC=空 → 警告（无法直接生成加载命令），但仍可继续（用户需补充）

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| CONFIG_HISOCK | 启用/未启用 |
| NF_HOOK 热点函数 | nf_hook_slow, nf_hook_entries |
| NF_HOOK 占比 | 3.5% |
| 推荐 cgroup | /sys/fs/cgroup/perf_event/docker |
| 推荐端口 | 6379 |
| 推荐网卡 | enp46s0f0np0 |

---

### Phase 2: 生成中间态调优建议

依据 `references/intermediate-report-template.md` 模板生成报告，按以下要求填充各字段：

#### 2.1 瓶颈点列表填充

从分析结果中提取以下信息填充表格：
- **瓶颈点**：根据 hisock 分析结论填写，如"网络收发包场景中 netfilter 钩子 (nf_hook) 开销过高"
- **类别**：固定为"网络"
- **严重程度**：根据分析结果中的严重度填写（high / medium / low）
- **影响描述**：总结 netfilter 开销对网络吞吐与延迟的影响
- **调优手段**：简短描述，如"启用 hisock eBPF 加速绕过 L2/L3 netfilter"
- **调优步骤**：精简操作步骤，如"1.编译 hisock 工具 2.加载 bpf.o 3.验证热点下降"
- **调优脚本**：填写 `./hisock-tuning/tuning.sh`（check/compile/apply 等子命令）

#### 2.2 调优建议详情填充

**瓶颈证据**：从分析结果中提取 hisock 相关的指标数据，如：
- CONFIG_HISOCK=y/m
- `nf_hook_slow`/`nf_hook_entries` 占比
- 主要网卡、cgroup、监听端口

**影响分析**：说明 netfilter 开销对业务的影响，如：
- 网络吞吐下降、PPS 受限
- 连接跟踪表满导致丢包
- iptables 规则越多延迟越高

**调优手段**：与瓶颈点列表中的调优手段一致

**调优步骤**：展示**手工操作步骤 + 用户确认执行的脚本命令**：

```text
步骤 0: 环境检查（agent 生成时已验证）
   bash scripts/hisock_tune.sh check

步骤 1: 编译 hisock 工具（用户主动执行）
   # 准备内核源码（与当前运行内核版本一致）
   # 内核源码路径: ${KERNEL_SRC}
   bash scripts/hisock_tune.sh compile ${KERNEL_SRC}
   # 产物路径: ${KERNEL_SRC}/samples/bpf/hisock/{hisock_cmd,bpf.o}

步骤 2: 加载 eBPF 加速策略（用户主动执行）
   bash scripts/hisock_tune.sh apply ${BPF_O_PATH} ${RECOMMENDED_CGROUP} ${RECOMMENDED_PORTS} ${RECOMMENDED_NIC}
   # 示例：
   bash scripts/hisock_tune.sh apply /opt/hisock/bpf.o /sys/fs/cgroup/perf_event/docker/abc123 6379 enp46s0f0np0

步骤 3: 验证热点下降
   perf record -g -- <业务负载>
   perf report | grep nf_hook
   # 期望：nf_hook 占比 < 应用前基线
```

**调优脚本**：
- 检查: `./hisock-tuning/tuning.sh check`
- 编译: `./hisock-tuning/tuning.sh compile <KERNEL_SRC>`（用户执行）
- 加载: `./hisock-tuning/tuning.sh apply`（用户执行）

**验证方法**：提供验证命令，确认 hisock 生效：
```bash
# 1. 验证 hisock_cmd 进程运行
ps aux | grep hisock_cmd
# 2. 验证热点下降
perf record -g -- <业务负载>
perf report | grep nf_hook
# 3. 观察业务吞吐 / 延迟改善（业务监控指标）
```

**回滚方法**：执行卸载命令，停止 eBPF 加速：
```bash
# 方式 A：通过脚本（推荐）
bash scripts/hisock_tune.sh unload <CGROUP_PATH> <NET_DEV_NAME>
# 示例：
bash scripts/hisock_tune.sh unload /sys/fs/cgroup/perf_event/docker/abc123 enp46s0f0np0

# 方式 B：直接调用 hisock_cmd
<BPF_O_PATH_DIR>/hisock_cmd -u -c <CGROUP_PATH> -i <NET_DEV_NAME>
```

> **特别说明**：hisock 的回滚操作可由脚本完成（仅卸载 eBPF，不涉及内核修改），但仍需用户主动执行。

---

### Phase 3: 报告输出

将生成的中间态调优建议保存至：（远端模式：先在 agent 本地用 Write 工具生成文件，再 scp 上传到远端该路径；禁止在 agent 本地创建 `${WORK_DIR}` 目录）

```
${WORK_DIR}/tuning/intermediate/hisock-tuning.md
```

同时，在报告目录下创建调优脚本文件夹：

```
${WORK_DIR}/tuning/hisock-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── hisock_tune.sh         # 复制的基础脚本（含 check/compile/apply/unload）
```

> **⚠️ 职责说明**：上述目录由协调器 `opentunex-scenario-tuning` 在步骤 4 创建，本子技能仅产出中间态建议，不负责脚本部署。

**注意**：本文件是中间态数据，最终将由调优域入口汇总为一份完整的调优建议报告。

---

## 产出

| 产出项 | 说明 |
|--------|------|
| 调优建议报告 | 依据中间态模板生成的结构化报告（含编译 + 加载步骤） |
| 调优脚本文件夹 | 包含 tuning.sh 入口脚本和 hisock_tune.sh 基础脚本（含 check/compile/apply/unload） |
| 预期收益 | 网络协议栈开销降低，PPS/吞吐提升 10%-30%（业务相关）；nf_hook 占比下降 |
| 风险提示 | eBPF 加载/卸载操作由用户执行；agent 不远程操作；需内核 CONFIG_HISOCK 支持 |
| 回滚方案 | `./hisock-tuning/tuning.sh unload` 或直接调用 `hisock_cmd -u` |

---

## 冲突约束

> **⚠️ 以下冲突约束由调优域入口统一处理，本技能无需处理。**

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|----------|
| hisock 网络加速 | iptables / nftables 规则 | netfilter | hisock 加速流量不经过 L2/L3 netfilter；iptables 规则对非加速流量仍生效 |
| hisock 网络加速 | oenetcls / venetcls 网卡多路径 | 不同层级加速 | 无冲突，可并行 |

### 与其他调优方向的协作

| 调优方向 | 冲突关系 | 处理策略 |
|---------|---------|----------|
| NUMA 并行调度 (PARAL) | 无冲突 | 可并行 |
| 窃取任务 (STEAL) | 无冲突 | 可并行 |
| 分域调度 (SOFT_DOMAIN) | 无冲突 | 可并行 |
| 动态 SMT (KEEP_ON_CORE) | 无冲突 | 可并行 |
| BTB/TidCMP BIOS 调优 | 无冲突 | 可并行 |
| copy_user 内核补丁 | 无冲突 | 可并行 |
| Docker 算力统筹 | 无冲突 | 可并行 |
| 网卡多路径 (oenetcls/venetcls) | 无冲突 | 可并行 |

---

## 与场景分析 skill 的协作

本 skill 接收 `opentunex-hisock-analysis` 输出的中间态分析结论：

```
瓶颈分析 skill 输出:
  ${WORK_DIR}/analysis/opentunex-hisock-analysis_collect/result.md
    ├─ IS_HISOCK_SUPPORTED (true/false)
    ├─ IS_NF_HOOK_HOTSPOT (true/false)
    ├─ NF_HOOK_FUNCS (e.g. nf_hook_slow,nf_hook_entries)
    ├─ NF_HOOK_PERCENT (e.g. 3.5)
    ├─ NET_DEV_NAME (e.g. enp46s0f0np0)
    ├─ CGROUP_PATH (e.g. /sys/fs/cgroup/perf_event/docker)
    ├─ LISTEN_PORTS (e.g. 6379)
    └─ 适用性结论 (applicable / not_applicable / limited_benefit)
          │
          ▼
本 skill:
  解析环境结论 → 前置检查 → 提示编译/加载步骤 → 输出调优报告（用户主动执行 apply/unload）
```

---

## 约束与限制

| 约束项 | 说明 |
|--------|------|
| 调优前提检查结果 | CONFIG_HISOCK=y、nf_hook 热点存在 |
| 调优步骤建议 | 内核源码编译 hisock_cmd + bpf.o → 加载 eBPF（不通过 agent 自动操作） |
| 验证方法 | hisock_cmd 进程 + nf_hook 占比下降 + 业务指标改善 |
| 回滚方案 | `hisock_cmd -u` 或调用脚本 unload |
| 预期收益 | 绕过 L2/L3 netfilter（连接跟踪/丢包策略/端口映射）开销，降低网络协议栈处理延迟 |
| 风险提示 | eBPF 加载/卸载操作由用户主动执行；agent 不会远程加载 eBPF |
| 回滚方案 | `./hisock-tuning/tuning.sh unload` 或 `hisock_cmd -u -c <cgroup> -i <nic>` |

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-hisock-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-05]
```