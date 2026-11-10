variable "name" {
  type        = string
  description = "Storage account name. Globally unique, 3-24 lowercase letters and numbers."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Name must be 3-24 lowercase letters and numbers."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the storage account in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "account_tier" {
  type        = string
  default     = "Standard"
  description = "Standard or Premium."
}

variable "replication_type" {
  type        = string
  default     = "ZRS"
  description = "LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = false
  description = <<DESCRIPTION
Allow account keys and SAS tokens. Off by default so all access uses Entra ID.
Turn on only for services that still require keys (e.g. Azure Files content shares).
DESCRIPTION
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet for the private endpoints (the landing zone's snet-private-endpoints)."
}

variable "private_endpoint_subresources" {
  type        = set(string)
  default     = ["blob"]
  description = "Storage services to expose through private endpoints: any of blob, file, queue, table, dfs, web."

  validation {
    condition     = alltrue([for s in var.private_endpoint_subresources : contains(["blob", "file", "queue", "table", "dfs", "web"], s)])
    error_message = "Allowed values: blob, file, queue, table, dfs, web."
  }
}

variable "private_dns_zone_ids" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Private DNS zone IDs keyed by subresource, e.g. { blob = "<privatelink.blob.core.windows.net zone id>" }.
Subresources without an entry rely on the ALZ "Deploy-Private-DNS-Zones" policy to register them.
DESCRIPTION
}

variable "containers" {
  type        = set(string)
  default     = []
  description = "Blob containers to create (private access)."
}

variable "file_shares" {
  type = map(object({
    quota_gb = optional(number, 100)
  }))
  default     = {}
  description = "Azure Files shares to create, keyed by share name."
}

variable "blob_soft_delete_days" {
  type        = number
  default     = 14
  description = "Retention for deleted blobs and containers."
}

variable "role_assignments" {
  type = map(object({
    principal_id   = string
    role           = string
    principal_type = optional(string)
  }))
  default     = {}
  description = <<DESCRIPTION
Data-plane access on the account. Example:
{ app = { principal_id = "<object id>", role = "Storage Blob Data Contributor" } }
DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for all resources."
}
