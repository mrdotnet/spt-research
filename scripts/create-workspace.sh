#!/bin/bash
# Create SPT-Deep Coder Workspace
# Usage: ./scripts/create-workspace.sh [workspace-name]

set -e

CODER_URL="${CODER_URL:-https://coder.smartpoints.tech}"
TEMPLATE_NAME="spt-deep-azure"
WORKSPACE_NAME="${1:-spt-deep-dev}"

echo "========================================"
echo "  SPT-Deep Workspace Creation"
echo "========================================"
echo ""

# Check prerequisites
if ! command -v coder &> /dev/null; then
    echo "Error: Coder CLI not installed."
    echo "Install with: curl -L https://coder.com/install.sh | sh"
    exit 1
fi

# Login check
if ! coder whoami &> /dev/null; then
    echo "Logging in to Coder..."
    coder login "$CODER_URL"
fi

# Check if workspace exists
if coder list | grep -q "$WORKSPACE_NAME"; then
    echo "Workspace '$WORKSPACE_NAME' already exists."
    read -p "Start existing workspace? (yes/no): " start_existing

    if [ "$start_existing" = "yes" ]; then
        coder start "$WORKSPACE_NAME"
        echo ""
        echo "Workspace started!"
        echo "Access VS Code: coder open $WORKSPACE_NAME"
        exit 0
    else
        exit 0
    fi
fi

# Prompt for configuration
echo "Creating new workspace: $WORKSPACE_NAME"
echo ""

read -p "Azure AI Endpoint [https://models.inference.ai.azure.com]: " AZURE_ENDPOINT
AZURE_ENDPOINT="${AZURE_ENDPOINT:-https://models.inference.ai.azure.com}"

read -sp "Azure AI Key / GitHub Token: " AZURE_KEY
echo ""

read -sp "Anthropic API Key (optional, press Enter to skip): " ANTHROPIC_KEY
echo ""

read -p "Azure Region [eastus2]: " LOCATION
LOCATION="${LOCATION:-eastus2}"

read -p "VM Size [Standard_D4s_v5]: " VM_SIZE
VM_SIZE="${VM_SIZE:-Standard_D4s_v5}"

read -p "Disk Size GB [64]: " DISK_SIZE
DISK_SIZE="${DISK_SIZE:-64}"

# Create workspace
echo ""
echo "Creating workspace..."

coder create "$WORKSPACE_NAME" \
    --template "$TEMPLATE_NAME" \
    --parameter "location=$LOCATION" \
    --parameter "instance_type=$VM_SIZE" \
    --parameter "home_disk_size=$DISK_SIZE" \
    --parameter "azure_ai_endpoint=$AZURE_ENDPOINT" \
    --parameter "azure_ai_key=$AZURE_KEY" \
    --parameter "anthropic_api_key=$ANTHROPIC_KEY" \
    --parameter "git_repo=https://github.com/MrDotnet/Perpetua.git" \
    --yes

echo ""
echo "========================================"
echo "  Workspace Created!"
echo "========================================"
echo ""
echo "Workspace: $WORKSPACE_NAME"
echo "URL: $CODER_URL/@$(coder whoami --output json | jq -r '.username')/$WORKSPACE_NAME"
echo ""
echo "Quick commands:"
echo "  coder ssh $WORKSPACE_NAME          # SSH into workspace"
echo "  coder open $WORKSPACE_NAME         # Open in VS Code"
echo "  coder port-forward $WORKSPACE_NAME # Forward ports"
echo ""
echo "SPT-Deep commands (inside workspace):"
echo "  perpetua-ctl start   # Start SPT-Deep in background"
echo "  perpetua-ctl logs    # View logs"
echo "  perpetua-ctl status  # Check status"
echo ""
