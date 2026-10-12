#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/windows/common.ps1"
$root = $RepositoryRoot
$work = Join-Path ([IO.Path]::GetTempPath()) "infrastructure-powershell-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($work) | Out-Null
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Expect-Failure {
    param([scriptblock]$Operation, [string]$Pattern)
    $failed = $false
    try { & $Operation } catch {
        $failed = $true
        Assert ($_.Exception.Message -match $Pattern) "Expected failure matching '$Pattern', got $($_.Exception.Message)"
    }
    Assert $failed "Expected failure: $Pattern"
}
try {
    foreach ($file in Get-ChildItem "$root/scripts/windows/*.ps1") {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        Assert ($errors.Count -eq 0) "Parse $($file.Name)"
        if ($file.Name -ne 'common.ps1') {
            $help = Invoke-NativeProcess $pwsh @('-NoProfile', '-File', $file.FullName, '-Help')
            Assert ($help -match 'Usage:') "Help for $($file.Name)"
        }
    }
    $data = [byte[]]::new(131072)
    for ($i = 0; $i -lt $data.Length; $i++) { $data[$i] = $i % 256 }
    $inputPath = Join-Path $work 'input.bin'
    $outputPath = Join-Path $work 'output.bin'
    [IO.File]::WriteAllBytes($inputPath, $data)
    $output = New-PrivateFile $outputPath
    try {
        Invoke-NativeProcess $pwsh @('-NoProfile', '-Command',
            '[Console]::OpenStandardInput().CopyTo([Console]::OpenStandardOutput())') `
            -InputFile $inputPath -OutputStream $output
    } finally { $output.Dispose() }
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($outputPath)) -eq [Convert]::ToBase64String($data)) 'Binary data round trip'
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $outputPath
        Assert $acl.AreAccessRulesProtected 'Private backup ACL inheritance disabled'
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        Assert ($rules.Count -eq 1 -and $rules[0].IdentityReference.Value -eq $sid) 'Only current user can access backup'
    } else {
        Assert ([IO.File]::GetUnixFileMode($outputPath) -eq ([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite)) 'Private backup mode'
    }
    Expect-Failure { Invoke-NativeProcess $pwsh @('-NoProfile', '-Command', '[Console]::Error.WriteLine("PRIVATE_CREDENTIAL"); exit 37') } 'exit 37'
    Expect-Failure { Invoke-NativeProcess $pwsh @('-NoProfile', '-Command', 'Start-Sleep 10') -TimeoutSeconds 1 } 'timed out'
    $argumentProbe = Join-Path $work 'arguments.ps1'
    [IO.File]::WriteAllText($argumentProbe, 'param([string]$Value) [Console]::Write($Value)')
    $quoted = Invoke-NativeProcess $pwsh @('-NoProfile', '-File', $argumentProbe, 'path with spaces')
    Assert ($quoted -eq 'path with spaces') 'Argument boundaries'

    function Assert-Command { param([string]$Name) }
    $script:failDump = $false
    $script:emptyDump = $false
    $script:calls = [Collections.Generic.List[object]]::new()
    function Invoke-Compose {
        param([string[]]$Arguments, [string]$InputFile, [IO.Stream]$OutputStream, [int]$TimeoutSeconds)
        $script:calls.Add($Arguments)
        if ($Arguments[0] -eq 'config') { return '{"name":"test-project"}' }
        if ($script:failDump -and $Arguments[2] -eq 'postgres') { throw 'Test dump failure' }
        if ($OutputStream -and -not $script:emptyDump) { $OutputStream.Write($data, 0, $data.Length) }
        if ($InputFile) { Assert ([IO.File]::Exists($InputFile)) 'Input exists' }
    }
    $backup = Join-Path $work 'backup.dump'
    Invoke-DatabaseWorkflow backup postgres $backup
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -eq [Convert]::ToBase64String($data)) 'Binary backup publication'
    Expect-Failure { Invoke-DatabaseWorkflow backup postgres $backup } 'already exists'
    Expect-Failure { Invoke-DatabaseWorkflow restore postgres $backup } 'requires -Confirm'
    Invoke-DatabaseWorkflow restore postgres $backup $true
    Invoke-DatabaseWorkflow seed all
    $script:failDump = $true
    $failedPath = Join-Path $work 'failed.dump'
    Expect-Failure { Invoke-DatabaseWorkflow backup postgres $failedPath } 'Test dump failure'
    Assert (-not (Test-Path -LiteralPath $failedPath)) 'No failed backup published'
    Assert (@(Get-ChildItem $work -Filter '*.partial.*').Count -eq 0) 'Failed partial files cleaned'
    $script:failDump = $false
    $script:emptyDump = $true
    Expect-Failure { Invoke-DatabaseWorkflow backup postgres $failedPath } 'empty'
    $script:emptyDump = $false
    $RepositoryRoot = $work
    $directory = Join-Path $work 'backups/scheduled/test-project'
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $old = Join-Path $directory 'scheduled-20000101T000000Z-1-mysql.sql'
    $manual = Join-Path $directory 'manual.sql'
    $partial = "$old.partial.keep"
    foreach ($file in @($old, $manual, $partial)) {
        [IO.File]::WriteAllText($file, 'keep')
        [IO.File]::SetLastWriteTimeUtc($file, [DateTime]::UtcNow.AddDays(-8))
    }
    $script:failDump = $true
    Expect-Failure { Invoke-ScheduledDatabaseBackup } 'Test dump failure'
    Assert (Test-Path -LiteralPath $old) 'Retention skipped after failed batch'
    $script:failDump = $false
    Start-Sleep -Seconds 1
    Invoke-ScheduledDatabaseBackup
    Assert (-not (Test-Path -LiteralPath $old)) 'Expired owned file removed'
    Assert ((Test-Path -LiteralPath $manual) -and (Test-Path -LiteralPath $partial)) 'Manual/partial files retained'
    $lock = [IO.File]::Open((Join-Path $directory '.windows.lock'), 'Open', 'ReadWrite', 'None')
    try { Expect-Failure { Invoke-ScheduledDatabaseBackup } 'backup lock' } finally { $lock.Dispose() }
    Expect-Failure { Invoke-ScheduledDatabaseBackup 0 } 'Retention'
    $link = Join-Path $work 'link'
    if (-not $IsWindows) {
        New-Item -ItemType SymbolicLink -Path $link -Target $directory | Out-Null
    } else {
        New-Item -ItemType Junction -Path $link -Target $directory | Out-Null
    }
    Expect-Failure { Assert-NoReparsePoint $link } 'symlink or junction'
    Remove-Item -LiteralPath $link -Force
    $registrationState = @{ Task = $null; Name = $null }
    function Register-ScheduledTask {
        param($TaskName, $InputObject)
        $registrationState.Task = $InputObject
        $registrationState.Name = $TaskName
    }
    $registrationProbe = Join-Path $work 'registration.ps1'
    [IO.File]::WriteAllText($registrationProbe,
        'Register-ScheduledTask -TaskName scope-probe -InputObject ([pscustomobject]@{ Settings = @{ Enabled = $false } })')
    & $registrationProbe
    Assert ($null -ne $registrationState.Task) 'Task registration visible across script scopes'
    Assert ($registrationState.Name -eq 'scope-probe') 'Registered task name visible across script scopes'
    Assert (-not $registrationState.Task.Settings.Enabled) 'Registered task settings visible across script scopes'
    if ($IsWindows) {
        $registrationState.Task = $null
        $registrationState.Name = $null
        function Get-ScheduledTask { return @() }
        function New-ScheduledTaskAction {
            param($Execute, $Argument, $WorkingDirectory)
            [pscustomobject]@{ Execute = $Execute; Argument = $Argument; WorkingDirectory = $WorkingDirectory }
        }
        function New-ScheduledTaskTrigger { param([switch]$Daily, $At) [pscustomobject]@{ At = $At } }
        function New-ScheduledTaskSettingsSet {
            param([switch]$StartWhenAvailable, $MultipleInstances, $ExecutionTimeLimit)
            [pscustomobject]@{ Enabled = $true; ExecutionTimeLimit = $ExecutionTimeLimit }
        }
        function New-ScheduledTaskPrincipal {
            param($UserId, $LogonType, $RunLevel)
            [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType; RunLevel = $RunLevel }
        }
        function New-ScheduledTask {
            param($Action, $Trigger, $Settings, $Principal)
            [pscustomobject]@{ Action = $Action; Trigger = $Trigger; Settings = $Settings; Principal = $Principal }
        }
        & "$root/scripts/windows/install-backup-task.ps1"
        Assert ($null -ne $registrationState.Task) 'Task registration invoked'
        Assert ($registrationState.Name -match '^Infrastructure-Backup-[0-9A-F]{16}$') 'Task registration name'
        Assert (-not $registrationState.Task.Settings.Enabled) 'Task installed disabled'
        Assert ($registrationState.Task.Principal.LogonType -eq 'Interactive') 'No stored password'
        Assert ($registrationState.Task.Principal.RunLevel -eq 'Limited') 'No elevation requested'
        Assert ($registrationState.Task.Trigger.At -eq '03:00') 'Daily task time'
        Assert ($registrationState.Task.Action.Argument -match '-RetentionDays 7') 'Task retention default'
    }
    Write-Status PASS 'PowerShell parsing, help, binary IO, private permissions, timeouts, backup/restore safeguards, retention, locking, and reparse-point rejection.'
} finally {
    $RepositoryRoot = $root
    Remove-Item -LiteralPath $work -Recurse -Force
}
