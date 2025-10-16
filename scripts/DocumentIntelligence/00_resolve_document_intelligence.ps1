[CmdletBinding()]
param(
    [string]$DocumentIntelligenceName = "",
    [string]$DocumentIntelligenceEndpoint = "",
    [string]$DocumentIntelligenceResourceGroup = ""
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/../SecurityModule.ps1"

function Write-Info([string]$message) {
    Write-Host "[docint-resolve] $message" -ForegroundColor Cyan
}

function Write-Warn([string]$message) {
    Write-Warning "[docint-resolve] $message"
}

function Get-AzdEnvValues {
    try {
        $values = @{}
        $raw = azd env get-values 2>$null
        foreach ($line in $raw) {
            if ($line -match '^([^=]+)=(.*)$') {
                $values[$Matches[1]] = $Matches[2].Trim('"')
            }
        }
        return $values
    } catch {
        Write-Warn "Unable to read azd environment values: $($_.Exception.Message)"
        return @{}
    }
}

try {
    $azdValues = Get-AzdEnvValues

    if (-not $DocumentIntelligenceName -and $env:DOCUMENT_INTELLIGENCE_NAME) {
        $DocumentIntelligenceName = $env:DOCUMENT_INTELLIGENCE_NAME
    }
    if (-not $DocumentIntelligenceName -and $azdValues.ContainsKey('documentIntelligenceName')) {
        $DocumentIntelligenceName = $azdValues['documentIntelligenceName']
    }
    if (-not $DocumentIntelligenceName -and $azdValues.ContainsKey('DOCUMENT_INTELLIGENCE_NAME')) {
        $DocumentIntelligenceName = $azdValues['DOCUMENT_INTELLIGENCE_NAME']
    }

    if (-not $DocumentIntelligenceResourceGroup -and $env:AZURE_RESOURCE_GROUP_NAME) {
        $DocumentIntelligenceResourceGroup = $env:AZURE_RESOURCE_GROUP_NAME
    }
    if (-not $DocumentIntelligenceResourceGroup -and $azdValues.ContainsKey('AZURE_RESOURCE_GROUP_NAME')) {
        $DocumentIntelligenceResourceGroup = $azdValues['AZURE_RESOURCE_GROUP_NAME']
    }
    if (-not $DocumentIntelligenceResourceGroup -and $azdValues.ContainsKey('resourceGroup')) {
        $DocumentIntelligenceResourceGroup = $azdValues['resourceGroup']
    }

    if (-not $DocumentIntelligenceEndpoint -and $env:DOCUMENT_INTELLIGENCE_ENDPOINT) {
        $DocumentIntelligenceEndpoint = $env:DOCUMENT_INTELLIGENCE_ENDPOINT
    }
    if (-not $DocumentIntelligenceEndpoint -and $azdValues.ContainsKey('documentIntelligenceEndpoint')) {
        $DocumentIntelligenceEndpoint = $azdValues['documentIntelligenceEndpoint']
    }

    if ([string]::IsNullOrWhiteSpace($DocumentIntelligenceName)) {
        Write-Info "Document Intelligence account not configured. Skipping resolution."
        Clear-SensitiveVariables -VariableNames @()
        exit 0
    }

    Write-Info "Resolving Document Intelligence account '$DocumentIntelligenceName'..."

    if ([string]::IsNullOrWhiteSpace($DocumentIntelligenceResourceGroup)) {
        Write-Warn "Resource group for Document Intelligence not provided; attempting discovery via Azure CLI."
        $accountInfo = az cognitiveservices account show --name $DocumentIntelligenceName --query "{resourceGroup:resourceGroup, endpoint:properties.endpoint}" -o json 2>$null | ConvertFrom-Json
    } else {
        $accountInfo = az cognitiveservices account show --name $DocumentIntelligenceName --resource-group $DocumentIntelligenceResourceGroup --query "{resourceGroup:resourceGroup, endpoint:properties.endpoint}" -o json 2>$null | ConvertFrom-Json
    }

    if ($accountInfo) {
        if (-not $DocumentIntelligenceResourceGroup) {
            $DocumentIntelligenceResourceGroup = $accountInfo.resourceGroup
        }
        if (-not $DocumentIntelligenceEndpoint) {
            $DocumentIntelligenceEndpoint = $accountInfo.endpoint
        }
    } else {
        Write-Warn "Unable to retrieve Document Intelligence account metadata via Azure CLI."
    }

    if ([string]::IsNullOrWhiteSpace($DocumentIntelligenceEndpoint)) {
        throw "Document Intelligence endpoint could not be resolved."
    }

    $envFile = '/tmp/document_intelligence.env'
    $lines = @(
        "DOCUMENT_INTELLIGENCE_NAME=$DocumentIntelligenceName",
        "DOCUMENT_INTELLIGENCE_ENDPOINT=$DocumentIntelligenceEndpoint",
        "DOCUMENT_INTELLIGENCE_RESOURCE_GROUP=$DocumentIntelligenceResourceGroup",
        "DOCUMENT_INTELLIGENCE_API_VERSION=2023-07-31"
    )
    $lines | Set-Content -Path $envFile

    # Export to current session for downstream scripts
    $env:DOCUMENT_INTELLIGENCE_NAME = $DocumentIntelligenceName
    $env:DOCUMENT_INTELLIGENCE_ENDPOINT = $DocumentIntelligenceEndpoint
    $env:DOCUMENT_INTELLIGENCE_RESOURCE_GROUP = $DocumentIntelligenceResourceGroup
    $env:DOCUMENT_INTELLIGENCE_API_VERSION = '2023-07-31'

    Write-Info "Document Intelligence endpoint: $DocumentIntelligenceEndpoint"
    Write-Info "Environment values persisted to $envFile"
}
catch {
    Write-Warn "Failed to resolve Document Intelligence configuration: $($_.Exception.Message)"
    throw
}
finally {
    Clear-SensitiveVariables -VariableNames @()
}
