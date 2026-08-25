---
name: "opentunex-hisock-analysis"
description: "hisock 网络加速适用性分析。检查热点函数调用栈中是否包含 nf_hook*（netfilter 钩子开销），评估使用 hisock_cmd 加载 eBPF 加速策略绕过 L2/L3 netfilter 开销的适用性。触发:hisock、nf_hook、netfilter、网络收发包慢、连接跟踪开销、网络过滤、eBPF 加速、网络协议栈绕过。"
---

# hisock 网络加速适用性分析

分析热点函数调用栈中是否存在 `nf_hook*` 开销，评估使用 hisock 加速策略绕过 netfilter 的适用性。

**分析原理**：在网络收发包场景中，数据包经过数据链路层(L2)和网络层(L3)时，netfilter 钩子（连接跟踪、丢包策略、端口映射等）会引入额外开销。当 `nf_hook*` 函数出现在热点调用栈中时，表明 netfilter 处理已成为瓶颈。hisock 通过 eBPF 程序在协议栈入口将已建链目标数据流直接转发到 TCP 层（收包）或网卡设备（发包），绕过 L2/L3 的 netfilter 开销。

> **⚠️ 本调优方向需要编译内核 samples/bpf 工具后生效，不支持一键使能。**

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-hisock-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

---

## 执行流程

本技能的完整执行流程如下，**必须按顺序完成所有步骤，不得在中间步骤终止**：

| 步骤 | 操作 | 产出 |
|------|------|------|
| 1 | 执行 `../../scripts/opentunex-hisock-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-hisock-analysis_collect` | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量 | 决策变量值 |
| 3 | 按"决策逻辑"章节依次执行环境约束前置检查 → 场景模式判定 | 分析结论 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-hisock-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。

---

## 数据读取

### 优先路径：预分析 JSON（推荐）

1. 执行预处理脚本生成 JSON：
   ```bash
   bash ../../scripts/opentunex-hisock-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-hisock-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-hisock-analysis_collect/preanalysis.json`

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `is_nf_hook_hotspot` | IS_NF_HOOK_HOTSPOT | `true` / `false`（调用栈中包含 nf_hook* 函数） |
| `nf_hook_funcs` | NF_HOOK_FUNCS | 命中的函数名列表，如 `"nf_hook_slow,nf_hook_entries"` |
| `nf_hook_percent` | NF_HOOK_PERCENT | 热点占比数值（如 `3.5` 表示 3.5%） |
| `net_dev_name` | NET_DEV_NAME | 主要物理网卡名，如 `"enp46s0f0np0"` |
| `cgroup_path` | CGROUP_PATH | cgroup 路径，如 `"/sys/fs/cgroup/perf_event"` |
| `listen_ports` | LISTEN_PORTS | 关联的服务端口信息 |
| `is_hisock_supported` | IS_HISOCK_SUPPORTED | `true` / `false`（内核配置 CONFIG_HISOCK=y） |
| `kernel_version` | KERNEL_VERSION | 内核版本字符串 |

### 降级路径：直接读取采集文件

当 `preanalysis.json` 不可用时，从以下文件直接提取：

| 决策变量 | 数据来源文件 | 提取方法 |
|---------|------------|---------|
| IS_NF_HOOK_HOTSPOT / NF_HOOK_FUNCS / NF_HOOK_PERCENT | `hotspot_analysis.txt` / `hotspot_function_analysis.txt` | 搜索 `nf_hook` 关键字 |
| NET_DEV_NAME | `network_metrics_analysis.txt` / `net_info.txt` | 提取物理网卡名 |
| IS_HISOCK_SUPPORTED / KERNEL_VERSION | `kernel_config_info.txt` / `static_info.txt` | 检查 CONFIG_HISOCK=y |

---

## 决策逻辑

按以下优先级依次判断，命中即输出。

> **前置检查分类（遵守 SB-06）**：
> - E0 为"环境不支持"（内核不支持 hisock，即 CONFIG_HISOCK 未启用），**不短路**，记录支持缺口 `HISOCK_UNSUPPORTED_GAP`，继续评估场景条件
> - E1 为"硬性不适用"（调用栈中无 nf_hook* 函数，无收益对象），命中即短路

### 环境约束前置检查

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| E0 | IS_HISOCK_SUPPORTED = false（内核未启用 CONFIG_HISOCK） | 记录 `HISOCK_UNSUPPORTED_GAP+="内核未启用CONFIG_HISOCK"`，**继续评估**（不短路） | hisock 依赖内核 CONFIG_HISOCK 配置（环境支持缺口，见 SB-06） |
| E1 | IS_NF_HOOK_HOTSPOT = false（调用栈中无 nf_hook* 函数） | 不适用 | 无 netfilter 钩子开销，hisock 加速无收益 |

### 场景模式判定

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| S1 | IS_NF_HOOK_HOTSPOT = true 且 IS_HISOCK_SUPPORTED = true | **适用** | nf_hook 开销存在 + hisock 支持 → hisock 可绕过 L2/L3 netfilter，降低网络协议栈开销 |
| S2 | IS_NF_HOOK_HOTSPOT = true 且 `HISOCK_UNSUPPORTED_GAP` 非空 | 收益有限（见 SB-06 处理） | netfilter 瓶颈场景存在，但当前内核未启用 CONFIG_HISOCK |

### 环境支持缺口处理（SB-06）

> 当 S2 命中（nf_hook 热点存在，但内核未启用 CONFIG_HISOCK），**不得直接判为"不适用"**，改按下表输出：

| 条件 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|------|---------|--------------|-----------|------------------------|
| S2 命中且 `HISOCK_UNSUPPORTED_GAP` 非空 | 收益有限（环境不支持但场景匹配） | `limited_benefit` | `[当前系统不支持（{HISOCK_UNSUPPORTED_GAP 具体原因}），需手动引入该特性后方可实施：启用内核 CONFIG_HISOCK=y 并重新编译，编译 hisock 工具后实施] <原建议操作>` | `low` |

**综合结论示例**：`收益有限 — 内核未启用 CONFIG_HISOCK，但调用栈中检测到 nf_hook_slow 占 3.5%，存在 netfilter 瓶颈，建议启用 CONFIG_HISOCK 后使用 hisock 加速`

### 严重度评估

| 条件 | severity | 原因 |
|------|----------|------|
| NF_HOOK_PERCENT >= 5 | `high` | netfilter 开销占比高（>=5%），加速收益显著 |
| NF_HOOK_PERCENT >= 1 且 < 5 | `medium` | netfilter 开销占比中等，加速有收益 |
| NF_HOOK_PERCENT < 1 或为 0 | `low` | netfilter 开销占比低，加速收益有限 |

---

## 调优步骤推荐

> 以下调优步骤仅在分析结论为"适用"时适用。结论为"不适用"或"收益有限"时不执行调优。

### 调优参数

| 参数 | 说明 |
|------|------|
| hisock_cmd | hisock 加速控制工具（需从内核源码编译） |
| bpf.o | eBPF 加速策略字节码（需从内核源码编译） |
| -c <cgroup路径> | 指定加速的 cgroup（如 Docker 容器路径） |
| -p <端口范围> | 指定加速的端口（如 6379） |
| -i <网卡设备> | 指定加速的网卡（如 enp46s0f0np0） |

> 本调优方向需要编译内核 samples/bpf 工具后生效，不支持一键使能。依赖内核启用 CONFIG_HISOCK=y。

### 使能步骤

1. 编译 hisock 工具:
   ```bash
   # 进入内核源码路径
   make -C tools/lib/bpf/ -j$(nproc)
   make -C samples/bpf -j$(nproc)
   cp samples/bpf/hisock/hisock_cmd <指定路径>
   cp samples/bpf/hisock/bpf.o <指定路径>
   ```
2. 使能 hisock 加速:
   ```bash
   ./hisock_cmd -f bpf.o -c <cgroup路径> -p <端口范围> -i <网卡设备>
   # 示例
   ./hisock_cmd -f ./bpf.o -c /sys/fs/cgroup/perf_event/docker/ -p 6379 -i enp46s0f0np0
   ```

### 验证命令

```bash
# 检查 hisock 进程是否运行
ps aux | grep hisock_cmd
# 重新采集 perf 数据，确认 nf_hook 占比下降
perf record -g -- <your_workload> && perf report | grep nf_hook
```

### 回滚步骤

```bash
./hisock_cmd -u -c <cgroup路径> -i <网卡设备>
```

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| 内核配置 | 内核需启用 CONFIG_HISOCK=y | 不支持时需重新编译内核启用该配置 |
| netfilter | hisock 绕过 L2/L3 netfilter | 与 iptables 规则共存，但 hisock 加速流量不经过 netfilter |
| oenetcls | 不同层级加速 | 无冲突，可并行 |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-hisock-analysis_collect/result.md`，格式如下：

```markdown
# hisock 网络加速适用性分析结果

## 1. 环境检查

| 检查项 | 结果 |
|--------|------|
| IS_HISOCK_SUPPORTED | {true/false} |
| KERNEL_VERSION | {内核版本} |

## 2. 热点函数信息

| 指标 | 值 |
|------|-----|
| IS_NF_HOOK_HOTSPOT | {true/false} |
| NF_HOOK_FUNCS | {命中的函数名，如 "nf_hook_slow,nf_hook_entries"} |
| NF_HOOK_PERCENT | {热点占比，如 "3.5"} |

## 3. 网络环境信息

| 指标 | 值 |
|------|-----|
| NET_DEV_NAME | {主要网卡名，如 "enp46s0f0np0"} |
| CGROUP_PATH | {cgroup 路径} |
| LISTEN_PORTS | {关联服务端口} |

## 4. 适用性评估

| 评估维度 | 结果 | 证据 |
|---------|------|------|
| nf_hook 热点存在 | ✅/❌ | 检测到 {函数名}，占比 {N}% |
| hisock 支持 | ✅/❌ | 内核版本={值}，CONFIG_HISOCK={y/n} |

**综合结论**: {适用/不适用/收益有限} — {原因}

**建议操作**:
1. 编译 hisock 工具:
   ```bash
   # 进入内核源码路径
   make -C tools/lib/bpf/ -j$(nproc)
   make -C samples/bpf -j$(nproc)
   cp samples/bpf/hisock/hisock_cmd <指定路径>
   cp samples/bpf/hisock/bpf.o <指定路径>
   ```
2. 使能 hisock 加速:
   ```bash
   ./hisock_cmd -f bpf.o -c <cgroup路径> -p <端口范围> -i <网卡设备>
   # 示例
   ./hisock_cmd -f ./bpf.o -c /sys/fs/cgroup/perf_event/docker/ -p 6379 -i enp46s0f0np0
   ```
3. 关闭 hisock 加速:
   ```bash
   ./hisock_cmd -u -c <cgroup路径> -i <网卡设备>
   ```

> **注意**：本调优方向需要编译内核 samples/bpf 工具后生效，不支持一键使能。

## 5. 调优步骤推荐

> 仅在结论为"适用"时适用。

### 使能步骤

1. 编译 hisock 工具: `make -C samples/bpf -j$(nproc)`
2. 使能加速: `./hisock_cmd -f bpf.o -c <cgroup> -p <端口> -i <网卡>`

### 验证

```bash
ps aux | grep hisock_cmd
perf report | grep nf_hook
```

### 回滚

```bash
./hisock_cmd -u -c <cgroup路径> -i <网卡设备>
```

## 6. 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "hisock_accel",
  "suggestion": "调用栈中检测到 nf_hook 热点，推荐使用 hisock 加速绕过 L2/L3 netfilter 开销：编译 hisock_cmd → 加载 eBPF 加速策略 → 指定 cgroup/端口/网卡使能",
  "equivalence_class": "hisock_accel",
  "activation_requirement": "manual_enable",
  "estimated_gain": {
    "primary_metric": "network_throughput",
    "severity": "medium",
    "description": "绕过 L2/L3 netfilter（连接跟踪/丢包策略/端口映射）开销，降低网络协议栈处理延迟"
  },
  "conflicts": [],
  "prerequisites": ["hisock_kernel_support"],
  "synergy_with": [],
  "scenario_priority": 5,
  "source": "skill_output",
  "cross_skill_relations": {
    "conflicts_with": [],
    "depends_on": []
  }
}
```
```

> **适用性结论 → JSON applicability 映射**：
> - 适用（S1 命中） → `"applicable"`
> - 不适用（E1 命中，无 nf_hook 热点） → `"not_applicable"`
> - 收益有限（S2 命中：环境不支持但场景匹配） → `"limited_benefit"`，suggestion 须以前缀 `[当前系统不支持（{具体缺口原因}），需手动引入该特性后方可实施：启用内核 CONFIG_HISOCK=y 并重新编译，编译 hisock 工具后实施] ` 标注支持缺口

---

## 契约输出

输出契约格式参见 [contract-spec.md](../contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-hisock-analysis"
input:
  data_dir: "[actual DATA_DIR]"
output:
  result_path: "[actual result_path]"
constraints_acknowledged: [SB-01~SB-06]
```
