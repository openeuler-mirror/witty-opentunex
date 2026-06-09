---
name: app-benchmark-deployment
description: Generic application and benchmark deployment framework via SSH. Installs app + benchmark tool, generates unified script structure, supports config backup/restore and benchmark lifecycle. Target OS: Linux (openEuler 24.03, CentOS, RHEL, Ubuntu).
---

# app-benchmark-deployment — Application Benchmark Deployment Framework

This skill provides a **generic deployment framework** for application + benchmark on target Linux machines via SSH. It defines a **unified script structure** and **standard deployment workflow** applicable to any app-benchmark pair.

## Client Connection

skill:remote-execution

## Supported Applications

| 应用 | 压测工具 | 参考文档 |
|------|----------|----------|
| MySQL | sysbench | `references/mysql/INSTALL.md` |
| Nginx | ApacheBench (ab) | `references/nginx/INSTALL.md` |
| PostgreSQL | pgbench | `references/pgsql/INSTALL.md` |
| Redis | redis-benchmark | `references/redis/INSTALL.md` |
| Spark | HiBench | `references/spark-cluster/INSTALL.md` |

## Usage

```
opencode run "Deploy <APP> benchmark on <TARGET_IP>"
```

---

## Deployment Workflow (Generic)

### Phase 1: Pre-Deployment Check

```bash
ssh -q -tt root@${TARGET_IP} "echo 'Connection OK'"
```

### Phase 2: Install Application & Benchmark

See application-specific installation in `references/<APP>.md`

### Phase 3: Deploy Scripts

The reference document provides the script deployment commands.

### Phase 4: Backup Original Configuration

```bash
ssh -q -tt root@${TARGET_IP} "<CONFIG_QUERY_CMD> > /opt/opentunex/applications/<APP>/configs/backup.txt"
```

### Phase 5: Start Application

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-start.sh"
```

### Phase 6: Deployment Verification

```bash
# Verify application is running
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-status.sh"

# Verify benchmark tool is available
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-status.sh"

# Run a minimal benchmark test
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-prepare.sh <MIN_PARAMS>"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-run.sh <MIN_PARAMS>"

# Verify config query/set work
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-config-query.sh <SAMPLE_PARAM>"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/<APP>/scripts/<APP>-config-set.sh <SAMPLE_PARAM> <TEST_VALUE>"
```

---

## Script Structure

All scripts are placed under `/opt/opentunex/applications/<APP>/scripts/` with this unified naming:

```
/opt/opentunex/applications/<APP>/
├── scripts/
│   ├── <APP>-start.sh              # 启动应用
│   ├── <APP>-stop.sh               # 停止应用
│   ├── <APP>-status.sh             # 查看应用运行状态
│   ├── <APP>-config-query.sh       # 查询配置项
│   ├── <APP>-config-set.sh         # 设置配置项
│   ├── <APP>-benchmark-prepare.sh  # 准备压测数据
│   ├── <APP>-benchmark-run.sh       # 执行压测
│   ├── <APP>-benchmark-cleanup.sh   # 清理压测数据
│   └── <APP>-benchmark-status.sh   # 查看压测工具状态
├── configs/
│   └── backup.txt            # 配置备份（部署时自动生成）
└── logs/
    └── *.log                 # 压测日志
```

### <APP>-start.sh — 应用启停

启动应用，检查是否已运行，启动服务，等待就绪，验证。

### <APP>-stop.sh — 应用启停

停止应用，优雅停止，强制停止（可选），验证。

### <APP>-status.sh — 应用启停

输出应用运行状态和基本信息：运行状态、版本、连接数、关键指标。

### <APP>-config-query.sh — 应用配置备份/修改

- 不带参数：查询所有配置
- 带参数：查询指定配置项

### <APP>-config-set.sh — 应用配置备份/修改

设置指定配置项并验证。

### <APP>-benchmark-prepare.sh — 压测启停

准备压测数据（如创建库表），接受应用特定参数。

### <APP>-benchmark-run.sh — 压测启停

执行压测，输出日志到 logs/ 目录，接受应用特定参数。日志文件名格式：`<APP>_benchmark_<TIMESTAMP>.log`

### <APP>-benchmark-cleanup.sh — 压测启停

清理压测数据（如删除库表）。

### <APP>-benchmark-status.sh — 压测启停

输出压测工具状态：是否安装，应用是否运行。

---

## 配置备份与恢复流程

### 部署时自动备份

```bash
# Phase 4 自动执行
<APP>-config-query.sh > configs/backup.txt
```

### 配置修改流程

```bash
# 查询当前值
<APP>-config-query.sh <param>

# 修改配置
<APP>-config-set.sh <param> <new_value>

# 验证修改
<APP>-config-query.sh <param>

# 恢复备份值
<APP>-config-query.sh <param>  # 从 backup.txt 读取原值
<APP>-config-set.sh <param> <original_value>
```

---

## 快速命令参考

```bash
# 应用启停
/opt/opentunex/applications/<APP>/scripts/<APP>-start.sh
/opt/opentunex/applications/<APP>/scripts/<APP>-stop.sh
/opt/opentunex/applications/<APP>/scripts/<APP>-status.sh

# 应用配置备份/修改
/opt/opentunex/applications/<APP>/scripts/<APP>-config-query.sh              # 查询所有
/opt/opentunex/applications/<APP>/scripts/<APP>-config-query.sh <param>      # 查询单个
/opt/opentunex/applications/<APP>/scripts/<APP>-config-set.sh <param> <val>  # 设置

# 压测启停
/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-prepare.sh [args]
/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-run.sh [args]
/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-cleanup.sh
/opt/opentunex/applications/<APP>/scripts/<APP>-benchmark-status.sh
```

## 错误处理

| 错误 | 处理 |
|------|------|
| SSH 连接失败 | 检查网络和认证配置 |
| 应用安装失败 | 检查包管理器源，手动安装 |
| 应用启动失败 | 检查端口占用，检查日志 |
| Benchmark 工具缺失 | 安装对应包 |
| 压测失败 | 检查应用运行状态，检查数据库/数据是否存在 |

---

## 验证检查清单

部署完成后必须验证以下所有项目:

- [ ] `<APP>-status.sh` 显示应用 RUNNING
- [ ] `<APP>-config-query.sh` 能查询配置
- [ ] `<APP>-config-set.sh` 能修改配置
- [ ] `<APP>-benchmark-status.sh` 显示压测工具 AVAILABLE
- [ ] `<APP>-benchmark-prepare.sh` 成功执行（如果有）
- [ ] `<APP>-benchmark-run.sh` 成功执行并生成日志
- [ ] `<APP>-benchmark-cleanup.sh` 成功执行（如果有）
- [ ] 配置修改/恢复流程正常

---

## References

具体应用的安装步骤和脚本见：
- `references/mysql/INSTALL.md` — MySQL + sysbench
- `references/nginx/INSTALL.md` — Nginx + ApacheBench (ab)
- `references/pgsql/INSTALL.md` — PostgreSQL + pgbench
- `references/redis/INSTALL.md` — Redis + redis-benchmark
- `references/spark-cluster/INSTALL.md` — Spark + HiBench