# 网卡多路径调优指南

加载网卡多路径特性内核模块（默认 `oenetcls`，部分内核命名为 `venetcls`，由脚本自动识别），接管多网卡中断亲和分配，将网卡中断绑定到对应 NUMA 节点本地处理，减少跨 NUMA 网络中断开销。

## 强制约束

> 本指南遵守 [场景调优子技能共享约束](../common-constraints.md) 中定义的所有执行约束、调优执行约束和数据目录约定。

本指南依据 [中间态建议模板](../intermediate-report-template.md) 生成结构化的中间态调优建议。

> **⚠️ 每次触发本指南都必须重新从头执行完整调优流程，不得引用历史数据或之前的回答。**
> - 即使系统状态未变化，也必须重新执行所有调优步骤
> - 不得跳过任何调优阶段，不得复用历史调优结果
> - 每次执行都必须创建新的时间戳批次目录，保存完整的调优过程数据
> - 这是强制性要求，无例外情况

本指南**禁止**直接在宿主机上或通过远程机器连接执行任何调优命令。本指南的职责是依据瓶颈分析结果，生成中间态调优建议，供调优域入口汇总为一份完整的调优建议报告。

### 数据目录约束

- **读取路径**：从 `${WORK_DIR}/analysis/` 下查找包含 multi-net-path 相关分析结论的 `result.md` 文件
- **查找命令示例**：
```bash
CONCLUSION_FILE=$(find ${WORK_DIR}/analysis/ -name "result.md" -exec grep -l "oenetcls\|venetcls\|multi.net.path\|ntuple\|跨NUMA.*中断" {} \; | head -1)
```
- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到网卡多路径相关的分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

---

## 输入约定

本指南的数据来源是**瓶颈分析结果**。

| 输入数据 | 必需 | 说明 |
|---------|------|------|
| 瓶颈分析结果数据 | 是 | 包含 oenetcls/venetcls 内核模块、ntuple 硬件能力、NUMA 拓扑、中断亲和相关的环境检查、指标数据和适用性评估结论 |

**前置校验**：如果适用性评估结论为"不建议启用"、"已启用"或"收益有限"，不应执行调优。

如果用户未提供评估结论，应先引导用户完成网卡多路径网络瓶颈适用性评估。

---

## 调优参数说明

### 网卡多路径模块参数（全部 10 个）

> 下文统称"网卡多路径模块"，实际模块名可能是 `oenetcls` 或 `venetcls`，详见下方兼容性小节。`tuning.sh` 会按实际情况自动识别并替换。瓶颈分析技能 `opentunex-multi-net-path-analysis` 会在 `recommended_params` 字段中预计算所有 10 个参数的推荐值，调优脚本直接透传给 `modprobe`。

| 参数 | 类型 / 取值范围 | 默认值 | 说明 | 推荐来源 |
|------|----------------|--------|------|---------|
| `mode` | 整数 0/1 | 0 | 0=ntuple 模式，可与分域调度特性配合实现 cluster 亲和；1=flow 模式 | 分析：推荐 NIC 中最小 `max_q ≤ 1` 时取 1 |
| `appname` | 字符串 ≤16 字符 | "" | 目标应用进程名，可 `#` 拼接多个（如 `IO_Con#redis-server`）；空 = 全局使能 | 分析：按 redis > nginx > mysql 优先级拼接 |
| `ifname` | `#` 分隔字符串 | 必填 | 物理网卡名称列表（如 `eth0#eth1`） | 分析：阶段二点五纳入的网卡列表 |
| `strategy` | 整数 0/1/2/3 | 0 | 0=缺省（NUMA 内分 + 不同 NIC 不同核）；1=Cluster 均分；2=NUMA 均分（不同 NIC 可同核）；3=用户已自定义绑核，自动提取 | 分析：NUMA≥4→1；NUMA=2→2 |
| `debug` | 整数 0/1 | 0 | 是否输出调试日志 | 分析：固定 0 |
| `match_ip_flag` | 整数 0/1 | 0 | 网卡接收数据包时是否按目的 IP 决定队列 | 分析：固定 0 |
| `irqname` | 字符串 ≤64 字节 | `comp` | 解析 `/proc/interrupts` 时匹配的网卡中断描述串（如 `mlx5_comp`、`ixgbe-*`） | 分析：按 NIC 驱动映射 |
| `rxq_multiplex_limit` | 整数 1~64 | 1 | 仅 mode=0 时生效；每队列可复用的 TCP 流数 | 分析：最小 `max_q ≤ 4` 时取 4 |
| `lo_rps_policy` | 整数 0/1/2 | 0 | 0=关闭 loopback rps；1=按 NUMA 内打散；2=按 cluster 内打散 | 分析：NUMA≥4→2；NUMA≥2→1 |
| `rps_policy` | 整数 0/1/2 | 0 | 0=关闭网卡 rps；1=按 NUMA 内打散；2=按 cluster 内打散 | 分析：同上 |

### 模块名兼容性（oenetcls / venetcls）

> ⚠️ 网卡多路径特性模块在不同内核中命名可能不同，必须自动识别，否则会误判模块不可用并跳过调优。

| 内核/厂商 | 模块名 | `/proc/net` 统计路径 |
|-----------|--------|---------------------|
| 多数发行版 | `oenetcls` | `/proc/net/oenetcls/stats` |
| 部分定制内核 | `venetcls` | `/proc/net/venetcls/stats` |

**检测方式**：脚本 `scripts/multi-net-path-tuning/multi_net_path_tune.sh` 内置 `resolve_module_name()`，按以下优先级自动识别（结果缓存到全局 `MODULE_NAME`）：

1. 优先匹配已加载的模块（`/sys/module/<name>` 或 `lsmod`）
2. 未加载时按顺序匹配 `modinfo` 可用的模块
3. 都失败则默认 `oenetcls`（脚本将依据 `unavailable` 状态终止调优）

**报告生成要求**：本指南在生成报告时**必须**从瓶颈分析结果中提取实际模块名（搜索 `oenetcls|venetcls`），填入调优步骤中的 `modprobe` / `lsmod` / `rmmod` / `/proc/net/...` 命令，**禁止**使用 `oenetcls` 作为硬编码默认值。当瓶颈分析未明确给出模块名时，应在报告中注明"实际模块名由 `tuning.sh check` 自动识别"。

### irqbalance 服务

| 项目 | 说明 |
|------|------|
| 服务含义 | 系统中断亲和自动均衡服务 |
| 冲突说明 | oenetcls/venetcls 特性需要接管中断亲和分配，与 irqbalance 功能冲突，必须先停止 irqbalance |
| 停止方式 | `systemctl stop irqbalance` |
| 恢复方式 | `systemctl start irqbalance` |

### 回滚说明

> 卸载命令中的 `<MODULE_NAME>` 由脚本根据实际内核识别（`oenetcls` 或 `venetcls`），调优报告应使用本机识别到的实际名称。

| 操作 | 命令 |
|------|------|
| 卸载多路径模块 | `rmmod <MODULE_NAME>`（如 `rmmod oenetcls` 或 `rmmod venetcls`） |
| 恢复 irqbalance | `systemctl start irqbalance` |
| 验证 | `systemctl is-active irqbalance` 应返回 `active` |

---

## 技能调用方法

### 基础脚本调用

本指南依赖 `scripts/multi-net-path-tuning/multi_net_path_tune.sh` 脚本完成调优操作。脚本支持以下操作：

| 操作 | 命令 | 说明 |
|------|------|------|
| 环境检查 | `bash scripts/multi-net-path-tuning/multi_net_path_tune.sh check` | 检查 oenetcls/venetcls 模块可用性（自动识别）、网卡 ntuple 支持、irqbalance 状态、NUMA 拓扑 |
| 状态备份 | `bash scripts/multi-net-path-tuning/multi_net_path_tune.sh backup` | 备份当前模块（oenetcls/venetcls）和 irqbalance 状态 |
| 应用调优 | `bash scripts/multi-net-path-tuning/multi_net_path_tune.sh apply "<ifnames>" "<appname>" [mode strategy debug match_ip_flag irqname rxq_multiplex_limit lo_rps_policy rps_policy]` | 停止 irqbalance + 加载自动识别的多路径模块。后 8 个参数可选，未传则由模块使用默认值 |
| 查看状态 | `bash scripts/multi-net-path-tuning/multi_net_path_tune.sh status` | 查看多路径模块（oenetcls/venetcls）状态、中断分布、NUMA 拓扑 |
| 回滚 | `bash scripts/multi-net-path-tuning/multi_net_path_tune.sh rollback` | 卸载多路径模块（oenetcls/venetcls）+ 恢复 irqbalance |

**调优 apply 命令参数顺序**（与 `modprobe` 一致）：

| 位置 | 参数 | 必填 | 示例 |
|------|------|------|------|
| 1 | `ifnames` | ✓ | `eth0#eth1` |
| 2 | `appname` | ✗（空=全局使能） | `redis-server` 或 `IO_Con#redis-server` 或 `""` |
| 3 | `mode` | ✗ | `0` |
| 4 | `strategy` | ✗ | `1` |
| 5 | `debug` | ✗ | `0` |
| 6 | `match_ip_flag` | ✗ | `0` |
| 7 | `irqname` | ✗ | `comp` |
| 8 | `rxq_multiplex_limit` | ✗ | `1` |
| 9 | `lo_rps_policy` | ✗ | `0` |
| 10 | `rps_policy` | ✗ | `0` |

> **⚠️ 说明**：调优报告中的"调优步骤"展示独立命令，目的是让用户了解具体做了什么操作、修改了哪些文件。实际调优时用户可使用入口脚本 `tuning.sh`（由用户确认后自行执行），脚本会自动完成环境检查、状态备份、调优执行、验证和回滚。Agent 不得自动执行调优操作。

---

## tuning.sh 动态生成说明

### 生成目的

根据最新的调优报告规范，每个调优方向的脚本需要组织为独立文件夹，包含：
- **入口脚本 `tuning.sh`**：动态生成，包含针对当前瓶颈的动态参数
- **基础脚本**：从 `scripts/` 目录复制的原始脚本

### 生成流程

1. **创建调优技能文件夹**：在报告输出目录下创建 `multi-net-path-tuning/` 文件夹
2. **复制基础脚本**：将 `scripts/multi-net-path-tuning/multi_net_path_tune.sh` 复制到该文件夹
3. **生成入口脚本 `tuning.sh`**：根据当前瓶颈分析结果，动态生成入口脚本

### tuning.sh 模板

入口脚本由大模型根据瓶颈分析结果动态生成，模板如下：

```bash
#!/bin/bash
# 网卡多路径调优入口脚本
# 由调优技能根据瓶颈分析动态生成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 动态参数（由大模型根据瓶颈分析结果填充，必须使用分析结果中的实际值，不得使用占位符）
# 每个变量对应 preanalysis.json 的 recommended_params 字段，禁止使用占位符或硬编码默认值。
# RECOMMENDED_IFNAMES:        瓶颈分析推荐的网卡列表，用 # 拼接
# RECOMMENDED_APPNAME:        推荐的目标应用名（多应用用 # 拼接）；未识别出应用则留空表示全局使能
# RECOMMENDED_MODE:           0=ntuple / 1=flow
# RECOMMENDED_STRATEGY:       0/1/2/3（见参数说明表）
# RECOMMENDED_DEBUG:          0/1
# RECOMMENDED_MATCH_IP_FLAG:  0/1
# RECOMMENDED_IRQNAME:        中断描述匹配串（如 comp / mlx5_comp）
# RECOMMENDED_RXQ_MULTIPLEX_LIMIT: 1~64
# RECOMMENDED_LO_RPS_POLICY:  0/1/2
# RECOMMENDED_RPS_POLICY:     0/1/2
IFNAMES="<RECOMMENDED_IFNAMES>"
APPNAME="<RECOMMENDED_APPNAME>"
MODE="<RECOMMENDED_MODE>"
STRATEGY="<RECOMMENDED_STRATEGY>"
DEBUG="<RECOMMENDED_DEBUG>"
MATCH_IP_FLAG="<RECOMMENDED_MATCH_IP_FLAG>"
IRQNAME="<RECOMMENDED_IRQNAME>"
RXQ_MULTIPLEX_LIMIT="<RECOMMENDED_RXQ_MULTIPLEX_LIMIT>"
LO_RPS_POLICY="<RECOMMENDED_LO_RPS_POLICY>"
RPS_POLICY="<RECOMMENDED_RPS_POLICY>"

case "${1:-}" in
    check)
        bash "${SCRIPT_DIR}/multi_net_path_tune.sh" check
        ;;
    apply)
        bash "${SCRIPT_DIR}/multi_net_path_tune.sh" apply \
            "${IFNAMES}" "${APPNAME}" \
            "${MODE}" "${STRATEGY}" "${DEBUG}" "${MATCH_IP_FLAG}" \
            "${IRQNAME}" "${RXQ_MULTIPLEX_LIMIT}" \
            "${LO_RPS_POLICY}" "${RPS_POLICY}"
        ;;
    status)
        bash "${SCRIPT_DIR}/multi_net_path_tune.sh" status
        ;;
    rollback)
        bash "${SCRIPT_DIR}/multi_net_path_tune.sh" rollback
        ;;
    *)
        echo "用法: $0 {check|apply|status|rollback}"
        exit 1
        ;;
esac
```

### 报告中的脚本路径

在中间态调优建议中，调优脚本路径应填写为：
- `./multi-net-path-tuning/tuning.sh` （相对于调优报告目录）

---

## 调优执行流程

### Phase 1: 调优前提检查

#### Step 1.1: 读取分析结果数据

从协调器传入的融合报告数据中，查找与网卡多路径网络瓶颈相关的分析结论。

**需要提取的数据项**：

| 指标 | 提取方法 | 默认值 |
|------|---------|--------|
| **模块名 (MODULE_NAME)** | 优先从"调优参数推荐"节读 `module_name` 行；否则搜索 "oenetcls\|venetcls" 关键词；若分析未明确，则在 `tuning.sh check` 时由脚本自动检测，报告注明"由 check 自动识别" | oenetcls |
| oenetcls/venetcls 模块状态 | 搜索 "oenetcls\|venetcls" 关键词：已加载/可用未加载/不可用 | 不可用 |
| 物理网卡列表 | 搜索 "物理网卡" 相关描述中的网卡名称列表 | 空 |
| ntuple 支持状态 | 搜索 "ntuple" 相关描述 | 无数据 |
| NUMA 节点数 | 搜索 "NUMA" 相关描述中的节点数量 | 1 |
| 目标业务进程 | 搜索 "redis-server\|nginx\|mysql" 相关进程存在性 | 无 |
| 适用性评估结论 | 搜索 "multi-net-path" 或 "oenetcls\|venetcls" 相关的适用性评估结论 | 不适用 |
| **RECOMMENDED_IFNAMES** | "调优参数推荐"节 `ifnames` 行（`#` 拼接） | 空 |
| **RECOMMENDED_APPNAME** | "调优参数推荐"节 `appname` 行（`#` 拼接多应用）；未识别则空 | 空 |
| **RECOMMENDED_MODE** | "调优参数推荐"节 `mode` 行 | 0 |
| **RECOMMENDED_STRATEGY** | "调优参数推荐"节 `strategy` 行 | 0 |
| **RECOMMENDED_DEBUG** | "调优参数推荐"节 `debug` 行 | 0 |
| **RECOMMENDED_MATCH_IP_FLAG** | "调优参数推荐"节 `match_ip_flag` 行 | 0 |
| **RECOMMENDED_IRQNAME** | "调优参数推荐"节 `irqname` 行 | comp |
| **RECOMMENDED_RXQ_MULTIPLEX_LIMIT** | "调优参数推荐"节 `rxq_multiplex_limit` 行 | 1 |
| **RECOMMENDED_LO_RPS_POLICY** | "调优参数推荐"节 `lo_rps_policy` 行 | 0 |
| **RECOMMENDED_RPS_POLICY** | "调优参数推荐"节 `rps_policy` 行 | 0 |

> **⚠️ 关键**：上述 10 个 `RECOMMENDED_*` 参数是瓶颈分析技能根据网卡 IRQ 亲和分析、NUMA 拓扑、网卡驱动和队列数等得出的精准推荐值，**必须**用于填充 `tuning.sh` 的动态参数和调优步骤中的 `modprobe` 命令。不得使用通用占位符（如 `eth0#eth1`、`redis-server`），必须使用分析结果中的实际值。

**校验逻辑**：
- 目录不存在 → 终止，提醒用户需要先完成瓶颈分析
- CONCLUSION=不建议启用 或 收益有限 → 终止调优
- CONCLUSION=已启用 → 终止调优
- oenetcls/venetcls=不可用 → 终止调优（脚本 check 阶段会同时探测两种命名，避免单一名称误判）
- RECOMMENDED_IFNAMES=空 → 终止调优，提示无符合条件的网卡
- 目标业务进程=无 → **不终止**，appname 留空以对所有应用使能特性

**产出**：调优前提检查结果

| 检查项 | 结果 |
|--------|------|
| 实际模块名 (MODULE_NAME) | oenetcls / venetcls（取自分析结果或 check 自动识别） |
| 模块状态 | 已加载/可用未加载/不可用 |
| 推荐网卡列表 (ifnames) | eth0#eth1（来自分析结果） |
| 推荐应用名 (appname) | redis-server / （无，将全局使能） |
| NUMA 节点数 | N |

---

### Phase 2: 生成中间态调优建议

依据 [中间态建议模板](../intermediate-report-template.md) 生成报告，按以下要求填充各字段：

#### 2.1 瓶颈点列表填充

从分析结果中提取以下信息填充表格：
- **瓶颈点**：根据网卡多路径分析结论填写，如"跨NUMA网络中断开销"
- **类别**：固定为"网络"
- **严重程度**：根据分析结果中的严重度填写
- **影响描述**：总结跨 NUMA 中断对网络性能的影响
- **调优手段**：简短描述，如"启用 oenetcls/venetcls 网卡多路径中断亲和"
- **调优步骤**：精简操作步骤，如"1.停止irqbalance 2.加载<MODULE_NAME> 3.验证中断分布"
- **调优脚本**：填写 `./multi-net-path-tuning/tuning.sh`

#### 2.2 调优建议详情填充

**瓶颈证据**：从分析结果中提取网卡多路径相关的指标数据，如：
- 实际模块名（`oenetcls` 或 `venetcls`）及其状态
- 物理网卡数量及 ntuple 支持状态
- NUMA 节点数
- 中断分布情况（集中在少数核心/跨 NUMA）
- 目标业务进程存在性

**影响分析**：说明跨 NUMA 网络中断对业务的影响，如网络吞吐下降、延迟增加等

**调优手段**：与瓶颈点列表中的调优手段一致

**调优步骤**：展示独立命令，让用户了解具体操作。**必须使用 Phase 1 提取的 `MODULE_NAME`、`RECOMMENDED_IFNAMES` 和 `RECOMMENDED_APPNAME` 实际值替换命令中的参数**，不得使用通用占位符。

> 当 `MODULE_NAME` 由 `tuning.sh check` 自动识别得出（瓶颈分析未明确给出）时，报告应注明"实际模块名由 check 阶段自动识别"。

有目标应用时（RECOMMENDED_APPNAME 非空）：
```bash
# 停止 irqbalance 服务
systemctl stop irqbalance
# 加载网卡多路径特性模块（MODULE_NAME 由 check 阶段识别：oenetcls 或 venetcls）
# 必须使用瓶颈分析的全部 10 个推荐参数；占位符需替换为 analysis 输出的实际值
modprobe <MODULE_NAME> \
  mode=<RECOMMENDED_MODE> \
  appname="<RECOMMENDED_APPNAME>" \
  ifname="<RECOMMENDED_IFNAMES>" \
  strategy=<RECOMMENDED_STRATEGY> \
  debug=<RECOMMENDED_DEBUG> \
  match_ip_flag=<RECOMMENDED_MATCH_IP_FLAG> \
  irqname="<RECOMMENDED_IRQNAME>" \
  rxq_multiplex_limit=<RECOMMENDED_RXQ_MULTIPLEX_LIMIT> \
  lo_rps_policy=<RECOMMENDED_LO_RPS_POLICY> \
  rps_policy=<RECOMMENDED_RPS_POLICY>
# 验证模块已加载
lsmod | grep <MODULE_NAME>
# 查看统计信息（如有）
cat /proc/net/<MODULE_NAME>/stats 2>/dev/null
```

无目标应用时（RECOMMENDED_APPNAME 为空，全局使能）：
```bash
# 停止 irqbalance 服务
systemctl stop irqbalance
# 加载网卡多路径特性模块（MODULE_NAME 由 check 阶段识别：oenetcls 或 venetcls）
modprobe <MODULE_NAME> \
  mode=<RECOMMENDED_MODE> \
  appname=\"\" \
  ifname="<RECOMMENDED_IFNAMES>" \
  strategy=<RECOMMENDED_STRATEGY> \
  debug=<RECOMMENDED_DEBUG> \
  match_ip_flag=<RECOMMENDED_MATCH_IP_FLAG> \
  irqname="<RECOMMENDED_IRQNAME>" \
  rxq_multiplex_limit=<RECOMMENDED_RXQ_MULTIPLEX_LIMIT> \
  lo_rps_policy=<RECOMMENDED_LO_RPS_POLICY> \
  rps_policy=<RECOMMENDED_RPS_POLICY>
# 验证模块已加载
lsmod | grep <MODULE_NAME>
# 查看统计信息（如有）
cat /proc/net/<MODULE_NAME>/stats 2>/dev/null
```

**回滚方法**：展示对应的回滚命令：
```bash
# 卸载网卡多路径特性模块（使用与加载时一致的模块名）
rmmod <MODULE_NAME>
# 恢复 irqbalance 服务
systemctl start irqbalance
# 验证 irqbalance 已恢复
systemctl is-active irqbalance
```

**调优脚本**：填写 `./multi-net-path-tuning/tuning.sh apply`

**验证方法**：提供验证命令，确认调优是否生效：
```bash
# 观察网卡中断分布是否变化
cat /proc/interrupts | grep eth
# 查看目标进程的 NUMA 内存访问（有指定应用时）
numastat -p $(pgrep redis-server | head -1)
# 若未指定应用，观察整体跨 NUMA 中断变化
cat /proc/interrupts | grep eth | awk '{print $1, $2, $3, $4}'
# 网络吞吐监控（需配合压测）
sar -n DEV 1 10
```

---

### Phase 3: 报告输出

将生成的中间态调优建议保存至：
```
${WORK_DIR}/tuning/intermediate/multi-net-path-tuning.md
```

同时，在报告目录下创建调优脚本文件夹：
```
${WORK_DIR}/tuning/multi-net-path-tuning/
├── tuning.sh              # 动态生成的入口脚本
└── multi_net_path_tune.sh # 复制的基础脚本
```

---

## 契约输出

输出契约格式参见 [contract-spec.md](../contract-spec.md)，本指南特有字段：

```yaml
skill_name: "opentunex-multi-net-path-tuning"
input:
  report_dir: "[actual report_dir]"
  fusion_report: "[actual fusion_report]"
  intermediate_path: "[actual intermediate_path]"
output:
  intermediate_path: "[actual intermediate_path]"
constraints_acknowledged: [ST-01~ST-04]
```