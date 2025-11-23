#!/bin/bash
# Deploy SPT-Deep Coder Template
# Usage: ./scripts/deploy-coder-template.sh

set -e

CODER_URL="${CODER_URL:-https://coder.smartpoints.tech}"
TEMPLATE_NAME="spt-deep-azure"
TEMPLATE_DIR="terraform/coder-template"

echo "========================================"
echo "  SPT-Deep Coder Template Deployment"
echo "========================================"
echo ""
echo "Coder URL: $CODER_URL"
echo "Template: $TEMPLATE_NAME"
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    if ! command -v coder &> /dev/null; then
        echo "Error: Coder CLI not installed."
        echo "Install with: curl -L https://coder.com/install.sh | sh"
        exit 1
    fi

    echo "✓ Prerequisites OK"
}

# Login to Coder
coder_login() {
    echo ""
    echo "Checking Coder authentication..."

    if ! coder whoami &> /dev/null; then
        echo "Not logged in. Starting Coder login..."
        coder login "$CODER_URL"
    fi

    CODER_USER=$(coder whoami --output json | jq -r '.username')
    echo "✓ Logged in as: $CODER_USER"
}

# Create or update template
deploy_template() {
    echo ""
    echo "Deploying template..."

    # Check if template exists
    if coder templates list | grep -q "$TEMPLATE_NAME"; then
        echo "Template exists. Updating..."
        coder templates push "$TEMPLATE_NAME" \
            --directory "$TEMPLATE_DIR" \
            --yes
    else
        echo "Creating new template..."
        coder templates create "$TEMPLATE_NAME" \
            --directory "$TEMPLATE_DIR" \
            --yes
    fi

    echo "✓ Template deployed"
}

# Show template info
show_info() {
    echo ""
    echo "========================================"
    echo "  Template Deployed!"
    echo "========================================"
    echo ""
    echo "Template: $TEMPLATE_NAME"
    echo "URL: $CODER_URL/templates/$TEMPLATE_NAME"
    echo ""
    echo "To create a workspace:"
    echo "  coder create my-spt-deep --template $TEMPLATE_NAME"
    echo ""
    echo "Parameters you'll need:"
    echo "  - azure_ai_endpoint: Azure AI inference endpoint"
    echo "  - azure_ai_key: GitHub PAT or Azure API key"
    echo "  - anthropic_api_key: (optional) Direct Anthropic key"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    coder_login
    deploy_template
    show_info
}

main "$@"
