# Deploy Azure AI Foundry Infrastructure for SPT-Deep
# Usage: .\scripts\deploy-azure.ps1 [-Environment dev] [-Location eastus2]

param(
    [string]$Environment = "dev",
    [string]$Location = "eastus2",
    [string]$ProjectName = "spt-deep"
)

$ErrorActionPreference = "Stop"
$TerraformDir = "terraform\azure-foundry"

Write-Host "========================================"
Write-Host "  SPT-Deep Azure AI Foundry Deployment"
Write-Host "========================================"
Write-Host ""
Write-Host "Environment: $Environment"
Write-Host "Location: $Location"
Write-Host ""

# Check prerequisites
function Test-Prerequisites {
    Write-Host "Checking prerequisites..."

    # Check Terraform
    try {
        $null = terraform version
        Write-Host "  Terraform: OK" -ForegroundColor Green
    } catch {
        Write-Host "  Terraform: NOT FOUND" -ForegroundColor Red
        Write-Host "  Run: .\scripts\setup-tools.ps1" -ForegroundColor Yellow
        exit 1
    }

    # Check Azure CLI
    try {
        $null = az version
        Write-Host "  Azure CLI: OK" -ForegroundColor Green
    } catch {
        Write-Host "  Azure CLI: NOT FOUND" -ForegroundColor Red
        Write-Host "  Run: .\scripts\setup-tools.ps1" -ForegroundColor Yellow
        exit 1
    }
}

# Login to Azure
function Connect-Azure {
    Write-Host ""
    Write-Host "Checking Azure authentication..."

    try {
        $account = az account show 2>$null | ConvertFrom-Json
        if ($account) {
            Write-Host "  Logged in to Azure" -ForegroundColor Green
            Write-Host "  Subscription: $($account.id)"
            Write-Host "  Tenant: $($account.tenantId)"
            return
        }
    } catch {}

    Write-Host "  Not logged in. Starting Azure login..."
    az login
}

# Initialize Terraform
function Initialize-Terraform {
    Write-Host ""
    Write-Host "Initializing Terraform..."

    Push-Location $TerraformDir
    try {
        terraform init -upgrade
        Write-Host "  Terraform initialized" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# Plan deployment
function New-TerraformPlan {
    Write-Host ""
    Write-Host "Planning deployment..."

    Push-Location $TerraformDir
    try {
        terraform plan `
            -var="environment=$Environment" `
            -var="location=$Location" `
            -var="project_name=$ProjectName" `
            -out=tfplan

        Write-Host "  Plan created" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# Apply deployment
function Invoke-TerraformApply {
    Write-Host ""
    $confirm = Read-Host "Apply this plan? (yes/no)"

    if ($confirm -ne "yes") {
        Write-Host "Deployment cancelled"
        exit 0
    }

    Write-Host "Applying deployment..."

    Push-Location $TerraformDir
    try {
        terraform apply tfplan
        Write-Host "  Deployment complete" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# Output configuration
function Export-Configuration {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Deployment Outputs"
    Write-Host "========================================"

    Push-Location $TerraformDir
    try {
        # Get outputs
        $outputs = terraform output -json | ConvertFrom-Json

        $aiEndpoint = terraform output -raw ai_services_endpoint 2>$null
        $openaiEndpoint = terraform output -raw openai_endpoint 2>$null
        $keyVault = terraform output -raw key_vault_name 2>$null

        Write-Host ""
        Write-Host "Azure AI Services Endpoint: $aiEndpoint"
        Write-Host "Azure OpenAI Endpoint: $openaiEndpoint"
        Write-Host "Key Vault: $keyVault"

        # Create .env file
        Write-Host ""
        Write-Host "Creating .env configuration..."

        $aiKey = terraform output -raw ai_services_key 2>$null
        $openaiKey = terraform output -raw openai_key 2>$null

        $envContent = @"
# Azure AI Foundry Configuration for SPT-Deep
# Generated: $(Get-Date)

# Azure AI Services
AZURE_AI_ENDPOINT=$aiEndpoint
AZURE_AI_KEY=$aiKey

# Azure OpenAI (fallback)
AZURE_OPENAI_ENDPOINT=$openaiEndpoint
AZURE_OPENAI_KEY=$openaiKey

# Claude Serverless (via Azure AI inference)
AZURE_INFERENCE_ENDPOINT=https://models.inference.ai.azure.com
# Note: Use GitHub PAT for serverless Claude access

# Key Vault (for production secret management)
KEY_VAULT_NAME=$keyVault
"@

        $envContent | Out-File -FilePath "..\..\env.azure" -Encoding UTF8
        Write-Host "  Configuration saved to .env.azure" -ForegroundColor Green

    } finally {
        Pop-Location
    }
}

# Main execution
Test-Prerequisites
Connect-Azure
Initialize-Terraform
New-TerraformPlan
Invoke-TerraformApply
Export-Configuration

Write-Host ""
Write-Host "========================================"
Write-Host "  Deployment Complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Copy .env.azure values to your SPT-Deep settings"
Write-Host "2. Get a GitHub PAT for Claude serverless access"
Write-Host "3. Configure the app with your API keys"
Write-Host ""
