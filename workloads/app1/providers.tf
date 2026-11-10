provider "azurerm" {
  subscription_id = var.subscription_ids.workload

  # Storage accounts here have public access and shared keys disabled, so the
  # provider must use Entra ID and skip data-plane calls it can't reach from a
  # GitHub-hosted runner.
  storage_use_azuread             = true
  resource_provider_registrations = "none"

  features {
    storage {
      data_plane_available = false
    }
    key_vault {
      # Purge protection is on; don't try to purge on destroy.
      purge_soft_delete_on_destroy = false
    }
  }
}
