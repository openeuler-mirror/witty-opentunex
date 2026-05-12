# io-bottleneck 设计文档

## 使用场景

### 典型场景

1. **IO问题诊断** - 磁盘利用率高、IO等待高
2. **top-down补充** - 全局分析后深入IO层面
3. **优化前分析** - IO优化前确定瓶颈

### 不适用

- 应用层IO问题 - 使用application-bottleneck
- 已知需应用优化 - 不是IO问题

## 瓶颈判定规则

```bash
# iostat关键指标
%util > 90%   → IO饱和
await > 20ms   → IO延迟高
avgqu-sz > 8   → 队列积压
svctm > 10ms  → 设备延迟

# vmstat关键指标
wa > 20%       → IO等待高
b > 0           → 有阻塞进程

# mpstat
%iowait > 20% → CPU等待IO
```

## 分析流程

```
Step 1: 环境检查
├→ 磁盘类型 (SSD/HDD)
├→ 调度器
└→ 可用队列深度

Step 2: 指标收集 (30s)
├→ vmstat 1 30
├→ iostat -xz 1 30
└→ mpstat -P ALL 1 30

Step 3: 瓶颈分析
├→ IO饱和分析
├→ 延迟分析
└→ 队列分析

Step 4: 优化建议
└→ 输出优化策略
```

## 流程图 (Mermaid)

### 主流程图

```mermaid
flowchart TD
    A[用户请求] --> B[Step 1: 环境检查]
    B --> C[磁盘类型/调度器]
    C --> D[Step 2: 指标收集]
    D --> E[iostat 30s]
    D --> F[vmstat 30s]
    D --> G[mpstat 30s]
    E --> H[Step 3: 瓶颈分析]
    F --> H
    G --> H
    H --> I{util > 90%?}
    I -->|是| J[IO饱和瓶颈]
    I -->|否| K{await > 20ms?}
    K -->|是| L[IO延迟瓶颈]
    K -->|否| M{队列 > 8?}
    M -->|是| N[队列积压瓶颈]
    M -->|否| O[无明显瓶颈]
    J --> P[优化建议]
    L --> P
    N --> P
    O --> P
```

### 瓶颈判定规则

```mermaid
flowchart LR
    A[iostat指标] --> B{%util}
    A --> C{await}
    A --> D{avgqu-sz}
    B -->|90%以上| E[瓶颈: IO饱和]
    C -->|20ms以上| F[瓶颈: IO延迟]
    D -->|8以上| G[瓶颈: 队列积压]
```

## 异常处理

| 异常 | 处理 |
|------|------|
| 工具缺失 | 报告安装方法 |
| 权限不足 | 降级分析 |
| 数据收集失败 | 部分收集 |
