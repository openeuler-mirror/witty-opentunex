# 场景调优子技能共享约束

所有 `opentunex-scenario-tuning` 下的子技能必须遵守以下共享约束。

## ST-01 执行约束

> **⚠️ 每次触发本技能都必须重新从头执行完整调优流程，不得引用历史数据或之前的回答。**
> - 即使系统状态未变化，也必须重新执行所有调优步骤
> - 不得跳过任何调优阶段，不得复用历史调优结果
> - 每次执行都必须将完整的调优过程数据落入 `${WORK_DIR}/tuning/intermediate/` 与 `${WORK_DIR}/tuning/<skill_name>/`（覆盖式或按需新建子目录，由调用方约定）
> - 这是强制性要求，无例外情况

## ST-02 调优执行约束

> **⚠️ 以下约束是强制性的，任何调优技能不得违反。违反将导致系统被意外修改，产生不可逆的风险。**

### 禁止项清单

| 编号 | 禁止项 | 说明 |
|------|--------|------|
| T-01 | **禁止直接执行调优命令** | 不允许在宿主机上或通过远程机器连接执行任何调优命令（sysctl、写入内核调试接口、修改配置文件、重启服务等） |
| T-02 | **禁止SSH远程执行** | 不允许通过SSH连接远程机器执行调优命令 |
| T-03 | **禁止自动修改系统参数** | 不允许自动执行修改系统参数的命令 |
| T-04 | **禁止自动重启服务** | 不允许自动重启服务或应用 |
| T-05 | **禁止自动修改配置文件** | 不允许自动修改应用或系统配置文件 |
| T-06 | **禁止跳过步骤0** | 必须先创建调优报告目录，才能执行后续步骤 |

- 远端场景（目标为远端服务器）时，`${WORK_DIR}` 为远端路径：调优域对 `${WORK_DIR}` 的文件操作（读融合报告、写契约、写中间态建议、部署调优脚本）须经 `opentunex-remote-execution` 的 ssh 机制在远端执行；调优脚本部署到远端后仍由**用户确认后在远端服务器上执行**（T-01/T-02 不变，agent 不代执行）。详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`

### 正确职责

**调优技能的正确职责**：依据瓶颈分析结果 → 生成中间态调优建议 → 由调优域入口汇总为一份完整报告 → **由用户确认后再执行**

### 违规后果

如果违反以上约束：
- 系统可能被意外修改，产生不可逆的风险
- 用户无法审查和确认调优操作
- 违反"调优建议报告"的设计初衷

## ST-03 数据目录约束

> **⚠️ 所有调优产出必须落入用户指定的工作目录 `WORK_DIR` 内，读取分析域数据，不得硬编码时间戳路径。**

| 路径 | 用途 |
|------|------|
| `${WORK_DIR}/analysis/` | 读取分析结论的 `result.md` |
| `${WORK_DIR}/tuning/<skill_name>/` | 场景调优技能写入中间态建议、脚本 |
| `${WORK_DIR}/tuning/tuning-report.md` | 最终调优报告 |

远端场景：产出文件经 scp 上传（或远端命令）写入远端 `${WORK_DIR}`，禁止在 agent 本地创建 `${WORK_DIR}`。

- **数据缺失处理**：如果 `${WORK_DIR}/analysis/` 目录不存在或未找到相关分析结果数据，必须明确提醒用户：**需要先完成瓶颈分析后才能生成调优建议**，不可在无分析数据的情况下直接调优

## ST-04 中间态建议模板

所有子技能必须依据 [中间态建议模板](intermediate-report-template.md) 生成结构化的中间态调优建议。

## ST-05 调优方向过滤约束

> **⚠️ 最终报告中仅体现场景分析结论为"适用"或"建议启用"的调优方向。"收益有限"方向可作为备选方案生成。**

- **适用结论**：场景分析结论为"适用"、"建议启用" → 正常进入调优流程，生成调优建议并写入最终报告（`primary_plan`）
- **收益有限结论**：场景分析结论为"收益有限" → 可生成调优建议，但标记为 `extended_plan`（备选方案），在最终报告中以备选形式列出。生成调优脚本但不要求必须执行
- **不适用结论**：场景分析结论为"不适用"、"不支持"、"环境不支持"、"不需要"、"无需额外操作"、"已启用" → **不得进入调优流程，不得生成中间态建议，不得出现在最终 `tuning-report.md` 中**
- **脚本生成**：仅为"适用"和"收益有限"的调优方向生成调优脚本。收益有限方向的脚本可附带"备选"标记，不适用方向不生成脚本

## 子技能名称与目录映射

| 子技能 | 目录名 | 中间态输出 |
|--------|--------|-----------|
| Docker算力统筹调优 | `opentunex-docker-coordination-burst-tuning` | `docker-coordination-burst-tuning.md` |
| numa并行感知调度调优 | `opentunex-numa-sched-tuning` | `numa-sched-tuning.md` |
| 窃取任务调度调优 | `opentunex-stealtask-tuning` | `stealtask-tuning.md` |
| 网卡多路径调优 | `opentunex-multi-net-path-tuning` | `multi-net-path-tuning.md` |
| 分域调度调优 | `opentunex-soft-domain-tuning` | `soft-domain-tuning.md` |
| 动态 SMT 调优 | `opentunex-dynamic-smt-tuning` | `dynamic-smt-tuning.md` |
| BTB/TidCMP BIOS 调优 | `opentunex-btb-tuning` | `btb-tuning.md` |
| copy_from_user 内核补丁调优 | `opentunex-copy-user-tuning` | `copy-user-tuning.md` |
| hisock 网络加速调优 | `opentunex-hisock-tuning` | `hisock-tuning.md` |