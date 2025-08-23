# 🌐 Custom Domain SSL Guide: prs.citylandcondo.com

## 📋 Overview

This guide provides multiple solutions for implementing `prs.citylandcondo.com` with automated Let's Encrypt SSL certificates, specifically designed for clients using GoDaddy hosting without API access and office-network-only accessibility.

## 🎯 Client Requirements

- **Domain**: `prs.citylandcondo.com`
- **DNS Provider**: GoDaddy (no API access)
- **Network**: Office network only (not public internet)
- **SSL**: Automated Let's Encrypt certificates
- **Infrastructure**: On-premises server (192.168.0.100)

## 🔧 Solution Options

### **Option 1: HTTP-01 Challenge with Port Forwarding (Recommended)**

This solution works by temporarily exposing port 80 during certificate generation.

#### Prerequisites
- Router/firewall can forward port 80 to internal server
- Domain `prs.citylandcondo.com` points to public IP
- Temporary public access during certificate generation

#### Implementation Steps

1. **DNS Configuration (One-time setup)**
   ```bash
   # In GoDaddy DNS settings, create A record:
   # Name: prs
   # Type: A
   # Value: [Your office public IP address]
   # TTL: 1 Hour
   ```

2. **Firewall Configuration**
   ```bash
   # Configure router to forward port 80 to 192.168.0.100:80
   # This can be done temporarily during certificate generation
   ```

3. **Automated Certificate Script**
   ```bash
   #!/bin/bash
   # /opt/prs/scripts/ssl-automation.sh

   DOMAIN="prs.citylandcondo.com"
   EMAIL="admin@citylandcondo.com"
   SSL_DIR="/opt/prs/prod-workplan/02-docker-configuration/ssl"

   # Function to enable port forwarding
   enable_port_forwarding() {
       echo "📡 Please enable port 80 forwarding on your router/firewall"
       echo "Forward: Public IP:80 → 192.168.0.100:80"
       read -p "Press Enter when port forwarding is enabled..."
   }

   # Function to disable port forwarding
   disable_port_forwarding() {
       echo "🔒 Please disable port 80 forwarding on your router/firewall"
       read -p "Press Enter when port forwarding is disabled..."
   }

   # Generate certificate
   generate_certificate() {
       echo "🔐 Generating Let's Encrypt certificate for $DOMAIN..."

       # Stop nginx temporarily
       docker compose -f /opt/prs/prod-workplan/02-docker-configuration/docker-compose.onprem.yml stop nginx

       # Generate certificate using standalone mode
       sudo certbot certonly --standalone \
           -d "$DOMAIN" \
           --email "$EMAIL" \
           --agree-tos \
           --non-interactive \
           --preferred-challenges http

       # Copy certificates
       sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/server.crt"
       sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/server.key"

       # Set permissions
       sudo chmod 644 "$SSL_DIR/server.crt"
       sudo chmod 600 "$SSL_DIR/server.key"

       # Generate DH parameters if not exists
       if [ ! -f "$SSL_DIR/dhparam.pem" ]; then
           sudo openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048
       fi

       # Restart nginx
       docker compose -f /opt/prs/prod-workplan/02-docker-configuration/docker-compose.onprem.yml start nginx

       echo "✅ Certificate generated successfully!"
   }

   # Main execution
   echo "🚀 Starting SSL certificate generation for $DOMAIN"
   enable_port_forwarding
   generate_certificate
   disable_port_forwarding

   echo "🎉 SSL setup complete! Your domain is now secured with Let's Encrypt."
   ```

4. **Automated Renewal Script**
   ```bash
   #!/bin/bash
   # /opt/prs/scripts/ssl-renewal.sh

   DOMAIN="prs.citylandcondo.com"
   SSL_DIR="/opt/prs/prod-workplan/02-docker-configuration/ssl"

   # Check if certificate expires in 30 days
   if openssl x509 -checkend 2592000 -noout -in "$SSL_DIR/server.crt"; then
       echo "✅ Certificate is still valid for more than 30 days"
       exit 0
   fi

   echo "⚠️ Certificate expires soon, renewing..."

   # Send notification to admin
   echo "SSL certificate for $DOMAIN expires soon. Please run renewal process." | \
       mail -s "SSL Certificate Renewal Required" admin@citylandcondo.com

   # Log renewal requirement
   echo "$(date): SSL renewal required for $DOMAIN" >> /var/log/prs-ssl.log
   ```

### **Option 2: DNS-01 Challenge with Manual DNS Updates**

For environments where port forwarding is not possible.

#### Implementation
```bash
#!/bin/bash
# /opt/prs/scripts/ssl-dns-challenge.sh

DOMAIN="prs.citylandcondo.com"
EMAIL="admin@citylandcondo.com"

echo "🔐 Starting DNS-01 challenge for $DOMAIN..."

# Generate certificate with manual DNS challenge
sudo certbot certonly --manual \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --preferred-challenges dns \
    --manual-public-ip-logging-ok

echo "📝 Follow the instructions above to add TXT record to GoDaddy DNS"
echo "After adding the TXT record, press Enter to continue..."
```

### **Option 3: Hybrid Approach with Staging Environment**

Use a staging subdomain for automated renewals.

#### Setup
1. Create `staging.citylandcondo.com` subdomain
2. Use automated renewal for staging
3. Copy certificates to production

## 🔧 Nginx Configuration Update

Update the nginx configuration to use the custom domain:

```nginx
# /opt/prs/prod-workplan/02-docker-configuration/nginx/sites-enabled/prs-onprem.conf

server {
    listen 80;
    server_name prs.citylandcondo.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name prs.citylandcondo.com;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # Rest of configuration remains the same...
    # (API routes, frontend, etc.)
}
```

## 📅 Automation Schedule

Set up cron jobs for certificate monitoring:

```bash
# Add to crontab: crontab -e
# Check certificate status daily
0 2 * * * /opt/prs/scripts/ssl-renewal.sh

# Monthly certificate validation
0 3 1 * * /opt/prs/scripts/ssl-validation.sh
```

## 🔍 Monitoring and Alerts

```bash
#!/bin/bash
# /opt/prs/scripts/ssl-validation.sh

DOMAIN="prs.citylandcondo.com"
SSL_DIR="/opt/prs/prod-workplan/02-docker-configuration/ssl"

# Check certificate validity
EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$SSL_DIR/server.crt" | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

echo "📊 SSL Certificate Status for $DOMAIN"
echo "Expires: $EXPIRY_DATE"
echo "Days until expiry: $DAYS_UNTIL_EXPIRY"

if [ $DAYS_UNTIL_EXPIRY -lt 30 ]; then
    echo "⚠️ WARNING: Certificate expires in $DAYS_UNTIL_EXPIRY days!"
    # Send alert to monitoring system
    curl -X POST "http://192.168.0.100:3000/api/alerts" \
        -H "Content-Type: application/json" \
        -d "{\"message\": \"SSL certificate expires in $DAYS_UNTIL_EXPIRY days\"}"
fi
```

## 🚀 Quick Deployment

For immediate implementation:

```bash
# 1. Install certbot
sudo apt update && sudo apt install -y certbot

# 2. Create SSL automation script
sudo mkdir -p /opt/prs/scripts
sudo cp ssl-automation.sh /opt/prs/scripts/
sudo chmod +x /opt/prs/scripts/ssl-automation.sh

# 3. Run initial setup
sudo /opt/prs/scripts/ssl-automation.sh

# 4. Update nginx configuration
# (Update the nginx config file as shown above)

# 5. Restart services
cd /opt/prs/prod-workplan/02-docker-configuration
docker compose -f docker-compose.onprem.yml restart nginx
```

## 📞 Support Notes

- **Certificate Renewal**: Requires temporary port 80 access (quarterly)
- **DNS Changes**: Manual updates in GoDaddy when needed
- **Monitoring**: Automated alerts 30 days before expiry
- **Backup**: Certificates automatically backed up to NAS

This solution provides automated SSL with minimal manual intervention while working within the constraints of GoDaddy hosting and office-network-only access.

## 🚀 Quick Start Guide

For immediate implementation, run the automated setup script:

```bash
# 1. Make scripts executable
sudo chmod +x /opt/prs/prod-workplan/scripts/*.sh

# 2. Run the complete setup
sudo /opt/prs/prod-workplan/scripts/setup-custom-domain.sh

# 3. Follow the guided prompts for:
#    - DNS configuration in GoDaddy
#    - Port forwarding setup
#    - SSL certificate generation
```

## 🔧 Manual Implementation Steps

If you prefer manual setup or need to troubleshoot:

### Step 1: DNS Configuration
1. Log into GoDaddy DNS management
2. Add A record: `prs` → `[Your Public IP]`
3. Wait 5-10 minutes for propagation

### Step 2: Install Dependencies
```bash
sudo apt update
sudo apt install -y certbot curl openssl
```

### Step 3: Run SSL Automation
```bash
sudo /opt/prs/scripts/ssl-automation-citylandcondo.sh
```

### Step 4: Update Nginx Configuration
The nginx configuration has been updated to handle the custom domain automatically.

### Step 5: Restart Services
```bash
cd /opt/prs/prod-workplan/02-docker-configuration
docker compose -f docker-compose.onprem.yml restart nginx
```

## 🔍 Troubleshooting Guide

### Common Issues and Solutions

#### 1. DNS Resolution Problems
**Symptom**: Domain doesn't resolve to your server
**Solutions**:
```bash
# Check DNS propagation
nslookup prs.citylandcondo.com
dig prs.citylandcondo.com

# Test from different DNS servers
nslookup prs.citylandcondo.com 8.8.8.8
```

#### 2. Port Forwarding Issues
**Symptom**: Certificate generation fails with connection errors
**Solutions**:
- Verify port 80 is forwarded to 192.168.0.100:80
- Check firewall rules on the server
- Temporarily disable any security software

#### 3. Certificate Generation Failures
**Symptom**: Let's Encrypt validation fails
**Solutions**:
```bash
# Check if port 80 is accessible
sudo netstat -tlnp | grep :80

# Test manual certificate generation
sudo certbot certonly --standalone -d prs.citylandcondo.com --dry-run

# Check Let's Encrypt logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

#### 4. SSL Certificate Not Loading
**Symptom**: Browser shows certificate errors
**Solutions**:
```bash
# Verify certificate files exist
ls -la /opt/prs/prod-workplan/02-docker-configuration/ssl/

# Check certificate validity
openssl x509 -in /opt/prs/prod-workplan/02-docker-configuration/ssl/server.crt -text -noout

# Restart nginx
docker compose -f /opt/prs/prod-workplan/02-docker-configuration/docker-compose.onprem.yml restart nginx
```

#### 5. Domain Access Issues
**Symptom**: Can't access via domain name from office network
**Solutions**:
- Check internal DNS resolution
- Verify firewall allows HTTPS traffic
- Test from different devices on the network

### Diagnostic Commands

```bash
# Check SSL certificate status
sudo /opt/prs/scripts/ssl-renewal-monitor.sh check

# Test HTTPS connectivity
curl -v https://prs.citylandcondo.com/health

# Check nginx configuration
docker exec prs-onprem-nginx nginx -t

# View nginx logs
docker logs prs-onprem-nginx

# Check certificate expiry
openssl x509 -enddate -noout -in /opt/prs/prod-workplan/02-docker-configuration/ssl/server.crt
```

## 📅 Maintenance Schedule

### Automated Tasks
- **Daily**: SSL certificate monitoring (2:00 AM)
- **Weekly**: SSL status reports (3:00 AM Sundays)

### Manual Tasks
- **Quarterly**: Certificate renewal (when notified)
- **Annually**: Review and update DNS configuration

### Renewal Process
When you receive renewal notifications:

1. **Prepare**: Schedule 5-10 minute maintenance window
2. **Execute**: Run `sudo /opt/prs/scripts/ssl-automation-citylandcondo.sh renew`
3. **Verify**: Check certificate with monitoring script
4. **Notify**: Inform users that maintenance is complete

## 🔐 Security Considerations

### Network Security
- Port 80 forwarding is only needed during certificate generation
- HTTPS (port 443) can remain permanently forwarded
- Consider VPN access for enhanced security

### Certificate Security
- Certificates are automatically backed up to NAS
- Private keys are protected with proper file permissions
- Monitoring alerts prevent certificate expiration

### Access Control
- Domain is only accessible from office network
- Additional firewall rules can restrict access further
- Consider implementing IP whitelisting if needed

## 📞 Support and Escalation

### Level 1: Self-Service
- Use monitoring scripts for status checks
- Follow troubleshooting guide for common issues
- Check logs for error messages

### Level 2: IT Team
- Router/firewall configuration issues
- Network connectivity problems
- DNS configuration changes

### Level 3: Technical Support
- Complex SSL certificate issues
- Application-level problems
- Infrastructure modifications

## 📋 Checklist for Go-Live

- [ ] DNS A record configured in GoDaddy
- [ ] Port forwarding rules configured
- [ ] SSL certificates generated and valid
- [ ] Nginx configuration updated
- [ ] Services restarted and healthy
- [ ] HTTPS access tested from multiple devices
- [ ] Monitoring scripts configured and running
- [ ] IT team trained on renewal process
- [ ] Documentation updated with any customizations

## 🎯 Success Criteria

✅ **Domain Access**: `https://prs.citylandcondo.com` accessible from office network
✅ **SSL Security**: Valid Let's Encrypt certificate with A+ rating
✅ **Automated Monitoring**: Daily certificate status checks
✅ **Renewal Process**: Documented and tested renewal procedure
✅ **Performance**: No degradation in application performance
✅ **Security**: Maintained security posture with custom domain
