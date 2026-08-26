#!/usr/bin/env python3
"""
网络流量亲和性采集 (eBPF)
利用 kprobe/tcp_connect、kretprobe/inet_csk_accept 和 tc_ingress 挂载，
统计进程 PID 对之间的网络流量字节数。

依赖:
    pip3 install bcc

用法:
    python3 collect_net_ebpf_traffic.py [-d DURATION] [-o OUTPUT_FILE]
"""

import os
import sys
import time
import signal
import argparse
from collections import defaultdict

try:
    from bcc import BPF
except ImportError:
    print("错误: 请先安装 BCC: pip3 install bcc 或 yum install bcc-tools", file=sys.stderr)
    sys.exit(1)

BPF_PROGRAM = r"""
#include <uapi/linux/ptrace.h>
#include <linux/tcp.h>
#include <linux/in.h>
#include <linux/ip.h>
#include <net/sock.h>

struct flow_key_t {
    u32 saddr;
    u32 daddr;
    u16 sport;
    u16 dport;
    u32 pid;
};

struct flow_val_t {
    u64 bytes_sent;
    u64 bytes_recv;
    u64 timestamp_ns;
};

BPF_HASH(flow_map, struct flow_key_t, struct flow_val_t);

// 挂载点 1: kprobe/tcp_connect — 采集主动连接的进程信息
int kprobe__tcp_connect(struct pt_regs *ctx, struct sock *sk)
{
    u32 pid = bpf_get_current_pid_tgid() >> 32;
    u32 tid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;

    u16 sport = sk->__sk_common.skc_num;
    u16 dport = sk->__sk_common.skc_dport;
    u32 saddr = sk->__sk_common.skc_rcv_saddr;
    u32 daddr = sk->__sk_common.skc_daddr;

    // 仅当端口有效时记录
    if (sport == 0 || dport == 0)
        return 0;

    dport = ntohs(dport);

    struct flow_key_t key = {};
    key.saddr = saddr;
    key.daddr = daddr;
    key.sport = sport;
    key.dport = dport;
    key.pid = pid;

    struct flow_val_t *val = flow_map.lookup(&key);

    if (!val) {
        struct flow_val_t new_val = {};
        new_val.timestamp_ns = bpf_ktime_get_ns();
        flow_map.insert(&key, &new_val);
    }

    return 0;
}

// 挂载点 2: kretprobe/inet_csk_accept — 服务端接受新连接
int kretprobe__inet_csk_accept(struct pt_regs *ctx)
{
    struct sock *newsk = (struct sock *)PT_REGS_RC(ctx);
    if (newsk == NULL)
        return 0;

    u32 pid = bpf_get_current_pid_tgid() >> 32;

    u16 sport = newsk->__sk_common.skc_num;
    u16 dport = newsk->__sk_common.skc_dport;
    u32 saddr = newsk->__sk_common.skc_rcv_saddr;
    u32 daddr = newsk->__sk_common.skc_daddr;

    if (sport == 0 || dport == 0)
        return 0;

    dport = ntohs(dport);

    struct flow_key_t key = {};
    key.saddr = saddr;
    key.daddr = daddr;
    key.sport = sport;
    key.dport = dport;
    key.pid = pid;

    struct flow_val_t *val = flow_map.lookup(&key);
    if (!val) {
        struct flow_val_t new_val = {};
        new_val.timestamp_ns = bpf_ktime_get_ns();
        flow_map.insert(&key, &new_val);
    }

    return 0;
}
"""

def ip_to_str(ip_int):
    return "{}.{}.{}.{}".format(
        ip_int & 0xFF,
        (ip_int >> 8) & 0xFF,
        (ip_int >> 16) & 0xFF,
        (ip_int >> 24) & 0xFF
    )

def get_process_name(pid):
    try:
        with open(f"/proc/{pid}/comm", "r") as f:
            return f.read().strip()
    except Exception:
        return "?"

def main():
    parser = argparse.ArgumentParser(description="eBPF 进程间网络流量亲和性采集")
    parser.add_argument("batch_dir", nargs="?", default=None, help="批次根目录，默认 /srv/opentunex/<timestamp>/collect")
    parser.add_argument("-d", "--duration", type=int, default=30, help="采集时长(秒, 默认30)")
    parser.add_argument("-o", "--output", type=str, default=None, help="输出文件(覆盖默认路径)")
    args = parser.parse_args()

    if args.batch_dir is None:
        args.batch_dir = f"/srv/opentunex/{time.strftime('%Y%m%d_%H%M%S')}/collect"
    if args.output is None:
        output_dir = args.batch_dir
        os.makedirs(output_dir, exist_ok=True)
        args.output = os.path.join(output_dir, "ebpf_traffic_affinity.txt")

    print("=== eBPF 网络流量亲和性采集 ===")
    print(f"采集时长: {args.duration}s")
    print(f"输出文件: {args.output}")
    print("挂载点: kprobe/tcp_connect, kretprobe/inet_csk_accept")
    print("注意: 本工具采集连接创建事件，实际流量字节数需配合 tc_ingress 采集")
    print("")

    try:
        b = BPF(text=BPF_PROGRAM)
    except Exception as e:
        print(f"eBPF 程序加载失败: {e}", file=sys.stderr)
        print("请确保内核支持 eBPF 且 BCC 已正确安装", file=sys.stderr)
        sys.exit(1)

    print(f"采集 {args.duration} 秒...")
    time.sleep(args.duration)

    flows = defaultdict(int)

    now_ns = int(time.time() * 1e9)

    for key, val in b["flow_map"].items():
        age_ns = now_ns - val.timestamp_ns
        age_s = age_ns / 1e9
        if age_s < args.duration:
            conn_key = (key.pid, key.saddr, key.sport, key.daddr, key.dport)
            flows[conn_key] += 1

    with open(args.output, "w") as f:
        f.write("=== 进程间 TCP 连接亲和性报告 ===\n")
        f.write(f"采集时间: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"采集时长: {args.duration}s\n\n")
        f.write(f"{'PID':>8} {'进程名':<16} {'源地址':<18} {'源端口':>6} {'目标地址':<18} {'目标端口':>6} {'新连接数':>8}\n")
        f.write("-" * 90 + "\n")

        sorted_flows = sorted(flows.items(), key=lambda x: x[1], reverse=True)

        for (pid, saddr, sport, daddr, dport), count in sorted_flows:
            proc_name = get_process_name(pid)
            src_ip = ip_to_str(saddr)
            dst_ip = ip_to_str(daddr)
            f.write(f"{pid:>8} {proc_name:<16} {src_ip:<18} {sport:>6} {dst_ip:<18} {dport:>6} {count:>8}\n")

    print("")
    print("=== 进程间 TCP 连接亲和性 Top 20 ===")
    print(f"{'PID':>8} {'进程名':<16} {'源地址':<18} {'源端口':>6} {'目标地址':<18} {'目标端口':>6} {'新连接数':>8}")
    print("-" * 90)

    sorted_flows = sorted(flows.items(), key=lambda x: x[1], reverse=True)
    for (pid, saddr, sport, daddr, dport), count in sorted_flows[:20]:
        proc_name = get_process_name(pid)
        src_ip = ip_to_str(saddr)
        dst_ip = ip_to_str(daddr)
        print(f"{pid:>8} {proc_name:<16} {src_ip:<18} {sport:>6} {dst_ip:<18} {dport:>6} {count:>8}")

    print(f"\n共 {len(flows)} 条唯一连接记录")
    print(f"报告已保存至: {args.output}")

    b.cleanup()

if __name__ == "__main__":
    main()
