#!/bin/bash
# /opt/prs-deployment/scripts/docker-cleanup.sh
# Docker maintenance and cleanup for PRS on-premises deployment

set -euo pipefail

LOG_FILE="/var/log/prs-docker-cleanup.log"

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/02-docker-configuration/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

cleanup_containers() {
    log_message "Cleaning up stopped containers"

    # Remove stopped containers (excluding PRS containers)
    local stopped_containers=$(docker ps -a --filter "status=exited" --format "{{.ID}} {{.Names}}" | grep -v "prs-onprem" | awk '{print $1}' || true)

    if [ -n "$stopped_containers" ]; then
        echo "$stopped_containers" | xargs docker rm
        log_message "Removed stopped containers: $(echo "$stopped_containers" | wc -l)"
    else
        log_message "No stopped containers to remove"
    fi
}

cleanup_images() {
    log_message "Cleaning up unused images"

    # Remove dangling images
    local dangling_images=$(docker images -f "dangling=true" -q)
    if [ -n "$dangling_images" ]; then
        echo "$dangling_images" | xargs docker rmi
        log_message "Removed dangling images: $(echo "$dangling_images" | wc -l)"
    else
        log_message "No dangling images to remove"
    fi

    # Remove unused images (not used by any container)
    docker image prune -af
    log_message "Removed unused images"
}

cleanup_volumes() {
    log_message "Cleaning up unused volumes"

    # List volumes before cleanup
    local volumes_before=$(docker volume ls -q | wc -l)

    # Remove unused volumes (excluding PRS volumes)
    docker volume prune -f

    local volumes_after=$(docker volume ls -q | wc -l)
    local removed_volumes=$((volumes_before - volumes_after))

    log_message "Removed $removed_volumes unused volumes"
}

cleanup_networks() {
    log_message "Cleaning up unused networks"

    # Remove unused networks
    docker network prune -f
    log_message "Removed unused networks"
}

cleanup_build_cache() {
    log_message "Cleaning up build cache"

    # Clean build cache
    docker builder prune -af
    log_message "Cleaned build cache"
}

check_disk_usage() {
    log_message "Checking Docker disk usage"

    # Show Docker system disk usage
    docker system df > /tmp/docker-disk-usage.log

    local total_size=$(docker system df | grep "Total" | awk '{print $4}')
    log_message "Total Docker disk usage: $total_size"

    # Check for large containers
    local large_containers=$(docker ps -a --format "table {{.Names}}\t{{.Size}}" | grep -E "[0-9]+GB" || true)
    if [ -n "$large_containers" ]; then
        log_message "Large containers detected:"
        echo "$large_containers" >> "$LOG_FILE"
    fi
}

main() {
    log_message "Starting Docker cleanup"

    check_disk_usage
    cleanup_containers
    cleanup_images
    cleanup_volumes
    cleanup_networks
    cleanup_build_cache

    log_message "Docker cleanup completed"

    # Show final disk usage
    check_disk_usage
}

main "$@"
