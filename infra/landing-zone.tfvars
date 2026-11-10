# Non-sensitive settings for the landing zone. Committed to the repo so every
# change goes through a pull request and shows up in the Terraform plan.
#
# Subscription IDs and the security contact email are NOT stored here. The
# GitHub Actions workflows supply them from repository variables:
#   TF_VAR_subscription_ids, TF_VAR_security_contact_email
# For local runs, copy local.auto.tfvars.example to local.auto.tfvars (git-ignored).

location = "eastus2"

tags = {
  managed_by  = "terraform"
  workload    = "platform-landing-zone"
  environment = "lab"
}

log_analytics_retention_days = 30
sentinel_enabled             = false

hub_address_space = "10.0.0.0/16"

# Cost-aware defaults for a lab. Review the README cost table before changing.
connectivity_features = {
  firewall_enabled          = true
  firewall_sku_tier         = "Basic"
  bastion_enabled           = false
  vpn_gateway_enabled       = false
  expressroute_enabled      = false
  private_dns_zones_enabled = true
  dns_resolver_enabled      = false
  ddos_protection_enabled   = false
}

workload_landing_zone = {
  enabled          = true
  name             = "app1"
  management_group = "corp"
  address_space    = "10.1.0.0/24"
  # owner_object_id = "00000000-0000-0000-0000-000000000000"
  # budget = {
  #   amount         = 100
  #   start_date     = "2026-12-01T00:00:00Z"
  #   end_date       = "2027-11-30T00:00:00Z"
  #   contact_emails = ["you@example.com"]
  # }
}
