#!/bin/sh
set -euo pipefail

[ -f /etc/pg-restic.env ] && . /etc/pg-restic.env

# Skip this run if the previous one, or a prune, is still going
exec 9> /var/run/pg-restic.lock
if ! flock -n 9; then
    echo "$(date -Iseconds) Previous backup or prune still running, skipping this run."
    exit 0
fi

echo "$(date -Iseconds) Streaming database dump to ${RESTIC_REPOSITORY}..."
# --stdin-from-command fails the backup (and creates no snapshot) if pg_dumpall exits non-zero
if ! restic backup --stdin-filename all-databases.sql --stdin-from-command -- \
        pg_dumpall -h "$PGHOST" -U "$PGUSER" --clean; then
    echo 'Database dump failed!' >&2
    exit 1
fi

# Space is freed by prune.sh on PRUNE_SCHEDULE; forget only drops snapshot records
echo 'Applying retention policy...'
restic forget \
    --keep-hourly "${RESTIC_KEEP_HOURLY:-24}" \
    --keep-daily "${RESTIC_KEEP_DAILY:-31}" \
    --keep-monthly "${RESTIC_KEEP_MONTHLY:-12}"

echo 'Backup complete.'

if [ -n "${PING_URL:-}" ] && ! wget -q -T 10 -O /dev/null "$PING_URL"; then
    echo 'Warning: could not reach PING_URL.' >&2
fi
