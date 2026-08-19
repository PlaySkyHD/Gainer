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
work=/work/gainer-backup
rm -rf "$work"
mkdir -p "$work"

pg_dump \
  --host="${PGHOST:-postgres}" \
  --port="${PGPORT:-5432}" \
  --username="${PGUSER:-gainer}" \
  --dbname="${PGDATABASE:-gainer}" \
  --format=custom \
  --file="$work/database.dump"

tar -C /source -czf "$work/persistent-keys.tar.gz" data-protection
if ! restic snapshots >/dev/null 2>&1; then
  restic init
fi
restic backup "$work" --tag gainer-vps
restic forget --keep-daily "${BACKUP_KEEP_DAILY:-7}" --keep-weekly "${BACKUP_KEEP_WEEKLY:-5}" --keep-monthly "${BACKUP_KEEP_MONTHLY:-12}" --prune
rm -rf "$work"
