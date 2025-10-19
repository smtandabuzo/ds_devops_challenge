#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Set working directory from environment variable or use default
TERRAFORM_DIR="${TERRAFORM_WORKING_DIR:-./terraform}"
cd "$TERRAFORM_DIR"

# Initialize Terraform
echo "=== Initializing Terraform ==="
terraform init

# Check if state exists
STATE_EXISTS=$(terraform state list 2>/dev/null || echo "false")

# Create workspace if it doesn't exist
echo -e "\n=== Setting up Terraform workspace ==="
if ! terraform workspace list | grep -q default; then
    echo "Creating default workspace..."
    terraform workspace new default || true
else
    terraform workspace select default || true
fi

# If state doesn't exist, create an empty one
if [ "$STATE_EXISTS" = "false" ]; then
    echo -e "\n=== Initializing empty Terraform state ==="
    terraform apply -auto-approve -target=null_resource.initial_state || {
        echo "No resources to create for initial state. This is normal for a new environment."
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
if terraform show -no-color plan.tfplan 2>/dev/null | grep -q 'No changes.'; then
    echo "No changes needed, infrastructure is up-to-date"
    echo "changes_needed=false" >> $GITHUB_OUTPUT
else
    echo "Changes detected, please apply the plan"
    echo "changes_needed=true" >> $GITHUB_OUTPUT
fi
