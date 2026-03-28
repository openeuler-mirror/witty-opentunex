# top-down-bottleneck

自上而下系统瓶颈分析Skill，通过系统级数据收集和多层分析识别CPU、内存、IO、网络等瓶颈。

## 总体功能

提供系统级瓶颈分析，主要功能包括：

1. **系统信息收集** - 快速收集CPU、内存、磁盘、网络指标
2. **全局瓶颈识别** - 识别系统级资源瓶颈
3. **进程级分析** - 识别高压力进程
4. **微架构分析** - CPU微架构层面分析
5. **迭代优化** - 支持反复分析直到定位问题

**Scope**: 仅分析OS级别资源，不包含应用层数据

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行

### 工具依赖

- `mpstat`, `vmstat`, `iostat` (sysstat包)
- `pidstat` (sysstat包)
- `sar` (sysstat包)
- `perf` (linux-tools-common)
- `numactl`, `lscpu`

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
Phase 1: 系统信息收集
    ├→ sys-sniffer后台收集
    └→ CPU/Memory/Disk/Network/内核信息

Phase 2: 瓶颈分析
    ├→ Step 2.1: 全局资源分析
    │   ├→ CPU瓶颈指标
    │   ├→ 内存瓶颈指标
    │   ├→ IO瓶颈指标
    │   └→ 网络瓶颈指标
    │
    ├→ Step 2.2: 进程级分析
    │   ├→ 高CPU进程
    │   ├→ 高内存进程
    │   └→ 高IO进程
    │
    └→ Step 2.3: 微架构分析 (可选)
        └→ CPI, IPC, 缓存命中率
```

### 输出示例

```markdown
## 系统瓶颈分析报告

### 系统概览
- Hostname: server01
- Kernel: 5.4.0-generic
- CPU: 16 cores (2 sockets)
- Memory: 64GB
- Uptime: 15 days

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
| 系统信息 | /tmp/system_info.txt | 原始系统数据 |
| CPU分析 | Skill输出 | CPU瓶颈报告 |
| 内存分析 | Skill输出 | 内存瓶颈报告 |
| IO分析 | Skill输出 | IO瓶颈报告 |
| 网络分析 | Skill输出 | 网络瓶颈报告 |
| 进程分析 | Skill输出 | 高压力进程列表 |

## 参考文档

- Phase 2.1 CPU瓶颈指标: mpstat, pidstat, vmstat
- Phase 2.1 内存瓶颈指标: free, vmstat, pidstat
- Phase 2.1 IO瓶颈指标: iostat, pidstat
- Phase 2.1 网络瓶颈指标: sar, ss, netstat
- Phase 2.2 进程级分析: pidstat, top
- Phase 2.3 微架构: perf stat
