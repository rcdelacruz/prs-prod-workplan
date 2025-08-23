# 🧪 Step-by-Step Testing Guide

## 📋 Overview

This guide provides a complete testing methodology to validate the `prs.citylandcondo.com` implementation before client deployment.

## 🎯 Testing Scenarios

### **Scenario 1: Local Testing (No External Dependencies)**
Test the scripts and configuration without requiring external DNS or certificates.

### **Scenario 2: Staging Domain Testing**
Use a test domain you control to validate the complete process.

### **Scenario 3: Production Simulation**
Simulate the exact client environment for final validation.

## 🧪 Scenario 1: Local Testing

### **Prerequisites**
- PRS system running on 192.168.0.100
- Docker containers operational
- Root/sudo access

### **Step 1: Script Validation**
```bash
# Test script syntax and basic functionality
cd /opt/prs/prod-workplan

# Check script permissions
ls -la scripts/*.sh

# Validate script syntax
bash -n scripts/ssl-automation-citylandcondo.sh
bash -n scripts/ssl-renewal-monitor.sh
bash -n scripts/setup-custom-domain.sh

# Test help functions
sudo scripts/ssl-automation-citylandcondo.sh help
sudo scripts/ssl-renewal-monitor.sh help
sudo scripts/setup-custom-domain.sh help
```

**Expected Results**:
- ✅ All scripts executable
- ✅ No syntax errors
- ✅ Help functions display correctly

### **Step 2: Configuration Testing**
```bash
# Test nginx configuration syntax
docker exec prs-onprem-nginx nginx -t

# Check SSL directory structure
ls -la 02-docker-configuration/ssl/

# Verify current certificate (if any)
if [ -f "02-docker-configuration/ssl/server.crt" ]; then
    openssl x509 -in 02-docker-configuration/ssl/server.crt -text -noout
fi

# Test current HTTPS access
curl -k -v https://192.168.0.100/health
```

**Expected Results**:
- ✅ Nginx configuration valid
- ✅ SSL directory exists
- ✅ Current HTTPS access working

### **Step 3: Monitoring Script Testing**
```bash
# Test SSL monitoring without certificates
sudo scripts/ssl-renewal-monitor.sh check

# Test connectivity checking
sudo scripts/ssl-renewal-monitor.sh test

# Generate test report
sudo scripts/ssl-renewal-monitor.sh report
```

**Expected Results**:
- ✅ Scripts execute without errors
- ✅ Appropriate warnings for missing certificates
- ✅ Connectivity tests work

## 🧪 Scenario 2: Staging Domain Testing

### **Prerequisites**
- A test domain you control (e.g., `test.yourdomain.com`)
- DNS management access
- Ability to configure port forwarding

### **Step 1: Modify Scripts for Testing**
```bash
# Create test versions of scripts
cp scripts/ssl-automation-citylandcondo.sh scripts/ssl-automation-test.sh
cp scripts/ssl-renewal-monitor.sh scripts/ssl-renewal-monitor-test.sh

# Edit test scripts to use your test domain
sed -i 's/prs.citylandcondo.com/test.yourdomain.com/g' scripts/ssl-automation-test.sh
sed -i 's/prs.citylandcondo.com/test.yourdomain.com/g' scripts/ssl-renewal-monitor-test.sh
sed -i 's/admin@citylandcondo.com/your-email@yourdomain.com/g' scripts/ssl-automation-test.sh
```

### **Step 2: DNS Configuration**
```bash
# Configure DNS A record for your test domain
# Point test.yourdomain.com to your public IP

# Test DNS resolution
nslookup test.yourdomain.com
dig test.yourdomain.com

# Verify propagation
nslookup test.yourdomain.com 8.8.8.8
```

**Expected Results**:
- ✅ DNS record resolves to your IP
- ✅ Propagation complete

### **Step 3: Port Forwarding Setup**
```bash
# Configure port forwarding: External 80 → 192.168.0.100:80
# Test port accessibility
nc -zv [your-public-ip] 80

# Test from external source (if possible)
curl -v http://test.yourdomain.com/health
```

**Expected Results**:
- ✅ Port 80 accessible externally
- ✅ Traffic reaches your server

### **Step 4: Certificate Generation Testing**
```bash
# Run test SSL automation
sudo scripts/ssl-automation-test.sh

# Monitor the process
tail -f /var/log/letsencrypt/letsencrypt.log

# Verify certificate generation
openssl x509 -in 02-docker-configuration/ssl/server.crt -text -noout | grep test.yourdomain.com
```

**Expected Results**:
- ✅ Certificate generated successfully
- ✅ Certificate matches test domain
- ✅ No errors in process

### **Step 5: HTTPS Access Testing**
```bash
# Test HTTPS access via test domain
curl -v https://test.yourdomain.com/health

# Test SSL certificate validation
openssl s_client -connect test.yourdomain.com:443 -servername test.yourdomain.com

# Test browser access
# Open https://test.yourdomain.com in browser
```

**Expected Results**:
- ✅ HTTPS access works
- ✅ Valid SSL certificate
- ✅ No browser warnings

### **Step 6: Renewal Testing**
```bash
# Test renewal process
sudo scripts/ssl-automation-test.sh renew

# Test monitoring
sudo scripts/ssl-renewal-monitor-test.sh check

# Verify new certificate
openssl x509 -in 02-docker-configuration/ssl/server.crt -dates -noout
```

**Expected Results**:
- ✅ Renewal process works
- ✅ New certificate generated
- ✅ Monitoring detects changes

## 🧪 Scenario 3: Production Simulation

### **Prerequisites**
- Test domain working (from Scenario 2)
- Understanding of client network setup
- Ability to simulate client environment

### **Step 1: Network Simulation**
```bash
# Simulate client network configuration
# Update nginx config for test domain
sed -i 's/prs.citylandcondo.com/test.yourdomain.com/g' 02-docker-configuration/nginx/sites-enabled/prs-onprem.conf

# Restart nginx
docker compose -f 02-docker-configuration/docker-compose.onprem.yml restart nginx

# Test configuration
docker exec prs-onprem-nginx nginx -t
```

### **Step 2: Internal DNS Simulation**
```bash
# Add test domain to local hosts file (simulates internal DNS)
echo "192.168.0.100 test.yourdomain.com" | sudo tee -a /etc/hosts

# Test internal resolution
nslookup test.yourdomain.com

# Test internal HTTPS access
curl -v https://test.yourdomain.com/health
```

**Expected Results**:
- ✅ Internal DNS resolution works
- ✅ HTTPS access via internal routing
- ✅ Performance is good

### **Step 3: Client Workflow Simulation**
```bash
# Simulate the complete client process

# 1. DNS setup (already done)
echo "✅ DNS configured"

# 2. Port forwarding (already configured)
echo "✅ Port forwarding active"

# 3. Run setup script
sudo scripts/setup-custom-domain.sh ssl-only

# 4. Test access from "office devices"
curl -v https://test.yourdomain.com/health
curl -I https://test.yourdomain.com

# 5. Disable port forwarding (simulate security)
echo "✅ Port forwarding disabled (simulated)"
```

### **Step 4: Operational Testing**
```bash
# Test monitoring system
sudo scripts/ssl-renewal-monitor-test.sh

# Test cron job simulation
sudo scripts/ssl-renewal-monitor-test.sh check

# Test alert system
sudo scripts/ssl-renewal-monitor-test.sh alert-test

# Generate operational report
sudo scripts/ssl-renewal-monitor-test.sh report
```

**Expected Results**:
- ✅ Monitoring system operational
- ✅ Alerts working
- ✅ Reports generated correctly

## 🔧 Testing Tools and Commands

### **DNS Testing Tools**
```bash
# Basic DNS testing
nslookup prs.citylandcondo.com
dig prs.citylandcondo.com
host prs.citylandcondo.com

# Advanced DNS testing
dig +trace prs.citylandcondo.com
dig @8.8.8.8 prs.citylandcondo.com
dig @1.1.1.1 prs.citylandcondo.com
```

### **SSL Testing Tools**
```bash
# Certificate validation
openssl x509 -in cert.crt -text -noout
openssl x509 -in cert.crt -dates -noout
openssl verify cert.crt

# SSL connection testing
openssl s_client -connect domain:443
openssl s_client -connect domain:443 -servername domain

# SSL security testing (if available)
sslscan domain
testssl.sh domain
```

### **Network Testing Tools**
```bash
# Port connectivity
nc -zv host port
telnet host port
nmap -p port host

# HTTP/HTTPS testing
curl -v https://domain/
curl -I https://domain/
wget --spider https://domain/

# Performance testing
curl -w "@curl-format.txt" -o /dev/null -s https://domain/
time curl https://domain/
```

## 📋 Testing Checklist

### **Pre-Testing Setup**
- [ ] PRS system running and healthy
- [ ] Docker containers operational
- [ ] Scripts executable and syntax-valid
- [ ] Test domain available (for full testing)
- [ ] DNS management access available
- [ ] Port forwarding capability confirmed

### **Local Testing Results**
- [ ] Scripts execute without syntax errors
- [ ] Nginx configuration valid
- [ ] Current HTTPS access working
- [ ] Monitoring scripts functional
- [ ] Help functions display correctly

### **Staging Testing Results**
- [ ] Test domain DNS configured
- [ ] Port forwarding working
- [ ] Certificate generation successful
- [ ] HTTPS access via test domain working
- [ ] SSL certificate valid and trusted
- [ ] Renewal process working

### **Production Simulation Results**
- [ ] Internal DNS simulation working
- [ ] Client workflow simulation successful
- [ ] Monitoring and alerting operational
- [ ] Performance meets expectations
- [ ] Security measures effective

### **Final Validation**
- [ ] All test scenarios passed
- [ ] No errors in logs
- [ ] Performance acceptable
- [ ] Security validated
- [ ] Ready for client deployment

## 🚀 Quick Test Commands

### **One-Line Health Check**
```bash
# Complete system health check
curl -k https://192.168.0.100/health && echo "✅ System healthy" || echo "❌ System issue"
```

### **Quick SSL Validation**
```bash
# Quick SSL certificate check
openssl x509 -in 02-docker-configuration/ssl/server.crt -dates -noout 2>/dev/null && echo "✅ Certificate exists" || echo "❌ No certificate"
```

### **Quick Script Test**
```bash
# Test all scripts quickly
for script in scripts/*.sh; do echo "Testing $script"; bash -n "$script" && echo "✅ OK" || echo "❌ Error"; done
```

## 📞 Troubleshooting During Testing

### **Common Issues and Solutions**

#### DNS Resolution Issues
```bash
# Clear DNS cache
sudo systemctl flush-dns
# or
sudo dscacheutil -flushcache

# Test with different DNS servers
nslookup domain 8.8.8.8
nslookup domain 1.1.1.1
```

#### Certificate Generation Issues
```bash
# Check Let's Encrypt logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# Test with dry run
sudo certbot certonly --standalone --dry-run -d test.domain.com

# Check port accessibility
sudo netstat -tlnp | grep :80
```

#### HTTPS Access Issues
```bash
# Check nginx logs
docker logs prs-onprem-nginx

# Test nginx configuration
docker exec prs-onprem-nginx nginx -t

# Check certificate files
ls -la 02-docker-configuration/ssl/
```

This comprehensive testing approach ensures that your implementation is robust and ready for client deployment!
