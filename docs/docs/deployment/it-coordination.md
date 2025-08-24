# IT Network Admin Coordination Guide

## Overview

This guide provides specific instructions for IT network administrators to support PRS deployment with custom domain SSL certificates, particularly for `*.citylandcondo.com` domains using GoDaddy DNS management.

## Prerequisites

Before proceeding, ensure you have:
- **Administrative access** to GoDaddy DNS management
- **Router/firewall configuration** access for port forwarding
- **Office public IP address** (static IP required)
- **Internal network** configured (192.168.0.0/20)

## Required IT Coordination Tasks

### Task 1: DNS Configuration (One-time Setup)

#### GoDaddy DNS Management

1. **Login to GoDaddy**:
   - Access your GoDaddy account
   - Navigate to "My Products" → "DNS"
   - Select the `citylandcondo.com` domain

2. **Create DNS A Record**:
   ```
   Record Type: A
   Name: prs
   Value: [Your office public IP address]
   TTL: 1 Hour (3600 seconds)
   ```

   !!! warning "Public IP Required"
       Replace `[Your office public IP address]` with your actual static public IP. This is **absolutely required** for SSL certificate validation.

3. **Verify DNS Configuration**:
   ```bash
   # Test DNS resolution
   nslookup prs.citylandcondo.com 8.8.8.8
   
   # Should return your office public IP
   dig prs.citylandcondo.com +short
   ```

#### Optional: Internal DNS Configuration

For better performance, configure internal DNS:

```
Record Type: A
Name: prs.citylandcondo.com
Value: 192.168.0.100
```

**Benefits**:
- Faster access for office users
- Reduced external traffic
- Better performance

### Task 2: Port Forwarding Configuration

#### When Port Forwarding is Needed

- **Initial Setup**: During first SSL certificate generation
- **Renewals**: Every 90 days (automated email notifications)
- **Duration**: 5-10 minutes each time

#### Port Forwarding Rules

**For SSL Certificate Generation (Temporary)**:
```
External Port: 80
Internal IP: 192.168.0.100
Internal Port: 80
Protocol: TCP
```

**For HTTPS Access (Optional - Permanent)**:
```
External Port: 443
Internal IP: 192.168.0.100
Internal Port: 443
Protocol: TCP
```

#### Port Forwarding Process

1. **Enable Forwarding**:
   - Add port 80 forwarding rule before certificate generation
   - Notify technical team when ready

2. **Certificate Generation**:
   - Technical team runs SSL automation script
   - Process takes 2-5 minutes

3. **Disable Forwarding**:
   - Remove port 80 forwarding rule after completion
   - Confirm with technical team

### Task 3: Network Security Configuration

#### Firewall Rules

Ensure these rules are configured:

```bash
# Allow internal network access
Allow from 192.168.0.0/20 to 192.168.0.100:80,443

# Allow temporary external access for SSL (when needed)
Allow from any to [public-ip]:80 (temporary only)

# Block all other external access
Deny from any to [public-ip]:* (default)
```

#### Security Considerations

- **Port 80 forwarding** only during certificate generation
- **HTTPS (port 443)** can remain permanently forwarded if desired
- **Internal network access** always maintained
- **External access** blocked except during SSL validation

## Implementation Timeline

### Phase 1: Initial Setup (Day 1)

**IT Admin Tasks (15 minutes)**:
1. Create GoDaddy DNS A record
2. Configure internal DNS (optional)
3. Verify DNS resolution
4. Confirm office public IP with technical team

**Coordination**:
- Provide office public IP to technical team
- Confirm DNS propagation (5-10 minutes)

### Phase 2: SSL Certificate Generation (Day 2)

**IT Admin Tasks (10 minutes)**:
1. Enable port 80 forwarding when notified
2. Monitor certificate generation process
3. Disable port 80 forwarding when complete

**Coordination**:
- Technical team provides 15-minute advance notice
- Be available during certificate generation window
- Confirm forwarding disabled after completion

### Phase 3: Ongoing Operations

**Quarterly Renewal Process**:
1. Receive automated email alert (30 days before expiry)
2. Schedule 10-minute maintenance window
3. Enable port 80 forwarding during renewal
4. Disable forwarding after completion

## Troubleshooting

### DNS Issues

**Problem**: DNS not resolving
```bash
# Check DNS propagation
dig prs.citylandcondo.com @8.8.8.8
dig prs.citylandcondo.com @1.1.1.1

# Check TTL and propagation
dig prs.citylandcondo.com +trace
```

**Solution**: Wait 5-10 minutes for DNS propagation

### Port Forwarding Issues

**Problem**: SSL certificate generation fails
1. Verify port 80 forwarding is active
2. Test external connectivity:
   ```bash
   # From external network
   telnet [office-public-ip] 80
   ```
3. Check firewall rules
4. Confirm internal server is responding

### Network Connectivity Issues

**Problem**: Internal access not working
1. Verify internal DNS configuration
2. Check internal firewall rules
3. Test direct IP access: `https://192.168.0.100`

## Contact Information

### Technical Team Contacts
- **Primary**: [Technical Lead Contact]
- **Secondary**: [Backup Contact]
- **Emergency**: [Emergency Contact]

### Notification Preferences
- **Email**: [IT Admin Email]
- **Phone**: [IT Admin Phone] (for urgent issues)
- **Preferred Time**: [Business Hours]

## Security Compliance

### Access Control
- **DNS Management**: Restricted to authorized IT staff
- **Port Forwarding**: Temporary access only
- **Certificate Files**: Secured on internal server

### Audit Trail
- **DNS Changes**: Logged in GoDaddy admin panel
- **Port Forwarding**: Logged in router/firewall
- **SSL Renewals**: Logged in monitoring system

### Compliance Requirements
- **Data Security**: All traffic encrypted with valid SSL
- **Network Security**: External access minimized
- **Change Management**: All changes documented and approved

---

!!! success "Coordination Complete"
    With proper IT coordination, the PRS system can maintain professional SSL certificates while ensuring office network security.

!!! tip "Automation Benefits"
    After initial setup, the process is largely automated with minimal IT intervention required (quarterly, 5-10 minutes).
