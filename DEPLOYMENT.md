# Deployment Guide

This document provides detailed instructions for deploying and managing the Data Science DevOps Challenge application.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Deployment Instructions](#deployment-instructions)
3. [Running Deployment Scripts](#running-deployment-scripts)
4. [Verifying Deployment](#verifying-deployment)
5. [Rollback Procedure](#rollback-procedure)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting the deployment, ensure you have the following:

- **Local Development**
  - Docker 20.10.0 or higher
  - Python 3.8+
  - Git

- **Server Requirements**
  - Ubuntu 20.04 LTS or higher (recommended)
  - 2 CPU cores (minimum)
  - 4GB RAM (minimum)
  - 20GB free disk space
  - Open ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 5000 (Flask App), 9000-9001 (MinIO)

- **Credentials**
  - GitHub repository access
  - SSH access to the deployment server
  - MinIO access and secret keys

## Deployment Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/ds_devops_challenge.git
cd ds_devops_challenge
```

### 2. Set Up Environment Variables
Create a `.env` file in the project root:
```bash
cp .env.example .env
# Edit the .env file with your configuration
nano .env
```

### 3. Deploy with Docker
```bash
# Build and start the application
docker build -t ds-app .
docker run -d -p 5000:5000 --name ds-app ds-app

# Start MinIO
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  -e "MINIO_ROOT_USER=your-access-key" \
  -e "MINIO_ROOT_PASSWORD=your-secret-key" \
  --name minio \
  minio/minio server /data --console-address ":9001"
```

### 4. Initialize MinIO
1. Access MinIO Console at `http://your-server-ip:9001`
2. Login with credentials from your `.env` file
3. Create a new bucket named `analytics-data`
4. Set bucket policy to `public` if needed

## Running Deployment Scripts

### Manual Deployment
```bash
# Make scripts executable
chmod +x bin/*.sh

# Run deployment
./bin/deploy.sh
```

### CI/CD Pipeline
1. Push to `main` branch
2. GitHub Actions will automatically:
   - Run tests
   - Build Docker images
   - Deploy to the target server
   - Run health checks

## Verifying Deployment

### Check Running Services
```bash
docker ps
```

### Verify API Endpoints
```bash
# Health check
curl http://localhost:5000/health

# List files in MinIO
curl http://localhost:5000/data
```

### Check Logs
```bash
# Application logs
docker logs -f ds-app

# MinIO logs
docker logs -f minio
```

## Rollback Procedure

### Manual Rollback
1. Find the previous working version:
   ```bash
   git log --oneline
   ```

2. Revert to previous version:
   ```bash
   git checkout <commit-hash>
   docker build -t ds-app .
   docker stop ds-app
   docker rm ds-app
   docker run -d -p 5000:5000 --name ds-app ds-app
   ```

### Using Rollback Script
```bash
./bin/rollback.sh <version-tag>
```

## Troubleshooting

### 1. ECS Service Fails to Start
**Error**: `ECS task failed to start`  
**Solution**:
1. Check ECS service events:
   ```bash
   aws ecs describe-services \
     --cluster ds-devops-app-cluster \
     --services ds-devops-app-service
   ```
2. Check stopped tasks:
   ```bash
   aws ecs describe-tasks \
     --cluster ds-devops-app-cluster \
     --tasks $(aws ecs list-tasks --cluster ds-devops-app-cluster --service-name ds-devops-app-service --query 'taskArns' --output text)
   ```

### 2. Container Health Check Failures
**Error**: `Task failed ELB health checks`  
**Solution**:
1. Check target group health:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn arn:aws:elasticloadbalancing:us-east-1:810772959397:targetgroup/ds-devops-app-tg/9e96df569e8821c8
   ```
2. Verify security group rules allow traffic on port 5000
3. Check application logs for errors

### 3. ECR Login Issues
**Error**: `no basic auth credentials`  
**Solution**:
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 810772959397.dkr.ecr.us-east-1.amazonaws.com
```

### 4. Terraform State Locked
**Error**: `Error acquiring the state lock`  
**Solution**:
```bash
# List and remove lock if needed
aws s3 ls s3://ds-devops-tfstate-810772959397/
aws s3 rm s3://ds-devops-tfstate-810772959397/terraform.tfstate.lock.info
```

### 5. Service Discovery Issues
**Error**: `ServiceDiscovery:ListTagsForResource` permission error  
**Solution**:
Ensure IAM user has `servicediscovery:*` permissions or specifically:
- `servicediscovery:ListTagsForResource`
- `servicediscovery:CreatePrivateDnsNamespace`
- `servicediscovery:CreateService`

### 6. Viewing Logs
```bash
# Get the most recent log stream
LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name /ecs/ds-devops-app \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].logStreamName' \
  --output text)

# View the logs
aws logs get-log-events \
  --log-group-name /ecs/ds-devops-app \
  --log-stream-name "$LOG_STREAM" \
  --query 'events[].message' \
  --output text
```

### 7. Scaling the Service
```bash
# Update the desired count
aws ecs update-service \
  --cluster ds-devops-app-cluster \
  --service ds-devops-app-service \
  --desired-count 2 \
  --force-new-deployment
```

### 8. Cleaning Up
To destroy all resources:
```bash
cd terraform
terraform destroy
```

### 9. Common Issues
- **Insufficient IAM Permissions**: Ensure the IAM user has all required permissions
- **VPC/Subnet Issues**: Verify the VPC and subnets exist and are properly configured
- **Container Port Mismatch**: Ensure the container port in the task definition matches the application port
- **Task Definition Issues**: Check CPU and memory allocations in the task definition

For additional help, check the AWS documentation or contact your AWS administrator.
   ```bash
   docker network ls
   docker network inspect bridge
   ```

## Support
For additional help, please open an issue in the GitHub repository or contact the DevOps team.
