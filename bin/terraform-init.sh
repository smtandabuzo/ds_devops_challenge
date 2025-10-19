#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Set working directory from environment variable or use default
TERRAFORM_DIR="${TERRAFORM_WORKING_DIR:-./terraform}"
cd "$TERRAFORM_DIR"

# Initialize Terraform
echo "=== Initializing Terraform ==="
terraform init

# Create workspace if it doesn't exist
echo -e "\n=== Setting up Terraform workspace ==="
if ! terraform workspace list | grep -q default; then
    echo "Creating default workspace..."
    terraform workspace new default
else
    terraform workspace select default
fi

# Create initial state if it doesn't exist
if [ ! -f "terraform.tfstate" ] && [ ! -f "terraform.tfstate.backup" ]; then
    echo -e "\n=== Creating initial Terraform state ==="
    terraform state pull > terraform.tfstate || {
        echo "Failed to create initial state file"
        exit 1
    }
    echo "Initial empty state created."
fi

# Show current state
echo -e "\n=== Current Terraform State ==="
terraform state list || echo "State is empty, which is expected for a new environment"

# Run plan with all required variables
echo -e "\n=== Running Terraform Plan ==="
terraform plan -input=false -no-color \
    -var="region=${AWS_REGION}" \
    -var="environment=production" \
    -var="app_name=${ECR_REPOSITORY}" \
    -var="app_port=5000" \
    -var="app_count=2" \
    -var="minio_access_key=minioadmin" \
    -var="minio_secret_key=minioadmin" \
    -var="image_tag=latest" \
    -out=plan.tfplan

# Check if there are any changes needed
if terraform show -no-color plan.tfplan | grep -q 'No changes.'; then
    echo "No changes needed, infrastructure is up-to-date"
    echo "changes_needed=false" >> $GITHUB_OUTPUT
else
    echo "Changes detected, please apply the plan"
    echo "changes_needed=true" >> $GITHUB_OUTPUT
fi
