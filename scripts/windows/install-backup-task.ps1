#Requires -Version 7.4
[CmdletBinding()]
param([switch]$Help)
. "$PSScriptRoot/common.ps1"
if ($Help) {
    @'
Usage: ./scripts/windows/install-backup-task.ps1 [-Help]

Register a DISABLED daily 03:00 Windows task for the current user. No backups are
run and the task is not enabled. Export Compose selectors before installation.
Requires Windows, PowerShell 7.4+, and ScheduledTasks cmdlets. Docker Desktop must
run when the task executes. Interactive logon only; no password is stored.
'@
    exit 0
}
try {
    if (-not $IsWindows) { throw 'Task installation requires Windows; use the systemd installer on Linux.' }
    foreach ($name in @('Get-ScheduledTask', 'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger',
            'New-ScheduledTaskSettingsSet', 'New-ScheduledTaskPrincipal', 'New-ScheduledTask', 'Register-ScheduledTask')) {
        Assert-Command $name
    }
    $selectors = @{
        ProjectName = $env:COMPOSE_PROJECT_NAME
        EnvFiles = $env:COMPOSE_ENV_FILES
        ComposeFile = $env:COMPOSE_FILE
    }
    $identity = "$RepositoryRoot|$($selectors.ProjectName)|$($selectors.EnvFiles)|$($selectors.ComposeFile)"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity))).Substring(0, 16)
    $taskName = "Infrastructure-Backup-$hash"
    if (Get-ScheduledTask | Where-Object TaskName -eq $taskName) {
        throw "Task already exists; inspect it before reinstalling: $taskName"
    }
    $script = Join-Path $PSScriptRoot 'scheduled-backup.ps1'
    $arguments = "-NoProfile -NonInteractive -File `"$script`" -RetentionDays 7"
    foreach ($key in $selectors.Keys) {
        $value = $selectors[$key]
        if ($value) {
            if ($value -match '["\r\n]' -or $value.EndsWith('\')) {
                throw 'Compose selectors must not contain quotes/newlines or end in a backslash.'
            }
            $arguments += " -$key `"$value`""
        }
    }
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'pwsh.exe') -Argument $arguments -WorkingDirectory $RepositoryRoot
    $trigger = New-ScheduledTaskTrigger -Daily -At '03:00'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 35)
    $settings.Enabled = $false
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal
    Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
    Write-Status PASS "Installed disabled task: $taskName"
    Write-Status INFO "Inspect: Get-ScheduledTask -TaskName '$taskName'"
    Write-Status INFO "Enable explicitly: Enable-ScheduledTask -TaskName '$taskName'"
    Write-Status INFO "Disable: Disable-ScheduledTask -TaskName '$taskName'"
} catch {
    Write-Status FAIL $_.Exception.Message
    exit 1
}
