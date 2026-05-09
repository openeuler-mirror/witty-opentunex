# net-bottleneck 设计文档

## 瓶颈判定规则

```bash
# ss -s 关键指标
TIME_WAIT > 2000  → 连接积压
Establised > 80%   → 连接数高

# netstat -s
RetransSegs > 1%   → 重传过多
TCPTTimeouts > 1000 → 超时频繁

# ping
rtt > 5ms          → 延迟异常
```

## 分析流程

```
Step 1: 环境检查
├→ ss -s
├→ cat /proc/net/sockstat
└→ ping测试

Step 2: 连接分析
├→ ss -tan状态统计
└→ 连接状态分布

Step 3: 协议分析
├→ netstat -s重传统计
└→ TCP窗口分析

Step 4: 优化建议
└→ tcp_tw_reuse等
```

## 流程图 (Mermaid)

### 主流程图

```mermaid
flowchart TD
    A[用户请求] --> B[Step 1: 环境检查]
    B --> C[ss/sockstat/ping]
    C --> D[Step 2: 连接分析]
    D --> E[ss -tan状态统计]
    E --> F{状态分布}
    F --> G{TIME_WAIT > 2000?}
    G -->|是| H[连接积压瓶颈]
    F --> I{Establised > 80%}
    I -->|是| J[连接数高瓶颈]
    G -->|否| K{Retrans > 1%?}
    I -->|否| K
    K -->|是| L[重传过多瓶颈]
    K -->|否| M[继续其他指标]
    H --> N[Step 3: 协议分析]
    J --> N
    L --> N
    M --> N
    N --> O[Step 4: 优化建议]
    O --> P[输出瓶颈报告]
```

### 瓶颈判定

```mermaid
flowchart LR
    A[netstat -s] --> B{TIME_WAIT}
    A --> C{RetransSegs}
    A --> D{TCPTTimeouts}
    B -->|2000以上| E[连接积压]
    C -->|1%以上| F[重传过多]
    D -->|1000以上| G[超时频繁]
```
