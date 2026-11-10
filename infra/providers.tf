# The ALZ provider reads the Azure Landing Zones Library: the reference set of
# management groups, archetypes and Azure Policy definitions published by Microsoft.
# The library version is pinned so a policy change upstream never lands by surprise.
provider "alz" {
  # The one assignment this warns about is handled in main.governance.tf.
  suppress_warning_policy_role_assignments = true

  library_references = [
    {
      path = "platform/alz"
      ref  = "2026.11.0"
    }
  ]
}

# Default providers point at the management subscription.
provider "azurerm" {
  subscription_id                 = var.subscription_ids.management
  resource_provider_registrations = "none"
  features {}
}

provider "azapi" {
  subscription_id            = var.subscription_ids.management
  skip_provider_registration = true
}

# Aliased providers for the connectivity (hub networking) subscription.
provider "azurerm" {
  alias                           = "connectivity"
  subscription_id                 = var.subscription_ids.connectivity
  resource_provider_registrations = "none"
  features {}
}

provider "azapi" {
  alias                      = "connectivity"
  subscription_id            = var.subscription_ids.connectivity
  skip_provider_registration = true
}
