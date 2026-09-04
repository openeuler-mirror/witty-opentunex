---
name: topo-info
description: Collect system topology via witty-profiler (processes, sockets, IPC, devices, NUMA). Requires witty-profiler.
---

**Do NOT use when**:
- witty-profiler not available
- Real-time streaming data is required (topo returns a snapshot)

---

## Information Obtained

**Source**: witty-profiler collectors (Socket, SharedMemory, NPU, GPU, NUMA, Container, etc.)

**Output**: `topology_graph.txt`

**Format**:

```text
Graph with N nodes and M edges
Nodes:
  - [namespace]EntityType_unique_id
  - ...
Edges:
  - source->target
  - ...
```

**Entity types** (nodes): ProcessEntity, ThreadEntity, SocketEntity, SharedMemoryEntity, PipeInodeEntity, NumaEntity, DeviceEntity (GPU/NPU), ContainerEntity, PodEntity, RDMA_QP

**Edge types**: SendToSocketEdge (process→socket), IPCEdge, OwnEdge/BelongEdge (parent-child), AccessEdge, NumaAccessEdge

---

## How to Interpret

- **Nodes**: Use `EntityType` to distinguish processes, sockets, shared memory, devices, containers. `unique_id` semantics: ProcessEntity = `pid=1234,ppid=1`, SocketEntity = `127.0.0.1:18090(TCP)`.
- **Edges**: Direction indicates data flow (e.g. process→socket = send) or structure (Own/Belong = parent-child).
- **Analysis**: Count nodes by type; locate services by socket addr/port; map PIDs to workloads.

---

## Call Instructions

1. Ensure witty-profiler is available on the client.
2. Call `witty-profiler --offline --duration 30 [--pid <target_pid>]`: pass target process PID as seed via `--pid`, or omit for full collection.
3. Tool returns the raw `topology_graph.txt` content.

---

## References

For full entity/edge tables and metrics: see https://gitcode.com/openeuler/witty-profiler/blob/master/collector/python/docs/architecture/graph-model.md
