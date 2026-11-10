variable "name" {
  type        = string
  description = "Logic App name. Globally unique (it becomes <name>.azurewebsites.net)."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the Logic App, its plan and its storage."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "plan_sku" {
  type        = string
  default     = "WS1"
  description = "Workflow Standard plan size: WS1, WS2 or WS3."

  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.plan_sku)
    error_message = "plan_sku must be WS1, WS2 or WS3."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Name for the Logic App's backing storage account (3-24 lowercase letters and numbers)."
}

variable "integration_subnet_id" {
  type        = string
  description = "Subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration (the landing zone's snet-integration-logicapp)."
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet for the inbound private endpoint and the storage private endpoints."
}

variable "private_dns_zone_ids" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Private DNS zone IDs keyed by: sites, blob, file, queue, table.
Pass these rather than relying on the ALZ policy: the Logic App reads its storage over the VNet
while it is being created, so the storage DNS records must exist before that.
DESCRIPTION
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
