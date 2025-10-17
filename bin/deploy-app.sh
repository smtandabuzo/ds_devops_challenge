#!/bin/bash
set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment from .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
else
    echo -e "${RED} .env file not found at $PROJECT_ROOT/.env${NC}"
    exit 1
fi

# Set default values
export APP_PORT=${APP_PORT:-5000}
export MINIO_PORT=${MINIO_PORT:-9000}
export NETWORK_NAME=${NETWORK_NAME:-analytics-network}
export VOLUME_NAME=${VOLUME_NAME:-minio-data}
export BUCKET_NAME=${BUCKET_NAME:-analytics-data}

# Validate required environment variables
for var in MINIO_ACCESS_KEY MINIO_SECRET_KEY; do
    if [ -z "${!var}" ]; then
        echo -e "${RED} $var is not set in .env file${NC}"
        exit 1
    fi
done

# Create a logs directory
LOGS_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOGS_DIR"

# Log file
LOG_FILE="$LOGS_DIR/deploy-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "\n${YELLOW} Starting deployment at $(date)${NC}"
echo -e "Log file: $LOG_FILE"

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}"
}

# Function to handle errors
error_exit() {
    log "ERROR" "${RED}$1${NC}"
    exit 1
}

# Function to check if a container is running
is_container_running() {
    local name=$1
    docker ps --filter "name=^${name}$" --format '{{.Names}}' | grep -q "^${name}$"
}

# Function to stop and remove a container
stop_and_remove_container() {
    local name=$1
    if is_container_running "$name"; then
        log "INFO" "Stopping container: $name"
        docker stop "$name" >/dev/null || true
    fi
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        log "INFO" "Removing container: $name"
        docker rm "$name" >/dev/null || true
    fi
}

# Create network if it doesn't exist
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    log "INFO" "Creating network: $NETWORK_NAME"
    if ! docker network create "$NETWORK_NAME" >/dev/null; then
        error_exit "Failed to create network: $NETWORK_NAME"
    fi
    log "INFO" "Network created: $NETWORK_NAME"
else
    log "INFO" "Using existing network: $NETWORK_NAME"
fi

# Create volume if it doesn't exist
if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
    log "INFO" "Creating volume: $VOLUME_NAME"
    if ! docker volume create "$VOLUME_NAME" >/dev/null; then
        error_exit "Failed to create volume: $VOLUME_NAME"
    fi
    log "INFO" "Volume created: $VOLUME_NAME"
else
    log "INFO" "Using existing volume: $VOLUME_NAME"
fi

# Create secrets directory
SECRETS_DIR="$PROJECT_ROOT/.secrets"
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# Create secret files if they don't exist
for secret in "minio_access_key" "minio_secret_key"; do
    secret_file="$SECRETS_DIR/$secret"
    if [ ! -f "$secret_file" ]; then
        var_name=$(echo "$secret" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        echo "${!var_name}" > "$secret_file"
        chmod 600 "$secret_file"
        log "INFO" "Created secret file: $secret_file"
    fi
done

# Stop and remove existing MinIO container if it exists
stop_and_remove_container "minio"

# Start MinIO
log "INFO" "Starting MinIO..."
if ! docker run -d \
    --name minio \
    --network "$NETWORK_NAME" \
    -p "${MINIO_PORT}:9000" \
    -p 9001:9001 \
    -e "MINIO_ROOT_USER=${MINIO_ACCESS_KEY}" \
    -e "MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}" \
    -v "${VOLUME_NAME}:/data" \
    quay.io/minio/minio server /data --console-address ":9001" >/dev/null; then
    error_exit "Failed to start MinIO container"
fi
log "INFO" "MinIO container started"

# Wait for MinIO to be ready
log "INFO" "Waiting for MinIO to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -s -f -o /dev/null "http://localhost:${MINIO_PORT}/minio/health/ready" || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log "INFO" "Waiting for MinIO... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    error_exit "Timed out waiting for MinIO to be ready"
fi
log "INFO" "MinIO is ready"

# Create bucket if it doesn't exist
log "INFO" "Ensuring bucket exists: $BUCKET_NAME"
if ! docker run --rm \
    --network "$NETWORK_NAME" \
    -e "MINIO_SERVER_URL=http://minio:9000" \
    -e "MINIO_SERVER_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
    -e "MINIO_SERVER_SECRET_KEY=${MINIO_SECRET_KEY}" \
    minio/mc \
    mb "minio/${BUCKET_NAME}" --ignore-existing >/dev/null 2>&1; then
    log "WARN" "Failed to create bucket $BUCKET_NAME (it might already exist)"
fi

# Stop and remove existing application container if it exists
stop_and_remove_container "data-app"

# Start the application
log "INFO" "Starting Data Application..."
if ! docker run -d \
    --name data-app \
    --network "$NETWORK_NAME" \
    -p "${APP_PORT}:5000" \
    -e "MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
    -e "MINIO_SECRET_KEY=${MINIO_SECRET_KEY}" \
    -e "MINIO_ENDPOINT=minio:9000" \
    -e "BUCKET_NAME=${BUCKET_NAME}" \
    --restart unless-stopped \
    data-app:latest >/dev/null; then
    error_exit "Failed to start data-app container"
fi
log "INFO" "Data Application container started"

# Run health checks
log "INFO" "Running health checks..."
MAX_RETRIES=10
RETRY_COUNT=0

until [ $RETRY_COUNT -ge $MAX_RETRIES ]; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${APP_PORT}/health" 2>/dev/null || true)
    if [ "$RESPONSE" = "200" ]; then
        log "INFO" "${GREEN}Health check passed!${NC}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log "INFO" "Health check failed (Attempt $RETRY_COUNT/$MAX_RETRIES) - Status: ${RESPONSE:-N/A}"
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    error_exit "Health check failed after $MAX_RETRIES attempts"
    exit 1
fi

echo ""
echo "Deployment completed successfully!"
echo "MinIO Console: http://localhost:9001"
echo "Data App: http://localhost:${APP_PORT}"
echo ""
echo "MinIO Access Key: ${MINIO_ACCESS_KEY}"
echo "MinIO Secret Key: ${MINIO_SECRET_KEY}"
