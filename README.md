# Azure Landing Zone (Terraform)

An end-to-end Azure platform landing zone, deployed from GitHub Actions with Terraform. It follows Microsoft's [Cloud Adoption Framework landing zone architecture](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/) and is built on [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/), the modules Microsoft now recommends for ALZ in place of the retired `caf-enterprise-scale` module.

The repository deploys:

| Area | What gets deployed |
|---|---|
| **Governance** | The ALZ management group hierarchy, more than 120 Azure Policy assignments from the ALZ library (security baselines, diagnostics, Defender for Cloud, allowed resource rules), and the ALZ custom RBAC roles |
| **Management** | A central Log Analytics workspace, Azure Monitor Agent managed identity, and data collection rules for VM Insights, Change Tracking and Defender for SQL. Microsoft Sentinel is optional |
| **Connectivity** | A hub VNet with Azure Firewall and firewall policy, and private DNS zones for Private Link. Bastion, VPN or ExpressRoute gateways, DNS Private Resolver and DDoS Network Protection are optional |
| **Application landing zone** | A subscription moved into **Corp** using the ALZ subscription vending pattern. It has a spoke VNet peered to the hub, a default route through the firewall, NSGs on every subnet, RBAC for the app team, and an optional budget |
| **Service modules** | Reusable modules for Key Vault, Storage, Virtual Machines, Azure SQL, Logic Apps Standard and Function Apps. All are private-endpoint-only and compliant with the landing zone policies. An example workload (`workloads/app1`) deploys all six into the spoke |
| **Delivery** | GitHub Actions: lint and security scan on every PR, `terraform plan` posted to the PR, and `apply` gated by an environment approval. Sign-in uses OIDC (no stored secrets). A manual destroy workflow is included |

## Architecture

```mermaid
flowchart TB
    subgraph MG["Management groups (Azure Policy inherited downward)"]
        ROOT["Azure Landing Zones"]
        ROOT --> PLAT["Platform"]
        ROOT --> LZ["Landing zones"]
        ROOT --> SBX["Sandbox"]
        ROOT --> DECOM["Decommissioned"]
        PLAT --> MGMT_MG["Management"]
        PLAT --> CONN_MG["Connectivity"]
        PLAT --> ID_MG["Identity"]
        PLAT --> SEC_MG["Security"]
        LZ --> CORP["Corp"]
        LZ --> ONLINE["Online"]
    end

    subgraph MGMT_SUB["Management subscription"]
        LAW["Log Analytics workspace"]
        DCR["Data collection rules + AMA identity"]
    end

    subgraph CONN_SUB["Connectivity subscription"]
        subgraph HUB["Hub VNet 10.0.0.0/16"]
            FW["Azure Firewall"]
            BAS["Bastion (optional)"]
            GW["VPN / ER gateway (optional)"]
        end
        DNS["Private DNS zones"]
    end

    subgraph APP_SUB["Workload subscription (Corp)"]
        subgraph SPOKE["Spoke VNet 10.1.0.0/24"]
            APPSN["snet-app: VM"]
            PESN["snet-private-endpoints: Key Vault, Storage, SQL, Logic App, Function App"]
            INTSN["snet-integration-*: App Service VNet integration"]
        end
    end

    MGMT_MG -.-> MGMT_SUB
    CONN_MG -.-> CONN_SUB
    CORP -.-> APP_SUB
    SPOKE <-->|peering| HUB
    APPSN -->|0.0.0.0/0| FW
    INTSN -->|0.0.0.0/0| FW
    MGMT_SUB -. diagnostics from all subscriptions .- LAW
```

More detail: [docs/architecture.md](docs/architecture.md). The reasons behind each choice: [docs/design-decisions.md](docs/design-decisions.md).

## Repository layout

```
.
├── bootstrap/                 One-time setup: state storage + GitHub OIDC identity
│   └── bootstrap.sh
├── infra/                     The landing zone (one Terraform root module)
│   ├── main.governance.tf     Management groups, policy, RBAC      (avm-ptn-alz)
│   ├── main.management.tf     Logging and monitoring               (avm-ptn-alz-management)
│   ├── main.connectivity.tf   Hub network, firewall, DNS           (avm-ptn-alz-connectivity-hub-and-spoke-vnet)
│   ├── main.landing_zones.tf  Application landing zone             (avm-ptn-alz-sub-vending)
│   ├── locals.tf              Naming, policy parameters, subscription placement
│   ├── variables.tf / outputs.tf / providers.tf / terraform.tf
│   └── landing-zone.tfvars    Committed, non-sensitive settings
├── modules/                   Reusable service modules (see modules/README.md)
│   ├── key-vault/  storage-account/  virtual-machine/
│   └── sql-database/  logic-app/  function-app/
├── workloads/app1/            Example application using all six modules
├── docs/
└── .github/workflows/         ci.yml, terraform.yml (reusable), deploy-platform.yml,
                               deploy-app1.yml, destroy.yml
```

## Prerequisites

- An Entra ID tenant where you can assign roles at the **Tenant Root Group**. This means Owner there, or Global Administrator with [elevated access](https://learn.microsoft.com/azure/role-based-access-control/elevate-access-global-admin).
- Two or three subscriptions: management, connectivity and (optionally) workload. For a low-cost lab you can reuse one subscription for several roles. See `subscription_ids` in [variables.tf](infra/variables.tf).
- Azure CLI 2.60 or newer. For local runs, also Terraform 1.12 or newer.

> Use a test tenant. This creates management groups at the top of the tenant and assigns policies that **deny** some resource configurations, such as public IPs on NICs in Corp and subnets without NSGs. Don't point it at a tenant with existing workloads until you've reviewed the policies.

## Deploy

**1. Bootstrap (once).** In Azure Cloud Shell:

```bash
./bootstrap/bootstrap.sh <github-owner>/<repo-name> <management-sub-id> <connectivity-sub-id> <workload-sub-id>
```

This creates the remote state storage account and an app registration with federated credentials for this repo, and grants it its roles. It then prints the repository variables to set.

**2. Set repository variables** in *Settings → Secrets and variables → Actions → Variables*:

| Variable | Example |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | printed by bootstrap |
| `TF_STATE_RESOURCE_GROUP`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER` | printed by bootstrap |
| `SUBSCRIPTION_IDS` | `{"management":"…","connectivity":"…","workload":"…"}` |
| `SECURITY_CONTACT_EMAIL` | `you@example.com` |

**3. Create the `production` environment** (*Settings → Environments*) and add yourself as a required reviewer.

**4. Open a pull request** that changes anything under `infra/`. The plan is posted as a comment. Merge it, approve the deployment, and the apply runs. The first apply takes about 30–45 minutes, mostly for the firewall and the policy role assignments.

**5. Deploy the example workload (optional).** Once the platform is in place, run *Actions → Deploy app1 workload*, or open a PR that changes `workloads/app1/` or `modules/`. It deploys a Key Vault, storage account, Linux VM, Azure SQL database, Logic App and Function App into the app1 spoke, all reachable only on private IPs. Switch services off in `workloads/app1/app1.tfvars`.

### Running locally

```bash
cd infra
cp backend.hcl.example backend.hcl                    # fill in from bootstrap output (key = landing-zone.tfstate)
cp local.auto.tfvars.example local.auto.tfvars        # subscription IDs + email
az login
terraform init -backend-config=backend.hcl
terraform plan -var-file=landing-zone.tfvars
```

After the first successful `init`, commit `infra/.terraform.lock.hcl` so every run uses the same provider versions.

## Cost

Approximate pay-as-you-go prices for US regions. Check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for current figures in your region.

| Component | Default | Approx. monthly cost |
|---|---|---|
| Azure Firewall Basic | **on** | ~$290 plus data processed |
| Azure Firewall Standard / Premium | off | ~$900 / ~$1,300 |
| Log Analytics | **on** | pay per GB ingested (small for a lab) |
| Private DNS zones | **on** | ~$0.50 per zone; the full Private Link set is a few dozen zones |
| Azure Bastion | off | ~$140 (Basic) |
| VPN gateway | off | ~$140–$300 |
| DNS Private Resolver | off | ~$180 per endpoint |
| **DDoS Network Protection** | off | **~$2,900** |
| Defender for Cloud plans | per policy defaults | per protected resource |

With the defaults, expect roughly **$350 a month** while it's running.

The **app1 workload** adds roughly $350–$450 a month: Logic App WS1 plan (~$175), Function App P0v3 plan (~$60), D2s_v5 VM (~$70 plus disks), serverless SQL (a few dollars when idle), plus storage, Key Vault and private endpoints (about $7 each, 12 in total). Run the **Destroy landing zone** workflow when you're done.

## Teardown

Run *Actions → Destroy landing zone → Run workflow*, pick **app1** first and then **platform**, and type `destroy` to confirm each time. Key Vaults have purge protection, so a destroyed vault's name stays reserved for 90 days. Policies may have deployed resources outside Terraform's state, such as Defender export or Service Health alert resource groups. Delete those by hand if they remain. Platform subscriptions are moved back to the tenant's default management group, which is normally the Tenant Root Group.

## Roadmap

- Multi-region hub (a second `hub_virtual_networks` entry) with hub-to-hub peering
- Custom least-privilege roles for the pipeline identity instead of Owner at the root
- `terraform test` suites and a nightly drift-detection plan
- Azure Monitor Baseline Alerts (AMBA) policy set

## References

- [Azure Landing Zones documentation (Terraform)](https://azure.github.io/Azure-Landing-Zones/terraform/)
- [Azure Verified Modules: Terraform pattern modules](https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-pattern-modules/)
- [Azure Landing Zones Library](https://azure.github.io/Azure-Landing-Zones-Library/)
