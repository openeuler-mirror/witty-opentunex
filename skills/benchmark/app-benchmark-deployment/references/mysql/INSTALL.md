# MySQL + sysbench 部署参考

## 组件说明

| 组件 | 名称 | 来源 |
|------|------|------|
| 应用 | MySQL | 独立安装 |
| 压测工具 | sysbench | 独立安装（非自带） |

## 安装步骤

### 1. 安装 MySQL

先尝试 yum 安装，如果失败则从源码编译：

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y mysql-community-server mysql-community-client 2>&1 | tail -5"
# 检查是否安装成功
ssh -q -tt root@${TARGET_IP} "command -v mysqld || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码编译：

```bash
# 方法2: 源码编译安装
ssh -q -tt root@${TARGET_IP} "yum install -y gcc gcc-c++ make cmake bison bison-devel ncurses ncurses-devel readline readline-devel openssl openssl-devel 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.33.tar.gz && \
  tar -xzf mysql-8.0.33.tar.gz && \
  cd mysql-8.0.33 && \
  cmake . -DCMAKE_INSTALL_PREFIX=/usr/local/mysql -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_unicode_ci -DWITH_SSL=system && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -10"

# 添加到 PATH
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/mysql/bin/mysql /usr/local/bin/mysql"
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/mysql/bin/mysqld /usr/local/bin/mysqld"
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/mysql/bin/mysqladmin /usr/local/bin/mysqladmin"
```

源码编译安装后初始化：

```bash
ssh -q -tt root@${TARGET_IP} "useradd mysql 2>/dev/null || true"
ssh -q -tt root@${TARGET_IP} "mkdir -p /usr/local/mysql/data"
ssh -q -tt root@${TARGET_IP} "chown -R mysql:mysql /usr/local/mysql"
ssh -q -tt root@${TARGET_IP} "/usr/local/mysql/bin/mysqld --initialize-insecure --user=mysql --datadir=/usr/local/mysql/data 2>&1 | tail -5"
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/mysql/support-files/mysql.server /etc/init.d/mysql"
```

### 2. 安装 sysbench

先尝试 yum 安装，如果失败则从源码编译：

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y sysbench 2>&1 | tail -3"
# 检查是否安装成功
ssh -q -tt root@${TARGET_IP} "command -v sysbench || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码编译：

```bash
# 方法2: 源码编译安装
ssh -q -tt root@${TARGET_IP} "yum install -y gcc gcc-c++ make automake libtool pkgconfig libaio-devel 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://github.com/akopytov/sysbench/archive/refs/tags/1.0.20.tar.gz && \
  tar -xzf 1.0.20.tar.gz && \
  cd sysbench-1.0.20 && \
  ./autogen.sh && \
  ./configure --prefix=/usr/local && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -10"

# 验证
ssh -q -tt root@${TARGET_IP} "/usr/local/bin/sysbench --version"
```

### 3. 设置密码 (Ask user, max 3 attempts)

```bash
# 尝试默认密码 123456
ssh -q -tt root@${TARGET_IP} "mysql -S /var/lib/mysql/mysql.sock -u root -p'123456' -e 'SELECT 1'" 2>&1 | grep -q "1"
if [ $? -ne 0 ]; then
  echo "Enter MySQL root password:"
  read -s MYSQL_PASS
fi
ssh -q -tt root@${TARGET_IP} "mysql -S /var/lib/mysql/mysql.sock -u root -p'123456' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '123456';\" 2>/dev/null || true"
```

### 4. 创建压测数据库

```bash
ssh -q -tt root@${TARGET_IP} "mysql -S /var/lib/mysql/mysql.sock -u root -p'123456' -e 'CREATE DATABASE IF NOT EXISTS sbtest'"
```

### 5. 创建目录结构

```bash
ssh -q -tt root@${TARGET_IP} "mkdir -p /opt/opentunex/applications/mysql/{scripts,configs,logs}"
```

### 6. 部署脚本

```bash
for script in /root/.config/opencode/skills/app-benchmark-deployment/references/mysql/scripts/*.sh; do
  scp -o StrictHostKeyChecking=no $script root@${TARGET_IP}:/opt/opentunex/applications/mysql/scripts/
done
ssh -q -tt root@${TARGET_IP} "chmod +x /opt/opentunex/applications/mysql/scripts/*.sh"
```

### 7. 备份配置

```bash
ssh -q -tt root@${TARGET_IP} "mysql -S /var/lib/mysql/mysql.sock -u root -p'123456' -e 'SHOW GLOBAL VARIABLES' 2>/dev/null > /opt/opentunex/applications/mysql/configs/backup.txt"
```

### 8. 启动 MySQL

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/mysql/scripts/mysql-start.sh"
```

### 9. 验证

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/mysql/scripts/mysql-status.sh"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/mysql/scripts/mysql-benchmark-prepare.sh 4 10000"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/mysql/scripts/mysql-benchmark-run.sh 8 120 read_write"
```

---

## 压测参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `$1` THREADS | 8 | 并发线程数 |
| `$2` TIME | 120 | 持续压测时间（秒） |
| `$3` TEST_TYPE | read_write | 测试类型（read_write/read_only/write_only） |

压测采用**持续性模式**，长时间运行获取稳定结果。

---

## sysbench 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--threads` | 1 | 压测线程数 |
| `--time` | 10 | 压测时长(秒) |
| `--rate` | 0 | TPS限流(0=不限) |
| `--report-interval` | 0 | 报告间隔(秒) |

### Lua 脚本

| 脚本 | 说明 |
|------|------|
| `oltp_read_write.lua` | 混合读写(默认) |
| `oltp_read_only.lua` | 只读 |
| `oltp_write_only.lua` | 只写 |
| `oltp_common.lua` | 通用工具 |

### 关键指标提取

```bash
# QPS
grep "queries:" sysbench.log | awk '{print $3}'
# TPS
grep "transactions:" sysbench.log | awk '{print $3}'
# Latency avg
grep "^    avg:" sysbench.log
# Latency 95th
grep "95th percentile:" sysbench.log
```

---

## 脚本列表

| 脚本 | 说明 |
|------|------|
| `mysql-start.sh` | 启动 MySQL |
| `mysql-stop.sh` | 停止 MySQL |
| `mysql-status.sh` | 查看状态 |
| `mysql-config-query.sh` | 查询配置 |
| `mysql-config-set.sh` | 设置配置 |
| `mysql-benchmark-prepare.sh` | 准备压测数据 |
| `mysql-benchmark-run.sh` | 执行压测 |
| `mysql-benchmark-cleanup.sh` | 清理压测数据 |
| `mysql-benchmark-status.sh` | 压测工具状态 |