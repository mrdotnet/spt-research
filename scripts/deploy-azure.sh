#!/bin/bash
# Deploy Azure AI Foundry Infrastructure for SPT-Deep
# Usage: ./scripts/deploy-azure.sh [environment] [location]

set -e

# Configuration
ENVIRONMENT="${1:-dev}"
LOCATION="${2:-eastus2}"
PROJECT_NAME="spt-deep"
TERRAFORM_DIR="terraform/azure-foundry"

echo "========================================"
echo "  SPT-Deep Azure AI Foundry Deployment"
echo "========================================"
echo ""
echo "Environment: $ENVIRONMENT"
echo "Location: $LOCATION"
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        echo "Error: Azure CLI not installed. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    if ! command -v terraform &> /dev/null; then
        echo "Error: Terraform not installed. Install from: https://terraform.io/downloads"
        exit 1
    fi

    echo "✓ Prerequisites OK"
}

# Login to Azure
azure_login() {
    echo ""
    echo "Checking Azure authentication..."

    if ! az account show &> /dev/null; then
        echo "Not logged in. Starting Azure login..."
        az login
    fi

    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    TENANT_ID=$(az account show --query tenantId -o tsv)

    echo "✓ Logged in to Azure"
    echo "  Subscription: $SUBSCRIPTION_ID"
    echo "  Tenant: $TENANT_ID"
}

# Initialize Terraform
terraform_init() {
    echo ""
    echo "Initializing Terraform..."

    cd "$TERRAFORM_DIR"

    terraform init -upgrade

    echo "✓ Terraform initialized"
}

# Plan deployment
terraform_plan() {
    echo ""
    echo "Planning deployment..."

    terraform plan \
        -var="environment=$ENVIRONMENT" \
        -var="location=$LOCATION" \
        -var="project_name=$PROJECT_NAME" \
        -out=tfplan

    echo "✓ Plan created"
}

# Apply deployment
terraform_apply() {
    echo ""
    read -p "Apply this plan? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Deployment cancelled"
        exit 0
    fi

    echo "Applying deployment..."

    terraform apply tfplan

    echo "✓ Deployment complete"
}

# Output configuration
output_config() {
    echo ""
    echo "========================================"
    echo "  Deployment Outputs"
    echo "========================================"

    terraform output -json > deployment-outputs.json

    AI_ENDPOINT=$(terraform output -raw ai_services_endpoint 2>/dev/null || echo "N/A")
    OPENAI_ENDPOINT=$(terraform output -raw openai_endpoint 2>/dev/null || echo "N/A")
    KEY_VAULT=$(terraform output -raw key_vault_name 2>/dev/null || echo "N/A")

    echo ""
    echo "Azure AI Services Endpoint: $AI_ENDPOINT"
    echo "Azure OpenAI Endpoint: $OPENAI_ENDPOINT"
    echo "Key Vault: $KEY_VAULT"
    echo ""
    echo "Full outputs saved to: $TERRAFORM_DIR/deployment-outputs.json"

    # Create .env file for local development
    echo ""
    echo "Creating .env configuration..."

    AI_KEY=$(terraform output -raw ai_services_key 2>/dev/null || echo "")
    OPENAI_KEY=$(terraform output -raw openai_key 2>/dev/null || echo "")

    cat > ../../.env.azure << EOF
# Azure AI Foundry Configuration for SPT-Deep
# Generated: $(date)

# Azure AI Services
AZURE_AI_ENDPOINT=$AI_ENDPOINT
AZURE_AI_KEY=$AI_KEY

# Azure OpenAI (fallback)
AZURE_OPENAI_ENDPOINT=$OPENAI_ENDPOINT
AZURE_OPENAI_KEY=$OPENAI_KEY

# Claude Serverless (via Azure AI inference)
AZURE_INFERENCE_ENDPOINT=https://models.inference.ai.azure.com
# Note: Use GitHub PAT for serverless Claude access

# Key Vault (for production secret management)
KEY_VAULT_NAME=$KEY_VAULT
EOF

    echo "✓ Configuration saved to .env.azure"
}

# Main execution
main() {
    check_prerequisites
    azure_login
    terraform_init
    terraform_plan
    terraform_apply
    output_config

    echo ""
    echo "========================================"
    echo "  Deployment Complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "1. Copy .env.azure values to your SPT-Deep settings"
    echo "2. Get a GitHub PAT for Claude serverless access"
    echo "3. Configure the app with your API keys"
    echo ""
}

main "$@"
