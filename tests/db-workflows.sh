#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export COMPOSE_FILE="$root/tests/docker-compose.yml"
export COMPOSE_PROJECT_NAME="infrastructure-db-test-$$"
compose=(docker compose --project-directory "$root")
work="$(mktemp -d)"

cleanup() {
  "${compose[@]}" down --volumes
  rm -f -- "$work/mysql.sql" "$work/postgres.dump" "$work/mongodb.archive.gz" "$work/errors"
  rmdir -- "$work"
}
trap cleanup EXIT
trap 'printf "Workflow test failed at line %s.\n" "$LINENO" >&2' ERR

db() {
  bash "$root/scripts/db.sh" "$@"
}

mysql_query() {
  "${compose[@]}" exec -T mysql sh -eu -c \
    'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; exec mysql -uroot -N -B "$MYSQL_DATABASE" -e "$1"' sh "$1"
}

postgres_query() {
  "${compose[@]}" exec -T postgres psql -U workflow_test -d workflow_test -At -v ON_ERROR_STOP=1 -c "$1"
}

mongo_query() {
  "${compose[@]}" exec -T mongodb mongosh --quiet -u workflow_test \
    -p test-only-password --authenticationDatabase admin --eval "$1"
}

expect_failure() {
  if db "$@" > "$work/errors" 2>&1; then
    printf 'Expected command to fail: %s\n' "$*" >&2
    exit 1
  fi
}

expect_failure restore mysql "$work/mysql.sql"
grep -q 'requires FILE and --confirm' "$work/errors"
expect_failure restore redis "$work/mysql.sql" --confirm
grep -q 'Unsupported database' "$work/errors"

"${compose[@]}" up -d --wait --wait-timeout 240

mysql_query "CREATE TABLE application_sentinel (id INT PRIMARY KEY); INSERT INTO application_sentinel VALUES (99);"
postgres_query "CREATE TABLE application_sentinel (id INT PRIMARY KEY); INSERT INTO application_sentinel VALUES (99);"
mongo_query 'db.getSiblingDB("application_sentinel").records.insertOne({_id:99});'
db seed all
mysql_query "INSERT INTO infrastructure_demo_customers VALUES (99, 'Keep Me', 'keep@example.test'); UPDATE infrastructure_demo_customers SET email='changed@example.test' WHERE id=1;"
postgres_query "INSERT INTO infrastructure_demo.customers VALUES (99, 'Keep Me', 'keep@example.test'); UPDATE infrastructure_demo.customers SET email='changed@example.test' WHERE id=1;"
mongo_query 'const demo=db.getSiblingDB("infrastructure_demo"); demo.customers.insertOne({_id:"keep-me",email:"keep@example.test"}); demo.customers.updateOne({_id:"demo-alice"},{$set:{email:"changed@example.test"}});'
db seed all

[[ "$(mysql_query 'SELECT COUNT(*) FROM infrastructure_demo_customers')" == 3 ]]
[[ "$(postgres_query 'SELECT COUNT(*) FROM infrastructure_demo.customers')" == 3 ]]
[[ "$(mongo_query 'db.getSiblingDB("infrastructure_demo").customers.countDocuments({})')" == 3 ]]
[[ "$(mysql_query 'SELECT email FROM infrastructure_demo_customers WHERE id=1')" == alice@example.test ]]
[[ "$(postgres_query 'SELECT email FROM infrastructure_demo.customers WHERE id=1')" == alice@example.test ]]
[[ "$(mongo_query 'db.getSiblingDB("infrastructure_demo").customers.findOne({_id:"demo-alice"}).email')" == alice@example.test ]]
[[ "$(mysql_query 'SELECT id FROM application_sentinel')" == 99 ]]
[[ "$(postgres_query 'SELECT id FROM application_sentinel')" == 99 ]]
[[ "$(mongo_query 'db.getSiblingDB("application_sentinel").records.countDocuments({_id:99})')" == 1 ]]

db backup mysql "$work/mysql.sql"
db backup postgres "$work/postgres.dump"
db backup mongodb "$work/mongodb.archive.gz"
for file in mysql.sql postgres.dump mongodb.archive.gz; do
  [[ "$(stat -c '%a' "$work/$file")" == 600 ]]
done
original="$(sha256sum "$work/mysql.sql")"
expect_failure backup mysql "$work/mysql.sql"
grep -q 'already exists' "$work/errors"
[[ "$(sha256sum "$work/mysql.sql")" == "$original" ]]
expect_failure restore postgres "$work/absent.dump" --confirm
grep -q 'readable, nonempty' "$work/errors"

mysql_query "DELETE FROM infrastructure_demo_customers; INSERT INTO infrastructure_demo_customers VALUES (999, 'Replace Me', 'replace@example.test'); DROP TABLE application_sentinel;"
postgres_query "DELETE FROM infrastructure_demo.customers; INSERT INTO infrastructure_demo.customers VALUES (999, 'Replace Me', 'replace@example.test'); DROP TABLE application_sentinel;"
mongo_query 'const demo=db.getSiblingDB("infrastructure_demo"); demo.customers.deleteMany({}); demo.customers.insertOne({_id:"replace-me"}); db.getSiblingDB("application_sentinel").dropDatabase();'

db restore mysql "$work/mysql.sql" --confirm
db restore postgres "$work/postgres.dump" --confirm
db restore mongodb "$work/mongodb.archive.gz" --confirm

[[ "$(mysql_query 'SELECT COUNT(*) FROM infrastructure_demo_customers')" == 3 ]]
[[ "$(postgres_query 'SELECT COUNT(*) FROM infrastructure_demo.customers')" == 3 ]]
[[ "$(mongo_query 'db.getSiblingDB("infrastructure_demo").customers.countDocuments({})')" == 3 ]]
[[ "$(mysql_query 'SELECT id FROM application_sentinel')" == 99 ]]
[[ "$(postgres_query 'SELECT id FROM application_sentinel')" == 99 ]]
[[ "$(mongo_query 'db.getSiblingDB("application_sentinel").records.countDocuments({_id:99})')" == 1 ]]
[[ "$(mysql_query 'SELECT email FROM infrastructure_demo_customers WHERE id=1')" == alice@example.test ]]
[[ "$(postgres_query 'SELECT email FROM infrastructure_demo.customers WHERE id=1')" == alice@example.test ]]
[[ "$(mongo_query 'db.getSiblingDB("infrastructure_demo").customers.findOne({_id:"demo-alice"}).email')" == alice@example.test ]]

"${compose[@]}" stop postgres
expect_failure backup postgres "$work/failed.dump"
[[ ! -e "$work/failed.dump" ]]
[[ -z "$(find "$work" -name '*.partial.*' -print)" ]]

printf 'PASS: repeatable seeds preserve unrelated data; all three backups restore data; overwrite, confirmation, and failure cleanup safeguards work.\n'
