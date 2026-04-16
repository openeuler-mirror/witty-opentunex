# top-down-bottleneck

自上而下系统瓶颈分析Skill，通过系统环境静态信息采集、动态指标收集和多层分析识别CPU、内存、IO、网络等瓶颈。

## 总体功能

提供系统级瓶颈分析，主要功能包括：

1. **系统环境静态信息采集** - 采集硬件规格、软件版本、内核启动参数
2. **全局瓶颈识别** - 识别系统级资源瓶颈
3. **进程级分析** - 识别高压力进程
4. **热点函数与系统调用分析** - perf热点函数和strace系统调用分析
5. **微架构分析** - CPU微架构层面分析
6. **基于证据的瓶颈分析** - 证据汇总、严重程度映射、优化建议
7. **迭代优化** - 支持反复分析直到定位问题

**Scope**: 仅分析OS级别资源，不包含应用层数据

## ⚠️ 重量级命令约束

`perf`和`strace`是重量级命令，会attach到目标进程并改变其运行时行为。**禁止在同一PID上并行运行重量级命令**，否则数据不可靠且可能导致目标进程崩溃。

| 类别 | 命令 | 可并行 | 原因 |
|------|------|--------|------|
| 轻量级 | mpstat, vmstat, iostat, pidstat, sar, free, ss, nstat, ps | ✅ | 只读观测 |
| 重量级 | perf record, perf top, perf stat, perf trace, strace | ❌ | Attach进程 |

**规则**: Phase 2.1轻量级命令可并行；Phase 3内Step 3.1→3.2必须串行；Phase 4内perf stat组必须串行。

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行

### 工具依赖

- `mpstat`, `vmstat`, `iostat` (sysstat包)
- `pidstat` (sysstat包)
- `sar` (sysstat包)
- `perf` (linux-tools-common)
- `numactl`, `lscpu`
- `strace`
- `dmidecode` (硬件信息，需root)

## 用法

### 自然语言输入示例

```
分析192.168.1.100的系统瓶颈
```

```
系统响应慢，帮我看看是哪里的瓶颈
```

```
进行CPU、内存、IO、网络的全面分析
```

### 执行流程

```
Phase 1: 系统环境静态信息采集
    ├→ 硬件规格: CPU/内存/磁盘/网卡型号
    ├→ 软件版本: OS/内核/工具版本
    └→ 内核启动参数: cmdline/sysctl/模块/调度器

Phase 2: 主负载识别与瓶颈分析
    ├→ Step 2.1: 全局资源分析
    │   ├→ CPU瓶颈指标
    │   ├→ 内存瓶颈指标
    │   ├→ IO瓶颈指标
    │   └→ 网络瓶颈指标
    │
    └→ Step 2.2: 进程级分析
        ├→ 高CPU进程
        ├→ 高内存进程
        └→ 高IO进程

Phase 3: 热点函数与系统调用分析 ⚠️重量级-必须串行
    ├→ Step 3.1: 热点函数分析 (perf) → 完成后
    └→ Step 3.2: 系统调用分析 (strace) → 完成后

Phase 4: 微架构瓶颈分析 ⚠️重量级-必须串行
    └→ PMU events: cache → branch/pipeline → NUMA (依次执行)

Phase 5: 基于证据的瓶颈分析
    ├→ 拓扑分析
    ├→ 瓶颈映射与严重程度
    ├→ 最终瓶颈汇总
    └→ OS级优化建议
```

### 输出示例

```markdown
## 系统瓶颈分析报告

### 系统环境静态信息
- Hostname: server01
- Kernel: 5.4.0-generic
- CPU: Intel Xeon E5-2680 v4, 2 sockets, 14 cores/socket, 28 threads
- Memory: 64GB DDR4 2400MHz
- Disk: sda 500GB SSD (mq-deadline), sdb 2TB HDD (mq-deadline)
- NIC: Intel X710 (driver: i40e)
- OS: openEuler 24.03
- Boot params: quiet splash

### 瓶颈汇总

| 类别 | 瓶颈 | 严重程度 | 证据 |
|------|------|----------|------|
| CPU | iowait高 | 高 | iowait > 20% |
| Memory | SWAP使用 | 中 | si/so > 10MB/s |
| Disk | %util高 | 高 | %util > 90% |

### 详细分析

#### CPU分析
- CPU利用率: 45% user, 25% sys, 30% iowait
- iowait异常 → 等待IO完成
- Load Average: 12.5 (高于CPU核心数)

#### 内存分析
- 已用: 58GB / 64GB (90%)
- Swap: 2GB / 8GB (25%)
- Page Fault: 12000/s

#### IO分析
- sda: %util = 95% (瓶颈!)
- await = 25ms (高)
- IOPS: 5000

### 建议
1. 优化IO瓶颈 (可能是MySQL缓冲池)
2. 减少内存压力
```

## 关键输出件

| 输出件 | 路径 | 说明 |
|--------|------|------|
| 静态系统信息 | Skill输出 | 硬件规格/软件版本/内核参数 |
| CPU分析 | Skill输出 | CPU瓶颈报告 |
| 内存分析 | Skill输出 | 内存瓶颈报告 |
| IO分析 | Skill输出 | IO瓶颈报告 |
| 网络分析 | Skill输出 | 网络瓶颈报告 |
| 进程分析 | Skill输出 | 高压力进程列表 |
| 热点分析 | Skill输出 | perf热点函数报告 |
| 系统调用分析 | Skill输出 | strace系统调用报告 |
| 微架构分析 | Skill输出 | PMU事件分析报告 |

## 一键采集脚本

各Phase提供一键采集脚本，可将该Phase所有命令串行执行完成：

| 脚本 | 参数 | 说明 | 运行时间 |
|------|------|------|----------|
| `scripts/phase1-static-info.sh` | 无 | 系统静态信息采集 | ~5s |
| `scripts/phase2.1-global-bottleneck.sh` | 无 | 全局资源瓶颈识别 | ~30s |
| `scripts/phase2.2-top-processes.sh` | 无 | 高资源消耗进程识别 | ~10s |
| `scripts/phase3.1-hotspot-function.sh` | `<PID>` | perf热点函数分析 (⚠️重量级) | ~60-90s |
| `scripts/phase3.2-syscall-analysis.sh` | `<PID>` | strace系统调用分析 (⚠️重量级) | 视进程活动 |
| `scripts/phase4-microarch.sh` | `<PID>` | 微架构PMU分析 (⚠️重量级) | ~1.5-2min |

⚠️ 重量级脚本必须严格按顺序执行：phase3.1 → phase3.2 → phase4，不可并行。

## 参考文档

- Phase 1 硬件规格: lscpu, dmidecode, lsblk, lspci
- Phase 1 软件版本: os-release, uname, tool -V
- Phase 1 内核启动参数: /proc/cmdline, sysctl, lsmod
- Phase 2.1 CPU瓶颈指标: mpstat, pidstat, vmstat
- Phase 2.1 内存瓶颈指标: free, vmstat, pidstat
- Phase 2.1 IO瓶颈指标: iostat, pidstat
- Phase 2.1 网络瓶颈指标: sar, ss, netstat
- Phase 2.2 进程级分析: pidstat, top
- Phase 3.1 热点函数: perf record, perf report, perf top
- Phase 3.2 系统调用: strace, perf trace
- Phase 4 微架构: perf stat, toplev
