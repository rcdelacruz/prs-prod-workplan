# 📊 Monitoring and Maintenance Setup for On-Premises Deployment

## 🎯 Overview

This document outlines the comprehensive monitoring and maintenance setup for the PRS on-premises deployment, adapted from the EC2 Graviton monitoring stack to work optimally with 16GB RAM and dual storage architecture.

## 🏗️ Monitoring Architecture

### Monitoring Stack Components
```
Data Collection Layer:
├── Node Exporter (System metrics)
├── PostgreSQL Exporter (Database metrics)
├── Redis Exporter (Cache metrics)
├── Nginx Exporter (Web server metrics)
└── Custom Application Metrics

Storage Layer:
├── Prometheus (Time-series database)
├── Long-term storage on HDD
└── Hot data on SSD

Visualization Layer:
├── Grafana (Dashboards and alerts)
├── Custom dashboards for on-premises
└── Alert manager integration

Alerting Layer:
├── Prometheus AlertManager
├── Email notifications
└── Webhook integrations
```

## 📈 Prometheus Configuration

### Prometheus Configuration File
```yaml
# /opt/prs/config/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    environment: 'onprem-production'
    datacenter: 'client-datacenter'

rule_files:
  - "rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter (System metrics)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 30s

  # Backend API metrics
  - job_name: 'prs-backend'
    static_configs:
      - targets: ['backend:4000']
    metrics_path: '/metrics'
    scrape_interval: 30s

  # PostgreSQL metrics
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
    scrape_interval: 30s

  # Redis metrics
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
    scrape_interval: 30s

  # Nginx metrics
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
    scrape_interval: 30s

  # Docker container metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
    scrape_interval: 30s
```

### Prometheus Alert Rules
```yaml
# /opt/prs/config/prometheus/rules/alerts.yml
groups:
  - name: system_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 85% for more than 5 minutes"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% for more than 5 minutes"

      - alert: SSDStorageHigh
        expr: (node_filesystem_size_bytes{mountpoint="/mnt/ssd"} - node_filesystem_avail_bytes{mountpoint="/mnt/ssd"}) / node_filesystem_size_bytes{mountpoint="/mnt/ssd"} * 100 > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "SSD storage usage high"
          description: "SSD storage usage is above 80%"

      - alert: HDDStorageHigh
        expr: (node_filesystem_size_bytes{mountpoint="/mnt/hdd"} - node_filesystem_avail_bytes{mountpoint="/mnt/hdd"}) / node_filesystem_size_bytes{mountpoint="/mnt/hdd"} * 100 > 70
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HDD storage usage high"
          description: "HDD storage usage is above 70%"

  - name: application_alerts
    rules:
      - alert: ApplicationDown
        expr: up{job="prs-backend"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PRS Backend is down"
          description: "PRS Backend application is not responding"

      - alert: DatabaseDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL database is not responding"

      - alert: HighResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response time detected"
          description: "95th percentile response time is above 1 second"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100 > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is above 5% for more than 5 minutes"
```

## 📊 Grafana Configuration

### Grafana Configuration File
```ini
# /opt/prs/config/grafana/grafana.ini
[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = grafana.client-domain.com
root_url = https://grafana.client-domain.com

[database]
type = postgres
host = postgres:5432
name = prs_production
user = prs_user
password = ${POSTGRES_PASSWORD}
ssl_mode = disable

[security]
admin_user = admin
admin_password = ${GRAFANA_ADMIN_PASSWORD}
secret_key = ${GRAFANA_SECRET_KEY}
disable_gravatar = true
cookie_secure = true
cookie_samesite = strict

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth]
disable_login_form = false
disable_signout_menu = false

[auth.anonymous]
enabled = false

[snapshots]
external_enabled = false

[alerting]
enabled = true
execute_alerts = true

[smtp]
enabled = true
host = ${SMTP_HOST}:${SMTP_PORT}
user = ${SMTP_USER}
password = ${SMTP_PASSWORD}
from_address = grafana@client-domain.com
from_name = PRS Monitoring

[log]
mode = console file
level = info
```

### Grafana Datasource Provisioning
```yaml
# /opt/prs/config/grafana/provisioning/datasources/prometheus.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: "30s"
      queryTimeout: "60s"
      httpMethod: "POST"

  - name: PostgreSQL
    type: postgres
    access: proxy
    url: postgres:5432
    database: prs_production
    user: prs_monitor
    secureJsonData:
      password: ${POSTGRES_MONITOR_PASSWORD}
    jsonData:
      sslmode: "disable"
      maxOpenConns: 0
      maxIdleConns: 2
      connMaxLifetime: 14400
```

## 📱 Custom Dashboards

### System Overview Dashboard
```json
{
  "dashboard": {
    "title": "PRS On-Premises System Overview",
    "tags": ["prs", "onprem", "system"],
    "panels": [
      {
        "title": "CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100",
            "legendFormat": "Memory Usage %"
          }
        ]
      },
      {
        "title": "SSD Storage Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(node_filesystem_size_bytes{mountpoint=\"/mnt/ssd\"} - node_filesystem_avail_bytes{mountpoint=\"/mnt/ssd\"}) / node_filesystem_size_bytes{mountpoint=\"/mnt/ssd\"} * 100",
            "legendFormat": "SSD Usage %"
          }
        ]
      },
      {
        "title": "HDD Storage Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(node_filesystem_size_bytes{mountpoint=\"/mnt/hdd\"} - node_filesystem_avail_bytes{mountpoint=\"/mnt/hdd\"}) / node_filesystem_size_bytes{mountpoint=\"/mnt/hdd\"} * 100",
            "legendFormat": "HDD Usage %"
          }
        ]
      }
    ]
  }
}
```

## 🔧 Maintenance Procedures

### Daily Maintenance Tasks
```bash
#!/bin/bash
# /opt/prs/maintenance/daily-maintenance.sh

# Check system health
echo "=== Daily System Health Check ===" >> /var/log/prs-maintenance.log
date >> /var/log/prs-maintenance.log

# Check disk usage
df -h | grep -E "(ssd|hdd)" >> /var/log/prs-maintenance.log

# Check memory usage
free -h >> /var/log/prs-maintenance.log

# Check Docker containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >> /var/log/prs-maintenance.log

# Check database connections
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';" >> /var/log/prs-maintenance.log

# Rotate logs
find /mnt/ssd/logs -name "*.log" -mtime +7 -exec mv {} /mnt/hdd/logs-archive/ \;

# Clean up old Docker images
docker image prune -f

echo "Daily maintenance completed" >> /var/log/prs-maintenance.log
```

### Weekly Maintenance Tasks
```bash
#!/bin/bash
# /opt/prs/maintenance/weekly-maintenance.sh

# Update system packages
sudo apt update && sudo apt upgrade -y

# Restart services for memory cleanup
docker-compose -f /opt/prs/docker-compose.onprem.yml restart redis
docker-compose -f /opt/prs/docker-compose.onprem.yml restart redis-worker

# Database maintenance
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "VACUUM ANALYZE;"

# Check SSL certificate expiry
openssl x509 -in /opt/prs/ssl/server.crt -noout -dates

# Generate weekly report
/opt/prs/maintenance/generate-weekly-report.sh

echo "Weekly maintenance completed" >> /var/log/prs-maintenance.log
```

### Monthly Maintenance Tasks
```bash
#!/bin/bash
# /opt/prs/maintenance/monthly-maintenance.sh

# Full system backup
/opt/prs/backup-scripts/monthly-backup.sh

# Security updates
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y

# Database optimization
docker exec prs-onprem-postgres-timescale psql -U prs_user -d prs_production -c "REINDEX DATABASE prs_production;"

# Clean up old backups (keep 12 months)
find /mnt/hdd/backups -name "monthly_*" -mtime +365 -delete

# Generate monthly report
/opt/prs/maintenance/generate-monthly-report.sh

echo "Monthly maintenance completed" >> /var/log/prs-maintenance.log
```

## 📧 Alert Configuration

### Email Alert Setup
```yaml
# /opt/prs/config/alertmanager/alertmanager.yml
global:
  smtp_smarthost: '${SMTP_HOST}:${SMTP_PORT}'
  smtp_from: 'alerts@client-domain.com'
  smtp_auth_username: '${SMTP_USER}'
  smtp_auth_password: '${SMTP_PASSWORD}'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    email_configs:
      - to: 'admin@client-domain.com'
        subject: 'PRS Alert: {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}
```

---

**Document Version**: 1.0  
**Created**: 2025-08-13  
**Last Updated**: 2025-08-13  
**Status**: Production Ready
