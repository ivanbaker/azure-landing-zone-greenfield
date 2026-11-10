locals {
  stack = var.runtime.name
}

resource "azurerm_service_plan" "this" {
  name                = "asp-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.plan_sku

  tags = var.tags
}

# Backing storage with account keys disabled: the app authenticates with its
# managed identity (AzureWebJobsStorage__accountName).
module "storage" {
  source = "../storage-account"

  name                          = var.storage_account_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  replication_type              = "ZRS"
  shared_access_key_enabled     = false
  private_endpoint_subnet_id    = var.private_endpoint_subnet_id
  private_endpoint_subresources = ["blob", "queue", "table"]
  private_dns_zone_ids          = { for k, v in var.private_dns_zone_ids : k => v if k != "sites" }

  tags = var.tags
}

resource "azurerm_application_insights" "this" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                = "appi-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  application_type    = "web"
  workspace_id        = var.log_analytics_workspace_id

  tags = var.tags
}

resource "azurerm_linux_function_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_account_name          = module.storage.name
  storage_uses_managed_identity = true

  # Outbound through the VNet; inbound through the private endpoint only.
  virtual_network_subnet_id     = var.integration_subnet_id
  public_network_access_enabled = false
  https_only                    = true

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                              = true
    vnet_route_all_enabled                 = true
    minimum_tls_version                    = "1.2"
    scm_minimum_tls_version                = "1.2"
    ftps_state                             = "Disabled"
    http2_enabled                          = true
    application_insights_connection_string = try(azurerm_application_insights.this[0].connection_string, null)

    application_stack {
      python_version              = local.stack == "python" ? var.runtime.version : null
      node_version                = local.stack == "node" ? var.runtime.version : null
      dotnet_version              = local.stack == "dotnet-isolated" ? var.runtime.version : null
      use_dotnet_isolated_runtime = local.stack == "dotnet-isolated" ? true : null
      java_version                = local.stack == "java" ? var.runtime.version : null
      powershell_core_version     = local.stack == "powershell" ? var.runtime.version : null
    }
  }

  app_settings = var.app_settings

  tags = var.tags
}

# Roles the Functions host needs on its storage when using a managed identity.
resource "azurerm_role_assignment" "storage" {
  for_each = toset([
    "Storage Blob Data Owner",
    "Storage Queue Data Contributor",
    "Storage Table Data Contributor",
  ])

  scope                = module.storage.id
  role_definition_name = each.key
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_private_endpoint" "sites" {
  name                          = "pe-${var.name}-sites"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-sites"

  private_service_connection {
    name                           = "psc-${var.name}-sites"
    private_connection_resource_id = azurerm_linux_function_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = contains(keys(var.private_dns_zone_ids), "sites") ? [var.private_dns_zone_ids["sites"]] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
