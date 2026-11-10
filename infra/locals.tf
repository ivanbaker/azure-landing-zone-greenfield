data "azapi_client_config" "current" {}

locals {
  root_parent_id = coalesce(var.root_parent_management_group_id, data.azapi_client_config.current.tenant_id)

  # ---------------------------------------------------------------------------
  # Resource names. Names are computed from inputs only (never from resource
  # outputs) so that policy parameters below are known at plan time.
  # ---------------------------------------------------------------------------
  names = {
    management_resource_group   = "rg-management-${var.location}"
    log_analytics_workspace     = "law-management-${var.location}"
    ama_identity                = "uami-ama-${var.location}"
    dcr_change_tracking         = "dcr-change-tracking-${var.location}"
    dcr_vm_insights             = "dcr-vm-insights-${var.location}"
    dcr_defender_sql            = "dcr-defender-sql-${var.location}"
    connectivity_resource_group = "rg-connectivity-${var.location}"
    dns_resource_group          = "rg-dns-${var.location}"
    service_health_rg           = "rg-alz-service-health-${var.location}"
    defender_export_rg          = "rg-alz-defender-export-${var.location}"
    ddos_protection_plan        = "ddos-${var.location}"
  }

  management_rg_id = "/subscriptions/${var.subscription_ids.management}/resourceGroups/${local.names.management_resource_group}"

  # ---------------------------------------------------------------------------
  # Values injected into the ALZ policy assignments (e.g. which workspace the
  # "deploy diagnostic settings" policies should send logs to).
  # ---------------------------------------------------------------------------
  policy_default_values_raw = merge(
    {
      log_analytics_workspace_id                  = "${local.management_rg_id}/providers/Microsoft.OperationalInsights/workspaces/${local.names.log_analytics_workspace}"
      ama_user_assigned_managed_identity_id       = "${local.management_rg_id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${local.names.ama_identity}"
      ama_user_assigned_managed_identity_name     = local.names.ama_identity
      ama_change_tracking_data_collection_rule_id = "${local.management_rg_id}/providers/Microsoft.Insights/dataCollectionRules/${local.names.dcr_change_tracking}"
      ama_vm_insights_data_collection_rule_id     = "${local.management_rg_id}/providers/Microsoft.Insights/dataCollectionRules/${local.names.dcr_vm_insights}"
      ama_mdfc_sql_data_collection_rule_id        = "${local.management_rg_id}/providers/Microsoft.Insights/dataCollectionRules/${local.names.dcr_defender_sql}"
      private_dns_zone_subscription_id            = var.subscription_ids.connectivity
      private_dns_zone_resource_group_name        = local.names.dns_resource_group
      private_dns_zone_region                     = var.location
      resource_group_location                     = var.location
      resource_group_name_service_health_alerts   = local.names.service_health_rg
      resource_group_name_mdfc                    = local.names.defender_export_rg
      email_security_contact                      = var.security_contact_email
    },
    {
      for key, value in {
        ddos_protection_plan_id = "/subscriptions/${var.subscription_ids.connectivity}/resourceGroups/${local.names.connectivity_resource_group}/providers/Microsoft.Network/ddosProtectionPlans/${local.names.ddos_protection_plan}"
      } : key => value if var.connectivity_features.ddos_protection_enabled
    }
  )

  # The ALZ module expects each value JSON-encoded as {"value": ...}.
  policy_default_values = { for key, value in local.policy_default_values_raw : key => jsonencode({ value = value }) }

  # Policies that would fail or misbehave because a feature is switched off are
  # set to audit-only (DoNotEnforce) rather than removed, so they still report.
  audit_only_policies = {
    connectivity = { assignment = "Enable-DDoS-VNET", audit_only = !var.connectivity_features.ddos_protection_enabled }
    landingzones = { assignment = "Enable-DDoS-VNET", audit_only = !var.connectivity_features.ddos_protection_enabled }
    corp         = { assignment = "Deploy-Private-DNS-Zones", audit_only = !var.connectivity_features.private_dns_zones_enabled }
  }
  policy_assignments_to_modify = {
    for management_group, policy in local.audit_only_policies : management_group => {
      policy_assignments = { (policy.assignment) = { enforcement_mode = "DoNotEnforce" } }
    } if policy.audit_only
  }

  # ---------------------------------------------------------------------------
  # Subscription placement. A subscription reused for several roles is placed
  # only once, in the management group of the first role it appears in.
  # ---------------------------------------------------------------------------
  platform_roles = ["management", "connectivity", "identity"]
  platform_subscription_ids = {
    management   = var.subscription_ids.management
    connectivity = var.subscription_ids.connectivity
    identity     = var.subscription_ids.identity
  }
  subscription_placement = {
    for index, role in local.platform_roles : role => {
      subscription_id       = local.platform_subscription_ids[role]
      management_group_name = role
    }
    if local.platform_subscription_ids[role] != null && !contains(
      [for earlier in slice(local.platform_roles, 0, index) : local.platform_subscription_ids[earlier]],
      local.platform_subscription_ids[role]
    )
  }

  # The workload subscription is moved into Corp/Online by the vending module,
  # unless it doubles as a platform subscription in a single-subscription lab.
  workload_is_platform_subscription = contains(values(local.platform_subscription_ids), coalesce(var.subscription_ids.workload, "none"))
}
