#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo -e "${RED}Error: .env file not found.${NC}"
    exit 1
fi

# Default values
APP_PORT=${APP_PORT:-5000}
MINIO_PORT=${MINIO_PORT:-9000}
MAX_RETRIES=5
RETRY_DELAY=5

# Check if a service is running
check_service() {
    local name=$1
    local port=$2
    local url=$3
    
    echo -e "${YELLOW}🔍 Checking $name service...${NC}"
    
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        if curl -s -f -o /dev/null "$url"; then
            echo -e "${GREEN}✅ $name is running on port $port${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}⏳ Waiting for $name to be ready (Attempt $attempt/$MAX_RETRIES)...${NC}"
        sleep $RETRY_DELAY
        ((attempt++))
    done
    
    echo -e "${RED}❌ $name is not accessible at $url${NC}"
    return 1
}

# Check if containers are running
check_container() {
    local name=$1
    if [ -z "$(docker ps -q -f name=^${name}$)" ]; then
        echo -e "${RED}❌ Container $name is not running${NC}"
        docker logs $name 2>&1 | tail -n 20
        return 1
    fi
    echo -e "${GREEN}✅ Container $name is running${NC}"
    return 0
}

# Test MinIO connectivity
test_minio_connection() {
    echo -e "${YELLOW}🔍 Testing MinIO connectivity...${NC}"
    
    # Use mc (MinIO Client) to test the connection
    if ! docker run --rm --network ${NETWORK_NAME:-analytics-network} \
         -e "MINIO_SERVER_URL=http://minio:9000" \
         -e "MINIO_SERVER_ACCESS_KEY=${MINIO_ACCESS_KEY}" \
         -e "MINIO_SERVER_SECRET_KEY=${MINIO_SECRET_KEY}" \
         minio/mc ls minio 2>/dev/null; then
        echo -e "${RED}❌ Failed to connect to MinIO${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Successfully connected to MinIO${NC}"
    return 0
}

# Test application health endpoint
test_health_endpoint() {
    echo -e "${YELLOW}🔍 Testing application health endpoint...${NC}"
    
    local health_url="http://localhost:${APP_PORT}/health"
    local response
    
    response=$(curl -s -f "$health_url" || echo "")
    
    if [ -z "$response" ]; then
        echo -e "${RED}❌ Failed to access health endpoint at $health_url${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Health endpoint response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    
    # Check if MinIO is connected in the health response
    if ! echo "$response" | grep -q '"minio":"connected"'; then
        echo -e "${RED}❌ Application is not connected to MinIO${NC}"
        return 1
    fi
    
    return 0
}

# Test file upload/download
test_file_operations() {
    echo -e "${YELLOW}🔍 Testing file operations...${NC}"
    
    local test_file="$PROJECT_ROOT/test_file.txt"
    local test_content="Hello, MinIO! $(date)"
    
    # Create a test file
    echo "$test_content" > "$test_file"
    
    # Upload the file
    if ! curl -s -X POST -F "file=@$test_file" "http://localhost:${APP_PORT}/data"; then
        echo -e "${RED}❌ Failed to upload test file${NC}"
        return 1
    fi
    
    # Get the file list
    echo -e "\n${YELLOW}📄 Listing files:${NC}"
    if ! curl -s "http://localhost:${APP_PORT}/data" | jq .; then
        echo -e "${RED}❌ Failed to list files${NC}"
        return 1
    fi
    
    # Clean up
    rm -f "$test_file"
    
    echo -e "${GREEN}✅ File operations test passed${NC}"
    return 0
}

# Main function
main() {
    local all_checks_passed=true
    
    # Check if containers are running
    check_container "minio" || all_checks_passed=false
    check_container "data-app" || all_checks_passed=false
    
    # Check services
    check_service "MinIO" "$MINIO_PORT" "http://localhost:${MINIO_PORT}/minio/health/ready" || all_checks_passed=false
    check_service "Application" "$APP_PORT" "http://localhost:${APP_PORT}/health" || all_checks_passed=false
    
    # Run additional tests if basic checks pass
    if [ "$all_checks_passed" = true ]; then
        test_minio_connection || all_checks_passed=false
        test_health_endpoint || all_checks_passed=false
        test_file_operations || all_checks_passed=false
    fi
    
    # Final result
    if [ "$all_checks_passed" = true ]; then
        echo -e "\n${GREEN}✅ All health checks passed!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some health checks failed${NC}"
        return 1
    fi
}

# Run the main function
main "$@"
