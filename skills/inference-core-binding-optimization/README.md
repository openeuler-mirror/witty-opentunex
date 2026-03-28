# inference-core-binding-optimization

推理负载优化Skill，针对NPU/vLLM-Ascend等推理场景进行CPU亲和性和NUMA优化。

## 总体功能

优化推理负载的CPU亲和性：

1. **关键进程发现** - 识别推理进程和线程
2. **系统信息收集** - NPU/CPU拓扑
3. **瓶颈分析** - 拓扑分布问题
4. **亲和性策略** - 生成绑定命令
5. **实施验证** - 应用并测试

**Scope**: 专用于推理场景的CPU绑定

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接
- **top-down-bottleneck skill** - 基础分析

### 工具依赖

- `numactl`, `taskset`, `perf`

## 用法

### 自然语言输入示例

```
优化192.168.1.100上vLLM推理的CPU亲和性
```

```
NPU推理延迟抖动，帮我看看CPU绑定
```

### 输出示例

```markdown
## 推理优化报告

### 关键进程

| PID/TID | 名称 | 角色 | 核心函数 |
|---------|------|------|----------|
| 1234 | python | 主进程 | vllm.run |
| 5678 | python | Worker | forward |
| 5679 | python | Worker | prefill |

### 瓶颈分析

| 进程 | 瓶颈 | 证据 |
|------|------|------|
| 5678 | 跨NUMA访问 | node1进程访问node0内存 |

### 亲和性策略

```bash
# 建议绑定
taskset -cp 0-7 5678  # 绑定到node0
```

### 优化后测试
- 延迟抖动: 15ms → 5ms
```
