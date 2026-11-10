output "id" {
  description = "Function App resource ID."
  value       = azurerm_linux_function_app.this.id
}

output "default_hostname" {
  description = "Hostname. Resolves to the private endpoint from inside the VNet."
  value       = azurerm_linux_function_app.this.default_hostname
}

output "principal_id" {
  description = "Object ID of the Function App's managed identity (grant it access to Key Vault, SQL, etc.)."
  value       = azurerm_linux_function_app.this.identity[0].principal_id
}

output "storage_account_id" {
  description = "Backing storage account ID."
  value       = module.storage.id
}

output "application_insights_id" {
  description = "Application Insights resource ID, when created."
  value       = try(azurerm_application_insights.this[0].id, null)
}
