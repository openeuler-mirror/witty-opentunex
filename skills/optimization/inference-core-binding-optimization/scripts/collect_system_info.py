#!/usr/bin/env python3
"""
单脚本并行采集瓶颈分析所需系统信息，在脚本内对命令输出做 parse，只保留有效结构化信息输出。
用法: python3 collect_system_info.py <tid> [tid ...] [--md]
输出: JSON 到 stdout（或 --md 输出紧凑 Markdown）
（pid 由 /proc/<tid>/status 的 Tgid 自动解析）
"""
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------


def run_cmd(cmd, timeout=10):
    """执行命令，返回 (stdout, stderr, ok)。"""
    if isinstance(cmd, str):
        cmd = cmd.split()
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (r.stdout or "").strip(), (r.stderr or "").strip(), r.returncode == 0
    except Exception as e:
        return "", str(e), False


def _target_key(pid: int, tid: int) -> str:
    return f"{pid}-{tid}"


def _pid_from_tid(tid: int):
    """从 /proc/<tid>/status 的 Tgid 得到 pid；不存在或无法读取则返回 None。"""
    p = Path(f"/proc/{tid}/status")
    if not p.exists():
        return None
    try:
        for line in p.read_text().splitlines():
            if line.startswith("Tgid:"):
                return int(line.split(":", 1)[-1].strip())
        return None
    except Exception:
        return None


def _is_num(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def _read_proc_field(path: Path, field: str) -> Optional[str]:
    """从 /proc 文件读取指定字段值（格式 'Field: value'）。"""
    if not path.exists():
        return None
    try:
        for line in path.read_text().splitlines():
            if line.startswith(field + ":"):
                return line.split(":", 1)[-1].strip()
        return None
    except Exception:
        return None


def parse_tids(args):
    """
    解析命令行参数为 (pid, tid) 列表。
    输入格式: <tid>（纯数字）；pid 由 /proc/<tid>/status 的 Tgid 自动解析。
    """
    pairs = []
    for a in args:
        s = str(a).strip()
        if not s or not re.fullmatch(r"\d+", s):
            if s:
                print(f"忽略非 tid 参数: {a}", file=sys.stderr)
            continue
        tid = int(s)
        pid = _pid_from_tid(tid)
        if pid is None:
            print(f"忽略无效或已退出的 tid: {tid}", file=sys.stderr)
            continue
        pairs.append((pid, tid))
    seen = set()
    return [p for p in pairs if p not in seen and not seen.add(p)]


# ---------------------------------------------------------------------------
# 解析器：纯函数，输入文本输出结构化数据
# ---------------------------------------------------------------------------

def _expand_cpu_str(cpu_str):
    """将 '144-167' 或 '0-23,48-71' 展开为 CPU 列表。"""
    cpu_list = []
    for part in cpu_str.replace(" ", "").split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            try:
                cpu_list.extend(range(int(a.strip()), int(b.strip()) + 1))
            except ValueError:
                pass
        else:
            try:
                cpu_list.append(int(part))
            except ValueError:
                pass
    return sorted(cpu_list)


def parse_npu_topo_numa_mapping(npu_topo_raw, lscpu_parsed):
    """
    从 npu-smi info -t topo 的文本和 lscpu 结果，解析 NPU → CPU Affinity，再映射到 NUMA。
    支持两种 topo 格式：
    1) 行内 "CPU Affinity : 144-167"
    2) 表格式：每行以 NPU<n> 开头，最后一列为 CPU 范围（如 144-167）
    返回: npu_numa_mapping = {npu_id: {"cpu_affinity": [cpu, ...], "numa_nodes": [node, ...]}}
    """
    if not npu_topo_raw or not lscpu_parsed:
        return {}

    numa_cpu_map = lscpu_parsed.get("numa_cpu_map", {})
    node_cpu = {}
    for node_id, cpu_str in numa_cpu_map.items():
        node_cpu[int(node_id)] = set(_expand_cpu_str(cpu_str))

    npu_affinity = {}
    lines = npu_topo_raw.splitlines()
    header_found = any("CPU" in line and "Affinity" in line for line in lines)

    for line in lines:
        m = re.match(r"^\s*NPU\s*(\d+)", line, re.I)
        if not m:
            continue
        npu_id = int(m.group(1))
        cpu_list = None

        # 格式1: 行内 "CPU Affinity : 144-167"
        aff_m = re.search(r"CPU\s*Affinity\s*:\s*([0-9,\-\s]+)", line, re.I)
        if aff_m:
            cpu_list = _expand_cpu_str(aff_m.group(1))
        # 格式2: 表格式，最后一列为 CPU 范围（如 144-167）
        if not cpu_list:
            parts = line.split()
            if len(parts) >= 2:
                last = parts[-1].strip()
                if re.match(r"^[0-9]+-[0-9]+$", last) or re.match(r"^[0-9]+,[0-9\-]+$", last):
                    cpu_list = _expand_cpu_str(last)

        if not cpu_list:
            continue
        numa_nodes = set()
        for node, cpus in node_cpu.items():
            if set(cpu_list) & cpus:
                numa_nodes.add(node)
        npu_affinity[npu_id] = {
            "cpu_affinity": cpu_list,
            "numa_nodes": sorted(numa_nodes),
        }
    return npu_affinity

def parse_loadavg(text):
    if not text:
        return None
    parts = text.split()
    if len(parts) < 3:
        return None
    try:
        return {"load_1m": float(parts[0]), "load_5m": float(parts[1]), "load_15m": float(parts[2])}
    except ValueError:
        return None


def parse_lscpu(text):
    if not text:
        return None
    out = {}
    numa_cpu_map = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key, val = key.strip(), val.strip()
        if key == "CPU(s)":
            try:
                out["cpus"] = int(val)
            except ValueError:
                pass
        elif key == "NUMA node(s)":
            try:
                out["numa_nodes"] = int(val)
            except ValueError:
                pass
        elif key == "Thread(s) per core":
            try:
                out["threads_per_core"] = int(val)
            except ValueError:
                pass
        elif key == "Core(s) per socket":
            try:
                out["cores_per_socket"] = int(val)
            except ValueError:
                pass
        elif key.startswith("NUMA node") and "CPU(s)" in key:
            m = re.match(r"NUMA node(\d+)\s+CPU\(s\)", key)
            if m:
                numa_cpu_map[int(m.group(1))] = val
    if numa_cpu_map:
        out["numa_cpu_map"] = numa_cpu_map
    return out if out else None


def parse_numastat(text, pids):
    if not text or not pids:
        return None
    pid_set = {str(p) for p in pids}
    header = None
    for line in text.strip().split("\n"):
        if "Node" in line and re.search(r"Node\s+\d+", line):
            header = re.findall(r"Node\s*(\d+)", line)
            break
    if not header:
        return None
    out = {}
    for line in text.strip().split("\n"):
        parts = line.split()
        if not parts or parts[0] not in pid_set:
            continue
        try:
            nums = [float(x) for x in parts[1 : 1 + len(header)] if _is_num(x)]
            if len(nums) == len(header):
                node_mb = {f"node_{h}_mb": n for h, n in zip(header, nums)}
                node_mb["total_mb"] = round(sum(nums), 2)
                out[parts[0]] = node_mb
        except (ValueError, IndexError):
            pass
    return out if out else None


def _parse_perf_llc_text(text):
    out = {}
    for m in re.finditer(r"\s*(\d[\d,]*)\s+(LLC-load-misses|LLC-load)(?:\s|#|$)", text):
        try:
            out[m.group(2)] = int(m.group(1).replace(",", ""))
        except ValueError:
            pass
    for pattern, key in [
        (r"#\s*([\d.]+)\s*%\s*of\s*all\s*LL-cache\s*accesses", "llc_miss_rate_pct"),
        (r"([\d.]+)\s*seconds\s*time\s*elapsed", "time_elapsed_seconds"),
    ]:
        match = re.search(pattern, text, re.I)
        if match:
            try:
                out[key] = float(match.group(1))
            except ValueError:
                pass
    return out if out else None


# ---------------------------------------------------------------------------
# 采集器：执行命令并解析，按 pid-tid 或 pid 返回结构化结果
# ---------------------------------------------------------------------------


def get_taskset_parsed(pid_tid_pairs):
    out = {}
    for pid, tid in pid_tid_pairs:
        stdout, _, ok = run_cmd(["taskset", "-p", str(tid)], timeout=5)
        mask = None
        if ok and stdout:
            if ":" in stdout:
                part = stdout.split(":", 1)[-1].strip()
                if part and re.match(r"^[0-9a-fA-F,\s]+$", part):
                    mask = part
            if not mask:
                m = re.search(r"[\s:]([0-9a-fA-F][0-9a-fA-F,\s]*)$", stdout)
                if m and re.match(r"^[0-9a-fA-F,\s]+$", m.group(1).strip()):
                    mask = m.group(1).strip()
        out[_target_key(pid, tid)] = mask
    return out


def get_task_cpus_allowed_parsed(pid_tid_pairs):
    out = {}
    for pid, tid in pid_tid_pairs:
        val = _read_proc_field(Path(f"/proc/{pid}/task/{tid}/status"), "Cpus_allowed")
        out[_target_key(pid, tid)] = val
    return out


def get_task_current_cpu_parsed(pid_tid_pairs):
    out = {}
    for pid, tid in pid_tid_pairs:
        stat = Path(f"/proc/{pid}/task/{tid}/stat")
        if not stat.exists():
            out[_target_key(pid, tid)] = None
            continue
        try:
            parts = stat.read_text().split()
            out[_target_key(pid, tid)] = {"current_cpu": int(parts[38])} if len(parts) >= 39 else None
        except Exception:
            out[_target_key(pid, tid)] = None
    return out


def get_numastat_raw(pid_tid_pairs):
    if not pid_tid_pairs:
        return None
    pids = sorted({pid for pid, _ in pid_tid_pairs})
    stdout, _, ok = run_cmd(["numastat", "-p"] + [str(p) for p in pids], timeout=10)
    return stdout.strip() if ok and stdout else None


def get_ps_thread_parsed(pid_tid_pairs):
    if not pid_tid_pairs:
        return None
    pids = sorted({pid for pid, _ in pid_tid_pairs})
    wanted = {(pid, tid) for pid, tid in pid_tid_pairs}
    stdout, _, ok = run_cmd(
        ["ps", "-L", "-p", ",".join(str(p) for p in pids), "-o", "pid=,tid=,pcpu=,psr="],
        timeout=5,
    )
    if not ok or not stdout:
        return None
    out = {}
    for line in stdout.strip().splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        try:
            pid, tid = int(parts[0]), int(parts[1])
        except (ValueError, IndexError):
            continue
        if (pid, tid) not in wanted:
            continue
        out[_target_key(pid, tid)] = {
            "pcpu": float(parts[2]) if _is_num(parts[2]) else None,
            "psr": int(parts[3]) if parts[3].isdigit() else None,
        }
    return out if out else None



def get_npu_smi_topo_raw():
    stdout, _, ok = run_cmd(["npu-smi", "info", "-t", "topo"], timeout=10)
    raw = (stdout or "").strip()
    if not raw:
        return None
    lines = []
    for line in raw.splitlines():
        if line.strip().lower().startswith("legend"):
            break
        lines.append(line.rstrip())
    text = "\n".join(lines).strip()
    return text or None

def get_npu_smi_info_parsed():
    stdout, _, ok = run_cmd(["npu-smi", "info"], timeout=10)
    text = (stdout or "").strip()
    if not text:
        return None
    mapping = []
    in_process_table = False
    for line in text.splitlines():
        line_strip = line.strip()
        if "Process id" in line_strip and "NPU" in line_strip:
            in_process_table = True
            continue
        if not in_process_table:
            continue
        if "No running processes" in line_strip and "NPU" in line_strip:
            m = re.search(r"NPU\s*(\d+)", line_strip, re.I)
            if m:
                mapping.append({"npu_id": int(m.group(1)), "pid": None})
        elif "|" in line_strip:
            cells = [c.strip() for c in line_strip.split("|") if c.strip()]
            if len(cells) >= 3:
                try:
                    npu_id = int(cells[0].split()[0])
                    pid = int(cells[1].split()[0])
                    mapping.append({"npu_id": npu_id, "pid": pid})
                except (ValueError, IndexError):
                    pass
    return {"npu_pid_mapping": mapping} if mapping else None


def get_mpstat_parsed():
    stdout, _, ok = run_cmd(["mpstat", "-P", "ALL", "1", "1"], timeout=8)
    if not ok or not stdout:
        return None
    for line in stdout.split("\n"):
        if line.strip().startswith("Average:"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    return {"avg_idle_pct": round(float(parts[-1].replace(",", ".")), 2)}
                except ValueError:
                    pass
            break
    return None


def get_perf_llc_parsed(pid_tid_pairs):
    if not pid_tid_pairs:
        return None
    out = {}

    def _one_tid(pid, tid):
        stdout, stderr, ok = run_cmd(
            ["perf", "stat", "-e", "LLC-load,LLC-load-misses", "-t", str(tid), "sleep", "2"],
            timeout=15,
        )
        text = (stdout or "") + "\n" + (stderr or "")
        rec = _parse_perf_llc_text(text) if ok else None
        return _target_key(pid, tid), rec

    with ThreadPoolExecutor(max_workers=min(8, len(pid_tid_pairs))) as ex:
        futures = [ex.submit(_one_tid, pid, tid) for pid, tid in pid_tid_pairs]
        for fut in as_completed(futures):
            key, rec = fut.result()
            if rec:
                out[key] = rec
    return out if out else None


# ---------------------------------------------------------------------------
# 主采集流程
# ---------------------------------------------------------------------------


def collect_all(pid_tid_pairs):
    pid_tid_pairs = [(int(pid), int(tid)) for pid, tid in pid_tid_pairs]
    pids = sorted({pid for pid, _ in pid_tid_pairs})

    result = {
        "pid_tid_pairs": [{"pid": pid, "tid": tid} for pid, tid in pid_tid_pairs],
        "cpu_affinity": None,
        "cpus_allowed": None,
        "loadavg": None,
        "lscpu": None,
        "task_current_cpu": None,
        "ps_thread": None,
        "numastat_raw": None,
        "npu_topo": None,
        "npu_pid_numa_triple": None,
        "mpstat": None,
        "perf_llc": None,
        "errors": [],
    }

    def _run_one(name, fn):
        try:
            return name, fn(), None
        except Exception as e:
            return name, None, str(e)

    def _make_collectors():
        loadavg_text = Path("/proc/loadavg").read_text() if Path("/proc/loadavg").exists() else ""
        return [
            ("cpu_affinity", "taskset", lambda: get_taskset_parsed(pid_tid_pairs)),
            ("cpus_allowed", "cpus_allowed", lambda: get_task_cpus_allowed_parsed(pid_tid_pairs)),
            ("loadavg", "loadavg", lambda: parse_loadavg(loadavg_text)),
            ("lscpu", "lscpu", lambda: parse_lscpu(run_cmd(["lscpu"], timeout=5)[0])),
            ("task_current_cpu", "task_cpu", lambda: get_task_current_cpu_parsed(pid_tid_pairs)),
            ("ps_thread", "ps_thread", lambda: get_ps_thread_parsed(pid_tid_pairs)),
            ("numastat_raw", "numastat", lambda: get_numastat_raw(pid_tid_pairs)),
            ("npu_topo_raw", "npu_topo_raw", get_npu_smi_topo_raw),
            ("npu_smi_info", "npu_smi_info", get_npu_smi_info_parsed),
            ("mpstat", "mpstat", get_mpstat_parsed),
            ("perf_llc", "perf_llc", lambda: get_perf_llc_parsed(pid_tid_pairs)),
        ]

    data_buffer = {}

    with ThreadPoolExecutor(max_workers=10) as ex:
        collectors = _make_collectors()
        futures = [ex.submit(_run_one, name, fn) for _, name, fn in collectors]
        key_by_name = {name: key for key, name, _ in collectors}
        for fut in as_completed(futures):
            name, data, err = fut.result()
            if err:
                result["errors"].append(f"{name}: {err}")
            elif data is not None:
                data_buffer[key_by_name[name]] = data

    npu_topo_raw = data_buffer.get("npu_topo_raw")
    lscpu = data_buffer.get("lscpu")
    npu_pid_mapping = (data_buffer.get("npu_smi_info") or {}).get("npu_pid_mapping", [])
    npu_numa_mapping = parse_npu_topo_numa_mapping(npu_topo_raw or "", lscpu or {})
    npu_pid_numa_triple = []
    for npupid in npu_pid_mapping:
        npu_id = npupid.get("npu_id")
        pid = npupid.get("pid")
        npu_aff = npu_numa_mapping.get(npu_id, {})
        triple = {
            "npu_id": npu_id,
            "pid": pid,
            "cpu_affinity": npu_aff.get("cpu_affinity", None),
            "numa_nodes": npu_aff.get("numa_nodes", None),
        }
        npu_pid_numa_triple.append(triple)
    result["npu_pid_numa_triple"] = npu_pid_numa_triple

    if lscpu is not None:
        result["lscpu"] = lscpu
    if npu_topo_raw is not None:
        result["npu_topo"] = {"npu_topo_raw": npu_topo_raw}
    for k in data_buffer:
        if k not in ["npu_topo_raw"]:
            result[k] = data_buffer[k]

    if result.get("cpu_affinity") and result.get("cpus_allowed"):
        for k in result["cpu_affinity"]:
            if result["cpu_affinity"][k] is None and result["cpus_allowed"].get(k):
                result["cpu_affinity"][k] = result["cpus_allowed"][k]

    result["errors"] = result["errors"] or None
    if result["errors"] is None:
        del result["errors"]
    return {k: v for k, v in result.items() if v is not None}


# ---------------------------------------------------------------------------
# 输出格式化
# ---------------------------------------------------------------------------


def to_md(data):
    """转为紧凑 Markdown，只含解析后的有效信息。"""
    lines = ["## 瓶颈信息摘要（已解析）", ""]
    if "pid_tid_pairs" in data:
        pairs = data["pid_tid_pairs"]
        lines.append(
            "- **PID-TID**: "
            + ", ".join(
                f"{p.get('pid')}-{p.get('tid')}"
                for p in pairs
                if p.get("pid") is not None and p.get("tid") is not None
            )
        )
    if "loadavg" in data:
        l = data["loadavg"]
        lines.append(f"- **负载**: 1m={l.get('load_1m')} 5m={l.get('load_5m')} 15m={l.get('load_15m')}")
    if "lscpu" in data:
        lines.append(f"- **CPU 拓扑**: {data['lscpu']}")
    lines.append("")

    if "cpu_affinity" in data:
        lines.append("### CPU 亲和 (taskset)")
        for k, mask in data["cpu_affinity"].items():
            lines.append(f"- {k}: {mask or '-'}")
        lines.append("")
    if "task_current_cpu" in data:
        lines.append("### 线程当前 CPU")
        for k, t in data["task_current_cpu"].items():
            if t:
                lines.append(f"- {k}: cpu={t.get('current_cpu')}")
        lines.append("")
    if "ps_thread" in data:
        lines.append("### 线程占用 (ps -L)")
        for k, u in data["ps_thread"].items():
            lines.append(f"- {k}: %cpu={u.get('pcpu')} psr={u.get('psr')}")
        lines.append("")
    if "numastat_raw" in data:
        lines.append("### 进程内存分布 (numastat -p <pid> 原始输出)")
        lines.append("")
        lines.append("```")
        lines.append(data["numastat_raw"])
        lines.append("```")
        lines.append("")
    if "mpstat" in data:
        lines.append(f"- **mpstat 摘要**: avg_idle_pct={data['mpstat'].get('avg_idle_pct')}%")
    if "perf_llc" in data:
        lines.append("### LLC (perf，按 tid 区分)")
        for key, plc in data["perf_llc"].items():
            parts = [f"LLC-load={plc.get('LLC-load')}", f"LLC-load-misses={plc.get('LLC-load-misses')}"]
            if plc.get("llc_miss_rate_pct") is not None:
                parts.append(f"miss_rate%={plc['llc_miss_rate_pct']}")
            if plc.get("time_elapsed_seconds") is not None:
                parts.append(f"time_elapsed_s={plc['time_elapsed_seconds']}")
            lines.append(f"- **{key}**: " + ", ".join(parts))
        lines.append("")
    # if "npu_topo" in data:
    #     raw = data["npu_topo"].get("npu_topo_raw") or ""
    #     if raw:
    #         lines.append("### npu-smi info -t topo")
    #         lines.append("```")
    #         lines.append(raw)
    #         lines.append("```")
    #         lines.append("")
    # NPU-PID-NUMA 三元组：npu-smi info（NPU↔PID）+ topo（NPU↔CPU）+ lscpu（NUMA↔CPU）→ NPU-PID-NUMA
    if "npu_pid_numa_triple" in data:
        triples = data["npu_pid_numa_triple"]
        lines.append("### NPU-PID-NUMA 三元组 (npu-smi info + topo CPU Affinity + lscpu NUMA 映射)")
        lines.append("")
        if triples:
            lines.append("| NPU | PID | NUMA node(s) | CPU Affinity |")
            lines.append("|-----|-----|--------------|--------------|")
            for t in triples:
                npu_id = t.get("npu_id", "")
                pid = t.get("pid")
                pid_str = str(pid) if pid is not None else "(无进程)"
                numa_nodes = t.get("numa_nodes") or []
                numa_str = ",".join(map(str, numa_nodes)) if numa_nodes else "-"
                aff = t.get("cpu_affinity") or []
                if not aff:
                    aff_str = "-"
                elif aff == list(range(aff[0], aff[-1] + 1)):
                    aff_str = f"{aff[0]}-{aff[-1]}"
                else:
                    aff_str = ",".join(map(str, aff))
                    if len(aff_str) > 36:
                        aff_str = aff_str[:33] + "..."
                lines.append(f"| {npu_id} | {pid_str} | {numa_str} | {aff_str} |")
        else:
            lines.append("> (无 NPU-PID-NUMA 信息，需 npu-smi info 与 topo 及 lscpu)")
        lines.append("")
    if data.get("errors"):
        lines.append("### 采集失败")
        lines.extend(f"- {e}" for e in data["errors"])
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    fmt = "md" if "--md" in args else "json"
    args = [a for a in args if a != "--md"]

    if not args:
        print("用法: collect_system_info.py <tid> [tid ...] [--md]", file=sys.stderr)
        sys.exit(1)

    pairs = parse_tids(args)
    if not pairs:
        print("未提供有效 tid", file=sys.stderr)
        sys.exit(1)

    data = collect_all(pairs)
    print(to_md(data) if fmt == "md" else json.dumps(data, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
