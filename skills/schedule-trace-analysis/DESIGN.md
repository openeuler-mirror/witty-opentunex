# schedule-trace-analysis 设计文档

## 瓶颈判定规则

```bash
# perf sched延迟
avg delay > 10ms    → 调度延迟高
max delay > 50ms    → 严重延迟

# perf sched切换
cs > 50%            → 频繁上下文切换
```

## 分析流程

```
Phase 1: 环境准备
├→ kernel版本检查
├→ perf可用性
└→ sched_schedstats启用

Phase 2: CPU拓扑
├→ lscpu
├→ numactl --hardware
└→ /proc/cpuinfo

Phase 3: 数据收集
├→ perf sched record
└→ 采集15-30s

Phase 4: 调度分析
├→ perf sched latency
├→ perf sched map
└→ perf sched hist
```

## 流程图 (Mermaid)

### 主流程图

```mermaid
flowchart TD
    A[用户请求] --> B[Phase 1: 环境准备]
    B --> C[perf可用性检查]
    C --> D[sched_schedstats启用]
    D --> E[Phase 2: CPU拓扑]
    E --> F[lscpu/numactl]
    F --> G[Phase 3: 数据收集]
    G --> H[perf sched record 15-30s]
    H --> I[Phase 4: 调度分析]
    I --> J[perf sched latency]
    J --> K{avg delay > 10ms?}
    K -->|是| L[调度延迟瓶颈]
    K -->|否| M[perf sched map]
    M --> N[perf sched hist]
    N --> O[输出调度报告]
```

### 瓶颈判定

```mermaid
flowchart LR
    A[perf sched] --> B{avg delay}
    A --> C{max delay}
    A --> D{cs切换}
    B -->|10ms以上| E[调度延迟高]
    C -->|50ms以上| F[严重延迟]
    D -->|50%以上| G[频繁切换]
```
