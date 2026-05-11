# application-bottleneck

应用级瓶颈分析Skill，识别MySQL、Redis、PostgreSQL、Kafka等应用内部性能问题。

## 总体功能

提供应用级瓶颈分析，主要功能包括：

1. **应用检测** - 识别运行中的应用类型
2. **指标收集** - 收集应用级性能指标
3. **瓶颈分析** - 识别应用内部瓶颈
4. **系统关联** - 关联应用与系统资源使用

**Scope**: 仅分析应用层组件，用于top-down瓶颈分析后的深度分析

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行
- **top-down-bottleneck skill** - 前置系统级分析（建议）

### 应用环境要求

| 应用 | 必需条件 |
|------|----------|
| MySQL | root/admin权限执行SHOW命令 |
| Redis | redis-cli可用 |
| PostgreSQL | psql可用，pg_stat视图权限 |
| Kafka | kafka命令行工具 |
| Nginx | stub_status模块启用 |
| MongoDB | mongosh可用 |

## 用法

### 自然语言输入示例

```
分析192.168.1.100上MySQL的内部瓶颈
```

```
Redis缓存命中率低，帮我分析下原因
```

```
对PostgreSQL进行深度瓶颈分析
```

### 执行流程

```
Phase 1: 应用检测
    ├→ 检测运行中的应用
    └→ 确定分析目标

Phase 2: 指标收集
    ├→ 查询应用状态命令
    └→ 收集性能指标

Phase 3: 瓶颈识别
    ├→ 分析指标异常
    └→ 识别瓶颈类型

Phase 4: 系统关联
    ├→ 关联系统资源使用
    └→ 输出综合报告
```

### 输出示例

```markdown
## MySQL瓶颈分析报告

### 检测到的应用
| 应用 | PID | 端口 | 版本 |
|------|-----|------|------|
| MySQL | 1234 | 3306 | 8.0.32 |

### 性能指标

| 指标 | 当前值 | 阈值 | 状态 |
|------|--------|------|------|
| 连接使用率 | 85% | 70% | ⚠️ |
| 缓冲池命中率 | 72% | 95% | ❌ |
| 锁等待时间 | 2.3s | 0.5s | ❌ |
| 慢查询数 | 150/s | 50/s | ❌ |

### 瓶颈识别

| 瓶颈 | 严重程度 | 证据 |
|------|----------|------|
| 缓冲池过小 | 高 | 命中率仅72%，大量磁盘IO |
| 连接池不足 | 中 | 连接使用率85% |

### 系统关联
- 磁盘IO高 → 由缓冲池不足导致
- CPU iowait高 → 由慢查询导致
```

## 支持的应用

| 应用 | 分析命令 | 关键指标 |
|------|----------|----------|
| MySQL | SHOW ENGINE INNODB STATUS | 缓冲池、锁、事务 |
| Redis | INFO, CONFIG GET * | 内存、命中率、过期 |
| PostgreSQL | pg_stat_* views | 连接、查询、VACUUM |
| Kafka | kafka-topics | 延迟、消费组 |
| Nginx | stub_status | 请求、连接 |
| MongoDB | serverStatus | 操作数、内存、连接 |
| Java | jstat/jstack | GC、堆、线程 |
| Go | runtime stats | Goroutine、GC |

## 参考文档

- [references/scenarios/mysql.md](references/scenarios/mysql.md)
- [references/scenarios/redis.md](references/scenarios/redis.md)
- [references/scenarios/postgres.md](references/scenarios/postgres.md)
- [references/scenarios/kafka.md](references/scenarios/kafka.md)
- [references/scenarios/nginx.md](references/scenarios/nginx.md)
- [references/scenarios/mongodb.md](references/scenarios/mongodb.md)
- [references/scenarios/java.md](references/scenarios/java.md)
- [references/scenarios/golang.md](references/scenarios/golang.md)
