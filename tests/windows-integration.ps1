#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/windows/common.ps1"
$project = "infrastructure-powershell-test-$PID"
$work = Join-Path ([IO.Path]::GetTempPath()) "$project-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($work) | Out-Null
$override = Join-Path $work 'ports.json'
$previous = @{}
foreach ($key in @('COMPOSE_FILE', 'COMPOSE_PROJECT_NAME', 'COMPOSE_ENV_FILES', 'COMPOSE_PROFILES')) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key)
}
$env:COMPOSE_PROJECT_NAME = $project
$env:COMPOSE_ENV_FILES = Join-Path $RepositoryRoot '.env.example'
$env:COMPOSE_PROFILES = $null
$env:COMPOSE_FILE = "$(Join-Path $RepositoryRoot 'tests/docker-compose.yml')$([IO.Path]::PathSeparator)$override"
$ports = @{ services = @{} }
foreach ($service in @('mysql', 'postgres', 'mongodb')) {
    $port = @{ mysql = 3306; postgres = 5432; mongodb = 27017 }[$service]
    $ports.services[$service] = @{ ports = @(@{ target = $port; published = '0'; host_ip = '127.0.0.1' }) }
}
[IO.File]::WriteAllText($override, ($ports | ConvertTo-Json -Depth 8))
function Query {
    param([string]$Service, [string]$Statement)
    $arguments = switch ($Service) {
        mysql { @('sh', '-eu', '-c', 'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysql -uroot -N -B "$MYSQL_DATABASE" -e "$1"', 'sh', $Statement) }
        postgres { @('psql', '-U', 'workflow_test', '-d', 'workflow_test', '-At', '-v', 'ON_ERROR_STOP=1', '-c', $Statement) }
        mongodb { @('mongosh', '--quiet', '-u', 'workflow_test', '-p', 'test-only-password', '--authenticationDatabase', 'admin', '--eval', $Statement) }
    }
    (Invoke-Compose (@('exec', '-T', $Service) + $arguments)).Trim()
}
function Check {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
try {
    Invoke-Compose @('up', '-d', '--wait', '--wait-timeout', '240') -TimeoutSeconds 300 | Out-Null
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    Invoke-NativeProcess $pwsh @('-NoProfile', '-File', "$RepositoryRoot/scripts/windows/doctor.ps1",
        'mysql', 'postgres', 'mongodb') -TimeoutSeconds 90 | Out-Null
    Invoke-DatabaseWorkflow seed all
    Query mysql "INSERT INTO infrastructure_demo_customers VALUES (99,'Keep','keep@example.test');" | Out-Null
    Query postgres "INSERT INTO infrastructure_demo.customers VALUES (99,'Keep','keep@example.test');" | Out-Null
    Query mongodb 'db.getSiblingDB("infrastructure_demo").customers.insertOne({_id:"keep-me"});' | Out-Null
    Invoke-DatabaseWorkflow seed all
    $statements = @{
        mysql = 'SELECT COUNT(*) FROM infrastructure_demo_customers'
        postgres = 'SELECT COUNT(*) FROM infrastructure_demo.customers'
        mongodb = 'db.getSiblingDB("infrastructure_demo").customers.countDocuments({})'
    }
    foreach ($service in $statements.Keys) {
        Check ((Query $service $statements[$service]) -eq '3') "$service repeatable seeds must preserve extra data."
        Invoke-DatabaseWorkflow backup $service (Join-Path $work "$service.backup")
    }
    Query mysql 'DELETE FROM infrastructure_demo_customers;' | Out-Null
    Query postgres 'DELETE FROM infrastructure_demo.customers;' | Out-Null
    Query mongodb 'db.getSiblingDB("infrastructure_demo").customers.deleteMany({});' | Out-Null
    foreach ($service in $statements.Keys) {
        Invoke-DatabaseWorkflow restore $service (Join-Path $work "$service.backup") $true
        Check ((Query $service $statements[$service]) -eq '3') "$service restore must recover data."
    }
    Write-Status PASS 'Native PowerShell diagnostics, repeatable seeds, and binary backup/restore round trips for all three databases.'
} finally {
    try { Invoke-Compose @('down', '--volumes') -TimeoutSeconds 120 | Out-Null }
    finally {
        foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
