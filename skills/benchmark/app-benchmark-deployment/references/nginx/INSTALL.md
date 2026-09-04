# Nginx + ApacheBench 部署参考

## 组件说明

| 组件 | 名称 | 来源 |
|------|------|------|
| 应用 | Nginx | 独立安装 |
| 压测工具 | ApacheBench (ab) | 独立安装（非自带） |

## 安装步骤

### 1. 安装 Nginx

先尝试 yum 安装，如果失败则从源码编译：

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y nginx 2>&1 | tail -5"
# 检查是否安装成功
ssh -q -tt root@${TARGET_IP} "command -v nginx || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码编译：

```bash
# 方法2: 源码编译安装
ssh -q -tt root@${TARGET_IP} "yum install -y gcc make pcre pcre-devel zlib zlib-devel openssl openssl-devel 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget http://nginx.org/download/nginx-1.24.0.tar.gz && \
  tar -xzf nginx-1.24.0.tar.gz && \
  cd nginx-1.24.0 && \
  ./configure --prefix=/usr/local/nginx --with-http_ssl_module && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -10"

# 添加到 PATH
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx"
```

### 2. 安装 ApacheBench (ab)

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y httpd-tools 2>&1 | tail -3"
# 检查
ssh -q -tt root@${TARGET_IP} "command -v ab || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码编译：

```bash
# 方法2: 源码编译安装 apr 和 ab
ssh -q -tt root@${TARGET_IP} "yum install -y gcc make autoconf libtool 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://archive.apache.org/dist/apr/apr-1.7.0.tar.gz && \
  tar -xzf apr-1.7.0.tar.gz && \
  cd apr-1.7.0 && \
  ./configure --prefix=/usr/local/apr && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -5"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://archive.apache.org/dist/apr/apr-util-1.6.1.tar.gz && \
  tar -xzf apr-util-1.6.1.tar.gz && \
  cd apr-util-1.6.1 && \
  ./configure --prefix=/usr/local/apr-util --with-apr=/usr/local/apr && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -5"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://archive.apache.org/dist/httpd/httpd-2.4.57.tar.gz && \
  tar -xzf httpd-2.4.57.tar.gz && \
  cd httpd-2.4.57 && \
  ./configure --prefix=/usr/local/apache2 --with-apr=/usr/local/apr --with-apr-util=/usr/local/apr-util --enable-modules=none --enable-mods-shared=none && \
  make -j\$(nproc) && \
  make install" 2>&1 | tail -5"

# ab 会在 bin 目录下
ssh -q -tt root@${TARGET_IP} "ln -sf /usr/local/apache2/bin/ab /usr/local/bin/ab"
```

### 3. 创建目录结构

```bash
ssh -q -tt root@${TARGET_IP} "mkdir -p /opt/opentunex/applications/nginx/{scripts,configs,logs}"
```

### 4. 部署脚本

```bash
for script in /root/.config/opencode/skills/app-benchmark-deployment/references/nginx/scripts/*.sh; do
  scp -o StrictHostKeyChecking=no $script root@${TARGET_IP}:/opt/opentunex/applications/nginx/scripts/
done
ssh -q -tt root@${TARGET_IP} "chmod +x /opt/opentunex/applications/nginx/scripts/*.sh"
```

### 5. 备份配置

```bash
ssh -q -tt root@${TARGET_IP} "nginx -T 2>&1 | head -100 > /opt/opentunex/applications/nginx/configs/backup.txt"
```

### 6. 启动 Nginx

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/nginx/scripts/nginx-start.sh"
```

### 7. 验证

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/nginx/scripts/nginx-status.sh"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/nginx/scripts/nginx-benchmark-run.sh 100 60000"
```

---

## 压测参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `$1` CLIENTS | 100 | 并发客户端数 |
| `$2` DURATION | 120 | 持续压测时间（秒） |
| `$3` INTERVAL | 10 | 每次迭代间隔（秒） |

压测采用**持续性模式**，每 `INTERVAL` 秒执行一次压测迭代，持续 `DURATION` 秒。

## 脚本列表

| 脚本 | 说明 |
|------|------|
| `nginx-start.sh` | 启动 Nginx |
| `nginx-stop.sh` | 停止 Nginx |
| `nginx-status.sh` | 查看状态 |
| `nginx-config-query.sh` | 查询配置 |
| `nginx-config-set.sh` | 设置配置 |
| `nginx-benchmark-run.sh` | 执行压测 |
| `nginx-benchmark-status.sh` | 压测工具状态 |