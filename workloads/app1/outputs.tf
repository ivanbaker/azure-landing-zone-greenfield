output "resource_group_name" {
  description = "Resource group holding the application resources."
  value       = azurerm_resource_group.app.name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = try(module.key_vault[0].vault_uri, null)
}

output "storage_account_name" {
  description = "Application data storage account."
  value       = try(module.storage_account[0].name, null)
}

output "vm_private_ip" {
  description = "Private IP of the VM. Connect through Bastion or VPN."
  value       = try(module.virtual_machine[0].private_ip_address, null)
}

output "sql_server_fqdn" {
  description = "SQL server FQDN (private)."
  value       = try(module.sql_database[0].server_fqdn, null)
}

output "logic_app_hostname" {
  description = "Logic App hostname (private)."
  value       = try(module.logic_app[0].default_hostname, null)
}

output "function_app_hostname" {
  description = "Function App hostname (private)."
  value       = try(module.function_app[0].default_hostname, null)
}

output "vm_generated_ssh_private_key" {
  description = "Break-glass SSH key for the VM's local admin. Prefer Entra ID sign-in."
  value       = try(module.virtual_machine[0].generated_ssh_private_key, null)
  sensitive   = true
}
