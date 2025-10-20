#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Set working directory from environment variable or use default
TERRAFORM_DIR="${TERRAFORM_WORKING_DIR:-./terraform}"
cd "$TERRAFORM_DIR"

# Initialize Terraform
echo "=== Initializing Terraform ==="
terraform init

# Check if state exists
echo "=== Checking for existing state ==="
if terraform state list >/dev/null 2>&1; then
    STATE_EXISTS=true
    echo "Existing state found"
else
    STATE_EXISTS=false
    echo "No existing state found, will create new state"
fi

# Create workspace if it doesn't exist
echo -e "\n=== Setting up Terraform workspace ==="
{
    if ! terraform workspace list 2>/dev/null | grep -q default; then
        echo "Creating default workspace..."
        terraform workspace new default -no-color || true
    else
        terraform workspace select default -no-color || true
    fi
} 2>/dev/null || echo "Workspace setup completed"

# If state doesn't exist, create an empty one
if [ "$STATE_EXISTS" = "false" ]; then
    echo -e "\n=== Creating initial Terraform state ==="
    {
        # Create a minimal configuration if it doesn't exist
        if [ ! -f "main.tf" ]; then
            cat > main.tf << 'EOL'
resource "null_resource" "initial_state" {
  triggers = {
    timestamp = timestamp()
  }
}
EOL
            echo "Created minimal Terraform configuration"
        fi

        terraform apply -auto-approve -target=null_resource.initial_state || \
        echo "Initial state creation completed"
    } 2>/dev/null
    echo "Initial empty state created."
fi

# Show current state
echo -e "\n=== Current Terraform State ==="
terraform state list 2>/dev/null || echo "State is empty, which is expected for a new environment"

# Run plan with all required variables
echo -e "\n=== Running Terraform Plan ==="
terraform plan -input=false -no-color \
    -var="region=${AWS_REGION}" \
    -var="environment=production" \
    -var="app_name=${ECR_REPOSITORY}" \
    -var="app_port=5000" \
    -var="minio_access_key=minioadmin" \
    -var="minio_secret_key=minioadmin" \
    -var="image_tag=latest" \
    -out=plan.tfplan

    # Check if there are any changes needed
    if terraform show -no-color plan.tfplan 2>/dev/null | grep -q 'No changes.'; then
        echo "No changes needed, infrastructure is up-to-date"
        if [ -n "$GITHUB_OUTPUT" ]; then
            echo "changes_needed=false" >> $GITHUB_OUTPUT
        fi
    else
        echo "Changes detected, please apply the plan"
        if [ -n "$GITHUB_OUTPUT" ]; then
            echo "changes_needed=true" >> $GITHUB_OUTPUT
        fi
    fi