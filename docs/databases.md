# Database workflows

[Documentation index](./README.md) | [Project README](../README.md)

Run all commands from the repository root.

## Backup and restore

Run `bash scripts/db.sh` from the repository root. The script uses the running
containers' credentials, so it does not source or print `.env`. Services must
already be running; these commands never start, stop, or recreate them.

```sh
mkdir -p backups
bash scripts/db.sh backup mysql backups/mysql.sql
bash scripts/db.sh backup postgres backups/postgres.dump
bash scripts/db.sh backup mongodb backups/mongodb.archive.gz
```

Choose a new filename for each backup (for example, include a date). Existing
files are never overwritten. Files are created with private permissions, and
only published at the requested path after the dump succeeds. Failed partial
files are removed. `backups/` is ignored by Git; treat backups as sensitive and
keep them out of source control if you store them anywhere else.

| Service | Backup scope | Restore behavior |
|---|---|---|
| MySQL | Configured `MYSQL_DATABASE`, including routines, events, and triggers | Loads SQL into the configured database; replaces tables present in the dump |
| PostgreSQL | Configured `POSTGRES_DB`; no role definitions, ownership, or ACLs | Cleans and restores backed-up objects in one transaction, owned by the configured user |
| MongoDB | `mongodump` default database scope, including any exported admin metadata | Drops and restores collections present in the archive, excluding `admin`, `config`, and `local`; retains current credentials |

Restore requires the explicit `--confirm` argument:

```sh
bash scripts/db.sh restore mysql backups/mysql.sql --confirm
bash scripts/db.sh restore postgres backups/postgres.dump --confirm
bash scripts/db.sh restore mongodb backups/mongodb.archive.gz --confirm
```

Stop application writes and take a fresh backup before restoring. Only restore
trusted files: SQL dumps can execute SQL. These are logical data backups, not
complete snapshots of container configuration or database users. Objects absent
from a backup are not necessarily removed on restore. MySQL and MongoDB restores
are not atomic; a failure can leave partial changes. Do not resume applications
until you have checked the restore outcome.

MySQL's snapshot is consistent for transactional tables; avoid concurrent DDL,
and stop writes for nontransactional tables. The standalone MongoDB deployment
does not offer a cross-collection point-in-time dump: stop writes for consistency.
Backups across these three services are not one coordinated transaction.
Test restore compatibility before upgrading database major versions.
Redis is intentionally untouched.

### Recovery practice

Run `bash tests/db-workflows.sh` periodically and before database-version changes.
It verifies backup/restore round trips using disposable data in an isolated
project, not your development databases.

If real local data matters, also restore a trusted backup into a separate project
with compatible database versions and verify application-specific record counts
and critical queries. Use that project's env selectors for every command; see
[project isolation](./project-isolation.md). Never use the active project's
databases for a recovery rehearsal. The automated test proves the tooling, not the
recoverability of each real backup or compatibility of a future major version.

Keep a protected copy of important backups on a separate disk or approved backup
destination. A backup on the same disk does not protect against disk failure.
No external copying, encryption, scheduling, or automatic upgrades are enabled
by this recommendation.

### Opt-in scheduled backups and retention

Run one scheduled batch manually:

```sh
bash scripts/scheduled-backup.sh
# Or choose a different retention window in days:
bash scripts/scheduled-backup.sh 30
```

It backs up MySQL, PostgreSQL, and MongoDB into
`backups/scheduled/COMPOSE_PROJECT_NAME/`, with private permissions and unique
timestamped filenames. A per-project `flock` lock prevents overlapping runs.
All three databases must be running. Each dump has a ten-minute timeout.
Redis is not backed up. Use `COMPOSE_ENV_FILES` to select another deployment.

The default retention is seven days, measured by file modification time. Only
completed files matching this workflow's exact generated naming convention in
that project's scheduled folder are eligible. Manual backups, subdirectories,
symlinks, and partial files are not pruned. Cleanup runs only after all three
backups succeed; a failed batch preserves older backups and reports failure.
Already completed backups from a partly failed batch are retained. Retention
does not make dumps consistent across services; the consistency warnings above
still apply. Symlinked backup directories and lock files are rejected.

For a daily Linux systemd user timer:

```sh
bash scripts/install-backup-timer.sh
```

The installer creates a disabled timer and prints its specific enable, log, and
disable commands. It does not enable the timer or run a backup. Inspect the
generated user units first, then explicitly execute the printed
`systemctl --user enable --now ...timer` command to opt in.
Daily runs occur at 03:00 local time with up to 15 minutes of jitter; `Persistent`
can trigger a catch-up run when the user manager starts. A login user manager and
Docker access are required. Runs while logged out require user lingering, which
this installer never enables.

It captures exported `COMPOSE_PROJECT_NAME`, `COMPOSE_ENV_FILES`, and `COMPOSE_FILE`
selectors; otherwise Compose reads this workspace's `.env` on each run. For another
project, export the env selector when installing its timer. Separate selectors
receive separate unit names. Keep the selected project identity stable or reinstall
deliberately. Credentials are not copied into units.
The timer uses seven days; edit the generated service's final argument and reload
the user manager if you want different retention. Reinstallation refuses to
overwrite existing units. Requires Bash, GNU coreutils, `flock`, Docker Compose,
and systemd for timer installation. Scheduling remains uninstalled and disabled
until you run the installer and explicitly enable its timer.

## Repeatable demo seeds

```sh
bash scripts/db.sh seed all
# Or one database:
bash scripts/db.sh seed postgres
```

Reserved demo locations:

- MySQL: `infrastructure_demo_customers` in `MYSQL_DATABASE`.
- PostgreSQL: `infrastructure_demo.customers` in `POSTGRES_DB`.
- MongoDB: `infrastructure_demo.customers` (database and collection).

The versioned scripts in `seeds/` upsert two fictional customers with fixed IDs.
Running them again refreshes those demo records without duplicating them; other
records and application tables/collections are not deleted. Reserve these names
and IDs for this tooling; do not use them for application data. Seeds are explicit,
not first-start initialization scripts, so they also work with existing volumes.
`seed all` stops at the first failure; it is not a cross-database transaction.


For isolated backup/restore and seeding checks, see [verification](./verification.md).
