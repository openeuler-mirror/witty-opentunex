# Spark Standalone Cluster + HiBench 部署参考

## 组件说明

| 组件 | 名称 | 来源 |
|------|------|------|
| 应用 | Spark Standalone | 独立安装 |
| 压测工具 | HiBench | 独立安装（Git clone） |

## 安装步骤

### 1. 安装 Java (JDK)

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y java-1.8.0-openjdk-devel 2>&1 | tail -3"
# 检查
ssh -q -tt root@${TARGET_IP} "command -v java || echo 'NOT_INSTALLED'"
```

如果 yum 安装失败，使用源码或其他方式：

```bash
# 方法2: 从官网下载 JDK tarball
ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u432-b06/OpenJDK8U-jdk_x64_linux_hotspot_8u432b06.tar.gz && \
  tar -xzf OpenJDK8U-jdk_x64_linux_hotspot_8u432b06.tar.gz -C /usr/local/ && \
  ln -sf /usr/local/jdk8u432-b06 /usr/local/java"
```

### 2. 安装 Spark

```bash
# 方法1: 下载预编译包
ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz && \
  tar -xzf spark-3.5.0-bin-hadoop3.tgz -C /opt/ && \
  mv /opt/spark-3.5.0-bin-hadoop3 /opt/apache-spark-3.5.0 && \
  ln -sf /opt/apache-spark-3.5.0/bin/pyspark /usr/local/bin/pyspark && \
  ln -sf /opt/apache-spark-3.5.0/bin/spark-submit /usr/local/bin/spark-submit"
```

如果预编译包不存在，使用源码编译：

```bash
# 方法2: 源码编译安装
ssh -q -tt root@${TARGET_IP} "yum install -y git 2>&1 | tail -3"

ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  git clone --depth 1 -b branch-3.5.0 https://github.com/apache/spark.git && \
  cd spark && \
  ./build/mvn package -DskipTests -Dhadoop.version=3.1.1 -Phive -Phive-thriftserver 2>&1 | tail -20"
```

### 3. 安装 Dependencies (ZooKeeper, Hadoop, Scala, Hive)

```bash
# 方法1: yum 安装
ssh -q -tt root@${TARGET_IP} "yum install -y zookeeper hadoop-3.1-client scala hive 2>&1 | tail -5"
```

如果 yum 安装失败，从源码或其他源安装：

```bash
# 方法2: 独立安装各组件
# ZooKeeper
ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://archive.apache.org/dist/zookeeper/zookeeper-3.9.3/zookeeper-3.9.3.tar.gz && \
  tar -xzf zookeeper-3.9.3.tar.gz -C /opt/ && \
  ln -sf /opt/zookeeper-3.9.3 /opt/zookeeper"

# Scala (如果需要)
ssh -q -tt root@${TARGET_IP} "cd /tmp && \
  wget https://archive.apache.org/dist/scala/scala-2.12.18/scala-2.12.18.tgz && \
  tar -xzf scala-2.12.18.tgz -C /opt/ && \
  ln -sf /opt/scala-2.12.18/bin/scala /usr/local/bin/scala"
```

### 4. 配置 JAVA_HOME

```bash
ssh -q -tt root@${TARGET_IP} "echo 'export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk' >> /root/.bashrc"
ssh -q -tt root@${TARGET_IP} "source /root/.bashrc"
```

### 5. 配置 ZooKeeper

```bash
ssh -q -tt root@${TARGET_IP} "mkdir -p /opt/zookeeper/conf /var/lib/zookeeper"
ssh -q -tt root@${TARGET_IP} "cat > /opt/zookeeper/conf/zoo.cfg << 'EOF'
tickTime=2000
dataDir=/var/lib/zookeeper
clientPort=2181
initLimit=10
syncLimit=5
EOF
echo '1' > /var/lib/zookeeper/myid"
```

### 6. 安装 HiBench

```bash
ssh -q -tt root@${TARGET_IP} "git clone --depth 1 https://github.com/Intel-bigdata/HiBench.git /opt/hibench 2>&1 | tail -5"
```

### 7. 创建目录结构

```bash
ssh -q -tt root@${TARGET_IP} "mkdir -p /opt/opentunex/spark-cluster/{scripts,configs,logs}"
```

### 8. 部署脚本

```bash
for script in /root/.config/opencode/skills/app-benchmark-deployment/references/spark-cluster/scripts/*.sh; do
  scp -o StrictHostKeyChecking=no $script root@${TARGET_IP}:/opt/opentunex/spark-cluster/scripts/
done
ssh -q -tt root@${TARGET_IP} "chmod +x /opt/opentunex/spark-cluster/scripts/*.sh"
```

### 9. 启动集群

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/spark-cluster/scripts/spark-start.sh"
```

### 10. 验证

```bash
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/spark-cluster/scripts/spark-status.sh"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/spark-cluster/scripts/spark-benchmark-prepare.sh"
ssh -q -tt root@${TARGET_IP} "/opt/opentunex/applications/spark-cluster/scripts/spark-benchmark-run.sh 2 1g 1g 2 1000000 180"
```

---

## 压测参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `$1` EXECUTORS | 2 | Executor 数量 |
| `$2` EXECUTOR_MEM | 1g | 每个 Executor 内存 |
| `$3` DRIVER_MEM | 1g | Driver 内存 |
| `$4` CORES | 2 | 每个 Executor CPU 核心数 |
| `$5` ROWS | 1000000 | GroupBy 测试数据行数 |
| `$6` DURATION | 180 | 目标持续压测时间（秒） |

压测采用 **GroupBy 持续迭代**，每轮检查已用时间，达到 `DURATION` 秒后结束迭代取稳定结果。

## 脚本列表

| 脚本 | 说明 |
|------|------|
| `spark-benchmark-prepare.sh` | 初始化集群（格式化HDFS、启动ZooKeeper/HDFS/Spark） |
| `spark-start.sh` | 启动 Spark 集群（依赖 prepare 后执行） |
| `spark-stop.sh` | 停止 Spark 集群 |
| `spark-status.sh` | 查看集群状态 |
| `spark-benchmark-run.sh` | 执行压测 |
| `spark-benchmark-status.sh` | 压测工具状态 |

## 启动顺序

```
spark-benchmark-prepare.sh  → 初始化集群（首次或重启后必须执行）
spark-start.sh              → 启动集群服务
spark-benchmark-run.sh      → 执行压测
spark-stop.sh               → 停止集群
```