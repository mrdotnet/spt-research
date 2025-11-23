# Setup Tools for SPT-Deep Development
# Installs Terraform, Azure CLI, and Coder CLI on Windows

$ErrorActionPreference = "Stop"

Write-Host "========================================"
Write-Host "  SPT-Deep Development Tools Setup"
Write-Host "========================================"
Write-Host ""

# Check for winget
function Test-Winget {
    try {
        $null = Get-Command winget -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Check for chocolatey
function Test-Chocolatey {
    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Install Terraform
function Install-Terraform {
    Write-Host "Checking Terraform..."

    try {
        $version = terraform version 2>$null
        if ($version) {
            Write-Host "  Terraform already installed: $($version.Split("`n")[0])" -ForegroundColor Green
            return
        }
    } catch {}

    Write-Host "  Installing Terraform..."

    if (Test-Winget) {
        winget install HashiCorp.Terraform --accept-source-agreements --accept-package-agreements
    } elseif (Test-Chocolatey) {
        choco install terraform -y
    } else {
        # Manual installation
        $terraformVersion = "1.6.6"
        $downloadUrl = "https://releases.hashicorp.com/terraform/${terraformVersion}/terraform_${terraformVersion}_windows_amd64.zip"
        $downloadPath = "$env:TEMP\terraform.zip"
        $installPath = "$env:LOCALAPPDATA\Programs\Terraform"

        Write-Host "  Downloading Terraform $terraformVersion..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath

        Write-Host "  Extracting..."
        New-Item -ItemType Directory -Force -Path $installPath | Out-Null
        Expand-Archive -Path $downloadPath -DestinationPath $installPath -Force
        Remove-Item $downloadPath

        # Add to PATH for current session
        $env:PATH = "$installPath;$env:PATH"

        # Add to user PATH permanently
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath -notlike "*$installPath*") {
            [Environment]::SetEnvironmentVariable("PATH", "$installPath;$userPath", "User")
            Write-Host "  Added Terraform to PATH. Restart terminal to use."
        }
    }

    Write-Host "  Terraform installed!" -ForegroundColor Green
}

# Install Azure CLI
function Install-AzureCLI {
    Write-Host "Checking Azure CLI..."

    try {
        $version = az version 2>$null | ConvertFrom-Json
        if ($version) {
            Write-Host "  Azure CLI already installed: $($version.'azure-cli')" -ForegroundColor Green
            return
        }
    } catch {}

    Write-Host "  Installing Azure CLI..."

    if (Test-Winget) {
        winget install Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements
    } elseif (Test-Chocolatey) {
        choco install azure-cli -y
    } else {
        # MSI installer
        $downloadUrl = "https://aka.ms/installazurecliwindows"
        $downloadPath = "$env:TEMP\AzureCLI.msi"

        Write-Host "  Downloading Azure CLI..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath

        Write-Host "  Installing (this may take a few minutes)..."
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$downloadPath`" /quiet"
        Remove-Item $downloadPath
    }

    Write-Host "  Azure CLI installed!" -ForegroundColor Green
}

# Install Coder CLI
function Install-CoderCLI {
    Write-Host "Checking Coder CLI..."

    try {
        $version = coder version 2>$null
        if ($version) {
            Write-Host "  Coder CLI already installed: $version" -ForegroundColor Green
            return
        }
    } catch {}

    Write-Host "  Installing Coder CLI..."

    if (Test-Winget) {
        winget install Coder.Coder --accept-source-agreements --accept-package-agreements
    } elseif (Test-Chocolatey) {
        choco install coder -y
    } else {
        # PowerShell install script
        $installScript = Invoke-WebRequest -Uri "https://coder.com/install.ps1" -UseBasicParsing
        Invoke-Expression $installScript.Content
    }

    Write-Host "  Coder CLI installed!" -ForegroundColor Green
}

# Install Node.js
function Install-NodeJS {
    Write-Host "Checking Node.js..."

    try {
        $version = node --version 2>$null
        if ($version) {
            Write-Host "  Node.js already installed: $version" -ForegroundColor Green
            return
        }
    } catch {}

    Write-Host "  Installing Node.js LTS..."

    if (Test-Winget) {
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    } elseif (Test-Chocolatey) {
        choco install nodejs-lts -y
    } else {
        Write-Host "  Please install Node.js manually from: https://nodejs.org/" -ForegroundColor Yellow
    }
}

# Main execution
Write-Host "Installing development tools..."
Write-Host ""

Install-NodeJS
Install-Terraform
Install-AzureCLI
Install-CoderCLI

Write-Host ""
Write-Host "========================================"
Write-Host "  Setup Complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "Please restart your terminal for PATH changes to take effect."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Run: az login"
Write-Host "  2. Run: coder login https://coder.smartpoints.tech"
Write-Host "  3. Run: .\scripts\deploy-azure.ps1"
Write-Host ""
