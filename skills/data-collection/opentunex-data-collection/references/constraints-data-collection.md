# 数据采集强制约束

## C-01: 只读操作
所有数据采集均为只读，不修改系统状态。

## C-02: 唯一采集方式
本技能只有一种采集方式：执行 `scripts/bottleneck_data_collector.sh`。禁止调用或推荐 scripts/ 目录下任何其他采集脚本，禁止自创其他采集流程。

## C-03: 禁止内联命令
必须直接调用采集脚本，禁止读取脚本内容后内联执行脚本中的命令，禁止自行合成等价采集命令（mpstat/iostat/vmstat/sar/perf 等）直接执行。

## C-04: 原始数据保留
采集过程中保留原始数据，不做过滤、清洗或分析。脚本输出直接落盘到数据文件。

## C-05: 数据目录约定
- 数据文件写入 `-o` 指定目录；未指定时默认 `bottleneck_data_<arch>_<YYYYMMDD_HHMMSS>/`（相对当前目录）
- 所有路径中的 `${WORK_DIR}/` 均指工作目录，可通过 `OPENTUNEX_WORK_DIR` 环境变量自定义
- 远端采集时数据留在远端落盘，禁止拷贝回本地

## C-06: 脚本直接落盘
采集脚本将数据直接写入数据文件，skill 不读取或改写采集内容，仅负责调度与结果汇总。

## C-07: 降级处理
工具不可用时脚本自动降级，标注不可用项，不中断整体流程。

## C-08: -p 仅支持单个活跃 PID（硬约束）
`-p` 只能传**一个**活跃进程的 PID；逗号分隔的多 PID 会被脚本硬校验拒绝并退出，禁止把 `pgrep <app>` 的多行输出整列传入。

**为什么**：pgrep 在多 worker（nginx master + N worker）、多实例（端口不同的 redis-shard）、父子进程等场景下天然返回多行；agent 若不主动收口就会传入 N 个 PID（曾观察到 5 个），导致热点/系统调用分析被反复 strace/perf，资源占用和数据不一致。

**做法**（SKILL.md 已给出可复制模板）：
```bash
# 严格取一个活跃 PID：排除 Z（zombie），并立即退出取第一行
APP_PID=$(pgrep -a "$APP_NAME" | awk '$2!="Z" {print $1; exit}')
[ -n "$APP_PID" ] && bash scripts/bottleneck_data_collector.sh -d 10 -p "$APP_PID" -o ${WORK_DIR}/collect
```

**与之矛盾的历史写法**（已废弃，不要再使用）：
```bash
# 错误：把 pgrep 整列传过去——脚本会拒绝并退出
bash scripts/bottleneck_data_collector.sh -d 10 -p "$(pgrep -a redis-server | awk '{print $1}' | paste -sd,)" -o ${WORK_DIR}/collect
```
