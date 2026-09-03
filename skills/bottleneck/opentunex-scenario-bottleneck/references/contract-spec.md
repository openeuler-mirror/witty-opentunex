# 场景化分析契约文件规范 v1.0

## 概述

契约文件是**协调器**（`opentunex-scenario-bottleneck`）与各**分析子技能**之间的标准化通信协议，替代上下文传递。每个分析子技能将执行结果写入契约文件，协调器读取契约文件获取结果。

> **本规范的执行约束**：所有分析子技能均按约束文件 [constraints-bottleneck.md](constraints-bottleneck.md) 中的 **B-08「子技能严格串行调用」** 串行调用。协调器**不**通过子智能体工具并发启动子技能，**不**一次性加载多个子技能后批量操作，每次只加载并执行一个子技能。

## 文件格式

契约文件使用 YAML 格式，存放路径：`${WORK_DIR}/<domain>/contracts/<skill_name>.yaml`

> **路径适配**：`WORK_DIR` 默认值为 `/srv/opentunex/<YYYYMMDD_HHMMSS>`，用户可通过一键采集脚本或手动指定覆盖。下文所有路径中的 `${WORK_DIR}/` 均指工作目录根路径。

> **远端场景语义**：当目标为远端服务器时（`target_host` 已填写），`${WORK_DIR}` 是远端服务器上的路径，agent 主机本地不存在该目录。所有对 `${WORK_DIR}` 的文件操作（mkdir/ls/cat/写契约/写报告/打包）必须经 `opentunex-remote-execution` 的 ssh 机制在远端执行：数据文件**直接在远端机器读取**（远端 cat/grep 流回上下文，禁止拷贝到本地后读取）；契约/报告等文件**直接在远端机器产出**（经 ssh 在远端落盘，禁止在 agent 本地生成后 scp 上传）；禁止在 agent 本地操作 `${WORK_DIR}`。详见 `opentunex-remote-execution/references/work_dir_remote_semantics.md`。契约建议携带 `execution_context` 字段（`execution_mode` / `user` / `ip`）供下游技能判定模式。
>
> **预采集数据目录**：当用户提供了已有采集数据目录时，通过 `DATA_DIR` 字段传入该路径，分析结果和调优产出仍写入 `${WORK_DIR}/` 下。这种情况下不需要再进行采集，直接进行瓶颈分析和调优。

## 输入契约（协调器 → 分析子技能）

协调器在调用分析子技能前，将输入参数写入契约文件：

```yaml
contract_type: "input"
skill_name: "<skill-name>"
timestamp: "<YYYYMMDD_HHMMSS>"

input:
  batch_dir: "<批次目录路径>"
  target_host: "<目标主机IP>"
  data_dir: "<数据源目录路径>"
  fusion_report: "<融合报告路径>"
  extra_params: {}

constraints_file: "<约束文件路径>"
constraints_version: "<约束文件版本号>"
```

### 标准输入字段

| 字段 | 必需 | 说明 |
|------|------|------|
| batch_dir | 是 | 批次根目录路径 |
| target_host | 否 | 目标主机IP（远程执行场景） |
| data_dir | 否 | 数据源目录路径（分析/调优场景） |
| fusion_report | 否 | 融合报告路径（调优场景） |
| extra_params | 否 | 扩展字段，各子技能可自定义 |

### 扩展字段机制

子技能可在 `extra_params` 下增加域特有字段，例如：

```yaml
input:
  batch_dir: "${WORK_DIR}/20260521_143022"
  target_host: "192.168.1.100"
  extra_params:
    collect_dir: "cpu-collection_collect"
    vmstat_duration: 5
```

## 输出契约（分析子技能 → 协调器）

分析子技能执行完成后，将结果写入契约文件：

```yaml
contract_type: "output"
skill_name: "<skill-name>"
timestamp: "<YYYYMMDD_HHMMSS>"
status: "success|partial|failed"

output:
  report_path: "<报告文件路径>"
  contract_path: "<契约文件自身路径>"
  summary: {}
  errors: []

constraints_acknowledged:
  - "<约束编号>: <约束描述>"
constraints_version: "<约束文件版本号>"
```

### status

| 值 | 含义 |
|---|------|
| success | 全部步骤执行成功 |
| partial | 部分步骤成功，部分降级或跳过 |
| failed | 执行失败，无法产出有效结果 |

### constraints_acknowledged

分析子技能**必须**列出已遵守的所有约束编号及版本号。协调器在读取输出契约时校验此字段，缺失约束确认时拒绝接受结果。

校验规则：
1. 输出契约中的 `constraints_acknowledged` 列表不得为空
2. 列表内容必须与约束文件中定义的约束编号一一对应
3. `constraints_version` 必须与输入契约中的版本号一致

## 契约文件路径约定

| 域 | 路径模板 |
|----|---------|
| 数据采集域 | `${WORK_DIR}/collect/contracts/<skill_name>-input.yaml` / `<skill_name>-output.yaml` |
| 瓶颈分析域 | `${WORK_DIR}/analysis/contracts/<skill_name>-input.yaml` / `<skill_name>-output.yaml` |
| 调优域 | `${WORK_DIR}/tuning/contracts/<skill_name>-input.yaml` / `<skill_name>-output.yaml` |

> **目录说明**：`${WORK_DIR}` 本身已包含时间戳（如 `/srv/opentunex/20260527_143052/`），本次所有采集、分析、调优操作均在此目录内完成，各域直接读写其子目录，无需 `latest` 符号链接。

## 分析子技能串行调用协议

### 串行调用模板

协调器**按调度声明表格的顺序**，每轮只加载一个分析子技能并执行完整流程：

```
调用分析子技能 [skill_name]：
- 加载技能定义：[skill_path]/SKILL.md（仅加载当前这一项，不与其他子技能并发或批量加载）
- 读取输入契约：[contract_input_path]
- 读取约束文件：[constraints_path]
- 执行技能定义中的步骤
- 写入输出契约：[contract_output_path]
- 写入报告：[report_path]
- 落盘完成后，再开始加载并调用下一个分析子技能
```

### 串行调用强制规则（与 constraints-bottleneck.md 中 B-08 一致）

1. **一次只加载一个子技能**：当前轮只读取一个子技能 SKILL.md 并执行其完整流程，禁止一次性读取多个子技能 SKILL.md
2. **完成后再加载下一个**：当前子技能的全部产出（输入/输出契约 + 分析报告）写入磁盘后，才能开始读取下一个子技能 SKILL.md
3. **禁止子智能体并发调度**：禁止通过 Task Tool / Agent Tool / sessions_spawn 等任何子智能体工具同时启动多个子技能
4. **禁止协调器内联执行**：禁止在协调器上下文中读取子技能 SKILL.md 后直接执行其分析逻辑
5. **禁止批量加载**：禁止将多个子技能 SKILL.md 一次性加载到当前上下文后做任何形式的批量操作

### 跨平台适配原则

本技能体系采用**声明式调度**：SKILL.md 定义 WHAT（调度哪些子技能、传什么参数、期望什么输出），运行时环境根据自身可用的工具决定 HOW（具体调用格式）。**该 HOW 仅适用于调度当前一个子技能，不用于并发批量调度。**

**调度声明要素**（每个 SKILL.md 中定义）：
1. **子技能列表**：需要调用哪些分析子技能
2. **技能名称**：子技能调用的 SKILL
3. **输入契约路径**：传入子技能的输入数据位置
4. **约束文件路径**：子技能必须遵守的约束文件
5. **输出契约路径**：子技能执行结果的输出位置
6. **任务描述**：传入子技能的执行指令

**运行时适配**（按表格顺序串行使用，每次只调度一个）：

| 可用工具 | 单次调用方式 | 等待方式 |
|---------|---------|---------|
| Skill 工具 | `Skill(skill="<skill-name>", args=...)` | 等待当前子技能全部产出落盘后，再调用下一个 |
| 读取并内联执行（受限场景） | 读取 SKILL.md 后按其步骤执行 | 当前子技能产出落盘后，再读取下一个 SKILL.md |

> **关于"读取并内联执行"**：仅作为 Skill 工具不可用时的兜底，**禁止**由此扩展为并发调度或批量加载；任何时候都只读一个、执行一个、产出落盘后再读下一个。

### 子技能任务描述模板

> 读取技能定义 \[技能名称]，读取输入契约 \[输入契约路径]，读取约束文件 \[约束文件路径]，执行技能定义中的步骤，写入输出契约 \[输出契约路径]，写入分析报告 \[分析报告路径]。**执行上下文**：execution_mode=remote（或 local）；远端模式时 ${user}@${ip} 为远端连接信息，${WORK_DIR} 为远端路径，所有对 ${WORK_DIR} 的读写经 opentunex-remote-execution 在远端执行（见 references/work_dir_remote_semantics.md），禁止在 agent 本地操作 ${WORK_DIR}。

## 嵌套深度限制

最大嵌套深度为 2 级：入口 → 一级分析子技能 → 二级分析子技能。

二级分析子技能的契约由一级分析子技能管理：
- 一级分析子技能创建二级契约目录
- 二级分析子技能将输出写入一级分析子技能指定的路径
- 一级分析子技能汇总二级结果后，写入自身的输出契约

> **嵌套场景下的串行要求**：即使在一级分析子技能内部需要调用二级分析子技能，也必须严格串行——一次一个、产出落盘后再调用下一个，禁止并发调度或批量加载。

## 子技能超时机制

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 子技能超时 | 300 秒 | 单个分析子技能的最大执行时间 |
| 重试次数 | 1 次 | 超时或失败后的最大重试次数 |
| 重试间隔 | 10 秒 | 重试前的等待时间 |
| 全局失败阈值 | 50% | 超过此比例的子技能失败时中止整个流程 |

超时处理流程：
1. 分析子技能超过 300 秒未完成 → 标记为 timed_out
2. 自动重试 1 次（间隔 10 秒）
3. 重试仍失败 → 标记为 failed，在输出契约中记录错误信息
4. 累计失败率 > 50% → 中止流程，通知用户

## 三级加载系统

技能采用三级渐进式加载：

| 级别 | 内容 | 加载时机 | 大小建议 |
|------|------|---------|---------|
| L1 - 元数据 | frontmatter（name, description） | 始终在上下文中 | <100 词 |
| L2 - 主体 | SKILL.md 正文（调度逻辑、执行步骤） | 当前轮被串行调用时一次性加载 | <500 行 |
| L3 - 参考资源 | references/ 目录下的文件 | 按需加载 | 单文件 <200 行 |

> **L2 的加载时机**：仅在当前轮到该子技能时一次性加载其 SKILL.md 主体，**禁止**预先把多个子技能的 SKILL.md 同时加载到上下文（详见 B-08）。