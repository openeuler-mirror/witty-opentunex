# 调优场景映射参考

根据融合分析报告的调优方向描述，路由到对应的调优技能。每个调优技能是原子化的，数据来源是瓶颈分析结果。

**调优执行约束**：所有调优技能**禁止**直接在宿主机上或通过远程机器连接执行任何调优命令，必须依据 [中间态建议模板](../references/intermediate-report-template.md) 生成中间态调优建议，最终由调优域入口依据 [最终汇总报告模板](../references/tuning-report-template.md) 汇总为一份完整的调优建议报告。

远端场景：表中的 `${WORK_DIR}` 路径均为远端服务器路径，文件操作经 `opentunex-remote-execution` 在远端执行。详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`

## 映射表

| 调优方向描述 | 调优域分类 | 所需输入数据 | 调优内容 | 中间态建议输出路径 |
|------------|-----------|-------------|---------|------------------|
| numa并行感知调度特性优化 | 场景调优 | 瓶颈分析结果（NUMA相关） | 启用PARAL特性+设置sched_util_low_pct=100 | `${WORK_DIR}/tuning/intermediate/numa-sched-tuning.md` |
| 窃取任务调度特性优化 | 场景调优 | 瓶颈分析结果（窃取任务相关） | 启用STEAL特性 | `${WORK_DIR}/tuning/intermediate/stealtask-tuning.md` |
| Docker算力统筹优化 | 场景调优 | 瓶颈分析结果（Docker Coordination Burst相关） | 设置sched_soft_runtime_ratio+容器cpu.soft_quota=1 | `${WORK_DIR}/tuning/intermediate/docker-coordination-burst-tuning.md` |
| 分域调度soft_domain特性优化 | 场景调优 | 瓶颈分析结果（分域调度相关） | 由opentunex-scenario-tuning协调 | `${WORK_DIR}/tuning/intermediate/scenario-tuning.md` |
| 动态SMT调度特性优化 | 场景调优 | 瓶颈分析结果（SMT相关） | 由opentunex-scenario-tuning协调 | `${WORK_DIR}/tuning/intermediate/scenario-tuning.md` |
| 网卡多路径中断亲和优化 | 场景调优 | 瓶颈分析结果（网络中断相关） | 由opentunex-scenario-tuning协调 | `${WORK_DIR}/tuning/intermediate/scenario-tuning.md` |
| 推理核心绑核优化 | 场景调优 | 瓶颈分析结果（推理负载相关） | CPU亲和性与NUMA放置 | `${WORK_DIR}/tuning/intermediate/inference-core-binding-optimization.md` |
| OS内核CPU调度参数优化 | 通用调优 | 瓶颈分析结果（CPU相关） | CPU调度参数优化 | `${WORK_DIR}/tuning/intermediate/os-performance-optimization.md` |
| OS内存管理参数优化 | 通用调优 | 瓶颈分析结果（内存相关） | 内存管理参数优化 | `${WORK_DIR}/tuning/intermediate/os-performance-optimization.md` |
| OS磁盘IO调度参数优化 | 通用调优 | 瓶颈分析结果（IO相关） | 磁盘IO参数优化 | `${WORK_DIR}/tuning/intermediate/os-performance-optimization.md` |
| OS网络协议栈参数优化 | 通用调优 | 瓶颈分析结果（网络相关） | 网络栈参数优化 | `${WORK_DIR}/tuning/intermediate/os-performance-optimization.md` |
| 应用配置与运行参数优化 | 通用调优 | 瓶颈分析结果（应用相关） | 应用配置优化 | `${WORK_DIR}/tuning/intermediate/application-optimization.md` |

## 报告汇总

**各调优技能生成中间态建议，最终由调优域入口汇总为一份完整报告**：
- 最终汇总报告：`${WORK_DIR}/tuning/tuning-report.md`
- 压缩包：`${WORK_DIR}/tuning-package_<YYYYMMDD_HHMMSS>.tar.gz`

## 执行原则

- **按需生成**：仅根据融合报告明确指定的调优方向生成中间态建议，不做全量调度
- **按批次建议**：融合报告已包含冲突检测和执行顺序，按批次生成建议
- **数据前提**：所有调优技能依赖瓶颈分析结果数据，无数据时需先完成瓶颈分析
- **中间态输出**：各调优技能生成中间态调优建议，不直接输出最终报告
- **汇总报告**：调优域入口汇总所有中间态建议，生成一份完整的调优建议报告
- **用户确认**：调优建议报告中的命令需用户确认后再执行
- **数据保留**：按日期时间归档保留历史数据，便于后续追踪

## 冲突约束

| 调优方向A | 调优方向B | 冲突资源 | 执行策略 |
|----------|----------|---------|---------|
| numa并行感知调度特性优化 | OS内核CPU调度参数优化 | sched_util_low_pct | 串行：先numa并行感知调度，后OS调度参数 |
| 窃取任务调度特性优化 | numa并行感知调度特性优化 | sched_features | 串行：先numa并行感知调度，后窃取任务 |
