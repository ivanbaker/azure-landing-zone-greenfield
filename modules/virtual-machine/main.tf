locals {
  is_linux = var.os_type == "linux"

  default_images = {
    linux = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      version   = "latest"
    }
    windows = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2025-datacenter-azure-edition"
      version   = "latest"
    }
  }
  image = coalesce(var.image, local.default_images[var.os_type])

  ssh_public_key = local.is_linux ? coalesce(var.ssh_public_key, try(tls_private_key.ssh[0].public_key_openssh, null)) : null
  admin_password = local.is_linux ? null : coalesce(var.admin_password, try(random_password.admin[0].result, null))

  vm_id = local.is_linux ? azurerm_linux_virtual_machine.this[0].id : azurerm_windows_virtual_machine.this[0].id
}

# Generated credentials, only when none are supplied. Kept in Terraform state,
# which is why the state storage account is private and Entra-ID-only.
resource "tls_private_key" "ssh" {
  count     = local.is_linux && var.ssh_public_key == null ? 1 : 0
  algorithm = "ED25519"
}

resource "random_password" "admin" {
  count            = !local.is_linux && var.admin_password == null ? 1 : 0
  length           = 24
  special          = true
  override_special = "!@#%*-_=+?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

# No public IP: reach the VM through Bastion in the hub, or over VPN/ExpressRoute.
resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address == null ? "Dynamic" : "Static"
    private_ip_address            = var.private_ip_address
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "this" {
  count = local.is_linux ? 1 : 0

  name                  = var.name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.size
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.this.id]

  admin_username                  = var.admin_username
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  # Trusted Launch (audited by the ALZ root policy set).
  secure_boot_enabled        = true
  vtpm_enabled               = true
  encryption_at_host_enabled = var.encryption_at_host_enabled

  # Patching through Azure Update Manager.
  patch_mode            = "AutomaticByPlatform"
  patch_assessment_mode = "AutomaticByPlatform"

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${var.name}"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk.storage_account_type
    disk_size_gb         = var.os_disk.size_gb
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  # Managed boot diagnostics storage.
  boot_diagnostics {}

  tags = var.tags
}

resource "azurerm_windows_virtual_machine" "this" {
  count = local.is_linux ? 0 : 1

  name                  = var.name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.size
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.this.id]

  admin_username = var.admin_username
  admin_password = local.admin_password

  secure_boot_enabled        = true
  vtpm_enabled               = true
  encryption_at_host_enabled = var.encryption_at_host_enabled

  patch_mode                = "AutomaticByPlatform"
  patch_assessment_mode     = "AutomaticByPlatform"
  automatic_updates_enabled = true

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${var.name}"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk.storage_account_type
    disk_size_gb         = var.os_disk.size_gb
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  boot_diagnostics {}

  tags = var.tags
}

resource "azurerm_managed_disk" "data" {
  for_each = var.data_disks

  name                 = "datadisk-${var.name}-${each.key}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  zone                 = var.zone
  storage_account_type = each.value.storage_account_type
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gb

  # No public import/export of disk contents.
  public_network_access_enabled = false
  network_access_policy         = "DenyAll"

  tags = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = var.data_disks

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = local.vm_id
  lun                = each.value.lun
  caching            = each.value.caching
}

# Sign in with Entra ID accounts instead of local credentials.
resource "azurerm_virtual_machine_extension" "entra_login" {
  count = var.entra_id_login_enabled ? 1 : 0

  name                       = local.is_linux ? "AADSSHLoginForLinux" : "AADLoginForWindows"
  virtual_machine_id         = local.vm_id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = local.is_linux ? "AADSSHLoginForLinux" : "AADLoginForWindows"
  type_handler_version       = local.is_linux ? "1.0" : "2.0"
  auto_upgrade_minor_version = true

  tags = var.tags
}

resource "azurerm_role_assignment" "admin_login" {
  for_each = var.admin_principal_ids

  scope                = local.vm_id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "user_login" {
  for_each = var.user_principal_ids

  scope                = local.vm_id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = each.value
}
