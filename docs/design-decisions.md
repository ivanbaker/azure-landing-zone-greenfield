# Design decisions

Short records of the main choices in this repo and why they were made.

### 1. Azure Verified Modules instead of `caf-enterprise-scale` or hand-written resources
Microsoft archived the `caf-enterprise-scale` Terraform module in 2026. The [AVM pattern modules](https://azure.github.io/Azure-Landing-Zones/terraform/) are now the supported way to build ALZ in Terraform. Hand-writing more than 120 policy assignments and their role assignments would be slower and drift from Microsoft's reference. Using the modules keeps this repo focused on configuration and composition.

### 2. One root module, not one per layer
Governance, management, connectivity and the workload spoke share a single state file. That fits a single-team lab. It keeps cross-layer references simple; for example, policy parameters point at the workspace and the spoke peers to the hub. For a real organization I'd split it into platform and application-landing-zone states with separate pipelines and identities, because the two change at different rates and have different owners.

### 3. Policy parameters built from names, not resource outputs
The ALZ provider has to resolve policy assignments at plan time. If a parameter were a resource ID known only after apply, the first plan would fail. Workspace, identity and DCR IDs are therefore assembled from deterministic names in `locals.tf`. `policy_assignments_dependencies` makes sure the assignments are still created after those resources exist.

### 4. Switched-off features set policies to audit rather than removing them
When DDoS protection or private DNS zones are disabled, the related policies are set to `DoNotEnforce`. Removing them would hide the gap. Audit mode keeps it on the compliance dashboard, which is the honest state for a lab.

### 5. Cost-aware defaults
A full production hub (Firewall Premium, DDoS Network Protection, gateways, Bastion, DNS resolver) costs more than $5,000 a month. The defaults use Firewall Basic and leave the expensive options off, so the whole design can be deployed for a few hundred dollars a month and destroyed afterward. Each option is one boolean in `landing-zone.tfvars`.

### 6. Existing subscriptions rather than creating them
Creating subscriptions through the API needs an Enterprise Agreement or Microsoft Customer Agreement billing scope. Most labs don't have one. The vending module is used with `subscription_alias_enabled = false`, so it manages placement, networking, RBAC and budget for a subscription that already exists. Switching to creating subscriptions means setting that flag, a billing scope and a display name.

### 7. OIDC federation for the pipeline
There's no client secret to leak or rotate. The federated credentials are limited to specific subjects (`main`, pull requests, the `production` environment), so a fork or another branch can't sign in.

### 8. Owner at the Tenant Root Group for the pipeline identity (known trade-off)
Creating management groups, assigning policies and granting the policies' managed identities their roles needs broad rights. Owner at the root is the simplest grant that works, and it's what the Microsoft accelerator starts with. In production I'd split the work across two identities with custom roles: a plan identity with Reader, and an apply identity with only the management group, policy and role-assignment-write permissions it needs. That's on the roadmap.

### 9. Saved plan and lock file applied as a pair
The apply job downloads the plan file and the `.terraform.lock.hcl` produced by the plan job. That guarantees the reviewer approved exactly what is applied. It also prevents a provider upgrade between plan and apply.
