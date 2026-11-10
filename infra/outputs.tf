output "management_group_ids" {
  description = "Resource IDs of the management groups, keyed by management group name."
  value       = module.governance.management_group_resource_ids
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the central Log Analytics workspace."
  value       = module.management.resource_id
}

output "hub_virtual_network_id" {
  description = "Resource ID of the hub virtual network."
  value       = module.hub_and_spoke.virtual_network_resource_ids["primary"]
}

output "firewall_private_ip" {
  description = "Private IP of the hub Azure Firewall (the next hop for spoke traffic)."
  value       = try(module.hub_and_spoke.firewall_private_ip_addresses["primary"], null)
}

output "private_dns_zone_ids" {
  description = "Private DNS zones for Private Link, created in the connectivity subscription."
  value       = try(module.hub_and_spoke.private_dns_zone_resource_ids["primary"], null)
}

output "workload_spoke_virtual_network_ids" {
  description = "Resource IDs of the workload landing zone spoke virtual networks."
  value       = try(module.workload_landing_zone[0].virtual_network_resource_ids, null)
}
