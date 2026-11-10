terraform {
  required_version = "~> 1.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.35"
    }
  }

  # Same state storage account as the platform, different key:
  #   key = "workloads/app1.tfstate"
  backend "azurerm" {}
}
