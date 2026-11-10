output "id" {
  description = "Logic App resource ID."
  value       = azurerm_logic_app_standard.this.id
}

output "default_hostname" {
  description = "Hostname. Resolves to the private endpoint from inside the VNet."
  value       = azurerm_logic_app_standard.this.default_hostname
}

output "principal_id" {
  description = "Object ID of the Logic App's managed identity (grant it access to Key Vault, Service Bus, etc.)."
  value       = azurerm_logic_app_standard.this.identity[0].principal_id
}

output "storage_account_id" {
  description = "Backing storage account ID."
  value       = module.storage.id
}
