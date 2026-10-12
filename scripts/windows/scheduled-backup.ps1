#Requires -Version 7.4
[CmdletBinding()]
param(
    [int]$RetentionDays = 7,
    [string]$ProjectName,
    [string]$EnvFiles,
    [string]$ComposeFile,
    [switch]$Help
)
. "$PSScriptRoot/common.ps1"
if ($Help) {
    @'
Usage: ./scripts/windows/scheduled-backup.ps1 [-RetentionDays 1..9999] [-Help]
Optional selectors: -ProjectName NAME -EnvFiles PATHS -ComposeFile PATHS

All three databases must already run. Completed owned backups are pruned only
after all dumps succeed. Default retention: seven days. Redis is not backed up.
Requires PowerShell 7.4+ and Docker Desktop Linux containers.
'@
    exit 0
}
$previous = @{
    COMPOSE_PROJECT_NAME = $env:COMPOSE_PROJECT_NAME
    COMPOSE_ENV_FILES = $env:COMPOSE_ENV_FILES
    COMPOSE_FILE = $env:COMPOSE_FILE
}
try {
    if ($ProjectName) { $env:COMPOSE_PROJECT_NAME = $ProjectName }
    if ($EnvFiles) { $env:COMPOSE_ENV_FILES = $EnvFiles }
    if ($ComposeFile) { $env:COMPOSE_FILE = $ComposeFile }
    Invoke-ScheduledDatabaseBackup -RetentionDays $RetentionDays
} catch {
    Write-Status FAIL "Scheduled backup failed: $($_.Exception.Message) Retention cleanup was not completed."
    exit 1
} finally {
    foreach ($key in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
    }
}
