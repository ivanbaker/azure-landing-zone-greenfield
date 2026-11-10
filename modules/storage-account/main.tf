resource "azurerm_storage_account" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = var.account_tier
  account_replication_type = var.replication_type

  # Security baseline (aligned with the ALZ storage guardrail policies).
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = false
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.blob_soft_delete_days
    }

    container_delete_retention_policy {
      days = var.blob_soft_delete_days
    }
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "this" {
  for_each = var.private_endpoint_subresources

  name                          = "pe-${var.name}-${each.key}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-${each.key}"

  private_service_connection {
    name                           = "psc-${var.name}-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = contains(keys(var.private_dns_zone_ids), each.key) ? [var.private_dns_zone_ids[each.key]] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }

  tags = var.tags

  # When the DNS zone group is added by ALZ policy rather than Terraform,
  # don't remove it on the next apply.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

# Containers and shares are created through Azure Resource Manager
# (storage_account_id), so they work while the data plane is private.
resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
  quota              = each.value.quota_gb
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = azurerm_storage_account.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}
