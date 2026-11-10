terraform {
  required_version = "~> 1.12"

  required_providers {
    alz = {
      source  = "Azure/alz"
      version = "~> 0.21"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.35"
    }
  }

  # Remote state lives in the storage account created by bootstrap/bootstrap.sh.
  # Settings are supplied at init time:
  #   terraform init -backend-config=backend.hcl
  # (the GitHub Actions workflows pass them from repository variables).
  backend "azurerm" {}
}
