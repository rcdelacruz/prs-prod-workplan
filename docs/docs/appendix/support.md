# Support

## Overview

This guide provides support resources, contact information, and procedures for getting help with the PRS on-premises deployment.

## Self-Service Resources

### Documentation

**Primary Documentation**
- **[Getting Started](../getting-started/prerequisites.md)** - Initial setup and requirements
- **[Installation Guide](../installation/environment.md)** - Complete deployment procedures
- **[Operations Guide](../operations/daily.md)** - Daily maintenance and monitoring
- **[Troubleshooting](../deployment/troubleshooting.md)** - Problem resolution procedures

**Quick References**
- **[Command Reference](../reference/commands.md)** - Common commands and operations
- **[FAQ](faq.md)** - Frequently asked questions and solutions
- **[Configuration Reference](../configuration/application.md)** - Complete configuration guide

### Diagnostic Tools

#### System Health Check

```bash
# Run comprehensive health check
cd /opt/prs-deployment/scripts
./system-health-check.sh

# Check specific components
./system-health-check.sh --component database
./system-health-check.sh --component storage
./system-health-check.sh --component network
```

#### Log Analysis

```bash
# Application logs
docker logs prs-onprem-backend --tail 100
docker logs prs-onprem-frontend --tail 100
docker logs prs-onprem-nginx --tail 100

# System logs
sudo journalctl -u docker --since "1 hour ago"
sudo tail -f /var/log/syslog

# Database logs
docker logs prs-onprem-postgres-timescale --tail 50
```

#### Performance Analysis

```bash
# System performance
htop
iostat -x 1
iotop

# Container performance
docker stats

# Database performance
docker exec prs-onprem-postgres-timescale psql -U prs_admin -d prs_production -c "
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;
"
```

## Issue Reporting

### Before Reporting an Issue

1. **Check Documentation**
   - Review relevant documentation sections
   - Check the FAQ for similar issues
   - Follow troubleshooting procedures

2. **Gather Information**
   - Run system health check
   - Collect relevant logs
   - Note error messages and timestamps
   - Document steps to reproduce the issue

3. **Attempt Basic Resolution**
   - Restart affected services
   - Check system resources
   - Verify configuration settings

### Issue Report Template

When reporting an issue, please include the following information:

```
## Issue Summary
Brief description of the problem

## Environment Information
- OS Version: Ubuntu 22.04 LTS
- Docker Version: 20.10.x
- PRS Version: [version]
- Deployment Date: [date]

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Error Messages
```
[Include exact error messages]
```

## System Information
```
[Output from system-health-check.sh]
```

## Logs
```
[Relevant log entries with timestamps]
```

## Additional Context
Any other relevant information
```

### Log Collection Script

```bash
#!/bin/bash
# /opt/prs-deployment/scripts/collect-support-info.sh

SUPPORT_DIR="/tmp/prs-support-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SUPPORT_DIR"

echo "Collecting PRS support information..."

# System information
echo "=== System Information ===" > "$SUPPORT_DIR/system-info.txt"
uname -a >> "$SUPPORT_DIR/system-info.txt"
lsb_release -a >> "$SUPPORT_DIR/system-info.txt" 2>/dev/null
free -h >> "$SUPPORT_DIR/system-info.txt"
df -h >> "$SUPPORT_DIR/system-info.txt"

# Docker information
echo "=== Docker Information ===" > "$SUPPORT_DIR/docker-info.txt"
docker --version >> "$SUPPORT_DIR/docker-info.txt"
docker-compose --version >> "$SUPPORT_DIR/docker-info.txt"
docker ps >> "$SUPPORT_DIR/docker-info.txt"
docker stats --no-stream >> "$SUPPORT_DIR/docker-info.txt"

# Service logs
echo "Collecting service logs..."
docker logs prs-onprem-backend --tail 500 > "$SUPPORT_DIR/backend.log" 2>&1
docker logs prs-onprem-frontend --tail 500 > "$SUPPORT_DIR/frontend.log" 2>&1
docker logs prs-onprem-nginx --tail 500 > "$SUPPORT_DIR/nginx.log" 2>&1
docker logs prs-onprem-postgres-timescale --tail 500 > "$SUPPORT_DIR/postgres.log" 2>&1
docker logs prs-onprem-redis --tail 500 > "$SUPPORT_DIR/redis.log" 2>&1

# System logs
echo "Collecting system logs..."
sudo journalctl -u docker --since "24 hours ago" > "$SUPPORT_DIR/docker-system.log"
sudo tail -1000 /var/log/syslog > "$SUPPORT_DIR/syslog.log"

# Configuration (sanitized)
echo "Collecting configuration..."
cp 02-docker-configuration/.env "$SUPPORT_DIR/env-config.txt"
sed -i 's/PASSWORD=.*/PASSWORD=***REDACTED***/g' "$SUPPORT_DIR/env-config.txt"
sed -i 's/SECRET=.*/SECRET=***REDACTED***/g' "$SUPPORT_DIR/env-config.txt"

# Health check
echo "Running health check..."
./system-health-check.sh > "$SUPPORT_DIR/health-check.txt" 2>&1

# Create archive
tar -czf "${SUPPORT_DIR}.tar.gz" -C /tmp "$(basename "$SUPPORT_DIR")"
rm -rf "$SUPPORT_DIR"

echo "Support information collected: ${SUPPORT_DIR}.tar.gz"
echo "Please attach this file to your support request."
```

## Support Channels

### Internal Support

#### System Administrator
- **Primary Contact**: System Administrator
- **Scope**: System-level issues, hardware problems, network connectivity
- **Response Time**: 4 hours during business hours
- **Escalation**: IT Manager

#### Database Administrator
- **Primary Contact**: Database Administrator
- **Scope**: Database performance, backup/recovery, data integrity
- **Response Time**: 2 hours for critical issues
- **Escalation**: Senior DBA

#### Application Support
- **Primary Contact**: Development Team Lead
- **Scope**: Application functionality, user interface issues, business logic
- **Response Time**: 8 hours during business hours
- **Escalation**: Technical Manager

### External Support

#### Vendor Support

**TimescaleDB Support**
- **Contact**: TimescaleDB Community Forum
- **Website**: https://github.com/timescale/timescaledb/issues
- **Scope**: TimescaleDB-specific issues, performance optimization
- **Documentation**: https://docs.timescale.com/

**Docker Support**
- **Contact**: Docker Community Forum
- **Website**: https://forums.docker.com/
- **Scope**: Docker engine issues, container problems
- **Documentation**: https://docs.docker.com/

**Ubuntu Support**
- **Contact**: Ubuntu Community Support
- **Website**: https://askubuntu.com/
- **Scope**: Operating system issues, package management
- **Documentation**: https://help.ubuntu.com/

#### Professional Services

**Infrastructure Consulting**
- **Scope**: Performance optimization, scaling, architecture review
- **Engagement**: Project-based consulting
- **Deliverables**: Performance reports, optimization recommendations

**Security Auditing**
- **Scope**: Security assessment, compliance review, penetration testing
- **Engagement**: Annual security audit
- **Deliverables**: Security report, remediation plan

## Emergency Procedures

### Critical Issue Response

#### Severity Levels

**Critical (Severity 1)**
- System completely down
- Data loss or corruption
- Security breach
- **Response Time**: Immediate (within 1 hour)
- **Escalation**: Immediate notification to all stakeholders

**High (Severity 2)**
- Major functionality impaired
- Performance severely degraded
- Backup failures
- **Response Time**: 4 hours during business hours
- **Escalation**: Notification to management within 2 hours

**Medium (Severity 3)**
- Minor functionality issues
- Performance degradation
- Non-critical errors
- **Response Time**: 24 hours during business hours
- **Escalation**: Weekly status report

**Low (Severity 4)**
- Enhancement requests
- Documentation updates
- Minor configuration changes
- **Response Time**: 5 business days
- **Escalation**: Monthly review

#### Emergency Contacts

```
Primary On-Call: [Phone Number]
Secondary On-Call: [Phone Number]
Management Escalation: [Phone Number]
Security Team: [Phone Number]
```

### Emergency Recovery Procedures

#### System Recovery

```bash
# Emergency system restart
sudo systemctl restart docker
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml down
docker-compose -f 02-docker-configuration/docker-compose.onprem.yml up -d

# Emergency database recovery
./scripts/restore-database.sh /mnt/hdd/postgres-backups/daily/latest-backup.sql

# Emergency storage cleanup
sudo find /mnt/ssd -name "*.tmp" -delete
sudo find /mnt/ssd/logs -name "*.log" -mtime +1 -exec gzip {} \;
```

#### Data Recovery

```bash
# Point-in-time recovery
./scripts/restore-database.sh --point-in-time "2024-08-22 14:30:00"

# File recovery from backup
rsync -av /mnt/hdd/file-backups/latest/ /mnt/ssd/uploads/

# Configuration recovery
cp /mnt/hdd/config-backups/latest/docker-configuration/ 02-docker-configuration/
```

## Knowledge Base

### Common Solutions

#### Performance Issues
1. **High CPU Usage**
   - Check for runaway processes
   - Restart affected containers
   - Review database queries

2. **Memory Issues**
   - Clear system cache
   - Restart memory-intensive services
   - Check for memory leaks

3. **Storage Issues**
   - Clean temporary files
   - Compress old logs
   - Move data to appropriate tier

#### Connectivity Issues
1. **Network Problems**
   - Check firewall rules
   - Verify DNS resolution
   - Test network connectivity

2. **SSL Issues**
   - Verify certificate validity
   - Check certificate permissions
   - Renew expired certificates

3. **Database Connectivity**
   - Check database status
   - Verify connection pool
   - Test network connectivity

### Best Practices

#### Preventive Maintenance
- Run daily health checks
- Monitor system resources
- Keep backups current
- Apply security updates regularly

#### Performance Optimization
- Monitor database performance
- Optimize queries regularly
- Balance storage tiers
- Review system metrics

#### Security Maintenance
- Update security configurations
- Review access logs
- Monitor for vulnerabilities
- Conduct security audits

## Training and Documentation

### Training Resources

#### Administrator Training
- **System Administration**: Linux, Docker, networking
- **Database Management**: PostgreSQL, TimescaleDB, backup/recovery
- **Security**: Hardening, monitoring, incident response
- **Monitoring**: Grafana, Prometheus, alerting

#### User Training
- **Application Usage**: PRS functionality, workflows
- **Troubleshooting**: Basic problem resolution
- **Reporting**: Issue reporting procedures

### Documentation Maintenance

#### Regular Updates
- Monthly documentation review
- Quarterly procedure updates
- Annual comprehensive review
- Version control for all changes

#### Feedback Process
- User feedback collection
- Documentation improvement suggestions
- Regular usability reviews
- Continuous improvement process

---

!!! success "Support Available"
    Comprehensive support resources are available to ensure smooth operation of your PRS deployment.

!!! tip "Proactive Support"
    Use monitoring tools and regular health checks to identify and resolve issues before they impact users.

!!! warning "Emergency Preparedness"
    Ensure all team members are familiar with emergency procedures and have access to necessary contact information.
