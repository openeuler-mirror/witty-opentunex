---
name: topo-info
description: Collect system topology via Anansi (processes, sockets, IPC, devices, NUMA). Requires topo capability.
---

**Do NOT use when**:
- Client has no `topo` capability
- Only a simple process list is needed (use `opentunex_bash` instead)
- Real-time streaming data is required (topo returns a snapshot)

---

## Information Obtained

**Source**: Anansi collectors (Socket, SharedMemory, NPU, GPU, NUMA, Container, etc.)

**Output**: `topology_graph.txt` content (path on client: `local/anansi/run/topology_graph.txt` or `local/run/anansi/topology_graph.txt` depending on Anansi config)

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

1. Ensure session is bound to a client with `topo` (check via `opentunex_get_clients`).
2. Call `opentunex_topo` with `pid` (optional): pass target process PID as seed, or omit/0 for full collection.
3. Tool returns the raw `topology_graph.txt` content.

**Important**: Use `pid` only. Do NOT pass `duration` — that parameter is deprecated.

---

## References

For full entity/edge tables and metrics: Anansi docs `architecture/graph-model.md`, `monitoring/overview.md`.
