# Troubleshooting Alpine Package Installation Issues

## Problem
Docker builds fail with errors like:
```
WARNING: fetching https://dl-cdn.alpinelinux.org/alpine/v3.20/community: temporary error (try again later)
ERROR: unable to select packages:
  chromium (no such package):
    required by: world[chromium]
```

## Root Cause
This issue occurs when:
1. Alpine Linux package repositories are temporarily unavailable
2. Network connectivity issues to Alpine CDN
3. Package repository mirrors are out of sync
4. DNS resolution issues

## Solutions

### 1. Automatic Retry (Already Implemented)
The Dockerfiles now include automatic retry logic:
- Retries package installation up to 5 times
- Waits 10-15 seconds between attempts
- Updates package index before each attempt

### 2. Use Fallback Dockerfile
If Alpine repositories continue to fail, use the Debian-based fallback:

```bash
# Use fallback Dockerfile for building
USE_FALLBACK_DOCKERFILE=true ./scripts/deploy-onprem.sh build

# Or for full deployment
USE_FALLBACK_DOCKERFILE=true ./scripts/deploy-onprem.sh deploy
```

### 3. Manual Retry
Simply retry the build after some time:
```bash
# Force rebuild after waiting
FORCE_REBUILD=true ./scripts/deploy-onprem.sh build
```

### 4. Check Network Connectivity
Verify network access to Alpine repositories:
```bash
# Test connectivity to Alpine CDN
curl -I https://dl-cdn.alpinelinux.org/alpine/v3.20/community/

# Test DNS resolution
nslookup dl-cdn.alpinelinux.org

# Check if behind corporate firewall/proxy
echo $HTTP_PROXY $HTTPS_PROXY
```

### 5. Alternative Alpine Mirrors
If the main CDN is down, you can modify the Dockerfile to use alternative mirrors:
```dockerfile
# Add before package installation
RUN echo "http://mirror.example.com/alpine/v3.20/main" > /etc/apk/repositories && \
    echo "http://mirror.example.com/alpine/v3.20/community" >> /etc/apk/repositories
```

## Prevention

### 1. Use Image Caching
Build images during off-peak hours and cache them:
```bash
# Build and tag images for later use
docker build -t prs-backend:cached /opt/prs/prs-backend-a/
docker build -t prs-frontend:cached /opt/prs/prs-frontend-a/
```

### 2. Pre-built Images
Consider using pre-built images from a private registry:
```bash
# Push to private registry
docker tag prs-backend:latest your-registry.com/prs-backend:latest
docker push your-registry.com/prs-backend:latest
```

### 3. Monitor Alpine Status
Check Alpine Linux status page for known issues:
- https://status.alpinelinux.org/
- https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management

## Differences Between Alpine and Debian Fallback

| Aspect | Alpine | Debian Fallback |
|--------|--------|-----------------|
| Image Size | ~50MB smaller | ~100MB larger |
| Package Manager | apk | apt |
| Chromium Package | chromium | chromium + dependencies |
| Build Time | Faster | Slower |
| Reliability | Depends on CDN | More stable |

## When to Use Each Approach

### Use Alpine (Default)
- Normal operations
- When Alpine CDN is accessible
- For production deployments (smaller images)

### Use Debian Fallback
- When Alpine repositories are consistently failing
- During Alpine CDN outages
- For development environments where image size is less critical
- When corporate networks block Alpine CDN

## Monitoring and Alerts

Consider setting up monitoring for:
1. Alpine CDN availability
2. Docker build success rates
3. Package repository response times

## Emergency Procedures

If builds consistently fail:
1. Switch to fallback Dockerfile immediately
2. Investigate network connectivity
3. Check Alpine Linux status pages
4. Consider using cached images
5. Contact network administrators if behind corporate firewall

## Contact Information

For persistent issues:
- Check Alpine Linux community forums
- Review Docker build logs for specific errors
- Verify corporate network policies
- Consider alternative base images (Ubuntu, Debian)
