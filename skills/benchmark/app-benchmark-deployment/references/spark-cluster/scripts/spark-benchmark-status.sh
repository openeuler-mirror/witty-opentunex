#!/bin/bash
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"
export PATH=$JAVA_HOME/bin:$PATH
export SPARK_HOME="${SPARK_HOME:-/opt/apache-spark-3.5.0}"

echo "=== Benchmark Tools Status ==="
echo ""

# Java
command -v java &>/dev/null && java -version 2>&1 | head -1 || echo "Java: NOT INSTALLED"

# Spark
command -v spark-submit &>/dev/null && echo "Spark Submit: AVAILABLE" || echo "Spark Submit: NOT INSTALLED"
[ -d "$SPARK_HOME" ] && echo "SPARK_HOME: $SPARK_HOME EXISTS" || echo "SPARK_HOME: NOT FOUND"

# HiBench
[ -d "/opt/hibench" ] && echo "HiBench: AVAILABLE" || echo "HiBench: NOT INSTALLED"

# Cluster status
echo ""
pgrep -f QuorumPeerMain > /dev/null && echo "ZooKeeper: RUNNING" || echo "ZooKeeper: STOPPED"
pgrep -f Master > /dev/null && echo "Spark Master: RUNNING" || echo "Spark Master: STOPPED"
pgrep -f Worker > /dev/null && echo "Spark Worker: RUNNING" || echo "Spark Worker: STOPPED"