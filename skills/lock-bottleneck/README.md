# lock-bottleneck

OS级别锁瓶颈分析Skill，分析futex争用、spinlock、阻塞行为。

## 总体功能

分析OS级别锁性能瓶颈：

1. **环境准备** - perf配置、kernel支持
2. **数据收集** - perf record/lock_stat
3. **锁分析** - futex争用、锁等待
4. **进程关联** - 关联到具体进程

**Scope**: 仅分析OS内核锁，不包含应用锁

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接

### 工具依赖

- `perf` (linux-tools-common)
- kernel >= 2.6.25

## 用法

### 自然语言输入示例

```
分析192.168.1.100的锁瓶颈
```

```
系统调度延迟，帮我看看是否锁问题
```

### 输出示例

```markdown
## 锁瓶颈分析报告

### 环境信息
- Kernel: 5.4.0
- perf_event_paranoid: 2
- lock_stat: enabled

### 瓶颈识别

| 进程 | 锁类型 | 争用程度 |
|------|--------|----------|
| mysqld | futex | 高 |
| redis-server | futex | 中 |

### 优化建议
1. 减少进程内锁争用
2. 调整调度器参数
3. 考虑无锁数据结构
```
