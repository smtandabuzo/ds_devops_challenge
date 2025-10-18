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
  - AWS IAM user with appropriate permissions (EC2, ECS, ECR, etc.)
  - SSH key pair for EC2 instance access (or let Terraform create one)

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

### 3. Deploy with Terraform

1. **Set Up SSH Key Pair**
   ```bash
   # Generate a new SSH key pair (if you don't have one)
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/ds-devops-key
   
   # Set proper permissions
   chmod 400 ~/.ssh/ds-devops-key
   
   # View public key (you'll need this for Terraform)
   cat ~/.ssh/ds-devops-key.pub
   ```

2. **Set Up AWS ECR (if not using public images)**
   ```bash
   # Login to ECR
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 810772959397.dkr.ecr.us-east-1.amazonaws.com
   
   # Create ECR repository (if it doesn't exist)
   aws ecr create-repository --repository-name ds-devops-app --region us-east-1
   
   # Build and push your application image
   docker build -t ds-devops-app .
   docker tag ds-devops-app:latest 810772959397.dkr.ecr.us-east-1.amazonaws.com/ds-devops-app:latest
   docker push 810772959397.dkr.ecr.us-east-1.amazonaws.com/ds-devops-app:latest
   ```

3. **Initialize Terraform**
   ```bash
   cd terraform
   
   # If you want Terraform to create the key pair, update the key_name in variables.tf
   # Otherwise, ensure your existing key pair is specified in variables.tf
   
   terraform init
   
   # Review and apply the plan
   terraform plan
   
   # The plan should show the creation of:
   # - aws_key_pair.ec2_key_pair (if creating new key pair)
   # - aws_instance.ecs_instance (using the key pair)
   ```

2. **Review the execution plan**
   ```bash
   terraform plan
   ```

3. **Apply the configuration**
   ```bash
   terraform apply
   ```

### 4. Deploy with Docker (Local Development)

#### Using Public Images
```bash
# Start MinIO (public image)
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  -v minio_data:/data \
  --name minio \
  minio/minio server /data --console-address ":9001"

# Build and start the application
docker build -t ds-app .
docker run -d -p 5000:5000 --name ds-app --network host ds-app
```

#### Using AWS ECR Images
```bash
# Pull and run MinIO from ECR (if using a custom image)
docker pull 810772959397.dkr.ecr.us-east-1.amazonaws.com/your-minio-image:latest
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  -v minio_data:/data \
  --name minio \
  810772959397.dkr.ecr.us-east-1.amazonaws.com/your-minio-image:latest server /data --console-address ":9001"

# Pull and run your application from ECR
docker pull 810772959397.dkr.ecr.us-east-1.amazonaws.com/ds-devops-app:latest
docker run -d -p 5000:5000 --name ds-app --network host 810772959397.dkr.ecr.us-east-1.amazonaws.com/ds-devops-app:latest
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

### Check ECS Cluster Status
```bash
# List container instances in the cluster
aws ecs list-container-instances --cluster ds-devops-app-cluster

# Describe container instances
aws ecs describe-container-instances \
  --cluster ds-devops-app-cluster \
  --container-instances $(aws ecs list-container-instances --cluster ds-devops-app-cluster --query 'containerInstanceArns[0]' --output text)

# List running tasks
aws ecs list-tasks --cluster ds-devops-app-cluster
```

### Verify MinIO Service
```bash
# Check service status
aws ecs describe-services \
  --cluster ds-devops-app-cluster \
  --services minio-service

# Get task details
TASK_ARN=$(aws ecs list-tasks --cluster ds-devops-app-cluster --service-name minio-service --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster ds-devops-app-cluster --tasks $TASK_ARN
```

### Access MinIO Console
1. Get the ALB DNS name:
   ```bash
   aws elbv2 describe-load-balancers --names ds-devops-app-alb --query 'LoadBalancers[0].DNSName' --output text
   ```
2. Open in browser: `http://<ALB_DNS_NAME>:9001`
3. Login with credentials from your Terraform variables

### Check Logs
```bash
# ECS agent logs
sudo tail -f /var/log/ecs/ecs-agent.log

# MinIO container logs
CONTAINER_ID=$(docker ps -q --filter "name=minio")
docker logs -f $CONTAINER_ID
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
**Error**: `ECS task failed to start` or `Insufficient memory available`  
**Solution**:
1. Check ECS service events:
   ```bash
   aws ecs describe-services \
     --cluster ds-devops-app-cluster \
     --services minio-service
   ```
2. Check stopped tasks:
   ```bash
   aws ecs describe-tasks \
     --cluster ds-devops-app-cluster \
     --tasks $(aws ecs list-tasks --cluster ds-devops-app-cluster --service-name minio-service --query 'taskArns' --output text)
   ```
3. **Memory Issues**:
   - Ensure your EC2 instance type has sufficient memory (t3.small or larger recommended)
   - Check task definition memory settings (768MB minimum for MinIO)
   - Verify ECS agent is running: `sudo systemctl status ecs`
   - Check ECS agent logs: `sudo tail -f /var/log/ecs/ecs-agent.log`

### 2. ECS Agent Not Registering with Cluster
**Error**: `Data mismatch; saved cluster 'default' does not match configured cluster`  
**Solution**:
1. Check ECS agent configuration:
   ```bash
   cat /etc/ecs/ecs.config
   ```
2. Update ECS cluster configuration:
   ```bash
   echo "ECS_CLUSTER=ds-devops-app-cluster" | sudo tee /etc/ecs/ecs.config
   ```
3. Clear ECS agent state and restart:
   ```bash
   sudo rm -f /var/lib/ecs/data/ecs_agent_data.json
   sudo systemctl restart ecs
   ```
4. Verify agent status:
   ```bash
   sudo systemctl status ecs
   sudo tail -f /var/log/ecs/ecs-agent.log
   ```

### 3. MinIO Service Health Check Failures
**Error**: `Task failed ELB health checks`  
**Solution**:
1. Check target group health:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn $(aws elbv2 describe-target-groups --names minio-tg --query 'TargetGroups[0].TargetGroupArn' --output text)
   ```
2. Verify security group rules allow traffic on ports 9000 (API) and 9001 (Console)
3. Check MinIO container logs:
   ```bash
   # Get container ID
   CONTAINER_ID=$(docker ps -q --filter "name=minio")
   docker logs $CONTAINER_ID
   ```
4. Verify MinIO service is accessible:
   ```bash
   # From the EC2 instance
   curl -v http://localhost:9000/minio/health/live
   ```
5. Check ECS task logs:
   ```bash
   # Get the most recent task ID
   TASK_ARN=$(aws ecs list-tasks --cluster ds-devops-app-cluster --service-name minio-service --query 'taskArns[0]' --output text)
   
   # Get the log stream name
   LOG_STREAM=$(aws logs describe-log-streams \
     --log-group-name /ecs/minio \
     --order-by LastEventTime \
     --descending \
     --query 'logStreams[0].logStreamName' \
     --output text)
   
   # View the logs
   aws logs get-log-events \
     --log-group-name /ecs/minio \
     --log-stream-name "$LOG_STREAM"
   ```

### 3. SSH Access Issues
**Error**: `Permission denied (publickey)` when trying to SSH to EC2  
**Solution**:
1. Ensure you're using the correct key pair:
   ```bash
   # Check the key pair name in Terraform output
   terraform output -raw key_pair_name
   
   # SSH using the correct key
   ssh -i ~/.ssh/your-key.pem ec2-user@<instance-public-ip>
   ```
2. If using an existing key pair, verify it's correctly specified in `variables.tf`
3. Check security group rules allow SSH access (port 22) from your IP

### 4. ECR Login and Push Issues
**Error**: `no basic auth credentials`  
**Solution**:
1. Ensure you have the AWS CLI configured with proper credentials
2. Log in to ECR:
   ```bash
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin 810772959397.dkr.ecr.us-east-1.amazonaws.com
   ```
3. If pushing fails, verify the repository exists and your IAM user has `ecr:InitiateLayerUpload` and `ecr:UploadLayerPart` permissions

**Error**: `Repository not found`  
**Solution**:
```bash
# Create the repository if it doesn't exist
aws ecr create-repository --repository-name your-repo-name --region us-east-1

# Tag and push the image
docker tag your-image:latest 810772959397.dkr.ecr.us-east-1.amazonaws.com/your-repo-name:latest
docker push 810772959397.dkr.ecr.us-east-1.amazonaws.com/your-repo-name:latest
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

### 4. Viewing ECS Logs

#### View ECS Agent Logs
```bash
# View live ECS agent logs
sudo tail -f /var/log/ecs/ecs-agent.log

# Search for errors
sudo grep -i error /var/log/ecs/ecs-agent.log

# Check cluster registration
sudo grep -i cluster /var/log/ecs/ecs-agent.log
```

#### View MinIO Container Logs
```bash
# Get container ID
CONTAINER_ID=$(docker ps -q --filter "name=minio")

# View logs
docker logs $CONTAINER_ID

# Follow logs
docker logs -f $CONTAINER_ID
```

#### View CloudWatch Logs
```bash
# Get the most recent log stream for MinIO
LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name /ecs/minio \
  --order-by LastEventTime \
  --descending \
  --query 'logStreams[0].logStreamName' \
  --output text)

# View the log events
aws logs get-log-events \
  --log-group-name /ecs/minio \
  --log-stream-name "$LOG_STREAM"
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
