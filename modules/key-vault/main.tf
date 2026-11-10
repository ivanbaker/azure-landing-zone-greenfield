data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name

  # Azure RBAC instead of access policies, so access is managed like everything else.
  rbac_authorization_enabled = true

  # Required by the ALZ Key Vault guardrail policies.
  purge_protection_enabled   = true
  soft_delete_retention_days = var.soft_delete_retention_days

  # Reachable only through the private endpoint.
  public_network_access_enabled = false
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "vault" {
  name                          = "pe-${var.name}-vault"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${var.name}-vault"

  private_service_connection {
    name                           = "psc-${var.name}-vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
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

  # When the DNS zone group is added by ALZ policy rather than Terraform,
  # don't remove it on the next apply.
  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = azurerm_key_vault.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}
