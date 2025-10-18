#!/bin/bash
set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOCK_FILE="/tmp/deploy.lock"
readonly BACKUP_DIR="$PROJECT_ROOT/deploy_backup_$(date +%Y%m%d_%H%M%S)"

# State variables
CURRENT_VERSION=""
ROLLBACK_NEEDED=false

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Release the lock
    rm -f "$LOCK_FILE"
    
    # If we're exiting with an error and rollback is needed
    if [[ $exit_code -ne 0 && "$ROLLBACK_NEEDED" == true ]]; then
        echo -e "\n${YELLOW}⚠️  Deployment failed! Attempting rollback...${NC}"
        if [ -d "$BACKUP_DIR" ]; then
            bash "$SCRIPT_DIR/rollback.sh" "$BACKUP_DIR"
        else
            echo -e "${RED}❌ No backup found for rollback!${NC}"
        fi
    fi
    
    exit $exit_code
}

# Set up trap for cleanup
setup_cleanup() {
    trap cleanup EXIT INT TERM
}

# Acquire deployment lock
acquire_lock() {
    if [ -e "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${RED}❌ Another deployment is already running (PID: $pid)${NC}"
            exit 1
        else
            echo -e "${YELLOW}⚠️  Removing stale lock file${NC}"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo "$$"> "$LOCK_FILE"
}

# Load environment variables
load_environment() {
    echo -e "${YELLOW}🔧 Loading environment...${NC}"
    
    if [ -f "$PROJECT_ROOT/.env" ]; then
        # shellcheck source=/dev/null
        source "$PROJECT_ROOT/.env"
    else
        echo -e "${RED}❌ .env file not found at $PROJECT_ROOT/.env. Please create one from .env.example${NC}"
        exit 1
    fi
    
    # Set defaults
    export APP_PORT=${APP_PORT:-5000}
    export MINIO_PORT=${MINIO_PORT:-9000}
    export NETWORK_NAME=${NETWORK_NAME:-analytics-network}
    export VOLUME_NAME=${VOLUME_NAME:-minio-data}
    export BUCKET_NAME=${BUCKET_NAME:-analytics-data}
    
    echo -e "${GREEN}✅ Environment loaded${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
    local missing_requirements=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_requirements+=("Docker")
    elif ! docker info &> /dev/null; then
        echo -e "${RED}❌ Docker daemon is not running. Please start Docker.${NC}"
        exit 1
    fi
    
    # Check required commands
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_requirements+=("$cmd")
        fi
    done
    
    if [ ${#missing_requirements[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Missing requirements: ${missing_requirements[*]}${NC}"
        echo -e "${YELLOW}   Some features may be limited.${NC}"
    else
        echo -e "${GREEN}✅ All prerequisites met${NC}"
    fi
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

# Backup current deployment
backup_current_deployment() {
    echo -e "${YELLOW}📦 Backing up current deployment...${NC}"
    
    mkdir -p "$BACKUP_DIR"
    
    # Save current container state
    if docker ps -a --format '{{.Names}}' | grep -q '^data-app$'; then
        docker inspect data-app > "${BACKUP_DIR}/container_inspect.json"
        CURRENT_VERSION=$(docker inspect --format '{{.Config.Image}}' data-app)
        echo "CURRENT_VERSION=$CURRENT_VERSION" > "${BACKUP_DIR}/version"
        echo -e "${GREEN}✅ Current version backed up: $CURRENT_VERSION${NC}"
    else
        echo -e "${YELLOW}⚠️  No existing data-app container found${NC}"
    fi
    
    env | grep -E '^(MINIO_|APP_|NETWORK_|VOLUME_|BUCKET_)' > "${BACKUP_DIR}/environment"
    
    echo -e "${GREEN}✅ Backup completed in $BACKUP_DIR${NC}"
}

# Build Docker image and push to ECR
build_docker_image() {
    echo -e "${GREEN}🚀 Building and pushing Docker image to ECR...${NC}\n"

    # Get AWS account ID and use us-east-1 region
    local aws_account_id
    aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    local aws_region="us-east-1"

    # Get the current git commit hash for tagging
    local git_commit
    git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")
    # Login to ECR
    echo -e "${YELLOW}🔐 Logging in to Amazon ECR...${NC}"
    if ! aws ecr get-login-password --region "$aws_region" | docker login --username AWS --password-stdin "${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com"; then
        echo -e "${RED}❌ Failed to authenticate with ECR${NC}"
        return 1
    fi

    # Build the image with multiple tags
    local ecr_image="${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/ds-devops-app:${git_commit}"

    echo -e "\n${YELLOW}🏗️  Building Docker image...${NC}"
    if ! docker build -t "${ecr_image}" -t "${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/ds-devops-app:latest" "$PROJECT_ROOT"; then
        echo -e "${RED}❌ Failed to build Docker image${NC}"
        return 1
    fi

    # Push the image to ECR
    echo -e "\n${YELLOW}🚀 Pushing image to ECR...${NC}"
    if ! docker push "${ecr_image}"; then
        echo -e "${RED}❌ Failed to push image to ECR${NC}"
        return 1
    fi

    # Also push the 'latest' tag
    if ! docker push "${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/ds-devops-app:latest"; then
        echo -e "${YELLOW}⚠️  Warning: Failed to push 'latest' tag to ECR${NC}"
    fi
    
    # Set the image tag for Terraform
    export TF_VAR_image_tag="${git_commit}"

    echo -e "\n${GREEN}✅ Successfully built and pushed Docker image to ECR: ${ecr_image}${NC}"
    return 0
}

deploy() {
    echo -e "${YELLOW}🚀 Starting deployment to AWS ECS...${NC}"

    # Mark that we need rollback if anything fails from now on
    ROLLBACK_NEEDED=true
    # Change to terraform directory
    cd "$PROJECT_ROOT/terraform" || {
        echo -e "${RED}❌ Failed to change to terraform directory${NC}"
        return 1
    }

    # Initialize Terraform if not already
    if [ ! -d ".terraform" ]; then
        echo -e "${YELLOW}🔄 Initializing Terraform...${NC}"
        if ! terraform init; then
            echo -e "${RED}❌ Terraform initialization failed${NC}"
            return 1
        fi
    fi

    # Apply the Terraform configuration
    echo -e "\n${YELLOW}🔄 Applying Terraform configuration...${NC}"
    if ! terraform apply -auto-approve -var="image_tag=${TF_VAR_image_tag:-latest}"; then
        echo -e "${RED}❌ Terraform apply failed${NC}"
        return 1
    fi

    # Get the ALB DNS name
    local alb_dns
    alb_dns=$(terraform output -raw alb_dns_name)

    echo -e "\n${GREEN}✅ Deployment complete!${NC}"
    echo -e "\n${GREEN}🌐 Application URL: http://${alb_dns}${NC}"
    echo -e "${GREEN}📊 MinIO Console: http://${alb_dns}:9001${NC}"

    # Unset rollback flag since deployment was successful
    ROLLBACK_NEEDED=false

    # If we got here, deployment was successful
    ROLLBACK_NEEDED=false
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

# Cleanup old backups
cleanup_old_backups() {
    echo -e "${YELLOW}🧹 Cleaning up old backups...${NC}"
    
    # Keep the 5 most recent backups
    find "$PROJECT_ROOT" -maxdepth 1 -type d -name 'deploy_backup_*' | \
        sort -r | tail -n +6 | xargs rm -rf --
    
    echo -e "${GREEN}✅ Cleanup complete${NC}"
}

# Main execution
main() {
    # Set up error handling
    setup_cleanup
    
    # Ensure only one deployment runs at a time
    acquire_lock
    
    # Load configuration
    load_environment
    
    # Start deployment
    echo -e "\n${GREEN}🚀 Starting deployment process...${NC}"
    
    # Check system requirements
    check_prerequisites
    
    # Backup current deployment
    backup_current_deployment
    
    # Run linting (don't fail on linting errors)
    run_linting || true
    
    # Build and deploy
    build_docker_image
    deploy
    
    # Verify deployment
    run_health_checks
    
    # Cleanup old backups
    cleanup_old_backups
    
    echo -e "\n${GREEN}✨ Deployment completed successfully! ✨${NC}"
    echo -e "\nAccess the application at: http://localhost:${APP_PORT}"
    echo -e "Access MinIO console at: http://localhost:9001"
    echo -e "\nDeployment backup available at: $BACKUP_DIR"
}

# Run the main function
main "$@"

exit 0
