---
name: opentunex-multi-net-path-analysis
description: 评估 oenetcls/venetcls 网卡多路径调优特性的适用性，并输出调优参数建议。适用：≥2 NUMA 节点 且 存在支持多队列的物理网卡 且 运行 Redis/Nginx/MySQL 等网络密集型业务。不适用：单 NUMA 环境、纯计算负载、已启用其他中断亲和方案、单机调优。触发词：多队列网卡多 NUMA、跨 NUMA 中断、网卡多路径、multi_net_path_tune、oenetcls、venetcls。
---

# 网卡多路径瓶颈分析

> **本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md)，数据目录名固定为 `opentunex-multi-net-path-analysis_collect`。**

## 0. 30 秒判断（必读）

**本技能做什么**：基于 `preanalysis.json` 中的预解析数据，判断 `multi_net_path_tune` 特性在目标机器是否值得启用，并给出具体调优参数。

**输入**：`${DATA_DIR}` 下的采集文件（`kernel_config_info.txt` / `static_info.txt` / `cpu_detail_info.txt` / `process_detail_info.txt` / `network_metrics_analysis.txt`）。
**输出**：`${WORK_DIR}/analysis/opentunex-multi-net-path-analysis_collect/result.md` + 契约 YAML。

**硬性触发条件**（同时满足才进入决策）：
- 多 NUMA（`NUMA_NODES ≥ 2`）
- 网络密集型业务存在（Redis / Nginx / MySQL）

**绝不使用本技能**：
- 单 NUMA 节点（无跨节点优化空间）
- 单网卡
- 用户明确说"我不打算动内核模块"
- 已使用其他中断亲和方案（如 RPS/RFS 自定义配置）

**强约束**（违反会导致结果错误）：
1. **必须先跑 `scripts/preanalysis.sh` 生成 `preanalysis.json`**，禁止直接读原始数据自行拼接
2. **禁止 Read/cat `preanalysis.sh` 脚本内容** — 直接执行，不理解实现
3. **本技能只输出建议，不执行 `modprobe` / `ethtool` / `systemctl` 等调优命令**
4. **`recommended_params` 字段已由脚本算好，直接采用，禁止再自行推导**

---

## 1. 执行流程

按顺序完成 5 步，**不得跳过任意一步**：

| 步骤 | 操作 | 产出 |
|------|------|------|
| 1 | 执行 `preanalysis.sh`，生成 `preanalysis.json` | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，得到决策变量 | 决策变量集 |
| 3 | 按 §3 决策树输出适用性结论 | 结论 + 缺口列表 |
| 4 | 按 §5 模板生成 `result.md` | 分析报告 |
| 5 | 按 §7 模板生成契约 YAML | 契约文件 |

### 步骤 1：执行 preanalysis.sh

**本地模式**（`execution_mode=local`）：
```bash
bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-multi-net-path-analysis_collect
```

**远端模式**（`execution_mode=remote`）：
1. `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-multi-net-path-analysis/"`
2. `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-multi-net-path-analysis/`
3. `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-multi-net-path-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-multi-net-path-analysis_collect"`
4. 超时设 1200 秒

> `preanalysis.json` 生成在 `${DATA_DIR}/opentunex-multi-net-path-analysis_collect/`，**远端模式下必须在远端**，禁止 scp 回本地。

### 步骤 2：读取 preanalysis.json

- **本地**：`Read` 工具读取 `${DATA_DIR}/opentunex-multi-net-path-analysis_collect/preanalysis.json`
- **远端**：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-multi-net-path-analysis_collect/preanalysis.json"` 流回上下文

字段定义见 [附录 A](#附录-a-preanalysisjson-字段定义)。

### 步骤 3-5

- 步骤 3：按 §3 决策树输出适用性结论
- 步骤 4：按 §5 模板生成 `result.md`
- 步骤 5：按 §6 模板生成契约 YAML

---

## 2. 模块名兼容性

脚本支持两个候选模块名，按优先级探测：
1. `oenetcls`（绝大多数发行版）
2. `venetcls`（部分定制内核）

**实际识别到的名字存放在 `preanalysis.json` 的 `oenetcls.name` 字段。** SKILL 与后续调优脚本统一引用 `${OENETCLS_NAME}`，禁止在硬编码中写死任一名称。

---

## 3. 决策树（核心逻辑）

> **原则**：按 M1 → M5 顺序检查硬性不适用；命中 M2/M3/M4 不短路，继续到 M6-M8 评估场景收益。
> **所有「多条件」均为「且」关系，除非显式标注「或」。**

### 3.1 硬性检查（命中即短路）

| 编号 | 条件 | 结论 | 说明 |
|------|------|------|------|
| **M1** | `OENETCLS_LOADED = true` | **已启用（不适用）** | 模块已加载，无需重复操作 |
| **M5** | `NUMA_NODES ≤ 1` | **不建议启用（不适用）** | 单 NUMA 无跨节点优化空间 |

### 3.2 软性缺口（命中后记录但不短路，继续到 3.3）

| 编号 | 条件 | 记录 | 说明 |
|------|------|------|------|
| **M2** | `OENETCLS_AVAILABLE = false` | `MULTI_NET_PATH_UNSUPPORTED_GAP += "内核不支持 oenetcls 模块"` | 环境支持缺口 |
| **M3** | 所有网卡 `nic_details[].recommend_enable != true` | `MULTI_NET_PATH_UNSUPPORTED_GAP += "所有网卡 ntuple 不可配置或Combined队列数<=1或流量<=2048 rxkB/s"` | 硬件能力缺失或网卡流量过小 |
| **M4** | `IRQBALANCE_ACTIVE = "active"` | `IRQBALANCE_RUNNING = true` | 运行时可恢复缺口 |

> **注意**：`recommend_enable` 已由脚本预计算（基于 has_ntuple=true + ntuple_fixed=no + max_q>1 + rxkB>2048 四项），无需重新判定。
> `ntuple_fixed` 字段语义：`"no"` = 可配置、`"yes"` = 被 [fixed] 锁定、`"N/A"` = 不适用。

### 3.3 场景收益评估（按优先级，命中即输出）

| 编号 | 条件 | 结论 |
|------|------|------|
| **M6** | `NUMA_NODES ≥ 2` 且`recommended_params.ifnames`非空 且 `apps.redis or apps.nginx or apps.mysql` 任一为 true | **建议启用（高收益）** |
| **M7** | `NUMA_NODES ≥ 2` 且`recommended_params.ifnames`非空 | **建议启用（中收益）** |
| **M8** | `interrupt_overview` 包含"集中在少数核心" 且`recommended_params.ifnames`非空 | **建议启用** |
| **M9** | 以上均不满足 | **收益有限** |

### 3.4 SB-06 后置修正（场景匹配 + 环境缺口）

> 当 M6/M7/M8 命中（即场景匹配）时，**必须**应用本节修正；不能因为 M2/M3/M4 缺口就输出"不建议启用"。

| 条件 | `applicability` | `suggestion` 前缀 | `severity` |
|------|----------------|-------------------|-----------|
| M6/M7/M8 命中 且 `MULTI_NET_PATH_UNSUPPORTED_GAP` 非空 | `limited_benefit` | `[当前系统不支持（{缺口}），需 {安装 oenetcls 模块 / 更换支持 ntuple和多队列 的网卡 / 提高网卡流量 > 2048 rxkB/s} 后方可实施] ` | `low` |
| M6/M7/M8 命中 且 仅 `IRQBALANCE_RUNNING=true` | `applicable` | （无前缀） | 按 M6/M7/M8 原等级 |
| M6/M7/M8 未命中 | `not_applicable` | 填"不适用原因" | `low` |

### 3.5 中断亲和深度评估（补充佐证，不影响主结论）

仅当 §3.3 命中 M6/M7/M8 时执行，用于在 result.md 中提供补充说明：

- `interrupt_overview` 显示"集中在 ≤2 核心" → 补充"中断处理瓶颈明显，启用后可分散到各 NUMA 节点本地处理"
- 推荐网卡的 `numa_span ≥ 2` → 补充"中断跨 NUMA，多路径收益明确"
- 目标应用 PID 不在推荐网卡所在 NUMA 节点 → 补充"跨 NUMA 中断开销显著，强烈推荐启用"

### 3.6 决策树速查图

```
                      ┌─────────────┐
                      │ 读取 JSON   │
                      └──────┬──────┘
                             │
                  ┌──────────┴──────────┐
                  ▼                     ▼
            M1: 已加载            M5: 单NUMA
            → 已启用              → 不建议启用
                  │                     │
                  └──────────┬──────────┘
                             ▼
                  M2/M3/M4 检查缺口（记录不短路）
                             │
                             ▼
                       M6/M7/M8?
                       ┌─────┴─────┐
                       ▼           ▼
                      命中        未命中
                       │           │
                       ▼           ▼
                  SB-06 修正    → 收益有限
                  输出结论
```

---

## 4. 调优参数（直接采用 `recommended_params`）

> `preanalysis.json` 的 `recommended_params` 字段已由脚本预计算全部调优参数，**禁止重新推导**。

### 4.1 字段映射

| JSON 字段 | 含义 | 取值范围 |
|-----------|------|----------|
| `recommended_params.module_name` | 实际模块名 | `oenetcls` / `venetcls` |
| `recommended_params.ifnames` | 推荐网卡列表（`#` 拼接） | 空字符串 = 终止调优 |
| `recommended_params.appname` | 目标应用名（`#` 拼接） | 空 = 全局使能 |
| `recommended_params.mode` | 工作模式 | `0`=ntuple（默认）/ `1`=flow（仅当推荐 NIC 最小 max_q≤1） |
| `recommended_params.strategy` | 中断分布策略 | `0`=缺省 / `1`=Cluster均分(NUMA≥4) / `2`=NUMA均分(NUMA=2) / `3`=用户自定义 |
| `recommended_params.debug` | 调试开关 | `0`=关闭（生产默认）/ `1`=开启 |
| `recommended_params.match_ip_flag` | 按目的 IP 分流 | `0`=不按（默认）/ `1`=按 |
| `recommended_params.irqname` | 中断描述匹配串 | 驱动映射：mlx5→`mlx5_comp`、ixgbe→`ixgbe-*`、其他→`comp` |
| `recommended_params.rxq_multiplex_limit` | mode=0 下每队列可复用的 TCP 流数 | `1`（默认）；推荐 NIC 最小 max_q≤4 时放大到 `4` |
| `recommended_params.lo_rps_policy` | loopback RPS 策略 | `0`=关闭 / `1`=NUMA内打散 / `2`=Cluster内打散 |
| `recommended_params.rps_policy` | 网卡 RPS 策略 | 同上 |

### 4.2 使能命令模板（用户确认后由用户在目标机器执行）

```bash
# 1. 停止 irqbalance
systemctl stop ${IRQBALANCE_SERVICE_NAME}    # 多数系统: irqbalance, 部分 Debian: irqbalance-ng

# 2. 确保推荐网卡的 ntuple 已开启
for iface in $(echo ${RECOMMENDED_IFNAMES} | tr '#' ' '); do
    ethtool -K $iface ntuple on
done

# 3. 加载模块
modprobe ${RECOMMENDED_MODULE_NAME} \
    mode=${RECOMMENDED_MODE} \
    appname="${RECOMMENDED_APPNAME}" \
    ifname="${RECOMMENDED_IFNAMES}" \
    strategy=${RECOMMENDED_STRATEGY} \
    debug=${RECOMMENDED_DEBUG} \
    match_ip_flag=${RECOMMENDED_MATCH_IP_FLAG} \
    irqname="${RECOMMENDED_IRQNAME}" \
    rxq_multiplex_limit=${RECOMMENDED_RXQ_MULTIPLEX_LIMIT} \
    lo_rps_policy=${RECOMMENDED_LO_RPS_POLICY} \
    rps_policy=${RECOMMENDED_RPS_POLICY}
```

### 4.3 验证与回滚

```bash
# 验证
lsmod | grep -E 'oenetcls|venetcls'
ethtool -k <ifname> | grep ntuple    # 应输出 ntuple-filters: on

# 回滚
rmmod ${RECOMMENDED_MODULE_NAME}
systemctl start ${IRQBALANCE_SERVICE_NAME}
```

---

## 5. 输出：`result.md` 模板

将结果写入 `${WORK_DIR}/analysis/opentunex-multi-net-path-analysis_collect/result.md`。
**远端模式**：在远端机器直接落盘（`ssh ${user}@${ip} "mkdir -p <dir> && cat > <file>"` heredoc 写入），禁止先本地生成再 scp。

````markdown
# 网卡多路径瓶颈分析结果

## 1. 环境检查
| 检查项 | 结果 |
|--------|------|
| 网卡多路径模块 | {OENETCLS_NAME}: 已加载 / 可用未加载 / 不可用 |
| 物理网卡数量 | {N} |
| ntuple 可配置网卡数 | {M}/{N} |
| ntuple 已开启网卡数 | {K}/{N}（加载前需确保推荐网卡 on） |
| irqbalance 状态 | {active/inactive/unknown}（服务名: {IRQBALANCE_SERVICE_NAME}） |
| NUMA 节点数 | {N} |
| 目标业务进程 | redis: {是/否}, nginx: {是/否}, mysql: {是/否} |

## 2. 关键指标
| 指标 | 值 |
|------|-----|
| 物理网卡列表 | {eth0, eth1, ...} |
| ntuple 详情 | {eth0: has_ntuple=true, ntuple_fixed=no, ...} |
| 队列（max/cur） | {eth0: 8/8, eth1: 4/4, ...} |
| 流量 rxkB/s | {eth0: 3456, eth1: 1234, ...} |
| 中断分布 | {interrupt_overview} |
| 跨 NUMA 风险 | {是/否/无法判断} |

## 3. 适用性评估
| 评估维度 | 结果 | 证据 |
|---------|------|------|
| 内核模块支持 | ✅/❌ | {OENETCLS_NAME}: {状态} |
| 硬件过滤能力 | ✅/❌ | ntuple可配置: {M}/{N} |
| irqbalance 停止 | ✅/❌ | {svc}: {状态} |
| 多 NUMA 环境 | ✅/❌ | {N} 节点 |
| 多网卡环境 | ✅/❌ | {N} 张 |
| 目标应用存在 | ✅/❌ | {进程列表} |

**综合结论**: {结论} — {原因}
**判定路径**: {基础可行性 / 场景收益 / 网卡-应用精准匹配 / 中断亲和深度评估}
**预期收益**: {高收益: 中断延迟-20~40%, 吞吐+10~25% / 中收益: 中断分布优化}

**启用前提**:
1. 模块 `{OENETCLS_NAME}` 可用且未加载
2. ≥1 张网卡 ntuple 可配置
3. 推荐网卡 ntuple 已开启
4. irqbalance 已停止
5. ≥2 个 NUMA 节点

**回滚参考**: `rmmod {OENETCLS_NAME}` + `systemctl start {IRQBALANCE_SERVICE_NAME}`

## 4. 调优参数推荐
> 直接采用 `preanalysis.json` 的 `recommended_params` 字段值，禁止重新计算。

| 参数 | 推荐值 |
|------|--------|
| module_name | {RECOMMENDED_MODULE_NAME} |
| mode | {RECOMMENDED_MODE} |
| ifname | {RECOMMENDED_IFNAMES} |
| appname | {RECOMMENDED_APPNAME} |
| strategy | {RECOMMENDED_STRATEGY} |
| debug | {RECOMMENDED_DEBUG} |
| match_ip_flag | {RECOMMENDED_MATCH_IP_FLAG} |
| irqname | {RECOMMENDED_IRQNAME} |
| rxq_multiplex_limit | {RECOMMENDED_RXQ_MULTIPLEX_LIMIT} |
| lo_rps_policy | {RECOMMENDED_LO_RPS_POLICY} |
| rps_policy | {RECOMMENDED_RPS_POLICY} |

## 5. 网卡级分析详情
| 网卡 | ntuple | ntuple_fixed | queues | rxkB/s | multi_path | recommend_enable | NUMA 跨度 | 判定 |
|------|--------|--------------|--------|--------|------------|------------------|----------|------|
| {eth0} | {1/0} | {no/yes/N/A} | {max/cur} | {rxkB} | {yes/no} | {yes/no/-} | {nodeX,nodeY(span=N)} | {纳入/排除 + 原因} |

## 6. 结构化数据
```json
{
  "applicability": "applicable|limited_benefit|not_applicable",
  "id": "multi_net_path",
  "suggestion": "{按 §3.4 拼接}",
  "equivalence_class": "multi_net_path",
  "activation_requirement": "immediate",
  "module_name": "{OENETCLS_NAME}",
  "estimated_gain": {
    "primary_metric": "network_latency",
    "severity": "high|medium|low",
    "description": "{收益描述}"
  },
  "conflicts": [],
  "prerequisites": [],
  "synergy_with": [],
  "scenario_priority": 10,
  "source": "skill_output",
  "cross_skill_relations": {}
}
```

**字段填充规则**：
- `applicability`：
  - §3.3 M6/M7/M8 命中且无环境缺口 → `applicable`
  - §3.3 M6/M7/M8 命中但有环境缺口 → `limited_benefit`
  - §3.3 M9 / M1 / M5 命中 → `not_applicable`
- `scenario_priority`：识别到 redis/nginx/mysql → `10`，否则 → `7`
- `severity`：M6 → `high`，M7/M8 → `medium`，其他 → `low`
- `suggestion`：按 §3.4 表拼接，limited_benefit 须带 `[当前系统不支持...]` 前缀
````

---

## 6. 契约输出

写入契约 YAML，格式见 [contract-spec.md](../references/contract-spec.md)：

```yaml
skill_name: "opentunex-multi-net-path-analysis"
input:
  analysis_dir: "[actual analysis_dir]"
  data_dir: "[actual data_dir]"
  collect_dir: "[actual collect_dir]"
output:
  analysis_report_path: "[actual analysis_report_path]"
constraints_acknowledged: [SB-01~SB-07]
```

---

## 附录 A：preanalysis.json 字段定义

> **关键提醒**：以下字段中标记「已预计算」的，**直接采用，禁止重新推导**。

### A.1 环境与模块

| JSON 路径 | 类型 | 含义 |
|-----------|------|------|
| `oenetcls.loaded` | bool | 模块是否已加载（`/sys/module/<name>` 或 `lsmod` 命中） |
| `oenetcls.available` | bool | 模块是否可用（`modinfo` 能查到） |
| `oenetcls.name` | string | 实际识别到的模块名 `oenetcls` 或 `venetcls` |
| `irqbalance` | string | `active` / `inactive` / `unknown` |
| `irqbalance_service_name` | string | 实际服务单元名 `irqbalance` 或 `irqbalance-ng` |
| `numa_nodes` | int | NUMA 节点数 |
| `numa_cpu_map` | object | `{node0: [cpu...], node1: [cpu...]}` |
| `interrupt_overview` | string | "集中在少数核心(≤2)" / "分布在N个核心" / "均匀分布在N个核心" / "无数据" |
| `apps.redis` | bool | 检测到 redis-server 进程 |
| `apps.nginx` | bool | 检测到 nginx 进程 |
| `apps.mysql` | bool | 检测到 mysqld 进程 |
| `target_app_pid` | int\|null | 首个匹配到的应用进程 PID |

### A.2 网卡列表

| JSON 路径 | 类型 | 含义 |
|-----------|------|------|
| `physical_nics` | string[] | 物理网卡名列表（已过滤 lo/docker/veth/br-/tun/tap） |
| `nic_details[].iface` | string | 网卡名 |
| `nic_details[].has_ntuple` | bool | `ethtool -k` 中 ntuple-filters 是否存在 |
| `nic_details[].ntuple_fixed` | string | `no`=可配置 / `yes`=被 [fixed] 锁定 / `N/A`=不适用 |
| `nic_details[].ntuple_enabled` | string | `on` / `off`（`ethtool -k` 当前状态） |
| `nic_details[].max_q` / `cur_q` | int | Combined 队列（或 RX+TX 之和） |
| `nic_details[].rxpck` / `rxkb` | number | `sar -n DEV` 采样均值 |
| `nic_details[].numa_span` | int | IRQ 涉及的 NUMA 节点数 |
| `nic_details[].numa_annotation` | string | 脚本预计算的 NUMA 标注 |
| `nic_details[].driver` | string | 网卡驱动名（`mlx5_core` / `ixgbe` / ...） |
| `nic_irq_map` | object | `{iface: [{irq, smp_affinity, cpu_list}, ...]}` |

### A.3 已预计算的判定字段（**直接使用**）

| JSON 路径 | 含义 | 判定逻辑 |
|-----------|------|----------|
| `nic_details[].multi_path` | 是否具备多路径硬件基础 | `has_ntuple=true` 且 `ntuple_fixed=no` |
| `nic_details[].recommend_enable` | 是否建议使能 | `multi_path=true` 且 `max_q>1` 且 `rxkB>2048`（或流量缺失视为通过） |

### A.4 已预计算的调优参数（**直接使用**）

见 §4.1 字段映射表。

---

## 附录 B：常见问题排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `oenetcls.name` 为空或 `oenetcls` | 脚本未识别到模块 | 确认采集文件含 `kernel_config_info.txt` 且包含 modinfo 节 |
| `nic_details` 为空 | 网络采集文件缺失或网卡全是虚拟网卡 | 检查 `network_metrics_analysis.txt` 中是否有 `--- ethX ---` 段 |
| `numa_nodes=1` 但用户期望 ≥2 | NUMA 拓扑采集失败 | 检查 `static_info.txt` 中 `--- NUMA Topology ---` 节 |
| `recommended_params.ifnames` 为空 | 没有网卡通过 recommend_enable 判定 | 检查网卡是否支持多队列、检查 ntuple 是否被 [fixed] 锁定、提升流量（rxkB 需 > 2048） |
| `IRQBALANCE_SERVICE_NAME` 报 `irqbalance-ng` | 部分 Debian 衍生版服务名差异 | 建议命令中使用此字段值，不要硬编码 |
