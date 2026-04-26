# UKwinika Enhanced Automated Backup Script – Documentation

**Version:** 3.1 (Idempotent Edition)  
**Author:** Urayayi Kwinika  
**Date:** April 2026  
**License:** MIT

---

## 1. Overview

The UKwinika Enhanced Automated Backup Script (EABS) is a lightweight, Open‑Source Backup Solution for Linux Systems. It implements the industry‑standard **3‑2‑1 Backup Principle** and adds Real‑Time File Monitoring, Database‑aware Dumps, Encryption, Auditing, and Prometheus Metrics. The script is built around **BorgBackup** and is designed to be **fully idempotent** – it can be run repeatedly without causing unintended changes or failures.

**Supported Distributions:** Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, CentOS Stream.

---

## 2. Key Features

- **Fully Idempotent** – safe for repeated execution; no stale locks, no duplicate side effects.
- **3‑2‑1 Backup** – primary on disk, secondary on removable USB, tertiary to cloud (rclone).
- **BorgBackup** – deduplication, compression (lz4), AES‑256 encryption (`repokey`), mountable archives.
- **Multiple modes** – `backup`, `restore` (with drill mode), `list`, `check`, `real-time`, `init`.
- **Real‑Time Monitoring** – uses inotify to trigger incremental backups on file changes.
- **Database‑aware** – dumps MySQL, PostgreSQL, and MongoDB before each backup; strict validation of `DB_TYPE`.
- **Pre/Post Hooks** – custom scripts that run before and after the backup.
- **Stale Lock Prevention** – lock file is automatically removed on any exit (trap).
- **Restore to target** – `borg extract --target` ensures extractions are repeatable and never overwrite live data by default.
- **Audit Trail** – SHA256 checksums of all repository files are logged after each backup.
- **Prometheus Metrics** – exposes `ukwinika_backup` metrics for monitoring.
- **Systemd Integration** – timer, run‑on‑demand service, and real‑time monitoring service.
- **Log Rotation** – pre‑configured logrotate snippet.

---

## 3. The 3‑2‑1 Backup Principle

The script adheres strictly to the 3‑2‑1 rule:

| Copy | Location                    | Media Type | Trigger                             |
|------|-----------------------------|------------|-------------------------------------|
| 1    | `/UKwinikaBackup/borg-repo` | System disk | Always (primary)                    |
| 2    | Removable USB               | External media | USB detected & mounted          |
| 3    | Cloud (rclone)              | Off‑site   | `CLOUD_REMOTE` defined in config    |

The primary copy is a Borg Repository. After each successful Borg Backup, the script:
- Syncs the entire repository to a USB drive (if a mount point is configured) using `rsync -a --delete`, making an exact mirror.
- Uploads the repository to a cloud remote via `rclone` (if configured).

---

## 4. Script Architecture

### 4.1 Invocation

```
enhanced_automated_backups.sh <mode> [arguments]
```

| Mode | Description | Extra Arguments |
|------|-------------|-----------------|
| `backup` | Full backup cycle (primary + USB + cloud) | None |
| `restore` | Restore an archive to a target directory | `<archive_name>` `<target_path>` (target optional) |
| `list` | List all archives in the repository | None |
| `check` | Verify repository integrity | None |
| `real-time` | Start inotify‑based monitoring loop | None |
| `init` | Initialise a new Borg repository | None |

If the repository does not exist, `backup`, `restore`, `list`, `check`, and `real-time` will fail with a clear error message instructing the user to run `init` first.

### 4.2 Workflow – `backup` mode

1. Acquire an exclusive lock (`flock`) – if already locked, the script exits cleanly.
2. Run the **pre‑hook** (if executable).
3. Perform a **database dump** (if `DB_TYPE` is not `none`). The dump is saved to a temporary directory.
4. Create a **Borg archive** using the configured include and exclude paths. The archive name is `<hostname>-<YYYY-MM-DD_HH:MM:SS>`.
5. **Prune old archives** according to `RETENTION_DAYS` and `RETENTION_VERSIONS`.
6. **Sync to USB** – if `USB_RSYNC_TARGET` is set, mount the USB drive, run `rsync -a --delete`, and unmount.
7. **Upload to cloud** – if `CLOUD_REMOTE` is set, copy the repository with `rclone`.
8. Generate an **audit checksum** file of all repository objects.
9. Update **Prometheus metrics**.
10. Send **notifications** (Slack / email) on success.
11. Run the **post‑hook** (if executable).
12. Release the lock (trap removes the lock file).

### 4.3 Real‑Time Monitoring (`real-time`)

Uses `inotifywait` to watch directories defined in `REAL_TIME_DIRS`. Whenever a file is modified, created, or deleted, the script triggers a full backup cycle (the `backup` routine). The service restarts on failure but stops after three rapid failures to prevent log flooding.

### 4.4 Restore Mode (`restore`)

- **Drill / Safe Restore:** by default, the archive is extracted to `/tmp/restore_<archive_name>`. You can specify a custom target directory.
- The restore uses `borg extract --target`, making it idempotent – running the same command again will overwrite the target directory with the exact same content.
- **No live data is ever touched** unless you explicitly point to a production directory.

### 4.5 Repository Initialisation (`init`)

The `init` command:
- Checks if the directory `$BORG_REPO` exists and is already a valid Borg repository; if so, it does nothing.
- Otherwise, it creates the parent directory and runs `borg init --encryption=repokey`. You will be prompted for a passphrase (set via `BORG_PASSPHRASE` environment variable or the secrets file).

---

## 5. Configuration

### 5.1 Main Configuration File (`/etc/ukwinika-backup.conf`)

This file sets all non‑sensitive parameters. A template is provided at `config/ukwinika-backup.conf.example`.

```bash
BORG_REPO="/UKwinikaBackup/borg-repo"         # Borg repository path
BACKUP_PATHS=("/")                             # Directories/files to include
EXCLUDE_DIRS=(                                 # Exclusion patterns (array)
    "/proc" "/sys" "/dev" "/tmp" "/run"
    "/mnt" "/media" "/lost+found"
    "/var/cache" "/var/tmp" "/home/*/.cache"
)
RETENTION_DAYS=90                              # Keep all archives within this many days
RETENTION_VERSIONS=5                           # Keep at least this many recent archives
USB_MOUNT="/mnt/backup_usb"                    # Mount point for USB drive
USB_RSYNC_TARGET="/mnt/backup_usb/offsite-borg-repo"  # Destination folder on USB
CLOUD_REMOTE=""                                # rclone remote (e.g., "s3:my-bucket")
DB_TYPE="none"                                 # none, mysql, postgresql, mongodb
PRE_HOOK="/etc/ukwinika/pre_backup_hook.sh"
POST_HOOK="/etc/ukwinika/post_backup_hook.sh"
HOOK_FAIL_ACTION="fatal"                       # fatal or warn
REAL_TIME_DIRS=("/etc" "/home")                # Directories for inotify monitoring
EMAIL_TO="admin@example.com"
METRICS_ENABLED="yes"
PROMETHEUS_FILE="/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom"
```

**Important:**  
- Exclude patterns are defined **only** in this file – no other place overrides them.  
- If `BACKUP_PATHS` is set to `"/"`, the entire filesystem is backed up except for the excluded directories.  
- `BORG_REPO` must be set; the default is `/UKwinikaBackup/borg-repo`.

### 5.2 Secrets File (`/etc/ukwinika-backup.secrets`)

All sensitive values are stored here. The file **must** have permissions `0600` and is sourced after the main config.

```bash
BORG_PASSPHRASE="your-strong-passphrase"     # Required
SLACK_WEBHOOK="https://hooks.slack.com/..."  # Optional
EMAIL_TO="admin@example.com"                 # Optional (can be in main config if not sensitive)
```

---

## 6. Setup and Installation

The recommended installation is a one‑time setup. Detailed steps are in the `README.md`. The short version:

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install         # Installs dependencies and script
sudo make systemd         # Deploys systemd units and logrotate
sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets
sudo chmod 600 /etc/ukwinika-backup.secrets
sudo nano /etc/ukwinika-backup.secrets
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
sudo chmod 600 /etc/ukwinika-backup.conf
sudo nano /etc/ukwinika-backup.conf
sudo enhanced_automated_backups.sh init      # Initialise the Borg repository
sudo enhanced_automated_backups.sh backup     # Test a backup
sudo systemctl enable --now ukwinika-backup.timer  # Enable daily run
```

---

## 7. Backup Storage and 3‑2‑1 Flow

- **Primary:** `/UKwinikaBackup/borg-repo` (or the path set in `BORG_REPO`). This directory contains the entire Borg repository with deduplicated, compressed, encrypted archives.
- **Secondary:** If `USB_RSYNC_TARGET` is defined and the USB drive is mounted at `USB_MOUNT`, the script mirrors the primary repository using `rsync -a --delete`. The sync is idempotent – only changed files are transferred, and the destination becomes an exact copy.
- **Tertiary:** If `CLOUD_REMOTE` is set (and `rclone` is installed), the script runs `rclone copy` to upload the repository to the configured cloud storage. Note: This is a copy, not a mirror; deleted files on the primary are not removed on the cloud unless you configure `rclone` accordingly.

---

## 8. Database Dumps

The script handles database dumps **before** the Borg backup begins, ensuring a consistent snapshot of your databases.

- Set `DB_TYPE` to one of `mysql`, `postgresql`, or `mongodb`.
- The dump is written to a temporary directory (`/tmp/ukwinika-db-dump`) which is destroyed and re‑created before each run – this is idempotent.
- **If an unrecognised `DB_TYPE` is set, the script aborts immediately** to avoid silent data loss.
- For MySQL, the script uses `mysqldump`; a credentials file `/root/.my.cnf` may be required on Debian systems (see Troubleshooting).
- For PostgreSQL, it runs `pg_dumpall` as the `postgres` user.
- For MongoDB, it uses `mongodump`.

The dump file is included in the Borg archive automatically.

---

## 9. Hooks

Two optional hook scripts can be configured:

- **Pre‑hook** (`PRE_HOOK`): Executed before the backup. Useful for stopping services or flushing logs.
- **Post‑hook** (`POST_HOOK`): Executed after the backup (even if the backup fails, but the script may exit early on fatal errors – see `HOOK_FAIL_ACTION`).

Hooks must be executable. If a hook fails:
- With `HOOK_FAIL_ACTION=fatal` (default), the script dies immediately and the backup is aborted.
- With `HOOK_FAIL_ACTION=warn`, a warning is logged and the backup continues.

---

## 10. Prometheus Metrics

When `METRICS_ENABLED` is `yes`, the script writes two metrics to the file specified in `PROMETHEUS_FILE` (default `/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom`):

```
# HELP ukwinika_backup_last_success_seconds Time of last successful backup
# TYPE ukwinika_backup_last_success_seconds gauge
ukwinika_backup_last_success_seconds <unix_timestamp>

# HELP ukwinika_backup_latest_archive Latest archive name
# TYPE ukwinika_backup_latest_archive gauge
ukwinika_backup_latest_archive{name="<archive_name>"} 1
```

These can be scraped by the Prometheus Node Exporter textfile collector.

---

## 11. Logging and Auditing

- **Main log:** `/var/log/UKwinikaBackup.log` – contains INFO and FATAL messages.
- **Audit log:** `/var/log/UKwinikaBackup_audit.log` – includes a timestamped entry for the start of each backup and the SHA256 checksums of every file inside the Borg repository (written at the end of the backup). This provides a tamper‑evident record of the repository’s state.

Both logs are rotated daily with the provided logrotate configuration.

---

## 12. Locking and Idempotency Guarantees

- **Exclusive lock:** The script uses `flock -n` on `/var/lock/ukwinika-backup.lock`. If another instance is already running, the new one exits immediately with status 0 – no concurrency.
- **Stale lock prevention:** A `trap` on `EXIT`, `INT`, and `TERM` releases the lock and removes the lock file. Even if the script is killed with `SIGKILL`, the lock file will be removed as soon as any subsequent run starts (because the trap runs on script exit, but a kill -9 would prevent that; however, the lock file is not used for anything else, and a future run will still succeed if the process holding the lock is dead – `flock` on a file descriptor that is no longer held by any process will succeed anyway). To be extra safe, the lock file is unconditionally removed in the `cleanup_lock` function.

- **Borg operations:** `borg create` is naturally idempotent – deduplication ensures that only new data is stored. Repeated runs with the same input produce archives of the same content.
- **USB sync:** `rsync -a --delete` makes the USB mirror **exactly** match the primary repository; the operation is idempotent.
- **Database dumps:** each run writes to a fresh temporary directory; no state is carried over.
- **Restore:** `borg extract --target` overwrites the target with the archive content – repeating the command yields the same result.

---

## 13. Security Considerations

- The **passphrase** is stored in a separate file with restricted permissions (`0600`).
- All communication with Borg is encrypted using AES‑256 in `repokey` mode. **Never lose the passphrase or repository key**.
- The lock file prevents concurrent backup runs.
- Notifications (Slack/email) can be disabled by leaving the corresponding variables empty.
- For extra resilience, replicate the primary repository to immutable cloud storage (e.g., S3 with Object Lock).

---

## 14. Troubleshooting

| Issue | Possible Cause | Solution |
|-------|----------------|----------|
| `Borg create failed` or “Repository does not exist” | Repository not initialised | Run `sudo enhanced_automated_backups.sh init` |
| Real‑time monitoring not working | `inotify-tools` missing | Install with `sudo make install` |
| MySQL dump fails with “Access denied” | Missing credentials file | Create `/root/.my.cnf` with valid MySQL credentials (see README) |
| Passphrase prompt appears during backup | Secrets file missing or wrong permissions | Ensure `/etc/ukwinika-backup.secrets` exists, mode `0600`, and contains `BORG_PASSPHRASE` |
| “Another instance is already running” | Stale lock? | The lock is automatically cleaned up on next run; if not, remove `/var/lock/ukwinika-backup.lock` manually |
| Real‑time service restarts continuously | Missing repository or configuration error | Check logs; the service will stop after 3 rapid failures |

---

## 15. RHEL / Rocky / AlmaLinux Specific Notes

- The `Makefile` enables the **EPEL** repository automatically before installing `borgbackup` and `inotify-tools`.
- Ensure the system is registered (RHEL) or that you are using a free derivative (Rocky, AlmaLinux) that provides `dnf` repositories.
- The Prometheus textfile collector directory may need to be created manually if the default path differs from `/var/lib/prometheus/node_exporter/custom`.

> **UKwinika Notable Advice:** Remember A Backup is Only as Good as its Last Successful Restore. Run monthly Restore Drills using the `restore` command with a safe target directory.

---

## 16. License

MIT License – see `LICENSE` file.
---
