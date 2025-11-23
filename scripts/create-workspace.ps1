# Create SPT-Deep Coder Workspace
# Usage: .\scripts\create-workspace.ps1 [-WorkspaceName spt-deep-dev]

param(
    [string]$WorkspaceName = "spt-deep-dev",
    [string]$CoderUrl = "https://coder.smartpoints.tech",
    [string]$TemplateName = "spt-deep-azure"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "  SPT-Deep Workspace Creation"
Write-Host "========================================"
Write-Host ""

# Check prerequisites
try {
    $null = coder version
} catch {
    Write-Host "Error: Coder CLI not installed." -ForegroundColor Red
    Write-Host "Run: .\scripts\setup-tools.ps1" -ForegroundColor Yellow
    exit 1
}

# Login check
try {
    $user = coder whoami --output json 2>$null | ConvertFrom-Json
    if (-not $user) { throw }
} catch {
    Write-Host "Logging in to Coder..."
    coder login $CoderUrl
}

# Check if workspace exists
$workspaces = coder list --output json 2>$null | ConvertFrom-Json
$existing = $workspaces | Where-Object { $_.name -eq $WorkspaceName }

if ($existing) {
    Write-Host "Workspace '$WorkspaceName' already exists."
    $startExisting = Read-Host "Start existing workspace? (yes/no)"

    if ($startExisting -eq "yes") {
        coder start $WorkspaceName
        Write-Host ""
        Write-Host "Workspace started!" -ForegroundColor Green
        Write-Host "Access VS Code: coder open $WorkspaceName"
        exit 0
    } else {
        exit 0
    }
}

# Prompt for configuration
Write-Host "Creating new workspace: $WorkspaceName"
Write-Host ""

$AzureEndpoint = Read-Host "Azure AI Endpoint [https://models.inference.ai.azure.com]"
if (-not $AzureEndpoint) { $AzureEndpoint = "https://models.inference.ai.azure.com" }

$AzureKey = Read-Host "Azure AI Key / GitHub Token" -AsSecureString
$AzureKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AzureKey))

$AnthropicKey = Read-Host "Anthropic API Key (optional, press Enter to skip)" -AsSecureString
$AnthropicKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AnthropicKey))

$Location = Read-Host "Azure Region [eastus2]"
if (-not $Location) { $Location = "eastus2" }

$VmSize = Read-Host "VM Size [Standard_D4s_v5]"
if (-not $VmSize) { $VmSize = "Standard_D4s_v5" }

$DiskSize = Read-Host "Disk Size GB [64]"
if (-not $DiskSize) { $DiskSize = "64" }

# Create workspace
Write-Host ""
Write-Host "Creating workspace..."

$params = @(
    "create", $WorkspaceName,
    "--template", $TemplateName,
    "--parameter", "location=$Location",
    "--parameter", "instance_type=$VmSize",
    "--parameter", "home_disk_size=$DiskSize",
    "--parameter", "azure_ai_endpoint=$AzureEndpoint",
    "--parameter", "azure_ai_key=$AzureKeyPlain",
    "--parameter", "git_repo=https://github.com/MrDotnet/spt-deep.git",
    "--yes"
)

if ($AnthropicKeyPlain) {
    $params += "--parameter"
    $params += "anthropic_api_key=$AnthropicKeyPlain"
}

& coder @params

Write-Host ""
Write-Host "========================================"
Write-Host "  Workspace Created!"
Write-Host "========================================"
Write-Host ""
Write-Host "Workspace: $WorkspaceName"

$user = coder whoami --output json | ConvertFrom-Json
Write-Host "URL: $CoderUrl/@$($user.username)/$WorkspaceName"
Write-Host ""
Write-Host "Quick commands:"
Write-Host "  coder ssh $WorkspaceName          # SSH into workspace"
Write-Host "  coder open $WorkspaceName         # Open in VS Code"
Write-Host "  coder port-forward $WorkspaceName # Forward ports"
Write-Host ""
Write-Host "SPT-Deep commands (inside workspace):"
Write-Host "  spt-deep-ctl start   # Start SPT-Deep in background"
Write-Host "  spt-deep-ctl logs    # View logs"
Write-Host "  spt-deep-ctl status  # Check status"
Write-Host ""
