output "server_id" {
  description = "SQL server resource ID."
  value       = azurerm_mssql_server.this.id
}

output "server_fqdn" {
  description = "Server FQDN. Resolves to the private endpoint from inside the VNet."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "server_principal_id" {
  description = "Object ID of the server's managed identity."
  value       = azurerm_mssql_server.this.identity[0].principal_id
}

output "database_ids" {
  description = "Database resource IDs keyed by name."
  value       = { for name, db in azurerm_mssql_database.this : name => db.id }
}

output "connection_string_template" {
  description = "ADO.NET connection string using Entra ID managed identity authentication (replace <database>)."
  value       = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},1433;Database=<database>;Authentication=Active Directory Managed Identity;Encrypt=True;"
}
