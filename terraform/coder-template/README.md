# Perpetua Coder Template

Azure Linux workspace template optimized for Perpetua development with Claude AI integration.

## Features

- **VS Code Server**: Browser-based VS Code with Perpetua project pre-loaded
- **Claude Code CLI**: Pre-installed with Azure AI Foundry configuration
- **Perpetua Runner**: Systemd service for persistent background execution
- **Xvfb**: Virtual framebuffer for headless Electron operation
- **Docker**: Pre-installed for containerized development

## Quick Start

### 1. Deploy Template to Coder

```bash
cd terraform/coder-template
coder templates create perpetua-azure --directory .
```

### 2. Create Workspace

```bash
coder create my-perpetua --template perpetua-azure
```

### 3. Configure Parameters

During workspace creation, you'll be prompted for:

| Parameter | Description | Required |
|-----------|-------------|----------|
| `azure_ai_endpoint` | Azure AI Foundry inference endpoint | Yes |
| `azure_ai_key` | GitHub PAT for Claude serverless API | Yes |
| `anthropic_api_key` | Direct Anthropic key (fallback) | No |
| `location` | Azure region | Yes |
| `instance_type` | VM size | Yes |
| `home_disk_size` | Persistent storage size | Yes |

## Usage

### Access Workspace

1. **VS Code**: Click "VS Code" app in Coder dashboard
2. **Terminal**: Click "Terminal" or SSH directly
3. **Perpetua**: Click "Perpetua App" (after starting)

### Control Perpetua

```bash
# Start Perpetua in background
perpetua-ctl start

# Check status
perpetua-ctl status

# View logs
perpetua-ctl logs

# Stop
perpetua-ctl stop

# Restart
perpetua-ctl restart
```

### Claude Code CLI

```bash
# Interactive chat
claude

# Run task
claude "Help me implement a new feature in Perpetua"

# With Azure AI
AZURE_AI_KEY=your-key claude --provider azure
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Coder Workspace                          │
│  ┌─────────────────┐  ┌──────────────────────────────────┐ │
│  │   VS Code       │  │  Perpetua (Electron + React)     │ │
│  │   Server        │  │  ┌──────────────────────────┐    │ │
│  │   :8080         │  │  │  Claude Service          │    │ │
│  └─────────────────┘  │  │  (Azure AI / Anthropic)  │    │ │
│                       │  └──────────────────────────┘    │ │
│  ┌─────────────────┐  │              ↓                   │ │
│  │  Claude Code    │  │  8-Stage Exploration Engine      │ │
│  │  CLI            │  └──────────────────────────────────┘ │
│  └─────────────────┘                                       │
│           ↓                          ↓                     │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              Xvfb (Virtual Display :99)              │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
                 ┌───────────────────────────┐
                 │  Azure AI Foundry         │
                 │  - Claude 3.5 Sonnet      │
                 │  - Claude 3.5 Haiku       │
                 │  - GPT-4o (fallback)      │
                 └───────────────────────────┘
```

## Persistent Storage

The `/home/coder/data` directory is mounted on a separate Azure managed disk that persists across workspace stops/starts.

Store any data you want to keep there.

## Troubleshooting

### Perpetua won't start

```bash
# Check Xvfb
sudo systemctl status xvfb

# Check logs
sudo journalctl -u perpetua -n 100

# Manual start for debugging
cd ~/perpetua
DISPLAY=:99 npm run dev
```

### Claude API errors

```bash
# Verify environment
cat ~/.perpetua-env

# Test Azure AI
curl -X POST "$AZURE_AI_ENDPOINT/chat/completions" \
  -H "Authorization: Bearer $AZURE_AI_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-3-5-sonnet-20241022", "messages": [{"role": "user", "content": "Hello"}]}'
```

### VS Code extensions not loading

```bash
# Reinstall extensions
code-server --install-extension ms-python.python
code-server --install-extension dbaeumer.vscode-eslint
```
