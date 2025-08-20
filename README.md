# 🏢 PRS On-Premises Production Deployment Workplan

## 📋 Project Overview

This comprehensive workplan provides a complete deployment strategy for the PRS (Property Registration System) on client's on-premises infrastructure. The deployment is systematically adapted from the existing AWS EC2 Graviton production setup to work optimally in an on-premises environment with 16GB RAM, dual storage (SSD/HDD), and 100 concurrent users.

## 🖥️ Client Infrastructure Specifications

### Hardware Configuration
- **RAM**: 16 GB (4x increase from EC2 setup)
- **Storage**:
  - **SSD**: 470 GB (RAID1 configuration) - Hot data and performance
  - **HDD**: 2,400 TB (RAID5 configuration) - Cold data and backups
- **Network**: 1 Gbps interface
- **UPS**: Backup power available
- **Location**: Data Center Server Room

### Network Configuration
- **Internal Network**: 192.168.0.0/20 (4,094 available IPs)
- **Firewall**: Hardware-based (managed by IT team)
- **Intrusion Detection**: Yes
- **Network Segmentation**: No
- **Expected Load**: 100 concurrent users

### Backup Infrastructure
- **Backup Storage**: NAS
- **Backup Capacity**: 2 TB
- **Backup Policy**: Zero-deletion database policy
- **Backup Frequency**: Weekly database backups

### Operating System
- **OS**: Ubuntu 24.04 LTS

## 🎯 Deployment Objectives

1. **Complete Migration**: Adapt all 11 services from EC2 setup to on-premises
2. **Performance Optimization**: Leverage 16GB RAM for 4x performance improvement
3. **Storage Strategy**: Implement intelligent SSD/HDD tiering for TimescaleDB
4. **Network Integration**: Seamless integration with existing 192.168.0.0/20 network
5. **Security Compliance**: Replace Cloudflare Tunnel with Let's Encrypt SSL
6. **Zero-Deletion Policy**: Implement comprehensive backup strategy with NAS
7. **Scalability**: Support 100 concurrent users (3x increase from EC2)
8. **Monitoring**: Complete Grafana/Prometheus stack adaptation
9. **Automation**: Adapt all 37 production scripts for on-premises use

## 🏗️ Architecture Adaptation

### Service Migration Overview

| Service | EC2 Configuration | On-Premises Adaptation | Memory Allocation |
|---------|------------------|------------------------|-------------------|
| **Nginx** | 128MB, localhost only | 256MB, internal network | 256MB |
| **Backend API** | 1GB, 30 connections | 4GB, 150 connections | 4GB |
| **Frontend** | 512MB | 1GB, enhanced caching | 1GB |
| **PostgreSQL + TimescaleDB** | 1.5GB, 128MB buffers | 6GB, 2GB buffers | 6GB |
| **Redis** | 512MB | 2GB, enhanced persistence | 2GB |
| **Redis Worker** | 512MB | 1GB, more background jobs | 1GB |
| **Prometheus** | 256MB, 3d retention | 1GB, 30d retention | 1GB |
| **Grafana** | 256MB | 1GB, enhanced dashboards | 1GB |
| **Adminer** | 64MB | 128MB | 128MB |
| **Portainer** | 128MB | 256MB | 256MB |
| **Node Exporter** | 64MB | 128MB | 128MB |

### Network Architecture Changes

```
EC2 Setup (Cloudflare Tunnel):
Internet → Cloudflare → Tunnel → localhost:ports

On-Premises Setup (Internal Network):
Internal Network (192.168.0.0/20) → Hardware Firewall → Server (192.168.16.100) → Services
```

### Storage Architecture

```
EC2 Setup (Single EBS):
Single 20GB EBS Volume → All data

On-Premises Setup (Dual Storage):
SSD (470GB RAID1):
├── Hot TimescaleDB data (0-30 days)
├── Database active chunks
├── Redis persistence
├── Application uploads
└── System logs

HDD (2,400TB RAID5):
├── Cold TimescaleDB data (30+ days)
├── Compressed chunks
├── Backup archives
├── Log archives
└── NAS sync staging
```

## 📁 Workplan Structure

```
prod-workplan/
├── README.md                           # This overview document
├── 01-hardware-analysis/               # Hardware optimization analysis
├── 02-docker-configuration/            # Complete Docker setup adaptation
│   ├── docker-compose.onprem.yml      # Adapted from 553-line EC2 version
│   ├── .env.onprem.example             # Adapted from 287-line EC2 version
│   ├── config/                         # Grafana & Prometheus configs
│   ├── nginx/                          # Nginx configuration files
│   ├── ssl/                            # SSL certificate management
│   └── scripts/                        # Container management scripts
├── 03-network-setup/                   # Network and SSL configuration
├── 04-backup-strategy/                 # Zero-deletion backup implementation
├── 05-security-configuration/          # Security hardening (no Cloudflare)
├── 06-installation-scripts/            # Automated deployment scripts
├── 07-monitoring-maintenance/          # Complete monitoring stack
├── 08-deployment-procedures/           # Step-by-step deployment guide
├── 09-scripts-adaptation/              # All 37 scripts adapted for on-premises
├── 10-documentation-guides/            # All 15 guides adapted from EC2
└── 99-templates-examples/              # Configuration templates
```

## 🚀 Key Adaptations from EC2 Setup

### 1. **Service Configuration Changes**
- **Remove Cloudflare Tunnel**: Replace with direct internal network access
- **Increase Memory Allocations**: Optimize for 16GB RAM vs 4GB
- **Enhance Connection Pools**: Support 100 users vs 30
- **Implement Dual Storage**: SSD/HDD tiering for TimescaleDB

### 2. **Network Access Changes**
- **From**: `127.0.0.1:port` (localhost only)
- **To**: `192.168.16.100:port` (internal network)
- **SSL**: Let's Encrypt certificates instead of Cloudflare SSL

### 3. **Storage Strategy Changes**
- **From**: Single EBS volume
- **To**: Intelligent SSD/HDD tiering with TimescaleDB optimization

### 4. **Backup Strategy Changes**
- **From**: Manual backup scripts
- **To**: Automated zero-deletion policy with NAS integration

### 5. **Monitoring Enhancements**
- **Prometheus**: Extended retention (3d → 30d)
- **Grafana**: Enhanced dashboards for on-premises metrics
- **Node Exporter**: System monitoring for physical hardware

## 📊 Performance Expectations

### Capacity Improvements
| Metric | EC2 Setup | On-Premises | Improvement |
|--------|-----------|-------------|-------------|
| **Concurrent Users** | 30 | 100 | **233%** |
| **Database Connections** | 30 | 150 | **400%** |
| **Memory Available** | 3.2GB | 14GB | **338%** |
| **Database Buffers** | 128MB | 2GB | **1,500%** |
| **Storage Capacity** | 20GB | 470GB + 2,400TB | **12,000%+** |
| **Response Time** | 200-500ms | 50-200ms | **60-75%** |

### TimescaleDB Performance
- **Chunk Management**: Intelligent SSD/HDD distribution
- **Compression**: Automated compression policies for space optimization
- **Query Performance**: Hot data on SSD, cold data on HDD
- **Backup Speed**: Dedicated backup storage on HDD

## 🔄 Migration Strategy

### Phase 1: Infrastructure Preparation (Week 1)
- Hardware setup and storage configuration
- Network integration and firewall rules
- SSL certificate setup with Let's Encrypt

### Phase 2: Service Deployment (Week 2)
- Docker environment setup
- Service configuration and testing
- Database migration and optimization

### Phase 3: Data Migration (Week 3)
- TimescaleDB data transfer
- Backup verification
- Performance testing

### Phase 4: Production Cutover (Week 4)
- Final testing and validation
- User acceptance testing
- Go-live and monitoring

## 📞 Support and Maintenance

### IT Team Responsibilities
- **Hardware Firewall**: Rule management and monitoring
- **Network**: Internal network access and DNS
- **Backup Verification**: NAS backup validation
- **SSL Certificates**: Let's Encrypt renewal coordination

### Automated Operations
- **Daily**: Incremental backups and log rotation
- **Weekly**: Full database backups and system maintenance
- **Monthly**: Archive creation and capacity planning
- **Quarterly**: Security updates and performance optimization

---

**Document Version**: 2.0
**Created**: 2025-08-13
**Last Updated**: 2025-08-13
**Status**: Complete Rebuild in Progress

**Migration Scope**:
- 11 Services adapted from EC2
- 37 Scripts adapted for on-premises
- 15 Documentation guides updated
- Complete monitoring stack migration
- Zero-deletion backup implementation

This workplan details the deployment of the PRS (Property Registration System) to a client's on-premises server infrastructure. The deployment is adapted from our existing AWS EC2 Graviton setup to work optimally in an on-premises environment.

## 🖥️ Client Infrastructure Specifications

### Hardware Configuration
- **RAM**: 16 GB
- **Storage**:
  - **SSD**: 470 GB (RAID1 configuration)
  - **HDD**: 2,400 TB (RAID5 configuration)
- **Network**: 1 Gbps interface
- **UPS**: Backup power available
- **Location**: Data Center Server Room

### Network Configuration
- **Internal Network**: 192.168.0.0/20 (4,094 available IPs)
- **Firewall**: Hardware-based (managed by IT team)
- **Intrusion Detection**: Yes
- **Network Segmentation**: No
- **Expected Load**: 100 concurrent users

### Backup Infrastructure
- **Backup Storage**: NAS
- **Backup Capacity**: 2 TB
- **Backup Policy**: Zero-deletion database policy
- **Backup Frequency**: Weekly database backups

### Operating System
- **OS**: Ubuntu 24.04 LTS

## 🎯 Deployment Objectives

1. **Performance Optimization**: Leverage 16GB RAM for optimal performance
2. **Storage Strategy**: Utilize SSD for database and application files, HDD for long-term storage and backups
3. **Network Integration**: Seamless integration with existing 192.168.0.0/20 network
4. **Security Compliance**: Work within existing firewall and security infrastructure
5. **SSL Certificates**: Use Let's Encrypt certificates with client's subdomain
6. **Backup Reliability**: Implement robust backup strategy using available NAS storage
7. **Scalability**: Support 100 concurrent users

## 📁 Workplan Structure

```
prod-workplan/
├── README.md                           # This overview document
├── 01-hardware-analysis/               # Hardware requirements and optimization
├── 02-docker-configuration/            # Adapted Docker Compose and configs
├── 03-network-setup/                   # Network configuration and SSL
├── 04-backup-strategy/                 # Backup and recovery procedures
├── 05-security-configuration/          # Security hardening and compliance
├── 06-installation-scripts/            # Automated deployment scripts
├── 07-monitoring-maintenance/          # Monitoring and maintenance procedures
├── 08-deployment-procedures/           # Step-by-step deployment guide
└── 99-templates-examples/              # Configuration templates and examples
```

## 🚀 Key Infrastructure Features

### Memory Optimization
- **16GB RAM**: Optimized allocation for database, application, and caching services
- **Large Buffer Pools**: PostgreSQL shared_buffers increased to 2GB for better performance

### Storage Strategy
- **Dual Storage**: SSD for performance-critical data, HDD for capacity and backups
- **RAID Protection**: RAID1 for SSD, RAID5 for HDD ensuring data redundancy

### Network Access
- **Internal Network**: Direct access within 192.168.0.0/20 network
- **Hardware Firewall**: Enterprise-grade security with IT team management
- **Let's Encrypt SSL**: Automated certificate management with client's subdomain

### Backup Approach
- **Automated Backups**: Scheduled daily, weekly, and monthly backup operations
- **NAS Integration**: Zero-deletion policy with 2TB NAS storage
- **Point-in-Time Recovery**: Complete recovery capabilities

## 📊 Performance Expectations

With the optimized hardware specifications:
- **Concurrent Users**: 100 users with excellent response times
- **Database Performance**: High-performance operations with 2GB shared buffers
- **Response Times**: Sub-200ms response times due to SSD storage and 16GB RAM
- **Backup Speed**: Fast backups to dedicated NAS storage with minimal impact

## 🔄 Migration Strategy

1. **Phase 1**: Infrastructure preparation and testing
2. **Phase 2**: Application deployment and configuration
3. **Phase 3**: Data migration and validation
4. **Phase 4**: Production cutover and monitoring

## 📞 Support and Maintenance

- **Primary Contact**: Client IT Team
- **Backup Management**: Automated with manual verification
- **Monitoring**: Grafana/Prometheus dashboard for IT team
- **Updates**: Coordinated deployment schedule

---

**Document Version**: 1.0
**Created**: 2025-08-13
**Last Updated**: 2025-08-13
**Status**: In Development
