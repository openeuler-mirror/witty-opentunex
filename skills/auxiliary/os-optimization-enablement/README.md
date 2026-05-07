# os-optimization-enablement

OS级别优化使能Skill，执行实际的系统优化操作、性能基准测试、结果验证和回滚支持。

## 总体功能

执行OS级别优化使能，主要功能包括：

1. **配置备份** - 备份当前系统配置到远程主机
2. **性能基线测试** - 建立优化前性能基准
3. **优化执行** - 支持批量或逐项优化执行模式
4. **结果验证** - 通过基准测试验证优化效果
5. **回滚支持** - 一键回滚到优化前状态

**前置依赖**: os-performance-optimization skill识别出的优化项

## 前置依赖

### 必需依赖

- **remote-execution skill** - SSH远程连接和命令执行
- **os-performance-optimization skill** - 优化项来源

### 系统要求

- Linux内核 >= 3.10
- SSH访问权限
- root或sudo权限（修改系统配置需要）

### 工具依赖

- `sysctl` (系统参数修改)
- `sysbench`, `fio`, `iperf3` (性能测试)
- `taskset`, `chrt` (进程调度)

## 用法

### 自然语言输入示例

```
执行192.168.1.100的OS优化使能，之前已经分析过了
```

```
对服务器应用以下优化: 降低swappiness为10，更改IO调度器为mq-deadline
```

```
使用step-by-step模式执行优化，每项优化后测试效果
```

### 执行模式

#### 模式1: 批量优化

```
1. 备份配置
2. 建立基线
3. 应用所有优化
4. 综合测试
5. 评估效果
```

#### 模式2: 逐项优化

```
For each 优化项:
    1. 建立该项基线
    2. 应用优化
    3. 测试效果
    4. 决定: 保留/回滚
```

### 输出示例

```markdown
## 优化使能执行报告

### Phase 1: 配置备份
备份目录: /opt/opentunex/backup/20240115_143022/
备份内容:
- sysctl_current.txt
- sysctl.conf.backup
- vm_params.txt
- scheduler_sda.txt

### Phase 2: 性能基线
| 指标 | 基线值 |
|------|--------|
| CPU ops/s | 12500 |
| Memory MB/s | 8500 |
| IOPS | 45000 |

### Phase 3: 优化执行

#### OPT-001: vm.swappiness=10
- 状态: ✓ 已应用
- 验证: sysctl vm.swappiness = 10

#### OPT-002: I/O调度器=mq-deadline
- 状态: ✓ 已应用
- 验证: cat /sys/block/sda/queue/scheduler = [mq-deadline]

### Phase 4: 优化后测试
| 指标 | 基线 | 优化后 | 提升 |
|------|------|--------|------|
| CPU ops/s | 12500 | 13200 | +5.6% |
| Memory MB/s | 8500 | 9100 | +7.1% |
| IOPS | 45000 | 58000 | +28.9% |

### Phase 5: 总结
- 应用优化: 2项
- 有效优化: 2项
- 回滚优化: 0项
- 回滚脚本: /opt/opentunex/backup/.../rollback.sh
```

## 关键输出件

| 输出件 | 路径/位置 | 说明 |
|--------|-----------|------|
| 配置备份 | /opt/opentunex/backup/YYYYMMDD_HHMMSS/ | 原始配置备份 |
| 基线数据 | /opt/optimization-results/baseline_*/ | 优化前性能数据 |
| 回滚脚本 | ${BACKUP_DIR}/rollback.sh | 一键回滚脚本 |
| 测试结果 | /opt/optimization-results/post_*/ | 优化后性能数据 |
| 最终报告 | Skill输出 | 执行总结 |

## 目录结构

```
os-optimization-enablement/
├── SKILL.md                          # 主Skill文件
└── scripts/
    └── backup_config.sh             # 配置备份脚本(远程执行)
```
