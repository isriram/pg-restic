#!/bin/sh
set -euo pipefail

[ -f /etc/pg-restic.env ] && . /etc/pg-restic.env

# Skip this run if the previous one is still going (slow dump or prune)
exec 9> /var/run/pg-restic.lock
if ! flock -n 9; then
    echo "$(date -Iseconds) Previous backup still running, skipping this run."
    exit 0
fi

echo "$(date -Iseconds) Streaming database dump to ${RESTIC_REPOSITORY}..."
# --stdin-from-command fails the backup (and creates no snapshot) if pg_dumpall exits non-zero
if ! restic backup --stdin-filename production.sql --stdin-from-command -- \
        pg_dumpall -h "$PGHOST" -U "$PGUSER" --clean; then
    echo 'Database dump failed!' >&2
    exit 1
fi

echo 'Applying retention policy...'
restic forget --prune \
    --keep-hourly "${RESTIC_KEEP_HOURLY:-24}" \
    --keep-daily "${RESTIC_KEEP_DAILY:-31}" \
    --keep-monthly "${RESTIC_KEEP_MONTHLY:-12}"

echo 'Backup and prune complete.'
