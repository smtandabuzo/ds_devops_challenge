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

### 1. Port Already in Use
**Error**: `Address already in use` or `port is already allocated`  
**Solution**:
```bash
# Find and stop the process using the port
sudo lsof -i :<port>
kill -9 <PID>

# Or change the port in your docker run command
# Example: Change -p 5000:5000 to -p 5001:5000
```

### 2. MinIO Connection Refused
**Error**: `ConnectionRefusedError: [Errno 111] Connection refused`  
**Solution**:
1. Check if MinIO is running:
   ```bash
   docker ps | grep minio
   ```
2. Check MinIO logs:
   ```bash
   docker logs minio
   ```
3. Ensure correct credentials in `.env`

### 3. Docker Build Failure
**Error**: `failed to solve: ...`  
**Solution**:
1. Check Docker daemon is running:
   ```bash
   systemctl status docker
   ```
2. Check disk space:
   ```bash
   df -h
   ```
3. Rebuild with no cache:
   ```bash
   docker build --no-cache -t ds-app .
   ```

### 4. Permission Denied on Scripts
**Error**: `Permission denied` when running scripts  
**Solution**:
```bash
chmod +x bin/*.sh
```

### 5. Health Check Failing
**Error**: Health check returns non-200 status  
**Solution**:
1. Check application logs:
   ```bash
   docker logs ds-app
   ```
2. Verify all services are running:
   ```bash
   docker ps
   ```
3. Check network connectivity:
   ```bash
   docker network ls
   docker network inspect bridge
   ```

## Support
For additional help, please open an issue in the GitHub repository or contact the DevOps team.
