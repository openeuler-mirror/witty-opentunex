# opentunex-scenario-tuning

场景化调优协调器。基于瓶颈分析层的融合报告，按需调度场景调优技能生成中间态建议，汇总为一份完整的调优建议报告。

## 总体功能

按需调度 6 个场景调优子技能：

1. **Docker算力统筹调优** - 建议启用 sched_soft_runtime_ratio + cpu.soft_quota，让容器借用空闲CPU
2. **numa并行感知调度调优** - 建议启用 PARAL 特性，减少跨NUMA访问延迟（仅aarch64）
3. **窃取任务调度调优** - 建议启用 STEAL 特性，提升多核负载均衡效率（仅aarch64）
4. **分域调度调优** - 建议启用 SOFT_DOMAIN 特性，优化跨NUMA漫游与软调度域（仅aarch64）
5. **动态 SMT 调优** - 建议启用 KEEP_ON_CORE 特性，优化低负载下超线程调度
6. **网卡多路径调优** - 建议启用 oenetcls/venetcls + ntuple，优化跨NUMA中断亲和

**Scope**: 纯协调器，不执行调优逻辑。所有调优命令需用户确认后执行（T-01/T-02）。远端场景（用户输入含 IP）时 `${WORK_DIR}` 为远端服务器路径：本协调器对 `${WORK_DIR}` 的文件操作（mkdir/读报告/写契约/写报告/部署脚本）经 `opentunex-remote-execution` 的 ssh 机制在远端执行，详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。

## 前置依赖

### 必需依赖

- **瓶颈分析层** - 提供融合分析报告（`${WORK_DIR}/analysis/opentunex-scenario-bottleneck_collect/result.md`）
- Bash 环境

### 工具依赖（子技能按需使用）

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
| NUMA内存不均衡 | 调度 | 高 | 跨NUMA访问延迟高 | 启用PARAL特性 | 1.启用PARAL 2.设置sched_util_low_pct=100 | ./opentunex-numa-sched-tuning/tuning.sh |
| 容器CPU受限 | 容器 | 高 | 容器突发性能受限 | 启用burst | 1.设置ratio=20 2.启用soft_quota | ./opentunex-docker-coordination-burst-tuning/tuning.sh |
```

## 目录结构

```
opentunex-scenario-tuning/
├── SKILL.md                                          # 协调器入口
├── DESIGN.md                                         # 设计文档
├── README.md                                         # 本文件
├── references/
│   ├── common-constraints.md                         # 共享约束
│   ├── intermediate-report-template.md               # 中间态建议模板
│   ├── tuning-report-template.md                     # 最终汇总报告模板
│   └── SKILL_MAPPING.md                              # 调优场景映射参考
├── opentunex-docker-coordination-burst-tuning/
│   ├── SKILL.md                                      # Docker burst 调优
│   └── scripts/
│       └── docker_coordination_burst.sh              # 调优脚本
├── opentunex-dynamic-smt-tuning/
│   ├── SKILL.md                                      # 动态 SMT 调优
│   └── scripts/
│       └── dynamic_smt_tune.sh                       # 调优脚本
├── opentunex-multi-net-path-tuning/
│   ├── SKILL.md                                      # 网卡多路径调优
│   └── scripts/
│       └── multi_net_path_tune.sh                    # 调优脚本
├── opentunex-numa-sched-tuning/
│   ├── SKILL.md                                      # numa并行感知调度调优
│   └── scripts/
│       └── numa_sched_tune.sh                        # 调优脚本
├── opentunex-soft-domain-tuning/
│   ├── SKILL.md                                      # 分域调度调优
│   └── scripts/
│       └── soft_domain_tune.sh                       # 调优脚本
└── opentunex-stealtask-tuning/
    ├── SKILL.md                                      # 窃取任务调优
    └── scripts/
        └── stealtask_tune.sh                         # 调优脚本
```