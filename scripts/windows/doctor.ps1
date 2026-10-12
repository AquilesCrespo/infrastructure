#Requires -Version 7.4
[CmdletBinding()]
param([Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Services, [switch]$Help)
. "$PSScriptRoot/common.ps1"
if ($Help) {
    @'
Usage: ./scripts/windows/doctor.ps1 [SERVICE ...] [-Help]
Example: ./scripts/windows/doctor.ps1 postgres redis mailpit

Without names, require core/profile-selected services and inspect running optional
services. With names, require only those services. Read-only; requires PowerShell
7.4+ and Docker Desktop Linux containers. Uses local loopback TCP probes.
'@
    exit 0
}
$counts = @{ PASS = 0; FAIL = 0; SKIP = 0 }
$clock = [Diagnostics.Stopwatch]::StartNew()
function Report {
    param([string]$Level, [string]$Message)
    Write-Status $Level $Message
    if ($counts.ContainsKey($Level)) { $counts[$Level]++ }
}
try {
    Assert-Command docker
    Invoke-Compose @('--profile', '*', 'config', '--quiet') | Out-Null
    Report PASS 'Compose configuration'
    Invoke-NativeProcess docker @('info') | Out-Null
    $available = @( (Invoke-Compose @('--profile', '*', 'config', '--services')) -split '\r?\n' | Where-Object { $_ } )
    $required = @( (Invoke-Compose @('config', '--services')) -split '\r?\n' | Where-Object { $_ } )
    if ($Services) {
        foreach ($service in $Services) {
            if ($service -cnotin $available) { throw "Unknown service: $service" }
        }
        $available = @($Services | Select-Object -Unique)
        $required = $available
    }
    $queries = @{
        mysql = 'export MYSQL_PWD="$MYSQL_PASSWORD"; exec mysql --host=127.0.0.1 --connect-timeout=5 --user="$MYSQL_USER" "$MYSQL_DATABASE" --execute="SELECT 1"'
        postgres = 'export PGPASSWORD="$POSTGRES_PASSWORD" PGCONNECT_TIMEOUT=5; exec psql --host=postgres --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-psqlrc --set=ON_ERROR_STOP=1 --command="SELECT 1"'
        mongodb = 'exec mongosh --quiet --host 127.0.0.1 --eval ''const a=db.getSiblingDB("admin"); if (!a.auth(process.env.MONGO_INITDB_ROOT_USERNAME,process.env.MONGO_INITDB_ROOT_PASSWORD) || a.runCommand({ping:1}).ok !== 1) {throw new Error("Authentication or ping failed");}'''
        redis = 'test "$(redis-cli -h 127.0.0.1 ping)" = PONG'
    }
    foreach ($service in $available) {
        try {
            $ids = @((Invoke-Compose @('ps', '--all', '--quiet', $service)) -split '\r?\n' | Where-Object { $_ })
            if (-not $ids.Count) {
                if ($service -in $required) { Report FAIL "${service}: no container; start it explicitly." }
                else { Report SKIP "${service}: optional service not created" }
                continue
            }
            foreach ($id in $ids) {
                $state = (Invoke-NativeProcess docker @('inspect', '--format',
                    '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}', $id)).Trim().Split('|')
                if ($state[0] -ne 'running') {
                    if ($service -in $required) { Report FAIL "${service}: container is $($state[0])" }
                    else { Report SKIP "${service}: optional container is $($state[0])" }
                    continue
                }
                Report PASS "${service}: running"
                switch ($state[1]) {
                    healthy { Report PASS "${service}: healthy" }
                    none { Report WARN "${service}: no Docker healthcheck configured" }
                    default { Report FAIL "${service}: health is $($state[1]); inspect bounded logs locally." }
                }
                $ports = @((Invoke-NativeProcess docker @('port', $id)) -split '\r?\n' | Where-Object { $_ })
                if ($service.EndsWith('-exporter')) {
                    Report INFO "${service}: internal metrics; verify Prometheus Targets"
                } elseif (-not $ports.Count) {
                    Report FAIL "${service}: no published ports"
                } else {
                    foreach ($mapping in $ports) {
                        if ($mapping -notmatch '^\d+/tcp -> 127\.0\.0\.1:(\d+)$') {
                            Report FAIL "${service}: unexpected binding; expected localhost-only TCP."
                            continue
                        }
                        $port = [int]$Matches[1]
                        $client = [Net.Sockets.TcpClient]::new()
                        try {
                            $task = $client.ConnectAsync('127.0.0.1', $port)
                            if (-not $task.Wait(3000)) { throw 'TCP timeout' }
                            Report PASS "${service}: 127.0.0.1:$port accepts TCP connections"
                        } catch {
                            Report FAIL "${service}: 127.0.0.1:$port is unreachable; check Docker context and listener."
                        } finally { $client.Dispose() }
                    }
                }
                if ($queries.ContainsKey($service)) {
                    try {
                        Invoke-NativeProcess docker @('exec', $id, 'sh', '-eu', '-c', $queries[$service]) | Out-Null
                        Report PASS "${service}: database connection"
                    } catch {
                        Report FAIL "${service}: database connection failed or timed out; check readiness and stored credentials."
                    }
                }
            }
        } catch {
            Report FAIL "${service}: $($_.Exception.Message)"
        }
    }
} catch {
    Report FAIL $_.Exception.Message
}
Write-Status INFO "Summary: $($counts.PASS) passed, $($counts.FAIL) failed, $($counts.SKIP) skipped checks ($([int]$clock.Elapsed.TotalSeconds)s)."
if ($counts.FAIL) { exit 1 }
Write-Status PASS 'Doctor passed all required and running-service checks.'
