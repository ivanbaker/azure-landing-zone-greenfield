# Hub network in the connectivity subscription: hub VNet, Azure Firewall and
# policy, private DNS zones for Private Link, and optional Bastion, VPN /
# ExpressRoute gateways, DNS Private Resolver and DDoS Network Protection.

locals {
  features             = var.connectivity_features
  firewall_is_standard = local.features.firewall_enabled && local.features.firewall_sku_tier != "Basic"
}

resource "azurerm_resource_group" "connectivity" {
  provider = azurerm.connectivity

  name     = local.names.connectivity_resource_group
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "dns" {
  provider = azurerm.connectivity

  name     = local.names.dns_resource_group
  location = var.location
  tags     = var.tags
}

module "hub_and_spoke" {
  source  = "Azure/avm-ptn-alz-connectivity-hub-and-spoke-vnet/azurerm"
  version = "0.18.1"

  providers = {
    azurerm = azurerm.connectivity
    azapi   = azapi.connectivity
  }

  hub_and_spoke_networks_settings = {
    enabled_resources = {
      ddos_protection_plan = local.features.ddos_protection_enabled
    }
    ddos_protection_plan = {
      name                = local.names.ddos_protection_plan
      resource_group_name = azurerm_resource_group.connectivity.name
      location            = var.location
    }
  }

  hub_virtual_networks = {
    primary = {
      location                  = var.location
      is_primary                = true
      default_hub_address_space = var.hub_address_space
      default_parent_id         = azurerm_resource_group.connectivity.id

      enabled_resources = {
        firewall                              = local.features.firewall_enabled
        firewall_policy                       = local.features.firewall_enabled
        bastion                               = local.features.bastion_enabled
        virtual_network_gateway_vpn           = local.features.vpn_gateway_enabled
        virtual_network_gateway_express_route = local.features.expressroute_enabled
        private_dns_zones                     = local.features.private_dns_zones_enabled
        private_dns_resolver                  = local.features.dns_resolver_enabled
        dns_resolver_policy                   = false
        nat_gateway                           = false
      }

      firewall = {
        sku_tier = local.features.firewall_sku_tier
      }

      firewall_policy = {
        sku = local.features.firewall_sku_tier
      }

      private_dns_zones = {
        parent_id = azurerm_resource_group.dns.id
      }
    }
  }

  tags             = var.tags
  enable_telemetry = var.enable_telemetry
}

# Egress allow-list for workload spokes. Spoke traffic is forced through the
# firewall by a route table (see main.landing_zones.tf); anything not listed
# here is denied by the firewall's default deny.
resource "azurerm_firewall_policy_rule_collection_group" "spoke_egress" {
  count    = local.features.firewall_enabled ? 1 : 0
  provider = azurerm.connectivity

  name               = "rcg-spoke-egress"
  firewall_policy_id = module.hub_and_spoke.firewall_policies["primary"].id
  priority           = 500

  application_rule_collection {
    name     = "allow-web-egress"
    priority = 500
    action   = "Allow"

    rule {
      name              = "allow-approved-fqdns"
      source_addresses  = [var.workload_landing_zone.address_space]
      destination_fqdns = var.firewall_allowed_egress_fqdns

      protocols {
        type = "Https"
        port = 443
      }

      protocols {
        type = "Http"
        port = 80
      }
    }
  }
}
