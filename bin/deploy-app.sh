#!/bin/bash
set -e

# Load environment variables from .env file
if [ -f "../.env" ]; then
    export $(grep -v '^#' ../.env | xargs)
else
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

# Validate required environment variables
for var in MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_PORT APP_PORT NETWORK_NAME VOLUME_NAME BUCKET_NAME; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set in .env file"
        exit 1
    fi
done

# Create network if it doesn't exist
if [ -z "$(docker network ls -q -f name=^${NETWORK_NAME}$)" ]; then
    echo "Creating network ${NETWORK_NAME}..."
    docker network create ${NETWORK_NAME}
fi

# Create volume if it doesn't exist
if [ -z "$(docker volume ls -q -f name=^${VOLUME_NAME}$)" ]; then
    echo "Creating volume ${VOLUME_NAME}..."
    docker volume create ${VOLUME_NAME}
fi

# Build the application image
echo "Building application image..."
docker build -t data-app .

# Create Docker secret for MinIO credentials
if [ -z "$(docker secret ls -q -f name=minio_access_key)" ]; then
    echo "Creating Docker secrets..."
    echo "$MINIO_ACCESS_KEY" | docker secret create minio_access_key -
    echo "$MINIO_SECRET_KEY" | docker secret create minio_secret_key -
fi

# Run MinIO
echo "Starting MinIO..."
docker run -d \
    --name minio \
    --network ${NETWORK_NAME} \
    -p ${MINIO_PORT}:9000 \
    -p 9001:9001 \
    --secret source=minio_access_key,target=MINIO_ACCESS_KEY \
    --secret source=minio_secret_key,target=MINIO_SECRET_KEY \
    -e MINIO_ROOT_USER_FILE=/run/secrets/MINIO_ACCESS_KEY \
    -e MINIO_ROOT_PASSWORD_FILE=/run/secrets/MINIO_SECRET_KEY \
    -v ${VOLUME_NAME}:/data \
    quay.io/minio/minio server /data --console-address ":9001"

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
until curl -s -f -o /dev/null "http://localhost:${MINIO_PORT}/minio/health/ready"; do
    echo "Waiting for MinIO..."
    sleep 1
done

# Create the bucket if it doesn't exist
echo "Creating bucket if it doesn't exist..."
BUCKET_NAME="analytics-data"
MC_CMD="docker run --rm --network ${NETWORK_NAME} -e MINIO_SERVER_URL=http://minio:9000 -e MINIO_SERVER_ACCESS_KEY=${MINIO_ACCESS_KEY} -e MINIO_SERVER_SECRET_KEY=${MINIO_SECRET_KEY} minio/mc"
${MC_CMD} mb minio/${BUCKET_NAME} || true

# Run the application
echo "Starting Data Application..."
docker run -d \
    --name data-app \
    --network ${NETWORK_NAME} \
    -p ${APP_PORT}:5000 \
    --secret source=minio_access_key,target=MINIO_ACCESS_KEY \
    --secret source=minio_secret_key,target=MINIO_SECRET_KEY \
    -e MINIO_ACCESS_KEY_FILE=/run/secrets/MINIO_ACCESS_KEY \
    -e MINIO_SECRET_KEY_FILE=/run/secrets/MINIO_SECRET_KEY \
    -e MINIO_ENDPOINT=minio:9000 \
    -e BUCKET_NAME=${BUCKET_NAME} \
    data-app

# Run health checks
echo "Running health checks..."
set +e
MAX_RETRIES=10
RETRY_COUNT=0

until [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ]
do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${APP_PORT}/health)
    if [ "${RESPONSE}" = "200" ]; then
        echo "Application is healthy!"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "Waiting for application to be healthy... (Attempt ${RETRY_COUNT}/${MAX_RETRIES})"
    sleep 5
done

if [ ${RETRY_COUNT} -ge ${MAX_RETRIES} ]; then
    echo "Health check failed after ${MAX_RETRIES} attempts."
    docker logs data-app
    exit 1
fi

echo ""
echo "Deployment completed successfully!"
echo "MinIO Console: http://localhost:9001"
echo "Data App: http://localhost:${APP_PORT}"
echo ""
echo "MinIO Access Key: ${MINIO_ACCESS_KEY}"
echo "MinIO Secret Key: ${MINIO_SECRET_KEY}"
