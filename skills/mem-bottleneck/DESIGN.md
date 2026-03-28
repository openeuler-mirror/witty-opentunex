# mem-bottleneck 设计文档

## 瓶颈判定规则

```bash
# vmstat/sar关键指标
used% > 90%   → 内存压力
swap% > 10%   → Swap异常活跃
si/so > 10MB  → 内存颠簸
majflt > 1000  → 严重页错误

# slab
Slab > 30%     → 内核内存压力
```

## 分析流程

```
Step 1: 环境检查
├→ free -h
├→ numactl --hardware
└→ cat /proc/meminfo

Step 2: 指标收集 (15s)
├→ vmstat 1 15
├→ sar -r 1 15
└→ sar -B 1 15

Step 3: 内存分析
├→ 压力分析
├→ Swap分析
└→ Slab分析

Step 4: NUMA分析 (如适用)
└→ 跨节点访问检测
```

## 流程图 (Mermaid)

### 主流程图

```mermaid
flowchart TD
    A[用户请求] --> B[Step 1: 环境检查]
    B --> C[free/numactl/meminfo]
    C --> D[Step 2: 指标收集]
    D --> E[vmstat/sar 15s]
    E --> F[Step 3: 内存分析]
    F --> G{used% > 90%?}
    G -->|是| H[内存压力瓶颈]
    G -->|否| I{swap% > 10%?}
    I -->|是| J[Swap异常瓶颈]
    I -->|否| K{majflt > 1000?}
    K -->|是| L[内存颠簸瓶颈]
    K -->|否| M[继续其他指标]
    H --> N[Step 4: NUMA分析]
    J --> N
    L --> N
    M --> N
    N --> O[输出瓶颈报告]
```

### 瓶颈判定

```mermaid
flowchart LR
    A[vmstat指标] --> B{used%}
    A --> C{swap%}
    A --> D{majflt}
    B -->|90%以上| E[内存压力]
    C -->|10%以上| F[Swap异常]
    D -->|1000以上| G[内存颠簸]
```
