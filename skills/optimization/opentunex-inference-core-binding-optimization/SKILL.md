---
name: opentunex-inference-core-binding-optimization
description: Use this skill to optimize inference workloads for latency and throughput by performing process/thread-level affinity and NUMA placement tuning on the host system. This skill is focused on optimizing host-side deployments of key inference processes/threads via CPU core binding and memory affinity, enhancing host-side performance.
---

# Host-Side Optimization for Inference Workloads

This skill is dedicated to host-side deployment optimizations aimed at eliminating long-tail latency and latency jitter resulting from suboptimal topology distribution. For identified key processes and threads in inference workloads, the skill proceeds through: **System Information Collection → Bottleneck Analysis → Core Affinity Strategy Generation → Affinity Implementation**.

## Scenario
NPU hardware, vllm-ascend inference workloads, Linux systems
---

### Phase 1: Key Process/Thread Discovery

Choose from the following three options: 
1. If "topo-info" have already been executed in previous content -> directly analysis the most important threads.
2. If no "topo-info" generation information is found above and the current client **has** the capability for "topo" -> run the "topo-info" (see [topo-info.md](references/topo-info.md)) to supplement additional information. 
3. If the current client does **not have** the capability for topo -> ask the user to input the key process/threads.

Record the most important threads (top 20–30) in the following table:

| PID/TID | Name | Role | Key Function |
|---------|------|------|--------------|
| ...     | ...  | ...  | ...          |
| ...     | ...  | ...  | ...          |

---

### Phase 2: System Information Collection

**Actions:**

1. **Verify sufficiency of key data:** Ensure the output includes the following information:
    - NPU topology
    - CPU topology
    - Current PID–NPU mapping
    - CPU affinity status
    - Process memory distribution
    - Cache usage

If sufficient, **avoid extra tooling**; if insufficient, **supplement with additional tools** to gather what is required.

2. **Run collection script:** Invoke `scripts/collect_system_info.py <tid> [tid ...] --md` to collect system information and summarize results in structured form.

---

### Phase 3: Bottleneck Analysis
**MUST read** [bottleneck.md](references/bottleneck.md) for detailed guidelines, and then analyze hot processes/threads for bottlenecks.

**Actions:**
Analyze potential bottlenecks for hot processes/threads.

**Output:** Bottleneck analysis report:
```markdown
# Hot Process/Thread & Bottleneck Mapping
| PID/TID | Name | Role | Key Function | Main Bottleneck/Evidence |
|---------|------|------|--------------|--------------------------|
| ...     | ...  | ...  | ...          | ...                      |
| ...     | ...  | ...  | ...          | ...                      |
```

**Output**: Bottleneck report with table:
```markdown
## Bottleneck Summary
(Brief summary of topology, cache, communication, scheduling issues)

## Hot Process/Thread & Bottleneck Mapping
| PID | TID | Name | Role | Key Function | Main Bottleneck/Evidence |
|-----|-----|------|------|--------------|--------------------------|
| ... | ... | ...  | ...  | ...          | ...                      |
```

## Phase 3: Affinity Strategy Generation

**MUST read** [affinity.md](references/affinity.md) for detailed examples, and then generate CPU affinity commands.

**Output**: Save affinity bash to `<work_dir>/tmp/affinity_strategy.sh`

---

## Phase 4: Execute Optimization

1. Ask User if execute the script. After user agree, execute script without output clutter:
```bash
bash <work_dir>/tmp/affinity_strategy.sh > /dev/null
```

NOTE: Redirect output to avoid clutter. Check for errors.