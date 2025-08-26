<#
.SYNOPSIS
  Ensure scripts/*.sh are executable on Unix-like systems.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){ Write-Host "[perm-fix] $m" }

$changed = 0
Get-ChildItem -Path scripts -Filter '*.sh' -File | ForEach-Object {
  $f = $_.FullName
  try {
    # On Windows, do nothing; on Linux/macOS set +x bits
    if ($IsWindows) { Log "Skipping chmod on Windows: $f" } else { 
      chmod +x $f 2>$null
      Log "Added +x to $f"
      $changed++
    }
  } catch { Log "Could not modify $f: $_" }
}
Log "Completed. Files updated: $changed"
exit 0
