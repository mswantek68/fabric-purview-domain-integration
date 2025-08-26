#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[fabric-datasource] $*"; }
warn(){ echo "[fabric-datasource][WARN] $*" >&2; }
info(){ echo "[fabric-datasource][INFO] $*" >&2; }
success(){ echo "[fabric-datasource] $*"; }
error(){ echo "[fabric-datasource][ERROR] $*" >&2; }
fail(){ echo "[fabric-datasource][ERROR] $*" >&2; exit 1; }

# Purpose: Register Fabric/PowerBI as a global datasource in Purview
# Atomic script - only handles datasource registration

PURVIEW_ACCOUNT_NAME=$(azd env get-value purviewAccountName)
COLLECTION_NAME=$(azd env get-value desiredFabricDomainName)

# Try to load collection info from previous script
if [[ -f /tmp/purview_collection.env ]]; then
  source /tmp/purview_collection.env
  COLLECTION_ID="${PURVIEW_COLLECTION_ID}"
else
  # Fallback - use collection name as ID
  COLLECTION_ID="${COLLECTION_NAME}"
fi

if [[ -z "${PURVIEW_ACCOUNT_NAME}" || -z "${COLLECTION_ID}" ]]; then
  fail "Missing required values: purviewAccountName and collection ID"
fi

echo "[fabric-datasource] Registering Fabric as global datasource"
echo "  • Account: $PURVIEW_ACCOUNT_NAME"
echo "  • Target Collection: $COLLECTION_ID"

# Get Purview token
log "Acquiring Purview access token..."
PURVIEW_TOKEN=$(az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>/dev/null || az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv)
if [[ -z "${PURVIEW_TOKEN}" ]]; then
  fail "Failed to acquire Purview access token"
fi

ENDPOINT="https://${PURVIEW_ACCOUNT_NAME}.purview.azure.com"

# Check if Fabric datasource already exists
log "Checking for existing Fabric datasources..."
EXISTING_DATASOURCES=$(curl -s "${ENDPOINT}/scan/datasources?api-version=2022-07-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}" 2>/dev/null || echo '{"value":[]}')
FABRIC_DATASOURCE=$(echo "${EXISTING_DATASOURCES}" | jq -r '.value[] | select(.kind == "PowerBI") | .name' | head -1)

if [[ -n "${FABRIC_DATASOURCE}" && "${FABRIC_DATASOURCE}" != "null" ]]; then
  success "✅ Fabric datasource already registered: ${FABRIC_DATASOURCE}"
else
  log "Registering new Fabric datasource..."
  
  DATASOURCE_NAME="Fabric"
  DATASOURCE_PAYLOAD=$(cat << JSON
{
  "kind": "PowerBI",
  "name": "${DATASOURCE_NAME}",
  "properties": {
    "tenant": "$(az account show --query tenantId -o tsv)",
    "collection": {
      "type": "CollectionReference",
      "referenceName": "${COLLECTION_ID}"
    }
  }
}
JSON
)

  HTTP_DS=$(curl -s -w "%{http_code}" -o /tmp/datasource_create.json -X PUT "${ENDPOINT}/scan/datasources/${DATASOURCE_NAME}?api-version=2022-07-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}" -H "Content-Type: application/json" -d "${DATASOURCE_PAYLOAD}")
  
  if [[ "${HTTP_DS}" =~ ^20[0-9]$ ]]; then
    success "✅ Fabric datasource '${DATASOURCE_NAME}' registered successfully"
    FABRIC_DATASOURCE="${DATASOURCE_NAME}"
  else
    error "Fabric datasource registration failed (HTTP ${HTTP_DS})"
    cat /tmp/datasource_create.json 2>/dev/null || true
    fail "Could not register datasource"
  fi
fi

success "✅ Fabric datasource registration completed"
info ""
info "📋 Datasource Details:"
info "  • Name: ${FABRIC_DATASOURCE}"
info "  • Type: PowerBI/Fabric"
info "  • Collection: ${COLLECTION_ID}"

# Export for other scripts to use
echo "FABRIC_DATASOURCE_NAME=${FABRIC_DATASOURCE}" > /tmp/fabric_datasource.env
echo "FABRIC_COLLECTION_ID=${COLLECTION_ID}" >> /tmp/fabric_datasource.env

exit 0
