---
name: "opentunex-data-collection"
description: "数据采集技能。唯一采集方式：执行 scripts/bottleneck_data_collector.sh 瓶颈分析专用采集脚本，产出瓶颈场景分析所需的 13 个数据文件。当用户提到 CPU 高、内存不足、磁盘慢、网络丢包、进程异常、性能瓶颈等关键词，或需要采集系统性能数据时，必须使用本技能。"
---

# 数据采集技能

本技能**只有一种采集模式**：调度执行 `scripts/bottleneck_data_collector.sh`。脚本输出直接落盘到数据文件，本技能不读取或改写采集内容。

> 采集产出的数据文件供 `opentunex-scenario-bottleneck` 各场景 preanalysis.sh 直接解析。完整约束见 [constraints-data-collection.md](references/constraints-data-collection.md)。

---

## 采集执行：`bottleneck_data_collector.sh`

```bash
# 默认采集方式，不指定PID
bash scripts/bottleneck_data_collector.sh -d 10 -o ${WORK_DIR}/collect

# 当明确有特定应用（mysql/redis 等）需要指定 PID 采集时：先用 pgrep 取一个**活跃** PID，
# 再传给脚本。**严禁**把 pgrep 多行输出（master+worker、多实例、子进程）整列传进去——
# 脚本已升级校验：含逗号的多 PID 会直接报错并退出。
APP_PID=$(pgrep -a "$APP_NAME" | awk '$2!="Z" {print $1; exit}')
[ -n "$APP_PID" ] && bash scripts/bottleneck_data_collector.sh -d 10 -p "$APP_PID" -o ${WORK_DIR}/collect
```

| 参数 | 说明 | 必填 |
|------|------|------|
| `-d <秒>` | 采集持续时间 | 是（除非 -C/-h） |
| `-p <PID>` | 监控进程 ID，**仅传一个活跃 PID**（禁止逗号分隔）；热点/系统调用分析必需 | 否 |
| `-o <目录>` | 输出目录，${WORK_DIR}/collect | 否 |
| `-c <项目>` | 采集项目，逗号分隔；默认全部 | 否 |
| `-C` | 仅前置检查，不执行采集 | 否 |
| `-h` | 显示帮助信息 | 否 |

### 输出数据文件

写入 `-o` 指定目录，值为${WORK_DIR}/collect：

| 文件 | 内容 |
|------|------|
| `static_info.txt` | 硬件规格、OS版本、内核参数、调度特性 |
| `global_bottleneck.txt` | CPU/内存/IO/网络全局瓶颈指标 |
| `top_processes.txt` | 顶级资源消耗进程列表 |
| `cpu_detail_info.txt` | CPU 深度信息（/proc/stat 多采样等） |
| `kernel_config_info.txt` | 内核配置、调度特性、模块 |
| `process_detail_info.txt` | 进程/线程详情、线程生命周期轮询 |
| `container_info.txt` | 容器资源监控（CPU/内存/IO 配额） |
| `memory_metrics_analysis.txt` | 内存深度分析（NUMA/缺页/Swap） |
| `network_metrics_analysis.txt` | 网络深度分析（网卡配置/IRQ/tcp） |
| `io_metrics_analysis.txt` | I/O 深度分析（调度器/队列/挂载） |
| `hotspot_analysis.txt` | 热点函数分析（perf，需 -p） |
| `syscall_analysis.txt` | 系统调用分析（strace，需 -p） |
| `pmu_info.txt` | PMU 远程访问与 HHA 分析（仅 aarch64） |

---

## 执行决策

```
需要采集数据
└── 目标是否为远端服务器（用户输入中含 IP）？
    ├── 是 → 必须组合 opentunex-remote-execution 技能（见下节）
    └── 否 → 本地直接 bash 执行
```

**任何采集需求都通过 `bottleneck_data_collector.sh` 完成，不存在其他采集脚本或模式。**

> **注意**：
> - 热点函数分析、系统调用分析**必须指定 PID**（通过 `-p`，仅一个活跃 PID，详见本节说明）
> - 脚本已硬校验：`-p` 出现逗号会被直接拒绝，避免 pgrep 多行输出被误传
> - 建议以 root 运行；非 root 下 perf、strace 等采集功能受限
> - 判断标准：**用户输入中是否明确给出了远端 IP 地址**——如果给了 IP，必须走远程执行流程

---

## 远程执行场景（CRITICAL — 目标为远端服务器时必读）

当采集目标为远端 Linux 服务器时，本技能必须与 `opentunex-remote-execution` 技能组合使用，禁止绕过脚本直接合成命令执行。

### 正确的远程执行流程

```
本地 scripts/bottleneck_data_collector.sh
    │
    ▼
scp 上传到远端 /tmp/bottleneck_data_collector.sh
    │
    ▼
ssh -q -tt 远端执行脚本
    │
    ▼
脚本输出直接落盘到远端 -o 指定目录（数据不出服务器）
```

### 强制规则

1. **必须上传脚本文件**：将脚本文件通过 `scp` 上传到远端（如 `/tmp/bottleneck_data_collector.sh`）后执行。**禁止**读取脚本内容后拆解为单条命令内联到 SSH 中执行。
2. **禁止内联合成命令**：**禁止**自行合成等价采集命令（如 mpstat、iostat、vmstat 等）直接 SSH 执行。采集逻辑必须以脚本文件形式完整上传。
3. **脚本文件完整性**：上传的脚本文件必须与本地 `scripts/` 中的源文件**字节一致**，禁止通过 heredoc / echo / printf 等方式在远端重建脚本内容。
4. **数据不出服务器**：采集数据留在远端落盘，禁止拷贝回本地分析。
5. **`${WORK_DIR}` 是远端路径**：远端模式下 `-o` 参数的 `${WORK_DIR}` 是**远端服务器上**的目录（`/srv/opentunex/<YYYYMMDD_HHMMSS>/`，由 `witty-opentunex` 初始化）。输出目录必须在**远端**创建（`ssh` 执行 `mkdir`），**禁止**在 agent 本地（如 Windows）创建同名目录或把采集数据写到本地。详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

### 远程执行示例

```bash
# Step 1: 远端创建输出目录（${WORK_DIR} 是远端路径）
ssh ${user}@${ip} "mkdir -p ${WORK_DIR}/collect"

# Step 2: 上传脚本文件到远端
scp scripts/bottleneck_data_collector.sh ${user}@${ip}:/tmp/

# Step 3: SSH 远端执行（-o 指向远端工作目录；引号内是远端 Linux 命令）
# 默认采集方式，不指定PID
ssh -q -tt ${user}@${ip} "bash /tmp/bottleneck_data_collector.sh -d 10 -o ${WORK_DIR}/collect"

# 当明确有特定应用（mysql/redis 等）需要指定 PID 采集时：远端先取一个活跃 PID，
# 再带进 ssh 单引号内。同样的禁令：禁止把 pgrep 多行输出整列塞给 -p，脚本会拒绝执行。
APP_PID=$(ssh -q ${user}@${ip} "pgrep -a '$APP_NAME' | awk '\$2!=\"Z\" {print \$1; exit}'")
ssh -q -tt ${user}@${ip} "bash /tmp/bottleneck_data_collector.sh -d 10 -p '$APP_PID' -o ${WORK_DIR}/collect"
```

> agent 主机为 Windows 时，本地侧命令（`scp` 路径、引号）按 `opentunex-remote-execution` 的平台指南翻译（PowerShell 双引号、`$env:TEMP` 等）；`ssh` 引号内的远端命令保持 Linux 语法不变。

**❌ 禁止的做法**（会导致绕过脚本、数据格式不一致）：
```bash
# 错误：将采集项拆解为单条命令执行
ssh ${user}@${ip} "mpstat -P ALL 1 5 > /tmp/cpu.txt"
ssh ${user}@${ip} "free -h > /tmp/mem.txt"
```

> **注意**：如果 agent 主机本身就在目标服务器上（本地采集），则无需远程执行，直接按上方示例在本地 bash 中执行脚本即可。

---

## 输出位置约定

| 项 | 路径 |
|----|------|
| 采集数据 | `-o` 指定目录，或默认 `bottleneck_data_<arch>_<YYYYMMDD_HHMMSS>/`（相对当前目录） |

> `WORK_DIR` 可通过环境变量 `OPENTUNEX_WORK_DIR` 自定义，默认 `/srv/opentunex/<YYYYMMDD_HHMMSS>/`

---

## 错误处理

| 场景 | 处理方式 |
|------|---------|
| 工具不可用（sar、perf、mpstat 等） | 脚本自动降级：标注不可用项，继续其他维度，不中断流程 |
| perf/strace 不可用或非 root | 热点/系统调用分析失败并标注，其他采集继续 |
| 未指定 `-p` | 热点/系统调用分析跳过并标注 |
| 非 aarch64 架构 | PMU 采集自动跳过 |
| 部分采集失败 | 标注失败项，继续其他采集，不中断流程 |

---

## 按需加载资源

| 资源 | 何时读取 |
|------|---------|
| [collection-items-reference.md](references/collection-items-reference.md) | 需要查看每个数据文件具体包含哪些数据项时 |
| [constraints-data-collection.md](references/constraints-data-collection.md) | 查看完整约束列表时 |
| `bash scripts/bottleneck_data_collector.sh -h` | 需要查看全部采集项目时 |
