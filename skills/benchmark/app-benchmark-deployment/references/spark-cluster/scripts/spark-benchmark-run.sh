#!/bin/bash
EXECUTORS=${1:-2}
EXECUTOR_MEM=${2:-1g}
DRIVER_MEM=${3:-1g}
CORES=${4:-2}
ROWS=${5:-1000000}
DURATION=${6:-180}
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-1.8.0-openjdk}"
export PATH=$JAVA_HOME/bin:$PATH
export SPARK_HOME="${SPARK_HOME:-/opt/apache-spark-3.5.0}"

SPARK_MASTER="spark://$(hostname -f):7077"
RESULT_DIR="/opt/opentunex/spark-cluster/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p $RESULT_DIR

JAR=$(find $SPARK_HOME -name "spark-examples*.jar" 2>/dev/null | head -1)

if [ -z "$JAR" ]; then
  echo "Error: spark-examples*.jar not found"
  exit 1
fi

echo "=== Spark Sustained Performance Test ==="
echo "Executors: $EXECUTORS, Executor Mem: $EXECUTOR_MEM, Cores: $CORES"
echo "Rows: $ROWS, Target Duration: ${DURATION}s"
echo "SPARK_MASTER: $SPARK_MASTER"
echo ""

START_TIME=$(date +%s)
ITER=0

while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
  ITER=$((ITER + 1))
  ITER_START=$(date +%s.%N)
  
  $SPARK_HOME/bin/spark-submit \
    --class org.apache.spark.examples.GroupByTest \
    --master $SPARK_MASTER \
    --conf spark.executor.memory=$EXECUTOR_MEM \
    --conf spark.driver.memory=$DRIVER_MEM \
    --conf spark.executor.cores=$CORES \
    --conf spark.cores.max=$((EXECUTORS * CORES)) \
    $JAR $ROWS 10 2>&1 | tee -a ${RESULT_DIR}/spark_benchmark_${TIMESTAMP}.log
  
  ITER_END=$(date +%s.%N)
  ITER_DURATION=$(echo "$ITER_END - $ITER_START" | bc)
  TOTAL_ELAPSED=$(($(date +%s) - START_TIME))
  
  echo "[$ITER] Duration: ${ITER_DURATION}s, Elapsed: ${TOTAL_ELAPSED}s" >> ${RESULT_DIR}/spark_benchmark_${TIMESTAMP}.log
  echo "[$ITER] Completed in ${ITER_DURATION}s (elapsed: ${TOTAL_ELAPSED}s/${DURATION}s)"
done

echo "=== Results Summary ==="
echo "Total iterations: $ITER"
echo "Last 5 GroupBy durations:"
grep "\[.*\] Duration:" ${RESULT_DIR}/spark_benchmark_${TIMESTAMP}.log | tail -5