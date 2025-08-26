#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[purview-scan] $*"; }
warn(){ echo "[purview-scan][WARN] $*" >&2; }
fail(){ echo "[purview-scan][ERROR] $*" >&2; exit 1; }

# Purpose: create/update a Purview scan on the Fabric datasource and scope it to a Fabric workspace, then trigger and poll the run
# Usage: ./trigger_purview_scan_for_fabric_workspace.sh [<workspace-id>]
# If no arg provided the script will look for /tmp/fabric_workspace.env and /tmp/fabric_datasource.env

PURVIEW_ACCOUNT_NAME=$(azd env get-value purviewAccountName 2>/dev/null || true)
if [[ -z "${PURVIEW_ACCOUNT_NAME}" ]]; then
  fail "purviewAccountName not found in azd env. Set azd env or pass PURVIEW_ACCOUNT_NAME environment variable."
fi

# Load datasource info if available
if [[ -f /tmp/fabric_datasource.env ]]; then
  # shellcheck disable=SC1090
  source /tmp/fabric_datasource.env || true
fi
DATASOURCE_NAME="${FABRIC_DATASOURCE_NAME:-Fabric}"

# Determine workspace id (arg > /tmp file)
if [[ -n "${1-}" ]]; then
  WORKSPACE_ID="$1"
else
  if [[ -f /tmp/fabric_workspace.env ]]; then
    # shellcheck disable=SC1090
    source /tmp/fabric_workspace.env || true
  fi
  WORKSPACE_ID="${FABRIC_WORKSPACE_ID:-}"
fi

if [[ -z "${WORKSPACE_ID}" ]]; then
  fail "Fabric workspace id not provided as first arg and not found in /tmp/fabric_workspace.env"
fi

# Acquire Purview token
log "Acquiring Purview access token..."
PURVIEW_TOKEN=$(az account get-access-token --resource https://purview.azure.net --query accessToken -o tsv 2>/dev/null || az account get-access-token --resource https://purview.azure.com --query accessToken -o tsv)
if [[ -z "${PURVIEW_TOKEN}" ]]; then
  fail "Failed to acquire Purview access token"
fi

ENDPOINT="https://${PURVIEW_ACCOUNT_NAME}.purview.azure.com"
SCAN_NAME="scan-workspace-${WORKSPACE_ID}"

# Verify jq exists for JSON parsing (used for run polling)
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found; script will still attempt to create/run the scan but will not parse JSON responses cleanly. Install jq for better output."
fi

log "Creating/Updating scan '${SCAN_NAME}' for datasource '${DATASOURCE_NAME}' targeting workspace '${WORKSPACE_ID}'"

SCAN_PAYLOAD=$(cat <<JSON
{
  "properties": {
    "scanRulesetName": "Default",
    "scanScope": {
      "type": "PowerBIScanScope",
      "workspaces": [
        { "id": "${WORKSPACE_ID}" }
      ]
    }
  }
}
JSON
)

HTTP_CREATE=$(curl -s -w "%{http_code}" -o /tmp/scan_create.json -X PUT "${ENDPOINT}/scan/datasources/${DATASOURCE_NAME}/scans/${SCAN_NAME}?api-version=2022-07-01-preview" \
  -H "Authorization: Bearer ${PURVIEW_TOKEN}" -H "Content-Type: application/json" -d "${SCAN_PAYLOAD}")

if [[ "${HTTP_CREATE}" =~ ^20[0-9]$ ]]; then
  log "Scan definition created/updated (HTTP ${HTTP_CREATE})"
else
  error_body=$(cat /tmp/scan_create.json 2>/dev/null || true)
  warn "Scan create/update failed (HTTP ${HTTP_CREATE}): ${error_body}"
  fail "Could not create/update scan"
fi

log "Triggering scan run..."
RUN_RESP=$(curl -s -w "\n%{http_code}" -X POST "${ENDPOINT}/scan/datasources/${DATASOURCE_NAME}/scans/${SCAN_NAME}/run?api-version=2022-07-01-preview" \
  -H "Authorization: Bearer ${PURVIEW_TOKEN}" -H "Content-Type: application/json" -d "{}")

RUN_BODY=$(echo "${RUN_RESP}" | head -n -1)
RUN_CODE=$(echo "${RUN_RESP}" | tail -n1)

if [[ "${RUN_CODE}" != "200" && "${RUN_CODE}" != "202" ]]; then
  echo "${RUN_BODY}"
  fail "Scan run request failed (HTTP ${RUN_CODE})"
fi

# Try to extract run id (best-effort)
if command -v jq >/dev/null 2>&1; then
  RUN_ID=$(echo "${RUN_BODY}" | jq -r '.runId // .id // empty' 2>/dev/null || true)
else
  RUN_ID=""
fi

if [[ -z "${RUN_ID}" ]]; then
  log "Scan run invoked but no run id returned. Monitor the run in Purview portal or inspect the response:" 
  echo "${RUN_BODY}"
  exit 0
fi

log "Scan run started: ${RUN_ID} — polling status..."

while true; do
  SJSON=$(curl -s -H "Authorization: Bearer ${PURVIEW_TOKEN}" "${ENDPOINT}/scan/datasources/${DATASOURCE_NAME}/scans/${SCAN_NAME}/runs/${RUN_ID}?api-version=2022-07-01-preview")
  if command -v jq >/dev/null 2>&1; then
    STATUS=$(echo "${SJSON}" | jq -r '.status // .runStatus // empty' 2>/dev/null || true)
  else
    STATUS=""
  fi

  log "Status: ${STATUS}"
  if [[ "${STATUS}" == "Succeeded" || "${STATUS}" == "Failed" || "${STATUS}" == "Cancelled" ]]; then
    log "Scan finished with status: ${STATUS}"
    echo "${SJSON}" > /tmp/scan_run_${RUN_ID}.json
    break
  fi
  sleep 5
done

log "Done. Run output saved to /tmp/scan_run_${RUN_ID}.json"
exit 0
