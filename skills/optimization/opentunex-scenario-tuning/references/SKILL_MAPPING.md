# 调优场景映射参考

根据融合分析报告的调优方向描述，路由到对应的调优子技能。每个调优子技能是原子化的，数据来源是瓶颈分析结果。

所有子技能遵守 [场景调优子技能共享约束](common-constraints.md)，依据 [中间态建议模板](intermediate-report-template.md) 生成中间态建议，最终由协调器依据 [最终汇总报告模板](tuning-report-template.md) 汇总为完整报告。

远端场景：表中的 `${WORK_DIR}` 路径均为远端服务器路径，文件操作经 `opentunex-remote-execution` 在远端执行。详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`

## 映射表

| 调优方向描述 | 子技能 | 技能目录 | 中间态输出 |
|------------|--------|---------|-----------|
| numa并行感知调度特性优化 | opentunex-numa-sched-tuning | `opentunex-numa-sched-tuning/` | `numa-sched-tuning.md` |
| 窃取任务调度特性优化 | opentunex-stealtask-tuning | `opentunex-stealtask-tuning/` | `stealtask-tuning.md` |
| Docker算力统筹优化 | opentunex-docker-coordination-burst-tuning | `opentunex-docker-coordination-burst-tuning/` | `docker-coordination-burst-tuning.md` |
| 分域调度特性优化 | opentunex-soft-domain-tuning | `opentunex-soft-domain-tuning/` | `soft-domain-tuning.md` |
| 网卡多路径调优 | opentunex-multi-net-path-tuning | `opentunex-multi-net-path-tuning/` | `multi-net-path-tuning.md` |
| 动态 SMT 调优 | opentunex-dynamic-smt-tuning | `opentunex-dynamic-smt-tuning/` | `dynamic-smt-tuning.md` |
| BTB/TidCMP BIOS 调优 | opentunex-btb-tuning | `opentunex-btb-tuning/` | `btb-tuning.md` |
| copy_from_user 内核补丁调优 | opentunex-copy-user-tuning | `opentunex-copy-user-tuning/` | `copy-user-tuning.md` |
| hisock 网络加速调优 | opentunex-hisock-tuning | `opentunex-hisock-tuning/` | `hisock-tuning.md` |

## 报告汇总

- 最终汇总报告：`${WORK_DIR}/tuning/tuning-report.md`
- 调优脚本：`${WORK_DIR}/tuning/<调优技能名称>/`

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
| BTB/TidCMP BIOS 调优 | copy_from_user 内核补丁 | 服务器重启窗口 | 串行：BTB 涉及 BIOS 修改 + 重启，copy_user 涉及内核重编 + 重启，错开执行窗口 |
| BTB/TidCMP BIOS 调优 | hisock 网络加速 | 无直接冲突 | 可并行 |
| copy_from_user 内核补丁 | hisock 网络加速 | 内核重编 | 串行：先 copy_user 重编内核并重启，再 hisock 加载（hisock 依赖新版内核 CONFIG_HISOCK） |
| BTB/TidCMP BIOS 调优 | NUMA调度并行特性优化 | 无冲突 | 可并行 |
| BTB/TidCMP BIOS 调优 | 窃取任务调度特性优化 | 无冲突 | 可并行 |
| copy_from_user 内核补丁 | NUMA调度并行特性优化 | 无冲突 | 可并行 |
| copy_from_user 内核补丁 | 窃取任务调度特性优化 | 无冲突 | 可并行 |
| hisock 网络加速 | 网卡多路径调优 | 不同层级加速 | 无冲突，可并行 |
| hisock 网络加速 | iptables/nftables 规则 | netfilter | hisock 加速流量绕过 L2/L3 netfilter；非加速流量仍受 iptables 控制 |