# Claude Model Deployment via Azure AI Foundry
# Deploys Claude models through Azure's partnership with Anthropic

# Note: Claude models in Azure AI Foundry are deployed via serverless API
# This requires the Azure AI Model Inference API

# Azure OpenAI Service for fallback GPT models
resource "azurerm_cognitive_account" "openai" {
  name                  = "oai-${local.resource_prefix}-${random_string.suffix.result}"
  location              = "eastus2" # OpenAI available regions
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "OpenAI"
  sku_name              = "S0"
  custom_subdomain_name = "perpetua-oai-${random_string.suffix.result}"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
  }

  tags = local.common_tags
}

# GPT-4o Deployment (fallback model)
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-08-06"
  }

  scale {
    type     = "Standard"
    capacity = 30 # TPM in thousands
  }
}

# GPT-4o-mini Deployment (fast/cheap fallback)
resource "azurerm_cognitive_deployment" "gpt4o_mini" {
  name                 = "gpt-4o-mini"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o-mini"
    version = "2024-07-18"
  }

  scale {
    type     = "Standard"
    capacity = 50
  }
}

# Claude Model Connection via Azure AI Foundry Serverless API
# Claude is available as a serverless endpoint in Azure AI Foundry
resource "azapi_resource" "claude_connection" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-04-01"
  name      = "claude-serverless"
  parent_id = azapi_resource.ai_project.id

  body = jsonencode({
    properties = {
      category      = "AzureOpenAI"
      authType      = "ApiKey"
      isSharedToAll = true
      target        = "https://models.inference.ai.azure.com"
      metadata = {
        ApiType = "Azure"
        Kind    = "Serverless"
      }
      credentials = {
        key = var.github_token # GitHub token for Azure AI inference
      }
    }
  })

  depends_on = [azapi_resource.ai_project]
}

# Variable for GitHub token (used for Azure AI inference serverless)
variable "github_token" {
  description = "GitHub personal access token for Azure AI inference serverless API"
  type        = string
  sensitive   = true
  default     = ""
}

# Store OpenAI key in Key Vault
resource "azurerm_key_vault_secret" "openai_key" {
  name         = "openai-key"
  value        = azurerm_cognitive_account.openai.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

# Outputs for Claude/OpenAI
output "openai_endpoint" {
  description = "Azure OpenAI endpoint"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_key" {
  description = "Azure OpenAI key"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "claude_inference_endpoint" {
  description = "Azure AI inference endpoint for Claude models"
  value       = "https://models.inference.ai.azure.com"
}

output "model_deployments" {
  description = "Available model deployments"
  value = {
    gpt4o = {
      name     = azurerm_cognitive_deployment.gpt4o.name
      endpoint = "${azurerm_cognitive_account.openai.endpoint}openai/deployments/${azurerm_cognitive_deployment.gpt4o.name}"
    }
    gpt4o_mini = {
      name     = azurerm_cognitive_deployment.gpt4o_mini.name
      endpoint = "${azurerm_cognitive_account.openai.endpoint}openai/deployments/${azurerm_cognitive_deployment.gpt4o_mini.name}"
    }
    claude_sonnet = {
      name     = "claude-3-5-sonnet"
      endpoint = "https://models.inference.ai.azure.com/chat/completions"
      model_id = "claude-3-5-sonnet-20241022"
    }
    claude_haiku = {
      name     = "claude-3-5-haiku"
      endpoint = "https://models.inference.ai.azure.com/chat/completions"
      model_id = "claude-3-5-haiku-20241022"
    }
  }
}
