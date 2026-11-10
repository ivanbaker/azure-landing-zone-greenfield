output "id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Blob endpoint. Resolves to the private endpoint from inside the VNet."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "primary_access_key" {
  description = "Primary access key (only usable when shared_access_key_enabled = true)."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "private_endpoint_ids" {
  description = "Private endpoint IDs keyed by subresource."
  value       = { for key, pe in azurerm_private_endpoint.this : key => pe.id }
}
