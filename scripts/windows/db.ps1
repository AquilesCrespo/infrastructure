#Requires -Version 7.4
[CmdletBinding()]
param([string]$Action, [string]$Service, [string]$File, [switch]$Confirm, [switch]$Help)
. "$PSScriptRoot/common.ps1"
if ($Help) {
    @'
Usage: ./scripts/windows/db.ps1 backup|restore|seed mysql|postgres|mongodb|all [-File PATH] [-Confirm]
       ./scripts/windows/db.ps1 -Help

Examples:
  ./scripts/windows/db.ps1 backup postgres -File backups/postgres.dump
  ./scripts/windows/db.ps1 restore postgres -File backups/postgres.dump -Confirm
  ./scripts/windows/db.ps1 seed all

Restore modifies data and requires -Confirm. Stop application writes and back up
first. Use trusted files only. Redis is not managed. Requires PowerShell 7.4+
and Docker Desktop Linux containers. Set NO_COLOR to disable terminal colors.
'@
    exit 0
}
try {
    Invoke-DatabaseWorkflow -Action $Action -Service $Service -File $File -Confirmed $Confirm.IsPresent
} catch {
    Write-Status FAIL $_.Exception.Message
    exit 1
}
