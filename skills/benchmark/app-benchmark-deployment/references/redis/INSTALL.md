# Redis + redis-benchmark 部署参考

## 组件说明

| 组件 | 名称 | 来源 |
|------|------|------|
| 应用 | Redis | 独立安装 |
| 压测工具 | redis-benchmark | **自带**（Redis 源码编译后自动生成） |

## 安装步骤

### 1. 安装 Redis

先尝试 yum 安装，如果失败则从源码编译：

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y redis 2>&1 | tail -5"
# 检查是否安装成功
ssh -q -tt root@${TARGET_IP} "command -v redis-server || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码编译（redis-benchmark 会一起编译）：

```bash
# 方法2: 源码编译安装 (redis-benchmark 会一起编译)
ssh -q -tt root@${TARGET_IP} "yum install -y gcc make jemalloc jemalloc-devel 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://github.com/redis/redis/archive/refs/tags/7.0.12.tar.gz && \
  tar -xzf 7.0.12.tar.gz && \
  cd redis-7.0.12 && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -10"

# 添加到 PATH
ssh -q -tt root@${TARGET_IP} "ln -sf /tmp/redis-7.0.12/src/redis-server /usr/local/bin/redis-server"
ssh -q -tt root@${TARGET_IP} "ln -sf /tmp/redis-7.0.12/src/redis-benchmark /usr/local/bin/redis-benchmark"
ssh -q -tt root@${TARGET_IP} "ln -sf /tmp/redis-7.0.12/src/redis-cli /usr/local/bin/redis-cli"
```

### 2. 创建目录结构

```bash
ssh -q -tt root@${TARGET_IP} "mkdir -p /opt/opentunex/applications/redis/{scripts,configs,logs}"
```

### 3. 部署脚本

```bash
for script in /root/.config/opencode/skills/app-benchmark-deployment/references/redis/scripts/*.sh; do
  scp -o StrictHostKeyChecking=no $script root@${TARGET_IP}:/opt/opentunex/applications/redis/scripts/
done
ssh -q -tt root@${TARGET_IP} "chmod +x /opt/opentunex/applications/redis/scripts/*.sh"
```

### 4. 备份配置

```bash
ssh -q -tt root@${TARGET_IP} "redis-cli CONFIG GET * 2>/dev/null | paste - - | head -50 > /opt/opentunex/applications/redis/configs/backup.txt"
```

### 5. 启动 Redis

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/redis/scripts/redis-start.sh"
```

### 6. 验证

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/redis/scripts/redis-status.sh"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/redis/scripts/redis-benchmark-run.sh 50 120"
```

---

## 压测参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `$1` CLIENTS | 50 | 并发客户端数 |
| `$2` DURATION | 120 | 持续压测时间（秒） |

压测采用**持续性模式**，长时间运行获取稳定结果。

## 脚本列表

| 脚本 | 说明 |
|------|------|
| `redis-start.sh` | 启动 Redis |
| `redis-stop.sh` | 停止 Redis |
| `redis-status.sh` | 查看状态 |
| `redis-config-query.sh` | 查询配置 |
| `redis-config-set.sh` | 设置配置 |
| `redis-benchmark-run.sh` | 执行压测 |
| `redis-benchmark-status.sh` | 压测工具状态 |