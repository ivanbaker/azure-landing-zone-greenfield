locals {
  content_share_name = "${lower(var.name)}-content"
}

resource "azurerm_service_plan" "this" {
  name                = "asp-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Windows"
  sku_name            = var.plan_sku

  tags = var.tags
}

# Backing storage for workflow state and the app's content share. Logic Apps
# Standard still needs an account key for this, so keys are enabled on this
# dedicated account only; it is reachable only through private endpoints.
module "storage" {
  source = "../storage-account"

  name                          = var.storage_account_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  replication_type              = "ZRS"
  shared_access_key_enabled     = true
  private_endpoint_subnet_id    = var.private_endpoint_subnet_id
  private_endpoint_subresources = ["blob", "file", "queue", "table"]
  private_dns_zone_ids          = { for k, v in var.private_dns_zone_ids : k => v if k != "sites" }
  file_shares                   = { (local.content_share_name) = { quota_gb = 100 } }

  tags = var.tags
}

resource "azurerm_logic_app_standard" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  app_service_plan_id = azurerm_service_plan.this.id
  version             = "~4"

  storage_account_name       = module.storage.name
  storage_account_access_key = module.storage.primary_access_key
  storage_account_share_name = local.content_share_name

  # Outbound: all traffic, including to the content share, goes through the VNet.
  virtual_network_subnet_id  = var.integration_subnet_id
  vnet_content_share_enabled = true

  # Inbound: private endpoint only.
  public_network_access = "Disabled"
  https_only            = true

  ftp_publish_basic_authentication_enabled = false
  scm_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    vnet_route_all_enabled    = true
    min_tls_version           = "1.2"
    scm_min_tls_version       = "1.2"
    ftps_state                = "Disabled"
    http2_enabled             = true
    use_32_bit_worker_process = false
  }

  app_settings = merge(
    {
      FUNCTIONS_WORKER_RUNTIME     = "node"
      WEBSITE_NODE_DEFAULT_VERSION = "~20"
    },
    var.app_settings
  )

  tags = var.tags

  # Storage DNS must resolve over the VNet before the app is created.
  depends_on = [module.storage]
}

resource "azurerm_private_endpoint" "sites" {
  name                          = "pe-${var.name}-sites"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-sites"

  private_service_connection {
    name                           = "psc-${var.name}-sites"
    private_connection_resource_id = azurerm_logic_app_standard.this.id
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
