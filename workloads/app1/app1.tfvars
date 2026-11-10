# Non-sensitive settings for the app1 workload. Subscription IDs come from
# the pipeline (TF_VAR_subscription_ids), the same as for infra/.

location          = "eastus2"
landing_zone_name = "app1"
workload_name     = "app1"

deploy = {
  key_vault       = true
  storage_account = true
  virtual_machine = true
  sql_database    = true
  logic_app       = true
  function_app    = true
}

# vm_admin_principal_ids = ["00000000-0000-0000-0000-000000000000"]

# sql_entra_admin = {
#   login_username = "sg-app1-sql-admins"
#   object_id      = "00000000-0000-0000-0000-000000000000"
# }
