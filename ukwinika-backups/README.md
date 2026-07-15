# UKwinika Enhanced Automated Backup Script (EABS)

**A 3‑2‑1 Backup Solution** built on BorgBackup with **Real-Time Monitoring**, **Database Dumps**, **AES-256 Encryption**, **Audit Trails**, **Prometheus Metrics**, **Cloud Support**, and **Automated Monthly Restore** verification.

**Author:** **Urayayi Kwinika** | **Version:** 3.2.2 | **License:** MIT

---

## Features

- **Fully Idempotent** – safe to run any number of times; no stale locks, no duplicate side effects.
- **3‑2‑1 Backup** – primary on disk (Borg), secondary on removable USB (rsync mirror), tertiary to cloud (rclone).
- **BorgBackup** – deduplication, lz4 compression, AES‑256 `repokey` encryption, mountable archives.
- **Safe Restore & Drill Mode** – extracts archives to an isolated target directory; live data is never touched by default.
- **Automated Restore verification** – `ukwinika_automated_restore.sh` runs six verification checks against the most recent archive and reports results via Slack, email, and Prometheus.
- **Real‑Time Monitoring** – inotify triggers a full backup on file change, using a lock-safe child process.
- **Database-aware** – pre-backup dumps for MySQL, PostgreSQL, and MongoDB; unknown `DB_TYPE` aborts immediately.
- **Pre/Post Hooks** – custom scripts before and after each backup, with configurable failure behaviour.
- **Failure Notifications** – Slack and email alerts fire on both backup and restore drill success and failure.
- **Prometheus Metrics** – backup and restore drill metrics written to the same textfile collector output.
- **SHA256 Audit Trail** – checksums of all repository objects logged after every backup and every drill.
- **Stale Lock Prevention** – separate lock files for backup and restore; each is automatically removed on exit.
- **Systemd & Logrotate** – five units and log rotation included and ready to deploy.
- **Cross-Distribution** – Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, CentOS.

---

## Repository Structure

```
ukwinika-backups/
├── enhanced_automated_backups.sh          # Main backup script 
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
│   ├── ukwinika_automated_restore.sh      # Automated monthly restore drill 
│   ├── ukwinika-restore-test.service      # Systemd oneshot service for the drill
│   └── ukwinika-restore-test.timer        # Monthly timer (15th of each month, 02:30)
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

## Quick Start

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git

cd ukwinika-backups

# Installs both scripts and dependencies
sudo make install        

# Deploys all systemd units and logrotate
sudo make systemd        
```

Follow the full setup below.

---

## Full Setup (Debian / RHEL)

### 1. Configure the secrets file

```bash
sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets

sudo chmod 600 /etc/ukwinika-backup.secrets

sudo nano /etc/ukwinika-backup.secrets
```

Set `BORG_PASSPHRASE` to a strong, unique passphrase. Optionally add `SLACK_WEBHOOK` and `EMAIL_TO`.

### 2. Configure the main config file

```bash
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf

sudo chmod 600 /etc/ukwinika-backup.conf

sudo nano /etc/ukwinika-backup.conf
```

Key settings to review: `BORG_REPO`, `BACKUP_PATHS`, `EXCLUDE_DIRS`, `USB_MOUNT`, `USB_RSYNC_TARGET`, `CLOUD_REMOTE`, `DB_TYPE`. See the [Configuration Reference](#configuration-reference) below.

### 3. Initialise the Borg Repository

```bash
sudo enhanced_automated_backups.sh init
```

Creates the repository at the path set in `BORG_REPO` (default `/UKwinikaBackup/borg-repo`) using `repokey` encryption. Running this again on an existing valid repository does nothing.

### 4. Test a Backup

```bash
sudo enhanced_automated_backups.sh backup

sudo tail -f /var/log/UKwinikaBackup.log
```

### 5. Enable Daily Scheduled Backups

```bash
sudo systemctl enable --now ukwinika-backup.timer
```

### 6. (Optional) Enable Real-Time Monitoring

```bash
sudo systemctl enable --now ukwinika-realtime-backup.service
```

Watches directories in `REAL_TIME_DIRS` (default `/etc` and `/home`) and triggers a **scoped** backup (only those paths, not full `BACKUP_PATHS`) after a debounce period (`REAL_TIME_DEBOUNCE_SEC`, default 60s).

### 7. Enable Automated Monthly Restore Drills

```bash
sudo systemctl enable --now ukwinika-restore-test.timer
```

Runs a full Automated Restore Drill on the 15th of each month at 02:30. Results are written to `/var/log/UKwinikaRestore.log`, the shared audit log, and sent via Slack and email. See [Automated Restore Drill](#automated-restore-drill) below.

---

## Usage

### Backup Script

| Command | Description |
|---|---|
| `sudo enhanced_automated_backups.sh backup` | Full backup cycle (primary → USB → cloud) |
| `sudo enhanced_automated_backups.sh restore <archive> [target]` | Restore archive to a target directory |
| `sudo enhanced_automated_backups.sh list` | List all archives in the repository |
| `sudo enhanced_automated_backups.sh check` | Verify repository integrity (`borg check`) |
| `sudo enhanced_automated_backups.sh init` | Initialise a new Borg repository |
| `sudo enhanced_automated_backups.sh real-time` | Start inotify monitoring manually |

```bash
# Run a backup
sudo enhanced_automated_backups.sh backup

# Safe restore to a test directory (live data never touched)
sudo enhanced_automated_backups.sh restore debian-2026-06-17_02:00:45 /mnt/restore-test

# Restore to the default /tmp location
sudo enhanced_automated_backups.sh restore debian-2026-06-17_02:00:45

# List available archives
sudo enhanced_automated_backups.sh list

# Run a full integrity check on the repository
sudo enhanced_automated_backups.sh check
```

### Restore Drill Script

| Command | Description |
|---|---|
| `sudo ukwinika_automated_restore.sh test` | Drill against the most recent archive |
| `sudo ukwinika_automated_restore.sh test <archive_name>` | Drill against a specific archive |
| `sudo ukwinika_automated_restore.sh list` | List all available archives |
| `sudo ukwinika_automated_restore.sh clean` | Remove all drill directories under `RESTORE_TARGET_BASE` |

```bash
# Run a drill against the most recent archive (standard monthly use)
sudo ukwinika_automated_restore.sh test

# Run a drill against a specific archive
sudo ukwinika_automated_restore.sh test debian-2026-06-15_02:00:33

# Check what archives are available
sudo ukwinika_automated_restore.sh list

# Clean up all drill directories
sudo ukwinika_automated_restore.sh clean

# Watch the drill in progress
sudo tail -f /var/log/UKwinikaRestore.log
```

---

## Automated Restore Drill

The `ukwinika_automated_restore.sh` script automates the manual procedure described in `docs/RESTORE-CHECKLIST.md`. It is designed to run unattended via systemd every month and reports its results without any human interaction required.

### How it works

On each run the script:

1. Performs a **full `borg check`** repository integrity scan (appropriate for monthly depth).
2. Verifies **free disk space** — requires at least 110% of the archive's uncompressed size.
3. **Extracts** the most recent archive to an isolated directory under `RESTORE_TARGET_BASE` (default `/var/lib/ukwinika/restore-drills/`). Live data is never touched.
4. Runs **six independent verification checks** against the extracted data, recording each as `[PASS]` or `[FAIL]`.
5. Writes a structured result to the **audit log** (`/var/log/UKwinikaBackup_audit.log`).
6. Updates **Prometheus metrics** (atomic rewrite of backup + restore sections).
7. Sends a **Slack and email notification** with the overall result and check summary.
8. **Cleans up** the drill directory on PASS; preserves it on FAIL for inspection (configurable).

### The six verification checks

| # | Check | What it confirms |
|---|---|---|
| 1 | Non-empty extraction | The drill directory contains files after extraction |
| 2 | Mandatory paths present | `etc/hostname`, `etc/os-release`, `etc/fstab` exist (configurable) |
| 3 | Minimum file count | At least 100 files restored (configurable) |
| 4 | SHA256 spot-check | Key files match checksums recorded in the audit log at backup time |
| 5 | No zero-byte files | No unexpectedly empty files in `/etc`, `/usr`, `/bin` |
| 6 | Archive metadata readable | `borg info` returns hostname and creation time |

All six checks run regardless of individual failures, so the complete picture is always captured in a single run.

### Restore Drill Configuration

Add any of these to `/etc/ukwinika-backup.conf`:

| Variable | Default | Description |
|---|---|---|
| `RESTORE_TARGET_BASE` | `/var/lib/ukwinika/restore-drills` | Base directory for drill extractions |
| `RESTORE_VERIFY_PATHS` | `"etc/hostname etc/os-release etc/fstab"` | Space-separated relative paths that must be present |
| `RESTORE_MIN_FILES` | `100` | Minimum file count the restore must contain |
| `RESTORE_KEEP_ON_FAILURE` | `yes` | Preserve the drill directory on failure for inspection |
| `RESTORE_DRILL_LOG` | `/var/log/UKwinikaRestore.log` | Dedicated restore drill log path |

---

## Configuration Reference

All non-sensitive settings go in `/etc/ukwinika-backup.conf`. The path can be overridden with `UKW_CONFIG`.

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
| `REAL_TIME_DEBOUNCE_SEC` | `60` | Seconds to wait after last change before a real-time backup |
| `EMAIL_TO` | _(empty)_ | Email address for success/failure notifications |
| `METRICS_ENABLED` | `yes` | Write Prometheus metrics (`yes` / `no`) |
| `PROMETHEUS_FILE` | `/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom` | Prometheus textfile output path |
| `CHECKSUM_FILE` | `/tmp/ukwinika-backup-checksums.txt` | Path for post-backup SHA256 checksum file |
| `RESTORE_TARGET_BASE` | `/var/lib/ukwinika/restore-drills` | Base directory for restore drill extractions |
| `RESTORE_VERIFY_PATHS` | `"etc/hostname etc/os-release etc/fstab"` | Paths that must exist in the restored data |
| `RESTORE_MIN_FILES` | `100` | Minimum restored file count |
| `RESTORE_KEEP_ON_FAILURE` | `yes` | Preserve drill directory on failure |
| `RESTORE_DRILL_LOG` | `/var/log/UKwinikaRestore.log` | Dedicated restore drill log path |

> **Array syntax:** `BACKUP_PATHS` and `EXCLUDE_DIRS` must use proper bash array syntax: `BACKUP_PATHS=("/home" "/etc")`. A plain string will not work correctly.

---

## Secrets Reference

All sensitive values go in `/etc/ukwinika-backup.secrets` (mode `0600`). The path can be overridden with `UKW_SECRETS`.

| Variable | Required | Description |
|---|---|---|
| `BORG_PASSPHRASE` | **Yes** | Borg `repokey` encryption passphrase. Both scripts abort if unset. |
| `SLACK_WEBHOOK` | No | Slack incoming webhook URL for backup and restore drill notifications |
| `EMAIL_TO` | No | Can be set here if the address is considered sensitive |

---

## Where Backups Are Stored (3‑2‑1)

| Copy | Location | How |
|---|---|---|
| Primary | `$BORG_REPO` (default `/UKwinikaBackup/borg-repo`) | Borg archive (deduplicated, encrypted) |
| Secondary | `$USB_RSYNC_TARGET` on removable USB | `rsync -a --delete` — exact mirror |
| Tertiary | `$CLOUD_REMOTE/borg_repo` via rclone | `rclone copy` — incremental upload |

Archive names follow the pattern: `<hostname>-<YYYY-MM-DD_HH:MM:SS>`

---

## How to Restore a File or Folder

### Using the Backup Script (recommended)

```bash
# Restore an entire archive to a safe location
sudo enhanced_automated_backups.sh restore <archive_name> /desired/target

# Drill mode — restore to /tmp to verify without risk
sudo enhanced_automated_backups.sh restore <archive_name>
```

### Manual Borg commands

```bash
# List archives
sudo borg list /UKwinikaBackup/borg-repo

# Extract a specific file or folder
sudo borg extract --strip-components 1 \
    /UKwinikaBackup/borg-repo::<archive> path/to/file

# Browse an archive as a read-only filesystem
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg-repo::<archive> /mnt/borg-restore
ls /mnt/borg-restore
sudo borg umount /mnt/borg-restore
```

For a guided monthly drill see `docs/RESTORE-CHECKLIST.md`, or let `ukwinika_automated_restore.sh` do it automatically.

---

## Database Support

Set `DB_TYPE` in the config file to `mysql`, `postgresql`, or `mongodb`. The dump runs before the Borg archive and is included in it automatically. Any unknown value aborts the backup immediately.

For MySQL on Debian/Ubuntu, create a credentials file so `mysqldump` does not prompt for a password:

```bash
sudo bash -c 'cat > /root/.my.cnf << EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```

---

## Hooks

Place executable scripts at the paths configured in `PRE_HOOK` and `POST_HOOK`. Example skeletons are in the `hooks/` directory.

- `PRE_HOOK` runs before the database dump and Borg archive (e.g. stop services, flush DB logs).
- `POST_HOOK` runs after notifications are sent (e.g. restart services, custom alerts).
- `HOOK_FAIL_ACTION=fatal` aborts the backup on hook failure (default).
- `HOOK_FAIL_ACTION=warn` logs a warning and continues.

---

## Notifications

Slack and email alerts are sent on **both success and failure** for both the backup script and the restore drill script. Configure `SLACK_WEBHOOK` in the secrets file and/or `EMAIL_TO` in either file. Both channels fail silently — a broken webhook will never prevent a backup or drill from running.

Notification subjects:
- Backup: `UKwinika Backup SUCCESS` / `UKwinika Backup FAILED: <reason>`
- Restore drill: `UKwinika Restore Drill PASSED` / `UKwinika Restore Drill FAILED`

---

## Prometheus Metrics

When `METRICS_ENABLED=yes`, both scripts write metrics to `PROMETHEUS_FILE`. The restore script appends its metrics to the same file so a single textfile collector scrape covers both. The parent directory is created automatically.

Configure the Node Exporter:

```
--collector.textfile.directory=/var/lib/prometheus/node_exporter/custom
```

| Metric | Type | Source |
|---|---|---|
| `ukwinika_backup_last_success_seconds` | gauge | Backup script |
| `ukwinika_backup_latest_archive` | gauge (name label) | Backup script |
| `ukwinika_restore_test_last_run_seconds` | gauge | Restore script |
| `ukwinika_restore_test_last_result` | gauge (archive label, 1=pass/0=fail) | Restore script |
| `ukwinika_restore_test_checks_passed` | gauge | Restore script |
| `ukwinika_restore_test_checks_failed` | gauge | Restore script |

Useful alert rules: fire if `time() - ukwinika_backup_last_success_seconds > 86400` (backup overdue), or if `ukwinika_restore_test_last_result == 0` (last drill failed).

---

## Systemd Integration

| Unit | Location | Purpose |
|---|---|---|
| `ukwinika-backup.timer` | `systemd/` | Triggers backup service daily at 02:00 ± 30 min |
| `ukwinika-backup.service` | `systemd/` | One-shot backup. `Nice=19`, `IOSchedulingClass=idle` |
| `ukwinika-realtime-backup.service` | `systemd/` | inotify monitoring; scoped backups with debounce; same hardening as daily backup |
| `ukwinika-restore-test.timer` | `backuprestore/` | Triggers restore drill monthly on the 15th at 02:30 ± 30 min |
| `ukwinika-restore-test.service` | `backuprestore/` | One-shot restore drill. Same hardening as backup service |

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
```

---

## Security & Best Practices

- `BORG_PASSPHRASE` and webhook URLs live exclusively in `/etc/ukwinika-backup.secrets` (mode `0600`). The passphrase is passed to Borg subprocesses only — not exported to the global environment.
- Config and secrets files must be mode `600` or `400` and owned by root; both scripts enforce this at startup.
- Always exclude your Borg repository from `BACKUP_PATHS` (included by default in `EXCLUDE_DIRS` as `/UKwinikaBackup`; also auto-excluded at runtime).
- Borg uses `repokey` encryption (AES‑256). **Never lose the passphrase or repository key.** Export the key with `borg key export` and store it separately from the repository.
- Both scripts use `flock` with separate lock files — they can run independently without blocking each other.
- Restrict both scripts: `chmod 700 /usr/local/bin/enhanced_automated_backups.sh /usr/local/bin/ukwinika_automated_restore.sh`.
- The restore script is entirely non-destructive — it never writes outside `RESTORE_TARGET_BASE`.
- For immutable off-site protection, use object storage with versioning and deletion protection (e.g. AWS S3 Object Lock).
- Run **monthly restore drills** — either via `ukwinika-restore-test.timer` (automated) or `docs/RESTORE-CHECKLIST.md` (manual).

---

## Troubleshooting

| Symptom | Likely cause | Solution |
|---|---|---|
| `Repository not found at ...` | `init` never run | `sudo enhanced_automated_backups.sh init` |
| `BORG_PASSPHRASE is not set` | Secrets file missing, wrong path, or wrong permissions | Ensure `/etc/ukwinika-backup.secrets` exists, mode `0600`, and contains `BORG_PASSPHRASE=...` |
| `borg create failed` | Disk full, passphrase mismatch, or corruption | Check logs; run `check` subcommand |
| Real-time monitoring not starting | `inotify-tools` missing | `sudo make install` |
| MySQL dump fails | Missing `/root/.my.cnf` | Create the credentials file (see [Database Support](#database-support)) |
| `Failed to mount USB` | USB not connected or bad `/etc/fstab` entry | Verify device and `USB_MOUNT` value |
| `USB_RSYNC_TARGET must be inside USB_MOUNT` | Misconfigured rsync destination | Set target under the USB mount point |
| `USB_MOUNT is on the same block device as /` | Dangerous rsync target | Fix fstab so USB is a separate device |
| `Refusing to run: ... insecure mode` | Config/secrets world-readable | `sudo chmod 600 /etc/ukwinika-backup.conf /etc/ukwinika-backup.secrets` |
| `Another backup instance is already running` | Stale lock after `kill -9` | If no backup is running: `rm -f /var/lock/ukwinika-backup.lock` |
| `Another restore drill is already running` | Stale restore lock | If no drill is running: `rm -f /var/lock/ukwinika-restore-test.lock` |
| Restore drill `[FAIL] Too few files` | Partial extraction or very small backup | Check `RESTORE_MIN_FILES`; inspect the preserved drill directory |
| Restore drill `[FAIL] Checksum mismatch` | Archive data integrity concern | Run `sudo enhanced_automated_backups.sh check`; investigate audit log |
| Restore drill `[FAIL] Mandatory paths missing` | `RESTORE_VERIFY_PATHS` lists paths not in archive | Review `BACKUP_PATHS` — the paths may have been excluded |
| Restore drill directory not cleaned up | `RESTORE_KEEP_ON_FAILURE=yes` and a check failed | Inspect then remove manually, or set `RESTORE_KEEP_ON_FAILURE=no` |
| Prometheus file not updating | Wrong `PROMETHEUS_FILE` or `METRICS_ENABLED=no` | Verify config; directory is created automatically |
| No Slack/email on failure | Was a bug in ≤ 3.1 | Upgrade to 3.2+; `die()` now notifies on failure |

---

## RHEL‑Specific Notes

- The `Makefile` enables the **EPEL** repository automatically and installs `borgbackup` and `inotify-tools` via `dnf`.
- RHEL proper requires a valid subscription. Rocky Linux and AlmaLinux work without one.
- The Prometheus textfile directory may need to be created manually if Node Exporter is installed in a non-standard location.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Open a [Discussion](https://github.com/UkwiNux/ukwinika-backups/discussions) for questions, or file a [Bug Report or Feature Request](https://github.com/UkwiNux/ukwinika-backups/issues) using the provided templates.

---

## License

MIT License – see the [LICENSE](LICENSE) file for details.

---

> **UKwinika Notable Advice: A Backup is Only as Good as its Last Successful Restore. Test Monthly.**
