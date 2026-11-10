# Central logging and monitoring in the management subscription:
# Log Analytics workspace, Azure Monitor Agent identity and data collection rules
# (VM Insights, Change Tracking, Defender for SQL). ALZ policies point every
# subscription's diagnostics and agents at these resources.
module "management" {
  source  = "Azure/avm-ptn-alz-management/azurerm"
  version = "0.10.0"

  location                     = var.location
  resource_group_name          = local.names.management_resource_group
  log_analytics_workspace_name = local.names.log_analytics_workspace

  log_analytics_workspace_retention_in_days = var.log_analytics_retention_days
  log_analytics_workspace_sku               = "PerGB2018"

  # Azure Automation is no longer needed now that Change Tracking and Update
  # Manager run on the Azure Monitor Agent.
  automation_account_name                    = null
  linked_automation_account_creation_enabled = false

  data_collection_rules = {
    change_tracking = { name = local.names.dcr_change_tracking }
    vm_insights     = { name = local.names.dcr_vm_insights }
    defender_sql    = { name = local.names.dcr_defender_sql }
  }

  user_assigned_managed_identities = {
    ama = { name = local.names.ama_identity }
  }

  sentinel_onboarding = var.sentinel_enabled ? {} : null

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}
