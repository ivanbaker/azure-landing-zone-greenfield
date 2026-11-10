# A sample application landing zone, created with the ALZ subscription vending
# module. It shows the pattern a platform team uses to hand out subscriptions:
# move the subscription under Corp/Online so the right policies apply, create a
# spoke VNet peered to the hub, force egress through the firewall, require NSGs
# on every subnet, grant the app team access and set a budget.

locals {
  lz           = var.workload_landing_zone
  lz_location  = var.location
  lz_rg_name   = "rg-${local.lz.name}-network-${var.location}"
  lz_vnet_name = "vnet-${local.lz.name}-${var.location}"

  # Subnets carved from the spoke address space (a /24 gives two /26s and two /27s,
  # leaving the top /26 free for growth).
  lz_subnet_prefixes = {
    app                   = cidrsubnet(local.lz.address_space, 2, 0)
    private_endpoints     = cidrsubnet(local.lz.address_space, 2, 1)
    integration_logicapp  = cidrsubnet(local.lz.address_space, 3, 4)
    integration_functions = cidrsubnet(local.lz.address_space, 3, 5)
  }

  # App Service VNet integration subnets must be delegated to Microsoft.Web/serverFarms.
  app_service_delegation = [{
    name               = "Microsoft.Web.serverFarms"
    service_delegation = { name = "Microsoft.Web/serverFarms" }
  }]
  route_via_firewall = local.features.firewall_enabled ? { key_reference = "to_hub" } : null

  spoke_dns_servers = (
    local.features.dns_resolver_enabled && local.firewall_is_standard
    ? [module.hub_and_spoke.dns_server_ip_addresses["primary"]]
    : []
  )
}

module "workload_landing_zone" {
  source  = "Azure/avm-ptn-alz-sub-vending/azure"
  version = "0.3.4"
  count   = local.lz.enabled ? 1 : 0

  location = local.lz_location

  # Use an existing subscription (creating new ones needs an EA or MCA billing account).
  subscription_alias_enabled                        = false
  subscription_id                                   = var.subscription_ids.workload
  subscription_management_group_association_enabled = !local.workload_is_platform_subscription
  subscription_management_group_id                  = local.lz.management_group

  # Register the common resource providers so the app team can deploy straight away.
  subscription_register_resource_providers_enabled = true

  resource_group_creation_enabled = true
  resource_groups = {
    network = {
      name     = local.lz_rg_name
      location = local.lz_location
      tags     = var.tags
    }
    # Managed here so the subscription can be cancelled cleanly later.
    network_watcher = {
      name     = "NetworkWatcherRG"
      location = local.lz_location
      tags     = var.tags
    }
  }

  network_security_group_enabled = true
  network_security_groups = {
    app = {
      name               = "nsg-${local.lz.name}-app-${var.location}"
      resource_group_key = "network"
      tags               = var.tags
    }
    private_endpoints = {
      name               = "nsg-${local.lz.name}-pe-${var.location}"
      resource_group_key = "network"
      tags               = var.tags
    }
    integration = {
      name               = "nsg-${local.lz.name}-integration-${var.location}"
      resource_group_key = "network"
      tags               = var.tags
    }
  }

  route_table_enabled = local.features.firewall_enabled
  route_tables = { for key, value in {
    to_hub = {
      name                          = "rt-${local.lz.name}-${var.location}"
      location                      = local.lz_location
      resource_group_key            = "network"
      bgp_route_propagation_enabled = false
      tags                          = var.tags
      routes = {
        default = {
          name                   = "default-via-hub-firewall"
          address_prefix         = "0.0.0.0/0"
          next_hop_type          = "VirtualAppliance"
          next_hop_in_ip_address = try(module.hub_and_spoke.firewall_private_ip_addresses["primary"], null)
        }
      }
    }
  } : key => value if local.features.firewall_enabled }

  virtual_network_enabled = true
  virtual_networks = {
    spoke = {
      name               = local.lz_vnet_name
      resource_group_key = "network"
      address_space      = [local.lz.address_space]
      dns_servers        = local.spoke_dns_servers
      tags               = var.tags

      subnets = {
        app = {
          name                   = "snet-app"
          address_prefix         = local.lz_subnet_prefixes.app
          network_security_group = { key_reference = "app" }
          route_table            = local.route_via_firewall
        }
        private_endpoints = {
          name                              = "snet-private-endpoints"
          address_prefix                    = local.lz_subnet_prefixes.private_endpoints
          network_security_group            = { key_reference = "private_endpoints" }
          private_endpoint_network_policies = "Enabled"
        }
        integration_logicapp = {
          name                   = "snet-integration-logicapp"
          address_prefix         = local.lz_subnet_prefixes.integration_logicapp
          network_security_group = { key_reference = "integration" }
          route_table            = local.route_via_firewall
          delegations            = local.app_service_delegation
        }
        integration_functions = {
          name                   = "snet-integration-functions"
          address_prefix         = local.lz_subnet_prefixes.integration_functions
          network_security_group = { key_reference = "integration" }
          route_table            = local.route_via_firewall
          delegations            = local.app_service_delegation
        }
      }

      hub_peering_enabled     = true
      hub_network_resource_id = module.hub_and_spoke.virtual_network_resource_ids["primary"]
      hub_peering_options_tohub = {
        use_remote_gateways = local.features.vpn_gateway_enabled || local.features.expressroute_enabled
      }
      hub_peering_options_fromhub = {
        allow_gateway_transit = local.features.vpn_gateway_enabled || local.features.expressroute_enabled
      }
    }
  }

  role_assignment_enabled = local.lz.owner_object_id != null
  role_assignments = { for key, value in {
    app_team_contributor = {
      principal_id   = coalesce(local.lz.owner_object_id, "unused")
      definition     = "Contributor"
      relative_scope = ""
    }
  } : key => value if local.lz.owner_object_id != null }

  budget_enabled = local.lz.budget != null
  budgets = { for key, value in {
    monthly = {
      name              = "budget-${local.lz.name}-monthly"
      amount            = try(local.lz.budget.amount, 0)
      time_grain        = "Monthly"
      time_period_start = try(local.lz.budget.start_date, "")
      time_period_end   = try(local.lz.budget.end_date, "")
      notifications = {
        actual_80 = {
          enabled        = true
          operator       = "GreaterThan"
          threshold      = 80
          threshold_type = "Actual"
          contact_emails = try(local.lz.budget.contact_emails, [])
        }
        forecast_100 = {
          enabled        = true
          operator       = "GreaterThan"
          threshold      = 100
          threshold_type = "Forecasted"
          contact_emails = try(local.lz.budget.contact_emails, [])
        }
      }
    }
  } : key => value if local.lz.budget != null }

  enable_telemetry = var.enable_telemetry

  # The Corp/Online management groups must exist before the subscription moves.
  depends_on = [module.governance]
}

# Link the hub's private DNS zones to the spoke so names such as
# <vault>.vault.azure.net resolve to private endpoint IPs from the spoke
# (without a DNS Private Resolver in the hub). Zone IDs are built from names so
# the for_each keys are known at plan time.
locals {
  spoke_private_dns_zones = toset([
    "privatelink.vaultcore.azure.net",
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.database.windows.net",
    "privatelink.azurewebsites.net",
  ])
  # Not needed when spokes already use the hub's DNS proxy + resolver.
  link_spoke_to_dns = (
    local.lz.enabled && local.features.private_dns_zones_enabled &&
    !(local.features.dns_resolver_enabled && local.firewall_is_standard)
  )
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = local.link_spoke_to_dns ? local.spoke_private_dns_zones : toset([])
  provider = azurerm.connectivity

  name                  = "link-${local.lz_vnet_name}"
  resource_group_name   = azurerm_resource_group.dns.name
  private_dns_zone_name = each.key
  virtual_network_id    = module.workload_landing_zone[0].virtual_network_resource_ids["spoke"]
  registration_enabled  = false
  tags                  = var.tags

  depends_on = [module.hub_and_spoke]
}
