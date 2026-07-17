# UKwinika Enhanced Automated Backup Script

**Version:** 3.3.0
**Author:** Urayayi Kwinika
**Date:** July 2026
**License:** MIT

---

## Table of Contents

1. [Overview](#1-overview)
2. [What's New in 3.3.0](#2-whats-new-in-330)
   - 2.1 [What's New in 3.2.2](#21-whats-new-in-322)
   - 2.2 [What's New in 3.2.1](#22-whats-new-in-321)
3. [Key Features](#3-key-features)
4. [The 3‑2‑1 Backup Principle](#4-the-321-backup-principle)
5. [Repository Structure](#5-repository-structure)
6. [Script Architecture](#6-script-architecture)
7. [Configuration Reference](#7-configuration-reference)
8. [Setup and Installation](#8-setup-and-installation)
9. [Database Dumps](#9-database-dumps)
10. [Filesystem Consistency (LVM Snapshot Hooks)](#10-filesystem-consistency-lvm-snapshot-hooks)
11. [Hooks](#11-hooks)
12. [Scheduled Consistency Checks](#12-scheduled-consistency-checks)
13. [Automated Restore Drills](#13-automated-restore-drills)
14. [Disaster Recovery](#14-disaster-recovery)
15. [Prometheus Metrics and Alerting](#15-prometheus-metrics-and-alerting)
16. [Logging and Auditing](#16-logging-and-auditing)
17. [Locking, Retries, and Idempotency Guarantees](#17-locking-retries-and-idempotency-guarantees)
18. [Security Considerations](#18-security-considerations)
19. [Troubleshooting](#19-troubleshooting)
20. [RHEL / Rocky / AlmaLinux Specific Notes](#20-rhel--rocky--almalinux-specific-notes)
21. [Upgrade Notes](#21-upgrade-notes)
22. [License](#22-license)

---

## 1. Overview

The UKwinika Enhanced Automated Backup Script (EABS) is a lightweight, open-source backup solution for Linux systems, built around **BorgBackup**, implementing the industry-standard **3‑2‑1 Backup Principle**. It adds real-time file monitoring, database-aware dumps, encryption, auditing, Prometheus metrics and alerting, automated restore drills, and — as of v3.3.0 — configuration validation, dry-run simulation, minimum-version enforcement, retry/backoff for transient failures, scheduled consistency checks, filesystem-consistency hooks, and a dedicated disaster-recovery runbook.

The project consists of two cooperating scripts sharing configuration, secrets, logs, and notification channels:

- **`enhanced_automated_backups.sh`** — the main backup/restore/validate/check engine.
- **`backuprestore/ukwinika_automated_restore.sh`** — an independent automated restore-drill script that verifies the most recent backup is genuinely restorable, on a schedule.

**Supported distributions:** Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, CentOS Stream.

---

## 2. What's New in 3.3.0

This release focused on closing gaps identified in a systems-administrator and Linux-programmer review of v3.2.2: a confirmed logic bug, full ShellCheck cleanliness, and several production-hardening features modeled on `borgmatic`.

### Fixed
- **`validate_usb_target()` dead-code bug.** The success branch of a `case` statement previously `return`ed immediately, which meant the directory auto-creation logic for `USB_RSYNC_TARGET` could never execute (confirmed via ShellCheck SC2317). Restructured so the containment check and the directory creation both run correctly.
- **ShellCheck now passes with zero findings** on both scripts (previously SC2015, SC2024, and four SC2317 findings on the main script).

### Added
- **`MIN_BORG_VERSION` enforcement** — the script refuses to run against an installed `borg` older than the configured minimum (default `1.2.0`), rather than failing confusingly partway through an operation.
- **Retry/backoff** for USB mount (`USB_RETRY_ATTEMPTS`, `USB_RETRY_DELAY_SEC`) and cloud upload (`CLOUD_RETRY_ATTEMPTS`, `CLOUD_RETRY_DELAY_SEC`).
- **`validate` subcommand** — configuration validation with zero side effects.
- **`backup --dry-run`** — full backup simulation (`borg create --dry-run`) with no archive written and no prune/USB/cloud/metrics/notification side effects.
- **`check-if-due` subcommand** and `ukwinika-check.timer`/`.service` — borgmatic-style due-date tracking for `borg check`, avoiding an expensive full scan on every run.
- **LVM snapshot hook examples** (`hooks/lvm_snapshot_pre_backup_hook.sh.example`, `hooks/lvm_snapshot_post_backup_hook.sh.example`) for point-in-time filesystem consistency.
- **`docs/DISASTER-RECOVERY.md`** — a full bare-metal / total-host-loss recovery runbook.
- **`prometheus/ukwinika-backup-alerts.yml`** — ready-to-use alerting rules for stale backups, missing metrics, and failed/stale restore drills.

See `CHANGELOG.md` for the complete, itemised entry.

## 2.1 What's New in 3.2.2

Hardening pass focused on lock-contention correctness in real-time mode, USB target containment validation, and repository-existence checks that avoid a full `borg check` on every invocation.

## 2.2 What's New in 3.2.1

Introduced the **UKwinika Automated Restore Script** (`ukwinika_automated_restore.sh`), which closes the backup lifecycle by automatically verifying that the most recent backup can actually be restored. Both scripts share the same configuration file, secrets file, log files, and notification channels.

---

## 3. Key Features

- **Fully idempotent** — safe for repeated execution; no stale locks, no duplicate side effects.
- **3‑2‑1 backup** — primary on disk, secondary on removable USB, tertiary to cloud (rclone), each independently optional.
- **BorgBackup** — deduplication, compression (lz4), AES‑256 encryption (`repokey`), mountable archives, minimum-version enforcement.
- **Multiple modes** — `backup [--dry-run]`, `restore`, `list`, `check`, `check-if-due`, `validate`, `real-time`, `init`.
- **Real-time monitoring** — inotify-triggered incremental backups, debounced and lock-contention-safe.
- **Database-aware** — dumps MySQL, PostgreSQL, MongoDB before each backup; strict `DB_TYPE` validation.
- **Filesystem-consistent** — optional LVM snapshot hooks for point-in-time consistency beyond DB dumps.
- **Pre/post hooks** — configurable fatal/warn failure handling.
- **Retry/backoff** — transient USB and cloud failures no longer fail the whole backup.
- **Automated restore drills** — six independent verification checks, scheduled monthly.
- **Scheduled consistency checks** — due-date-tracked `borg check`, not run on every backup.
- **Prometheus metrics + alerting rules** — backup and restore-drill health, with rules that actually page someone.
- **Audit trail** — SHA256 checksums logged after every backup and cross-checked during restores.
- **Config/secrets security validation** — refuses to run on incorrectly permissioned files.
- **Systemd integration** — hardened timer, on-demand service, real-time service, restore-drill service, consistency-check service.
- **Log rotation** — pre-configured logrotate snippet covering all three log streams.

---

## 4. The 3‑2‑1 Backup Principle

| Copy | Location | Media Type | Trigger |
|------|----------|------------|---------|
| 1 | `BORG_REPO` (default `/UKwinikaBackup/borg-repo`) | System disk | Always (primary) |
| 2 | Removable USB (`USB_RSYNC_TARGET`) | External media | USB mounted, retried on transient failure |
| 3 | Cloud (`rclone`, `CLOUD_REMOTE`) | Off-site | Configured, retried on transient failure |

After each successful Borg backup, the script mirrors the repository to USB with `rsync -a --delete` and, if configured, uploads to cloud storage with `rclone copy`. Both steps use configurable retry/backoff before giving up; a cloud-upload failure does not fail the overall backup, since the local and USB copies are already safe by that point.

---

## 5. Repository Structure

```
ukwinika-backups/
├── README.md
├── UKWINIKA-DOCUMENTATION.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
├── .shellcheckrc
├── Makefile
├── enhanced_automated_backups.sh
├── config/
│   ├── ukwinika-backup.conf.example
│   └── ukwinika-backup.secrets.example
├── systemd/
│   ├── ukwinika-backup.service
│   ├── ukwinika-backup.timer
│   ├── ukwinika-realtime-backup.service
│   ├── ukwinika-check.service
│   └── ukwinika-check.timer
├── backuprestore/
│   ├── ukwinika_automated_restore.sh
│   ├── ukwinika-restore-test.service
│   └── ukwinika-restore-test.timer
├── hooks/
│   ├── pre_backup_hook.sh.example
│   ├── post_backup_hook.sh.example
│   ├── lvm_snapshot_pre_backup_hook.sh.example
│   └── lvm_snapshot_post_backup_hook.sh.example
├── prometheus/
│   └── ukwinika-backup-alerts.yml
├── logrotate/
│   └── ukwinika-backup
├── docs/
│   ├── RESTORE-CHECKLIST.md
│   └── DISASTER-RECOVERY.md
└── .github/
    ├── dependabot.yml
    └── workflows/
        ├── release.yml
        └── test.yml
```

---

## 6. Script Architecture

### 6.1 Invocation

```
enhanced_automated_backups.sh <mode> [arguments]
```

| Mode | Description | Extra Arguments |
|------|-------------|------------------|
| `validate` | Validate configuration, secrets, `DB_TYPE`, and borg version. No side effects. | None |
| `backup` | Full backup cycle (primary + USB + cloud) | `--dry-run` (optional) |
| `restore` | Restore an archive to a target directory | `<archive_name>` `<target_path>` (target optional) |
| `list` | List all archives in the repository | None |
| `check` | Force a full repository integrity check now | None |
| `check-if-due` | Run a full check only if `CHECK_INTERVAL_DAYS` has elapsed | None |
| `real-time` | Start inotify-based monitoring loop | None |
| `init` | Initialise a new Borg repository | None |

Every mode except `validate` (and the bare usage message) enforces `MIN_BORG_VERSION` before proceeding. `backup`, `restore`, `list`, `check`, `check-if-due`, and `real-time` additionally require the repository to already exist (`init` first) — otherwise they fail with a clear, actionable error.

### 6.2 Workflow — `backup` mode

1. Acquire an exclusive lock (`flock`) — if already locked, the script exits cleanly.
2. Run the **pre-hook** (if executable) — e.g. an LVM snapshot creation hook.
3. Perform a **database dump** (if `DB_TYPE` is not `none`), written fresh to `DB_DUMP_DIR` each run.
4. Create a **Borg archive** (or simulate one, with `--dry-run`) named `<hostname>-<YYYY-MM-DD_HH:MM:SS>`.
5. In dry-run mode, stop here — no prune, no USB/cloud sync, no metrics, no notification.
6. **Prune** old archives per `RETENTION_DAYS` / `RETENTION_VERSIONS`.
7. **Verify restore-critical checksums** for the paths in `RESTORE_VERIFY_PATHS`.
8. **Sync to USB** — mount (retried per `USB_RETRY_ATTEMPTS`/`USB_RETRY_DELAY_SEC`), `rsync -a --delete`, unmount.
9. **Upload to cloud** — `rclone copy` (retried per `CLOUD_RETRY_ATTEMPTS`/`CLOUD_RETRY_DELAY_SEC`); failure here is a warning, not a fatal error.
10. Generate an **audit checksum** file of all repository objects.
11. Update **Prometheus metrics**.
12. Send **notifications** (Slack/email) on success — and on failure, via `die()`.
13. Run the **post-hook** (if executable) — e.g. LVM snapshot cleanup.
14. Release the lock (trap removes the lock file on any exit).

### 6.3 Real-Time Monitoring (`real-time`)

Uses `inotifywait` to watch directories in `REAL_TIME_DIRS`. On a change, the script debounces briefly, releases its own lock, spawns a child `"$0" backup` (which acquires its own lock independently), and waits for it to finish before resuming the watch loop. The systemd unit restarts on failure but stops after three rapid failures.

### 6.4 Restore Mode (`restore`)

- **Drill / safe restore:** by default, extracts to `/tmp/restore_<archive_name>`; a custom target may be given.
- Uses a `(cd "$target" && borg extract REPO::ARCHIVE)` subshell — **not** `borg extract --target`, which is unsupported on Borg 1.2.x.
- Idempotent — repeating the command overwrites the target with identical content. Live data is never touched unless you explicitly point at it.

### 6.5 Repository Initialisation (`init`)

Checks whether `BORG_REPO` already exists and is a valid repository; if so, does nothing. Otherwise creates the parent directory and runs `borg init --encryption=repokey`, prompting for the passphrase (from `BORG_PASSPHRASE`).

### 6.6 `validate` (Configuration Validation)

Runs entirely read-only: prints every key configuration value, confirms `DB_TYPE` is one of the supported values, confirms `borg` is installed and reports its version, and reports whether `BORG_REPO` currently exists — without ever touching the repository, USB, or cloud. Exits non-zero if any required check fails, making it suitable for pre-deployment CI or a pre-flight step before scheduling automation on a new host.

### 6.7 `check-if-due` (Scheduled Consistency Checks)

A full `borg check` walks and verifies every object in the repository and can be expensive on large repositories. `check-if-due` compares the current time against a timestamp recorded in `CHECK_STATE_FILE`; if more than `CHECK_INTERVAL_DAYS` have elapsed, it runs `check_repo` and updates the timestamp. Wired to `ukwinika-check.timer`, which evaluates daily but only triggers an actual check on the configured cadence — mirroring `borgmatic`'s "checks" frequency feature.

---

## 7. Configuration Reference

### 7.1 Main Configuration File (`/etc/ukwinika-backup.conf`)

```bash
BORG_REPO="/UKwinikaBackup/borg-repo"
MIN_BORG_VERSION="1.2.0"
BACKUP_PATHS=("/")
EXCLUDE_DIRS=(
    "/proc" "/sys" "/dev" "/tmp" "/run"
    "/mnt" "/media" "/lost+found"
    "/var/cache" "/var/tmp" "/home/*/.cache"
)
RETENTION_DAYS=90
RETENTION_VERSIONS=5
USB_MOUNT="/mnt/backup_usb"
USB_RSYNC_TARGET="/mnt/backup_usb/offsite-borg-repo"
USB_RETRY_ATTEMPTS=3
USB_RETRY_DELAY_SEC=5
CLOUD_REMOTE=""
CLOUD_RETRY_ATTEMPTS=3
CLOUD_RETRY_DELAY_SEC=15
DB_TYPE="none"                # none, mysql, postgresql, mongodb
DB_DUMP_DIR="/tmp/ukwinika-db-dump"
PRE_HOOK="/etc/ukwinika/pre_backup_hook.sh"
POST_HOOK="/etc/ukwinika/post_backup_hook.sh"
HOOK_FAIL_ACTION="fatal"      # fatal or warn
REAL_TIME_DIRS=("/etc" "/home")
EMAIL_TO="admin@example.com"
METRICS_ENABLED="yes"
PROMETHEUS_FILE="/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom"
RESTORE_TARGET_BASE="/var/lib/ukwinika/restore-drills"
RESTORE_VERIFY_PATHS="etc/hostname"
RESTORE_MIN_FILES=10
RESTORE_KEEP_ON_FAILURE="no"
RESTORE_DRILL_LOG="/var/log/UKwinikaRestore.log"
CHECK_STATE_FILE="/var/lib/ukwinika/last-check-timestamp"
CHECK_INTERVAL_DAYS=7
```

| Variable | Default | Purpose |
|---|---|---|
| `BORG_REPO` | `/UKwinikaBackup/borg-repo` | Primary repository path |
| `MIN_BORG_VERSION` | `1.2.0` | Minimum installed `borg` version accepted |
| `BACKUP_PATHS` | `("/")` | Directories/files included in each archive |
| `EXCLUDE_DIRS` | see above | `--exclude` patterns; defined only here |
| `RETENTION_DAYS` | `90` | `borg prune --keep-within` window |
| `RETENTION_VERSIONS` | `5` | `borg prune --keep-last` floor |
| `USB_MOUNT` | `/mnt/backup_usb` | USB mount point |
| `USB_RSYNC_TARGET` | `/mnt/backup_usb/offsite-borg-repo` | USB mirror destination; empty skips USB entirely |
| `USB_RETRY_ATTEMPTS` / `USB_RETRY_DELAY_SEC` | `3` / `5` | USB mount retry/backoff |
| `CLOUD_REMOTE` | `""` | rclone remote+path; empty skips cloud entirely |
| `CLOUD_RETRY_ATTEMPTS` / `CLOUD_RETRY_DELAY_SEC` | `3` / `15` | Cloud upload retry/backoff |
| `DB_TYPE` | `none` | `none`, `mysql`, `postgresql`, or `mongodb`; anything else aborts |
| `DB_DUMP_DIR` | `/tmp/ukwinika-db-dump` | Scratch directory for DB dumps, recreated each run |
| `PRE_HOOK` / `POST_HOOK` | see hooks | Executable scripts run before/after backup |
| `HOOK_FAIL_ACTION` | `fatal` | `fatal` aborts the backup; `warn` logs and continues |
| `REAL_TIME_DIRS` | `("/etc" "/home")` | Directories watched by `real-time` mode |
| `EMAIL_TO` / `SLACK_WEBHOOK` (secrets) | — | Notification targets |
| `METRICS_ENABLED` | `yes` | Toggle Prometheus textfile output |
| `PROMETHEUS_FILE` | see above | Path scraped by the node_exporter textfile collector |
| `RESTORE_TARGET_BASE` | `/var/lib/ukwinika/restore-drills` | Base directory for automated restore drills |
| `RESTORE_VERIFY_PATHS` | `etc/hostname` | Mandatory paths the restore drill must find |
| `RESTORE_MIN_FILES` | `10` | Minimum file count floor for a passing drill |
| `RESTORE_KEEP_ON_FAILURE` | `no` | Keep the drill directory around for inspection if a check fails |
| `RESTORE_DRILL_LOG` | `/var/log/UKwinikaRestore.log` | Restore-drill log stream |
| `CHECK_STATE_FILE` | `/var/lib/ukwinika/last-check-timestamp` | Due-date marker for scheduled checks |
| `CHECK_INTERVAL_DAYS` | `7` | Days between actual `borg check` runs via `check-if-due` |

**Important:** `EXCLUDE_DIRS` is defined only in this file — no other location overrides it. `BACKUP_PATHS=("/")` backs up the entire filesystem except the excludes. `BORG_REPO` itself is always auto-excluded from `BACKUP_PATHS` to avoid backing up the repository into itself.

### 7.2 Secrets File (`/etc/ukwinika-backup.secrets`)

Mode `0600`, sourced after the main config:
```bash
BORG_PASSPHRASE="your-strong-passphrase"     # Required
SLACK_WEBHOOK="https://hooks.slack.com/..."  # Optional
EMAIL_TO="admin@example.com"                 # Optional (may live in main config if non-sensitive)
```

---

## 8. Setup and Installation

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets
sudo chmod 600 /etc/ukwinika-backup.secrets
sudo nano /etc/ukwinika-backup.secrets
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
sudo chmod 600 /etc/ukwinika-backup.conf
sudo nano /etc/ukwinika-backup.conf
sudo enhanced_automated_backups.sh validate         # confirm config before touching anything
sudo enhanced_automated_backups.sh init              # initialise the Borg repository
sudo enhanced_automated_backups.sh backup --dry-run  # simulate first
sudo enhanced_automated_backups.sh backup             # then run for real
sudo systemctl enable --now ukwinika-backup.timer
sudo systemctl enable --now ukwinika-restore-test.timer
sudo systemctl enable --now ukwinika-check.timer
```

---

## 9. Database Dumps

Handled **before** the Borg backup begins, for a consistent snapshot:

- `DB_TYPE` must be `mysql`, `postgresql`, or `mongodb` — an unrecognised value aborts immediately.
- The dump is written to `DB_DUMP_DIR`, destroyed and recreated each run (idempotent).
- MySQL uses `mysqldump`; a `/root/.my.cnf` credentials file may be required on Debian.
- PostgreSQL runs `pg_dumpall` as the `postgres` user — the redirect target file descriptor is opened by the invoking root shell before privilege drop, so this works correctly under the script's `User=root` systemd context (documented inline with a ShellCheck `SC2024` suppression and rationale).
- MongoDB uses `mongodump`.

The dump directory is included in the Borg archive automatically.

---

## 10. Filesystem Consistency (LVM Snapshot Hooks)

The database-aware dumps give consistency for the databases they cover, but the rest of a live, changing filesystem has no point-in-time guarantee by default — Borg reads files as they are at the moment it gets to them. `hooks/lvm_snapshot_pre_backup_hook.sh.example` and `hooks/lvm_snapshot_post_backup_hook.sh.example` close this gap for hosts using LVM:

1. The pre-backup hook takes an LVM snapshot of the configured volume group/logical volume and mounts it read-only.
2. `BACKUP_PATHS` should then point at the snapshot mount rather than the live path, so Borg reads a frozen view for the whole backup duration.
3. The post-backup hook unmounts and removes the snapshot once Borg has finished.

Copy both to the paths configured in `PRE_HOOK`/`POST_HOOK`, make them executable, and set the `UKW_LVM_VG`, `UKW_LVM_LV`, `UKW_LVM_SNAP_NAME`, `UKW_LVM_SNAP_SIZE`, and `UKW_LVM_SNAP_MOUNT` environment variables (or edit the defaults directly) to match your volume layout. Ensure the volume group has enough free extents to hold the snapshot's copy-on-write delta for the backup's duration.

Btrfs/ZFS users can adapt the same pattern using `btrfs subvolume snapshot` or `zfs snapshot` in place of `lvcreate`/`lvremove`.

---

## 11. Hooks

Two optional hook scripts:

- **`PRE_HOOK`** — runs before the backup. Useful for LVM snapshot creation, stopping services, or flushing logs.
- **`POST_HOOK`** — runs after the backup. Useful for LVM snapshot cleanup or restarting services.

Both must be executable. On failure: `HOOK_FAIL_ACTION=fatal` (default) aborts the backup; `warn` logs and continues.

---

## 12. Scheduled Consistency Checks

`borg check` verifies the integrity of every object in a repository and can be slow on large repositories, so it is intentionally **not** run automatically on every backup. Instead:

- `enhanced_automated_backups.sh check` runs a full check immediately, on demand.
- `enhanced_automated_backups.sh check-if-due` only runs the check if `CHECK_INTERVAL_DAYS` (default 7) have elapsed since the timestamp recorded in `CHECK_STATE_FILE`.
- `ukwinika-check.timer` fires `check-if-due` daily at 03:30 (± 20 min jitter), so the *evaluation* happens every day but the expensive check itself only happens on the configured cadence.

---

## 13. Automated Restore Drills

`backuprestore/ukwinika_automated_restore.sh` runs six independent verification checks against the most recent archive (or a specified one):

1. Extraction succeeds and produces a non-empty directory.
2. All `RESTORE_VERIFY_PATHS` (mandatory paths) are present.
3. The restored file count meets `RESTORE_MIN_FILES`.
4. A checksum spot-check against the audit log matches.
5. No unexpected zero-byte files outside known-legitimate locations (e.g. `/etc`).
6. Archive metadata is readable and consistent.

Scheduled monthly via `ukwinika-restore-test.timer` (15th of the month, 04:00 ± jitter). Results are written to `RESTORE_DRILL_LOG`, cross-posted to the main Prometheus metrics file, and alertable via `prometheus/ukwinika-backup-alerts.yml`. See `docs/RESTORE-CHECKLIST.md` for the manual walkthrough version of this same drill.

---

## 14. Disaster Recovery

The restore drill above answers "can we restore a file on a *living* host?" It does not cover total host loss. For that scenario — dead disk, destroyed VM, stolen hardware — see **`docs/DISASTER-RECOVERY.md`**, which covers:

- What must survive off-host before disaster strikes (repository copy, passphrase, repokey, tooling).
- Provisioning a replacement host and reinstalling the toolchain.
- Pointing at whichever copy (USB or cloud) survived.
- Verifying integrity before restoring anything.
- Restoring `/etc`, application data, and database dumps in the right order.
- Rebuilding scheduling and monitoring on the new host, and confirming a fresh backup and drill both succeed before considering the rebuild complete.

---

## 15. Prometheus Metrics and Alerting

When `METRICS_ENABLED=yes`, the backup script writes:
```
ukwinika_backup_last_success_seconds <unix_timestamp>
ukwinika_backup_latest_archive{name="<archive_name>"} 1
```
The restore-drill script writes its own `ukwinika_restore_test_last_result`, `ukwinika_restore_test_last_run_seconds`, and `ukwinika_restore_test_checks_failed` metrics to the same file, scraped by the node_exporter textfile collector.

`prometheus/ukwinika-backup-alerts.yml` ships ready-to-use rules for:
- **`UkwinikaBackupStale`** — no successful backup in 30+ hours.
- **`UkwinikaBackupMetricsMissing`** — metric absent entirely (misconfiguration or a host that's never backed up successfully).
- **`UkwinikaRestoreDrillFailed`** — most recent drill failed.
- **`UkwinikaRestoreDrillStale`** — no drill in 45+ days.
- **`UkwinikaRestoreDrillChecksFailing`** — one or more of the six checks failing even if the overall result hasn't flipped yet.

Copy the file into your Prometheus rule directory and reference it from `prometheus.yml`, then reload Prometheus.

---

## 16. Logging and Auditing

- **Main log:** `/var/log/UKwinikaBackup.log` — INFO and FATAL messages.
- **Audit log:** `/var/log/UKwinikaBackup_audit.log` — SHA256 checksums of every repository object, plus restore-drill verification checksums.
- **Restore drill log:** `RESTORE_DRILL_LOG`, default `/var/log/UKwinikaRestore.log`.

All three are rotated daily by the provided logrotate configuration.

---

## 17. Locking, Retries, and Idempotency Guarantees

- **Exclusive lock:** `flock -n` on `/var/lock/ukwinika-backup.lock`; a second concurrent instance exits immediately with status 0.
- **Stale lock prevention:** a `trap` on `EXIT`, `INT`, `TERM` unconditionally removes the lock file.
- **Real-time mode:** releases its own lock before spawning a child `backup` invocation (which reacquires its own), avoiding the lock-contention deadlock present in earlier iterations of the design.
- **Borg operations** are naturally idempotent via deduplication.
- **Retry/backoff:** USB mount and cloud upload each retry up to their configured attempt count with a delay between attempts, tolerating transient failures without failing the whole backup. A cloud-upload failure after retries is logged as a warning, not fatal — the local and USB copies are already safe.
- **Minimum version enforcement:** every operation except `validate` checks `borg --version` against `MIN_BORG_VERSION` before doing anything, failing fast and clearly instead of partway through with a confusing error.
- **Database dumps:** fresh temporary directory each run; no carried-over state.
- **Restore:** the `cd`-subshell extraction pattern overwrites the target with identical content on repeat runs.
- **Scheduled checks:** `check-if-due` is itself idempotent — running it multiple times within the same interval only performs the expensive check once.

---

## 18. Security Considerations

- The passphrase is stored in a separate `0600` file; the script validates this permission and ownership before running and refuses otherwise.
- All Borg communication is AES-256 encrypted in `repokey` mode. **Never lose the passphrase or repository key** — export a copy with `borg key export` and store it off-host per `docs/DISASTER-RECOVERY.md`.
- The lock file prevents concurrent backup runs.
- Systemd units apply `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges=true`, and `PrivateTmp=true` wherever the operation's write requirements allow it.
- Notifications can be disabled by leaving `SLACK_WEBHOOK`/`EMAIL_TO` empty.
- For extra resilience, replicate the primary repository to immutable cloud storage (e.g. S3 Object Lock).
- See `SECURITY.md` for the vulnerability reporting process and supported-version table.

---

## 19. Troubleshooting

| Issue | Possible Cause | Solution |
|-------|-----------------|----------|
| `borg version X is older than required minimum` | Outdated `borgbackup` package | Upgrade via `apt`/`dnf` |
| `Borg create failed` or "Repository does not exist" | Repository not initialised | Run `sudo enhanced_automated_backups.sh init` |
| Real-time monitoring not working | `inotify-tools` missing | `sudo make install` |
| MySQL dump fails with "Access denied" | Missing credentials file | Create `/root/.my.cnf` |
| Passphrase prompt appears during backup | Secrets file missing/wrong permissions | Ensure `0600`, contains `BORG_PASSPHRASE` |
| "Another instance is already running" | Stale lock? | Cleaned up automatically on next run |
| USB mount fails intermittently | Slow-enumerating controller | Raise `USB_RETRY_ATTEMPTS`/`USB_RETRY_DELAY_SEC` |
| Cloud upload fails intermittently | Transient network issue | Raise `CLOUD_RETRY_ATTEMPTS`/`CLOUD_RETRY_DELAY_SEC` — backup still succeeds locally/USB |
| `check-if-due` never actually checks | `CHECK_STATE_FILE` path not writable | Ensure `/var/lib/ukwinika` exists (created by `sudo make systemd`) |
| Real-time service restarts continuously | Missing repository or config error | Check logs; service stops after 3 rapid failures |

---

## 20. RHEL / Rocky / AlmaLinux Specific Notes

- `Makefile` enables the **EPEL** repository automatically before installing `borgbackup` and `inotify-tools`.
- Ensure the system is registered (RHEL) or using a free derivative (Rocky, AlmaLinux) with `dnf` repositories available.
- The Prometheus textfile collector directory may need manual creation if it differs from `/var/lib/prometheus/node_exporter/custom`.

---

## 21. Upgrade Notes

### From 3.2.2 to 3.3.0
1. Replace `enhanced_automated_backups.sh` and `backuprestore/ukwinika_automated_restore.sh` with the v3.3.0 versions.
2. Add the new config variables to `/etc/ukwinika-backup.conf`: `MIN_BORG_VERSION`, `USB_RETRY_ATTEMPTS`, `USB_RETRY_DELAY_SEC`, `CLOUD_RETRY_ATTEMPTS`, `CLOUD_RETRY_DELAY_SEC`, `CHECK_STATE_FILE`, `CHECK_INTERVAL_DAYS` (see `config/ukwinika-backup.conf.example` for defaults).
3. Run `sudo make systemd` again to install `ukwinika-check.service`/`.timer` and create `/var/lib/ukwinika`.
4. Enable the new timer: `sudo systemctl enable --now ukwinika-check.timer`.
5. Validate the upgraded configuration before your next scheduled run: `sudo enhanced_automated_backups.sh validate`.
6. (Optional) Adopt the LVM snapshot hooks if you need filesystem consistency beyond DB-aware dumps.
7. (Optional) Install `prometheus/ukwinika-backup-alerts.yml` into your Prometheus rule directory.

### From 3.2.1 to 3.2.2
1. Replace `enhanced_automated_backups.sh` and `backuprestore/ukwinika_automated_restore.sh` with the v3.2.2 versions.
2. No configuration variable changes required.

### From 3.2 to 3.2.1
1. Add `backuprestore/` to your working copy.
2. Add `RESTORE_TARGET_BASE`, `RESTORE_VERIFY_PATHS`, `RESTORE_MIN_FILES`, `RESTORE_KEEP_ON_FAILURE`, and `RESTORE_DRILL_LOG` to your configuration.
3. Add `/var/log/UKwinikaRestore.log` to the logrotate configuration if not already present.
4. Run `sudo make systemd` to install `ukwinika-restore-test.service`/`.timer`.
5. No changes to `enhanced_automated_backups.sh` itself in this step — it is unchanged from v3.2.

---

## 22. License

MIT License – see `LICENSE` file.

> **UKwinika Notable Advice:** A Backup is Only as Good as its Last Successful Restore. Run monthly restore drills, rehearse disaster recovery at least annually, and let `validate` and `check-if-due` catch drift before it becomes an incident.
