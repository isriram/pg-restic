#!/bin/sh
set -euo pipefail

[ -f /etc/pg-restic.env ] && . /etc/pg-restic.env

# Wait for a running backup to finish; prune needs the repository to itself
exec 9> /var/run/pg-restic.lock
flock 9

echo "$(date -Iseconds) Pruning unreferenced data from ${RESTIC_REPOSITORY}..."
restic prune

echo 'Prune complete.'
