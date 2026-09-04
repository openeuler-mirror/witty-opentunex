#!/bin/bash
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"
export PATH=$JAVA_HOME/bin:$PATH

SPARK_HOME="${SPARK_HOME:-/opt/apache-spark-3.5.0}"
HOSTNAME=$(hostname -f)

echo "=== Preparing Spark Cluster ==="

# Check Java
if ! command -v java &>/dev/null; then
  echo "Error: Java not found"
  exit 1
fi
echo "Java: $(java -version 2>&1 | head -1)"

# Format HDFS (if not initialized)
if [ -d "/opt/hadoop" ]; then
  echo "Initializing HDFS..."
  /opt/hadoop/bin/hdfs namenode -format -force 2>/dev/null || true
fi

# Start ZooKeeper first
echo "Starting ZooKeeper..."
/opt/zookeeper/bin/zkServer.sh start 2>/dev/null || true
sleep 3

# Start HDFS
echo "Starting HDFS..."
/opt/hadoop/bin/hdfs --daemon start namenode 2>/dev/null || true
sleep 2
/opt/hadoop/bin/hdfs --daemon start datanode 2>/dev/null || true
sleep 2

# Verify HDFS
echo "Checking HDFS..."
/opt/hadoop/bin/hdfs dfsadmin -report 2>/dev/null | head -10 || echo "HDFS may not be ready"

# Create HiBench directory in HDFS
if [ -d "/opt/hibench" ]; then
  echo "Setting up HiBench in HDFS..."
  /opt/hadoop/bin/hdfs dfs -mkdir -p /benchmarks 2>/dev/null || true
  /opt/hadoop/bin/hdfs dfs -mkdir -p /user/root 2>/dev/null || true
fi

# Start Spark Master
echo "Starting Spark Master..."
$SPARK_HOME/sbin/start-master.sh
sleep 5

# Check Spark Master
if pgrep -f Master > /dev/null; then
  echo "Spark Master started successfully"
else
  echo "Warning: Spark Master may not have started"
fi

# Start Spark Worker
echo "Starting Spark Worker..."
SPARK_MASTER_URL="spark://${HOSTNAME}:7077"
$SPARK_HOME/sbin/start-worker.sh $SPARK_MASTER_URL
sleep 3

# Final status
echo ""
echo "=== Cluster Prepare Complete ==="
pgrep -f QuorumPeerMain > /dev/null && echo "ZooKeeper: RUNNING" || echo "ZooKeeper: STOPPED"
pgrep -f NameNode > /dev/null && echo "HDFS NameNode: RUNNING" || echo "HDFS NameNode: STOPPED"
pgrep -f DataNode > /dev/null && echo "HDFS DataNode: RUNNING" || echo "HDFS DataNode: STOPPED"
pgrep -f Master > /dev/null && echo "Spark Master: RUNNING" || echo "Spark Master: STOPPED"
pgrep -f Worker > /dev/null && echo "Spark Worker: RUNNING" || echo "Spark Worker: STOPPED"