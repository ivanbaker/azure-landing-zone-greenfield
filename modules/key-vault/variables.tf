variable "name" {
  type        = string
  description = "Key Vault name. Globally unique, 3-24 characters, letters, numbers and hyphens."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Name must be 3-24 characters, start with a letter, and contain only letters, numbers and hyphens."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the Key Vault in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "sku_name" {
  type        = string
  default     = "standard"
  description = "standard, or premium for HSM-backed keys."

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  default     = 90
  description = "Days that deleted vault objects are kept (7-90)."
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet for the private endpoint (the landing zone's snet-private-endpoints)."
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = <<DESCRIPTION
ID of the privatelink.vaultcore.azure.net zone. Leave null in a Corp landing zone:
the ALZ "Deploy-Private-DNS-Zones" policy registers the endpoint in the hub zone automatically.
DESCRIPTION
}

variable "role_assignments" {
  type = map(object({
    principal_id   = string
    role           = string
    principal_type = optional(string)
  }))
  default     = {}
  description = <<DESCRIPTION
Data-plane access, using Azure RBAC (access policies are disabled). Example:
{ app = { principal_id = "<object id>", role = "Key Vault Secrets User" } }
DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for all resources."
}
