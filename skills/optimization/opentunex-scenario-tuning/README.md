# opentunex-scenario-tuning

场景化调优协调器。基于瓶颈分析层的融合报告，按需调度场景调优指南生成中间态建议，汇总为一份完整的调优建议报告。

## 总体功能

按需调度六个场景调优方向：

1. **Docker算力统筹调优** - 建议启用 sched_soft_runtime_ratio + cpu.soft_quota，让容器借用空闲CPU
2. **numa并行感知调度调优** - 建议启用 PARAL 特性，减少跨NUMA访问延迟（仅aarch64）
3. **窃取任务调度调优** - 建议启用 STEAL 特性，提升多核负载均衡效率（仅aarch64）
4. **分域调度调优** - 建议启用 SOFT_DOMAIN 特性，降低跨NUMA调度与访存抖动（仅aarch64）
5. **动态 SMT 调优** - 建议启用 KEEP_ON_CORE 特性，在低负载时智能分配计算资源
6. **网卡多路径调优** - 建议加载 oenetcls/venetcls 模块，减少跨NUMA网络中断开销

**Scope**: 纯协调器，不执行调优逻辑，不执行远程命令。所有调优命令需用户确认后执行。

## 前置依赖

### 必需依赖

- **瓶颈分析层** - 提供融合分析报告（`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`）
- Bash 环境

### 工具依赖（调优脚本按需使用）

- `docker` - Docker容器管理
- root 权限 - 内核参数修改

## 用法

### 自然语言输入示例

```
根据瓶颈分析结果，生成调优建议
```

```
容器CPU受限，帮我生成Docker burst调优建议
```

```
NUMA内存不均衡，需要调优建议
```

### 输出示例

```markdown
# 性能调优建议报告

## 1. 总结

| 瓶颈点 | 类别 | 严重程度 | 影响描述 | 调优手段 | 调优步骤 | 调优脚本 |
|--------|------|----------|----------|----------|----------|----------|
| NUMA内存不均衡 | 调度 | 高 | 跨NUMA访问延迟高 | 启用PARAL特性 | 1.启用PARAL 2.设置sched_util_low_pct=100 | ./numa-sched-tuning/tuning.sh |
| 容器CPU受限 | 容器 | 高 | 容器突发性能受限 | 启用burst | 1.设置ratio=20 2.启用soft_quota | ./docker-coordination-burst-tuning/tuning.sh |
```

## 目录结构

```
opentunex-scenario-tuning/
├── SKILL.md                                          # 协调器入口
├── DESIGN.md                                         # 设计文档
├── README.md                                         # 本文件
├── references/
│   ├── common-constraints.md                         # 共享约束
│   ├── constraints-tuning.md                         # 调优域约束
│   ├── contract-spec.md                              # 契约规范
│   ├── intermediate-report-template.md               # 中间态建议模板
│   ├── tuning-report-template.md                     # 最终汇总报告模板
│   ├── SKILL_MAPPING.md                              # 调优场景映射参考
│   ├── docker-coordination-burst-tuning/
│   │   └── tuning-guide.md                           # Docker burst 调优指南
│   ├── dynamic-smt-tuning/
│   │   └── tuning-guide.md                           # 动态 SMT 调优指南
│   ├── multi-net-path-tuning/
│   │   └── tuning-guide.md                           # 网卡多路径调优指南
│   ├── numa-sched-tuning/
│   │   └── tuning-guide.md                           # numa并行感知调度调优指南
│   ├── soft-domain-tuning/
│   │   └── tuning-guide.md                           # 分域调度调优指南
│   └── stealtask-tuning/
│       └── tuning-guide.md                           # 窃取任务调优指南
└── scripts/
    ├── docker-coordination-burst-tuning/
    │   └── docker_coordination_burst.sh              # Docker burst 调优脚本
    ├── dynamic-smt-tuning/
    │   └── dynamic_smt_tune.sh                       # 动态 SMT 调优脚本
    ├── multi-net-path-tuning/
    │   └── multi_net_path_tune.sh                    # 网卡多路径调优脚本
    ├── numa-sched-tuning/
    │   └── numa_sched_tune.sh                        # NUMA 调度调优脚本
    ├── soft-domain-tuning/
    │   └── soft_domain_tune.sh                       # 分域调度调优脚本
    └── stealtask-tuning/
        └── stealtask_tune.sh                         # 窃取任务调优脚本
```