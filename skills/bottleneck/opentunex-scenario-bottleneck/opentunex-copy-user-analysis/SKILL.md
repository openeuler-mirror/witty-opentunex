---
name: "opentunex-copy-user-analysis"
description: "copy_from_user 拷贝优化适用性分析。检查 ARM64 CPU partID、火焰图中 __arch_copy_to_user/__arch_copy_from_user 热点、大块读写 size (>4KB) 等条件，评估应用 Hisilicon 优化补丁（ldp/ldtp 双字加载）的适用性。触发:copy_to_user、copy_from_user、__arch_copy、用户态拷贝、数据拷贝热路径、大块 IO、rocksdb、ldp、ldtp、LSUI。"
---

# copy_from_user 拷贝优化适用性分析

分析 CPU 架构、热点函数和大块读写 size，评估应用 Hisilicon `copy_from_user` 优化补丁的适用性。

**分析原理**：在大规模数据拷贝场景（网络收发包、文件 I/O）中，`copy_from_user` 是内核关键热路径。当前内核使用 `ldtr` 单寄存器指令逐字节或逐双字搬运，在 Hisilicon ARM64 CPU 上无法充分利用加载指令带宽。应用优化补丁（PR #22481）后：
- Hisilicon CPU（LINXICORE9100、HIP11、HIP12，partID > 0xd02）：大拷贝（>=4KB）切换到 `ldp` 双字加载
- 支持 FEAT_LSUI 的 CPU（ARMv8.9）：直接使用 `ldtp` 非特权双字加载，size 不再受限

> **⚠️ 本调优方向需要更新内核补丁后生效，不支持一键使能。**

## 强制约束

> 本技能遵守 [场景分析子技能共享约束](../references/common-constraints.md) 中定义的所有执行约束和数据目录约定。
>
> 本技能的数据目录名为 `opentunex-copy-user-analysis_collect`。

---

## 输入约定

本技能的数据来源支持两种模式：
- **预采集模式**：协调器传入 `${DATA_DIR}` 变量，指向用户已采集的数据目录
- **按需采集模式**：协调器在调度本技能前已完成数据采集，数据位于 `${DATA_DIR}` 或 `${WORK_DIR}/`

本技能**禁止自行采集数据**，数据缺失时在结果中标注 `DATA_MISSING`，由协调器决定是否触发补充采集。

### 执行模式与 `${WORK_DIR}` 语义（核心）

- 输入契约携带 `execution_context`（`execution_mode` / `user` / `ip`）。**远端模式**（execution_mode=remote）：`${WORK_DIR}` 与 `${DATA_DIR}` 都是**远端服务器上**的路径：
  - `scripts/preanalysis.sh` 远端执行**必须加载并遵循 `opentunex-remote-execution` skill 的执行方式**（`ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-copy-user-analysis/"` → scp 上传脚本到远端 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-copy-user-analysis/` → 远端执行`ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-copy-user-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-copy-user-analysis_collect"`；session 超时按该 skill 扩展为 1200 秒；**禁止**读取脚本内容后自行合成命令代替执行。**禁止**在 agent 本地执行该脚本或读写本地 `${DATA_DIR}` 路径
  - 读取 `${DATA_DIR}` 下的数据文件：`ssh -q ${user}@${ip} "cat <文件>"` 流回上下文分析，**禁止** scp 拷回本地
  - 写入 result.md / 输出契约到 `${WORK_DIR}/analysis/...`：**直接在远端机器上产出**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <文件>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、**禁止**在 agent 本地创建 `${WORK_DIR}` 目录
  - 本技能输出的调优/使能命令（echo > /sys/...、tune 脚本调用等）仅作为报告建议，**不执行**；用户确认后由用户在远端服务器上执行
- **本地模式**（execution_mode=local）：脚本与命令直接本地执行。
- 具体写法见 `opentunex-remote-execution` skill（含其 `references/work_dir_remote_semantics.md`）。

---

## 执行流程

本技能的完整执行流程如下，**必须按顺序完成所有步骤，不得在中间步骤终止**：

| 步骤 | 操作 | 产出 |
|------|------|------|
| 1 | 执行 `scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-copy-user-analysis_collect`（本地模式直接执行；远端模式按 `opentunex-remote-execution` skill 执行方式先 `ssh -q ${user}@${ip} "mkdir -p /tmp/opentunex-copy-user-analysis/"`，然后 `scp scripts/preanalysis.sh ${user}@${ip}:/tmp/opentunex-copy-user-analysis/` 再 `ssh -q -tt ${user}@${ip} "bash /tmp/opentunex-copy-user-analysis/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-copy-user-analysis_collect"`，`preanalysis.json` 生成在**远端**输出目录，禁止在 agent 本地执行） | `preanalysis.json` |
| 2 | 读取 `preanalysis.json`，按"字段→决策变量映射"表提取决策变量（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-copy-user-analysis_collect/preanalysis.json"` 流回上下文；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径） | 决策变量值 |
| 3 | 按"决策逻辑"章节依次执行环境约束前置检查 → 场景模式判定 | 分析结论 |
| 4 | 按"产出"章节模板，将决策结果写入 `${WORK_DIR}/analysis/opentunex-copy-user-analysis_collect/result.md` | 完整分析报告（含结构化数据 JSON） |
| 5 | 按"契约输出"章节格式写入输出契约 YAML 文件 | 契约文件 |

> **注意**：步骤 1 仅完成数据预处理，步骤 2-5 必须继续执行。不得在生成 `preanalysis.json` 后终止流程。**远端模式**下 `preanalysis.json` 生成在远端服务器输出目录 `${DATA_DIR}/opentunex-copy-user-analysis_collect/`，步骤 2 必须经 ssh `cat` 流回上下文读取，**禁止**在 agent 本地目录查找或读取该文件。步骤 1 为强制预解析模式：仅当步骤 1 执行失败或 `preanalysis.json` 不存在时才允许进入"数据读取"章节的降级路径，**禁止**跳过步骤 1 直接读取原始数据文件。**预解析模式下禁止直接读取 `scripts/preanalysis.sh` 脚本内容**（不得 Read/cat 脚本文件本身）：本地模式直接执行脚本；远端模式按 `opentunex-remote-execution` skill 执行方式 scp 上传脚本文件到远端后 ssh 执行，无需阅读脚本实现。

---

## 数据读取

### 预解析模式（强制首选）：预分析 JSON

> **强制**：必须先执行 `scripts/preanalysis.sh` 生成 `preanalysis.json` 并基于 JSON 分析，**禁止**跳过预解析直接读取原始数据文件。仅当预解析模式失败（脚本执行失败或 `preanalysis.json` 不存在，远端模式经 ssh 在远端确认）后，才允许进入下方降级路径。

1. 执行预处理脚本生成 JSON（远端模式：按 `opentunex-remote-execution` skill 执行方式 scp 上传后 `ssh -q -tt` 在远端执行，见"输入约定"执行模式章节）：
   ```bash
   bash scripts/preanalysis.sh ${DATA_DIR} ${DATA_DIR}/opentunex-copy-user-analysis_collect
   ```
2. 读取生成的 JSON 文件：`${DATA_DIR}/opentunex-copy-user-analysis_collect/preanalysis.json`（远端模式：`ssh -q ${user}@${ip} "cat ${DATA_DIR}/opentunex-copy-user-analysis_collect/preanalysis.json"` 流回上下文读取；**禁止**在 agent 本地用 Read 工具读取 `${DATA_DIR}` 路径、禁止 scp 拷回本地）

#### preanalysis.json 字段 → 决策变量映射

| JSON 路径 | 决策变量 | 取值说明 |
|-----------|---------|---------|
| `is_arm64` | IS_ARM64 | `true` / `false`（架构为 aarch64/arm64） |
| `part_id_hex` | PART_ID_HEX | 十六进制 partID 字符串，如 `"0xd02"` |
| `part_id_dec` | PART_ID_DEC | 十进制 partID，如 `3330` |
| `is_hisilicon_supported_cpu` | IS_HISILICON_SUPPORTED_CPU | `true` / `false`（ARM64 且 partID > 0xd02） |
| `is_copy_user_hotspot` | IS_COPY_USER_HOTSPOT | `true` / `false`（火焰图检测到 __arch_copy_to_user/__arch_copy_from_user） |
| `copy_user_funcs` | COPY_USER_FUNCS | 命中的函数名列表，如 `"__arch_copy_from_user,__arch_copy_to_user"` |
| `hotspot_percent` | HOTSPOT_PERCENT | 热点占比数值（如 `5.2` 表示 5.2%） |
| `large_copy_detected` | LARGE_COPY_DETECTED | `true` / `false`（检测到 size > 4KB 的读写） |
| `max_copy_size` | MAX_COPY_SIZE | 最大单次读写 size（字节） |
| `large_copy_count` | LARGE_COPY_COUNT | size > 4KB 的调用次数 |

### 降级路径：直接读取采集文件（仅当预解析模式失败后）

仅当预解析模式失败（`preanalysis.json` 不可用）后，从以下文件直接提取（远端模式："不可用"的判断与以下文件的读取同样必须经 ssh 在远端执行，禁止在 agent 本地查找 `${DATA_DIR}` 下的文件）：

> **⚠️ 大文件警告**：采集数据文件可能非常大，**禁止**直接 `cat`/Read 整个文件。必须按下表中每个指标的提取方法（grep 关键字 / sed 定位节）**定向搜索**目标内容，只读取命中的片段；远端模式经 ssh 在远端执行 grep，只把命中片段流回上下文，禁止把整个文件拉回 agent 本地。

| 决策变量 | 数据来源文件 | 提取方法 |
|---------|------------|---------|
| IS_ARM64 / PART_ID_HEX | `static_info.txt` / `cpu_info.txt` / `cpu_detail_info.txt` | 提取 Architecture 字段；提取 "CPU part" 行的十六进制值 |
| IS_COPY_USER_HOTSPOT / HOTSPOT_PERCENT | `hotspot_analysis.txt` / `hotspot_function_analysis.txt` | 搜索 `__arch_copy_to_user` / `__arch_copy_from_user` |
| LARGE_COPY_DETECTED / MAX_COPY_SIZE | `syscall_analysis.txt` / `io_metrics_analysis.txt` / `perf_trace.txt` | 解析 `pread64`/`pwrite64` 调用的 count 字段 |

---

## 决策逻辑

按以下优先级依次判断，命中即输出。

> **前置检查分类（遵守 SB-06）**：
> - E0 为"环境不支持"（非 ARM64 架构，硬件能力缺失），**不短路**，记录支持缺口 `COPY_USER_UNSUPPORTED_GAP`，继续评估场景条件
> - E1 为"环境不支持"（ARM64 但 partID <= 0xd02，非支持的 Hisilicon CPU），**不短路**，记录支持缺口，继续评估场景条件
> - E2 为"硬性不适用"（无 copy_to_user/copy_from_user 热点，无收益对象），命中即短路

### 环境约束前置检查

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| E0 | IS_ARM64 = false（CPU 不是 ARM64 架构） | 记录 `COPY_USER_UNSUPPORTED_GAP+="非ARM64架构"`，**继续评估**（不短路） | 本特性仅 ARM64 平台支持（环境支持缺口，见 SB-06） |
| E1 | IS_ARM64 = true 且 IS_HISILICON_SUPPORTED_CPU = false（partID <= 0xd02，非支持的 Hisilicon CPU） | 记录 `COPY_USER_UNSUPPORTED_GAP+="非支持的Hisilicon CPU(partID={PART_ID_HEX})"`，**继续评估**（不短路） | 仅 LINXICORE9100/HIP11/HIP12 等（partID > 0xd02）支持（环境支持缺口，需硬件升级） |
| E2 | IS_COPY_USER_HOTSPOT = false（火焰图未检测到 __arch_copy_to_user/__arch_copy_from_user 热点） | 不适用 | 无 copy_to_user/copy_from_user 热点，优化无收益 |

### 场景模式判定

| 优先级 | 条件 | 结论 | 原因 |
|--------|------|------|------|
| S1 | IS_COPY_USER_HOTSPOT = true 且 LARGE_COPY_DETECTED = true 且 IS_HISILICON_SUPPORTED_CPU = true | **适用** | Hisilicon CPU + 热点存在 + 大块读写(>4KB) → 应用 ldp 优化补丁可显著降低指令发射密度 |
| S2 | IS_COPY_USER_HOTSPOT = true 且 LARGE_COPY_DETECTED = true 且 `COPY_USER_UNSUPPORTED_GAP` 非空 | 收益有限（见 SB-06 处理） | 存在大块拷贝热点场景，但当前硬件/平台不支持 |
| S3 | IS_COPY_USER_HOTSPOT = true 且 LARGE_COPY_DETECTED = false 且 IS_HISILICON_SUPPORTED_CPU = true | 收益有限（场景匹配但收益不确定） | 热点存在但未检测到大块读写(>4KB)，优化收益有限（Hisilicon 路径仅对 >=4KB 生效）；若 CPU 支持 FEAT_LSUI 则仍可受益 |

### 环境支持缺口处理（SB-06）

> 当 S2 命中（热点 + 大块读写，但 partID <= 0xd02 或非 ARM64），**不得直接判为"不适用"**，改按下表输出：

| 条件 | 输出结论 | applicability | suggestion | estimated_gain.severity |
|------|---------|--------------|-----------|------------------------|
| S2 命中且 `COPY_USER_UNSUPPORTED_GAP` 非空 | 收益有限（环境不支持但场景匹配） | `limited_benefit` | `[当前硬件不支持（{COPY_USER_UNSUPPORTED_GAP 具体原因}），需手动引入该特性后方可实施：更换为支持优化的 Hisilicon CPU（partID > 0xd02，如 LINXICORE9100/HIP11/HIP12），并应用内核补丁 PR #22481] <原建议操作>` | `low` |

**综合结论示例**：`收益有限 — 当前 CPU 非 Hisilicon 支持型号(partID=0xd01)，但火焰图检测到 __arch_copy_from_user 占 5.2%，且存在 size>4KB 的大块读写，建议更换为支持优化的 Hisilicon CPU 后应用补丁`

### 严重度评估

| 条件 | severity | 原因 |
|------|----------|------|
| HOTSPOT_PERCENT >= 10 | `high` | 拷贝函数占比高（>=10%），优化收益显著 |
| HOTSPOT_PERCENT >= 3 且 < 10 | `medium` | 拷贝函数占比中等，优化有收益 |
| HOTSPOT_PERCENT < 3 或为 0 | `low` | 拷贝函数占比低，优化收益有限 |

---

## 调优步骤推荐

> **执行位置说明**：本技能只输出建议，**不执行**调优命令（遵守 T-01/T-02）。远端模式下这些命令的目标机器是远端服务器——用户确认后由用户（或后续调优域技能生成的 tuning.sh）在**远端服务器**上执行；agent 不通过 ssh 代执行调优命令。

> 以下调优步骤仅在分析结论为"适用"时适用。结论为"不适用"或"收益有限"时不执行调优。

### 调优参数

| 参数 | 说明 |
|------|------|
| 内核补丁 PR #22481 | 应用 ldp 双字加载优化补丁 |
| CONFIG_ARM64_COPY_FROM_USER_OPT=y | 内核编译配置，启用 copy_from_user 优化 |

> 本调优方向需要更新内核补丁并重新编译内核，不支持一键使能。仅 ARM64 + Hisilicon 支持 CPU (partID > 0xd02) 有效。

### 使能步骤

1. 应用内核补丁: https://atomgit.com/openeuler/kernel/pull/22481
2. 启用内核编译配置: `CONFIG_ARM64_COPY_FROM_USER_OPT=y`（已加入 openeuler_defconfig）
3. 重新编译并安装内核
4. 重启系统使新内核生效

### 验证命令

```bash
# 重启后验证内核配置
grep CONFIG_ARM64_COPY_FROM_USER_OPT /boot/config-$(uname -r)
# 重新采集火焰图，确认 __arch_copy_to_user/__arch_copy_from_user 使用 ldp/ldtp 指令
perf record -g -- <your_workload> && perf script | grep -E 'ldp|ldtp'
```

### 回滚步骤

1. 恢复原内核: 在 grub 启动菜单选择旧内核启动
2. 或重新编译不含该补丁的内核

### 冲突约束

| 冲突资源 | 冲突方向 | 执行策略 |
|---------|---------|---------|
| 内核版本 | 需要内核补丁支持 | 需重新编译内核 |
| hisock | 不同层级优化 | 无冲突，可并行 |

---

## 产出

将分析结果写入 `${WORK_DIR}/analysis/opentunex-copy-user-analysis_collect/result.md`（远端模式：**直接在远端机器上产出该文件**——经 ssh 在远端落盘（`ssh ${user}@${ip} "mkdir -p <目录> && cat > <路径>"`，heredoc 写入内容）；**禁止**先在 agent 本地生成文件再 scp 上传、禁止在 agent 本地创建 `${WORK_DIR}` 目录），格式如下：

```markdown
# copy_from_user 拷贝优化适用性分析结果

## 1. 环境检查

| 检查项 | 结果 |
|--------|------|
| IS_ARM64 | {true/false} |
| PART_ID_HEX | {十六进制 partID，如 "0xd02"} |
| PART_ID_DEC | {十进制 partID，如 3330} |
| IS_HISILICON_SUPPORTED_CPU | {true/false} |

## 2. 热点函数信息

| 指标 | 值 |
|------|-----|
| IS_COPY_USER_HOTSPOT | {true/false} |
| COPY_USER_FUNCS | {命中的函数名，如 "__arch_copy_from_user,__arch_copy_to_user"} |
| HOTSPOT_PERCENT | {热点占比，如 "5.2"} |

## 3. 大块读写信息

| 指标 | 值 |
|------|-----|
| LARGE_COPY_DETECTED | {true/false} |
| MAX_COPY_SIZE | {最大单次读写 size，字节} |
| LARGE_COPY_COUNT | {size > 4KB 的调用次数} |

## 4. 适用性评估

| 评估维度 | 结果 | 证据 |
|---------|------|------|
| ARM64 架构 | ✅/❌ | ARCH={值} |
| Hisilicon 支持 CPU (partID > 0xd02) | ✅/❌ | PART_ID={值}，十进制={值} |
| __arch_copy 热点存在 | ✅/❌ | 检测到 {函数名}，占比 {N}% |
| 大块读写 (>4KB) | ✅/❌ | 最大 size={值}字节，大块调用次数={值} |

**综合结论**: {适用/不适用/收益有限} — {原因}

**建议操作**:
1. 应用内核补丁: https://atomgit.com/openeuler/kernel/pull/22481
2. 补丁启用配置: `CONFIG_ARM64_COPY_FROM_USER_OPT=y`（已加入 openeuler_defconfig）
3. 重新编译并安装内核后重启生效
4. 验证: 重新采集火焰图，确认 `__arch_copy_to_user`/`__arch_copy_from_user` 使用 `ldp`/`ldtp` 指令

> **注意**：本调优方向需要更新内核补丁并重新编译内核后生效，不支持一键使能。

## 5. 调优步骤推荐

> 仅在结论为"适用"时适用。

### 使能步骤

1. 应用内核补丁 PR #22481
2. 设置 `CONFIG_ARM64_COPY_FROM_USER_OPT=y`
3. 重编内核并重启

### 验证

```bash
grep CONFIG_ARM64_COPY_FROM_USER_OPT /boot/config-$(uname -r)
```

### 回滚

恢复原内核启动

## 6. 结构化数据

> 以下 JSON 数据供融合器（Phase 2）自动提取，用于等价组聚合和融合分析。请将分析结论映射为此格式并写入 result.md。

```json
{
  "applicability": "applicable",
  "id": "copy_user_opt",
  "suggestion": "Hisilicon CPU + __arch_copy 热点 + 大块读写(>4KB)，推荐应用内核补丁 PR #22481 启用 ldp 双字加载优化：应用补丁 → 设置 CONFIG_ARM64_COPY_FROM_USER_OPT=y → 重编内核 → 重启生效",
  "equivalence_class": "copy_user_opt",
  "activation_requirement": "kernel_rebuild",
  "estimated_gain": {
    "primary_metric": "memory_bandwidth",
    "severity": "medium",
    "description": "使用 ldp/ldtp 双字加载替代 ldtr 单寄存器指令，降低指令发射密度，提升内存带宽利用率"
  },
  "conflicts": [],
  "prerequisites": [],
  "synergy_with": [],
  "scenario_priority": 6,
  "source": "skill_output",
  "cross_skill_relations": {
    "conflicts_with": [],
    "depends_on": []
  }
}
```
```

> **适用性结论 → JSON applicability 映射**：
> - 适用（S1 命中） → `"applicable"`
> - 不适用（E2 命中，无热点） → `"not_applicable"`
> - 收益有限（S2 命中：环境不支持但场景匹配） → `"limited_benefit"`，suggestion 须以前缀 `[当前硬件不支持（{具体缺口原因}），需手动引入该特性后方可实施：更换为支持优化的 Hisilicon CPU（partID > 0xd02），并应用内核补丁 PR #22481] ` 标注支持缺口
> - 收益有限（S3 命中：热点存在但未检测到大块读写） → `"limited_benefit"`，suggestion 须说明"未检测到大块读写(>4KB)，Hisilicon 路径仅对 >=4KB 生效，收益有限；若 CPU 支持 FEAT_LSUI 则仍可受益"

---

## 契约输出

输出契约格式参见 [contract-spec.md](../references/contract-spec.md)，本技能特有字段：

```yaml
skill_name: "opentunex-copy-user-analysis"
input:
  data_dir: "[actual DATA_DIR]"
output:
  result_path: "[actual result_path]"
constraints_acknowledged: [SB-01~SB-07]
```
