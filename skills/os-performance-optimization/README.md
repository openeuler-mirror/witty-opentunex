# os-performance-optimization

OS级别性能优化分析Skill，基于top-down瓶颈分析方法识别系统性能问题并提出优化策略建议。

## 总体功能

执行OS级别性能分析和优化推荐，主要功能包括：

1. **瓶颈分析** - 调用top-down-bottleneck skill识别系统级性能问题
2. **优化推荐** - 基于识别出的瓶颈提出具体的OS级别优化策略
3. **环境检查** - 验证内核特性、硬件能力、当前配置状态
4. **优化过滤** - 过滤掉不支持、已启用、不适用的优化项

**Scope**: 仅分析OS级别组件，不包含应用层组件(MySQL, Redis等)

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行
- **top-down-bottleneck skill** - 系统级瓶颈分析

### 系统要求

- Linux内核 >= 3.10
- SSH访问权限
- root或sudo权限（部分优化需要）

### 工具依赖

- `sysctl`, `vmstat`, `iostat`, `mpstat`, `lscpu`, `numactl`
- `perf` (用于性能数据收集)
- `sysbench`, `fio`, `iperf3` (用于基准测试)

## 用法

### 自然语言输入示例

```
分析192.168.1.100的OS级别性能瓶颈并给出优化建议
```

```
对服务器进行OS性能分析，识别CPU、内存、IO、网络方面的瓶颈
```

### 执行流程

1. **Phase 1: 瓶颈分析**
   - 加载top-down-bottleneck skill执行系统级分析

2. **Phase 2: 优化推荐**
   - 执行环境检查
   - 过滤优化项
   - 生成推荐报告

3. **Phase 3: 执行确认**
   - 询问用户是否执行优化使能

### 输出示例

```markdown
## 优化推荐报告

### 系统环境
- Kernel: 5.4.0-generic
- CPU: 16 cores (2 sockets)
- Memory: 64GB
- Disk: SSD (NVMe)

### 瓶颈汇总
| 类别 | 瓶颈 | 严重程度 |
|------|------|----------|
| CPU | Context Switch过高 | High |
| Memory | Swappiness过高 | Medium |
| IO | SSD调度器优化 | Low |

### 推荐优化项

#### OPT-001: 降低vm.swappiness
- **当前值**: 60
- **推荐值**: 10
- **风险**: Low
- **影响**: 减少15% IO等待

#### OPT-002: 更改I/O调度器为mq-deadline
- **当前值**: deadline
- **推荐值**: mq-deadline
- **风险**: Medium
- **影响**: 增加25%随机读写

---

是否执行优化使能?
1. 执行优化使能 (加载os-optimization-enablement skill)
2. 跳过
3. 修改优化列表
```

## 关键输出件

| 输出件 | 路径/位置 | 说明 |
|--------|-----------|------|
| 瓶颈分析报告 | Skill输出 | Phase 1结果，包含瓶颈列表和证据 |
| 优化推荐报告 | Skill输出 | Phase 2结果，包含优化项详情 |
| 优化确认决策 | 用户输入 | 用户选择是否执行优化 |
| 系统环境清单 | Skill输出 | 检查结果汇总 |

## 参考文档

- [references/optimizations/cpu.md](references/optimizations/cpu.md) - CPU优化策略
- [references/optimizations/memory.md](references/optimizations/memory.md) - 内存优化策略
- [references/optimizations/disk.md](references/optimizations/disk.md) - 磁盘/IO优化策略
- [references/optimizations/network.md](references/optimizations/network.md) - 网络优化策略

## 相关Skill

- **os-optimization-enablement** - 执行实际的优化使能操作
- **top-down-bottleneck** - 系统级瓶颈分析（前置依赖）
- **application-optimization** - 应用级性能优化
