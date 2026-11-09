# pg-restic

[![Docker Hub](https://img.shields.io/docker/v/sriramiyer/pg-restic?sort=semver&label=docker%20hub&logo=docker)](https://hub.docker.com/r/sriramiyer/pg-restic)
[![Docker pulls](https://img.shields.io/docker/pulls/sriramiyer/pg-restic?logo=docker)](https://hub.docker.com/r/sriramiyer/pg-restic)
[![Image size](https://img.shields.io/docker/image-size/sriramiyer/pg-restic?sort=semver)](https://hub.docker.com/r/sriramiyer/pg-restic/tags)
[![GitHub stars](https://img.shields.io/github/stars/isriram/pg-restic?logo=github)](https://github.com/isriram/pg-restic)
[![License: MIT](https://img.shields.io/github/license/isriram/pg-restic)](https://github.com/isriram/pg-restic/blob/main/LICENSE)

**Image:** [sriramiyer/pg-restic on Docker Hub](https://hub.docker.com/r/sriramiyer/pg-restic) · **Source and issues:** [isriram/pg-restic on GitHub](https://github.com/isriram/pg-restic)

Back up Postgres to S3, B2 or any S3-compatible storage with restic. Encrypted, deduplicated snapshots in one Docker container.

On a cron schedule, pg-restic streams `pg_dumpall` straight into a [restic](https://restic.net) repository (nothing is written to local disk), then applies your retention policy. Once a day it prunes data no snapshot needs any more.

- **Encrypted and deduplicated:** restic encrypts everything client-side, and hourly dumps of a mostly unchanged database take up very little extra space.
- **No broken snapshots:** if `pg_dumpall` fails, no snapshot is saved.
- **Small:** Alpine base with only `postgresql-client` and `restic`.
- **Self-initializing:** creates the restic repository on first run.

## Why I built this

I needed Postgres backups at work and at home at the same time. I tried a few existing images, but after spending time setting them up, I found they shipped an older `pg_dump` that couldn't back up newer Postgres versions. So I built pg-restic.

I now run it in production at my workplace, as well as at home, so I'll keep it up to date. If it's useful to you too, a ⭐ would genuinely make my day. It's how I know someone else out there is relying on it.

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
    image: sriramiyer/pg-restic:latest  # or pin a version tag
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

| Variable                | Required | Default      | Description                                                                                                |
| ----------------------- | -------- | ------------ | ---------------------------------------------------------------------------------------------------------- |
| `PGHOST`                | Yes      |              | Postgres host name (not `localhost`, see [Postgres outside Docker](#postgres-outside-docker))              |
| `PGPORT`                | No       | `5432`       | Postgres port                                                                                              |
| `PGUSER`                | Yes      |              | Postgres user (see [Postgres permissions](#postgres-permissions))                                          |
| `PGPASSWORD`            | Yes      |              | Postgres password                                                                                          |
| `RESTIC_REPOSITORY`     | Yes      |              | Restic repository, e.g. `s3:s3.amazonaws.com/bucket` or `rest:http://host:8000/repo`                       |
| `RESTIC_PASSWORD`       | Yes      |              | Repository encryption password                                                                             |
| `AWS_ACCESS_KEY_ID`     | For S3   |              | S3 access key (on B2: the application key ID)                                                              |
| `AWS_SECRET_ACCESS_KEY` | For S3   |              | S3 secret key (on B2: the application key)                                                                 |
| `CRON_SCHEDULE`         | No       | `0 * * * *`  | When to back up, in [cron format](https://crontab.guru)                                                    |
| `RESTIC_KEEP_HOURLY`    | No       | `24`         | Hourly snapshots to keep                                                                                   |
| `RESTIC_KEEP_DAILY`     | No       | `31`         | Daily snapshots to keep                                                                                    |
| `RESTIC_KEEP_MONTHLY`   | No       | `12`         | Monthly snapshots to keep                                                                                  |
| `PRUNE_SCHEDULE`        | No       | `30 3 * * *` | When to free space from forgotten snapshots, in cron format                                                |
| `PING_URL`              | No       |              | URL visited after each successful backup (see [Logs and failures](#logs-and-failures))                     |
| `PRUNE_PING_URL`        | No       |              | URL visited after each successful prune                                                                    |
| `RESTIC_HOST`           | No       | `pg-restic`  | Host name recorded on snapshots. Keep it fixed so retention keeps working when the container is recreated. |
| `TZ`                    | No       | `UTC`        | Time zone for `CRON_SCHEDULE` and `PRUNE_SCHEDULE`, e.g. `America/Toronto`                                 |

Any other [restic environment variable](https://restic.readthedocs.io/en/stable/040_backup.html#environment-variables) is passed through too.

For [restic's REST server](https://github.com/restic/rest-server), pass its credentials in `RESTIC_REST_USERNAME` and `RESTIC_REST_PASSWORD` and leave out the AWS variables. Don't run the server with `--append-only`: backups still succeed, but retention is refused, so every run reports a failure and old snapshots are never removed.

## Restoring

Run these on any machine with restic installed, using the same `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and storage credentials. You can also run them inside the container with `docker exec -it pg-restic sh`.

```sh
# List snapshots
restic snapshots

# Save the latest dump to a file
restic dump latest all-databases.sql > all-databases.sql

# Or restore straight into a Postgres server (requires a superuser)
restic dump latest all-databases.sql | psql -h target-host -U postgres -d postgres
```

The dump is made with `pg_dumpall --clean`, so it drops and recreates databases and roles on the target. Restore into an empty or scratch server first if you're unsure.

**Test a restore before you rely on these backups.**

## Good to know

### Postgres outside Docker

`PGHOST=localhost` won't work: inside the container, `localhost` is the container itself. Use one of these instead.

**On the same machine (recommended):** set `PGHOST=host.docker.internal`. This works as is on Docker Desktop (Windows/Mac). On Linux, also add this to the service in `compose.yaml`:

```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Postgres must also accept connections from Docker, which by default it doesn't:

- In `postgresql.conf`, set `listen_addresses` to include the Docker bridge address, or `'*'`.
- In `pg_hba.conf`, allow the Docker subnet, for example `host  all  backup  172.16.0.0/12  scram-sha-256`.

**On the same machine, Linux only:** add `network_mode: host` to the service and remove its `networks:` section. `PGHOST=localhost` then works without changing the Postgres config, but the container is no longer network-isolated from the host.

**On another server:** set `PGHOST` to its hostname or IP.

### Postgres permissions

`pg_dumpall` backs up every database plus roles. The user needs `pg_read_all_data` (Postgres 14+) or superuser.

### Postgres versions

The image ships `pg_dumpall` 18 and restic 0.19. `pg_dumpall` 18 can back up Postgres servers from 9.2 up to 18, but refuses to dump a newer server.

### Logs and failures

Backup output goes to `docker logs pg-restic`. A failed run logs `Database dump failed!` and saves no snapshot.

To be alerted when backups stop, use a heartbeat monitor such as [healthchecks.io](https://healthchecks.io) or an [Uptime Kuma](https://github.com/louislam/uptime-kuma) push monitor. Create a check that expects a ping as often as `CRON_SCHEDULE` runs, and set its URL as `PING_URL`. pg-restic visits it after every successful backup, so a failed backup, a stopped container or a powered-off host all show up as a missed ping. Do the same with `PRUNE_PING_URL` and a daily check to hear about failed prunes. If the monitor can't be reached, pg-restic logs a warning and the backup still counts as successful.

### Upgrading from 0.0.x

Snapshots are now saved as `all-databases.sql` instead of `production.sql`, and prune runs daily instead of after every backup. See the [changelog](https://github.com/isriram/pg-restic/blob/main/CHANGELOG.md) for how to restore and clean up older snapshots.

### Overlapping runs

If a backup is still running when the next one is due, the new run is skipped.

## Building

```sh
docker build -t pg-restic .
```

Releasing (run `docker login` first, and update `CHANGELOG.md`):

```sh
scripts/release.sh                # patch: 0.1.1 -> 0.1.2
scripts/release.sh --bump minor   # 0.1.1 -> 0.2.0
scripts/release.sh --bump 1.0.0   # an exact version
```

In PowerShell, use `scripts\release.ps1`, `-Bump minor` or `-Bump 1.0.0`.

The script works out the next version from the latest `vX.Y.Z` git tag and asks before publishing. It checks that `main` is clean and pushed, builds for amd64 and arm64, pushes the `X.Y.Z` and `latest` tags to Docker Hub, and creates the `vX.Y.Z` git tag.

## Contributing

Found a bug or have an idea? [Open an issue](https://github.com/isriram/pg-restic/issues). Pull requests are welcome too: for anything larger than a small fix, open an issue first so we can agree on the approach.

## License

MIT. See [LICENSE](https://github.com/isriram/pg-restic/blob/main/LICENSE).
