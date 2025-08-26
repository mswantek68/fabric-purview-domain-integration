#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[fabric-scan-guide] $*"; }
warn(){ echo "[fabric-scan-guide][WARN] $*" >&2; }
info(){ echo "[fabric-scan-guide][INFO] $*" >&2; }
success(){ echo "[fabric-scan-guide] $*"; }
error(){ echo "[fabric-scan-guide][ERROR] $*" >&2; }
fail(){ echo "[fabric-scan-guide][ERROR] $*" >&2; exit 1; }

# Purpose: Provide guidance and setup for Fabric scan creation
# Atomic script - handles scan guidance and workspace discovery

PURVIEW_ACCOUNT_NAME=$(azd env get-value purviewAccountName)
FABRIC_WORKSPACE_NAME=$(azd env get-value desiredFabricWorkspaceName)
COLLECTION_NAME=$(azd env get-value desiredFabricDomainName)

# Load previous script outputs
COLLECTION_ID="${COLLECTION_NAME}"
FABRIC_DATASOURCE="fabric-powerbi-global"

if [[ -f /tmp/purview_collection.env ]]; then
  source /tmp/purview_collection.env
  COLLECTION_ID="${PURVIEW_COLLECTION_ID}"
fi

if [[ -f /tmp/fabric_datasource.env ]]; then
  source /tmp/fabric_datasource.env
  FABRIC_DATASOURCE="${FABRIC_DATASOURCE_NAME}"
fi

if [[ -z "${PURVIEW_ACCOUNT_NAME}" || -z "${FABRIC_WORKSPACE_NAME}" ]]; then
  fail "Missing required env values: purviewAccountName, desiredFabricWorkspaceName"
fi

echo "[fabric-scan-guide] Providing Fabric scan setup guidance"
echo "  • Account: $PURVIEW_ACCOUNT_NAME"
echo "  • Datasource: $FABRIC_DATASOURCE"
echo "  • Collection: $COLLECTION_ID"
echo "  • Target Workspace: $FABRIC_WORKSPACE_NAME"

# Try to discover Fabric workspace ID
log "Attempting to discover Fabric workspace ID..."
FABRIC_TOKEN=$(az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv 2>/dev/null || echo "")
FABRIC_WORKSPACE_ID="fabric-workspace-id-placeholder"

if [[ -n "${FABRIC_TOKEN}" ]]; then
  log "Looking up Fabric workspace '${FABRIC_WORKSPACE_NAME}'..."
  FABRIC_WORKSPACES=$(curl -s "https://api.powerbi.com/v1.0/myorg/groups" -H "Authorization: Bearer ${FABRIC_TOKEN}" 2>/dev/null || echo '{"value":[]}')
  DISCOVERED_WORKSPACE_ID=$(echo "${FABRIC_WORKSPACES}" | jq -r --arg name "${FABRIC_WORKSPACE_NAME}" '.value[] | select(.name == $name) | .id' | head -1)
  
  if [[ -n "${DISCOVERED_WORKSPACE_ID}" && "${DISCOVERED_WORKSPACE_ID}" != "null" ]]; then
    FABRIC_WORKSPACE_ID="${DISCOVERED_WORKSPACE_ID}"
    success "✅ Found Fabric workspace '${FABRIC_WORKSPACE_NAME}' (ID: ${FABRIC_WORKSPACE_ID})"
  else
    warn "Could not find Fabric workspace '${FABRIC_WORKSPACE_NAME}' via API"
  fi
else
  warn "Could not get Fabric API token for workspace discovery"
fi

# Generate scan guidance
SCAN_NAME="${COLLECTION_NAME}-fabric-scan"

echo ""
log "🔧 Manual Scan Setup Required"
echo ""
info "PowerBI/Fabric scans require authentication credentials to be configured."
info ""
info "📋 Scan Configuration Details:"
info "  • Scan Name: ${SCAN_NAME}"
info "  • Datasource: ${FABRIC_DATASOURCE}"
info "  • Target Collection: ${COLLECTION_ID}"
info "  • Target Workspace: ${FABRIC_WORKSPACE_NAME}"
if [[ "${FABRIC_WORKSPACE_ID}" != "fabric-workspace-id-placeholder" ]]; then
  info "  • Workspace ID: ${FABRIC_WORKSPACE_ID}"
fi
echo ""
info "🛠️ Setup Steps:"
info "1. Configure authentication credentials in Purview:"
info "   • Service Principal with PowerBI API permissions, OR"
info "   • Delegated authentication for Power BI admin users"
info ""
info "2. Create scan in Purview Data Map UI:"
info "   • Navigate to: Data Map > Sources > ${FABRIC_DATASOURCE}"
info "   • Click 'New Scan'"
info "   • Scan name: ${SCAN_NAME}"
info "   • Target collection: ${COLLECTION_ID}"
info "   • Select appropriate credentials"
info ""
info "3. Configure scan scope:"
info "   • Target workspace: ${FABRIC_WORKSPACE_NAME}"
if [[ "${FABRIC_WORKSPACE_ID}" != "fabric-workspace-id-placeholder" ]]; then
  info "   • Workspace ID: ${FABRIC_WORKSPACE_ID}"
fi
info ""
info "💡 Authentication Options:"
info "   • Service Principal: Requires Azure AD app registration + PowerBI permissions"
info "   • Delegated Auth: Requires Power BI admin user consent"
echo ""

# Export scan configuration for reference
cat > /tmp/fabric_scan_config.json << JSON
{
  "scanName": "${SCAN_NAME}",
  "datasourceName": "${FABRIC_DATASOURCE}",
  "collectionId": "${COLLECTION_ID}",
  "targetWorkspace": "${FABRIC_WORKSPACE_NAME}",
  "workspaceId": "${FABRIC_WORKSPACE_ID}",
  "purviewAccount": "${PURVIEW_ACCOUNT_NAME}"
}
JSON

success "✅ Scan configuration exported to /tmp/fabric_scan_config.json"
info ""
info "✅ Next Steps Summary:"
info "1. Set up PowerBI authentication credentials in Purview portal"
info "2. Create scan using the configuration details above"
info "3. Run scan to discover Fabric workspace assets"

exit 0
