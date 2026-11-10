# Example application deployed into the app1 landing zone created by infra/.
# It uses each module in modules/ and wires them together the way an app team
# would: the Function App and Logic App read secrets from Key Vault with their
# managed identities, and everything is reachable only on private IPs.

data "azurerm_client_config" "current" {}

locals {
  # Short, stable suffix so globally unique names don't collide.
  suffix = substr(sha1(var.subscription_ids.workload), 0, 6)
  base   = "${var.workload_name}${local.suffix}"

  # Names follow the conventions used in infra/.
  spoke = {
    resource_group = "rg-${var.landing_zone_name}-network-${var.location}"
    vnet           = "vnet-${var.landing_zone_name}-${var.location}"
  }

  # Private DNS zones live in the connectivity subscription (see infra/locals.tf).
  dns_rg_id = "/subscriptions/${var.subscription_ids.connectivity}/resourceGroups/rg-dns-${var.location}"
  dns_zone_ids = {
    vault = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    blob  = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    file  = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
    queue = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    table = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
    sql   = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
    sites = "${local.dns_rg_id}/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
  }

  log_analytics_workspace_id = "/subscriptions/${var.subscription_ids.management}/resourceGroups/rg-management-${var.location}/providers/Microsoft.OperationalInsights/workspaces/law-management-${var.location}"

  sql_admin = coalesce(var.sql_entra_admin, {
    login_username = "terraform-pipeline"
    object_id      = data.azurerm_client_config.current.object_id
  })

  # Identities that read secrets from Key Vault.
  key_vault_readers = merge(
    var.deploy.function_app ? { function_app = module.function_app[0].principal_id } : {},
    var.deploy.logic_app ? { logic_app = module.logic_app[0].principal_id } : {},
  )
}

data "azurerm_subnet" "this" {
  for_each = toset(["snet-app", "snet-private-endpoints", "snet-integration-logicapp", "snet-integration-functions"])

  name                 = each.key
  virtual_network_name = local.spoke.vnet
  resource_group_name  = local.spoke.resource_group
}

resource "azurerm_resource_group" "app" {
  name     = "rg-${var.workload_name}-${var.location}"
  location = var.location
  tags     = var.tags
}

module "key_vault" {
  source = "../../modules/key-vault"
  count  = var.deploy.key_vault ? 1 : 0

  name                       = "kv-${local.base}"
  resource_group_name        = azurerm_resource_group.app.name
  location                   = var.location
  private_endpoint_subnet_id = data.azurerm_subnet.this["snet-private-endpoints"].id
  private_dns_zone_id        = local.dns_zone_ids.vault

  role_assignments = {
    for name, principal_id in local.key_vault_readers : name => {
      principal_id   = principal_id
      role           = "Key Vault Secrets User"
      principal_type = "ServicePrincipal"
    }
  }

  tags = var.tags
}

module "storage_account" {
  source = "../../modules/storage-account"
  count  = var.deploy.storage_account ? 1 : 0

  name                          = "st${local.base}data"
  resource_group_name           = azurerm_resource_group.app.name
  location                      = var.location
  private_endpoint_subnet_id    = data.azurerm_subnet.this["snet-private-endpoints"].id
  private_endpoint_subresources = ["blob"]
  private_dns_zone_ids          = { blob = local.dns_zone_ids.blob }
  containers                    = ["uploads", "processed"]

  role_assignments = var.deploy.function_app ? {
    function_app = {
      principal_id   = module.function_app[0].principal_id
      role           = "Storage Blob Data Contributor"
      principal_type = "ServicePrincipal"
    }
  } : {}

  tags = var.tags
}

module "virtual_machine" {
  source = "../../modules/virtual-machine"
  count  = var.deploy.virtual_machine ? 1 : 0

  name                = "vm-${var.workload_name}-01"
  resource_group_name = azurerm_resource_group.app.name
  location            = var.location
  os_type             = "linux"
  subnet_id           = data.azurerm_subnet.this["snet-app"].id
  admin_principal_ids = var.vm_admin_principal_ids

  data_disks = {
    data = { lun = 0, size_gb = 64 }
  }

  tags = var.tags
}

module "sql_database" {
  source = "../../modules/sql-database"
  count  = var.deploy.sql_database ? 1 : 0

  server_name                = "sql-${local.base}"
  resource_group_name        = azurerm_resource_group.app.name
  location                   = var.location
  entra_admin                = local.sql_admin
  private_endpoint_subnet_id = data.azurerm_subnet.this["snet-private-endpoints"].id
  private_dns_zone_id        = local.dns_zone_ids.sql

  databases = {
    appdb = {}
  }

  tags = var.tags
}

module "logic_app" {
  source = "../../modules/logic-app"
  count  = var.deploy.logic_app ? 1 : 0

  name                       = "logic-${local.base}"
  resource_group_name        = azurerm_resource_group.app.name
  location                   = var.location
  storage_account_name       = "st${local.base}logic"
  integration_subnet_id      = data.azurerm_subnet.this["snet-integration-logicapp"].id
  private_endpoint_subnet_id = data.azurerm_subnet.this["snet-private-endpoints"].id
  private_dns_zone_ids = {
    sites = local.dns_zone_ids.sites
    blob  = local.dns_zone_ids.blob
    file  = local.dns_zone_ids.file
    queue = local.dns_zone_ids.queue
    table = local.dns_zone_ids.table
  }

  tags = var.tags
}

module "function_app" {
  source = "../../modules/function-app"
  count  = var.deploy.function_app ? 1 : 0

  name                       = "func-${local.base}"
  resource_group_name        = azurerm_resource_group.app.name
  location                   = var.location
  storage_account_name       = "st${local.base}func"
  integration_subnet_id      = data.azurerm_subnet.this["snet-integration-functions"].id
  private_endpoint_subnet_id = data.azurerm_subnet.this["snet-private-endpoints"].id
  log_analytics_workspace_id = local.log_analytics_workspace_id
  private_dns_zone_ids = {
    sites = local.dns_zone_ids.sites
    blob  = local.dns_zone_ids.blob
    queue = local.dns_zone_ids.queue
    table = local.dns_zone_ids.table
  }

  runtime = {
    name    = "python"
    version = "3.12"
  }

  # Example of wiring app settings to other services without secrets.
  app_settings = merge(
    var.deploy.storage_account ? { DATA_STORAGE_ACCOUNT = "st${local.base}data" } : {},
    var.deploy.key_vault ? { KEY_VAULT_URI = "https://kv-${local.base}.vault.azure.net/" } : {},
    var.deploy.sql_database ? { SQL_SERVER = "sql-${local.base}.database.windows.net" } : {},
  )

  tags = var.tags
}
