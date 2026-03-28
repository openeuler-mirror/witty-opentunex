# Affinity Strategy Guide

## Strategy Generation Procedure

1. Recite available NUMA nodes and their CPU core lists from `topology_graph.txt`
2. Assign NUMA node for each process based on bottleneck analysis
3. Split CPU list on assigned NUMA: dedicated ranges for key threads, remainder for other threads
4. Generate executable commands

---

## Commands

| Command | Purpose |
|---------|---------|
| `migratepages <PID> all <NUMA>` | Migrate process memory to NUMA node |
| `taskset -acp <CPU_LIST> <PID>` | Set CPU affinity for process (all threads inherit) |
| `taskset -cp <CPU_LIST> <TID>` | Set CPU affinity for specific thread |

---

## Critical Rules

- **NUMA alignment**: CPU list MUST match NUMA node. NEVER assign CPUs from NUMA X while migrating pages to NUMA Y.
- **Parent-child coherence**: When migrating process pages, child threads inherit. Keep parent and key child threads on same NUMA.
- **Resource isolation**: Important threads get dedicated CPU ranges; less important threads follow parent's default. 
- **Process separation**: Different processes can share NUMA but AVOID overlapping CPU lists.
- When NUMA resources are sufficient (NUMA num > worker num), different worker process groups should be distributed across different NUMA nodes to have ample L3 cache resources. It is **more important than NUMA-NPU affinity**.

### **IMPORTANT**: NUMA Allocation Policy for Worker Processes

The following rules GOVERN the allocation of Worker processes to NUMA nodes, assuming Worker `i` intends to access NPU `j`:

1. **Affinity Allocation**
    If the affinity NUMA node of NPU `j` is unoccupied, Worker `i` shall be allocated to this affinity NUMA node.
 
2. **Proximity Allocation**
    If the affinity NUMA node of NPU `j` is already occupied by another Worker, Worker `i` shall be allocated to the nearest available (free) NUMA node relative to the affinity NUMA node.
    try to AVOID assigning two worker to the same NUMA if there are still free NUMA. The the penalty of L3 Cache contention due to sharing a NUMA node might be larger than the benefit from "NPU-NUMA" affinity.

3. **Resource Contention Allocation**
    If all NUMA nodes are occupied but there are still unallocated Workers, the scheduler must balance the trade-offs between the performance penalty of cross-NUMA access and the penalty of L3 Cache contention due to sharing a NUMA node. Allocation should proceed based on this balanced assessment.


---

## Command Template

```bash
migratepages <PID> all <NUMA_NODE> && \
taskset -acp <CPU_LIST_DEFAULT> <PID> && \
taskset -cp <CPU_LIST_THREAD1> <TID1> && \
taskset -cp <CPU_LIST_THREAD2> <TID2>
```

Where:
- `<CPU_LIST_DEFAULT>`: Default range for less important threads
- `<CPU_LIST_THREAD1/2>`: Dedicated ranges for key threads
- All CPU lists must be on `<NUMA_NODE>`

---

* **Example**:
Assume I'm assigning numa 0 to process 1000(with threads 1000~1010, among wich thread 1002 and 1003 are important threads):

Assmue Numa 0 has CPU 0-31, and Numa 1 has CPU 32-63.

Then I should:
- `migratepages 1000 all 0` to migrate the process memory to NUMA 0
- `taskset -acp 0-7 1000` to assign the default cpu list for process 1000
- `taskset -cp 8-15 1000` to assign the cpu list for for main thread 1000
- `taskset -cp 16-23 1002` to assign the cpu list for for main thread 1002
- `taskset -cp 24-31 1003` to assign the cpu list for important thread 1003


Similarly, I'm assigning numa 1 to process 2000(with threads 2000~2010, among wich thread 2002 and 2003 are important threads) to avoid resource contention with process 1000:
- `migratepages 2000 all 1` to migrate the process memory to NUMA 1
- `taskset -acp 32-39 2000` to assign the default cpu list for process 2000
- `taskset -cp 40-47 2000` to assign the cpu list for for main thread 2000
- `taskset -cp 48-55 2002` to assign the cpu list for important thread 2002
- `taskset -cp 56-63 2003` to assign the cpu list for important thread 2003

If some process are less important, they can share the resources:
- `migratepages 3000 all 2-7` to migrate the process memory to NUMA 1
- `taskset -acp 24-191 3000` to assign the cpu list for process 3000 without splitting the cpu list for important threads and less important threads, because the process is less important and we don't care about the resource contention within the process. But we assign the cpu list not overlapping with the cpu list of process 1000/2000 to avoid resource contention between process 3000 and process 1000/2000.

```bash 
# Worker 1
migratepages 1000 all 0 && \
taskset -acp 0-7 1000
# Worker 1 Key threads
taskset -cp 8-15 1000 && \
taskset -cp 16-23 1002 && \
taskset -cp 24-31 1003

# Worker 2
migratepages 2000 all 1 && \
taskset -acp 32-39 2000
# Worker 2 Key threads
taskset -cp 40-47 2000 && \
taskset -cp 48-55 2002 && \
taskset -cp 58-63 2003
 
# Others
migratepages 3000 all 2-7 && \
taskset -acp 64-255 3000
```

---

## Output

Save script to `<work_dir>/tmp/affinity_strategy.sh`

**Script Style**:
- No `echo` statements (concise)
- No process stops (apply affinity on-the-fly)
- Group by worker with comments
- Use `&&` for command chaining
