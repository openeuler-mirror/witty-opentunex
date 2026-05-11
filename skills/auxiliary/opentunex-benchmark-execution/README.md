# benchmark-execution

应用性能基准测试执行框架，支持MySQL、Redis、PostgreSQL、Nginx、Java、Go等应用的性能测试。

## 总体功能

提供基准测试执行框架，主要功能包括：

1. **测试配置** - 用户选择应用、测试类型、时长、负载
2. **测试执行** - 后台启动并运行基准测试
3. **测试监控** - 监控测试进程和系统指标
4. **结果解析** - 解析benchmark输出提取性能指标
5. **结果存储** - 保存测试结果到指定目录

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行

### 工具依赖

| 应用 | 工具 | 安装命令 |
|------|------|----------|
| MySQL | mysqlslap | apt-get install mysql-client |
| Redis | redis-benchmark | apt-get install redis-tools |
| PostgreSQL | pgbench | apt-get install postgresql-contrib |
| Nginx | ab/wrk/wrk2 | apt-get install apache2-utils |
| Java | JMeter/Gatling | 下载二进制 |
| Go | go test | 内置 |

## 用法

### 自然语言输入示例

```
对192.168.1.100的MySQL执行60秒基准测试
```

```
运行Redis的SET/GET性能测试，100万请求
```

```
使用wrk对Nginx进行压力测试，100并发60秒
```

### 执行流程

```
Phase 0: 配置
    ├→ 选择应用 (MySQL/Redis/PostgreSQL/Nginx/Java/Go)
    ├→ 选择测试类型 (内置/自定义/生产负载)
    ├→ 配置时长 (30s/60s/120s)
    └→ 配置负载 (低/中/高)

Phase 1: 启动测试
    └→ 后台启动 benchmark_command &

Phase 2: 监控
    └→ 监控进程状态、连接数、系统负载

Phase 3: 停止测试
    └→ 测试完成后自动停止或手动终止

Phase 4: 解析输出
    └→ 解析日志提取性能指标
```

### 输出示例

```markdown
## 基准测试报告

### 测试配置
- 应用: MySQL
- 工具: mysqlslap
- 时长: 60秒
- 负载: 50并发

### 性能指标

| 指标 | 值 | 单位 |
|------|-----|------|
| QPS | 2456.78 | queries/sec |
| 平均延迟 | 20.35 | ms |
| 最小延迟 | 0.05 | ms |
| 最大延迟 | 125.00 | ms |

### 测试日志
保存在: /opt/benchmark-results/20240115_143022/
```

## 支持的基准测试

| 应用 | 工具 | 关键指标 |
|------|------|----------|
| MySQL | mysqlslap | QPS, 延迟 |
| Redis | redis-benchmark | ops/sec, 命中率 |
| PostgreSQL | pgbench | TPS, 延迟 |
| Nginx | ab/wrk/wrk2 | req/sec, 延迟 |
| Java | JMeter/Gatling | req/sec, 响应时间 |
| Go | go test/pprof | ops/sec, 内存 |

## 关键输出件

| 输出件 | 路径 | 说明 |
|--------|------|------|
| 原始日志 | /opt/benchmark-results/.../benchmark_output.txt | 工具原始输出 |
| 解析指标 | /opt/benchmark-results/.../parsed_metrics.txt | 提取的性能指标 |
| 测试摘要 | /opt/benchmark-results/.../benchmark_summary.txt | 测试配置和结果摘要 |

## 参考文档

- [references/mysql.md](references/mysql.md) - MySQL测试详解
- [references/redis.md](references/redis.md) - Redis测试详解
- [references/postgres.md](references/postgres.md) - PostgreSQL测试详解
- [references/nginx.md](references/nginx.md) - Nginx测试详解
- [references/java.md](references/java.md) - Java测试详解
- [references/go.md](references/go.md) - Go测试详解
