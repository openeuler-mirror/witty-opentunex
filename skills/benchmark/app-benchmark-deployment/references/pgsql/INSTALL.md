# PostgreSQL + pgbench 部署参考

## 组件说明

| 组件 | 名称 | 来源 |
|------|------|------|
| 应用 | PostgreSQL | 独立安装 |
| 压测工具 | pgbench | **自带**（包含在 postgresql-contrib 包中） |

## 安装步骤

### 1. 安装 PostgreSQL

先尝试 yum 安装，如果失败则从源码编译：

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y postgresql-server postgresql-contrib 2>&1 | tail -5"
# 检查是否安装成功
ssh -q -tt root@${TARGET_IP} "command -v psql || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码编译（pgbench 会一起编译）：

```bash
# 方法2: 源码编译安装 (pgbench 会一起编译)
ssh -q -tt root@${TARGET_IP} "yum install -y gcc make readline readline-devel zlib zlib-devel 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://ftp.postgresql.org/pub/source/v15.3/postgresql-15.3.tar.gz && \
  tar -xzf postgresql-15.3.tar.gz && \
  cd postgresql-15.3 && \
  ./configure --prefix=/usr/local/pgsql --with-readline && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -10"

# 添加到 PATH
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/pgsql/bin/psql /usr/local/bin/psql"
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/pgsql/bin/pgbench /usr/local/bin/pgbench"
```

### 2. 初始化数据库 (如果使用 yum 安装)

```bash
ssh -q -tt root@${TARGET_IP} "postgresql-setup --initdb"
```

如果是源码安装，手动初始化：

```bash
ssh -q -tt root@${TARGET_IP} "useradd postgres 2>/dev/null || true"
ssh -q -tt root@${TARGET_IP} "mkdir -p /var/lib/pgsql/data"
ssh -q -tt root@${TARGET_IP} "chown postgres:postgres /var/lib/pgsql/data"
ssh -q -tt root@${TARGET_IP} "su - postgres -c '/usr/local/pgsql/bin/initdb -D /var/lib/pgsql/data'"
```

### 3. 设置密码

```bash
# 尝试默认密码 123456
ssh -q -tt root@${TARGET_IP} "su - postgres -c \"psql -c 'SELECT 1'\"" 2>&1 | grep -q "1"
if [ $? -ne 0 ]; then
  echo "Enter PostgreSQL postgres password:"
  read -s PG_PASS
fi
ssh -q -tt root@${TARGET_IP} "su - postgres -c \"psql -c \\\"ALTER USER postgres WITH PASSWORD '123456';\\\"\""
```

### 4. 创建压测数据库

```bash
ssh -q -tt root@${TARGET_IP} "su - postgres -c 'createdb pgbench' 2>/dev/null || true"
```

### 5. 创建目录结构

```bash
ssh -q -tt root@${TARGET_IP} "mkdir -p /opt/opentunex/applications/pgsql/{scripts,configs,logs}"
```

### 6. 部署脚本

```bash
for script in /root/.config/opencode/skills/app-benchmark-deployment/references/pgsql/scripts/*.sh; do
  scp -o StrictHostKeyChecking=no $script root@${TARGET_IP}:/opt/opentunex/applications/pgsql/scripts/
done
ssh -q -tt root@${TARGET_IP} "chmod +x /opt/opentunex/applications/pgsql/scripts/*.sh"
```

### 7. 备份配置

```bash
ssh -q -tt root@${TARGET_IP} "su - postgres -c \"psql -c 'SHOW ALL'\" 2>/dev/null | head -100 > /opt/opentunex/applications/pgsql/configs/backup.txt"
```

### 8. 启动 PostgreSQL

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/pgsql/scripts/pgsql-start.sh"
```

### 9. 验证

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/pgsql/scripts/pgsql-status.sh"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/pgsql/scripts/pgsql-benchmark-prepare.sh 5"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/pgsql/scripts/pgsql-benchmark-run.sh 10 120 1"
```

---

## 压测参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `$1` CLIENTS | 10 | 并发客户端数 |
| `$2` TIME | 120 | 持续压测时间（秒） |
| `$3` THREADS | 1 | 内部线程数 |

压测采用**持续性模式**，长时间运行获取稳定结果。

## 脚本列表

| 脚本 | 说明 |
|------|------|
| `pgsql-start.sh` | 启动 PostgreSQL |
| `pgsql-stop.sh` | 停止 PostgreSQL |
| `pgsql-status.sh` | 查看状态 |
| `pgsql-config-query.sh` | 查询配置 |
| `pgsql-config-set.sh` | 设置配置 |
| `pgsql-benchmark-prepare.sh` | 准备压测数据 |
| `pgsql-benchmark-run.sh` | 执行压测 |
| `pgsql-benchmark-cleanup.sh` | 清理压测数据 |
| `pgsql-benchmark-status.sh` | 压测工具状态 |