#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the environment file
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo -e "${RED}Error: .env file not found. Please create one from .env.example${NC}"
    exit 1
fi

echo -e "${GREEN}🚀 Starting deployment process...${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        echo -e "${RED}❌ Docker daemon is not running. Please start Docker.${NC}"
        exit 1
    fi
    
    # Check Python for linting
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}⚠️  Python 3 is not installed. Skipping Python linting.${NC}"
        return 1
    fi
    
    return 0
}

# Run Python linting
run_linting() {
    echo -e "${YELLOW}🔍 Running Python linting...${NC}"
    
    if ! command -v flake8 &> /dev/null; then
        echo -e "${YELLOW}⚠️  flake8 not found. Installing...${NC}"
        pip3 install --user flake8
    fi
    
    if ! flake8 "$PROJECT_ROOT/resources"; then
        echo -e "${YELLOW}⚠️  Linting issues found. Continuing deployment...${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Linting passed!${NC}"
    return 0
}

# Build Docker image
build_docker_image() {
    echo -e "${YELLOW}🔨 Building Docker image...${NC}"
    
    local timestamp=$(date +%Y%m%d%H%M%S)
    local git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    # Build with multiple tags
    docker build \
        -t "data-app:latest" \
        -t "data-app:${timestamp}" \
        -t "data-app:${git_sha}" \
        -f "$PROJECT_ROOT/Dockerfile" \
        "$PROJECT_ROOT"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Docker build failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker image built successfully!${NC}"
}

# Main deployment function
deploy() {
    echo -e "${YELLOW}🚀 Starting deployment...${NC}"
    
    # Run the deployment script
    if ! bash "$SCRIPT_DIR/deploy-app.sh"; then
        echo -e "${RED}❌ Deployment failed!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
}

# Run health checks
run_health_checks() {
    echo -e "${YELLOW}🏥 Running health checks...${NC}"
    
    if ! bash "$SCRIPT_DIR/health-check.sh"; then
        echo -e "${RED}❌ Health checks failed!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All health checks passed!${NC}"
}

# Main execution
main() {
    check_prerequisites
    run_linting || true  # Don't fail on linting errors
    build_docker_image
    deploy
    run_health_checks
    
    echo -e "${GREEN}✨ Deployment completed successfully! ✨${NC}"
    echo -e "\nAccess the application at: http://localhost:${APP_PORT:-5000}"
    echo -e "Access MinIO console at: http://localhost:9001"
}

# Run the main function
main "$@"
