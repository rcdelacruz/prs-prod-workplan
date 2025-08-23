# Frequently Asked Questions

## General Questions

### What is the PRS on-premises deployment?

**A:** The PRS (Procurement and Requisition System) on-premises deployment is a complete enterprise-grade solution that runs on your own hardware infrastructure. It provides:

- **100+ concurrent user support** (vs 30 on cloud)
- **Dual storage architecture** (SSD for performance, HDD for capacity)
- **Zero-deletion data policy** with TimescaleDB
- **Enterprise security** and compliance
- **Complete data ownership** and control

### What are the main benefits over cloud deployment?

**A:** Key improvements include:

| Metric | Cloud | On-Premises | Improvement |
|--------|-------|-------------|-------------|
| **Concurrent Users** | 30 | 100+ | **233%** |
| **Response Time** | 200-500ms | 50-200ms | **60-75%** |
| **Storage Capacity** | 20 GB | 2.4+ TB | **12,000%** |
| **Database Performance** | 100 queries/sec | 500+ queries/sec | **400%** |

### How does the zero-deletion policy work?

**A:** The system never deletes data. Instead, it uses:

1. **Automatic Compression**: Reduces storage by 60-80%
2. **Data Tiering**: Moves old data from SSD to HDD automatically
3. **Transparent Access**: Applications query data normally regardless of storage tier
4. **Compliance Ready**: Meets regulatory requirements for data retention

## Architecture Questions

### How does the dual storage system work?

**A:** The system automatically manages data across two storage tiers:

- **SSD Storage (470GB)**: Hot data (0-30 days), fast access (<50ms)
- **HDD Storage (2.4TB)**: Cold data (30+ days), slower access (<2s)

TimescaleDB automatically moves data between tiers based on age and access patterns. Your application never needs to know which tier contains the data.

### What happens when SSD storage fills up?

**A:** The system has multiple automatic safeguards:

1. **Automatic Compression**: Compresses data after 7-30 days (saves 60-80% space)
2. **Automatic Movement**: Moves data older than 30 days to HDD
3. **Emergency Procedures**: Manual compression and movement if needed
4. **Monitoring Alerts**: Warns at 80% usage, critical at 90%

### Can I scale the system horizontally?

**A:** Yes, the system supports several scaling options:

- **Application Scaling**: Multiple backend instances with load balancing
- **Database Scaling**: Read replicas for reporting workloads
- **Storage Scaling**: Additional SSD/HDD tiers
- **Network Scaling**: Link aggregation and 10Gbps upgrades

## Technical Questions

### What operating systems are supported?

**A:** Supported operating systems include:

- **Ubuntu 20.04 LTS or later** (Recommended: Ubuntu 22.04 LTS)
- **CentOS 8 or later**
- **RHEL 8 or later**
- **Debian 11 or later**

### What are the minimum hardware requirements?

**A:** Minimum requirements:

- **CPU**: 4 cores (8+ recommended)
- **RAM**: 16 GB (32 GB recommended)
- **SSD**: 470 GB RAID1 (1 TB recommended)
- **HDD**: 2.4 TB RAID5 (5+ TB recommended)
- **Network**: 1 Gbps (10 Gbps recommended)

### How long does deployment take?

**A:** Deployment timeline:

- **Environment Setup**: 30 minutes
- **Complete Deployment**: 2-3 hours
- **Testing and Validation**: 1-2 hours
- **Total**: 4-6 hours for complete setup

### Can I migrate from cloud to on-premises?

**A:** Yes, migration is supported with:

1. **Database Export**: Export cloud database to SQL
2. **File Transfer**: Copy uploaded files and attachments
3. **Configuration Migration**: Transfer settings and configurations
4. **Data Validation**: Verify data integrity after migration
5. **Cutover**: Switch DNS and go live

## Security Questions

### How secure is the on-premises deployment?

**A:** Security features include:

- **SSL/TLS Encryption**: All communications encrypted
- **Firewall Protection**: Network-level security
- **Access Controls**: Role-based permissions
- **Security Hardening**: System-level security measures
- **Audit Logging**: Complete activity tracking
- **Regular Updates**: Security patches and updates

### How are passwords and secrets managed?

**A:** Security best practices:

- **Auto-generated Secrets**: Cryptographically secure random generation
- **Environment Variables**: Secrets stored in protected environment files
- **No Hardcoded Passwords**: All credentials configurable
- **Regular Rotation**: Automated password rotation capabilities

### What compliance standards does it meet?

**A:** The system supports:

- **Data Retention**: Zero-deletion policy for compliance
- **Audit Trails**: Complete activity logging
- **Access Controls**: Role-based permissions
- **Data Encryption**: At-rest and in-transit encryption
- **Backup Requirements**: Automated backup procedures

## Data Management Questions

### How does backup and recovery work?

**A:** Comprehensive backup strategy:

- **Daily Full Backups**: Complete database backups
- **Incremental Backups**: Every 6 hours
- **Real-time WAL**: Continuous transaction log archiving
- **File Backups**: Daily upload and configuration backups
- **Point-in-Time Recovery**: Restore to any point in time

### What happens if hardware fails?

**A:** Redundancy and recovery:

- **RAID Protection**: SSD RAID1 and HDD RAID5
- **UPS Power**: Uninterruptible power supply
- **Automated Backups**: Multiple backup copies
- **Quick Recovery**: Restore procedures documented
- **Hardware Replacement**: Hot-swappable components

### How much data can the system handle?

**A:** Scalability limits:

- **Current Capacity**: 2.4TB+ with room for expansion
- **Daily Growth**: 20GB+ sustainable
- **User Capacity**: 100+ concurrent users
- **Transaction Volume**: 500+ database queries/second
- **Unlimited Expansion**: Add more HDD storage as needed

## Operations Questions

### What maintenance is required?

**A:** Maintenance schedule:

- **Daily**: Automated health checks and backups
- **Weekly**: Performance monitoring and log rotation
- **Monthly**: Security updates and capacity planning
- **Quarterly**: Full system maintenance and optimization

### How do I monitor system health?

**A:** Monitoring tools:

- **Grafana Dashboards**: Real-time metrics and alerts
- **Prometheus Metrics**: System and application monitoring
- **Health Check Scripts**: Automated system validation
- **Log Analysis**: Centralized logging and analysis
- **Email Alerts**: Automated notification system

### What if I need support?

**A:** Support options:

- **Documentation**: Comprehensive guides and references
- **Health Checks**: Automated problem detection
- **Troubleshooting Guides**: Step-by-step problem resolution
- **Command Reference**: Quick access to common commands
- **Emergency Procedures**: Critical issue resolution

## Performance Questions

### How fast is the system compared to cloud?

**A:** Performance improvements:

- **Response Time**: 60-75% faster (50-200ms vs 200-500ms)
- **Database Queries**: 400% faster (500+ vs 100 queries/sec)
- **File Uploads**: 400% faster (50 MB/s vs 10 MB/s)
- **Concurrent Users**: 233% more (100+ vs 30 users)

### What causes performance issues?

**A:** Common performance factors:

- **High CPU Usage**: >85% sustained usage
- **Memory Pressure**: >90% memory utilization
- **Storage Full**: SSD >90% or HDD >85%
- **Network Congestion**: >90% bandwidth utilization
- **Database Locks**: Long-running queries or transactions

### How can I optimize performance?

**A:** Performance optimization:

- **Resource Monitoring**: Track CPU, memory, storage, network
- **Query Optimization**: Analyze and optimize slow database queries
- **Index Management**: Ensure proper database indexing
- **Cache Tuning**: Optimize Redis cache configuration
- **Storage Management**: Balance data across SSD/HDD tiers

## Troubleshooting Questions

### Services won't start - what should I check?

**A:** Troubleshooting steps:

1. **Check Docker**: `docker --version` and `docker-compose --version`
2. **Check Logs**: `docker-compose logs service-name`
3. **Check Resources**: `df -h` and `free -h`
4. **Check Permissions**: Verify storage directory permissions
5. **Check Configuration**: Validate environment variables

### Database connection fails - how to fix?

**A:** Database troubleshooting:

1. **Check Status**: `docker exec prs-onprem-postgres-timescale pg_isready`
2. **Check Logs**: `docker logs prs-onprem-postgres-timescale`
3. **Check Connections**: Verify connection pool settings
4. **Check Credentials**: Validate database username/password
5. **Restart Service**: `docker-compose restart postgres backend`

### SSL certificate issues - how to resolve?

**A:** SSL troubleshooting:

1. **Check Certificate**: `openssl x509 -in certificate.crt -text -noout`
2. **Check Expiration**: `openssl x509 -in certificate.crt -noout -dates`
3. **Regenerate Certificate**: `./scripts/ssl-automation-citylandcondo.sh --force`
4. **Check Nginx Config**: Verify SSL configuration in nginx
5. **Restart Nginx**: `docker-compose restart nginx`

### System running slowly - how to diagnose?

**A:** Performance diagnosis:

1. **Check Resources**: `htop`, `free -h`, `df -h`
2. **Check Containers**: `docker stats`
3. **Check Database**: Look for slow queries and locks
4. **Check Network**: Monitor bandwidth and connections
5. **Check Logs**: Look for errors and warnings

## Scaling Questions

### When should I consider scaling?

**A:** Scaling indicators:

- **CPU Usage**: Consistently >70%
- **Memory Usage**: Consistently >80%
- **Storage Usage**: SSD >80% or HDD >70%
- **Response Time**: >500ms average
- **User Complaints**: Performance issues reported

### How do I add more storage?

**A:** Storage expansion:

1. **SSD Expansion**: Add drives to RAID1 array
2. **HDD Expansion**: Add drives to RAID5 array
3. **New Tiers**: Create additional storage tiers
4. **Update Configuration**: Modify Docker volumes
5. **Test Performance**: Validate improved performance

### Can I add more servers?

**A:** Horizontal scaling:

1. **Load Balancer**: Configure nginx load balancing
2. **Application Servers**: Deploy additional backend instances
3. **Database Replicas**: Set up read replicas for reporting
4. **Shared Storage**: Configure shared file storage
5. **Session Management**: Use Redis for session sharing

---

!!! tip "Getting Help"
    If you can't find the answer to your question here, check the [Troubleshooting Guide](../deployment/troubleshooting.md) or [Support](support.md) section.

!!! info "Documentation Updates"
    This FAQ is regularly updated based on common questions and issues. Suggest improvements through the support channels.
