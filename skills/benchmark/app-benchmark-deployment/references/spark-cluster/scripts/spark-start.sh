#!/bin/bash
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"
export PATH=$JAVA_HOME/bin:$PATH

SPARK_HOME="${SPARK_HOME:-/opt/apache-spark-3.5.0}"
HOSTNAME=$(hostname -f)
SPARK_MASTER_URL="spark://${HOSTNAME}:7077"

echo "=== Starting Spark Standalone Cluster ==="
echo "SPARK_MASTER_URL: $SPARK_MASTER_URL"

# Start ZooKeeper (if not running)
if ! pgrep -f QuorumPeerMain > /dev/null; then
  /opt/zookeeper/bin/zkServer.sh start 2>/dev/null || true
  sleep 3
else
  echo "ZooKeeper already running"
fi

# Start HDFS (if not running)
if ! pgrep -f NameNode > /dev/null; then
  /opt/hadoop/bin/hdfs --daemon start namenode 2>/dev/null || true
  sleep 2
  /opt/hadoop/bin/hdfs --daemon start datanode 2>/dev/null || true
  sleep 2
else
  echo "HDFS already running"
fi

# Start Spark Master (if not running)
if ! pgrep -f Master > /dev/null; then
  $SPARK_HOME/sbin/start-master.sh
  sleep 5
else
  echo "Spark Master already running"
fi

# Start Spark Worker (if not running)
if ! pgrep -f Worker > /dev/null; then
  $SPARK_HOME/sbin/start-worker.sh $SPARK_MASTER_URL
  sleep 3
else
  echo "Spark Worker already running"
fi

echo "=== Cluster Status ==="
pgrep -f QuorumPeerMain > /dev/null && echo "ZooKeeper: RUNNING" || echo "ZooKeeper: STOPPED"
pgrep -f NameNode > /dev/null && echo "HDFS NameNode: RUNNING" || echo "HDFS NameNode: STOPPED"
pgrep -f DataNode > /dev/null && echo "HDFS DataNode: RUNNING" || echo "HDFS DataNode: STOPPED"
pgrep -f Master > /dev/null && echo "Spark Master: RUNNING" || echo "Spark Master: STOPPED"
pgrep -f Worker > /dev/null && echo "Spark Worker: RUNNING" || echo "Spark Worker: STOPPED"