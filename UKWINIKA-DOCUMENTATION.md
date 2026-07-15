# UKwinika Enhanced Automated Backup Script (EABS)

**Version:** 3.2.2
**Author:** Urayayi Kwinika
**License:** MIT
**Date:** June 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [What's New in 3.2.2](#2-whats-new-in-322)
3. [Key Features](#3-key-features)
4. [The 3-2-1 Backup Principle](#4-the-3-2-1-backup-principle)
5. [Repository Structure](#5-repository-structure)
6. [Quick Start](#6-quick-start)
7. [Full Setup](#7-full-setup)
8. [Configuration Reference](#8-configuration-reference)
9. [Secrets File Reference](#9-secrets-file-reference)
10. [Backup Script Architecture](#10-backup-script-architecture)
11. [Backup CLI Reference](#11-backup-cli-reference)
12. [Database Dumps](#12-database-dumps)
13. [Hooks](#13-hooks)
14. [Real-Time Monitoring](#14-real-time-monitoring)
15. [Manual Restore and Drill Mode](#15-manual-restore-and-drill-mode)
16. [Automated Restore Drill](#16-automated-restore-drill)
17. [Locking and Idempotency](#17-locking-and-idempotency)
18. [Prometheus Metrics](#18-prometheus-metrics)
19. [Logging and Auditing](#19-logging-and-auditing)
20. [Notifications](#20-notifications)
21. [Security Considerations](#21-security-considerations)
22. [Systemd Integration](#22-systemd-integration)
23. [Log Rotation](#23-log-rotation)
24. [Troubleshooting](#24-troubleshooting)
25. [RHEL / Rocky / AlmaLinux Notes](#25-rhel--rocky--almalinux-notes)
26. [Upgrade Notes](#26-upgrade-notes)
27. [License](#27-license)

---

## 1. Overview

The UKwinika Enhanced Automated Backup Script (EABS) is a lightweight, open-source backup solution for Linux systems built on top of **BorgBackup**. It implements the industry-standard **3-2-1 backup principle** and adds real-time file monitoring, database-aware pre-backup dumps, AES-256 encryption, SHA256 audit trails, Prometheus metrics, and cloud upload support.

Version 3.2.1 adds the **UKwinika Automated Restore Script** (`ukwinika_automated_restore.sh`), which closes the backup lifecycle by automatically verifying that the most recent backup can actually be restored. Both scripts share the same configuration file, secrets file, log files, and notification channels.

The backup script is designed to be **fully idempotent** — it can be run any number of times without causing unintended changes, duplicate archives, stale locks, or overwritten live data. The restore drill script is **entirely non-destructive** — it never writes outside its dedicated drill directory.

**Supported distributions:** Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, CentOS Stream.

---

## 2. What's New in 3.2.2

- **Borg self-inclusion prevented** — `BORG_REPO` auto-excluded at runtime; `/UKwinikaBackup` in default `EXCLUDE_DIRS`.
- **Restore checksum verification fixed** — backup records SHA256 of `RESTORE_VERIFY_PATHS` files in the audit log.
- **Real-time scoped backups** — inotify triggers backup only `REAL_TIME_DIRS` with debounce (`REAL_TIME_DEBOUNCE_SEC`).
- **USB rsync guards** — mount validation, same-device-as-root rejection, target path checks before `--delete`.
- **Unified Prometheus writes** — single atomic metrics file (no append duplication).
- **Config permission enforcement** — root-owned mode `600`/`400` required (skip in CI with `UKW_SKIP_CONFIG_SECURITY=1`).
- **Passphrase scoping** — `BORG_PASSPHRASE` passed via `run_borg()` only, not exported globally.
- **Real-time systemd hardening** — aligned with daily backup service.

## 2.1 What's New in 3.2.1

- **`backuprestore/` folder** — the automated restore drill and its two systemd units now live in a dedicated folder, keeping restore-specific files separate from the backup systemd units in `systemd/`.
- **`ukwinika_automated_restore.sh` (v1.0)** — new script that automates the full restore verification workflow: full repository integrity check, disk space pre-flight, archive extraction, six independent verification checks, audit log entry, Prometheus metrics, and Slack/email notification. Exit code 0 = PASS, exit code 1 = FAIL.
- **`ukwinika-restore-test.service` and `.timer`** — two new systemd units that schedule the restore drill monthly on the 15th at 02:30, offset from the daily backup timer.
- **Makefile updated** — installs the restore script from `backuprestore/` and deploys its systemd units alongside the backup units.
- **Four new Prometheus metrics** for restore drill observability.
- **Dedicated restore log** at `/var/log/UKwinikaRestore.log`.

---

## 3. Key Features

- **Fully idempotent backup** — safe for repeated execution; no stale locks, no duplicate side effects.
- **3-2-1 backup** — primary on disk (Borg), secondary on removable USB (rsync mirror), tertiary to cloud (rclone).
- **BorgBackup** — deduplication, lz4 compression, AES-256 `repokey` encryption, mountable archives.
- **Multiple backup subcommands** — `backup`, `restore`, `list`, `check`, `real-time`, `init`.
- **Real-time monitoring** — inotify triggers scoped backups of `REAL_TIME_DIRS` only (with debounce), spawning a child process to avoid lock contention.
- **Database-aware** — adaptive dumps for MySQL, PostgreSQL, and MongoDB before each backup; unknown `DB_TYPE` values abort immediately.
- **Pre/post hooks** — custom executable scripts before and after the backup, with configurable failure behaviour.
- **Automated restore drill** — `ukwinika_automated_restore.sh` runs six checks against the most recent archive and reports pass/fail results without human interaction.
- **Shared configuration** — both scripts source the same `/etc/ukwinika-backup.conf` and `/etc/ukwinika-backup.secrets`; no separate config required for the restore script.
- **Failure notifications** — Slack and email alerts sent on both backup and restore drill success and failure.
- **Prometheus metrics** — six metrics covering both backup and restore drill state, all written to the same `.prom` file.
- **SHA256 audit trail** — checksums logged after every backup; used by the restore script for spot-check verification.
- **Separate locking** — backup and restore scripts use different lock files and never block each other.
- **Systemd-ready** — five units total; all carry hardening directives (`ProtectSystem=strict`, `NoNewPrivileges=true`).
- **Log rotation** — pre-configured logrotate snippet rotates all log files daily.
- **Cross-distribution** — Debian/Ubuntu and RHEL/Rocky/AlmaLinux/CentOS supported via the `Makefile`.

---

## 4. The 3-2-1 Backup Principle

| Copy | Location | Media | Trigger |
|------|----------|-------|---------|
| 1 (Primary) | `$BORG_REPO` (default `/UKwinikaBackup/borg-repo`) | System disk | Always |
| 2 (Secondary) | `$USB_RSYNC_TARGET` on a removable USB | External media | `USB_RSYNC_TARGET` is set and USB is mountable |
| 3 (Tertiary) | Cloud via rclone (`$CLOUD_REMOTE`) | Off-site | `CLOUD_REMOTE` is set and `rclone` is installed |

After every successful Borg archive the script mirrors the repository to USB using `rsync -a --delete` and uploads it to cloud via `rclone copy`. Cloud failures are logged as warnings; the backup is still considered successful if the primary and secondary copies completed.

---

## 5. Repository Structure

```
ukwinika-backups/
├── enhanced_automated_backups.sh          # Main backup script (v3.2)
├── Makefile                               # Install, deps, systemd, clean
├── README.md
├── CHANGELOG.md
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
├── config/
│   ├── ukwinika-backup.conf.example       # Non-sensitive configuration template
│   └── ukwinika-backup.secrets.example    # Sensitive credentials template
├── backuprestore/
│   ├── ukwinika_automated_restore.sh      # Automated monthly restore drill (v1.0)
│   ├── ukwinika-restore-test.service      # Systemd oneshot service for the drill
│   └── ukwinika-restore-test.timer        # Monthly timer (15th, 02:30 ± 30 min)
├── systemd/
│   ├── ukwinika-backup.service            # Oneshot backup service
│   ├── ukwinika-backup.timer              # Daily timer (02:00 ± 30 min)
│   └── ukwinika-realtime-backup.service   # inotify monitoring service
├── logrotate/
│   └── ukwinika-backup                    # Logrotate configuration
├── hooks/
│   ├── pre_backup_hook.sh.example
│   └── post_backup_hook.sh.example
└── docs/
    └── RESTORE-CHECKLIST.md               # Manual monthly restore drill checklist
```

---

## 6. Quick Start

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install        # Installs both scripts and dependencies
sudo make systemd        # Deploys all five systemd units and logrotate
```

Then follow the full setup below.

---

## 7. Full Setup

### Step 1 — Configure the secrets file

```bash
sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets
sudo chmod 600 /etc/ukwinika-backup.secrets
sudo nano /etc/ukwinika-backup.secrets
```

Set `BORG_PASSPHRASE` to a strong passphrase. Optionally add `SLACK_WEBHOOK` and `EMAIL_TO`. Both scripts read this file.

### Step 2 — Configure the main configuration file

```bash
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
sudo chmod 600 /etc/ukwinika-backup.conf
sudo nano /etc/ukwinika-backup.conf
```

Adjust paths, retention, USB mount point, database type, and hook locations as needed. See [Configuration Reference](#8-configuration-reference) for all options including the restore drill variables.

### Step 3 — Initialise the Borg repository

```bash
sudo enhanced_automated_backups.sh init
```

Creates the repository at `BORG_REPO` (default `/UKwinikaBackup/borg-repo`) using `repokey` encryption. Idempotent — running again on an existing valid repository does nothing.

### Step 4 — Deploy all systemd units

```bash
sudo make systemd
```

Installs all five units (daily backup timer, backup service, real-time monitoring service, monthly restore timer, restore service) and the logrotate configuration.

### Step 5 — Test a backup

```bash
sudo enhanced_automated_backups.sh backup
sudo tail -f /var/log/UKwinikaBackup.log
```

### Step 6 — Enable daily scheduled backups

```bash
sudo systemctl enable --now ukwinika-backup.timer
```

### Step 7 — Enable automated monthly restore drills

```bash
sudo systemctl enable --now ukwinika-restore-test.timer
```

Fires on the 15th of each month at 02:30. To run a drill immediately:

```bash
sudo systemctl start ukwinika-restore-test.service
# or directly:
sudo ukwinika_automated_restore.sh test
```

### Step 8 (optional) — Enable real-time monitoring

```bash
sudo systemctl enable --now ukwinika-realtime-backup.service
```

---

## 8. Configuration Reference

All non-sensitive settings live in `/etc/ukwinika-backup.conf` (overridable via `UKW_CONFIG`). Both the backup script and the restore script source this file.

### Backup variables

| Variable | Default | Description |
|---|---|---|
| `BORG_REPO` | `/UKwinikaBackup/borg-repo` | Primary Borg repository path |
| `BACKUP_PATHS` | `("/")` | Bash array of paths to include |
| `EXCLUDE_DIRS` | `("/proc" "/sys" "/dev" "/tmp" "/run" "/mnt" "/media" "/lost+found")` | Bash array of paths to exclude |
| `RETENTION_DAYS` | `90` | Keep all archives within this many days |
| `RETENTION_VERSIONS` | `5` | Minimum number of recent archives to keep |
| `USB_MOUNT` | `/mnt/backup_usb` | Mount point for secondary USB drive |
| `USB_RSYNC_TARGET` | _(empty)_ | Destination on USB; leave empty to skip |
| `CLOUD_REMOTE` | _(empty)_ | rclone remote + path; leave empty to skip |
| `DB_TYPE` | `none` | `none`, `mysql`, `postgresql`, or `mongodb` |
| `DB_DUMP_DIR` | `/tmp/ukwinika-db-dump` | Temporary directory for database dumps |
| `PRE_HOOK` | _(empty)_ | Executable script run before backup |
| `POST_HOOK` | _(empty)_ | Executable script run after backup |
| `HOOK_FAIL_ACTION` | `fatal` | `fatal` (abort) or `warn` (continue) on hook failure |
| `REAL_TIME_DIRS` | `("/etc" "/home")` | Directories watched by inotify |
| `EMAIL_TO` | _(empty)_ | Email address for notifications |
| `METRICS_ENABLED` | `yes` | Write Prometheus metrics (`yes` / `no`) |
| `PROMETHEUS_FILE` | `/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom` | Prometheus textfile output path |
| `CHECKSUM_FILE` | `/tmp/ukwinika-backup-checksums.txt` | Post-backup SHA256 checksum file path |

### Restore drill variables

| Variable | Default | Description |
|---|---|---|
| `RESTORE_TARGET_BASE` | `/var/lib/ukwinika/restore-drills` | Base directory for drill extractions |
| `RESTORE_VERIFY_PATHS` | `"etc/hostname etc/os-release etc/fstab"` | Space-separated relative paths that must exist in the restored data |
| `RESTORE_MIN_FILES` | `100` | Minimum file count the restore must contain |
| `RESTORE_KEEP_ON_FAILURE` | `yes` | Preserve the drill directory on failure for inspection |
| `RESTORE_DRILL_LOG` | `/var/log/UKwinikaRestore.log` | Dedicated restore drill log path |

> **Array syntax:** `BACKUP_PATHS` and `EXCLUDE_DIRS` must use proper bash array syntax: `BACKUP_PATHS=("/home" "/etc")`.

---

## 9. Secrets File Reference

All sensitive values live in `/etc/ukwinika-backup.secrets` (mode `0600`, overridable via `UKW_SECRETS`). Both scripts source this file.

| Variable | Required | Description |
|---|---|---|
| `BORG_PASSPHRASE` | **Yes** | Borg `repokey` passphrase. Both scripts abort if unset. |
| `SLACK_WEBHOOK` | No | Slack incoming webhook URL for backup and restore drill notifications |
| `EMAIL_TO` | No | Can be set here if the address is considered sensitive |

---

## 10. Backup Script Architecture

### Startup sequence

1. Load `$UKW_CONFIG` (abort if missing).
2. Load `$UKW_SECRETS` (skip if file absent, but `BORG_PASSPHRASE` must be set).
3. Pass `BORG_PASSPHRASE` to Borg subprocesses via `run_borg()` (not exported globally).
4. Validate config/secrets permissions (mode `600`/`400`, root-owned).
5. Auto-exclude `BORG_REPO` from backup paths if not already in `EXCLUDE_DIRS`.
6. Apply defaults for unset variables.
7. Acquire exclusive `flock` on `/var/lock/ukwinika-backup.lock`; exit cleanly if already locked.
8. Register `trap cleanup_lock EXIT INT TERM`.
9. Dispatch to the requested subcommand.

### `backup` call chain

```
pre-hook
  └─ db_dump()           → $DB_DUMP_DIR/
  └─ borg_backup()       → $BORG_REPO::<hostname>-<timestamp>
  └─ borg prune          → enforces retention policy
  └─ sync_to_usb()       → rsync -a --delete → USB
  └─ cloud_upload()      → rclone copy → cloud
  └─ audit_verify_path_checksums() → SHA256 of RESTORE_VERIFY_PATHS → AUDIT_LOG
  └─ audit_checksum()    → SHA256 of all repo files → $CHECKSUM_FILE + AUDIT_LOG
  └─ push_metrics()      → $PROMETHEUS_FILE
  └─ notify "SUCCESS"    → Slack + email
post-hook
```

On any `die()` call: `notify "FAILED: <reason>"` → exit 1.

### Archive naming

```
<hostname>-<YYYY-MM-DD_HH:MM:SS>
```

---

## 11. Backup CLI Reference

```
sudo enhanced_automated_backups.sh <subcommand> [arguments]
```

| Subcommand | Arguments | Description |
|---|---|---|
| `backup` | — | Full backup cycle (primary → USB → cloud) |
| `restore` | `<archive_name> [target_path]` | Extract archive. Default target: `/tmp/restore_<archive_name>` |
| `list` | — | List all archives in the repository |
| `check` | — | Run `borg check` for full integrity verification |
| `real-time` | — | Start inotify monitoring loop |
| `init` | — | Initialise a new Borg repository (idempotent) |

---

## 12. Database Dumps

Set `DB_TYPE` in the config file. The dump runs before `borg create` and is included in the archive automatically.

| `DB_TYPE` | Tool | Output |
|---|---|---|
| `none` | — | No dump |
| `mysql` | `mysqldump --all-databases --single-transaction` | `$DB_DUMP_DIR/mysql-all.sql` |
| `postgresql` | `pg_dumpall` as `postgres` user | `$DB_DUMP_DIR/postgresql-all.sql` |
| `mongodb` | `mongodump --out` | `$DB_DUMP_DIR/mongo/` |

Any unknown value causes an immediate abort. The dump directory is wiped and recreated on every run (idempotent).

---

## 13. Hooks

| Variable | Runs | Common use |
|---|---|---|
| `PRE_HOOK` | Before DB dump and `borg create` | Stop services, flush logs, take LVM snapshots |
| `POST_HOOK` | After notifications | Restart services, custom alerts, clean up snapshots |

Hooks must be executable files. Failure behaviour is controlled by `HOOK_FAIL_ACTION`:
- `fatal` (default) — calls `die()`, which sends a failure notification and exits.
- `warn` — logs a warning and continues.

---

## 14. Real-Time Monitoring

The `real-time` subcommand uses `inotifywait` to watch `REAL_TIME_DIRS`. After a debounce period (`REAL_TIME_DEBOUNCE_SEC`, default 60s), it triggers a **scoped** backup of only those directories (not full `BACKUP_PATHS`) in a child process.

**Lock safety:** the monitoring loop releases its `flock` before spawning the child, then re-acquires it after the child exits. This prevents the deadlock that would occur if the child tried to acquire the lock already held by the parent.

For production use, manage via systemd (`ukwinika-realtime-backup.service`). The service stops after three rapid failures to prevent log flooding.

---

## 15. Manual Restore and Drill Mode

### Safe restore

```bash
# Restore to /tmp/restore_<archive_name> (default — never touches live data)
sudo enhanced_automated_backups.sh restore <archive_name>

# Restore to a custom target
sudo enhanced_automated_backups.sh restore <archive_name> /mnt/restore-test
```

The extraction uses `(cd target && borg extract)` for Borg 1.2.x compatibility — running the same command again produces the same result.

### Manual drill checklist

For a guided step-by-step monthly drill see `docs/RESTORE-CHECKLIST.md`. For fully automated monthly verification, use `ukwinika_automated_restore.sh` (section 16).

---

## 16. Automated Restore Drill

`backuprestore/ukwinika_automated_restore.sh` automates the complete verification workflow without human interaction. It is installed to `/usr/local/bin/ukwinika_automated_restore.sh` and is designed for scheduled execution via systemd.

### Architecture

```
ensure_repo_exists()         → lightweight filesystem check (matches backup script)
preflight_repo_check()       → full borg check (appropriate for monthly depth)
preflight_disk_space()       → borg info → uncompressed size → df check (110% headroom)
resolve_archive()            → auto-select most recent, or validate named archive
extract_archive()            → borg extract --target $RESTORE_TARGET_BASE/<timestamp>_<archive>
  └─ verify_non_empty()                Check 1: extraction directory is non-empty
  └─ verify_mandatory_paths()          Check 2: RESTORE_VERIFY_PATHS all exist
  └─ verify_file_count()               Check 3: file count ≥ RESTORE_MIN_FILES
  └─ verify_checksums()                Check 4: SHA256 spot-check vs AUDIT_LOG
  └─ verify_no_zero_byte_files()       Check 5: no zero-byte files in /etc, /usr, /bin
  └─ verify_archive_metadata()         Check 6: borg info returns hostname + creation time
write_audit_entry()          → structured PASS/FAIL entry in AUDIT_LOG
push_restore_metrics()       → atomic rewrite of PROMETHEUS_FILE (backup + restore sections)
cleanup_drill_dir()          → remove on PASS; keep on FAIL if RESTORE_KEEP_ON_FAILURE=yes
notify_restore()             → "Restore Drill PASSED/FAILED on <hostname>"
```

All six checks run independently — a failed check is counted and logged but does not abort the remaining checks. The overall result is PASS only if every check passes.

### Drill directory naming

```
$RESTORE_TARGET_BASE/<YYYY-MM-DD_HH-MM-SS>_<archive_name>/
```

Example: `/var/lib/ukwinika/restore-drills/2026-06-15_02-30-12_debian-2026-06-14_02:00:33/`

### Restore drill CLI reference

```
sudo ukwinika_automated_restore.sh <subcommand> [arguments]
```

| Subcommand | Arguments | Description |
|---|---|---|
| `test` | `[archive_name]` | Run drill against most recent archive, or a named one. Default when called with no arguments. |
| `list` | — | List all archives in the repository |
| `clean` | — | Remove all drill directories under `RESTORE_TARGET_BASE` |

### Lock file

The restore script uses `/var/lock/ukwinika-restore-test.lock`, separate from the backup script's `/var/lock/ukwinika-backup.lock`. The two scripts never block each other.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All verification checks passed |
| `1` | One or more checks failed, or a fatal pre-flight error occurred |

---

## 17. Locking and Idempotency

### Lock files

| Script | Lock file |
|---|---|
| `enhanced_automated_backups.sh` | `/var/lock/ukwinika-backup.lock` |
| `ukwinika_automated_restore.sh` | `/var/lock/ukwinika-restore-test.lock` |

Each script uses `flock -n` and a `trap cleanup_lock EXIT INT TERM` to release and remove its lock file on any exit. The two locks are independent — a running backup does not block a restore drill and vice versa.

### Idempotency guarantees

| Operation | How it is idempotent |
|---|---|
| `borg create` | Deduplication stores only new data |
| `borg prune` | Retention policy is re-applied on every run without accumulating side effects |
| USB rsync | `rsync -a --delete` makes the destination an exact mirror; re-running transfers only deltas |
| DB dump | Dump directory wiped and recreated on every run |
| Restore | `borg extract --target` overwrites the target consistently |
| `init` | Checks for existing valid repository before creating |
| Prometheus metrics | `.prom` file atomically rewritten with backup and restore sections on each run |
| Restore drill | Drill directory name includes timestamp; each run creates a fresh directory |

---

## 18. Prometheus Metrics

When `METRICS_ENABLED=yes`, both scripts atomically rewrite `PROMETHEUS_FILE` with all six metrics so Node Exporter always sees a consistent file.

```
--collector.textfile.directory=/var/lib/prometheus/node_exporter/custom
```

| Metric | Type | Written by | Description |
|---|---|---|---|
| `ukwinika_backup_last_success_seconds` | gauge | Backup | Unix timestamp of the last successful backup |
| `ukwinika_backup_latest_archive` | gauge (name label) | Backup | Name of the most recent archive |
| `ukwinika_restore_test_last_run_seconds` | gauge | Restore | Unix timestamp of the last restore drill |
| `ukwinika_restore_test_last_result` | gauge (archive label) | Restore | 1 = all checks passed, 0 = one or more failed |
| `ukwinika_restore_test_checks_passed` | gauge | Restore | Number of checks that passed in the last drill |
| `ukwinika_restore_test_checks_failed` | gauge | Restore | Number of checks that failed in the last drill |

**Recommended alert rules:**
- `time() - ukwinika_backup_last_success_seconds > 86400` — no successful backup in 24 hours.
- `ukwinika_restore_test_last_result == 0` — the most recent restore drill failed.
- `time() - ukwinika_restore_test_last_run_seconds > 2678400` — no restore drill in 31 days.

---

## 19. Logging and Auditing

| File | Written by | Content | Rotation |
|---|---|---|---|
| `/var/log/UKwinikaBackup.log` | Both scripts | Timestamped INFO and FATAL messages | Daily, 14 rotations |
| `/var/log/UKwinikaBackup_audit.log` | Both scripts | Structured audit entries; SHA256 of `RESTORE_VERIFY_PATHS` at backup time; repo checksum file reference; drill PASS/FAIL entries | Daily, 14 rotations |
| `/var/log/UKwinikaRestore.log` | Restore script only | Full restore drill output (also tee'd to UKwinikaBackup.log) | Daily, 14 rotations |

Both scripts use the same `log()` format so all events appear in a single chronological timeline in `/var/log/UKwinikaBackup.log`.

Restore drill audit entry format:

```
2026-06-15 02:31:44 [AUDIT] RESTORE DRILL PASS — archive: debian-2026-06-14_02:00:33 | checks passed: 6 | checks failed: 0 | drill dir: /var/lib/ukwinika/restore-drills/2026-06-15_02-30-12_debian-2026-06-14_02:00:33
```

---

## 20. Notifications

Both scripts call `notify()` / `notify_restore()` on success and failure. Both use the same `SLACK_WEBHOOK` and `EMAIL_TO` from the secrets/config file. Both channels fail silently — a broken webhook never prevents a backup or drill from running.

| Event | Slack message | Email subject |
|---|---|---|
| Backup success | `Backup SUCCESS on <hostname>` | `UKwinika Backup SUCCESS` |
| Backup failure | `Backup FAILED: <reason> on <hostname>` | `UKwinika Backup FAILED: <reason>` |
| Restore drill pass | `Restore Drill PASSED on <hostname> — archive: <name>` | `UKwinika Restore Drill PASSED` |
| Restore drill fail | `Restore Drill FAILED — <n> check(s) did not pass on <hostname>` | `UKwinika Restore Drill FAILED` |

The restore drill failure email also includes the check counts and the drill directory path.

---

## 21. Security Considerations

- `BORG_PASSPHRASE` and webhook URLs are stored exclusively in `/etc/ukwinika-backup.secrets` (mode `0600`). The passphrase is passed to Borg subprocesses only via `run_borg()`.
- Config and secrets files must be mode `600` or `400` and owned by root; both scripts enforce this at startup (`UKW_SKIP_CONFIG_SECURITY=1` for CI/dev only).
- Always exclude the Borg repository from backup paths (`/UKwinikaBackup` in default excludes; auto-excluded at runtime).
- Borg uses `repokey` encryption (AES-256). **Never lose the passphrase or repository key.** Export with `borg key export` and store separately.
- Both scripts use `flock` and `set -euo pipefail`. Separate lock files mean neither blocks the other.
- Restrict both scripts: `chmod 700 /usr/local/bin/enhanced_automated_backups.sh /usr/local/bin/ukwinika_automated_restore.sh`.
- The restore script is **entirely non-destructive** — it never writes outside `RESTORE_TARGET_BASE`. Live data is physically unreachable from the drill.
- All five systemd units carry `ProtectSystem=strict`, `NoNewPrivileges=true`, `PrivateTmp=true`, and explicit `ReadWritePaths=` so the operating system enforces the write boundaries at the kernel level.
- For immutable off-site protection, configure object storage with versioning and deletion protection (e.g. AWS S3 Object Lock).

---

## 22. Systemd Integration

Five units are provided across two directories:

### Backup units (`systemd/`)

**`ukwinika-backup.service`** — oneshot service. Runs `backup`. `Nice=19`, `IOSchedulingClass=idle`, `PrivateTmp=true`, `ProtectSystem=strict`.

**`ukwinika-backup.timer`** — fires daily at 02:00 ± 30 min. `Persistent=true` catches missed runs.

**`ukwinika-realtime-backup.service`** — simple service. Runs `real-time`. Same hardening as backup service (`ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges`). Restarts on failure; stops after three rapid failures (`StartLimitBurst=3`, `StartLimitIntervalSec=60`).

### Restore drill units (`backuprestore/`)

**`ukwinika-restore-test.service`** — oneshot service. Runs `ukwinika_automated_restore.sh test`. Same hardening profile as the backup service. `ReadWritePaths` includes `/var/lib/ukwinika` for the drill directory base.

**`ukwinika-restore-test.timer`** — fires on the 15th of each month at 02:30 ± 30 min. `Persistent=true`. Offset from the backup timer so the two never overlap.

### Useful systemd commands

```bash
# Check next scheduled backup
systemctl list-timers ukwinika-backup.timer

# Check next scheduled restore drill
systemctl list-timers ukwinika-restore-test.timer

# Run a backup now
systemctl start ukwinika-backup.service

# Run a restore drill now
systemctl start ukwinika-restore-test.service

# Watch backup log live
journalctl -u ukwinika-backup.service -f

# Watch restore drill log live
journalctl -u ukwinika-restore-test.service -f

# Check real-time monitoring status
systemctl status ukwinika-realtime-backup.service

# Reset a failed restore drill service before retrying
systemctl reset-failed ukwinika-restore-test.service
```

---

## 23. Log Rotation

The logrotate configuration (`logrotate/ukwinika-backup`) rotates all three log files daily, keeping 14 compressed copies.

```
/var/log/UKwinikaBackup.log
/var/log/UKwinikaBackup_audit.log
/var/log/UKwinikaRestore.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        if [ -f /run/rsyslogd.pid ]; then
            kill -HUP "$(cat /run/rsyslogd.pid 2>/dev/null)" 2>/dev/null || true
        fi
    endscript
}
```

Installed to `/etc/logrotate.d/ukwinika-backup` by `sudo make systemd`.

> **Note:** Add `/var/log/UKwinikaRestore.log` to the logrotate configuration block if it is not already present after upgrading from v3.2 to v3.2.1.

---

## 24. Troubleshooting

| Symptom | Likely cause | Solution |
|---|---|---|
| `Repository not found at /UKwinikaBackup/borg-repo` | Repository never initialised | `sudo enhanced_automated_backups.sh init` |
| `BORG_PASSPHRASE is not set` | Secrets file missing, wrong path, or wrong permissions | Ensure `/etc/ukwinika-backup.secrets` exists, mode `0600`, contains `BORG_PASSPHRASE=...` |
| `borg create failed` | Disk full, passphrase mismatch, or corruption | Check logs; run `sudo enhanced_automated_backups.sh check` |
| Real-time monitoring not starting | `inotify-tools` missing | `sudo make install` |
| `MySQL dump failed` | Missing credentials | Create `/root/.my.cnf` with valid credentials |
| `Failed to mount USB` | USB not connected or bad `/etc/fstab` entry | Verify device and `USB_MOUNT` value |
| `Another backup instance is already running` | Stale lock after `kill -9` | `rm -f /var/lock/ukwinika-backup.lock` |
| `Another restore drill is already running` | Stale restore lock | `rm -f /var/lock/ukwinika-restore-test.lock` |
| Restore drill `[FAIL] Non-empty` | Extraction produced no output | Run `sudo enhanced_automated_backups.sh check`; re-run backup |
| Restore drill `[FAIL] Too few files` | Partial extraction or overly strict `RESTORE_MIN_FILES` | Inspect preserved drill directory; adjust `RESTORE_MIN_FILES` if threshold is wrong |
| Restore drill `[FAIL] Mandatory paths missing` | Paths in `RESTORE_VERIFY_PATHS` not included in `BACKUP_PATHS` | Review `BACKUP_PATHS` and `EXCLUDE_DIRS` in config |
| Restore drill `[FAIL] Checksum mismatch` | Possible data integrity concern | Run `sudo enhanced_automated_backups.sh check`; examine audit log for details |
| Restore drill `[FAIL] Zero-byte files` | Incomplete archive; interrupted backup | Run a fresh backup; run `check`; inspect the drill directory |
| Restore drill `[FAIL] Archive metadata` | `borg info` error; repository structural issue | Run `sudo enhanced_automated_backups.sh check` |
| Drill directory not removed after PASS | Unexpected — PASS always removes the directory | Check `/var/log/UKwinikaRestore.log` for errors during cleanup |
| Drill directory not removed after FAIL | `RESTORE_KEEP_ON_FAILURE=yes` (default) | This is correct; inspect the directory, then remove manually or set `RESTORE_KEEP_ON_FAILURE=no` |
| Prometheus metrics not showing restore data | `METRICS_ENABLED=no` or wrong `PROMETHEUS_FILE` | Verify config; parent directory is created automatically |
| Restore drill Slack/email not received | `SLACK_WEBHOOK` / `EMAIL_TO` not set | Add to `/etc/ukwinika-backup.secrets` |

---

## 25. RHEL / Rocky / AlmaLinux Notes

- The `Makefile` detects RHEL-based systems and automatically enables the **EPEL** repository before installing `borgbackup`, `inotify-tools`, `rsync`, and `mailx` via `dnf`.
- RHEL proper requires a valid subscription. Rocky Linux and AlmaLinux work without one.
- The Prometheus textfile directory (`/var/lib/prometheus/node_exporter/custom`) may need to be created manually if Node Exporter is installed in a non-standard location. Both scripts create it automatically via `mkdir -p`.
- The restore drill directory base (`/var/lib/ukwinika/restore-drills`) is created automatically on first run.
- SELinux: if you encounter permission denials on the drill directory or log files, add a custom policy or temporarily use permissive mode for testing.

---

## 26. Upgrade Notes

### From 3.2.1 to 3.2.2

1. Replace `enhanced_automated_backups.sh` and `backuprestore/ukwinika_automated_restore.sh` with the v3.2.2 versions.
2. Run `sudo make install && sudo make systemd` to redeploy scripts and the updated `ukwinika-realtime-backup.service`.
3. Add `/UKwinikaBackup` to `EXCLUDE_DIRS` in `/etc/ukwinika-backup.conf` if not already present (auto-excluded at runtime regardless).
4. Optionally set `REAL_TIME_DEBOUNCE_SEC=60` (default) in config.
5. Ensure `/etc/ukwinika-backup.conf` and `/etc/ukwinika-backup.secrets` are mode `600` and owned by root.
6. No passphrase or repository changes required.

### From 3.2 to 3.2.1

1. Add `backuprestore/` to your working copy (clone or download the v3.2.1 tarball).
2. Run `sudo make install` — installs `ukwinika_automated_restore.sh` to `/usr/local/bin/`.
3. Run `sudo make systemd` — deploys `ukwinika-restore-test.service` and `ukwinika-restore-test.timer` to `/etc/systemd/system/`.
4. Enable the monthly timer: `sudo systemctl enable --now ukwinika-restore-test.timer`.
5. Optionally add restore drill variables to `/etc/ukwinika-backup.conf` (all have sensible defaults; no change is required for basic use).
6. Optionally add `/var/log/UKwinikaRestore.log` to the logrotate configuration block.
7. No changes to `enhanced_automated_backups.sh` itself — the backup script is unchanged from v3.2.

### From 3.1 to 3.2

1. Replace `enhanced_automated_backups.sh` with the v3.2 version.
2. Review `DB_DUMP_DIR` and `CHECKSUM_FILE` — they now respect config values. Leave unset to retain `/tmp` defaults.
3. `ensure_repo_exists` no longer runs a full `borg check` on every invocation. Add an explicit `check` call to any automation that relied on the old behaviour.
4. Real-time monitoring now spawns child processes — child backup PIDs differ from the parent monitoring loop PID.
5. No configuration file changes are required.

---

## 27. License

MIT License — Copyright (c) 2026 Urayayi Kwinika.
See the `LICENSE` file for the full text.

---

> **UKwinika Notable Advice: A Backup is Only as Good as its Last Successful Restore. Test Monthly.**
