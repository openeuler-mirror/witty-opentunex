# 调优场景映射参考

根据融合分析报告的调优方向描述，路由到对应的调优参考指南。每个调优指南是原子化的，数据来源是瓶颈分析结果。

所有调优指南遵守 [场景调优子技能共享约束](common-constraints.md)，依据 [中间态建议模板](intermediate-report-template.md) 生成中间态建议，最终由协调器依据 [最终汇总报告模板](tuning-report-template.md) 汇总为完整报告。

## 映射表

| 调优方向描述 | 调优指南 | 指南路径 | 中间态输出 |
|------------|---------|---------|-----------|
| numa并行感知调度特性优化 | numa-sched-tuning | `references/numa-sched-tuning/tuning-guide.md` | `numa-sched-tuning.md` |
| 窃取任务调度特性优化 | stealtask-tuning | `references/stealtask-tuning/tuning-guide.md` | `stealtask-tuning.md` |
| Docker算力统筹优化 | docker-coordination-burst-tuning | `references/docker-coordination-burst-tuning/tuning-guide.md` | `docker-coordination-burst-tuning.md` |
| 分域调度特性优化 | soft-domain-tuning | `references/soft-domain-tuning/tuning-guide.md` | `soft-domain-tuning.md` |
| 网卡多路径调优 | multi-net-path-tuning | `references/multi-net-path-tuning/tuning-guide.md` | `multi-net-path-tuning.md` |
| 动态 SMT 调优 | dynamic-smt-tuning | `references/dynamic-smt-tuning/tuning-guide.md` | `dynamic-smt-tuning.md` |

## 报告汇总

- 最终汇总报告：`${WORK_DIR}/tuning/tuning-report.md`
- 压缩包：`${WORK_DIR}/tuning-package_<YYYYMMDD_HHMMSS>.tar.gz`

## 冲突约束

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|---------|
| NUMA调度并行特性优化 | 窃取任务调度特性优化 | sched_features | 串行：先NUMA调度并行，后窃取任务 |
| Docker算力统筹优化 | NUMA调度并行特性优化 | 无直接冲突 | 可并行 |
| 分域调度特性优化 | NUMA调度并行特性优化 | 无直接冲突 | 可并行 |
| 分域调度特性优化 | 窃取任务调度特性优化 | 无直接冲突 | 可并行 |
| 分域调度特性优化 | OS内核网络参数优化 | rps_sock_flow_entries | 串行：先分域调度，后OS网络参数 |
| 动态 SMT 调优 | 窃取任务调度特性优化 | sched_features | 串行：先窃取任务，后动态SMT |
| 动态 SMT 调优 | NUMA调度并行特性优化 | sched_features | 串行：先NUMA调度并行，后动态SMT |
| 动态 SMT 调优 | 分域调度特性优化 | 无直接冲突 | 可并行 |