# Architecture

This repo implements the **platform landing zone** from the Cloud Adoption Framework: the shared foundation that application teams' subscriptions plug into. It covers four of the eight CAF design areas directly: resource organization, governance, management and network topology. It covers a fifth, security, through policy.

## 1. Resource organization: management groups

| Management group | Purpose | Subscriptions placed here |
|---|---|---|
| Azure Landing Zones (`alz`) | Intermediate root. Tenant-wide guardrails are assigned here, not at the Tenant Root Group | none |
| Platform → Management | Central logging and monitoring | `management` |
| Platform → Connectivity | Hub networking | `connectivity` |
| Platform → Identity | Domain controllers / identity services | `identity` (optional) |
| Platform → Security | Security tooling (e.g. Sentinel in its own subscription) | none by default |
| Landing zones → Corp | Internal workloads, private and connected to the hub | `workload` |
| Landing zones → Online | Internet-facing workloads | none by default |
| Sandbox | Experimentation, isolated from Corp networking | none |
| Decommissioned | Subscriptions being retired | none |

Placement is the main control. Moving a subscription into a management group applies every policy assigned to that group and its parents. Application teams get a consistent baseline without filing a ticket.

## 2. Governance: Azure Policy

Policies come from the [Azure Landing Zones Library](https://azure.github.io/Azure-Landing-Zones-Library/), pinned to release `2026.11.0` in `providers.tf`. Some examples of what is enforced:

- **At the root:** Defender for Cloud configuration, activity log and resource diagnostics sent to the central workspace, Service Health alerts, the Azure compute security baseline, and denial of classic resources and unmanaged disks.
- **Landing zones:** no subnets without an NSG, private subnets (no default outbound access), no IP forwarding, no management ports open to the internet, HTTPS-only storage, Azure Monitor Agent and Change Tracking on VMs using the shared data collection rules, VM backup, and service guardrails for Key Vault, SQL, AKS and others.
- **Corp:** no public IPs on NICs, no public PaaS endpoints, and no hybrid networking resources inside workloads. Private endpoints automatically register in the hub's private DNS zones.
- **Connectivity / Identity:** platform-specific network and VM rules.

Policies that depend on a switched-off feature are set to `DoNotEnforce` instead of being removed. For example, *Enable DDoS on VNets* is set this way when DDoS Network Protection is off. They still report compliance, so the gap is visible. See `local.policy_assignments_to_modify` in `infra/locals.tf`.

Policy parameters such as the workspace ID and DCR IDs are built from **names** rather than resource outputs. This keeps them known at plan time, which the ALZ provider requires.

## 3. Management: logging and monitoring

`avm-ptn-alz-management` creates the Log Analytics workspace, a user-assigned managed identity for the Azure Monitor Agent, and three data collection rules. ALZ policies then deploy the agent to every VM in every subscription and attach these rules. Azure Automation is intentionally not deployed, because Change Tracking and Update Manager now run on AMA.

## 4. Network topology: hub and spoke

```
             ┌──────────── Connectivity subscription ────────────┐
             │  Hub VNet 10.0.0.0/16                            │
  on-prem ───┤   ├── GatewaySubnet          (VPN/ER, optional)  │
             │   ├── AzureFirewallSubnet    Azure Firewall      │
             │   ├── AzureFirewallMgmtSubnet (Basic SKU)        │
             │   ├── AzureBastionSubnet     (optional)          │
             │   └── DNS resolver subnets   (optional)          │
             │  Private DNS zones (privatelink.*) linked to hub │
             └───────────────────────▲─────────────────────────┘
                                     │ VNet peering
             ┌───────────────────────┴─── Workload subscription ─┐
             │  Spoke VNet 10.1.0.0/24                           │
             │   ├── snet-app                   10.1.0.0/26   VMs │
             │   ├── snet-private-endpoints     10.1.0.64/26      │
             │   ├── snet-integration-logicapp  10.1.0.128/27 *   │
             │   ├── snet-integration-functions 10.1.0.160/27 *   │
             │   └── (free)                     10.1.0.192/26     │
             │  every subnet: NSG; app + integration: UDR → FW   │
             │  * delegated to Microsoft.Web/serverFarms         │
             └───────────────────────────────────────────────────┘
```

- **Egress:** a route table on the app subnet sends `0.0.0.0/0` to the firewall. The firewall policy allows HTTP/HTTPS only to the FQDNs in `firewall_allowed_egress_fqdns` and denies everything else.
- **Name resolution:** with the defaults, spokes use Azure-provided DNS, and the hub's private DNS zones for Key Vault, Storage, SQL and App Service are linked to the spoke. Private endpoint names therefore resolve to private IPs without a DNS server. For a central model, set `dns_resolver_enabled = true` with a Standard or Premium firewall. The firewall then acts as a DNS proxy in front of the resolver, spokes point at it automatically, and the per-spoke links are dropped.
- **Gateway transit:** when a VPN or ExpressRoute gateway is enabled, spoke peerings switch to `use_remote_gateways` automatically.

## 5. Application landing zones: subscription vending

`avm-ptn-alz-sub-vending` shows how a platform team hands a subscription to an app team. In one module call it:

1. moves the subscription into Corp or Online,
2. creates the network resource group, NSGs, route table and spoke VNet,
3. peers the spoke to the hub in both directions,
4. grants the team's Entra ID group Contributor, and
5. creates a monthly budget with alerts at 80% actual and 100% forecast.

Adding another application means adding another module call, or turning `workload_landing_zone` into a map and using `for_each`. It doesn't take a new architecture.

## Deployment pipeline

```
 PR opened ──► ci.yml:     fmt ─► validate ─► tflint ─► checkov
           └─► deploy.yml: plan (OIDC) ─► plan posted as PR comment

 merge to main ─► deploy.yml: plan ─► [approval on "production"] ─► apply saved plan
```

- **No secrets:** GitHub's OIDC token is exchanged for an Entra ID token through federated credentials. The credentials are scoped to this repo's `main` branch, its pull requests and the `production` environment.
- **What you approve is what runs:** apply uses the exact plan file and provider lock file from the plan job.
- **One writer at a time:** a shared `concurrency` group serializes all runs against the state file.

## 6. Workloads: service modules

`modules/` holds one module per service, and `workloads/app1` shows them used together:

```
 Function App ──(managed identity)──► Key Vault (secrets)
      │  └────(managed identity)──► Storage (blob data)
      │  └────(managed identity)──► own storage (runtime state, no keys)
 Logic App ────(managed identity)──► Key Vault
      └──────────────────────────► own storage (keys; private endpoints only)
 VM ──(Entra ID sign-in via Bastion)
 SQL ──(Entra ID only; apps connect with managed identity)
```

Inbound traffic to every service arrives through a private endpoint in `snet-private-endpoints`. The two app platforms send all outbound traffic through their integration subnets, so it passes the hub firewall like everything else. Diagnostics reach the central workspace through the ALZ `Deploy-Diag-LogsCat` policy, so the modules don't configure diagnostic settings themselves.
