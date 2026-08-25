#!/usr/bin/env python3
"""
线程网卡队列处理分布采集 (eBPF)
利用 tc_ingress 挂载，统计各线程 (TID) 在网卡各队列上处理的包数和字节数。

依赖:
    pip3 install bcc

用法:
    python3 collect_net_ebpf_queue.py [-d DURATION] [-i IFACE] [-o OUTPUT_FILE]
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
#include <linux/skbuff.h>
#include <linux/netdevice.h>

struct queue_key_t {
    u32 tid;
    u32 ifindex;
    u16 queue_id;
};

struct queue_val_t {
    u64 packets;
    u64 bytes;
    u64 last_ts;
};

BPF_HASH(queue_map, struct queue_key_t, struct queue_val_t);

// 挂载点: net:netif_receive_skb — 网卡驱动将包交给协议栈
TRACEPOINT_PROBE(net, netif_receive_skb) {
    struct queue_key_t key = {};
    u32 tid = bpf_get_current_pid_tgid() & 0xFFFFFFFF;
    key.tid = tid;

    if (args->skbaddr) {
        struct sk_buff *skb = (struct sk_buff *)args->skbaddr;
        bpf_probe_read_kernel(&key.ifindex, sizeof(key.ifindex), &skb->dev->ifindex);
        bpf_probe_read_kernel(&key.queue_id, sizeof(key.queue_id), &skb->queue_mapping);
    }

    struct queue_val_t *val = queue_map.lookup(&key);
    if (val) {
        val->packets += 1;
        if (args->len)
            val->bytes += args->len;
        val->last_ts = bpf_ktime_get_ns();
    } else {
        struct queue_val_t new_val = {};
        new_val.packets = 1;
        if (args->len)
            new_val.bytes = args->len;
        new_val.last_ts = bpf_ktime_get_ns();
        queue_map.insert(&key, &new_val);
    }

    return 0;
}
"""

def get_iface_name(ifindex):
    try:
        with open(f"/sys/class/net/{ifindex}/ifindex", "r") as f:
            pass
    except:
        pass
    for name in os.listdir("/sys/class/net"):
        try:
            with open(f"/sys/class/net/{name}/ifindex", "r") as f:
                if int(f.read().strip()) == ifindex:
                    return name
        except:
            continue
    return str(ifindex)

def get_thread_name(tid):
    try:
        with open(f"/proc/{tid}/comm", "r") as f:
            return f.read().strip()
    except:
        pass
    try:
        with open(f"/proc/{tid}/task/{tid}/comm", "r") as f:
            return f.read().strip()
    except:
        return "?"

def main():
    parser = argparse.ArgumentParser(description="eBPF 线程网卡队列处理分布采集")
    parser.add_argument("batch_dir", nargs="?", default=None, help="批次根目录，默认 /srv/opentunex/<timestamp>/collect")
    parser.add_argument("-d", "--duration", type=int, default=30, help="采集时长(秒, 默认30)")
    parser.add_argument("-i", "--iface", type=str, default="", help="过滤指定网卡(如 eth0)")
    parser.add_argument("-o", "--output", type=str, default=None, help="输出文件(覆盖默认路径)")
    args = parser.parse_args()

    if args.batch_dir is None:
        args.batch_dir = f"/srv/opentunex/{time.strftime('%Y%m%d_%H%M%S')}/collect"
    if args.output is None:
        output_dir = args.batch_dir
        os.makedirs(output_dir, exist_ok=True)
        args.output = os.path.join(output_dir, "ebpf_queue_distribution.txt")

    print("=== eBPF 线程网卡队列处理分布采集 ===")
    print(f"采集时长: {args.duration}s")
    print(f"输出文件: {args.output}")
    print("挂载点: tracepoint/net/netif_receive_skb")
    print("")

    try:
        b = BPF(text=BPF_PROGRAM)
    except Exception as e:
        print(f"eBPF 程序加载失败: {e}", file=sys.stderr)
        print("请确保内核支持 eBPF tracepoint 且 BCC 已正确安装", file=sys.stderr)
        sys.exit(1)

    print(f"采集 {args.duration} 秒...")
    time.sleep(args.duration)

    queue_data = defaultdict(lambda: {"packets": 0, "bytes": 0})

    for key, val in b["queue_map"].items():
        ifname = get_iface_name(key.ifindex)
        if args.iface and ifname != args.iface:
            continue

        entry_key = (ifname, key.queue_id, key.tid)
        queue_data[entry_key]["packets"] += val.packets
        queue_data[entry_key]["bytes"] += val.bytes

    sorted_data = sorted(queue_data.items(), key=lambda x: x[1]["packets"], reverse=True)

    with open(args.output, "w") as f:
        f.write("=== 线程网卡队列处理分布报告 ===\n")
        f.write(f"采集时间: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"采集时长: {args.duration}s\n\n")
        f.write(f"{'网卡':<10} {'队列ID':>6} {'TID':>8} {'线程名':<20} {'包数':>12} {'字节数':>14}\n")
        f.write("-" * 75 + "\n")

        for (iface, qid, tid), vals in sorted_data:
            tname = get_thread_name(tid)
            f.write(f"{iface:<10} {qid:>6} {tid:>8} {tname:<20} {vals['packets']:>12} {vals['bytes']:>14}\n")

    print("")
    print("=== 线程网卡队列处理分布 Top 30 ===")
    print(f"{'网卡':<10} {'队列ID':>6} {'TID':>8} {'线程名':<20} {'包数':>12} {'字节数':>14}")
    print("-" * 75)

    for (iface, qid, tid), vals in sorted_data[:30]:
        tname = get_thread_name(tid)
        print(f"{iface:<10} {qid:>6} {tid:>8} {tname:<20} {vals['packets']:>12} {vals['bytes']:>14}")

    # 按队列汇总
    queue_summary = defaultdict(lambda: {"packets": 0, "bytes": 0, "threads": set()})
    for (iface, qid, tid), vals in sorted_data:
        key = (iface, qid)
        queue_summary[key]["packets"] += vals["packets"]
        queue_summary[key]["bytes"] += vals["bytes"]
        queue_summary[key]["threads"].add(tid)

    print("")
    print("=== 各队列负载分布汇总 ===")
    print(f"{'网卡':<10} {'队列ID':>6} {'线程数':>6} {'包数':>12} {'字节数':>14} {'占比':>8}")
    print("-" * 60)

    total_packets = sum(v["packets"] for v in queue_summary.values())
    sorted_queue = sorted(queue_summary.items(), key=lambda x: x[1]["packets"], reverse=True)

    with open(args.output, "a") as f:
        f.write("\n=== 各队列负载分布汇总 ===\n")
        f.write(f"{'网卡':<10} {'队列ID':>6} {'线程数':>6} {'包数':>12} {'字节数':>14} {'占比':>8}\n")
        f.write("-" * 60 + "\n")

        for (iface, qid), vals in sorted_queue:
            pct = (vals["packets"] / total_packets * 100) if total_packets > 0 else 0
            line = f"{iface:<10} {qid:>6} {len(vals['threads']):>6} {vals['packets']:>12} {vals['bytes']:>14} {pct:>7.1f}%"
            print(line)
            f.write(line + "\n")

    print(f"\n共 {len(sorted_data)} 条线程-队列记录, {len(queue_summary)} 个队列")
    print(f"报告已保存至: {args.output}")

    b.cleanup()

if __name__ == "__main__":
    main()
