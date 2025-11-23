# Azure AI Foundry Infrastructure for Perpetua
# Provisions Azure AI Services with Claude model access via Azure partnership

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "azapi" {}

# Variables
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "perpetua"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Perpetua"
    ManagedBy   = "Terraform"
    Application = "AI-Exploration-Engine"
  }
}

# Locals for naming
locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
  })
}

# Random suffix for globally unique names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}"
  location = var.location
  tags     = local.common_tags
}

# Azure AI Services Account (Multi-service cognitive account)
resource "azurerm_cognitive_account" "ai_services" {
  name                  = "ai-${local.resource_prefix}-${random_string.suffix.result}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  kind                  = "CognitiveServices"
  sku_name              = "S0"
  custom_subdomain_name = "perpetua-ai-${random_string.suffix.result}"

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
  }

  tags = local.common_tags
}

# Azure AI Foundry Hub (AI Studio Hub)
resource "azapi_resource" "ai_hub" {
  type      = "Microsoft.MachineLearningServices/workspaces@2024-04-01"
  name      = "hub-${local.resource_prefix}-${random_string.suffix.result}"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    kind = "Hub"
    properties = {
      friendlyName               = "Perpetua AI Hub"
      description                = "Azure AI Foundry Hub for Perpetua exploration engine"
      publicNetworkAccess        = "Enabled"
      v1LegacyMode               = false
      managedNetwork = {
        isolationMode = "Disabled"
      }
    }
    sku = {
      name = "Basic"
      tier = "Basic"
    }
  })

  tags = local.common_tags

  response_export_values = ["*"]
}

# Azure AI Foundry Project
resource "azapi_resource" "ai_project" {
  type      = "Microsoft.MachineLearningServices/workspaces@2024-04-01"
  name      = "proj-${local.resource_prefix}-${random_string.suffix.result}"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    kind = "Project"
    properties = {
      friendlyName  = "Perpetua Project"
      description   = "AI Foundry project for Perpetua infinite thought engine"
      hubResourceId = azapi_resource.ai_hub.id
    }
    sku = {
      name = "Basic"
      tier = "Basic"
    }
  })

  tags = local.common_tags

  depends_on = [azapi_resource.ai_hub]

  response_export_values = ["*"]
}

# Storage Account for AI Foundry
resource "azurerm_storage_account" "ai_storage" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  blob_properties {
    versioning_enabled = true
  }

  tags = local.common_tags
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.project_name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Purge", "Recover"
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = local.common_tags
}

# Current Azure client config
data "azurerm_client_config" "current" {}

# Store AI Services key in Key Vault
resource "azurerm_key_vault_secret" "ai_services_key" {
  name         = "ai-services-key"
  value        = azurerm_cognitive_account.ai_services.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "appi-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"

  tags = local.common_tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

# Outputs
output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "ai_services_endpoint" {
  description = "Azure AI Services endpoint"
  value       = azurerm_cognitive_account.ai_services.endpoint
}

output "ai_services_key" {
  description = "Azure AI Services primary key"
  value       = azurerm_cognitive_account.ai_services.primary_access_key
  sensitive   = true
}

output "ai_hub_id" {
  description = "Azure AI Foundry Hub ID"
  value       = azapi_resource.ai_hub.id
}

output "ai_project_id" {
  description = "Azure AI Foundry Project ID"
  value       = azapi_resource.ai_project.id
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.ai_storage.name
}

output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "azure_config" {
  description = "Configuration for Perpetua app"
  value = {
    endpoint     = azurerm_cognitive_account.ai_services.endpoint
    region       = var.location
    key_vault    = azurerm_key_vault.main.vault_uri
    project_name = azapi_resource.ai_project.name
  }
  sensitive = false
}
