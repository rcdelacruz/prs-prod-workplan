# 🖥️ Hardware Analysis and Optimization for On-Premises Deployment

## 📊 Current Infrastructure Assessment

### Client Hardware Specifications
- **RAM**: 16 GB (4x improvement over EC2 4GB)
- **Storage**: 
  - **SSD**: 470 GB RAID1 (23x improvement over EC2 20GB)
  - **HDD**: 2,400 TB RAID5 (120,000x improvement)
- **Network**: 1 Gbps interface
- **UPS**: Backup power available
- **Location**: Data Center Server Room

### EC2 Baseline Comparison
| Component | EC2 t4g.medium | On-Premises | Improvement Factor |
|-----------|----------------|-------------|-------------------|
| **CPU** | 2 vCPUs (ARM64) | 4+ cores (x86_64) | 2x+ |
| **RAM** | 4 GB | 16 GB | **4x** |
| **Storage** | 20 GB EBS | 470 GB SSD + 2.4 TB HDD | **12,000x+** |
| **Network** | Shared | Dedicated 1 Gbps | **10x+** |
| **Availability** | 99.5% | 99.9% (UPS) | **Better** |

## 🎯 Optimization Strategy

### Memory Allocation (16GB Total)
```
System Reserved:     2 GB  (12.5%)
Docker Engine:       1 GB  (6.25%)
Available for Apps: 13 GB  (81.25%)

Application Distribution:
├── PostgreSQL:      6 GB  (46%)
├── Backend API:     4 GB  (31%)
├── Redis:           2 GB  (15%)
├── Frontend:        1 GB  (8%)
└── Monitoring:      2 GB  (15%)
```

### Storage Strategy (SSD/HDD Tiering)
```
SSD (470 GB RAID1) - Hot Data:
├── PostgreSQL Hot Data:     200 GB
├── Redis Persistence:        50 GB
├── Application Uploads:     100 GB
├── System Logs:              50 GB
├── Nginx Cache:              20 GB
├── Monitoring Data:          30 GB
└── System Reserve:           20 GB

HDD (2,400 TB RAID5) - Cold Data:
├── PostgreSQL Cold Data:   1,000 GB
├── Backup Archives:        1,000 GB
├── Log Archives:             200 GB
├── NAS Sync Staging:         100 GB
└── Future Growth:          100+ TB
```

### Network Optimization
```
Internal Network: 192.168.0.0/20
├── Server IP: 192.168.16.100
├── Service Network: 192.168.100.0/24
├── Firewall: Hardware-managed
└── DNS: Internal + External fallback
```

## 🔧 Performance Tuning

### PostgreSQL Configuration (6GB RAM)
```sql
-- Memory Settings
shared_buffers = 2GB                    # 33% of allocated RAM
effective_cache_size = 4GB              # 67% of allocated RAM
work_mem = 32MB                         # For complex queries
maintenance_work_mem = 512MB            # For maintenance operations

-- Connection Settings
max_connections = 150                   # 5x increase from EC2
max_worker_processes = 32               # Utilize all CPU cores
max_parallel_workers = 16               # Parallel query execution
max_parallel_workers_per_gather = 4    # Per-query parallelism

-- Storage Settings
random_page_cost = 1.1                 # SSD optimization
effective_io_concurrency = 200         # SSD concurrent I/O
checkpoint_completion_target = 0.9     # Smooth checkpoints
wal_buffers = 32MB                     # WAL buffer size
```

### Redis Configuration (2GB RAM)
```
maxmemory 2gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
appendonly yes
appendfsync everysec
```

### Backend API Configuration (4GB RAM)
```javascript
// Node.js Memory Settings
--max-old-space-size=2048              // 2GB heap limit
--max-semi-space-size=128              // 128MB semi-space

// Connection Pool Settings
pool: {
  min: 5,                              // Minimum connections
  max: 20,                             // Maximum connections (vs 3 on EC2)
  acquire: 30000,                      // Connection timeout
  idle: 10000,                         // Idle timeout
  evict: 20000                         // Eviction timeout
}
```

## 📈 Performance Expectations

### Capacity Improvements
| Metric | EC2 Performance | On-Premises Target | Improvement |
|--------|-----------------|-------------------|-------------|
| **Concurrent Users** | 30 | 100 | **233%** |
| **Response Time** | 200-500ms | 50-200ms | **60-75%** |
| **Database Queries/sec** | 100 | 500 | **400%** |
| **File Upload Speed** | 10 MB/s | 50 MB/s | **400%** |
| **Backup Speed** | 5 MB/s | 100 MB/s | **1,900%** |

### TimescaleDB Performance
```
Data Ingestion Rate:
├── EC2: 10,000 rows/sec
└── On-Premises: 50,000 rows/sec (5x improvement)

Query Performance:
├── Recent Data (SSD): <50ms
├── Historical Data (HDD): <2s
└── Compressed Data: <5s

Storage Efficiency:
├── Compression Ratio: 80-90%
├── Hot Data Retention: 30 days
└── Cold Data: Unlimited (zero-deletion)
```

## 🔍 Monitoring and Alerting

### Resource Monitoring Thresholds
```yaml
CPU Usage:
  Warning: 70%
  Critical: 85%

Memory Usage:
  Warning: 75%
  Critical: 90%

SSD Storage:
  Warning: 80% (376 GB)
  Critical: 90% (423 GB)

HDD Storage:
  Warning: 70% (1,680 TB)
  Critical: 85% (2,040 TB)

Network Usage:
  Warning: 70% (700 Mbps)
  Critical: 90% (900 Mbps)
```

### Performance Metrics
```yaml
Application Response Time:
  Target: <200ms
  Warning: >500ms
  Critical: >1000ms

Database Query Time:
  Target: <100ms
  Warning: >500ms
  Critical: >2000ms

Error Rate:
  Target: <0.1%
  Warning: >1%
  Critical: >5%

Uptime:
  Target: 99.9%
  Warning: <99.5%
  Critical: <99%
```

## 🛠️ Hardware Optimization Recommendations

### Immediate Optimizations
1. **SSD Mount Options**: Use `noatime,discard` for better performance
2. **HDD Configuration**: Optimize RAID5 stripe size for large files
3. **Network Tuning**: Increase TCP buffer sizes for high throughput
4. **Kernel Parameters**: Optimize for database workloads

### Future Upgrades (Optional)
1. **RAM Expansion**: 16GB → 32GB for even better caching
2. **SSD Expansion**: Add dedicated SSD for TimescaleDB hot data
3. **Network Upgrade**: 1 Gbps → 10 Gbps for future growth
4. **CPU Upgrade**: More cores for parallel processing

## 📋 Hardware Validation Checklist

### Pre-Deployment Validation
- [ ] RAM: 16GB available and recognized
- [ ] SSD: 470GB RAID1 configured and mounted
- [ ] HDD: 2.4TB RAID5 configured and mounted
- [ ] Network: 1 Gbps interface active
- [ ] UPS: Backup power tested
- [ ] Cooling: Adequate for 24/7 operation

### Storage Performance Testing
```bash
# SSD Performance Test
sudo fio --name=ssd-test --filename=/mnt/ssd/test --size=10G --rw=randwrite --bs=4k --numjobs=4 --time_based --runtime=60

# HDD Performance Test  
sudo fio --name=hdd-test --filename=/mnt/hdd/test --size=10G --rw=write --bs=1M --numjobs=1 --time_based --runtime=60

# Network Performance Test
iperf3 -c target-server -t 60 -P 4
```

### Memory Performance Testing
```bash
# Memory Bandwidth Test
sudo apt install sysbench
sysbench memory --memory-total-size=10G run

# Memory Latency Test
sudo apt install intel-cmt-cat
pqos -m all:0-3
```

## 🎯 Success Criteria

### Performance Targets
- **Response Time**: 95% of requests under 200ms
- **Throughput**: Support 100 concurrent users
- **Uptime**: 99.9% availability
- **Data Growth**: Handle 20GB/day sustainably

### Resource Utilization Targets
- **CPU**: Average <60%, Peak <85%
- **Memory**: Average <75%, Peak <90%
- **SSD**: <80% utilization
- **HDD**: <70% utilization
- **Network**: <50% utilization

---

**Document Version**: 1.0  
**Created**: 2025-08-13  
**Last Updated**: 2025-08-13  
**Status**: Production Ready
