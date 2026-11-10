variable "location" {
  type        = string
  default     = "eastus2"
  description = "Primary Azure region for platform resources (logging, hub network, workload spoke)."
  nullable    = false
}

variable "subscription_ids" {
  type = object({
    management   = string
    connectivity = string
    identity     = optional(string)
    workload     = optional(string)
  })
  description = <<DESCRIPTION
Subscription IDs for each role in the landing zone.

- `management`   - (Required) Hosts Log Analytics, data collection rules and the Azure Monitor Agent identity.
- `connectivity` - (Required) Hosts the hub virtual network, Azure Firewall and private DNS zones.
- `identity`     - (Optional) Reserved for domain controllers / identity services. Placed in the Identity management group.
- `workload`     - (Optional) An application subscription that is placed in the Corp or Online management group and peered to the hub.

For a low-cost lab you may reuse the same subscription for several roles; it is then placed
in the management group of the first role it appears in (management, connectivity, identity).
DESCRIPTION

  validation {
    condition = alltrue([
      for id in values(var.subscription_ids) :
      id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))
    ])
    error_message = "Subscription IDs must be lowercase GUIDs."
  }
}

variable "root_parent_management_group_id" {
  type        = string
  default     = ""
  description = "ID of the management group the ALZ hierarchy is created under. Leave empty to use the Tenant Root Group."
  nullable    = false
}

variable "security_contact_email" {
  type        = string
  description = "Email address that Microsoft Defender for Cloud and Service Health alerts are sent to."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.security_contact_email))
    error_message = "Provide a valid email address."
  }
}

variable "tags" {
  type = map(string)
  default = {
    managed_by = "terraform"
    workload   = "platform-landing-zone"
  }
  description = "Tags applied to every resource group and resource created by this configuration."
}

# ---------------------------------------------------------------------------
# Management (logging and monitoring)
# ---------------------------------------------------------------------------

variable "log_analytics_retention_days" {
  type        = number
  default     = 30
  description = "Retention period for the central Log Analytics workspace. 30 days is included in the ingestion price."

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Retention must be between 30 and 730 days."
  }
}

variable "sentinel_enabled" {
  type        = bool
  default     = false
  description = "Onboard Microsoft Sentinel to the central Log Analytics workspace. Adds per-GB cost."
}

# ---------------------------------------------------------------------------
# Connectivity (hub and spoke)
# ---------------------------------------------------------------------------

variable "hub_address_space" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Address space of the hub virtual network. Subnets for firewall, bastion, gateways and DNS are carved from it automatically."
}

variable "connectivity_features" {
  type = object({
    firewall_enabled          = optional(bool, true)
    firewall_sku_tier         = optional(string, "Basic")
    bastion_enabled           = optional(bool, false)
    vpn_gateway_enabled       = optional(bool, false)
    expressroute_enabled      = optional(bool, false)
    private_dns_zones_enabled = optional(bool, true)
    dns_resolver_enabled      = optional(bool, false)
    ddos_protection_enabled   = optional(bool, false)
  })
  default     = {}
  description = <<DESCRIPTION
Feature switches for the hub. Defaults keep a lab affordable: Azure Firewall Basic and private DNS
zones are on; Bastion, gateways, DNS Private Resolver and DDoS Network Protection are off.
See the cost section of the README before enabling anything.
DESCRIPTION

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.connectivity_features.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Basic, Standard or Premium."
  }
}

variable "firewall_allowed_egress_fqdns" {
  type = list(string)
  default = [
    "*.ubuntu.com",
    "*.microsoft.com",
    "*.windowsupdate.com",
    "*.azure.com",
    "github.com",
    "*.github.com",
    # Azure control plane and identity, used by App Service / Functions / Logic Apps.
    "login.microsoftonline.com",
    "management.azure.com",
    "*.azurewebsites.net",
    "*.logic.azure.com",
    "*.monitor.azure.com",
  ]
  description = "FQDNs that workload spokes may reach over HTTP/HTTPS through the hub firewall. Everything else is denied."
}

# ---------------------------------------------------------------------------
# Application landing zone (subscription vending)
# ---------------------------------------------------------------------------

variable "workload_landing_zone" {
  type = object({
    enabled          = optional(bool, true)
    name             = optional(string, "app1")
    management_group = optional(string, "corp")
    address_space    = optional(string, "10.1.0.0/24")
    owner_object_id  = optional(string)
    budget = optional(object({
      amount         = number
      start_date     = string
      end_date       = string
      contact_emails = list(string)
    }))
  })
  default     = {}
  description = <<DESCRIPTION
A sample application landing zone built with the ALZ subscription vending module.

- `enabled`          - Create the landing zone. Requires `subscription_ids.workload`.
- `name`             - Short name used in resource names.
- `management_group` - `corp` (private, hub-connected) or `online` (internet-facing).
- `address_space`    - Spoke VNet address space. Must not overlap the hub.
- `owner_object_id`  - (Optional) Entra ID object ID of a user or group to grant Contributor on the subscription.
- `budget`           - (Optional) Monthly cost budget. Dates use the form `2026-12-01T00:00:00Z`; start must be the first of a month.
DESCRIPTION

  validation {
    condition     = contains(["corp", "online"], var.workload_landing_zone.management_group)
    error_message = "management_group must be corp or online."
  }

  validation {
    condition     = !var.workload_landing_zone.enabled || try(length(var.subscription_ids.workload) > 0, false)
    error_message = "workload_landing_zone.enabled is true, so subscription_ids.workload must be set."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Allow Azure Verified Modules to send anonymous usage telemetry to Microsoft."
}
