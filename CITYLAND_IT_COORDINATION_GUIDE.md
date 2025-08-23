# 🤝 Cityland IT Network Admin Coordination Guide

## 📋 Overview

This guide provides specific instructions for the Cityland IT network admin to support the `prs.citylandcondo.com` implementation with automated SSL certificates.

## 🎯 Your Role in the Implementation

As the Cityland IT network admin managing GoDaddy DNS, you'll need to:

1. **Create one DNS A record** in GoDaddy (one-time setup)
2. **Assist with port forwarding** during certificate generation (quarterly, 5-10 minutes)
3. **Optional**: Configure internal DNS for better performance

## 📋 Required Actions

### **Action 1: GoDaddy DNS Configuration (One-time)**

#### Login to GoDaddy DNS Management
1. Log into your GoDaddy account
2. Navigate to "My Products" → "DNS"
3. Select the `citylandcondo.com` domain

#### Create DNS A Record
```
Record Type: A
Name: prs
Value: [Your office public IP address]
TTL: 1 Hour (3600 seconds)
```

**Important**: Replace `[Your office public IP address]` with your actual public IP

#### Verification
After creating the record, test with:
```bash
nslookup prs.citylandcondo.com 8.8.8.8
```

### **Action 2: Router/Firewall Port Forwarding**

#### When Needed
- **Initial Setup**: During first certificate generation
- **Renewals**: Every ~90 days (you'll receive email notification)
- **Duration**: 5-10 minutes each time

#### Port Forwarding Configuration
```
External Port: 80
Internal IP: 192.168.0.100
Internal Port: 80
Protocol: TCP
```

#### Process
1. **Enable**: Add port forwarding rule before certificate generation
2. **Generate**: Certificate generation process (automated)
3. **Disable**: Remove port forwarding rule after completion

### **Action 3: Internal DNS Configuration (Optional but Recommended)**

#### Benefits
- Faster access for office users
- Reduced external traffic
- Better performance

#### Configuration
Add internal DNS record:
```
Record Type: A
Name: prs.citylandcondo.com
Value: 192.168.0.100
```

## 📅 Implementation Timeline

### **Phase 1: Initial Setup (Day 1)**

#### Your Tasks (15 minutes)
1. **GoDaddy DNS**: Create A record for `prs.citylandcondo.com`
2. **Internal DNS**: Configure internal record (optional)
3. **Verification**: Test DNS resolution

#### Coordination
- **Before**: Confirm your office public IP address
- **After**: Notify technical team when DNS is configured

### **Phase 2: Certificate Generation (Day 2)**

#### Your Tasks (10 minutes)
1. **Port Forwarding**: Enable temporary rule
2. **Monitoring**: Confirm certificate generation completes
3. **Security**: Disable port forwarding rule

#### Coordination
- **Before**: Technical team will notify you when ready
- **During**: Be available for 10-15 minutes
- **After**: Confirm port forwarding is disabled

### **Phase 3: Testing (Day 3)**

#### Your Tasks (5 minutes)
1. **DNS Testing**: Verify both external and internal resolution
2. **Access Testing**: Test HTTPS access from office devices
3. **Documentation**: Note any network-specific configurations

## 🔄 Ongoing Operations

### **Quarterly Certificate Renewal**

#### Notification Process
You'll receive an email notification 30 days before certificate expiry:

```
Subject: SSL Certificate Renewal Required - prs.citylandcondo.com
Content: Certificate expires in 30 days. Please coordinate renewal.
```

#### Renewal Process (5-10 minutes)
1. **Schedule**: Coordinate brief maintenance window
2. **Enable**: Add port 80 forwarding rule
3. **Execute**: Technical team runs renewal script
4. **Disable**: Remove port 80 forwarding rule
5. **Verify**: Confirm new certificate is working

### **Monitoring and Alerts**

#### Automated Monitoring
- Daily certificate status checks
- Email alerts for issues
- Health monitoring reports

#### Your Involvement
- **Minimal**: Most monitoring is automated
- **Alerts**: You'll be notified of any DNS-related issues
- **Renewals**: Coordination required only for renewals

## 🔧 Technical Details

### **DNS Configuration Details**

#### External DNS (GoDaddy)
- **Purpose**: Let's Encrypt certificate validation
- **Usage**: Only during certificate generation/renewal
- **TTL**: 1 hour for faster updates if needed

#### Internal DNS (Your Network)
- **Purpose**: Daily office access
- **Usage**: All regular user traffic
- **Benefit**: Keeps traffic internal, improves performance

### **Port Forwarding Details**

#### Security Considerations
- **Temporary**: Only enabled during certificate generation
- **Minimal Exposure**: Port 80 only, brief duration
- **Automated**: Process is scripted and monitored

#### Network Impact
- **Minimal**: 5-10 minutes quarterly
- **Scheduled**: Coordinated maintenance windows
- **Reversible**: Easy to enable/disable

## 🔍 Troubleshooting Guide

### **DNS Issues**

#### Problem: DNS record not resolving
**Solutions**:
1. Check GoDaddy DNS configuration
2. Verify TTL has expired (wait 1 hour)
3. Test with different DNS servers
4. Clear local DNS cache

#### Problem: Internal DNS conflicts
**Solutions**:
1. Verify internal DNS record is correct
2. Check DNS server priority/order
3. Test from different office devices
4. Restart DNS services if needed

### **Port Forwarding Issues**

#### Problem: Certificate generation fails
**Solutions**:
1. Verify port forwarding rule is active
2. Check firewall allows port 80 traffic
3. Confirm internal IP (192.168.0.100) is correct
4. Test port accessibility

#### Problem: Security concerns
**Solutions**:
1. Confirm port forwarding is disabled after use
2. Monitor firewall logs during process
3. Schedule during low-traffic periods
4. Document all changes

## 📞 Contact Information

### **For DNS Issues**
- **Primary**: Technical team lead
- **Secondary**: System administrator
- **Emergency**: On-call support

### **For Network Issues**
- **Router/Firewall**: Your network team
- **Internet Connectivity**: ISP support
- **Internal DNS**: Your DNS administrator

## 📋 Quick Reference

### **GoDaddy DNS Record**
```
Type: A
Name: prs
Value: [Office Public IP]
TTL: 3600
```

### **Port Forwarding Rule**
```
External: 80
Internal: 192.168.0.100:80
Protocol: TCP
Duration: Temporary (5-10 minutes)
```

### **Internal DNS Record**
```
Type: A
Name: prs.citylandcondo.com
Value: 192.168.0.100
```

### **Testing Commands**
```bash
# Test external DNS
nslookup prs.citylandcondo.com 8.8.8.8

# Test internal DNS
nslookup prs.citylandcondo.com

# Test HTTPS access
curl -v https://prs.citylandcondo.com/health
```

## ✅ Checklist for Implementation

### **Pre-Implementation**
- [ ] GoDaddy admin access confirmed
- [ ] Office public IP address identified
- [ ] Router/firewall admin access confirmed
- [ ] Internal DNS server access confirmed (optional)
- [ ] Coordination schedule established

### **Implementation Day**
- [ ] GoDaddy DNS A record created
- [ ] Internal DNS record configured (optional)
- [ ] DNS resolution tested and verified
- [ ] Port forwarding capability confirmed
- [ ] Technical team notified of completion

### **Post-Implementation**
- [ ] HTTPS access tested from office devices
- [ ] Certificate monitoring confirmed working
- [ ] Renewal process documented and understood
- [ ] Contact information exchanged
- [ ] Success criteria verified

## 🎯 Success Criteria

- ✅ DNS record resolves correctly from external sources
- ✅ Internal DNS provides fast local resolution (if configured)
- ✅ Port forwarding process tested and documented
- ✅ HTTPS access working from all office devices
- ✅ Renewal coordination process established
- ✅ Monitoring and alerting operational

Your cooperation is essential for the success of this implementation. The process is designed to be simple and require minimal ongoing involvement while providing maximum security and automation benefits.
