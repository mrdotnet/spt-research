# SPT-Deep Workspace Setup Guide

## Workspace Access Methods

Your workspace **spt-test** is now running and can be accessed via:

### 1. Web Browser (VS Code Server)
Open in your browser:
```
https://coder.smartpoints.tech/@mrdotnet/spt-test
```

Click on **"VS Code"** to launch the browser-based VS Code editor.

### 2. VS Code Desktop (Remote SSH)
```bash
# Install the Coder extension first
code --install-extension coder.coder-remote

# Then open the workspace
coder open spt-test
```

Or click the **"VS Code Desktop"** button in the Coder dashboard.

### 3. SSH Access
```bash
# Direct SSH
coder ssh spt-test

# Or configure SSH config for standard ssh command
coder config-ssh
ssh coder.spt-test
```

### 4. Terminal (Web)
Click **"Terminal"** in the Coder dashboard for a browser-based terminal.

---

## Configuring GitHub PAT for Claude Models

To use Claude models via Azure AI Inference, you need a **GitHub Personal Access Token (PAT)**.

### Step 1: Create a GitHub PAT

1. Go to [GitHub Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens?type=beta)
2. Click **"Generate new token (Fine-grained)"**
3. Give it a name like `azure-ai-inference`
4. Set expiration as needed
5. Under **Permissions**, no special permissions are required for Azure AI inference
6. Click **"Generate token"**
7. Copy the token (starts with `github_pat_...`)

### Step 2: Add the Token to Your Workspace

**Option A: Via Coder UI (Recommended)**

1. Go to https://coder.smartpoints.tech/workspaces
2. Click on **spt-test**
3. Click **Settings** (gear icon) or **Parameters**
4. Update the **"Azure AI Key / GitHub Token"** parameter
5. Paste your GitHub PAT
6. Click **Update** and restart the workspace

**Option B: Via Environment File (Inside Workspace)**

1. Connect to your workspace:
   ```bash
   coder ssh spt-test
   ```

2. Edit the environment file:
   ```bash
   nano ~/.spt-deep-env
   ```

3. Update the `AZURE_AI_KEY` line:
   ```bash
   export AZURE_AI_KEY="github_pat_YOUR_TOKEN_HERE"
   ```

4. Reload the environment:
   ```bash
   source ~/.spt-deep-env
   ```

**Option C: Via Claude Code CLI Config**

1. SSH into the workspace:
   ```bash
   coder ssh spt-test
   ```

2. Configure Claude Code:
   ```bash
   mkdir -p ~/.config/claude
   cat > ~/.config/claude/config.json << 'EOF'
   {
     "provider": "azure",
     "azure": {
       "endpoint": "https://models.inference.ai.azure.com",
       "apiKey": "github_pat_YOUR_TOKEN_HERE"
     }
   }
   EOF
   ```

---

## Available AI Models

### Claude Models (via Azure AI Inference)
| Model | Model ID | Endpoint |
|-------|----------|----------|
| Claude 3.5 Sonnet | `claude-3-5-sonnet-20241022` | https://models.inference.ai.azure.com |
| Claude 3.5 Haiku | `claude-3-5-haiku-20241022` | https://models.inference.ai.azure.com |

### Azure OpenAI Models (Fallback)
| Model | Deployment | Endpoint |
|-------|------------|----------|
| GPT-4o | `gpt-4o` | https://perpetua-oai-abyug6.openai.azure.com/ |
| GPT-4o-mini | `gpt-4o-mini` | https://perpetua-oai-abyug6.openai.azure.com/ |

---

## Quick Commands

### Inside the Workspace

```bash
# Start SPT-Deep application
spt-deep-ctl start

# View SPT-Deep logs
spt-deep-ctl logs

# Check SPT-Deep status
spt-deep-ctl status

# Stop SPT-Deep
spt-deep-ctl stop

# Restart SPT-Deep
spt-deep-ctl restart
```

### From Your Local Machine

```bash
# SSH into workspace
coder ssh spt-test

# Open in VS Code Desktop
coder open spt-test

# Forward ports (e.g., for local development)
coder port-forward spt-test --tcp 5173:5173

# View workspace status
coder show spt-test

# Stop workspace (saves costs)
coder stop spt-test

# Start workspace
coder start spt-test
```

---

## Workspace Resources

| Resource | Value |
|----------|-------|
| **VM Size** | Standard_D2s_v5 (2 vCPU, 8 GB RAM) |
| **Disk** | 32 GB Premium LRS |
| **Region** | East US 2 |
| **OS** | Ubuntu 22.04 LTS |
| **Public IP** | Assigned (check Coder dashboard) |

---

## Troubleshooting

### Claude Code not working?
1. Verify your GitHub PAT is valid
2. Check the environment: `echo $AZURE_AI_KEY`
3. Test the endpoint:
   ```bash
   curl -H "Authorization: Bearer $AZURE_AI_KEY" \
        -H "Content-Type: application/json" \
        https://models.inference.ai.azure.com/chat/completions \
        -d '{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"Hello"}]}'
   ```

### VS Code Server not loading?
1. Check if code-server is running: `pgrep -f code-server`
2. Restart it: `code-server --auth none --bind-addr 127.0.0.1:8080 &`

### SPT-Deep not starting?
1. Check logs: `spt-deep-ctl logs`
2. Ensure Xvfb is running: `systemctl status xvfb`
3. Check for npm issues: `cd ~/spt-deep && npm install`

---

## URLs

- **Coder Dashboard**: https://coder.smartpoints.tech
- **Workspace**: https://coder.smartpoints.tech/@mrdotnet/spt-test
- **Template**: https://coder.smartpoints.tech/templates/spt-deep-azure
- **Azure Portal**: https://portal.azure.com
