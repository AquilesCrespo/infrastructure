#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))

function Write-Status {
    param([ValidateSet('PASS', 'FAIL', 'WARN', 'INFO', 'SKIP')][string]$Level, [string]$Message)
    $errorStream = $Level -in @('FAIL', 'WARN')
    $redirected = if ($errorStream) { [Console]::IsErrorRedirected } else { [Console]::IsOutputRedirected }
    $label = $Level
    if (-not $redirected -and $env:TERM -ne 'dumb' -and -not (Test-Path Env:NO_COLOR)) {
        $color = @{ PASS = 32; FAIL = 31; WARN = 33; INFO = 2; SKIP = 33 }[$Level]
        $label = "$([char]27)[$($color)m$Level$([char]27)[0m"
    }
    $writer = if ($errorStream) { [Console]::Error } else { [Console]::Out }
    $writer.WriteLine("$label $Message")
}

function Assert-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is unavailable; install it or check PATH."
    }
}

function Invoke-NativeProcess {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$InputFile,
        [IO.Stream]$OutputStream,
        [int]$TimeoutSeconds = 15
    )
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Command
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $inputStream = $null
    $started = $false
    try {
        if (-not $process.Start()) { throw "Cannot start $Command." }
        $started = $true
        $errorTask = $process.StandardError.ReadToEndAsync()
        $outputTask = if ($OutputStream) {
            $process.StandardOutput.BaseStream.CopyToAsync($OutputStream)
        } else {
            $process.StandardOutput.ReadToEndAsync()
        }
        $inputTask = $null
        if ($InputFile) {
            $inputStream = [IO.File]::OpenRead($InputFile)
            $inputTask = $inputStream.CopyToAsync($process.StandardInput.BaseStream)
        } else {
            $process.StandardInput.Close()
        }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(50)) {
            if ($inputTask -and $inputTask.IsCompleted) {
                $inputTask.GetAwaiter().GetResult() | Out-Null
                $process.StandardInput.Close()
                $inputTask = $null
            }
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw "$Command timed out after $TimeoutSeconds seconds."
            }
        }
        if ($inputTask) {
            $inputTask.GetAwaiter().GetResult() | Out-Null
            $process.StandardInput.Close()
        }
        $outputTask.GetAwaiter().GetResult() | Out-Null
        $errorTask.GetAwaiter().GetResult() | Out-Null
        if ($process.ExitCode -ne 0) {
            # Raw CLI errors may include credentials or resolved configuration.
            throw "$Command failed (exit $($process.ExitCode)); inspect service readiness and credentials locally."
        }
        if (-not $OutputStream) { return $outputTask.Result }
    } finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }

        if ($inputStream) { $inputStream.Dispose() }
        $process.Dispose()
    }
}

function Invoke-ScheduledDatabaseBackup {
    param([int]$RetentionDays = 7)
    if ($RetentionDays -lt 1 -or $RetentionDays -gt 9999) { throw 'Retention must be from 1 to 9999 days.' }
    Assert-Command docker
    $config = (Invoke-Compose @('config', '--format', 'json')) | ConvertFrom-Json
    $project = $config.name
    if ($project -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Invalid or missing Compose project name.' }
    $directory = $RepositoryRoot
    foreach ($part in @('backups', 'scheduled', $project)) {
        $directory = Join-Path $directory $part
        Assert-NoReparsePoint $directory
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $lockPath = Join-Path $directory '.windows.lock'
    Assert-NoReparsePoint $lockPath
    $lock = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        try {
            $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        } catch {
            throw "Cannot acquire backup lock for $project; another run may be active or access is denied."
        }
        $stamp = "$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))-$PID"
        foreach ($service in @('mysql', 'postgres', 'mongodb')) {
            $extension = @{ mysql = 'sql'; postgres = 'dump'; mongodb = 'archive.gz' }[$service]
            Invoke-DatabaseWorkflow backup $service (Join-Path $directory "scheduled-$stamp-$service.$extension")
        }
        $cutoff = [DateTime]::UtcNow.AddDays(-$RetentionDays)
        $removed = 0
        foreach ($item in Get-ChildItem -LiteralPath $directory -File -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                $item.Name -cmatch '^scheduled-[0-9]{8}T[0-9]{6}Z-[0-9]+-(mysql\.sql|postgres\.dump|mongodb\.archive\.gz)$' -and
                $item.LastWriteTimeUtc -lt $cutoff) {
                [IO.File]::Delete($item.FullName)
                $removed++
                Write-Status INFO "Removed expired scheduled backup: $($item.Name)"
            }
        }
        Write-Status PASS "Scheduled backups completed for $project; retention $RetentionDays days; removed $removed expired backup(s) ($([int]$clock.Elapsed.TotalSeconds)s)."
    } finally {
        if ($lock) { $lock.Dispose() }
    }
}

function Invoke-Compose {
    param([string[]]$Arguments, [string]$InputFile, [IO.Stream]$OutputStream, [int]$TimeoutSeconds = 15)
    Invoke-NativeProcess -Command docker -Arguments (@('compose', '--project-directory', $RepositoryRoot) + $Arguments) `
        -InputFile $InputFile -OutputStream $OutputStream -TimeoutSeconds $TimeoutSeconds
}

function Assert-NoReparsePoint {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing symlink or junction: $Path"
    }
}

function New-PrivateFile {
    param([string]$Path)
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = [Security.AccessControl.FileSecurity]::new()
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner($identity)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $identity, 'FullControl', 'Allow'))
        return [IO.FileSystemAclExtensions]::Create([IO.FileInfo]::new($Path),
            [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::FullControl,
            [IO.FileShare]::None, 4096, [IO.FileOptions]::None, $acl)
    }
    $options = [IO.FileStreamOptions]::new()
    $options.Mode = [IO.FileMode]::CreateNew
    $options.Access = [IO.FileAccess]::ReadWrite
    $options.Share = [IO.FileShare]::None
    $options.UnixCreateMode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
    return [IO.FileStream]::new($Path, $options)
}

function Invoke-DatabaseWorkflow {
    param([string]$Action, [string]$Service, [string]$File, [bool]$Confirmed = $false)
    if ($Service -notin @('mysql', 'postgres', 'mongodb', 'all')) { throw "Unsupported database: $Service" }
    if ($Action -notin @('backup', 'restore', 'seed')) { throw 'Expected backup, restore, or seed.' }
    if ($Service -eq 'all') {
        if ($Action -ne 'seed') { throw "'all' is supported only for seed." }
        foreach ($database in @('mysql', 'postgres', 'mongodb')) {
            Invoke-DatabaseWorkflow -Action seed -Service $database
        }
        return
    }
    if ($Action -eq 'restore' -and -not $Confirmed) {
        throw 'Restore requires -Confirm; nothing was restored.'
    }
    if ($Action -ne 'seed' -and -not $File) { throw 'Backup/restore requires -File.' }
    if ($Action -eq 'seed' -and $File) { throw 'Seed does not accept -File.' }
    Assert-Command docker
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $commands = @{
        backup = @{
            mysql = 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysqldump --user=root --single-transaction --routines --events --triggers --no-tablespaces --set-gtid-purged=OFF "$MYSQL_DATABASE"'
            postgres = 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --format=custom --no-owner --no-acl'
            mongodb = 'exec mongodump --username="$MONGO_INITDB_ROOT_USERNAME" --password="$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase=admin --archive --gzip'
        }
        restore = @{
            mysql = 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysql --user=root "$MYSQL_DATABASE"'
            postgres = 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --clean --if-exists --exit-on-error --single-transaction --no-owner --no-acl'
            mongodb = 'exec mongorestore --username="$MONGO_INITDB_ROOT_USERNAME" --password="$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase=admin --archive --gzip --drop --stopOnError --nsExclude="admin.*" --nsExclude="config.*" --nsExclude="local.*"'
        }
        seed = @{
            mysql = 'export MYSQL_PWD="$MYSQL_PASSWORD"; exec mysql --user="$MYSQL_USER" "$MYSQL_DATABASE"'
            postgres = 'export PGPASSWORD="$POSTGRES_PASSWORD"; exec psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-psqlrc --set=ON_ERROR_STOP=1 --single-transaction'
            mongodb = 'exec mongosh --quiet --username="$MONGO_INITDB_ROOT_USERNAME" --password="$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase=admin --file /dev/stdin'
        }
    }
    $arguments = @('exec', '-T', $Service, 'sh', '-eu', '-c', $commands[$Action][$Service])
    if ($Action -eq 'backup') {
        $destination = [IO.Path]::GetFullPath($File)
        Assert-NoReparsePoint $destination
        if (Test-Path -LiteralPath $destination) { throw "Backup destination already exists: $destination" }
        if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($destination))) {
            throw 'Create the backup destination directory first.'
        }
        $temporary = "$destination.partial.$([guid]::NewGuid().ToString('N'))"
        $stream = $null
        try {
            $stream = New-PrivateFile $temporary
            Invoke-Compose -Arguments $arguments -OutputStream $stream -TimeoutSeconds 600
            $bytes = $stream.Length
            if ($bytes -eq 0) { throw 'Backup output was empty.' }
            $stream.Dispose()
            $stream = $null
            [IO.File]::Move($temporary, $destination, $false)
            Write-Status PASS "Backup saved to $destination ($bytes bytes, $([int]$clock.Elapsed.TotalSeconds)s; private permissions)."
        } finally {
            if ($stream) { $stream.Dispose() }
            if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        }
    } else {
        $inputPath = if ($Action -eq 'seed') {
            $extension = if ($Service -eq 'mongodb') { 'js' } else { 'sql' }
            Join-Path $RepositoryRoot "seeds/$Service.$extension"
        } else {
            [IO.Path]::GetFullPath($File)
        }
        if (-not [IO.File]::Exists($inputPath) -or (Get-Item -LiteralPath $inputPath).Length -eq 0) {
            throw 'Input must be a readable, nonempty file.'
        }
        if ($Action -eq 'restore') { Write-Status WARN "Restoring $Service; existing backed-up objects may be replaced." }
        Invoke-Compose -Arguments $arguments -InputFile $inputPath -TimeoutSeconds 600 | Out-Null
        Write-Status PASS "Completed $Action for $Service ($([int]$clock.Elapsed.TotalSeconds)s)."
    }
}
