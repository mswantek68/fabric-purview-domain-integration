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
  COLLECTION_ID="${PURVIEW_COLLECTION_ID:-${COLLECTION_NAME:-}}"
else
  COLLECTION_ID="${COLLECTION_NAME:-}"
fi

if [[ -z "${PURVIEW_ACCOUNT_NAME}" ]]; then
  fail "Missing required value: purviewAccountName"
fi

# Allow registering at account root (default domain) by leaving desiredFabricDomainName empty
# You can force registration into the default domain by setting desiredFabricDomainName to empty, '-' or 'default'/'root'
REGISTER_IN_DEFAULT=false
if [[ -z "${COLLECTION_ID}" || "${COLLECTION_ID}" == "-" || "${COLLECTION_ID,,}" == "default" || "${COLLECTION_ID,,}" == "root" ]]; then
  REGISTER_IN_DEFAULT=true
fi

if [[ "${REGISTER_IN_DEFAULT}" == "true" ]]; then
  echo "[fabric-datasource] Registering Fabric as global datasource in Purview account root (default domain)"
  echo "  • Account: $PURVIEW_ACCOUNT_NAME"
  echo "  • Target Collection: (default/domain root)"
else
  echo "[fabric-datasource] Registering Fabric as global datasource"
  echo "  • Account: $PURVIEW_ACCOUNT_NAME"
  echo "  • Target Collection: $COLLECTION_ID"
fi

# Get Purview token
log "Acquiring Purview access token..."
PURVIEW_TOKEN=$(az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>/dev/null || az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv)
if [[ -z "${PURVIEW_TOKEN}" ]]; then
  fail "Failed to acquire Purview access token"
fi

ENDPOINT="https://${PURVIEW_ACCOUNT_NAME}.purview.azure.com"

# Check for existing PowerBI/Fabric datasources and decide action:
log "Checking for existing Fabric (PowerBI) datasources..."
EXISTING_DATASOURCES=$(curl -s "${ENDPOINT}/scan/datasources?api-version=2022-07-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}" 2>/dev/null || echo '{"value":[]}')

# Prefer a datasource already registered at account root (no collection property)
FABRIC_AT_ROOT=$(echo "${EXISTING_DATASOURCES}" | jq -r '.value[] | select(.kind=="PowerBI" and ( .properties.collection == null or (.properties.collection? | length == 0) )) | .name' | head -1)
if [[ -n "${FABRIC_AT_ROOT}" && "${FABRIC_AT_ROOT}" != "null" ]]; then
  FABRIC_DATASOURCE="${FABRIC_AT_ROOT}"
  REGISTER_IN_DEFAULT=true
  success "✅ Found existing Fabric datasource registered at account root: ${FABRIC_DATASOURCE}"
else
  # No root-level Fabric datasource exists. Create one only if there are no PowerBI datasources at all.
  ANY_PBI_EXISTS=$(echo "${EXISTING_DATASOURCES}" | jq -r '.value[] | select(.kind=="PowerBI") | .name' | head -1)
  if [[ -n "${ANY_PBI_EXISTS}" && "${ANY_PBI_EXISTS}" != "null" ]]; then
    warn "Found existing PowerBI datasource '${ANY_PBI_EXISTS}' registered under a collection and no root-level Fabric datasource exists."
    warn "To avoid overwriting or moving that datasource, this script will NOT create a new root-level datasource."
    warn "If you want Fabric at the account root, please remove or rename the existing datasource and re-run."

    # Use the existing datasource for downstream actions (scan creation will operate against this datasource)
    FABRIC_DATASOURCE="${ANY_PBI_EXISTS}"
    # try to read its collection reference (if any)
    DS_DETAIL=$(curl -s "${ENDPOINT}/scan/datasources/${FABRIC_DATASOURCE}?api-version=2022-07-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}" 2>/dev/null || echo '{}')
    EXISTING_COLLECTION_REF=$(echo "${DS_DETAIL}" | jq -r '.properties.collection.referenceName // empty' 2>/dev/null || true)
    if [[ -z "${EXISTING_COLLECTION_REF}" ]]; then
      REGISTER_IN_DEFAULT=true
    else
      REGISTER_IN_DEFAULT=false
      COLLECTION_ID="${EXISTING_COLLECTION_REF}"
    fi
  else
    # No PowerBI datasource exists anywhere -> register Fabric at account root
    log "No existing PowerBI datasource found — registering Fabric at account root"
    DATASOURCE_NAME="Fabric"
    DATASOURCE_PAYLOAD=$(cat << JSON
{
  "kind": "PowerBI",
  "name": "${DATASOURCE_NAME}",
  "properties": {
    "tenant": "$(az account show --query tenantId -o tsv)"
  }
}
JSON
)

    HTTP_DS=$(curl -s -w "%{http_code}" -o /tmp/datasource_create.json -X PUT "${ENDPOINT}/scan/datasources/${DATASOURCE_NAME}?api-version=2022-07-01-preview" -H "Authorization: Bearer ${PURVIEW_TOKEN}" -H "Content-Type: application/json" -d "${DATASOURCE_PAYLOAD}")

    if [[ "${HTTP_DS}" =~ ^20[0-9]$ ]]; then
      success "✅ Fabric datasource '${DATASOURCE_NAME}' registered successfully at account root"
      FABRIC_DATASOURCE="${DATASOURCE_NAME}"
      REGISTER_IN_DEFAULT=true
    else
      error "Fabric datasource registration failed (HTTP ${HTTP_DS})"
      cat /tmp/datasource_create.json 2>/dev/null || true
      fail "Could not register datasource"
    fi
  fi
fi

success "✅ Fabric datasource registration completed"
info ""
info "📋 Datasource Details:"
info "  • Name: ${FABRIC_DATASOURCE}"
info "  • Type: PowerBI/Fabric"
if [[ "${REGISTER_IN_DEFAULT}" == "true" ]]; then
  info "  • Collection: (default/domain root)"
else
  info "  • Collection: ${COLLECTION_ID}"
fi

# Export for other scripts to use
if [[ "${REGISTER_IN_DEFAULT}" == "true" ]]; then
  echo "FABRIC_DATASOURCE_NAME=${FABRIC_DATASOURCE}" > /tmp/fabric_datasource.env
  echo "FABRIC_COLLECTION_ID=" >> /tmp/fabric_datasource.env
else
  echo "FABRIC_DATASOURCE_NAME=${FABRIC_DATASOURCE}" > /tmp/fabric_datasource.env
  echo "FABRIC_COLLECTION_ID=${COLLECTION_ID}" >> /tmp/fabric_datasource.env
fi

exit 0
