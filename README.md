# UKwinika Enhanced Automated Backup Script (EABS)

**A 3‑2‑1 Backup Solution** built on BorgBackup with real-time monitoring, database dumps, AES-256 encryption, audit trails, Prometheus metrics, and cloud support.

**Author:** Urayayi Kwinika | **Version:** 3.2 | **License:** MIT

---

## Features

- **Fully idempotent** – safe to run any number of times; no stale locks, no duplicate side effects.
- **3‑2‑1 Backup** – primary on disk (Borg), secondary on removable USB (rsync mirror), tertiary to cloud (rclone).
- **BorgBackup** – deduplication, lz4 compression, AES‑256 `repokey` encryption, mountable archives.
- **Safe restore & drill mode** – extracts archives to an isolated target directory; live data is never touched by default.
- **Real‑time monitoring** – inotify triggers a full backup on file change, using a lock-safe child process.
- **Database-aware** – pre-backup dumps for MySQL, PostgreSQL, and MongoDB; unknown `DB_TYPE` aborts immediately.
- **Pre/post hooks** – custom scripts before and after each backup, with configurable failure behaviour.
- **Failure notifications** – Slack and email alerts fire on both success and failure.
- **Prometheus metrics** – exposes last-success timestamp and latest archive name for monitoring.
- **SHA256 audit trail** – checksums of all repository objects logged after every backup.
- **Stale lock prevention** – lock file is automatically removed on any exit (`EXIT`, `INT`, `TERM`).
- **Systemd & logrotate** – timer, services, and log rotation included and ready to deploy.
- **Cross-distribution** – Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, CentOS.

---

## Repository Structure

```
ukwinika-backups/
├── enhanced_automated_backups.sh          # Main backup script (v3.2)
├── Makefile                               # Install, deps, systemd, clean
├── README.md
├── CHANGELOG.md
├── LICENSE
├── SECURITY.md
├── config/
│   ├── ukwinika-backup.conf.example       # Non-sensitive configuration template
│   └── ukwinika-backup.secrets.example    # Sensitive credentials template
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
    └── RESTORE-CHECKLIST.md               # Monthly restore drill checklist
```

---

## Quick Start

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install        # Installs script and dependencies (borgbackup, inotify-tools)
sudo make systemd        # Deploys systemd units and logrotate
```

Then follow the full setup below.

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

### 3. Initialise the Borg repository

```bash
sudo enhanced_automated_backups.sh init
```

Creates the repository at the path set in `BORG_REPO` (default `/UKwinikaBackup/borg-repo`) using `repokey` encryption. Running this again on an existing valid repository does nothing.

### 4. Test a backup

```bash
sudo enhanced_automated_backups.sh backup
sudo tail -f /var/log/UKwinikaBackup.log
```

### 5. Enable daily scheduled backups

```bash
sudo systemctl enable --now ukwinika-backup.timer
```

### 6. (Optional) Enable real-time monitoring

```bash
sudo systemctl enable --now ukwinika-realtime-backup.service
```

Watches directories in `REAL_TIME_DIRS` (default `/etc` and `/home`) and triggers a backup on any file change.

---

## Usage

| Command | Description |
|---|---|
| `sudo enhanced_automated_backups.sh backup` | Full backup cycle (primary → USB → cloud) |
| `sudo enhanced_automated_backups.sh restore <archive> [target]` | Restore archive to a target directory |
| `sudo enhanced_automated_backups.sh list` | List all archives in the repository |
| `sudo enhanced_automated_backups.sh check` | Verify repository integrity (`borg check`) |
| `sudo enhanced_automated_backups.sh init` | Initialise a new Borg repository |
| `sudo enhanced_automated_backups.sh real-time` | Start inotify monitoring manually |

**Examples:**

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
| `EMAIL_TO` | _(empty)_ | Email address for success/failure notifications |
| `METRICS_ENABLED` | `yes` | Write Prometheus metrics (`yes` / `no`) |
| `PROMETHEUS_FILE` | `/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom` | Prometheus textfile output path |
| `CHECKSUM_FILE` | `/tmp/ukwinika-backup-checksums.txt` | Path for post-backup SHA256 checksum file |

> **Array syntax:** `BACKUP_PATHS` and `EXCLUDE_DIRS` must use proper bash array syntax: `BACKUP_PATHS=("/home" "/etc")`. A plain string will not work correctly.

---

## Secrets Reference

All sensitive values go in `/etc/ukwinika-backup.secrets` (mode `0600`). The path can be overridden with `UKW_SECRETS`.

| Variable | Required | Description |
|---|---|---|
| `BORG_PASSPHRASE` | **Yes** | Borg `repokey` encryption passphrase. The script aborts if unset. |
| `SLACK_WEBHOOK` | No | Slack incoming webhook URL for notifications |
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

### Using the script (recommended)

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

Run a **monthly restore drill** using the checklist in `docs/RESTORE-CHECKLIST.md`.

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

Slack and email alerts are sent on **both success and failure**. Configure `SLACK_WEBHOOK` in the secrets file and/or `EMAIL_TO` in either file. Both channels fail silently — a broken webhook will never prevent a backup from running.

---

## Prometheus Metrics

When `METRICS_ENABLED=yes`, the script writes a `.prom` file to `PROMETHEUS_FILE`. The directory is created automatically if it does not exist. Configure the Node Exporter textfile collector to scrape it:

```
--collector.textfile.directory=/var/lib/prometheus/node_exporter/custom
```

Metrics exposed: `ukwinika_backup_last_success_seconds` (gauge) and `ukwinika_backup_latest_archive` (gauge with `name` label).

---

## Systemd Integration

| Unit | Purpose |
|---|---|
| `ukwinika-backup.timer` | Triggers the backup service daily at 02:00 ± 30 min. `Persistent=true` catches missed runs. |
| `ukwinika-backup.service` | One-shot service that runs `backup`. `Nice=19`, `IOSchedulingClass=idle`. |
| `ukwinika-realtime-backup.service` | Keeps `real-time` running; stops after 3 rapid failures to prevent log flooding. |

```bash
# Useful commands
systemctl list-timers ukwinika-backup.timer    # next scheduled run
systemctl start ukwinika-backup.service        # run a backup now
journalctl -u ukwinika-backup.service -f       # live log
systemctl status ukwinika-realtime-backup.service
```

---

## Security & Best Practices

- `BORG_PASSPHRASE` and webhook URLs live exclusively in `/etc/ukwinika-backup.secrets` (mode `0600`). No secret ever appears in arguments or the main config file.
- Borg uses `repokey` encryption (AES‑256). **Never lose the passphrase or repository key.** Export the key with `borg key export` and store it separately from the repository.
- The script uses `flock` to prevent concurrent runs and `set -euo pipefail` to abort on any error.
- Restrict the script itself: `chmod 700 /usr/local/bin/enhanced_automated_backups.sh`.
- For immutable off-site protection, use object storage with versioning and deletion protection (e.g. AWS S3 Object Lock).
- Run **monthly restore drills** — see `docs/RESTORE-CHECKLIST.md`.

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
| `Another backup instance is already running` | Stale lock after `kill -9` | If no backup is running: `rm -f /var/lock/ukwinika-backup.lock` |
| No Slack/email on failure | Was a bug in ≤ 3.1 | Upgrade to 3.2; `die()` now notifies on failure |
| Real-time service stops after 3 failures | Repository missing or config error | Check `journalctl -u ukwinika-realtime-backup.service`; fix config; `systemctl reset-failed` then restart |
| Prometheus file not updating | Wrong `PROMETHEUS_FILE` or `METRICS_ENABLED=no` | Verify config; directory is created automatically in 3.2 |

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
