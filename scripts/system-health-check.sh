#!/bin/bash
# PRS Production Server - System Health Check and Optimization Script

set -e

echo "=== PRS Production Server Health Check ==="
echo "Timestamp: $(date)"
echo

# System resource utilization
echo "=== System Resources ==="
echo "Memory Usage:"
free -h
echo
echo "Disk Usage:"
df -h | grep -E "(/$|/mnt)"
echo
echo "CPU Load:"
uptime
echo
echo "CPU Usage (last 1 minute):"
top -bn1 | head -3
echo

# Docker resources
echo "=== Docker Resources ==="
if command -v docker &> /dev/null && docker info &> /dev/null; then
    echo "Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" 2>/dev/null || echo "No containers running"
    echo
    echo "Docker system info:"
    docker system df 2>/dev/null || echo "Docker system info unavailable"
    echo
fi

# Network connections
echo "=== Network Status ==="
echo "Active connections by service:"
ss -tuln | grep -E "(80|443|22|5432|6379|9090|3001|8080|9000)" || echo "No matching connections found"
echo

# System limits
echo "=== System Limits ==="
echo "Current user limits:"
ulimit -a | grep -E "(open files|max user processes)"
echo

# Log analysis
echo "=== System Logs (Last 10 errors) ==="
journalctl --since "1 hour ago" -p err --no-pager -n 10 2>/dev/null | tail -10 || echo "No recent errors"
echo

# Performance recommendations
echo "=== Performance Recommendations ==="

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100}')
if [ "$MEMORY_USAGE" -gt 80 ]; then
    echo "⚠️  High memory usage: ${MEMORY_USAGE}% - Consider scaling down services or adding more RAM"
else
    echo "✅ Memory usage: ${MEMORY_USAGE}% (Good)"
fi

# Check disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    echo "⚠️  High disk usage: ${DISK_USAGE}% - Consider cleanup or expanding storage"
else
    echo "✅ Disk usage: ${DISK_USAGE}% (Good)"
fi

# Check load average
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
LOAD_THRESHOLD=$(nproc)
if (( $(echo "$LOAD_AVG > $LOAD_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
    echo "⚠️  High load average: $LOAD_AVG (threshold: $LOAD_THRESHOLD) - Consider optimizing or scaling"
else
    echo "✅ Load average: $LOAD_AVG (Good)"
fi

echo "✅ Health check completed"
echo "=== End Health Check ==="
