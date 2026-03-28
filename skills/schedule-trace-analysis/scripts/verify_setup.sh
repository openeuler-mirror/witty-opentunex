#!/bin/bash
# Quick test script to verify process-schedule-trace-analysis skill setup

set -e

echo "======================================="
echo "Process Scheduling Trace Analysis Skill"
echo "Setup Verification"
echo "======================================="
echo ""

# Check if all required files exist
echo "Checking required files..."

files=(
    "SKILL.md"
    "README.md"
    "scripts/collect_sched_trace.sh"
    "scripts/analyze_sched_trace.sh"
    "references/bottleneck.md"
)

all_found=true
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (not found)"
        all_found=false
    fi
done

echo ""

# Check script permissions
echo "Checking script permissions..."
if [ -x "scripts/collect_sched_trace.sh" ]; then
    echo "  ✓ collect_sched_trace.sh is executable"
else
    echo "  ✗ collect_sched_trace.sh is not executable"
    all_found=false
fi

if [ -x "scripts/analyze_sched_trace.sh" ]; then
    echo "  ✓ analyze_sched_trace.sh is executable"
else
    echo "  ✗ analyze_sched_trace.sh is not executable"
    all_found=false
fi

echo ""

# Check if perf is available
echo "Checking dependencies..."
if command -v perf &> /dev/null; then
    echo "  ✓ perf is available: $(perf --version | head -1)"
else
    echo "  ⚠ perf is not installed. Install with: apt-get install linux-tools-$(uname -r)"
fi

echo ""

# Check bc for calculations
if command -v bc &> /dev/null; then
    echo "  ✓ bc is available (needed for calculations)"
else
    echo "  ⚠ bc is not installed. Install with: apt-get install bc"
fi

echo ""

# Summary
echo "======================================="
if [ "$all_found" = true ]; then
    echo "✓ All files and permissions are correct"
    echo ""
    echo "To use this skill:"
    echo "1. Load the skill: skill process-schedule-trace-analysis"
    echo "2. Collect data: ./scripts/collect_sched_trace.sh <PID>"
    echo "3. Analyze data: ./scripts/analyze_sched_trace.sh <input_dir> <PID>"
    echo ""
    echo "For more information, see README.md"
else
    echo "✗ Some files or permissions are missing"
    exit 1
fi
echo "======================================="
