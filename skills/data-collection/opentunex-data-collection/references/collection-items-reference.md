---
name: collection-items-reference
description: bottleneck_data_collector.sh 各数据文件与采集数据项速查表
---

# 瓶颈采集数据文件与采集项速查表

> **采集脚本**: 唯一采集脚本 `scripts/bottleneck_data_collector.sh`
>
> **输出目录**: `-o` 指定目录（默认 `bottleneck_data_<arch>_<时间戳>/`）
>
> **输出模式**: 每个采集项输出 **一份数据文件**，脚本直接落盘，不经过 skill 读取或格式转换。

## static_info.txt — 系统静态信息

脚本函数: `collect_static_info`（Phase 1）

| 采集项 | 采集方式 |
|--------|---------|
| CPU 型号/插槽/核数/缓存 | `lscpu`、`dmidecode -t processor` |
| NUMA 拓扑 | `numactl --hardware` |
| 内存 DIMM 信息 | `dmidecode -t memory` |
| 物理内存/大页概览 | `/proc/meminfo` 关键字段 |
| 磁盘设备与拓扑 | `lsblk`、`/proc/scsi/scsi` |
| 网卡型号/驱动/固件 | `lspci`、`ethtool -i` |
| 硬件型号、CPU 频率调节 | `dmidecode -t system`、cpufreq sysfs |
| OS/内核/GCC/glibc 版本 | `/etc/os-release`、`uname`、`gcc`、`ldd` |
| 内核启动参数 | `/proc/cmdline` |
| 性能相关 sysctl | `vm.*`、`net.*`、`kernel.sched*`、`fs.*` |
| 性能相关内核模块 | `lsmod` |
| 内核编译选项 | `/boot/config-*`（NO_HZ/HZ_1000/PREEMPT） |
| 透明大页、IO 调度器、IRQ 亲和 | THP sysfs、`/sys/block/*/queue/scheduler`、`/proc/irq/default_smp_affinity` |

## global_bottleneck.txt — 全局资源瓶颈指标

脚本函数: `collect_global_bottleneck`（Phase 2）

| 采集项 | 采集方式 |
|--------|---------|
| 每核 CPU 利用率（跳过空闲核） | `mpstat -P ALL` |
| 负载 vs CPU 数、上下文切换/中断 | `/proc/loadavg`、`vmstat` |
| Top 30 上下文切换任务 | `pidstat -w` |
| Swap 使用与压力、关键 Swap 指标 | `free -h`、`/proc/meminfo` |
| Top 20 缺页任务 | `pidstat -r` |
| Slab 内存使用 | `/proc/meminfo` |
| 磁盘利用率（跳过 0% util） | `iostat -xz` |
| 队列深度 (inflight_IO) | `/proc/diskstats` |
| 磁盘空间、Top 20 IO 进程 | `df -h`、`pidstat -d` |
| 网络接口统计/错误统计 | `sar -n DEV/EDEV` |
| TCP 重传与丢包（5s delta） | `nstat` |
| 连接积压、Top 10 端口 | `ss` |

## top_processes.txt — 顶级资源消耗进程

脚本函数: `collect_top_processes`（Phase 1）

| 采集项 | 采集方式 |
|--------|---------|
| Top 20 CPU 进程 | `ps aux --sort=-%cpu` |
| Top 20 内存进程 | `ps aux --sort=-%mem` |
| Top 20 IO 进程 | `iotop`、`pidstat -d` |

## cpu_detail_info.txt — CPU 深度信息

脚本函数: `collect_cpu_detail_info`（Phase 2）

| 采集项 | 采集方式 |
|--------|---------|
| 在线 CPU 列表及数量 | `/sys/devices/system/cpu/online` |
| 完整 CPU 信息 | `/proc/cpuinfo` |
| NUMA 节点 sysfs 详情 | `/sys/devices/system/node/node*` |
| SMT 超线程状态 | `/sys/devices/system/cpu/smt/active`、`thread_siblings_list` |
| CPU 频率与调频策略 | cpufreq sysfs |
| 硬件 CPPC 支持 | `/proc/cpuinfo` |
| 中断分布 | `/proc/interrupts` |
| /proc/stat 解析 + 多采样 | `/proc/stat`（间隔 INTERVAL 秒，持续 DURATION 秒） |

## kernel_config_info.txt — 内核配置与诊断

脚本函数: `collect_kernel_config_info`（Phase 1）

| 采集项 | 采集方式 |
|--------|---------|
| 全量内核参数 | `sysctl -a` |
| 关键网络参数、命名空间限制 | `sysctl` 过滤 |
| 启动参数特殊项（xcall 等） | `/proc/cmdline` |
| 调度特性 | `/sys/kernel/debug/sched_features` |
| 特殊调度参数 | `sched_cluster`、`sched_util_ratio`、`sched_soft_runtime_ratio`、`sched_max_steal_count` |
| 完整内核模块列表 | `lsmod` |
| 内核版本与编译选项 | `uname -a`、`/boot/config-*` 或 `/proc/config.gz` |
| 内核 taint、Oops/Panic | `/proc/sys/kernel/tainted`、`dmesg` |
| 活跃内核线程、THP defrag | `ps`、THP sysfs |
| irqbalance / oenetcls / SMC / ism 模块 | `systemctl`、`lsmod`、`modinfo` |
| ARM SPE 支持、debugfs 挂载 | `perf list`、`mount` |
| 文件系统、SECCOMP、fd Top5、关键服务 PID | `/proc/filesystems`、`/proc/*/status`、`pgrep` |

## process_detail_info.txt — 进程/线程详细信息

脚本函数: `collect_process_detail_info`（Phase 3）

| 采集项 | 采集方式 |
|--------|---------|
| 系统进程/线程总数、状态分布 | `ps` |
| pidstat CPU/内存/IO 采样 | `pidstat -u/-r/-d` |
| 线程级 CPU 统计 | `pidstat -t -u` |
| 线程最多的进程 Top 10 | `ps --sort=-nlwp` |
| Top CPU 进程线程详情 | `/proc/<pid>/task` |
| /proc/schedstat、PID/线程上限 | `/proc/schedstat`、`pid_max`、`threads-max` |
| 关键进程检查（redis-server） | `pgrep` |
| 线程生命周期轮询（创建/销毁事件） | `/proc/<pid>/task` 快照对比，持续 DURATION 秒 |

## container_info.txt — 容器资源监控

脚本函数: `collect_container_info`（Phase 3）

| 采集项 | 采集方式 |
|--------|---------|
| cgroup 版本检测 | `/sys/fs/cgroup` |
| 容器发现（docker/containerd/libpod/kubepods） | cgroup 目录扫描 |
| CPU 限额与可用 CPU 数 | `cpu.max` / `cpu.cfs_*` |
| CPU 累计使用 | `cpu.stat` / `cpuacct.usage` |
| NUMA/CPU 亲和性 | `cpuset.*` |
| 内存配置与使用 | `memory.max` / `memory.limit_in_bytes` |
| blkio 限速 | `io.max` / `blkio.throttle.*` |
| 任务列表（TID 映射） | cgroup tasks/threads |
| Docker 元数据 | `docker inspect` |
| 容器 CPU 多采样观测 | cgroup 配额/usage 采样，持续 DURATION 秒 |

## memory_metrics_analysis.txt — 内存指标深度分析

脚本函数: `collect_mem_metrics`（Phase 1）

| 采集项 | 采集方式 |
|--------|---------|
| 内存压力 PSI | `/proc/pressure/mem` |
| 内存使用概览 | `free -h` |
| OOM 统计、Swap 配置 | `/proc/vmstat`、`swapon -s` |
| Slab/Vmalloc 信息 | `/proc/slabinfo`、`/proc/meminfo` |
| 分配/回收统计 | `/proc/vmstat`（pgfault/pgalloc/pgscan 等） |
| 大页配置（静态+透明） | `/proc/meminfo`、THP sysfs、hugepages sysfs |
| OOM 配置、KSM、NUMA balancing | sysctl、KSM sysfs |
| 内存 cgroup 限额 | `/sys/fs/cgroup/memory.*` |
| 内存水位线、Zone 信息 | `/proc/sys/vm/watermark*`、`/proc/zoneinfo` |
| jemalloc 检测、MALLOC 环境变量 | `/proc/<pid>/maps`、env |
| NUMA 统计（系统级+进程级） | `/proc/vmstat`、`numastat -p` |
| NUMA 布局、Buddy Info | `numactl --hardware`、`lscpu`、`/proc/buddyinfo` |
| 近期 OOM 事件 | `dmesg` / `journalctl -k` |
| 完整 meminfo/vmstat、页大小、每节点内存 | `/proc/meminfo`、`/proc/vmstat`、`getconf`、node sysfs |

## network_metrics_analysis.txt — 网络指标深度分析

脚本函数: `collect_net_metrics`（Phase 2）

| 采集项 | 采集方式 |
|--------|---------|
| 网络接口列表 | `ip -br link show` |
| 网络 sysctl 配置 | `/proc/sys/net/ipv4/*`、`/proc/sys/net/core/*` |
| 网卡链路/驱动/队列/Ring/Coalesce/Pause/Offload | `ethtool` |
| 网卡 IRQ 亲和性 | `/proc/interrupts`、`/proc/irq/*/smp_affinity` |
| 网络设备统计/错误统计 | `sar -n DEV/EDEV`（持续 DURATION 秒） |
| 网关/回环延迟 | `ping` |
| TCP 统计、Socket 概览 | `netstat -s`、`ss -s` |
| Socket 内存、连接状态分布 | `/proc/net/sockstat`、`ss -tan` |
| 网络队列统计 | `/proc/net/netstat`（TcpExt/IpExt） |
| 接口详细状态、IP/路由/ARP | `/sys/class/net/*`、`ip addr/route`、`arp` |
| 监听端口 | `ss -tlnp` |
| 队列/RPS 配置、ntuple 支持 | `/sys/class/net/*/queues`、`ethtool -k` |
| 排队规则、设备统计、进程名列表 | `tc qdisc show`、`/proc/net/dev`、`ps` |

## io_metrics_analysis.txt — I/O 指标深度分析

脚本函数: `collect_io_metrics`（Phase 2）

| 采集项 | 采集方式 |
|--------|---------|
| 系统概览（内核/CPU/内存） | `uname`、`nproc`、`free` |
| 磁盘设备列表、IO 调度器与队列参数 | `lsblk`、`/sys/block/*/queue/*` |
| 内存/页缓存设置 | `/proc/sys/vm/*`（dirty 系列等） |
| 进程 IO 优先级/统计/文件限制 | `ionice`、`/proc/<pid>/io`、`/proc/<pid>/limits` |
| 系统级 IO 限制（AIO/文件句柄） | `/proc/sys/fs/aio-*`、`file-max`、`file-nr` |
| 实时性能数据 | `vmstat`、`iostat -x`（持续 DURATION 秒） |
| 文件系统/NFS/CIFS 挂载选项 | `mount` |

## hotspot_analysis.txt — 热点函数分析（需 -p）

脚本函数: `collect_hotspot_analysis`（Phase 4）

| 采集项 | 采集方式 |
|--------|---------|
| 进程热点采样（30 秒） | `perf record -p <PID> -g` |
| 热点函数报告 | `perf report --stdio --percent-limit 1` |

## syscall_analysis.txt — 系统调用分析（需 -p）

脚本函数: `collect_syscall_analysis`（Phase 4）

| 采集项 | 采集方式 |
|--------|---------|
| 系统调用汇总统计 | `strace -p <PID> -c -f`（持续 DURATION 秒） |

## pmu_info.txt — PMU 远程访问与 HHA 分析（仅 aarch64）

脚本函数: `collect_pmu_info`（Phase 4）

| 采集项 | 采集方式 |
|--------|---------|
| HHA 设备检测 | `/sys/devices/hha*` |
| PMU 事件列表（rx_ops/rx_outer/rx_sccl/uncore） | `perf list` |
| 远程访问统计 | `perf stat -e rx_ops -e rx_outer -e rx_sccl`（持续 DURATION 秒） |
| 速率与远程访问占比计算 | 基于 perf stat 结果 |
| perf list 输出预览 | `perf list` |
