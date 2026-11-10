variable "server_name" {
  type        = string
  description = "Logical SQL server name. Globally unique, lowercase letters, numbers and hyphens."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.server_name))
    error_message = "Use lowercase letters, numbers and hyphens; must not start or end with a hyphen."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the server and databases in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "entra_admin" {
  type = object({
    login_username = string
    object_id      = string
  })
  description = <<DESCRIPTION
Entra ID administrator for the server. Use a group so access isn't tied to one person.
SQL authentication is disabled: every login uses Entra ID.
DESCRIPTION
}

variable "databases" {
  type = map(object({
    sku_name                    = optional(string, "GP_S_Gen5_1")
    max_size_gb                 = optional(number, 32)
    auto_pause_delay_in_minutes = optional(number, 60)
    min_capacity                = optional(number, 0.5)
    zone_redundant              = optional(bool, false)
    backup_storage_type         = optional(string, "Geo")
    short_term_retention_days   = optional(number, 7)
    long_term_retention = optional(object({
      weekly_retention  = optional(string, "P4W")
      monthly_retention = optional(string, "P12M")
      yearly_retention  = optional(string, "PT0S")
      week_of_year      = optional(number, 1)
    }))
  }))
  default = {
    appdb = {}
  }
  description = <<DESCRIPTION
Databases keyed by name. The default is one General Purpose serverless database
(1 vCore max, pauses after 60 idle minutes), which keeps a lab inexpensive.
Serverless-only settings (auto_pause_delay_in_minutes, min_capacity) are ignored for other SKUs.
DESCRIPTION
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet for the private endpoint (the landing zone's snet-private-endpoints)."
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = "ID of the privatelink.database.windows.net zone. Leave null to let the ALZ policy register it."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for all resources."
}
