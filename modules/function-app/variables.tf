variable "name" {
  type        = string
  description = "Function App name. Globally unique (it becomes <name>.azurewebsites.net)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the Function App, its plan and its storage."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "plan_sku" {
  type        = string
  default     = "P0v3"
  description = <<DESCRIPTION
Linux App Service plan size. Premium v3 (P0v3-P3v3) supports VNet integration and private
endpoints with identity-based storage (no account keys). Elastic Premium (EP1-EP3) also works
but needs an Azure Files content share, which requires storage account keys.
DESCRIPTION

  validation {
    condition     = can(regex("^P[0-3]v3$|^P[1-5]mv3$", var.plan_sku))
    error_message = "Use a Premium v3 SKU (P0v3, P1v3, P2v3, P3v3 or P1mv3-P5mv3)."
  }
}

variable "runtime" {
  type = object({
    name    = string
    version = string
  })
  default = {
    name    = "python"
    version = "3.12"
  }
  description = "Language runtime: name is python, node, dotnet-isolated, java or powershell."

  validation {
    condition     = contains(["python", "node", "dotnet-isolated", "java", "powershell"], var.runtime.name)
    error_message = "runtime.name must be python, node, dotnet-isolated, java or powershell."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Name for the Function App's backing storage account (3-24 lowercase letters and numbers)."
}

variable "integration_subnet_id" {
  type        = string
  description = "Subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration (the landing zone's snet-integration-functions)."
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet for the inbound private endpoint and the storage private endpoints."
}

variable "private_dns_zone_ids" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Private DNS zone IDs keyed by: sites, blob, queue, table.
Pass these rather than relying on the ALZ policy, so storage resolves privately before the app first starts.
DESCRIPTION
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Central Log Analytics workspace ID. When set, a workspace-based Application Insights resource is created."
}

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Extra app settings. Use Key Vault references (@Microsoft.KeyVault(...)) for secrets."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for all resources."
}
