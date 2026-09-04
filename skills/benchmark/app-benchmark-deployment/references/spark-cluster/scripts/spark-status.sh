#!/bin/bash
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"
export PATH=$JAVA_HOME/bin:$PATH

SPARK_HOME="${SPARK_HOME:-/opt/apache-spark-3.5.0}"

echo "=== Spark Cluster Status ==="
echo ""
echo "Java:"
java -version 2>&1 | head -1
echo ""
echo "JAVA_HOME: $JAVA_HOME"
echo ""

pgrep -f QuorumPeerMain > /dev/null && echo "ZooKeeper: RUNNING" || echo "ZooKeeper: STOPPED"
pgrep -f Master > /dev/null && echo "Spark Master: RUNNING" || echo "Spark Master: STOPPED"
pgrep -f Worker > /dev/null && echo "Spark Worker: RUNNING" || echo "Spark Worker: STOPPED"
echo ""

# Try to get Spark UI info
if pgrep -f Master > /dev/null; then
  echo "Spark Master UI: http://$(hostname -f):8080"
fi
if pgrep -f Worker > /dev/null; then
  echo "Spark Worker UI: http://$(hostname -f):8081"
fi