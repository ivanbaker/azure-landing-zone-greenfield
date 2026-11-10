output "id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Key Vault URI, e.g. for Key Vault references in app settings."
  value       = azurerm_key_vault.this.vault_uri
}

output "private_endpoint_ip" {
  description = "Private IP address of the Key Vault private endpoint."
  value       = azurerm_private_endpoint.vault.private_service_connection[0].private_ip_address
}
