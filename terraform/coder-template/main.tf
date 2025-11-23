# Coder Template for SPT-Deep Development Workspace
# Based on Azure Linux template with VS Code, Claude Code, and persistent SPT-Deep runner

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

# Azure Provider - uses environment variables set on Coder server:
# ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET
# These should be configured by the Coder server administrator
provider "azurerm" {
  features {}
  # Uses environment variables by default:
  # ARM_SUBSCRIPTION_ID = "85579fe1-921e-43ca-8ad0-95ea618035c9"
  # ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET from Service Principal
}

# Coder workspace data
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Parameters
data "coder_parameter" "location" {
  name         = "location"
  display_name = "Azure Region"
  description  = "Azure region for the workspace"
  default      = "eastus2"
  mutable      = false
  option {
    name  = "East US 2"
    value = "eastus2"
  }
  option {
    name  = "West US 2"
    value = "westus2"
  }
  option {
    name  = "North Europe"
    value = "northeurope"
  }
  option {
    name  = "UK South"
    value = "uksouth"
  }
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "VM Size"
  description  = "Azure VM size for the workspace"
  default      = "Standard_D4s_v5"
  mutable      = true
  option {
    name  = "2 vCPU, 8 GB RAM (Standard_D2s_v5)"
    value = "Standard_D2s_v5"
  }
  option {
    name  = "4 vCPU, 16 GB RAM (Standard_D4s_v5)"
    value = "Standard_D4s_v5"
  }
  option {
    name  = "8 vCPU, 32 GB RAM (Standard_D8s_v5)"
    value = "Standard_D8s_v5"
  }
  option {
    name  = "16 vCPU, 64 GB RAM (Standard_D16s_v5)"
    value = "Standard_D16s_v5"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home Disk Size (GB)"
  description  = "Size of the home directory disk (32-512 GB)"
  default      = "64"
  type         = "number"
  mutable      = true
  validation {
    min = 32
    max = 512
  }
}

data "coder_parameter" "azure_ai_endpoint" {
  name         = "azure_ai_endpoint"
  display_name = "Azure AI Endpoint"
  description  = "Azure AI Foundry inference endpoint"
  default      = "https://models.inference.ai.azure.com"
  mutable      = true
}

data "coder_parameter" "azure_ai_key" {
  name         = "azure_ai_key"
  display_name = "Azure AI Key / GitHub Token"
  description  = "API key for Azure AI inference (GitHub PAT for serverless Claude)"
  mutable      = true
  type         = "string"
}

data "coder_parameter" "anthropic_api_key" {
  name         = "anthropic_api_key"
  display_name = "Anthropic API Key (Direct)"
  description  = "Optional: Direct Anthropic API key as fallback"
  mutable      = true
  type         = "string"
  default      = ""
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git Repository"
  description  = "Repository to clone"
  default      = "https://github.com/mrdotnet/spt-research.git"
  mutable      = true
}

# Locals
locals {
  workspace_name = lower("spt-deep-${data.coder_workspace.me.name}")
  username       = "coder"
  home_dir       = "/home/${local.username}"
  repo_name      = "spt-research"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-coder-${local.workspace_name}"
  location = data.coder_parameter.location.value
  tags = {
    Coder_Provisioned = "true"
    Workspace         = data.coder_workspace.me.name
    Owner             = data.coder_workspace_owner.me.name
    Project           = "SPT-Deep"
  }
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.workspace_name}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "snet-${local.workspace_name}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${local.workspace_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Coder"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "13337"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SPT-Deep-Electron"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5173"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "pip-${local.workspace_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "nic-${local.workspace_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Cloud-init configuration
data "cloudinit_config" "main" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      users = [{
        name                = local.username
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        groups              = ["docker", "sudo"]
        ssh_authorized_keys = []
      }]

      packages = [
        "curl",
        "wget",
        "git",
        "jq",
        "htop",
        "tmux",
        "unzip",
        "build-essential",
        "python3",
        "python3-pip",
        "xvfb",
        "x11vnc",
        "fluxbox",
        "libgtk-3-0",
        "libnotify4",
        "libnss3",
        "libxss1",
        "libxtst6",
        "xdg-utils",
        "libatspi2.0-0",
        "libdrm2",
        "libgbm1",
        "libasound2",
      ]

      write_files = [
        {
          path    = "${local.home_dir}/.spt-deep-env"
          content = <<-EOT
            export AZURE_AI_ENDPOINT="${data.coder_parameter.azure_ai_endpoint.value}"
            export AZURE_AI_KEY="${data.coder_parameter.azure_ai_key.value}"
            export ANTHROPIC_API_KEY="${data.coder_parameter.anthropic_api_key.value}"
            export SPT_DEEP_HOME="${local.home_dir}/${local.repo_name}"
            export DISPLAY=:99
          EOT
          owner   = "${local.username}:${local.username}"
          permissions = "0600"
        },
        {
          path    = "/etc/systemd/system/spt-deep.service"
          content = <<-EOT
            [Unit]
            Description=SPT-Deep Infinite Thought Engine
            After=network.target xvfb.service

            [Service]
            Type=simple
            User=${local.username}
            WorkingDirectory=${local.home_dir}/${local.repo_name}
            Environment=DISPLAY=:99
            Environment=NODE_ENV=production
            EnvironmentFile=${local.home_dir}/.spt-deep-env
            ExecStart=/usr/bin/npm run dev
            Restart=always
            RestartSec=10

            [Install]
            WantedBy=multi-user.target
          EOT
        },
        {
          path    = "/etc/systemd/system/xvfb.service"
          content = <<-EOT
            [Unit]
            Description=X Virtual Frame Buffer
            After=network.target

            [Service]
            Type=simple
            ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24
            Restart=always

            [Install]
            WantedBy=multi-user.target
          EOT
        },
        {
          path    = "${local.home_dir}/.config/code-server/config.yaml"
          content = <<-EOT
            bind-addr: 127.0.0.1:8080
            auth: none
            cert: false
          EOT
          owner   = "${local.username}:${local.username}"
        },
        {
          path    = "${local.home_dir}/bin/spt-deep-ctl"
          content = <<-EOT
            #!/bin/bash
            # SPT-Deep Control Script

            case "$1" in
              start)
                sudo systemctl start spt-deep
                echo "SPT-Deep started"
                ;;
              stop)
                sudo systemctl stop spt-deep
                echo "SPT-Deep stopped"
                ;;
              restart)
                sudo systemctl restart spt-deep
                echo "SPT-Deep restarted"
                ;;
              status)
                sudo systemctl status spt-deep
                ;;
              logs)
                sudo journalctl -u spt-deep -f
                ;;
              *)
                echo "Usage: spt-deep-ctl {start|stop|restart|status|logs}"
                exit 1
            esac
          EOT
          permissions = "0755"
          owner   = "${local.username}:${local.username}"
        }
      ]

      runcmd = [
        # Install Node.js 20
        "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -",
        "apt-get install -y nodejs",

        # Install Docker
        "curl -fsSL https://get.docker.com | sh",
        "usermod -aG docker ${local.username}",

        # Install code-server
        "curl -fsSL https://code-server.dev/install.sh | sh",

        # Install Claude Code CLI
        "npm install -g @anthropic-ai/claude-code",

        # Create directories
        "mkdir -p ${local.home_dir}/bin",
        "mkdir -p ${local.home_dir}/.config/code-server",
        "mkdir -p ${local.home_dir}/.local/share/code-server/extensions",

        # Clone repository
        "git clone ${data.coder_parameter.git_repo.value} ${local.home_dir}/${local.repo_name} || true",
        "cd ${local.home_dir}/${local.repo_name} && npm install || true",

        # Set ownership
        "chown -R ${local.username}:${local.username} ${local.home_dir}",

        # Enable services
        "systemctl daemon-reload",
        "systemctl enable xvfb",
        "systemctl start xvfb",

        # Install VS Code extensions for code-server
        "code-server --install-extension ms-python.python",
        "code-server --install-extension dbaeumer.vscode-eslint",
        "code-server --install-extension esbenp.prettier-vscode",
        "code-server --install-extension bradlc.vscode-tailwindcss",

        # Install Claude extension for VS Code (Anthropic official)
        "code-server --install-extension anthropic.claude-code || true",

        # Install Continue extension as Claude interface alternative
        "code-server --install-extension Continue.continue || true",

        # Source environment
        "echo 'source ~/.spt-deep-env' >> ${local.home_dir}/.bashrc",
        "echo 'export PATH=$PATH:${local.home_dir}/bin' >> ${local.home_dir}/.bashrc"
      ]
    })
  }
}

# Managed Disk for home directory persistence
resource "azurerm_managed_disk" "home" {
  name                 = "disk-home-${local.workspace_name}"
  location             = azurerm_resource_group.main.location
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = data.coder_parameter.home_disk_size.value
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                  = "vm-${local.workspace_name}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = data.coder_parameter.instance_type.value
  admin_username        = local.username
  network_interface_ids = [azurerm_network_interface.main.id]

  admin_ssh_key {
    username   = local.username
    public_key = data.coder_workspace.me.id != "" ? tls_private_key.ssh.public_key_openssh : ""
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-${local.workspace_name}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  custom_data = data.cloudinit_config.main.rendered

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Coder_Provisioned = "true"
    Workspace         = data.coder_workspace.me.name
    Owner             = data.coder_workspace_owner.me.name
    Project           = "SPT-Deep"
  }

  lifecycle {
    ignore_changes = [custom_data]
  }
}

# Attach home disk
resource "azurerm_virtual_machine_data_disk_attachment" "home" {
  managed_disk_id    = azurerm_managed_disk.home.id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = 0
  caching            = "ReadWrite"
}

# SSH Key
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Coder Agent
resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Source environment
    source ~/.spt-deep-env

    # Mount home disk if not mounted
    if ! mountpoint -q /home/${local.username}/data; then
      sudo mkdir -p /home/${local.username}/data
      sudo mkfs.ext4 -F /dev/sdc 2>/dev/null || true
      sudo mount /dev/sdc /home/${local.username}/data
      sudo chown -R ${local.username}:${local.username} /home/${local.username}/data
    fi

    # Start code-server
    code-server --auth none --bind-addr 127.0.0.1:8080 &

    # Configure Claude Code
    if [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$AZURE_AI_KEY" ]; then
      echo "Configuring Claude Code..."
      mkdir -p ~/.config/claude
      cat > ~/.config/claude/config.json << EOF
    {
      "provider": "azure",
      "azure": {
        "endpoint": "$AZURE_AI_ENDPOINT",
        "apiKey": "$AZURE_AI_KEY"
      },
      "anthropic": {
        "apiKey": "$ANTHROPIC_API_KEY"
      }
    }
    EOF
    fi

    # Update repository
    cd ~/${local.repo_name}
    git pull origin main 2>/dev/null || true
    npm install || true

    # Configure Claude extension for VS Code
    mkdir -p ~/.local/share/code-server/User
    cat > ~/.local/share/code-server/User/settings.json << SETTINGS
    {
      "claude.apiKey": "$AZURE_AI_KEY",
      "claude.apiEndpoint": "$AZURE_AI_ENDPOINT",
      "continue.telemetryEnabled": false,
      "editor.formatOnSave": true
    }
    SETTINGS

    echo "Workspace ready! Use 'spt-deep-ctl start' to launch SPT-Deep"
    echo "Claude is available via: 1) VS Code extension  2) Terminal: claude"
  EOT

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    script       = "coder stat disk"
    interval     = 60
    timeout      = 1
  }

  metadata {
    key          = "spt-deep"
    display_name = "SPT-Deep Status"
    script       = "systemctl is-active spt-deep 2>/dev/null || echo 'stopped'"
    interval     = 10
    timeout      = 1
  }
}

# Coder Apps
resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:8080?folder=/home/${local.username}/${local.repo_name}"
  icon         = "/icon/code.svg"
  subdomain    = true
  share        = "owner"
}

resource "coder_app" "spt_deep" {
  agent_id     = coder_agent.main.id
  slug         = "spt-deep"
  display_name = "SPT-Deep App"
  url          = "http://localhost:5173"
  icon         = "/emojis/1f300.png"
  subdomain    = true
  share        = "owner"
  healthcheck {
    url       = "http://localhost:5173"
    interval  = 10
    threshold = 3
  }
}

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Terminal"
  icon         = "/icon/terminal.svg"
}

# VS Code Desktop - opens in local VS Code via Remote SSH
resource "coder_app" "vscode_desktop" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code Desktop"
  url          = "vscode://vscode-remote/ssh-remote+${lower(data.coder_workspace.me.name)}/home/${local.username}/${local.repo_name}"
  icon         = "/icon/code.svg"
  external     = true
}

# SSH Configuration info
resource "coder_metadata" "workspace_info" {
  resource_id = coder_agent.main.id

  item {
    key   = "SSH Command"
    value = "coder ssh ${data.coder_workspace.me.name}"
  }
  item {
    key   = "VS Code Command"
    value = "coder open ${data.coder_workspace.me.name}"
  }
  item {
    key   = "Azure AI Endpoint"
    value = data.coder_parameter.azure_ai_endpoint.value
  }
  item {
    key   = "Git Repository"
    value = data.coder_parameter.git_repo.value
  }
}

# Outputs
output "vm_public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "workspace_url" {
  value = "https://coder.smartpoints.tech/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"
}
