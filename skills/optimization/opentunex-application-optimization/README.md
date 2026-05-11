# application-optimization

应用级性能优化Skill，针对MySQL、Redis、PostgreSQL、Kafka、Nginx等应用进行配置优化。

## 总体功能

执行应用级性能优化，主要功能包括：

1. **应用检测** - 识别运行中的应用及版本
2. **瓶颈分析** - 调用application-bottleneck skill进行深度分析
3. **配置备份** - 备份当前应用配置
4. **优化推荐** - 基于瓶颈提出应用级优化策略
5. **优化执行** - 应用配置变更
6. **效果验证** - 通过基准测试验证

**Scope**: 仅分析应用层组件，不包含OS级别组件(内核、调度器等)

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行
- **application-bottleneck skill** - 应用级瓶颈分析

### 应用环境要求

| 应用 | 必需条件 |
|------|----------|
| MySQL | 服务运行，mysql客户端可用 |
| Redis | 服务运行，redis-cli可用 |
| PostgreSQL | 服务运行，psql可用 |
| Kafka | 服务运行，kafka tools可用 |
| Nginx | 服务运行，nginx可用 |
| MongoDB | 服务运行，mongosh可用 |
| Java | JVM应用运行 |
| Go | Go应用运行 |

## 用法

### 自然语言输入示例

```
优化192.168.1.100上MySQL的性能
```

```
分析并优化Redis的配置，提高缓存命中率
```

```
对PostgreSQL进行性能优化，连接池配置和查询优化
```

### 执行流程

1. **Phase 1: 应用检测**
   - 检测运行中的应用
   - 检查监听端口

2. **Phase 2: 瓶颈分析**
   - 调用application-bottleneck skill
   - 收集应用级指标

3. **Phase 3: 配置备份**
   - 备份应用配置文件

4. **Phase 4: 优化推荐**
   - 查询优化策略库
   - 生成推荐报告

5. **Phase 5: 优化执行**
   - 用户确认后应用变更

6. **Phase 6: 效果验证**
   - 基准测试验证

### 输出示例

```markdown
## MySQL优化报告

### 检测到的应用
| 应用 | 状态 | 端口 | 版本 |
|------|------|------|------|
| MySQL | 运行中 | 3306 | 8.0.32 |

### 瓶颈分析
| 指标 | 当前值 | 阈值 | 状态 |
|------|--------|------|------|
| 连接使用率 | 85% | 70% | ⚠️ 高 |
| 缓冲池命中率 | 72% | 95% | ❌ 低 |
| 慢查询 | 150/s | 50/s | ❌ 高 |

### 推荐优化

#### OPT-1: innodb_buffer_pool_size
- **当前**: 128M
- **推荐**: 4G
- **原因**: 缓冲池过小，命中率低

#### OPT-2: max_connections
- **当前**: 151
- **推荐**: 500
- **原因**: 连接使用率达到85%

---

是否应用以上优化?
1. 应用优化
2. 跳过
```

## 关键输出件

| 输出件 | 路径/位置 | 说明 |
|--------|-----------|------|
| 应用检测报告 | Skill输出 | 检测到的应用列表 |
| 瓶颈分析报告 | Skill输出 | Phase 2结果 |
| 配置备份 | /opt/opentunex/backup/app/ | 应用配置备份 |
| 优化报告 | Skill输出 | Phase 4结果 |
| 测试结果 | Skill输出 | 优化后基准测试 |

## 支持的应用

| 应用 | 优化重点 | 配置文件 |
|------|----------|-----------|
| MySQL | InnoDB缓冲池、连接池、查询缓存 | /etc/mysql/my.cnf |
| Redis | 内存管理、持久化、集群 | /etc/redis/redis.conf |
| PostgreSQL | 共享缓冲、工作内存、VACUUM | /var/lib/pgsql/data/postgresql.conf |
| Kafka | Broker参数、生产者/消费者调优 | /etc/kafka/server.properties |
| Nginx | Worker进程、缓存、SSL、keepalive | /etc/nginx/nginx.conf |
| MongoDB | WiredTiger缓存、日志、分片 | /etc/mongod.conf |
| Java | JVM堆、GC、线程池 | application config |
| Go | GOMAXPROCS、GOGC、runtime | application config |

## 参考文档

- [references/scenarios/mysql.md](references/scenarios/mysql.md)
- [references/scenarios/redis.md](references/scenarios/redis.md)
- [references/scenarios/postgres.md](references/scenarios/postgres.md)
- [references/scenarios/nginx.md](references/scenarios/nginx.md)
- [references/scenarios/kafka.md](references/scenarios/kafka.md)
- [references/scenarios/mongodb.md](references/scenarios/mongodb.md)
- [references/scenarios/java.md](references/scenarios/java.md)
- [references/scenarios/golang.md](references/scenarios/golang.md)
