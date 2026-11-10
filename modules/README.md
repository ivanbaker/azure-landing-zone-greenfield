# Service modules

Reusable Terraform modules for common Azure services. They're built to drop into a **Corp** application landing zone: private by default, and they pass the ALZ policies assigned to the Landing zones and Corp management groups.

| Module | Creates | Private endpoint(s) | Key security defaults |
|---|---|---|---|
| [key-vault](key-vault) | Key Vault, RBAC role assignments | `vault` | RBAC authorization (no access policies), purge protection, public access off |
| [storage-account](storage-account) | StorageV2 account, containers, file shares, RBAC | any of `blob` `file` `queue` `table` `dfs` `web` | Shared keys off (Entra ID only), TLS 1.2, infrastructure encryption, blob versioning and soft delete, public access off |
| [virtual-machine](virtual-machine) | Linux (Ubuntu 24.04) or Windows Server 2025 VM, NIC, data disks, Entra ID login | n/a (NIC in `snet-app`, no public IP) | Trusted Launch, platform patching, managed identity, Entra ID sign-in, disks deny public export |
| [sql-database](sql-database) | Azure SQL logical server + databases | `sqlServer` | Entra-ID-only authentication, TLS 1.2, TDE; serverless by default |
| [logic-app](logic-app) | Logic App Standard, WS1 plan, backing storage (via storage-account) | `sites` + storage `blob` `file` `queue` `table` | VNet integration with route-all, content share over VNet, no basic auth or FTP, public access off |
| [function-app](function-app) | Linux Function App, Premium v3 plan, backing storage, optional App Insights | `sites` + storage `blob` `queue` `table` | Identity-based storage (no keys), VNet integration with route-all, no basic auth or FTP, public access off |

See [workloads/app1](../workloads/app1) for all six wired together.

## Usage

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  name                       = "kv-app1-prod"
  resource_group_name        = azurerm_resource_group.app.name
  location                   = "eastus2"
  private_endpoint_subnet_id = data.azurerm_subnet.pe.id
  private_dns_zone_id        = local.dns_zone_ids.vault # optional, see below

  role_assignments = {
    api = { principal_id = module.function_app.principal_id, role = "Key Vault Secrets User" }
  }
}
```

## Private DNS: two ways it can work

Each private endpoint needs an A record in the matching `privatelink.*` zone in the hub.

1. **Let ALZ policy do it.** Leave the DNS zone input empty. In a Corp landing zone the `Deploy-Private-DNS-Zones` policy adds the record a few minutes after the endpoint is created.
2. **Pass the zone ID.** The record is created as part of `terraform apply`. The Logic App and Function App modules need this for their storage, because the app reads its storage over the VNet when it first starts.

Either way, every endpoint has `lifecycle { ignore_changes = [private_dns_zone_group] }`, so Terraform doesn't remove a record group that policy added.

## Things to know

- **Provider settings for private storage.** A root module that uses `storage-account` with shared keys off must configure the provider with `storage_use_azuread = true` and `features { storage { data_plane_available = false } }`. Otherwise the provider tries data-plane calls that a GitHub-hosted runner can't reach. Containers and shares are created through Azure Resource Manager, so they still work.
- **Data-plane work needs network line of sight.** Writing secrets, uploading blobs, creating SQL users and deploying function or workflow code all go to private endpoints. Run those steps from inside the VNet, for example a self-hosted GitHub runner in the spoke, a VM reached through Bastion, or a deployment pipeline with VNet access.
- **SQL users.** The module sets an Entra ID group as server admin. To give an app's managed identity access, connect as that admin and run `CREATE USER [func-app1xxxx] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [func-app1xxxx];`.
- **Logic App storage keys.** Logic Apps Standard still requires an account key for its runtime storage. That's why the module gives it a dedicated account that's reachable only through private endpoints, rather than reusing a shared one.
