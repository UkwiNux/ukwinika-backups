# UKwinika Enhanced Automated Backup Script (EABS)

**Version:** 3.2 (Idempotent Edition)
**Author:** Urayayi Kwinika
**License:** MIT
**Date:** June 2026

---

## Table of Contents

1. [Overview](#1-overview)
2. [What's New in 3.2](#2-whats-new-in-32)
3. [Key Features](#3-key-features)
4. [The 3-2-1 Backup Principle](#4-the-3-2-1-backup-principle)
5. [Repository Structure](#5-repository-structure)
6. [Quick Start](#6-quick-start)
7. [Full Setup](#7-full-setup)
8. [Configuration Reference](#8-configuration-reference)
9. [Secrets File Reference](#9-secrets-file-reference)
10. [Script Architecture](#10-script-architecture)
11. [CLI Reference](#11-cli-reference)
12. [Database Dumps](#12-database-dumps)
13. [Hooks](#13-hooks)
14. [Real-Time Monitoring](#14-real-time-monitoring)
15. [Restore and Drill Mode](#15-restore-and-drill-mode)
16. [Locking and Idempotency](#16-locking-and-idempotency)
17. [Prometheus Metrics](#17-prometheus-metrics)
18. [Logging and Auditing](#18-logging-and-auditing)
19. [Notifications](#19-notifications)
20. [Security Considerations](#20-security-considerations)
21. [Systemd Integration](#21-systemd-integration)
22. [Log Rotation](#22-log-rotation)
23. [Troubleshooting](#23-troubleshooting)
24. [RHEL / Rocky / AlmaLinux Notes](#24-rhel--rocky--almalinux-notes)
25. [Upgrade Notes](#25-upgrade-notes)
26. [License](#26-license)

---

## 1. Overview

The UKwinika Enhanced Automated Backup Script (EABS) is a lightweight, open-source backup solution for Linux systems built on top of **BorgBackup**. It implements the industry-standard **3-2-1 backup principle** and adds real-time file monitoring, database-aware pre-backup dumps, AES-256 encryption, SHA256 audit trails, Prometheus metrics, and cloud upload support.

The script is designed to be **fully idempotent** — it can be run any number of times without causing unintended changes, duplicate archives, stale locks, or overwritten live data.

**Supported distributions:** Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, CentOS Stream.

---

## 2. What's New in 3.2

- **Lightweight repository check** — `ensure_repo_exists` now performs a fast file-system test (`-d $BORG_REPO && -f $BORG_REPO/config`) instead of a full `borg check --info` on every invocation, making `list`, `backup`, and `restore` noticeably faster on large repositories.
- **Real-time monitoring lock fix** — the `real-time` subcommand now releases the parent lock before spawning each child backup process, preventing the child from deadlocking on `flock`. The parent re-acquires the lock after the child exits to protect the monitoring loop itself.
- **Failure notifications** — `die()` now calls `notify()` before exiting, so Slack and email alerts are sent on failure as well as success.
- **Pruning correction** — removed the redundant `--keep-daily` flag from `borg prune`; `--keep-within` and `--keep-last` fully express the retention policy without duplication.
- **Configurable paths** — `DB_DUMP_DIR` and `CHECKSUM_FILE` are now configurable variables (with sensible defaults) instead of hardcoded `/tmp` paths.
- **`PROMETHEUS_FILE` respected everywhere** — the metrics writer now uses the value from configuration rather than a hardcoded path, and it creates the parent directory if it does not exist.
- **Cleaner array defaults** — `BACKUP_PATHS` and `EXCLUDE_DIRS` defaults are guarded with `${VAR+x}` to avoid overwriting values already set by the config file.

---

## 3. Key Features

- **Fully idempotent** — safe for repeated execution; no stale locks, no duplicate side effects.
- **3-2-1 backup** — primary on disk (Borg), secondary on removable USB (rsync mirror), tertiary to cloud (rclone).
- **BorgBackup** — deduplication, lz4 compression, AES-256 `repokey` encryption, mountable archives.
- **Multiple subcommands** — `backup`, `restore` (with safe drill mode), `list`, `check`, `real-time`, `init`.
- **Real-time monitoring** — inotify triggers a full backup on file change, spawning a child process to avoid lock contention.
- **Database-aware** — adaptive dumps for MySQL, PostgreSQL, and MongoDB before each backup; unknown `DB_TYPE` values abort immediately.
- **Pre/post hooks** — custom executable scripts before and after the backup, with configurable failure behaviour.
- **Failure notifications** — Slack and email alerts sent on both success and failure.
- **Prometheus metrics** — exports last-success timestamp and latest archive name.
- **SHA256 audit trail** — checksums of all repository files logged after every backup.
- **Stale lock prevention** — lock file automatically removed on any exit (`EXIT`, `INT`, `TERM`).
- **Systemd-ready** — timer, run-on-demand service, and real-time monitoring service included.
- **Log rotation** — pre-configured logrotate snippet rotates both log files daily.
- **Cross-distribution** — Debian/Ubuntu and RHEL/Rocky/AlmaLinux/CentOS supported via the `Makefile`.

---

## 4. The 3-2-1 Backup Principle

| Copy | Location | Media | Trigger |
|------|----------|-------|---------|
| 1 (Primary) | `$BORG_REPO` (default `/UKwinikaBackup/borg-repo`) | System disk | Always |
| 2 (Secondary) | `$USB_RSYNC_TARGET` on a removable USB | External media | `USB_RSYNC_TARGET` is set and USB is mountable |
| 3 (Tertiary) | Cloud via rclone (`$CLOUD_REMOTE`) | Off-site | `CLOUD_REMOTE` is set and `rclone` is installed |

After every successful Borg archive, the script:

1. Mirrors the entire Borg repository to USB using `rsync -a --delete` (exact mirror, idempotent).
2. Copies the repository to the cloud using `rclone copy` (incremental upload).

Cloud failures are logged as warnings; the backup is still considered successful if the primary and secondary copies completed.

---

## 5. Repository Structure

```
ukwinika-backups/
├── enhanced_automated_backups.sh        # Main script
├── Makefile                             # Install, deps, systemd, clean targets
├── README.md
├── CHANGELOG.md
├── LICENSE
├── SECURITY.md
├── config/
│   ├── ukwinika-backup.conf.example     # Non-sensitive configuration template
│   └── ukwinika-backup.secrets.example  # Sensitive credentials template
├── systemd/
│   ├── ukwinika-backup.service          # Oneshot backup service
│   ├── ukwinika-backup.timer            # Daily timer (02:00, ±30 min jitter)
│   └── ukwinika-realtime-backup.service # inotify monitoring service
├── logrotate/
│   └── ukwinika-backup                  # Logrotate configuration
├── hooks/
│   ├── pre_backup_hook.sh.example
│   └── post_backup_hook.sh.example
└── docs/
    └── RESTORE-CHECKLIST.md             # Monthly restore drill checklist
```

---

## 6. Quick Start

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups

sudo make install        # Installs script and dependencies (borgbackup, inotify-tools)
sudo make systemd        # Deploys systemd units and logrotate
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

Set `BORG_PASSPHRASE` to a strong passphrase. Optionally add `SLACK_WEBHOOK` and `EMAIL_TO`.

### Step 2 — Configure the main configuration file

```bash
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
sudo chmod 600 /etc/ukwinika-backup.conf
sudo nano /etc/ukwinika-backup.conf
```

Adjust paths, retention, USB mount point, database type, and hook locations as needed. See [Configuration Reference](#8-configuration-reference) for all options.

### Step 3 — Initialise the Borg repository

```bash
sudo enhanced_automated_backups.sh init
```

The repository is created at the path defined by `BORG_REPO` (default `/UKwinikaBackup/borg-repo`) using `repokey` encryption. This operation is idempotent — running it again on an existing valid repository does nothing.

### Step 4 — Deploy systemd units

```bash
sudo make systemd
```

This installs the daily timer, the on-demand service, the real-time monitoring service, and the logrotate configuration.

### Step 5 — Test a backup

```bash
sudo enhanced_automated_backups.sh backup
sudo tail -f /var/log/UKwinikaBackup.log
```

### Step 6 — Enable scheduled backups

```bash
sudo systemctl enable --now ukwinika-backup.timer
```

### Step 7 (optional) — Enable real-time monitoring

```bash
sudo systemctl enable --now ukwinika-realtime-backup.service
```

---

## 8. Configuration Reference

All non-sensitive settings live in `/etc/ukwinika-backup.conf` (sourced by the script on startup). The path can be overridden via the `UKW_CONFIG` environment variable.

**No secrets belong in this file.**

| Variable | Default | Description |
|---|---|---|
| `BORG_REPO` | `/UKwinikaBackup/borg-repo` | Path to the primary Borg repository |
| `BACKUP_PATHS` | `("/")` | Bash array of paths/files to include in the backup |
| `EXCLUDE_DIRS` | `("/proc" "/sys" "/dev" "/tmp" "/run" "/mnt" "/media" "/lost+found")` | Bash array of paths to exclude (each becomes `--exclude`) |
| `RETENTION_DAYS` | `90` | Keep all archives created within this many days |
| `RETENTION_VERSIONS` | `5` | Minimum number of recent archives to keep regardless of age |
| `USB_MOUNT` | `/mnt/backup_usb` | Mount point for the secondary USB drive |
| `USB_RSYNC_TARGET` | _(empty)_ | Destination folder on USB; leave empty to skip secondary copy |
| `CLOUD_REMOTE` | _(empty)_ | rclone remote and path (e.g. `s3:my-bucket`); leave empty to skip |
| `DB_TYPE` | `none` | Database engine to dump: `none`, `mysql`, `postgresql`, `mongodb` |
| `DB_DUMP_DIR` | `/tmp/ukwinika-db-dump` | Temporary directory for database dumps |
| `PRE_HOOK` | _(empty)_ | Path to an executable script run before the backup |
| `POST_HOOK` | _(empty)_ | Path to an executable script run after the backup |
| `HOOK_FAIL_ACTION` | `fatal` | Hook failure behaviour: `fatal` (abort) or `warn` (continue) |
| `REAL_TIME_DIRS` | `("/etc" "/home")` | Bash array of directories watched by inotify |
| `EMAIL_TO` | _(empty)_ | Email address for success/failure notifications |
| `METRICS_ENABLED` | `yes` | Write Prometheus metrics (`yes` / `no`) |
| `PROMETHEUS_FILE` | `/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom` | Path for the Prometheus textfile collector output |
| `CHECKSUM_FILE` | `/tmp/ukwinika-backup-checksums.txt` | Path where post-backup SHA256 checksums are written |

### Array syntax

Configuration arrays **must** use proper bash array syntax:

```bash
# Correct
BACKUP_PATHS=("/home" "/etc" "/var/www")
EXCLUDE_DIRS=("/proc" "/sys" "/dev" "/tmp" "/run")

# Wrong – treated as a single string, not an array
BACKUP_PATHS="/home /etc /var/www"
```

---

## 9. Secrets File Reference

All sensitive values live in `/etc/ukwinika-backup.secrets` (sourced after the main config). The file **must** have permissions `0600`. The path can be overridden via the `UKW_SECRETS` environment variable.

| Variable | Required | Description |
|---|---|---|
| `BORG_PASSPHRASE` | **Yes** | Passphrase for Borg `repokey` encryption. The script will abort if this is unset. |
| `SLACK_WEBHOOK` | No | Full Slack incoming webhook URL for notifications |
| `EMAIL_TO` | No | Can be set here instead of the main config if the address is considered sensitive |

---

## 10. Script Architecture

### Startup sequence

1. Load `$UKW_CONFIG` (abort if missing).
2. Load `$UKW_SECRETS` (skip if missing, but `BORG_PASSPHRASE` must be set by some means).
3. Export `BORG_PASSPHRASE` to the environment (required by Borg).
4. Apply defaults for any unset variables.
5. Acquire an exclusive `flock` on `$LOCK_FILE`; exit cleanly if already locked.
6. Register a `trap` to release the lock on `EXIT`, `INT`, or `TERM`.
7. Dispatch to the requested subcommand.

### `backup` workflow

```
pre-hook
  └─ db_dump           → /tmp/ukwinika-db-dump/
  └─ borg create       → $BORG_REPO::<hostname>-<timestamp>
  └─ borg prune        → enforces retention policy
  └─ sync_to_usb       → rsync -a --delete to USB (if configured)
  └─ cloud_upload      → rclone copy to cloud (if configured)
  └─ audit_checksum    → SHA256 of all repo files → $CHECKSUM_FILE + audit log
  └─ push_metrics      → Prometheus .prom file
  └─ notify SUCCESS    → Slack + email
post-hook
```

On any `die()` call: notify FAILED → exit 1.

### Archive naming

```
<hostname>-<YYYY-MM-DD_HH:MM:SS>
```

Example: `debian-2026-06-17_02:00:45`

---

## 11. CLI Reference

```
sudo enhanced_automated_backups.sh <subcommand> [arguments]
```

| Subcommand | Arguments | Description |
|---|---|---|
| `backup` | — | Full backup cycle (primary → USB → cloud) |
| `restore` | `<archive_name> [target_path]` | Extract an archive. Defaults to `/tmp/restore_<archive_name>` |
| `list` | — | List all archives in the repository |
| `check` | — | Run `borg check` to verify repository integrity |
| `real-time` | — | Start inotify monitoring loop (blocks; use systemd for production) |
| `init` | — | Initialise a new Borg repository (idempotent) |

All subcommands except `init` call `ensure_repo_exists` first and abort with a helpful message if the repository is missing.

### Examples

```bash
# Run a full backup
sudo enhanced_automated_backups.sh backup

# List available archives
sudo enhanced_automated_backups.sh list

# Safe restore to a test directory
sudo enhanced_automated_backups.sh restore debian-2026-06-17_02:00:45 /mnt/restore-test

# Restore to the default /tmp location
sudo enhanced_automated_backups.sh restore debian-2026-06-17_02:00:45

# Verify repository integrity
sudo enhanced_automated_backups.sh check

# Initialise a fresh repository
sudo enhanced_automated_backups.sh init
```

---

## 12. Database Dumps

Set `DB_TYPE` in `/etc/ukwinika-backup.conf` to enable pre-backup database dumps. The dump runs before the Borg archive is created, ensuring a consistent snapshot is included.

| `DB_TYPE` | Tool used | Output |
|---|---|---|
| `none` | — | No dump; backup proceeds without one |
| `mysql` | `mysqldump --all-databases --single-transaction --quick --lock-tables=false` | `$DB_DUMP_DIR/mysql-all.sql` |
| `postgresql` | `pg_dumpall` (run as `postgres` user via `sudo -u postgres`) | `$DB_DUMP_DIR/postgresql-all.sql` |
| `mongodb` | `mongodump --out` | `$DB_DUMP_DIR/mongo/` |

Any other value causes an **immediate abort** to prevent silent data loss.

The dump directory (`$DB_DUMP_DIR`, default `/tmp/ukwinika-db-dump`) is destroyed and recreated on every run — no stale dump data is ever left from a previous execution.

### MySQL credentials on Debian/Ubuntu

On Debian systems `mysqldump` may prompt for a password. Create a credentials file:

```bash
sudo bash -c 'cat > /root/.my.cnf << EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```

---

## 13. Hooks

Two hook scripts can be configured to run custom logic around the backup:

| Variable | When it runs | Common use |
|---|---|---|
| `PRE_HOOK` | Before the database dump and Borg archive | Stop services, flush database logs, take LVM snapshots |
| `POST_HOOK` | After notifications are sent | Restart services, send custom alerts, clean up temporary files |

Hooks must be **executable files** (`chmod +x`). If the hook path is empty or the file is not executable, the hook is silently skipped.

Hook failure behaviour is controlled by `HOOK_FAIL_ACTION`:

- `fatal` (default) — the script calls `die()`, which sends a failure notification and exits immediately.
- `warn` — a warning is logged and the backup continues.

Example hook skeleton (pre-backup):

```bash
#!/bin/bash
echo "$(date '+%F %T') [HOOK] Pre-Backup Hook Started" >> /var/log/UKwinikaBackup.log
systemctl stop apache2
mysql -e "FLUSH LOGS;"
echo "$(date '+%F %T') [HOOK] Pre-Backup Hook Completed" >> /var/log/UKwinikaBackup.log
exit 0
```

---

## 14. Real-Time Monitoring

The `real-time` subcommand uses `inotifywait` (from `inotify-tools`) to watch the directories listed in `REAL_TIME_DIRS`. When any file in those directories is modified, created, or deleted, a full backup cycle is triggered.

**Lock safety:** The monitoring loop holds the script's exclusive `flock`. Before spawning each child backup, the parent releases the lock so the child can acquire it independently. After the child exits, the parent re-acquires the lock to protect the loop. This prevents deadlocks that would otherwise occur if the child tried to acquire the same lock file descriptor.

```
real_time_mode (holds flock)
  └─ inotifywait (blocks until change)
  └─ flock -u 200          # release lock
  └─ "$0" backup           # child process acquires its own lock
  └─ flock -n 200          # re-acquire lock for the loop
  └─ (repeat)
```

For production use, manage this via systemd:

```bash
sudo systemctl enable --now ukwinika-realtime-backup.service
```

The service is configured with `Restart=on-failure`, `StartLimitBurst=3`, and `StartLimitIntervalSec=60` to prevent tight restart loops after configuration errors.

---

## 15. Restore and Drill Mode

### Safe restore (recommended)

By default, `restore` extracts the archive to a temporary directory that never touches live data:

```bash
sudo enhanced_automated_backups.sh restore <archive_name>
# → extracts to /tmp/restore_<archive_name>
```

With a custom target:

```bash
sudo enhanced_automated_backups.sh restore <archive_name> /mnt/restore-drill
```

The extraction uses `borg extract --target`, making it **idempotent** — running the same command again overwrites the target with exactly the same content.

### Monthly restore drill

Run a drill every month to confirm your backups are restorable. The full drill checklist is in `docs/RESTORE-CHECKLIST.md`. Summary:

```bash
# 1. Check repository health
sudo enhanced_automated_backups.sh check

# 2. List archives and pick one to test
sudo enhanced_automated_backups.sh list

# 3. Restore to a safe target
sudo enhanced_automated_backups.sh restore <archive_name> /tmp/restore-drill

# 4. Verify a key file
diff /etc/fstab /tmp/restore-drill/etc/fstab

# 5. Clean up
rm -rf /tmp/restore-drill
```

### Manual Borg commands

```bash
# Extract a single file
sudo borg extract --strip-components 1 \
    /UKwinikaBackup/borg-repo::<archive> path/to/file

# Mount the archive as a read-only filesystem
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg-repo::<archive> /mnt/borg-restore
ls /mnt/borg-restore
sudo borg umount /mnt/borg-restore
```

---

## 16. Locking and Idempotency

### Exclusive lock

The script opens a lock file descriptor (`exec 200>"$LOCK_FILE"`) and calls `flock -n 200`. If another instance is already running, the new invocation logs a message and exits with status 0 — no error, no partial state.

### Stale lock prevention

A `trap cleanup_lock EXIT INT TERM` ensures the lock is always released and the lock file removed, even on `SIGTERM`. Note: `SIGKILL` cannot be trapped; however, because `flock` operates on a file descriptor tied to the process, the kernel releases the lock automatically when the process is killed — the stale lock file can be removed manually if needed.

### Idempotency guarantees

| Operation | How it is idempotent |
|---|---|
| `borg create` | Deduplication stores only new data; repeated runs produce consistent archives |
| `borg prune` | Prune policies are applied on every run; re-running does not remove archives that should be kept |
| USB rsync | `rsync -a --delete` makes the destination an exact mirror; re-running transfers only deltas |
| DB dump | The dump directory is wiped and recreated on every run |
| Restore | `borg extract --target` overwrites the target directory consistently |
| `init` | Checks for an existing repository (`-d $BORG_REPO && -f $BORG_REPO/config`) before creating |
| Prometheus metrics | The `.prom` file is overwritten atomically on every backup |

---

## 17. Prometheus Metrics

When `METRICS_ENABLED=yes`, the script writes a textfile collector `.prom` file at the path defined by `PROMETHEUS_FILE`. The parent directory is created automatically if it does not exist.

```
# HELP ukwinika_backup_last_success_seconds Unix timestamp of the last successful backup
# TYPE ukwinika_backup_last_success_seconds gauge
ukwinika_backup_last_success_seconds 1750000000

# HELP ukwinika_backup_latest_archive Label carrying the name of the most recent archive
# TYPE ukwinika_backup_latest_archive gauge
ukwinika_backup_latest_archive{name="debian-2026-06-17_02:00:45"} 1
```

Configure the Prometheus Node Exporter to scrape the textfile directory:

```yaml
# prometheus.yml (node_exporter flag)
--collector.textfile.directory=/var/lib/prometheus/node_exporter/custom
```

A useful alert rule: fire if `time() - ukwinika_backup_last_success_seconds > 86400` (no backup in 24 hours).

---

## 18. Logging and Auditing

| File | Content | Rotation |
|---|---|---|
| `/var/log/UKwinikaBackup.log` | Timestamped INFO and FATAL messages from every run | Daily, 14 rotations |
| `/var/log/UKwinikaBackup_audit.log` | Timestamped audit entries + SHA256 checksums of all repository files after each backup | Daily, 14 rotations |

Both log files are written via `tee -a` so output appears on the terminal and in the file simultaneously.

The audit log entry format:

```
2026-06-17 02:01:33 [AUDIT] Checksums saved to /tmp/ukwinika-backup-checksums.txt
<sha256>  /UKwinikaBackup/borg-repo/data/0/0
<sha256>  /UKwinikaBackup/borg-repo/data/0/1
...
```

---

## 19. Notifications

`notify()` is called with a status string on both **success** (`SUCCESS`) and **failure** (via `die()`, e.g. `FAILED: borg create failed`). Two channels are supported:

**Slack** — requires `SLACK_WEBHOOK` (set in the secrets file). Sends a plain-text message:
```
Backup SUCCESS on debian
Backup FAILED: borg create failed on debian
```

**Email** — requires `EMAIL_TO` and a local `mail` command (e.g. `mailutils`). Sends with subject `UKwinika Backup SUCCESS` / `UKwinika Backup FAILED: ...`.

Both channels fail silently (the notification error is not fatal) so a broken webhook never prevents a backup from completing.

---

## 20. Security Considerations

- `BORG_PASSPHRASE` and webhook URLs are stored exclusively in `/etc/ukwinika-backup.secrets` with mode `0600`. No secret ever appears in the main config file or in the process argument list.
- Borg uses `repokey` encryption (AES-256). The encrypted key is stored inside the repository itself — **never lose the passphrase or the repository key**. Export the key with `borg key export` and store it separately.
- `flock` prevents concurrent execution; combined with `set -euo pipefail`, partial-state issues are minimised.
- The script runs as `root` (required for full filesystem access). Restrict execution with filesystem permissions: `chmod 700 /usr/local/bin/enhanced_automated_backups.sh`.
- For immutable off-site protection, configure the cloud remote to use object storage with versioning and deletion protection (e.g. AWS S3 Object Lock).
- Rotate the Slack webhook URL periodically.

---

## 21. Systemd Integration

Three units are provided in `systemd/`:

### `ukwinika-backup.service`

One-shot service that runs a single `backup` cycle. Invoked by the timer or manually.

```ini
[Service]
Type=oneshot
Environment="UKW_CONFIG=/etc/ukwinika-backup.conf"
Environment="UKW_SECRETS=/etc/ukwinika-backup.secrets"
ExecStart=/usr/local/bin/enhanced_automated_backups.sh backup
User=root
Nice=19
IOSchedulingClass=idle
PrivateTmp=true
```

`Nice=19` and `IOSchedulingClass=idle` ensure the backup does not impact interactive workloads.

### `ukwinika-backup.timer`

Triggers `ukwinika-backup.service` daily at 02:00 with a random delay of up to 30 minutes to spread load across multiple hosts.

```ini
[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=30min
Persistent=true
AccuracySec=1min
```

`Persistent=true` means a missed trigger (e.g. system was off) runs as soon as the system comes back online.

### `ukwinika-realtime-backup.service`

Keeps the `real-time` subcommand running, restarting after transient failures but stopping after three rapid failures to prevent log flooding.

```ini
[Service]
Type=simple
ExecStart=/usr/local/bin/enhanced_automated_backups.sh real-time
Restart=on-failure
RestartSec=5
StartLimitBurst=3
StartLimitIntervalSec=60
```

### Useful systemd commands

```bash
# Check timer status and next trigger time
systemctl list-timers ukwinika-backup.timer

# View live backup log
journalctl -u ukwinika-backup.service -f

# Manually trigger a backup
systemctl start ukwinika-backup.service

# Check real-time monitoring status
systemctl status ukwinika-realtime-backup.service
```

---

## 22. Log Rotation

The provided logrotate configuration (`logrotate/ukwinika-backup`) rotates both log files daily, keeps 14 compressed copies, and sends a HUP to rsyslog after rotation.

```
/var/log/UKwinikaBackup.log
/var/log/UKwinikaBackup_audit.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
    sharedscripts
    postrotate
        kill -HUP $(cat /var/run/rsyslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
```

Installed to `/etc/logrotate.d/ukwinika-backup` by `sudo make systemd`.

---

## 23. Troubleshooting

| Symptom | Likely cause | Solution |
|---|---|---|
| `Repository not found at /UKwinikaBackup/borg-repo` | Repository never initialised | `sudo enhanced_automated_backups.sh init` |
| `BORG_PASSPHRASE is not set` | Secrets file missing, wrong path, or wrong permissions | Ensure `/etc/ukwinika-backup.secrets` exists, mode `0600`, and contains `BORG_PASSPHRASE=...` |
| `borg create failed` | Passphrase mismatch, disk full, or repository corruption | Check logs; run `sudo enhanced_automated_backups.sh check` |
| Real-time monitoring not working | `inotify-tools` not installed | `sudo make install` |
| `MySQL dump failed` | Missing credentials | Create `/root/.my.cnf` with valid credentials (see [Database Dumps](#12-database-dumps)) |
| `Failed to mount USB` | USB not connected or wrong entry in `/etc/fstab` | Verify the device and `USB_MOUNT` setting |
| `Another backup instance is already running` | Concurrent run or stale lock after `SIGKILL` | If no backup is running: `rm -f /var/lock/ukwinika-backup.lock` |
| Real-time service stops after 3 restarts | Repository missing or configuration error | Check `journalctl -u ukwinika-realtime-backup.service`; fix config; `systemctl reset-failed` then restart |
| Prometheus file not updating | `METRICS_ENABLED` not `yes` or wrong `PROMETHEUS_FILE` path | Verify config; check directory permissions |
| Cloud upload warning but backup succeeds | `rclone` not installed or remote misconfigured | `rclone config` to set up the remote; `rclone listremotes` to verify |

---

## 24. RHEL / Rocky / AlmaLinux Notes

- The `Makefile` detects RHEL-based systems via `/etc/redhat-release` or `/etc/os-release` and automatically enables the **EPEL** repository before installing `borgbackup` and `inotify-tools` via `dnf`.
- For RHEL proper, ensure the system is registered with a valid subscription before running `make install`.
- The default Prometheus textfile directory (`/var/lib/prometheus/node_exporter/custom`) may need to be created manually if the Node Exporter is installed in a non-standard location.
- SELinux: if you encounter permission denials, you may need to add a custom policy or temporarily set SELinux to permissive mode during testing (`setenforce 0`). File a bug if a standard policy module is needed.

---

## 25. Upgrade Notes

### From 3.1 to 3.2

1. Replace `enhanced_automated_backups.sh` with the v3.2 version.
2. Review `DB_DUMP_DIR` and `CHECKSUM_FILE` — they now respect config values. If you relied on the hardcoded `/tmp` paths in automation or monitoring, either set these variables explicitly or leave them unset to retain the same defaults.
3. The `ensure_repo_exists` function no longer runs a full `borg check`. If you scripted around the old behaviour (e.g. relying on `list` to implicitly verify integrity), add an explicit `check` call to your workflow.
4. Real-time monitoring now spawns child processes. If you have custom `systemd` drop-ins that monitor the PID of the monitoring loop, review them — child backup PIDs will differ from the parent.
5. No configuration file changes are required.

---

## 26. License

MIT License — Copyright (c) 2026 Urayayi Kwinika.
See the `LICENSE` file for the full text.

---

> **UKwinika Notable Advice: Remember A Backup is Only as Good as its Last Successful Restore. Test Monthly.**
