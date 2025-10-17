#!/bin/bash
set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# Global variables
BACKUP_DIR=""
NETWORK_NAME=""
VOLUME_NAME=""
MINIO_PORT=""
APP_PORT=""
MINIO_ACCESS_KEY=""
MINIO_SECRET_KEY=""
BUCKET_NAME=""

# Load environment from backup file
load_environment() {
    if [ -f "${BACKUP_DIR}/environment" ]; then
        echo -e "${YELLOW}🔧 Loading environment from backup...${NC}"
        # shellcheck source=/dev/null
        source "${BACKUP_DIR}/environment"
    else
        echo -e "${YELLOW}⚠️  No environment backup found. Using current environment.${NC}"
    fi

    # Set defaults
    NETWORK_NAME=${NETWORK_NAME:-analytics-network}
    VOLUME_NAME=${VOLUME_NAME:-minio-data}
    MINIO_PORT=${MINIO_PORT:-9000}
    APP_PORT=${APP_PORT:-5000}
    BUCKET_NAME=${BUCKET_NAME:-analytics-data}
    MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-minioadmin}
    MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-minioadmin}
}

# Stop and remove containers
stop_containers() {
    echo -e "${YELLOW}🛑 Stopping and removing current containers...${NC}"
    docker stop data-app minio 2>/dev/null || true
    docker rm data-app minio 2>/dev/null || true
}

# Restore from backup
restore_backup() {
    echo -e "${YELLOW}🔄 Restoring from backup...${NC}"
    
    if [ ! -f "${BACKUP_DIR}/container_inspect.json" ]; then
        echo -e "${RED}❌ No valid backup found in $BACKUP_DIR${NC}"
        return 1
    fi
    
    # Get the image name from the backup
    local image_name
    image_name=$(jq -r '.[0].Config.Image' "${BACKUP_DIR}/container_inspect.json" 2>/dev/null || echo "")
    
    if [ -z "$image_name" ] || ! docker image inspect "$image_name" &> /dev/null; then
        echo -e "${RED}❌ Previous version image not found: ${image_name:-N/A}${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}🚀 Starting previous version: $image_name${NC}"
    
    # Recreate the network if it doesn't exist
    if ! docker network inspect "$NETWORK_NAME" &> /dev/null; then
        docker network create "$NETWORK_NAME" || true
    fi
    
    # Start MinIO
    echo -e "${YELLOW}Starting MinIO...${NC}"
    docker run -d \
        --name minio \
        --network "$NETWORK_NAME" \
        -p "${MINIO_PORT}:9000" \
        -p 9001:9001 \
        -e "MINIO_ROOT_USER=$MINIO_ACCESS_KEY" \
        -e "MINIO_ROOT_PASSWORD=$MINIO_SECRET_KEY" \
        -v "${VOLUME_NAME}:/data" \
        quay.io/minio/minio server /data --console-address ":9001"
    
    # Start the application
    echo -e "${YELLOW}Starting Application...${NC}"
    docker run -d \
        --name data-app \
        --network "$NETWORK_NAME" \
        -p "${APP_PORT}:5000" \
        -e "MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY" \
        -e "MINIO_SECRET_KEY=$MINIO_SECRET_KEY" \
        -e "MINIO_ENDPOINT=minio:9000" \
        -e "BUCKET_NAME=$BUCKET_NAME" \
        "$image_name"
    
    return 0
}

# Main function
main() {
    # Check if backup directory is provided
    if [ $# -ne 1 ] || [ ! -d "$1" ]; then
        echo -e "${RED}❌ Usage: $0 <backup_directory>${NC}"
        return 1
    fi

    BACKUP_DIR="$1"
    
    # Load environment
    load_environment
    
    # Stop existing containers
    stop_containers
    
    # Restore from backup
    if ! restore_backup; then
        return 1
    fi
    
    echo -e "\n${GREEN}✅ Successfully rolled back to previous version${NC}"
    echo -e "\nAccess the application at: http://localhost:${APP_PORT}"
    echo -e "Access MinIO console at: http://localhost:9001"
    
    return 0
}

# Run the main function
if main "$@"; then
    echo -e "\n${GREEN}🔁 Rollback completed successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Rollback failed!${NC}" >&2
    exit 1
fi
