variable "subscription_ids" {
  type = object({
    management   = string
    connectivity = string
    identity     = optional(string)
    workload     = string
  })
  description = "Same value as the platform deployment (supplied by the pipeline as TF_VAR_subscription_ids)."
}

variable "location" {
  type        = string
  default     = "eastus2"
  description = "Region of the landing zone this workload runs in."
}

variable "landing_zone_name" {
  type        = string
  default     = "app1"
  description = "workload_landing_zone.name from the platform deployment. Used to find the spoke VNet and subnets."
}

variable "workload_name" {
  type        = string
  default     = "app1"
  description = "Short name used in resource names (lowercase letters and numbers, max 8)."

  validation {
    condition     = can(regex("^[a-z0-9]{1,8}$", var.workload_name))
    error_message = "Use 1-8 lowercase letters and numbers."
  }
}

variable "deploy" {
  type = object({
    key_vault       = optional(bool, true)
    storage_account = optional(bool, true)
    virtual_machine = optional(bool, true)
    sql_database    = optional(bool, true)
    logic_app       = optional(bool, true)
    function_app    = optional(bool, true)
  })
  default     = {}
  description = "Switch individual services on or off."
}

variable "vm_admin_principal_ids" {
  type        = set(string)
  default     = []
  description = "Entra ID users or groups allowed to sign in to the VM as administrators."
}

variable "sql_entra_admin" {
  type = object({
    login_username = string
    object_id      = string
  })
  default     = null
  description = "Entra ID group to make SQL administrator. Defaults to the identity running Terraform."
}

variable "tags" {
  type = map(string)
  default = {
    managed_by  = "terraform"
    workload    = "app1"
    environment = "lab"
  }
  description = "Tags for all resources."
}
