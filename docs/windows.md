# Native Windows development

[Documentation index](./README.md) | [Project README](../README.md)

## Requirements and setup

- Docker Desktop, running in **Linux containers** mode. These images are not
  Windows container images. Docker Desktop may itself use a WSL 2 backend, but
  these scripts run directly in PowerShell and need no WSL shell or Bash.
- PowerShell **7.4 or newer** (`pwsh`), not Windows PowerShell 5.1.
- A local Docker context and `docker` available in PATH.
- A local NTFS checkout/backup destination for predictable private-file ACLs
  and locking. Avoid network shares and cloud-synchronized backup folders.
- Your application's runtime/SDK, installed separately.

Run commands from the repository root in PowerShell:

```powershell
# Preserve an existing configuration.
if (-not (Test-Path -LiteralPath .env)) {
    Copy-Item .env.example .env
}
# Edit .env and replace placeholder credentials before starting.
docker compose --profile "*" config --quiet
docker compose up -d --wait postgres redis mailpit
./scripts/windows/doctor.ps1 postgres redis mailpit
```

If trusted downloaded scripts are blocked, review them and use Windows' Unblock
action or `Unblock-File` on the specific files as permitted by your organization.
Do not disable machine-wide execution policy. Group Policy restrictions may
require administrator guidance.

## Commands

| Bash command | Native PowerShell equivalent |
|---|---|
| `scripts/doctor.sh` | `scripts/windows/doctor.ps1` |
| `scripts/db.sh` | `scripts/windows/db.ps1` |
| `scripts/scheduled-backup.sh` | `scripts/windows/scheduled-backup.ps1` |
| `scripts/install-backup-timer.sh` | `scripts/windows/install-backup-task.ps1` |

Each PowerShell entrypoint supports `-Help`. Doctor accepts service names;
without them it requires all core/profile-selected services and checks running
optional services. It checks state, health, loopback TCP, and database connectivity.
It never starts or stops services. A remote Docker context can cause host TCP
checks to fail even when remote containers are healthy.

```powershell
./scripts/windows/doctor.ps1 -Help
./scripts/windows/db.ps1 -Help
./scripts/windows/scheduled-backup.ps1 -Help
./scripts/windows/install-backup-task.ps1 -Help

New-Item -ItemType Directory -Path backups -Force | Out-Null
./scripts/windows/db.ps1 seed all
./scripts/windows/db.ps1 backup mysql -File backups/mysql.sql
./scripts/windows/db.ps1 backup postgres -File backups/postgres.dump
./scripts/windows/db.ps1 backup mongodb -File backups/mongodb.archive.gz

# Destructive: stop application writes and take a fresh backup first.
./scripts/windows/db.ps1 restore postgres -File backups/postgres.dump -Confirm
```

Use `-Confirm`, not Bash's `--confirm`. Restore executes immediately when the
switch is provided; there is no additional interactive confirmation prompt.
Backup scopes, consistency limits, demo locations, and non-atomic restore
warnings are the same as the [database guide](./databases.md).

Backups transfer raw bytes through .NET streams: do not replace the implementation
with PowerShell text pipelines or `Out-File`, which can corrupt binary dumps.
New files grant access only to the current Windows user, with inherited access
rules removed. Dumps are published only after success, refuse overwrite, and
remove failed partial files. Administrators can still take ownership of files.
The scripts return zero on success and nonzero on failure; CLI errors are
summarized rather than printing potentially sensitive raw output.

Status colors are automatic for terminal streams and disabled for redirected
streams, `TERM=dumb`, or a set `NO_COLOR` variable. Labels remain readable without
color; warnings/failures go to stderr.

## Project selection

The scripts preserve normal Compose environment selection; they do not source
the private env file themselves:

```powershell
$env:COMPOSE_PROJECT_NAME = 'my-project'
$env:COMPOSE_ENV_FILES = 'C:\development\infrastructure\.env.my-project'
./scripts/windows/doctor.ps1 postgres redis
```

Use the same selectors for startup, diagnostics, seeds, backups, and restores.
Give enabled services distinct host ports for another project. A new project
selects different volumes, not migrated data. See [project isolation](./project-isolation.md).

## Opt-in scheduled backups

Run a batch manually:

```powershell
./scripts/windows/scheduled-backup.ps1
./scripts/windows/scheduled-backup.ps1 -RetentionDays 30
```

All three databases must be running. Dumps have ten-minute timeouts and are
written under `backups/scheduled/PROJECT/`. The default retention is seven days
by modification time; pruning happens only after all dumps succeed, only for
owned completed filenames. Manual/partial files, subdirectories, and reparse
points are not pruned. Symlink/junction directories and lock files are rejected.

An exclusive `.windows.lock` prevents overlapping native PowerShell batches.
Do not schedule both Windows and Bash/WSL backup jobs against the same project
folder: their locks are platform-specific and do not coordinate with one another.

Install a **disabled** Windows Task Scheduler task:

```powershell
./scripts/windows/install-backup-task.ps1
```

The installer prints the task name and inspection/enable/disable commands.
It refuses to replace an existing task. Review it before explicitly enabling it.
It runs daily at 03:00 with seven-day retention, under the current user without
elevation or a stored password. The user must be logged in, Docker Desktop must
be running, and the configured PowerShell executable must remain installed.
Missed runs can be attempted when the task is next available.

Exported `COMPOSE_PROJECT_NAME`, `COMPOSE_ENV_FILES`, and `COMPOSE_FILE` selectors
are captured as arguments, not credentials. Without selectors, the repository's
env file is read on each run. Keep project identity stable. To remove the task,
use Task Scheduler or `Unregister-ScheduledTask` for the printed task name.
Installation may require permission to register user tasks; failures are reported
and do not enable anything.

## Verification

```powershell
# No Docker daemon needed; tests use disposable files and mocks.
./tests/windows.ps1

# Requires Linux-container Docker; disposable databases and ephemeral ports.
./tests/windows-integration.ps1
```

The Windows CI job checks parsing/help, byte-preserving IO, private ACLs, backup
safeguards, retention, locks, junction rejection, and mocked disabled task
registration. It does not install an actual scheduled task.
The weekly/manual Linux integration job runs the PowerShell database workflows
against actual Linux containers. An actual Windows/Docker Desktop integration
run remains the recommended local acceptance check.
