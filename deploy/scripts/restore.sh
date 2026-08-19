#!/bin/sh
set -eu

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE is required}"
: "${POSTGRES_PASSWORD_FILE:?POSTGRES_PASSWORD_FILE is required}"
case "$RESTIC_REPOSITORY" in
  azure:*)
    : "${AZURE_ACCOUNT_NAME:?AZURE_ACCOUNT_NAME is required for the native Azure backend}"
    export AZURE_ACCOUNT_SAS="$(cat "${AZURE_ACCOUNT_SAS_FILE:?AZURE_ACCOUNT_SAS_FILE is required for the native Azure backend}")"
    ;;
  rclone:*)
    : # rclone receives its Azure/Azurite configuration through RCLONE_AZUREBLOB_*.
    ;;
  *)
    echo "RESTIC_REPOSITORY must use the azure: or rclone: backend." >&2
    exit 64
    ;;
esac
export PGPASSWORD="$(cat "$POSTGRES_PASSWORD_FILE")"
target=/restore
rm -rf "$target"
mkdir -p "$target"
restic restore "${RESTIC_SNAPSHOT:-latest}" --target "$target" --tag gainer-vps
dump="$target/work/gainer-backup/database.dump"
keys="$target/work/gainer-backup/persistent-keys.tar.gz"
test -s "$dump"
test -s "$keys"

pg_restore \
  --host="${PGHOST:-postgres}" \
  --port="${PGPORT:-5432}" \
  --username="${PGUSER:-gainer}" \
  --dbname="${PGDATABASE:-gainer_restore}" \
  --clean --if-exists --no-owner --exit-on-error "$dump"

psql --host="${PGHOST:-postgres}" --port="${PGPORT:-5432}" --username="${PGUSER:-gainer}" --dbname="${PGDATABASE:-gainer_restore}" --set=ON_ERROR_STOP=1 <<'SQL'
SELECT COUNT(*) AS identity_users FROM identity.users;
SELECT COUNT(*) AS body_goals FROM body.goals;
SELECT COUNT(*) AS workouts FROM training.workouts;
SELECT COUNT(*) AS processed_mutations FROM sync.processed_mutations;
SELECT "MigrationId" FROM identity."__EFMigrationsHistory" ORDER BY "MigrationId" DESC LIMIT 1;
SQL

echo "Restore verified in the isolated database. Persistent keys remain staged in $keys for deliberate operator recovery."
