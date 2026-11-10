variable "name" {
  type        = string
  description = "VM name. Also used for the NIC and disk names."

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,15}$", var.name))
    error_message = "Use 1-15 letters, numbers and hyphens (the Windows computer name limit)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create the VM in."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "os_type" {
  type        = string
  default     = "linux"
  description = "linux (Ubuntu 24.04 LTS) or windows (Windows Server 2025 Azure Edition)."

  validation {
    condition     = contains(["linux", "windows"], var.os_type)
    error_message = "os_type must be linux or windows."
  }
}

variable "size" {
  type        = string
  default     = "Standard_D2s_v5"
  description = "VM size. Must support Trusted Launch (Gen2)."
}

variable "zone" {
  type        = string
  default     = null
  description = "Availability zone (1, 2 or 3). Null for no zone."
}

variable "subnet_id" {
  type        = string
  description = "Subnet for the NIC (the landing zone's snet-app). No public IP is created."
}

variable "private_ip_address" {
  type        = string
  default     = null
  description = "Static private IP. Null for dynamic."
}

variable "admin_username" {
  type        = string
  default     = "azureadmin"
  description = "Local administrator name (break-glass; day-to-day sign-in uses Entra ID)."
}

variable "ssh_public_key" {
  type        = string
  default     = null
  description = "Linux only. SSH public key for the local admin. If null, a key pair is generated and the private key is returned as a sensitive output."
}

variable "admin_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Windows only. Local admin password. If null, a random 24-character password is generated."
}

variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  default     = null
  description = "Override the default marketplace image. Must be a Gen2 image."
}

variable "os_disk" {
  type = object({
    storage_account_type = optional(string, "Premium_LRS")
    size_gb              = optional(number)
  })
  default     = {}
  description = "OS disk settings."
}

variable "data_disks" {
  type = map(object({
    lun                  = number
    size_gb              = number
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadOnly")
  }))
  default     = {}
  description = "Data disks keyed by a short name, e.g. { data = { lun = 0, size_gb = 128 } }."
}

variable "encryption_at_host_enabled" {
  type        = bool
  default     = false
  description = "Encrypt temp disks and caches on the host. Requires the EncryptionAtHost feature to be registered on the subscription."
}

variable "entra_id_login_enabled" {
  type        = bool
  default     = true
  description = "Install the Entra ID login extension so users sign in with their Entra ID accounts and Azure RBAC."
}

variable "admin_principal_ids" {
  type        = set(string)
  default     = []
  description = "Entra ID object IDs (users or groups) granted 'Virtual Machine Administrator Login'."
}

variable "user_principal_ids" {
  type        = set(string)
  default     = []
  description = "Entra ID object IDs (users or groups) granted 'Virtual Machine User Login'."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for all resources."
}
