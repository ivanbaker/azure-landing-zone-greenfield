data "azurerm_client_config" "current" {}

resource "azurerm_mssql_server" "this" {
  name                = var.server_name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "12.0"

  # Entra ID only: no SQL logins or passwords to manage or leak.
  azuread_administrator {
    login_username              = var.entra_admin.login_username
    object_id                   = var.entra_admin.object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  public_network_access_enabled = false
  minimum_tls_version           = "1.2"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_mssql_database" "this" {
  for_each = var.databases

  name           = each.key
  server_id      = azurerm_mssql_server.this.id
  sku_name       = each.value.sku_name
  max_size_gb    = each.value.max_size_gb
  zone_redundant = each.value.zone_redundant

  # Serverless settings apply only to GP_S_* SKUs.
  auto_pause_delay_in_minutes = startswith(each.value.sku_name, "GP_S_") ? each.value.auto_pause_delay_in_minutes : null
  min_capacity                = startswith(each.value.sku_name, "GP_S_") ? each.value.min_capacity : null

  storage_account_type                = each.value.backup_storage_type
  transparent_data_encryption_enabled = true

  short_term_retention_policy {
    retention_days = each.value.short_term_retention_days
  }

  dynamic "long_term_retention_policy" {
    for_each = each.value.long_term_retention == null ? [] : [each.value.long_term_retention]
    content {
      weekly_retention  = long_term_retention_policy.value.weekly_retention
      monthly_retention = long_term_retention_policy.value.monthly_retention
      yearly_retention  = long_term_retention_policy.value.yearly_retention
      week_of_year      = long_term_retention_policy.value.week_of_year
    }
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "sql" {
  name                          = "pe-${var.server_name}-sql"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.server_name}-sql"

  private_service_connection {
    name                           = "psc-${var.server_name}-sql"
    private_connection_resource_id = azurerm_mssql_server.this.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id == null ? [] : [var.private_dns_zone_id]
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
