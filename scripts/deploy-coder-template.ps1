# Deploy SPT-Deep Coder Template
# Usage: .\scripts\deploy-coder-template.ps1

param(
    [string]$CoderUrl = "https://coder.smartpoints.tech",
    [string]$TemplateName = "spt-deep-azure"
)

$ErrorActionPreference = "Stop"
$TemplateDir = "terraform\coder-template"

Write-Host "========================================"
Write-Host "  SPT-Deep Coder Template Deployment"
Write-Host "========================================"
Write-Host ""
Write-Host "Coder URL: $CoderUrl"
Write-Host "Template: $TemplateName"
Write-Host ""

# Check prerequisites
function Test-Prerequisites {
    Write-Host "Checking prerequisites..."

    try {
        $null = coder version
        Write-Host "  Coder CLI: OK" -ForegroundColor Green
    } catch {
        Write-Host "  Coder CLI: NOT FOUND" -ForegroundColor Red
        Write-Host "  Run: .\scripts\setup-tools.ps1" -ForegroundColor Yellow
        exit 1
    }
}

# Login to Coder
function Connect-Coder {
    Write-Host ""
    Write-Host "Checking Coder authentication..."

    try {
        $user = coder whoami --output json 2>$null | ConvertFrom-Json
        if ($user) {
            Write-Host "  Logged in as: $($user.username)" -ForegroundColor Green
            return
        }
    } catch {}

    Write-Host "  Not logged in. Starting Coder login..."
    coder login $CoderUrl
}

# Deploy template
function Deploy-Template {
    Write-Host ""
    Write-Host "Deploying template..."

    # Check if template exists
    $templates = coder templates list --output json 2>$null | ConvertFrom-Json
    $exists = $templates | Where-Object { $_.name -eq $TemplateName }

    if ($exists) {
        Write-Host "  Template exists. Updating..."
        coder templates push $TemplateName --directory $TemplateDir --yes
    } else {
        Write-Host "  Creating new template..."
        coder templates create $TemplateName --directory $TemplateDir --yes
    }

    Write-Host "  Template deployed!" -ForegroundColor Green
}

# Show info
function Show-Info {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Template Deployed!"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Template: $TemplateName"
    Write-Host "URL: $CoderUrl/templates/$TemplateName"
    Write-Host ""
    Write-Host "To create a workspace:"
    Write-Host "  coder create my-spt-deep --template $TemplateName"
    Write-Host ""
    Write-Host "Or run: .\scripts\create-workspace.ps1"
    Write-Host ""
}

# Main execution
Test-Prerequisites
Connect-Coder
Deploy-Template
Show-Info
