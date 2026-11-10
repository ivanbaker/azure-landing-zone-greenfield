#!/usr/bin/env bash
# One-time bootstrap for the landing zone pipeline. Run it from Azure Cloud Shell
# or any machine with the Azure CLI, signed in as a user who can:
#   - create resources in the management subscription, and
#   - assign roles at the Tenant Root Group (Owner there, or a Global Administrator
#     who has turned on "Access management for Azure resources").
#
# It creates:
#   1. A storage account for Terraform remote state (Entra ID auth only, versioned).
#   2. An Entra ID app registration that GitHub Actions signs in as, using OpenID
#      Connect federated credentials. No client secret is created or stored.
#   3. Role assignments for that identity.
#
# Usage:
#   ./bootstrap.sh <github-owner>/<repo-name> <management-sub-id> [connectivity-sub-id] [workload-sub-id]
#
# Set LOCATION to change the region of the state storage account (default eastus2).

set -euo pipefail

USAGE="Usage: $0 <github-owner>/<repo-name> <management-sub-id> [connectivity-sub-id] [workload-sub-id]"
REPO="${1:?$USAGE}"
SUBSCRIPTION_ID="${2:?$USAGE}"
CONNECTIVITY_SUBSCRIPTION_ID="${3:-$SUBSCRIPTION_ID}"
WORKLOAD_SUBSCRIPTION_ID="${4:-}"
LOCATION="${LOCATION:-eastus2}"

STATE_RG="rg-tfstate"
STATE_CONTAINER="tfstate"
APP_NAME="gh-${REPO//\//-}-landing-zone"
SUFFIX="$(echo -n "$REPO$SUBSCRIPTION_ID" | sha1sum | cut -c1-8)"
STORAGE_ACCOUNT="sttfstate${SUFFIX}"

az account set --subscription "$SUBSCRIPTION_ID"
TENANT_ID="$(az account show --query tenantId -o tsv)"

echo "==> Registering resource providers used by the platform subscriptions"
# (The workload subscription's providers are registered by Terraform.)
for sub in $(printf '%s\n' "$SUBSCRIPTION_ID" "$CONNECTIVITY_SUBSCRIPTION_ID" | sort -u); do
  for rp in Microsoft.Storage Microsoft.Network Microsoft.OperationalInsights Microsoft.Insights \
            Microsoft.ManagedIdentity Microsoft.Management Microsoft.PolicyInsights Microsoft.Security \
            Microsoft.OperationsManagement Microsoft.SecurityInsights Microsoft.Compute; do
    az provider register --subscription "$sub" --namespace "$rp" --output none
  done
done

echo "==> Creating Terraform state storage: $STORAGE_ACCOUNT"
az group create --name "$STATE_RG" --location "$LOCATION" --tags managed_by=bootstrap --output none
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --https-only true \
  --output none
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 \
  --output none

STORAGE_ID="$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$STATE_RG" --query id -o tsv)"
CURRENT_USER_ID="$(az ad signed-in-user show --query id -o tsv)"

# The signed-in user needs data-plane access to create the container (shared keys are disabled).
az role assignment create --assignee-object-id "$CURRENT_USER_ID" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" --output none || true
echo "    Waiting 60s for role assignment to propagate..."
sleep 60
az storage container create --name "$STATE_CONTAINER" --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login --output none

echo "==> Creating Entra ID app registration: $APP_NAME"
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
fi
SP_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)"
if [[ -z "$SP_ID" ]]; then
  SP_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
fi

echo "==> Adding GitHub OIDC federated credentials"
add_federated_credential() {
  local name="$1" subject="$2"
  if ! az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name']" -o tsv | grep -q .; then
    az ad app federated-credential create --id "$APP_ID" --parameters "{
      \"name\": \"$name\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$subject\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }" --output none
  fi
}
add_federated_credential "github-pull-request" "repo:${REPO}:pull_request"
add_federated_credential "github-main"         "repo:${REPO}:ref:refs/heads/main"
add_federated_credential "github-env-production" "repo:${REPO}:environment:production"

echo "==> Assigning roles to the pipeline identity"
# Owner at the Tenant Root Group: needed to create management groups, assign
# policies and grant the policy managed identities their roles.
# For production, replace with narrower custom roles (see docs/design-decisions.md).
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Owner" --scope "/providers/Microsoft.Management/managementGroups/${TENANT_ID}" --output none
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$STORAGE_ID" --output none

cat <<EOF

Bootstrap complete. Add these to GitHub: Settings > Secrets and variables > Actions > Variables

  AZURE_CLIENT_ID        = $APP_ID
  AZURE_TENANT_ID        = $TENANT_ID
  AZURE_SUBSCRIPTION_ID  = $SUBSCRIPTION_ID
  TF_STATE_RESOURCE_GROUP  = $STATE_RG
  TF_STATE_STORAGE_ACCOUNT = $STORAGE_ACCOUNT
  TF_STATE_CONTAINER       = $STATE_CONTAINER
  SUBSCRIPTION_IDS       = {"management":"$SUBSCRIPTION_ID","connectivity":"$CONNECTIVITY_SUBSCRIPTION_ID","workload":"${WORKLOAD_SUBSCRIPTION_ID:-<id>}"}
  SECURITY_CONTACT_EMAIL = <your email>

Then create an environment named "production" (Settings > Environments) and add
yourself as a required reviewer so every apply waits for your approval.
EOF

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  read -r -p "GitHub CLI detected. Set the first six variables on $REPO now? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    gh variable set AZURE_CLIENT_ID          --repo "$REPO" --body "$APP_ID"
    gh variable set AZURE_TENANT_ID          --repo "$REPO" --body "$TENANT_ID"
    gh variable set AZURE_SUBSCRIPTION_ID    --repo "$REPO" --body "$SUBSCRIPTION_ID"
    gh variable set TF_STATE_RESOURCE_GROUP  --repo "$REPO" --body "$STATE_RG"
    gh variable set TF_STATE_STORAGE_ACCOUNT --repo "$REPO" --body "$STORAGE_ACCOUNT"
    gh variable set TF_STATE_CONTAINER       --repo "$REPO" --body "$STATE_CONTAINER"
    echo "Done. Set SUBSCRIPTION_IDS and SECURITY_CONTACT_EMAIL yourself."
  fi
fi
