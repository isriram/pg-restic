# pg-restic

[![Docker Hub](https://img.shields.io/docker/v/sriramiyer/pg-restic?sort=semver&label=docker%20hub&logo=docker)](https://hub.docker.com/r/sriramiyer/pg-restic)
[![Docker pulls](https://img.shields.io/docker/pulls/sriramiyer/pg-restic?logo=docker)](https://hub.docker.com/r/sriramiyer/pg-restic)
[![Image size](https://img.shields.io/docker/image-size/sriramiyer/pg-restic?sort=semver)](https://hub.docker.com/r/sriramiyer/pg-restic/tags)
[![GitHub stars](https://img.shields.io/github/stars/isriram/pg-restic?logo=github)](https://github.com/isriram/pg-restic)
[![License: MIT](https://img.shields.io/github/license/isriram/pg-restic)](https://github.com/isriram/pg-restic/blob/main/LICENSE)

**Image:** [sriramiyer/pg-restic on Docker Hub](https://hub.docker.com/r/sriramiyer/pg-restic) · **Source and issues:** [isriram/pg-restic on GitHub](https://github.com/isriram/pg-restic)

Back up Postgres to S3, B2 or any S3-compatible storage with restic. Encrypted, deduplicated snapshots in one Docker container.

On a cron schedule, pg-restic streams `pg_dumpall` straight into a [restic](https://restic.net) repository (nothing is written to local disk), then applies your retention policy.

- **Encrypted and deduplicated:** restic encrypts everything client-side, and hourly dumps of a mostly unchanged database take up very little extra space.
- **No broken snapshots:** if `pg_dumpall` fails, no snapshot is saved.
- **Small:** Alpine base with only `postgresql-client` and `restic`.
- **Self-initializing:** creates the restic repository on first run.

## Quick start

**1. Create a read-only Postgres user** (Postgres 14+):

```sql
CREATE ROLE backup LOGIN PASSWORD 'change-me';
GRANT pg_read_all_data TO backup;
```

**2. Create a `.env` file:**

```env
# Postgres
PGHOST=postgres          # container or host name of your Postgres server
PGUSER=backup
PGPASSWORD=change-me

# Storage
AWS_ACCESS_KEY_ID=your-key-id
AWS_SECRET_ACCESS_KEY=your-secret-key
RESTIC_REPOSITORY=s3:s3.us-east-005.backblazeb2.com/your-bucket

# Encryption password. Generate with `openssl rand -hex 32`.
# Store it somewhere safe: without it your backups cannot be restored.
RESTIC_PASSWORD=

# Schedule and retention
CRON_SCHEDULE=0 * * * *
RESTIC_KEEP_HOURLY=24
RESTIC_KEEP_DAILY=31
RESTIC_KEEP_MONTHLY=12
```

**3. Add the service to `compose.yaml`** on the same network as your database:

```yaml
services:
  pg-restic:
    image: sriramiyer/pg-restic:latest (or any version tag)
    container_name: pg-restic
    restart: unless-stopped
    env_file: .env
    networks:
      - data_net

networks:
  data_net:
    external: true
```

**4. Start it, and run a first backup to check your settings:**

```sh
docker compose up -d
docker compose run --rm pg-restic backup-now
docker logs -f pg-restic
```

## Configuration

| Variable                | Required | Default     | Description                                                                                                |
| ----------------------- | -------- | ----------- | ---------------------------------------------------------------------------------------------------------- |
| `PGHOST`                | Yes      |             | Postgres host name                                                                                         |
| `PGUSER`                | Yes      |             | Postgres user (see [Postgres permissions](#postgres-permissions))                                          |
| `PGPASSWORD`            | Yes      |             | Postgres password                                                                                          |
| `RESTIC_REPOSITORY`     | Yes      |             | Restic repository, e.g. `s3:s3.amazonaws.com/bucket`                                                       |
| `RESTIC_PASSWORD`       | Yes      |             | Repository encryption password                                                                             |
| `AWS_ACCESS_KEY_ID`     | For S3   |             | S3 access key (on B2: the application key ID)                                                              |
| `AWS_SECRET_ACCESS_KEY` | For S3   |             | S3 secret key (on B2: the application key)                                                                 |
| `CRON_SCHEDULE`         | No       | `0 * * * *` | When to back up, in [cron format](https://crontab.guru)                                                    |
| `RESTIC_KEEP_HOURLY`    | No       | `24`        | Hourly snapshots to keep                                                                                   |
| `RESTIC_KEEP_DAILY`     | No       | `31`        | Daily snapshots to keep                                                                                    |
| `RESTIC_KEEP_MONTHLY`   | No       | `12`        | Monthly snapshots to keep                                                                                  |
| `RESTIC_HOST`           | No       | `pg-restic` | Host name recorded on snapshots. Keep it fixed so retention keeps working when the container is recreated. |
| `TZ`                    | No       | `UTC`       | Time zone for `CRON_SCHEDULE`, e.g. `America/Toronto`                                                      |

Any other [restic environment variable](https://restic.readthedocs.io/en/stable/040_backup.html#environment-variables) is passed through too.

## Restoring

Run these on any machine with restic installed, using the same `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and storage credentials. You can also run them inside the container with `docker exec -it pg-restic sh`.

```sh
# List snapshots
restic snapshots

# Save the latest dump to a file
restic dump latest production.sql > production.sql

# Or restore straight into a Postgres server (requires a superuser)
restic dump latest production.sql | psql -h target-host -U postgres -d postgres
```

The dump is made with `pg_dumpall --clean`, so it drops and recreates databases and roles on the target. Restore into an empty or scratch server first if you're unsure.

**Test a restore before you rely on these backups.**

## Good to know

### Postgres permissions

`pg_dumpall` backs up every database plus roles. The user needs `pg_read_all_data` (Postgres 14+) or superuser.

### Postgres versions

The image ships `pg_dumpall` 18 and restic 0.19. `pg_dumpall` 18 can back up Postgres servers from 9.2 up to 18, but refuses to dump a newer server.

### Logs and failures

Backup output goes to `docker logs pg-restic`. A failed run logs `Database dump failed!` and saves no snapshot. Nothing alerts you to failures, so watch the logs or add your own monitoring.

### Overlapping runs

If a backup is still running when the next one is due, the new run is skipped.

## Building

```sh
docker build -t pg-restic .
```

Multi-architecture build:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t youruser/pg-restic:0.0.1 --push .
```

## License

MIT. See [LICENSE](https://github.com/isriram/pg-restic/blob/main/LICENSE).
