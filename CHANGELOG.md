# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- **Full idempotency** – the entire backup, restore, and maintenance workflow is safe to run repeatedly without side effects.
- **Safe restore** – archives are now extracted using `borg extract --target` to a dedicated directory; live data is never overwritten unless explicitly chosen.
- **Dedicated secrets file** – sensitive values (`BORG_PASSPHRASE`, `SLACK_WEBHOOK`, `EMAIL_TO`) are stored exclusively in `/etc/ukwinika-backup.secrets` (mode 0600).
- **Strict database type validation** – unknown `DB_TYPE` values now cause an immediate abort, preventing silent data loss.
- **Stale lock prevention** – a cleanup trap removes the lock file on any exit (`EXIT`, `INT`, `TERM`), eliminating the risk of a stale lock blocking future runs.
- **New CLI commands** – `list` (show all archives) and `check` (verify repository integrity).
- **Configurable hook failure action** – `HOOK_FAIL_ACTION` can be set to `fatal` (abort) or `warn` (continue).
- **Audit checksum generation** – SHA256 checksums of every file in the repository are computed after each backup and stored in the audit log.
- **Prometheus metrics** now include the last success timestamp and the name of the most recent archive.
- **USB synchronisation** uses `rsync -a --delete` to guarantee an exact mirror of the primary repository on secondary media.
- **Exclude patterns** are now defined exclusively in the configuration file (array syntax), removing any ambiguity.
- **Backup paths** are configurable as an array (`BACKUP_PATHS`) instead of a fixed set of directories.

### Changed
- All repository-related variables consolidated to `BORG_REPO` for consistency.
- Real‑time monitoring now triggers the full backup cycle (not a separate incremental workflow), ensuring identical behaviour between scheduled and event‑driven backups.
- Notifications (Slack/email) are sent only after a successful backup, using the values in the secrets file.
- Systemd units receive the configuration and secrets paths via environment variables (`UKW_CONFIG` and `UKW_SECRETS`), eliminating hard‑coded file locations.
- Documentation completely rewritten to reflect the idempotent design, new commands, and configuration layout.

### Fixed
- Stale lock file that could persist after a crash or forced termination – now always removed.
- Restore logic that previously risked overwriting live data unintentionally – now always uses a dedicated target.
- Inconsistent variable naming for the backup destination, which could lead to confusion and misconfiguration.

---

## [v2.3] – 2026-04-21

### Added
- Full real‑time file monitoring using inotify.
- Complete restore logic with safe “drill” mode.
- Adaptive database dumps for MySQL, PostgreSQL, and Oracle.
- Optional LVM snapshots for hot database consistency.
- Pre‑ and post‑backup hook support.
- Prometheus metrics export.
- Removable USB auto‑detection.
- Concurrency locking with `flock`.
- Detailed audit trail including SHA256 checksums.
- Comprehensive documentation (`UKWINIKA-DOCUMENTATION.md`).

---

## [v2.2] – 2026-03-10

### Changed
- Improved Borg lock handling (`--max-lock-wait 300` + automatic stale lock breaker).
- Updated configuration example with new options.
- Enhanced systemd services with better I/O priority and restart behaviour.
- Expanded README.md with clear restore instructions and storage location.

### Fixed
- Stale lock issues during rapid backup attempts.
- Real‑time monitoring warnings.
- Missing environment variables from earlier versions.

---

## [v2.1] – 2026-02-01

### Added
- Automatic stale lock breaker.
- `--max-lock-wait 300` for Borg operations.
- Improved logging and error handling.

### Fixed
- Borg “unrecognized arguments: --encryption” error.

---

## [v2.0] – 2026-01-16

### Added
- Automatic installation of Borg and inotify-tools via Makefile.
- Debian compatibility fixes.

### Fixed
- Initial encryption flag issues on Debian.

---

## [v1.0] – 2025-10-01

### Initial Release
- Core Borg backup functionality.
- Systemd timer and services.
- Basic configuration and logging.

---

**Author:** Urayayi Kwinika  
**License:** MIT
