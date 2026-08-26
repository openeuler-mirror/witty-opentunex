#!/usr/bin/env python3
"""
eBPF 线程创建与销毁事件采集
挂载 tracepoint/syscalls/sys_exit_clone 采集线程创建事件
挂载 tracepoint/syscalls/sys_enter_exit 采集线程销毁事件

依赖:
    pip3 install bcc

用法:
    python3 collect_process_ebpf_thread.py [-d DURATION] [-o OUTPUT_FILE]
"""

import os
import sys
import time
import argparse
from collections import defaultdict

try:
    from bcc import BPF
except ImportError:
    print("错误: 请先安装 BCC: pip3 install bcc 或 yum install bcc-tools", file=sys.stderr)
    sys.exit(1)

BPF_PROGRAM = r"""
#include <uapi/linux/ptrace.h>

// 线程创建事件结构
struct thread_create_t {
    u32 ppid;     // 父 PID
    u32 pid;      // 子 PID (或 TGID)
    u32 tid;      // 子 TID (线程ID)
    char comm[16];
    u64 ts_ns;
};

// 线程销毁事件结构
struct thread_exit_t {
    u32 pid;
    u32 tid;
    char comm[16];
    u64 ts_ns;
};

// 环形缓冲区输出
BPF_PERF_OUTPUT(thread_create_events);
BPF_PERF_OUTPUT(thread_exit_events);

// 挂载点 1: tracepoint/syscalls/sys_exit_clone
// 采集线程/进程创建事件
TRACEPOINT_PROBE(syscalls, sys_exit_clone) {
    struct thread_create_t event = {};

    u64 pid_tgid = bpf_get_current_pid_tgid();
    event.ppid = pid_tgid >> 32;
    event.tid = args->ret;  // clone 返回值 = 子 TID

    if (event.tid <= 0)
        return 0;

    // 读取子线程的 comm 和 TGID
    struct task_struct *task = (struct task_struct *)bpf_get_current_task();
    if (task) {
        // 对于线程创建(clone没有CLONE_THREAD时是进程), tgid 需要从 task 中取
        bpf_probe_read_kernel(&event.pid, sizeof(event.pid),
            &task->tgid);  // 实际上当前task的tgid就是ppid的tgid, 子task还没建立
    }

    event.ts_ns = bpf_ktime_get_ns();
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    thread_create_events.perf_submit(args, &event, sizeof(event));
    return 0;
}

// 挂载点 2: tracepoint/syscalls/sys_enter_exit
// 采集线程/进程销毁事件 (注意: 进程退出也走 exit syscall)
TRACEPOINT_PROBE(syscalls, sys_enter_exit) {
    struct thread_exit_t event = {};

    u64 pid_tgid = bpf_get_current_pid_tgid();
    event.pid = pid_tgid >> 32;
    event.tid = pid_tgid & 0xFFFFFFFF;

    event.ts_ns = bpf_ktime_get_ns();
    bpf_get_current_comm(&event.comm, sizeof(event.comm));

    thread_exit_events.perf_submit(args, &event, sizeof(event));
    return 0;
}
"""

def get_process_name(pid):
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            return f.read().strip()
    except Exception:
        return "?"

class EventCollector:
    def __init__(self):
        self.create_events = []
        self.exit_events = []
        self.create_count_by_pid = defaultdict(int)
        self.exit_count_by_pid = defaultdict(int)

    def handle_create(self, cpu, data, size):
        event = BPFProgram.b["thread_create_events"].event(data)
        comm = event.comm.decode('utf-8', errors='replace').rstrip('\x00')
        self.create_events.append({
            "ppid": event.ppid,
            "pid": event.pid,
            "tid": event.tid,
            "comm": comm,
            "ts_ns": event.ts_ns,
        })
        self.create_count_by_pid[event.ppid] += 1

    def handle_exit(self, cpu, data, size):
        event = BPFProgram.b["thread_exit_events"].event(data)
        comm = event.comm.decode('utf-8', errors='replace').rstrip('\x00')
        self.exit_events.append({
            "pid": event.pid,
            "tid": event.tid,
            "comm": comm,
            "ts_ns": event.ts_ns,
        })
        self.exit_count_by_pid[event.pid] += 1

def format_ts(ts_ns):
    return time.strftime('%Y-%m-%d %H:%M:%S.', time.localtime(ts_ns / 1e9)) + f"{(ts_ns % 1000000000) // 1000:06d}"

def main():
    parser = argparse.ArgumentParser(description="eBPF 线程创建与销毁事件采集")
    parser.add_argument("batch_dir", nargs="?", default=None, help="批次根目录，默认 /srv/opentunex/<timestamp>/collect")
    parser.add_argument("-d", "--duration", type=int, default=30, help="采集时长(秒, 默认30)")
    parser.add_argument("-o", "--output", type=str, default=None, help="输出文件(覆盖默认路径)")
    args = parser.parse_args()

    if args.batch_dir is None:
        args.batch_dir = f"/srv/opentunex/{time.strftime('%Y%m%d_%H%M%S')}/collect"
    if args.output is None:
        output_dir = args.batch_dir
        os.makedirs(output_dir, exist_ok=True)
        args.output = os.path.join(output_dir, "ebpf_thread_events.txt")

    print("=== eBPF 线程创建与销毁事件采集 ===")
    print(f"采集时长: {args.duration}s")
    print(f"输出文件: {args.output}")
    print("挂载点: tracepoint/syscalls/sys_exit_clone (创建)")
    print("        tracepoint/syscalls/sys_enter_exit (销毁)")
    print("")

    try:
        global BPFProgram
        BPFProgram = BPF(text=BPF_PROGRAM)
    except Exception as e:
        print(f"eBPF 程序加载失败: {e}", file=sys.stderr)
        print("请确保内核支持 eBPF tracepoint 且 BCC 已正确安装", file=sys.stderr)
        sys.exit(1)

    collector = EventCollector()

    BPFProgram["thread_create_events"].open_perf_buffer(collector.handle_create)
    BPFProgram["thread_exit_events"].open_perf_buffer(collector.handle_exit)

    print(f"采集 {args.duration} 秒...")
    start_time = time.time()
    while time.time() - start_time < args.duration:
        BPFProgram.perf_buffer_poll(timeout=100)

    with open(args.output, "w") as f:
        f.write("=== eBPF 线程创建与销毁事件报告 ===\n")
        f.write(f"采集时间: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"采集时长: {args.duration}s\n\n")

        f.write("--- 线程创建事件 (tracepoint/sys_exit_clone) ---\n")
        f.write(f"{'时间':<25} {'父PID':>8} {'子TID':>8} {'父comm':<16}\n")
        f.write("-" * 65 + "\n")
        for e in collector.create_events[:200]:
            f.write(f"{format_ts(e['ts_ns']):<25} {e['ppid']:>8} {e['tid']:>8} {e['comm']:<16}\n")

        f.write("\n--- 线程销毁事件 (tracepoint/sys_enter_exit) ---\n")
        f.write(f"{'时间':<25} {'PID':>8} {'TID':>8} {'comm':<16}\n")
        f.write("-" * 65 + "\n")
        for e in collector.exit_events[:200]:
            f.write(f"{format_ts(e['ts_ns']):<25} {e['pid']:>8} {e['tid']:>8} {e['comm']:<16}\n")

        f.write("\n--- 进程创建线程数排行 ---\n")
        f.write(f"{'父PID':>8} {'进程名':<16} {'创建线程数':>10}\n")
        f.write("-" * 40 + "\n")
        sorted_create = sorted(collector.create_count_by_pid.items(), key=lambda x: x[1], reverse=True)
        for pid, count in sorted_create[:20]:
            pname = get_process_name(pid)
            f.write(f"{pid:>8} {pname:<16} {count:>10}\n")

        f.write("\n--- 进程退出线程数排行 ---\n")
        f.write(f"{'PID':>8} {'进程名':<16} {'退出线程数':>10}\n")
        f.write("-" * 40 + "\n")
        sorted_exit = sorted(collector.exit_count_by_pid.items(), key=lambda x: x[1], reverse=True)
        for pid, count in sorted_exit[:20]:
            pname = get_process_name(pid)
            f.write(f"{pid:>8} {pname:<16} {count:>10}\n")

    print("")
    print("=== 线程创建/销毁事件统计 ===")
    print(f"线程创建事件: {len(collector.create_events)} 次")
    print(f"线程销毁事件: {len(collector.exit_events)} 次")
    print("")

    if collector.create_events:
        print(f"--- 最近 10 个创建事件 ---")
        print(f"{'时间':<25} {'父PID':>8} {'子TID':>8} {'父comm':<16}")
        print("-" * 65)
        for e in collector.create_events[-10:]:
            print(f"{format_ts(e['ts_ns']):<25} {e['ppid']:>8} {e['tid']:>8} {e['comm']:<16}")

    if collector.exit_events:
        print(f"\n--- 最近 10 个销毁事件 ---")
        print(f"{'时间':<25} {'PID':>8} {'TID':>8} {'comm':<16}")
        print("-" * 65)
        for e in collector.exit_events[-10:]:
            print(f"{format_ts(e['ts_ns']):<25} {e['pid']:>8} {e['tid']:>8} {e['comm']:<16}")

    if sorted_create:
        print(f"\n--- 进程创建线程数 Top 10 ---")
        print(f"{'父PID':>8} {'进程名':<16} {'创建线程数':>10}")
        print("-" * 40)
        for pid, count in sorted_create[:10]:
            pname = get_process_name(pid)
            print(f"{pid:>8} {pname:<16} {count:>10}")

    print(f"\n报告已保存至: {args.output}")

    BPFProgram.cleanup()

if __name__ == "__main__":
    main()
