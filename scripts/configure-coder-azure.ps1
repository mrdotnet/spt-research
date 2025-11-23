# Configure Coder Server with Azure Credentials
# Usage: .\scripts\configure-coder-azure.ps1 -SshKeyPath "path\to\svs-devops.pem"

param(
    [Parameter(Mandatory=$true)]
    [string]$SshKeyPath,

    [string]$CoderServer = "coder.smartpoints.tech",
    [string]$SshUser = "sptadmin",

    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret
)

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "  Coder Server Azure Configuration"
Write-Host "========================================"
Write-Host ""

# Verify SSH key exists
if (-not (Test-Path $SshKeyPath)) {
    Write-Host "Error: SSH key not found at $SshKeyPath" -ForegroundColor Red
    exit 1
}

Write-Host "Configuring Azure credentials on Coder server..."
Write-Host "Server: $CoderServer"
Write-Host "User: $SshUser"
Write-Host ""

# Create the environment file content
$envContent = @"
# Azure Service Principal credentials for Coder Terraform templates
ARM_SUBSCRIPTION_ID=$SubscriptionId
ARM_TENANT_ID=$TenantId
ARM_CLIENT_ID=$ClientId
ARM_CLIENT_SECRET=$ClientSecret
"@

# SSH command to add environment variables to Coder systemd service
$sshCommands = @"
# Create Azure credentials environment file
sudo tee /etc/coder.d/azure.env > /dev/null << 'EOF'
$envContent
EOF

sudo chmod 600 /etc/coder.d/azure.env

# Check if Coder is running as systemd service
if systemctl is-active --quiet coder; then
    # Add environment file to Coder service override
    sudo mkdir -p /etc/systemd/system/coder.service.d
    sudo tee /etc/systemd/system/coder.service.d/azure.conf > /dev/null << 'EOF'
[Service]
EnvironmentFile=/etc/coder.d/azure.env
EOF

    sudo systemctl daemon-reload
    sudo systemctl restart coder
    echo "Coder service restarted with Azure credentials"
else
    # Check if running via Docker
    if docker ps | grep -q coder; then
        echo "Coder is running in Docker. Please add these environment variables to your docker-compose.yml or docker run command:"
        cat /etc/coder.d/azure.env
    else
        echo "Warning: Could not detect Coder service. Environment file created at /etc/coder.d/azure.env"
        echo "Add these to your Coder startup configuration."
    fi
fi

echo ""
echo "Azure credentials configured successfully!"
"@

# Execute SSH command
Write-Host "Connecting to $CoderServer..."
Write-Host ""

# Use ssh with the PEM key
ssh -i $SshKeyPath -o StrictHostKeyChecking=no "$SshUser@$CoderServer" $sshCommands

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Configuration Complete!"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Azure credentials have been configured on the Coder server."
    Write-Host "All templates can now provision Azure resources."
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Deploy the spt-deep-azure template:"
    Write-Host "     coder templates push spt-deep-azure --directory terraform\coder-template"
    Write-Host ""
    Write-Host "  2. Create a workspace:"
    Write-Host "     .\scripts\create-workspace.ps1"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Error: Failed to configure Coder server" -ForegroundColor Red
    Write-Host "Check SSH connection and try again."
    exit 1
}
