# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v3.2] – 2026-06-17

### Added
- **`DB_DUMP_DIR` config variable** – the temporary directory used for database dumps is now configurable (default `/tmp/ukwinika-db-dump`) instead of hardcoded, so it can be placed on a dedicated filesystem or tmpfs.
- **`CHECKSUM_FILE` config variable** – the path where post-backup SHA256 checksums are written is now configurable (default `/tmp/ukwinika-backup-checksums.txt`).
- **Failure notifications** – `die()` now calls `notify()` before exiting, so Slack and email alerts fire on backup failures, not only on success.
- **Auto-create Prometheus directory** – `push_metrics` now runs `mkdir -p "$(dirname "$PROMETHEUS_FILE")"` to create the metrics output directory if it does not exist, preventing silent write failures on fresh installs.
- **Config variable coverage test** – CI (`test.yml`) now asserts that every documented variable is present in `config/ukwinika-backup.conf.example`.

### Changed
- **Lightweight repository check** – `ensure_repo_exists` now uses a fast filesystem test (`-d $BORG_REPO && -f $BORG_REPO/config`) instead of running `borg check --info` on every subcommand invocation. The full integrity check remains available via `sudo enhanced_automated_backups.sh check`.
- **Real-time monitoring lock safety** – `real_time_mode` now releases the parent `flock` before invoking `"$0" backup` as a child process, and re-acquires it afterwards. This eliminates the deadlock that occurred when the child tried to acquire the same lock file descriptor already held by the monitoring loop.
- **Pruning flags simplified** – removed redundant `--keep-daily "$RETENTION_DAYS"` from `borg prune`; `--keep-within "${RETENTION_DAYS}d"` and `--keep-last "$RETENTION_VERSIONS"` fully express the retention intent without duplication.
- **`PROMETHEUS_FILE` used consistently** – `push_metrics` now always honours the `PROMETHEUS_FILE` config variable; there is no longer a risk of the function writing to a different path than what was configured.
- **Array default guarding** – `BACKUP_PATHS` and `EXCLUDE_DIRS` defaults are now set only when the variable is genuinely unset (`${VAR+x}` test), preventing the defaults from silently overwriting values provided by the config file.
- **CI workflow (`test.yml`) overhauled** – the test now initialises a real (temporary) Borg repository, runs `list` against it, and validates that all v3.2 config variables appear in `conf.example`. The minimal-config stub correctly wires `UKW_CONFIG` and `UKW_SECRETS`.
- **`release.yml` fixed** – `runs-on` previously used an invalid comma-separated string (`ubuntu-latest, debian-latest, redhat-latest`); it now correctly targets `ubuntu-latest` (the tarball is distribution-agnostic).
- **`dependabot.yml` fixed** – `version: 2.4` is not a valid Dependabot schema version; corrected to `version: 2`.
- **`SECURITY.md` rewritten** – the previous policy incorrectly marked all versions including `< 4.0` as fully supported. The policy now accurately reflects the current support status and describes a real vulnerability reporting and response process.
- **`config/ukwinika-backup.conf.example` updated** – added `DB_DUMP_DIR`, `CHECKSUM_FILE`, and an inline comment explaining that `PROMETHEUS_FILE`'s parent directory is created automatically.

### Fixed
- Deadlock in `real-time` mode when the child backup process attempted to acquire the lock held by the parent monitoring loop.
- Failure events were previously silent (no Slack/email alert sent); now `die()` always triggers a notification.
- `push_metrics` would fail silently if the Prometheus output directory did not yet exist.
- `borg prune` was applying `--keep-daily` and `--keep-within` for the same `RETENTION_DAYS` value, causing redundant and potentially confusing prune behaviour.

---

## [v3.1] – 2026-04-26

### Added
- **`init` subcommand** – initialises a new Borg repository idempotently (skips if already valid).
- **Repository existence check** – every backup, restore, list, check, and real‑time operation now verifies the repository exists before proceeding, providing a clear error if it is missing.

### Changed
- Real‑time systemd service now uses `Restart=on-failure` with `StartLimitBurst=3` and `StartLimitIntervalSec=60` to prevent log flooding and tight restart loops.

### Fixed
- Endless failure loop when the Borg repository was missing (the script now exits immediately instead of retrying indefinitely).
- Real‑time service no longer restarts endlessly after a configuration or repository error – it stops cleanly after three rapid failures.

---

## [v3.0] – 2026-04-24

### Added
- Full idempotency – the entire backup, restore, and maintenance workflow is safe to run repeatedly without side effects.
- Safe restore – archives are now extracted using `borg extract --target` to a dedicated directory; live data is never overwritten unless explicitly chosen.
- Dedicated secrets file – sensitive values (`BORG_PASSPHRASE`, `SLACK_WEBHOOK`, `EMAIL_TO`) are stored exclusively in `/etc/ukwinika-backup.secrets` (mode 0600).
- Strict database type validation – unknown `DB_TYPE` values now cause an immediate abort, preventing silent data loss.
- Stale lock prevention – a cleanup trap removes the lock file on any exit (`EXIT`, `INT`, `TERM`), eliminating the risk of a stale lock blocking future runs.
- New CLI commands – `list` (show all archives) and `check` (verify repository integrity).
- Configurable hook failure action – `HOOK_FAIL_ACTION` can be set to `fatal` (abort) or `warn` (continue).
- Audit checksum generation – SHA256 checksums of every file in the repository are computed after each backup and stored in the audit log.
- Prometheus metrics now include the last success timestamp and the name of the most recent archive.
- USB synchronisation uses `rsync -a --delete` to guarantee an exact mirror of the primary repository on secondary media.
- Exclude patterns are now defined exclusively in the configuration file (array syntax).
- Backup paths are configurable as an array (`BACKUP_PATHS`).

### Changed
- All repository-related variables consolidated to `BORG_REPO` for consistency.
- Real‑time monitoring now triggers the full backup cycle.
- Notifications (Slack/email) sent only after a successful backup.
- Systemd units receive config and secrets paths via environment variables.
- Documentation completely rewritten.

### Fixed
- Stale lock file that could persist after a crash.
- Restore logic that previously risked overwriting live data.
- Inconsistent variable naming for the backup destination.

---

## [v2.3] – 2026-04-21

### Added
- Full real‑time file monitoring using inotify.
- Complete restore logic with safe "drill" mode.
- Adaptive database dumps for MySQL, PostgreSQL, and MongoDB.
- Pre‑ and post‑backup hook support.
- Prometheus metrics export.
- Removable USB auto‑detection.
- Concurrency locking with `flock`.
- Detailed audit trail including SHA256 checksums.

---

## [v2.2] – 2026-03-10

### Changed
- Improved Borg lock handling.
- Enhanced systemd services with better I/O priority and restart behaviour.
- Expanded README.

### Fixed
- Stale lock issues during rapid backup attempts.
- Real‑time monitoring warnings.

---

## [v2.1] – 2026-02-01

### Added
- Automatic stale lock breaker.
- `--max-lock-wait 300` for Borg operations.

### Fixed
- Borg "unrecognized arguments: --encryption" error.

---

## [v2.0] – 2026-01-16

### Added
- Automatic installation of Borg and inotify-tools via Makefile.
- Debian compatibility fixes.

---

## [v1.0] – 2025-10-01

### Initial Release
- Core Borg backup functionality.
- Systemd timer and services.
- Basic configuration and logging.

---

**Author:** Urayayi Kwinika | **License:** MIT
