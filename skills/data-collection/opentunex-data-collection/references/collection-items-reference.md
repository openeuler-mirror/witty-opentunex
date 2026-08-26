---
name: collection-items-reference
description: 各维度采集项与数据存储位置速查表，每个采集项输出一份聚合报告文件
---

# 各维度采集项与数据存储位置速查表

> **日志**: 每次脚本执行的完整输出同步写入 `${WORK_DIR}/collect/collect_log/<item>_YYYYMMDD_HHMMSS.log`，便于追踪和回溯。
>
> **归档**: 所有采集项统一写入批次目录 `${WORK_DIR}/collect/`。
>
> **输出模式**: 每个采集项输出 **一份聚合报告文件** `<item>-collection_report.txt`，包含该维度全部采集数据。脚本直接落盘，不经过 skill 读取或格式转换。

## cpu → 报告 `cpu-collection_report.txt`

脚本: `scripts/collect_cpu_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| CPU 型号与架构 | `lscpu` / `/proc/cpuinfo` |
| 在线 CPU 核心列表及数量 | `/sys/devices/system/cpu/online`、`nproc` |
| NUMA 拓扑 (节点距离、CPU-NUMA 映射) | `/sys/devices/system/node/node*/`、`numactl --hardware` |
| NUMA 节点数量 | `ls /sys/devices/system/node/node* | wc -l` |
| 每个 CPU 所属 NUMA 节点 | `/sys/devices/system/cpu/cpu*/topology/physical_package_id` |
| 各核心利用率 (%user, %sys, %iowait, %idle 等) | `mpstat -P ALL 1 5` |
| /proc/stat 差值计算 (两次快照) | `/proc/stat` 间隔 1s |
| 中断与软中断分布 | `/proc/interrupts`、`/proc/softirqs` |
| CPU 频率与调频策略 | `/sys/devices/system/cpu/cpu*/cpufreq/` |
| SMT 是否开启及拓扑 | `/sys/devices/system/cpu/smt/active`、`thread_siblings_list` |

## mem → 报告 `mem-collection_report.txt`

脚本: `scripts/collect_mem_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 完整物理内存信息 | `/proc/meminfo` |
| 虚拟内存累计统计 | `/proc/vmstat` |
| 内存使用概览 | `free -h` |
| 虚拟内存、交换区、块 I/O 动态统计 | `vmstat -w -t 1 5` |
| 系统内存页大小 | `getconf PAGE_SIZE` |
| 大页 (HugePages) 配置 | `/proc/meminfo`、`/sys/kernel/mm/hugepages/` |
| 交换区详情 | `/proc/swaps`、`swapon --show` |
| NUMA 节点内存分布 | `/sys/devices/system/node/node*/meminfo`、`numactl --hardware` |
| 进程内存占用 Top 15 | `ps -eo pid,comm,rss,vsz --sort=-rss` |
| PSI 内存压力 | `/proc/pressure/memory` |

## io → 报告 `io-collection_report.txt`

脚本: `scripts/collect_io_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 块设备列表与类型 | `lsblk` |
| 磁盘调度器与队列参数 | `/sys/block/<dev>/queue/` |
| /proc/diskstats 原始数据 | `/proc/diskstats` |
| 磁盘挂载与使用率 | `df -h` |
| vmstat 初始采样 | `vmstat 1 1` |
| iostat 扩展统计 (单次+持续) | `iostat -x 1 1` + `iostat -x 1 N` |
| pidstat 进程 I/O | `pidstat -d 1 N` |

## net → 报告 `net-collection_report.txt`

脚本: `scripts/collect_net_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 网络接口名称、状态 (UP/DOWN)、索引 | `/sys/class/net/<iface>/` |
| 网络接口简表 | `ip -o link show` + `ip link show \| paste -sd '#'` |
| 网卡驱动详情 (版本、固件等) | `ethtool -i <iface>` |
| 网卡队列信息 (RX/TX 队列数、RPS) | `/sys/class/net/<iface>/queues/` |
| 网络接口 IP 配置 | `ip addr show` |
| 路由表 | `ip route show` |
| ARP 表 | `arp -n` / `/proc/net/arp` |
| 网络统计 (retrans, 丢包等) | `netstat -s` |
| TCP/UDP 连接状态 | `ss -s`, `ss -tan` |
| 网卡中断亲和性 | `/proc/irq/*/smp_affinity` |
| /proc/net/dev 原始统计 | `/proc/net/dev` |
| 网络设备统计 (sar) | `sar -n DEV` |
| 网络设备错误 (sar) | `sar -n EDEV` |
| eBPF 进程间流量亲和性 | `python3 scripts/collect_net_ebpf_traffic.py [BATCH_DIR] -d 30` |
| eBPF 线程队列分布 | `python3 scripts/collect_net_ebpf_queue.py [BATCH_DIR] -d 30` |

## process → 报告 `process-collection_report.txt`

脚本: `scripts/collect_process_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 系统负载 | `/proc/loadavg` |
| 进程状态分布 (R/S/D/Z/T/I) | `ps -eo stat` |
| 进程 CPU 统计 | `pidstat -u 1 5` |
| 进程内存统计 | `pidstat -r 1 1` |
| 进程 I/O 统计 | `pidstat -d 1 1` |
| 线程级 CPU 统计 | `pidstat -t -u 1 3` |
| 上下文切换统计 | `pidstat -w 1 1` |
| Top CPU 进程排行 | `ps -eo pid,comm,%cpu,%mem,rss,vsz --sort=-%cpu` |
| 线程最多的进程 Top 10 | `ps -eo pid,comm,nlwp --sort=-nlwp` |
| 指定进程线程详情 | `/proc/<pid>/task/` |
| eBPF 线程创建/销毁事件 | `python3 scripts/collect_process_ebpf_thread.py [BATCH_DIR] -d 30` |

## process-thread-poll → 报告 `process-thread-poll_report.txt` (可选)

脚本: `scripts/collect_process_thread_poll.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 线程创建/销毁轮询 (eBPF 降级方案) | 轮询 `/proc/<pid>/task/` 快照对比 |

## system → 报告 `system-collection_report.txt`

脚本: `scripts/collect_system_sar.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 内核版本、启动时间、虚拟化检测 | `uname -r`, `uptime`, `systemd-detect-virt` |
| CPU 使用率 (sar) | `sar -u` |
| 每核心 CPU (sar) | `sar -P ALL` |
| 内存使用 (sar) | `sar -r` |
| 交换区 (sar) | `sar -S` |
| 分页统计 (sar) | `sar -B` |
| I/O 速率 (sar) | `sar -b` |
| Socket 统计 (sar) | `sar -n SOCK` |
| 系统负载与队列 (sar) | `sar -q` |
| 上下文切换 (sar) | `sar -w` |
| 大页使用 (sar) | `sar -H` |
| 中断统计 (sar) | `sar -I SUM` |
| TTY 设备活动 (sar) | `sar -y` |
| sysstat 历史数据 | `sadf -d /var/log/sa/saDD` |
| PSI CPU/IO 压力指标 | `/proc/pressure/cpu`、`/proc/pressure/io` |

> 注: 网络设备统计 (`sar -n DEV`/`sar -n EDEV`) 已归入 net 采集项，不在 system 中重复采集。

## kernel → 报告 `kernel-collection_report.txt`

脚本: `scripts/collect_kernel_config.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 全量内核运行时参数 | `sysctl -a` (同时缓存至 `sysctl_cache.txt`) |
| 关键内核参数分组提取 (网络/内存/调度/FS/用户) | 从缓存 grep 分组 |
| 内核启动参数与特征 | `/proc/cmdline` |
| 内核模块列表 | `lsmod` |
| 内核版本与构建配置 | `uname -a`, `/proc/version`, `/boot/config-*` |
| taint、dmesg 错误 | 多源 |
| 内核线程、挂载点、THP、KSM、filesystems | 多源 |

## container → 报告 `container-collection_report.txt`

脚本: `scripts/collect_container_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| 运行中容器列表 | 遍历 cgroup + `docker ps -q` 辅助 |
| 容器 CPU 限额与累计使用 | cpu/cpuacct cgroup |
| 容器 CPU/内存亲和性 | cpuset cgroup |
| 容器内存限额与使用 | memory cgroup |
| 容器 blkio 限速与累计 | blkio cgroup |
| 容器任务列表 (TID→PID 映射) | cpu cgroup tasks |
| 容器元数据 (名称、镜像、标签) | `docker inspect` |
| Docker Daemon 信息 | `docker info` |

## pmu → 报告 `pmu-collection_report.txt`

脚本: `scripts/collect_pmu_info.sh`

| 采集项 | 采集方式 |
|--------|---------|
| HHA 设备检测 | `ls -d /sys/devices/hha*` |
| NUMA 远程访问 PMU 事件列表 | `perf list | grep -iE 'hha|rx_ops|rx_outer|rx_sccl|uncore'` |
| 内存访问压力统计 | `perf stat -e <events> -a sleep 10` |
| 每秒操作速率与远程访问占比 | awk 换算 |
