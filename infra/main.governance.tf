# Management group hierarchy, Azure Policy and custom RBAC roles from the
# Azure Landing Zones reference architecture:
#
#   Tenant Root Group
#   └── Azure Landing Zones (alz)
#       ├── Platform
#       │   ├── Connectivity
#       │   ├── Identity
#       │   ├── Management
#       │   └── Security
#       ├── Landing zones
#       │   ├── Corp
#       │   ├── Online
#       │   └── Local
#       ├── Sandbox
#       └── Decommissioned
module "governance" {
  source  = "Azure/avm-ptn-alz/azurerm"
  version = "0.22.0"

  architecture_name  = "alz"
  parent_resource_id = local.root_parent_id
  location           = var.location

  policy_default_values        = local.policy_default_values
  policy_assignments_to_modify = local.policy_assignments_to_modify
  subscription_placement       = local.subscription_placement

  # Policies that deploy agents and diagnostics reference the management and
  # connectivity resources, so assign them only after those exist.
  policy_assignments_dependencies      = [module.management, module.hub_and_spoke]
  policy_role_assignments_dependencies = [module.management, module.hub_and_spoke]

  enable_telemetry = var.enable_telemetry
}

# The ALZ provider can't work out the roles for one policy assignment (it
# reports "PolicyRoleAssignmentError ... Deploy-MCSB2-Monitoring" during plan),
# because the identity is passed into a nested policy set. Grant the roles it
# names explicitly, so the policy can deploy the monitoring agent and its
# managed identity to VMs. See https://github.com/Azure/alzlib/issues/189
resource "azurerm_role_assignment" "mcsb2_monitoring" {
  for_each = toset(["Contributor", "User Access Administrator"])

  scope                = module.governance.management_group_resource_ids["alz"]
  role_definition_name = each.key
  principal_id         = module.governance.policy_assignment_identity_ids["alz/Deploy-MCSB2-Monitoring"]
  principal_type       = "ServicePrincipal"
}
