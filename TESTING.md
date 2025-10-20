# Testing Guide

This document provides comprehensive instructions for testing the infrastructure and application components of the Data Analytics Hub DevOps Challenge solution.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Local Development Testing](#local-development-testing)
- [Infrastructure Testing](#infrastructure-testing)
- [Application Testing](#application-testing)
- [CI/CD Pipeline Testing](#cicd-pipeline-testing)
- [Security Testing](#security-testing)
- [Cleanup](#cleanup)

## Prerequisites

1. **Required Tools**
   - [Terraform](https://www.terraform.io/downloads.html) >= 1.0.0
   - [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
   - [Docker](https://docs.docker.com/get-docker/)
   - [Python](https://www.python.org/downloads/) 3.8+
   - [jq](https://stedolan.github.io/jq/download/) for JSON processing

2. **Environment Setup**
   ```bash
   # Install Python dependencies
   pip install -r requirements-test.txt
   
   # Configure AWS credentials
   aws configure
   
   # Verify AWS credentials
   aws sts get-caller-identity
   ```

## Local Development Testing

### 1. Linting and Formatting

```bash
# Format Terraform code
terraform fmt -recursive

# Validate Terraform configuration
cd terraform
terraform init -backend=false
terraform validate
```

### 2. Container Testing

```bash
# Build the Docker image
docker build -t ds-devops-app .

# Run the container locally
docker run -p 5000:5000 -e ENVIRONMENT=development ds-devops-app

# In another terminal, test the application
curl http://localhost:5000/health
# Expected: {"status":"healthy"}
```

## Infrastructure Testing

### 1. Plan and Validate

```bash
cd terraform

# Initialize Terraform
terraform init

# Create a test variables file
cat > test.tfvars <<EOL
environment = "test"
app_name = "test-app"
app_port = 5000
vpc_cidr = "10.1.0.0/16"
public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
EOL

# Run plan to verify configuration
terraform plan -var-file=test.tfvars
```

### 2. Integration Testing

```bash
# Apply the infrastructure (in test environment)
terraform apply -var-file=test.tfvars -auto-approve

# Get the ALB DNS name
export ALB_DNS=$(terraform output -raw alb_dns_name)

# Test application endpoints
curl http://$ALB_DNS:5000/health

# Test MinIO console (if exposed)
curl -I http://$ALB_DNS:9001
```

## Application Testing

### 1. Unit Tests

```bash
# Run Python unit tests
pytest tests/

# With coverage report
pytest --cov=resources tests/
```

### 2. Integration Tests

```bash
# Run integration tests against deployed infrastructure
pytest tests/integration/ --alb-dns=$ALB_DNS
```

## CI/CD Pipeline Testing

1. **Pre-commit Hooks**
   ```bash
   # Install pre-commit
   pip install pre-commit
   pre-commit install
   
   # Run pre-commit checks
   pre-commit run --all-files
   ```

2. **GitHub Actions Workflow**
   - Push changes to a feature branch
   - Create a pull request to trigger the workflow
   - Monitor the workflow execution in GitHub Actions
   - Verify all steps complete successfully

## Security Testing

### 1. Static Code Analysis

```bash
# Run security scan on Terraform code
docker run --rm -v $(pwd):/src -w /src aquasec/tfsec /src/terraform

# Check for misconfigurations
pip install checkov
checkov -d .
```

### 2. Container Scanning

```bash
# Scan the Docker image for vulnerabilities
docker scan ds-devops-app
```

## Cleanup

### 1. Remove Test Infrastructure

```bash
# Destroy test infrastructure
cd terraform
terraform destroy -var-file=test.tfvars -auto-approve

# Remove Docker images
docker rmi ds-devops-app
```

### 2. Clean Up Local Files

```bash
# Remove Terraform state and cache
rm -rf terraform/.terraform* terraform/terraform.tfstate*

# Remove Python cache
find . -type d -name "__pycache__" -exec rm -r {} +
```

## Troubleshooting

### Common Issues

1. **AWS Credentials**
   - Ensure AWS credentials are properly configured
   - Verify the IAM user has sufficient permissions
   - Check for MFA requirements

2. **Terraform State**
   - If state becomes corrupted, you may need to manually remove the `.terraform` directory and reinitialize
   - For S3 backend issues, verify the bucket exists and is accessible

3. **Docker Issues**
   - Ensure Docker daemon is running
   - Check for port conflicts (5000, 9001)

For additional help, please refer to the project documentation or open an issue in the repository.
