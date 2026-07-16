# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v3.2.2] – 2026-06-29

### Fixed
- **Borg self-inclusion** — `BORG_REPO` is auto-excluded at runtime if missing from `EXCLUDE_DIRS`; `/UKwinikaBackup` added to the default exclude list in `ukwinika-backup.conf.example`.
- **Restore drill checksum verification** — backup now records SHA256 hashes of `RESTORE_VERIFY_PATHS` into the audit log; the restore drill fails if no matching entries exist.
- **Real-time backup storms** — real-time triggers now back up only `REAL_TIME_DIRS` (not full `BACKUP_PATHS`) with configurable debounce (`REAL_TIME_DEBOUNCE_SEC`, default 60s).
- **USB rsync safety** — validates mount point, rejects same-device-as-root mounts, and requires `USB_RSYNC_TARGET` to be inside `USB_MOUNT` before `rsync --delete`.
- **Prometheus metrics** — backup and restore scripts atomically rewrite a single metrics file (no duplicate blocks from append).
- **Config file permissions** — both scripts refuse to run if config/secrets files are not mode `600`/`400` and root-owned (skip with `UKW_SKIP_CONFIG_SECURITY=1` for CI).
- **Passphrase exposure** — `BORG_PASSPHRASE` is no longer exported globally; passed only to Borg via `run_borg()`.

### Changed
- **`ukwinika-realtime-backup.service`** — aligned systemd hardening with the daily backup unit (`ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`, etc.).
- **`ukwinika_automated_restore.sh`** bumped to v1.1.
- **CI** — added `shellcheck` static analysis for both main scripts (`.shellcheckrc` included).
- **Release workflow** — bumped `softprops/action-gh-release` to v3; release tarballs now include documentation (`*.md` no longer excluded).

---

## [v3.2.1] – 2026-06-18

### Added
- **`backuprestore/` folder** – groups the automated restore drill and its systemd units together in a dedicated directory for clarity. Contains:
  - **`ukwinika_automated_restore.sh` (v1.0)** — automated monthly restore drill script. Sources the same `UKW_CONFIG` and `UKW_SECRETS` as the backup script; no separate configuration required. Runs six independent verification checks (non-empty extraction, mandatory paths, minimum file count, SHA256 spot-check against the audit log, zero-byte file detection, archive metadata readability) and reports results via the existing Slack/email channels and four new Prometheus metrics. Exit code 0 = all checks passed; exit code 1 = one or more checks failed or a fatal error occurred.
  - **`ukwinika-restore-test.service`** — oneshot systemd service that executes `ukwinika_automated_restore.sh test`. Carries the same hardening profile as `ukwinika-backup.service` (`ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateTmp=true`, `Nice=19`, `IOSchedulingClass=idle`). Uses a separate lock file (`/var/lock/ukwinika-restore-test.lock`) so it never conflicts with a running backup.
  - **`ukwinika-restore-test.timer`** — fires on the 15th of each month at 02:30 ± 30 min. Offset from the daily backup timer (02:00) so the two never overlap. `Persistent=true` ensures a missed drill runs as soon as the system comes back online.
- **Five new restore-specific configuration variables** (all optional, added to `ukwinika-backup.conf`): `RESTORE_TARGET_BASE`, `RESTORE_VERIFY_PATHS`, `RESTORE_MIN_FILES`, `RESTORE_KEEP_ON_FAILURE`, `RESTORE_DRILL_LOG`.
- **Four new Prometheus metrics** written by the restore script and appended to the existing `PROMETHEUS_FILE`: `ukwinika_restore_test_last_run_seconds`, `ukwinika_restore_test_last_result` (1=pass/0=fail, archive label), `ukwinika_restore_test_checks_passed`, `ukwinika_restore_test_checks_failed`.
- **Dedicated restore log** at `/var/log/UKwinikaRestore.log` — restore drill output is written here in addition to the shared `/var/log/UKwinikaBackup.log`, so the full backup-and-verify timeline remains visible in one place.

### Changed
- **Makefile updated to v3.2.1** — `RESTORE_SCRIPT` now points to `backuprestore/ukwinika_automated_restore.sh`. The `systemd` target explicitly copies `backuprestore/ukwinika-restore-test.service` and `backuprestore/ukwinika-restore-test.timer` to `/etc/systemd/system/` in addition to the existing `systemd/*` units. The `clean` target now also removes `/var/log/UKwinikaRestore*.log` and calls `ukwinika_automated_restore.sh clean` to purge drill directories.
- **`install` target** installs `ukwinika_automated_restore.sh` from `backuprestore/` to `/usr/local/bin/` alongside the backup script.
- **`uninstall` target** removes both installed scripts.
- **README and documentation updated** — repository structure, feature list, setup steps, configuration reference, systemd table, Prometheus metrics section, and troubleshooting table all reflect the new `backuprestore/` folder and restore drill capability.

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
