#!/bin/bash
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"
export PATH=$JAVA_HOME/bin:$PATH

SPARK_HOME="${SPARK_HOME:-/opt/apache-spark-3.5.0}"

echo "=== Stopping Spark Standalone Cluster ==="

# Stop Spark Worker
$SPARK_HOME/sbin/stop-worker.sh 2>/dev/null || pkill -f Worker

# Stop Spark Master
$SPARK_HOME/sbin/stop-master.sh 2>/dev/null || pkill -f Master

# Stop HDFS
/opt/hadoop/bin/hdfs --daemon stop namenode 2>/dev/null || true
/opt/hadoop/bin/hdfs --daemon stop datanode 2>/dev/null || true

# Stop ZooKeeper
/opt/zookeeper/bin/zkServer.sh stop 2>/dev/null || pkill -f QuorumPeerMain

echo "=== Cluster Stopped ==="