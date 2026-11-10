output "id" {
  description = "VM resource ID."
  value       = local.vm_id
}

output "private_ip_address" {
  description = "Private IP of the VM's NIC."
  value       = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "Object ID of the VM's system-assigned managed identity."
  value       = local.is_linux ? azurerm_linux_virtual_machine.this[0].identity[0].principal_id : azurerm_windows_virtual_machine.this[0].identity[0].principal_id
}

output "generated_ssh_private_key" {
  description = "Generated SSH private key (Linux, only when ssh_public_key was not supplied)."
  value       = try(tls_private_key.ssh[0].private_key_openssh, null)
  sensitive   = true
}

output "generated_admin_password" {
  description = "Generated local admin password (Windows, only when admin_password was not supplied)."
  value       = try(random_password.admin[0].result, null)
  sensitive   = true
}
