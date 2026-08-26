---
name: "opentunex-data-collection"
description: "数据采集技能。直接调度各维度采集脚本（CPU/内存/IO/网络/进程/系统/内核/容器/PMU）执行系统数据采集，脚本输出直接落盘到报告文件。当用户提到 CPU 高、内存不足、磁盘慢、网络丢包、进程异常、系统基线、内核参数、容器资源、PMU 事件、NUMA 远程访问等关键词，或需要采集系统性能数据时，必须使用本技能。支持单项采集或全量采集。"
---

# 数据采集技能

直接调度采集脚本执行系统数据采集，脚本输出直接落盘到报告文件，本技能不读取或改写采集内容。

> 所有脚本位于 `scripts/` 目录下。完整约束见 [constraints-data-collection.md](references/constraints-data-collection.md)。

---

## 远程执行场景（CRITICAL — 当目标为远端服务器时必读）

**当采集目标为远端 Linux 服务器时，本技能必须与 `opentunex-remote-execution` 技能组合使用，禁止绕过脚本直接合成命令执行。**

### 正确的远程执行流程

```
本地 scripts/ 目录中的脚本文件
    │
    ▼
scp 上传到远端 ${WORK_DIR}/collect/scripts/
    │
    ▼
ssh 远端执行上传后的脚本
    │
    ▼
脚本输出直接落盘到远端 ${WORK_DIR}/collect/
```

### 强制规则

1. **必须上传脚本文件**：将 `scripts/` 下的脚本文件通过 SCP 上传到远端 `${WORK_DIR}/collect/scripts/`，再通过 SSH 执行。**禁止**将脚本内容读出来后拆解为单条命令内联到 SSH 中执行。
2. **禁止内联合成命令**：**禁止**读取 `collection-items-reference.md` 后自行合成等价采集命令（如 mpstat、iostat、vmstat 等）直接 SSH 执行。采集逻辑必须以脚本文件形式完整上传。
3. **脚本文件完整性**：上传的脚本文件必须与本地 `scripts/` 中的源文件**字节一致**，禁止通过 heredoc / echo / printf 等方式在远端重建脚本内容。
4. **远端路径约定**：脚本上传到远端 `${WORK_DIR}/collect/scripts/`，执行后产出文件写入远端 `${WORK_DIR}/collect/`（ `${WORK_DIR}` 默认按 `/srv/opentunex/<YYYYMMDD_HHMMSS>/` 这个格式根据当前日期时间生成）。

### 远程执行示例

```bash
# 标准流程：上传脚本 → 远端执行
# Step 1: 上传脚本文件到远端
scp scripts/collect_all.sh ${user}@${ip}:${WORK_DIR}/collect/scripts/
scp scripts/collect_cpu_info.sh ${user}@${ip}:${WORK_DIR}/collect/scripts/
scp scripts/collect_mem_info.sh ${user}@${ip}:${WORK_DIR}/collect/scripts/
# ... (上传所有需要的采集脚本)

# Step 2: SSH 远端执行（脚本已上传，直接调用）
ssh -q -tt ${user}@${ip} "bash ${WORK_DIR}/collect/scripts/collect_all.sh ${WORK_DIR}/collect/ all 10 1"

# 一键采集同理
scp scripts/server_data_collector.sh ${user}@${ip}:${WORK_DIR}/collect/scripts/
ssh -q -tt ${user}@${ip} "bash ${WORK_DIR}/collect/scripts/server_data_collector.sh -d 60 -o ${WORK_DIR}/collect/"
```

**❌ 禁止的做法**（会导致绕过脚本、数据格式不一致）：
```bash
# 错误：将采集项拆解为单条命令执行
ssh ${user}@${ip} "mpstat -P ALL 1 5 > /tmp/cpu.txt"
ssh ${user}@${ip} "free -h > /tmp/mem.txt"
ssh ${user}@${ip} "iostat -xz 1 5 > /tmp/io.txt"
# ... 这种做法绕过了脚本的完整采集逻辑，产出格式与下游契约不兼容
```

> **注意**：如果 agent 主机本身就在目标服务器上（本地采集），则无需远程执行，直接按下方示例在本地 bash 中执行脚本即可。判断标准：**用户输入中是否明确给出了远端 IP 地址**——如果给了 IP，必须走远程执行流程。

---

---

## 三种采集方式

### 1. 一键采集：`server_data_collector.sh`

适用：全量诊断、热点/系统调用/微架构分析、devkit 工具（aarch64）。默认使用该采集方式。

```bash
# 全量采集（60 秒）
bash scripts/server_data_collector.sh -d 60

# 指定进程采集（热点分析等必需）
bash scripts/server_data_collector.sh -d 60 -p 1234

# 指定输出目录
bash scripts/server_data_collector.sh -d 60 -o ${WORK_DIR}/collect/profiling

# 指定采集项目（项目名见 -h 输出）
bash scripts/server_data_collector.sh -d 30 -c collect_cpu_detail_info,collect_mem_metrics

# 仅前置依赖检查 / 查看采集项目列表
bash scripts/server_data_collector.sh -C
bash scripts/server_data_collector.sh -h
```

| 参数 | 说明 | 必填 |
|------|------|------|
| `-d <秒>` | 采集持续时间 | 是（除非用 -C/-h） |
| `-p <PID>` | 监控进程ID，逗号分隔；热点/系统调用/微架构分析必需 | 否 |
| `-o <目录>` | 输出目录，默认 `profiling_data_<arch>_<时间戳>/` | 否 |
| `-c <项目>` | 指定采集项目，逗号分隔；默认全部 | 否 |
| `-t <秒>` | 命令超时缓冲，默认 60 | 否 |

输出：每个采集项对应一个 `.txt` 文件，写入 `-o` 指定目录。

---

### 2. 轻量编排：`collect_all.sh`

适用：只需 CPU/内存/IO/网络/进程/系统/内核/容器/PMU 这 9 个基础维度，不需要热点分析等高级功能。

```bash
# 全量采集（9 个维度，并行调度）
bash scripts/collect_all.sh "$BATCH_DIR"

# 单项/多项采集
bash scripts/collect_all.sh "$BATCH_DIR" cpu
bash scripts/collect_all.sh "$BATCH_DIR" cpu,mem,io

# 指定采集时长和间隔
bash scripts/collect_all.sh "$BATCH_DIR" all 10 1
```

| 位置 | 参数 | 默认值 | 说明 |
|------|------|--------|------|
| $1 | batch_dir | ${WORK_DIR}/collect/ | 批次输出目录 |
| $2 | items | all | 采集项：all 或逗号分隔列表 |
| $3 | duration | 10 | 采集时长（秒/次） |
| $4 | interval | 1 | 采集间隔（秒） |

可选 items 值：`cpu` `mem` `io` `net` `process` `system` `kernel` `container` `pmu` `process-thread-poll`

并行调度：组1(cpu/mem/io) → 组2(net/process) → 组3(system) → 串行(kernel/container) → 独立(pmu/process-thread-poll)

输出：`<item>-collection_report.txt` 写入 batch_dir。

---

### 3. 单项采集脚本（独立调用）

适用：只需某个特定维度、瓶颈分析域要求补充采集、需要对单维度精细化采集。

```bash
mkdir -p "$BATCH_DIR"
bash scripts/<script>.sh "$BATCH_DIR" [duration] [interval]
```

| 脚本 | 适用场景关键词 |
|------|--------------|
| `collect_cpu_info.sh` | CPU高、负载大、NUMA、频率、mpstat |
| `collect_mem_info.sh` | 内存不足、OOM、Swap、大页、NUMA内存 |
| `collect_io_info.sh` | 磁盘慢、IO高、await延迟、iostat |
| `collect_net_info.sh` | 网络慢、丢包、重传、队列、网卡驱动 |
| `collect_process_info.sh` | 进程多、线程泄漏、上下文切换、pidstat |
| `collect_process_thread_poll.sh` | 线程创建/销毁频繁（eBPF 降级方案） |
| `collect_system_sar.sh` | 全貌、基线、sar、PSI、系统概况 |
| `collect_kernel_config.sh` | 内核参数、sysctl、模块、taint、启动参数 |
| `collect_container_info.sh` | 容器资源、Docker、cgroup、容器CPU/内存 |
| `collect_pmu_info.sh` | PMU事件、NUMA远程访问、perf stat |

输出：`<item>-collection_report.txt` 写入 batch_dir。

---

## 选用决策

```
需要采集数据
├── 目标是否为远端服务器（用户输入中含 IP）？
│   ├── 是 → 必须组合 opentunex-remote-execution：先 scp 上传脚本，再 ssh 执行
│   └── 否 → 本地直接执行，按下方决策树选择脚本
├── 需要完整诊断（热点/系统调用/微架构/devkit）？
│   └── server_data_collector.sh -d <秒> [-p <PID>] [-c <项目>]
├── 只需要 9 个基础维度？
│   └── collect_all.sh "$BATCH_DIR" [items] [duration] [interval]
└── 只需要某个特定维度？
    └── bash scripts/collect_<item>_info.sh "$BATCH_DIR" [duration] [interval]
```

> **注意**：
> - **远程目标必须先上传脚本**：当目标为远端服务器时，必须先通过 `opentunex-remote-execution` 的 SCP 将 scripts/ 下的文件上传到远端 `${WORK_DIR}/collect/scripts/`，再通过 SSH 执行。**禁止**将脚本内容拆解为单条命令直接 SSH 执行。
> - 热点函数分析、系统调用分析、微架构瓶颈分析**必须指定 PID**（通过 `-p`）
> - `server_data_collector.sh` 的采集项目名（如 `collect_cpu_detail_info`）与 `collect_all.sh` 的短名（如 `cpu`）不同，不要混用
> - 一键采集输出到 `-o` 目录，轻量编排和单项采集输出到 `$BATCH_DIR`

---

## eBPF 辅助脚本（无需直接调用）

以下脚本由 `collect_net_info.sh` 或 `collect_process_info.sh` 内部调用：

| 脚本 | 被调用方 |
|------|---------|
| `collect_net_ebpf_traffic.py` | collect_net_info.sh（进程间流量亲和性） |
| `collect_net_ebpf_queue.py` | collect_net_info.sh（线程队列分布） |
| `collect_process_ebpf_thread.py` | collect_process_info.sh（线程创建/销毁事件） |

---

## 输出位置约定

| 执行方式 | 输出路径 | 文件命名 |
|---------|---------|---------|
| 一键采集 | `-o` 指定目录或 `${WORK_DIR}/collect/profiling_data_<arch>_<时间戳>/` | `<采集项名>.txt` |
| 轻量编排/单项 | `${WORK_DIR}/collect/` | `<item>-collection_report.txt` |
| 采集日志 | `${WORK_DIR}/collect/collect_log/` | `<item>_<时间戳>.log` |

> `WORK_DIR` 可通过环境变量 `OPENTUNEX_WORK_DIR` 自定义，默认 `/srv/opentunex/<YYYYMMDD_HHMMSS>/`

---

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| 工具不可用（sar、perf 等） | 一键采集自动检测并提示安装；独立脚本自动降级 |
| devkit 工具缺失（aarch64） | 一键采集提示自动下载安装 |
| eBPF 环境不满足 | 跳过 eBPF 项，使用轮询方式降级 |
| 部分采集失败 | 标注失败项，继续其他维度，不中断流程 |
| Docker Daemon 不可用 | 容器采集使用纯 cgroup 模式 |
| 命令执行超时 | 一键采集按 `-t` 参数超时中止 |

---

## 按需加载资源

| 资源 | 何时读取 |
|------|---------|
| [collection-items-reference.md](references/collection-items-reference.md) | 需要查看每个维度具体采集哪些数据项时 |
| [constraints-data-collection.md](references/constraints-data-collection.md) | 查看完整约束列表时 |
| `bash scripts/server_data_collector.sh -h` | 需要查看一键采集支持的全部项目时 |
