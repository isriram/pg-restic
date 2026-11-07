# Changelog

All notable changes to this image are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Updates to the bundled Postgres client are minor releases.

## [0.1.2] - 2026-11-06

### Changed

- Snapshots now store the dump as `all-databases.sql` instead of `production.sql`. Older snapshots keep the old name: restore them with `restic dump <snapshot-id> production.sql`. Retention treats them as a separate group, so they are no longer forgotten automatically. Once you no longer need them, preview with `restic forget --path /production.sql --unsafe-allow-remove-all --dry-run`, then run it without `--dry-run`, followed by `restic prune`. Only snapshots of `/production.sql` are removed. To keep some of them instead, use the usual `--keep-*` options in place of `--unsafe-allow-remove-all`.
- Prune now runs once a day on `PRUNE_SCHEDULE` instead of after every backup. Retention rules (`forget`) still apply after every backup.
- At startup, the repository is only initialized when restic reports that it doesn't exist. A wrong password, bad credentials or a network error now stops the container with restic's error instead of attempting `restic init`.

### Added

- `PRUNE_SCHEDULE` (default `30 3 * * *`).
- `PING_URL`: optional heartbeat URL visited after each successful backup.
- `PRUNE_PING_URL`: optional heartbeat URL visited after each successful prune.

### Fixed

- The README's compose example no longer puts a note inside the `image:` value.
