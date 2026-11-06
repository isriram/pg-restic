#!/bin/sh
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"
: "${CRON_SCHEDULE:=0 * * * *}"
# Container hostnames change on every recreate; a fixed host keeps restic's stale-lock detection
# and per-host retention grouping consistent
export RESTIC_HOST="${RESTIC_HOST:-pg-restic}"

echo "$(pg_dumpall --version), $(restic version)"

# crond does not pass the container environment to jobs, so snapshot it to a file backup.sh can source
export -p > /etc/pg-restic.env
chmod 600 /etc/pg-restic.env

# Create the repository on first run. restic exits 10 only when the repository doesn't exist;
# any other failure (wrong password, bad credentials, network) must not lead to an init attempt.
config_status=0
config_error=$(restic cat config 2>&1 > /dev/null) || config_status=$?
if [ "$config_status" -eq 10 ]; then
    echo 'Initializing restic repository...'
    restic init
elif [ "$config_status" -ne 0 ]; then
    echo "Cannot open the restic repository: ${config_error}" >&2
    exit 1
fi

# Nothing from this container is running yet, so clear stale locks left by a killed previous run
restic unlock

# "backup-now" runs a single backup and exits, e.g. `docker compose run --rm pg-restic backup-now`
if [ "${1:-}" = "backup-now" ]; then
    exec /usr/local/bin/backup.sh
fi

echo "${CRON_SCHEDULE} /usr/local/bin/backup.sh > /proc/1/fd/1 2>&1" > /etc/crontabs/root
echo "Cron daemon started with pattern: ${CRON_SCHEDULE}"
exec crond -f -d 8
