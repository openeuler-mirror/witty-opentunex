# remote-execution

远程执行框架，提供标准化的SSH连接管理、命令执行模式和超时处理。

## 总体功能

所有需要远程执行的Skill的基础依赖：

1. **连接管理** - SSH连接建立、测试、保存
2. **命令执行** - 远程命令执行、脚本上传执行
3. **认证处理** - 密码/SSH密钥认证
4. **安全控制** - 特权命令确认、数据本地性

## 前置依赖

### 系统要求

- SSH服务运行
- 目标机器可达
- 有效用户凭证

## 用法

### 被引用方式

所有需要远程执行的Skill在开头引用：

```markdown
## Client Connection and Command Execution

Load the remote-execution skill for standardized SSH connection and command execution:

skill:remote-execution
```

### 执行模式

#### 简单命令

```bash
ssh ${username}@${ip} "uname -r"
ssh -q -tt ${username}@${ip} "cat /proc/cpuinfo"
```

#### 复杂脚本

```bash
# 方式1: 管道传输
ssh ${username}@${ip} "bash -s" < script.sh

# 方式2: scp后执行
scp script.sh ${username}@${ip}:/tmp/
ssh -q -tt ${username}@${ip} "sh /tmp/script.sh"
```

#### perf相关命令

```bash
ssh -q -tt ${username}@${ip} 'perf sched record -a -- sleep 15'
```

## 关键输出件

| 输出件 | 说明 |
|--------|------|
| 连接状态 | SSH连接是否成功 |
| 命令输出 | 远程命令执行结果 |
| 错误码 | 命令执行是否成功 |

## 安全要求

1. **破坏性命令需确认** - rm, shutdown等需用户确认
2. **数据本地性** - 禁止将客户端数据传回分析
3. **认证信息保护** - 凭证存储需加密

## 认证流程

```
1. 提取IP (从用户输入)
2. 测试SSH连接
   ├→ 成功 → 继续
   └→ 失败 → 查询client.yaml
        ├→ 找到 → 尝试保存的凭证
        └→ 未找到 → 询问用户
3. 凭证测试
   ├→ 成功 → 继续
   └→ 失败 → 重新询问
4. 配置免密
```
