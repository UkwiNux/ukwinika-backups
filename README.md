# UKwinika Enhanced Automated Backup Script (EABS)

**A 3‑2‑1 Backup Solution** with Borg, Real-time Monitoring, Database Consistency, Encryption, Auditing, and Cloud Support.

**Author:** Urayayi Kwinika  
**Version:** 3.1  
**License:** MIT

---

## Features

- **Fully Idempotent** – Safe to run any number of times without side effects.
- **3‑2‑1 Backup Principle** – Primary on Disk, Secondary on Removable USB, Tertiary to Cloud.
- **BorgBackup** – Deduplication, AES‑256 Encryption, Compression, and Mountable Archives.
- **Restore with Safe Drill Mode** – test restores easily without overwriting live data.
- **Real‑time Monitoring** (inotify) – instant backups on file changes.
- **Database‑aware** – adaptive dumps for MySQL, PostgreSQL, and MongoDB.
- **Pre/Post Hooks** – custom scripts before and after each backup.
- **Prometheus Metrics** – monitor backups with a simple metric endpoint.
- **Audit Trail** – SHA256 checksums logged after every backup.
- **Stale Lock Prevention** – lock file is automatically removed on exit.
- **Systemd & Logrotate** – ready for automatic, scheduled execution and log rotation.
- **Cross‑distribution Support** – Debian, Ubuntu, RHEL, Rocky, AlmaLinux, CentOS.
---

## Repository Structure
```
ukwinika-backups/
├── README.md
├── LICENSE
├── .gitignore
├── Makefile
├── enhanced_automated_backups.sh          # Main backup script
├── config/
│   ├── ukwinika-backup.conf.example       # Configuration template
│   └── ukwinika-backup.secrets.example    # Secrets template
├── systemd/
│   ├── ukwinika-backup.service
│   ├── ukwinika-backup.timer
│   └── ukwinika-realtime-backup.service
├── logrotate/
│   └── ukwinika-backup
├── docs/
│   └── RESTORE-CHECKLIST.md
├── hooks/
│   ├── pre_backup_hook.sh.example
│   └── post_backup_hook.sh.example
└── .github/
    └── workflows/
        ├── release.yml
        └── test.yml
```

---

## Quick Start

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git

cd ukwinika-backups

sudo make install        # Installs script and dependencies

sudo make systemd        # Deploys systemd units and logrotate
```

Then follow the **Setup** steps below to configure and initialise the repository.

---

## Full Setup (Debian / RHEL)

Follow these steps **in the respictive order** after cloning the repository.

### 1. Install the Script and Dependencies
```bash
cd ukwinika-backups
sudo make install
```
This installs `borgbackup` and `inotify-tools` if needed, copies the script to `/usr/local/bin/`, and creates the Prometheus metrics directory.

### 2. Copy and Edit Configuration Files
```bash
# Secrets file (must be 600!)
sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets

sudo chmod 600 /etc/ukwinika-backup.secrets

sudo nano /etc/ukwinika-backup.secrets
```
Replace the placeholder passphrase and, optionally, the Slack webhook URL and email address.

```bash
# Main configuration
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf

sudo chmod 600 /etc/ukwinika-backup.conf

sudo nano /etc/ukwinika-backup.conf
```
Adjust paths, retention, USB mount point, database type, and hook locations as needed.

### 3. Initialise the Borg Repository
```bash
sudo enhanced_automated_backups.sh init
```
You’ll be prompted for the passphrase – use the one you placed in the secrets file.  
The repository is created at `/UKwinikaBackup/borg-repo` (configurable in `ukwinika-backup.conf`).

### 4. Deploy Systemd Services and Logrotate
```bash
sudo make systemd
```
This installs the daily timer, the main backup service, the real‑time monitoring service, and the logrotate configuration.

### 5. Test a Backup
```bash
sudo enhanced_automated_backups.sh backup
```
Check the logs:
```bash
sudo tail -f /var/log/UKwinikaBackup.log
```

### 6. Enable Daily Scheduled Backups
```bash
sudo systemctl enable --now ukwinika-backup.timer
```

### 7. (Optional) Start Real‑time Monitoring
```bash
sudo systemctl start ukwinika-realtime-backup.service
```
The service monitors directories defined in `REAL_TIME_DIRS` (default: `/etc` and `/home`) and triggers a backup whenever a file changes.

---

## Usage

| Command | Description |
|--------|-------------|
| `sudo enhanced_automated_backups.sh backup` | Full backup cycle |
| `sudo enhanced_automated_backups.sh restore <archive> [target]` | Restore an archive to a target directory |
| `sudo enhanced_automated_backups.sh list` | List all archives |
| `sudo enhanced_automated_backups.sh check` | Verify repository integrity |
| `sudo enhanced_automated_backups.sh init` | Initialise a new Borg repository |
| `sudo enhanced_automated_backups.sh real-time` | Start real‑time monitoring manually |

**Examples:**
```bash
# Run a backup
sudo enhanced_automated_backups.sh backup

# Safe restore (files go to /tmp/restore_<archive> by default)
sudo enhanced_automated_backups.sh restore debian-2026-04-25_08:20:17 /mnt/restore-test

# List available archives
sudo enhanced_automated_backups.sh list
```

---

## Where Backups Are Stored (3‑2‑1)

- **Primary copy:** `/UKwinikaBackup/borg-repo` (system disk)
- **Secondary copy:** Removable USB (mounted at the path defined in `USB_MOUNT`)
- **Tertiary copy:** Cloud storage via `rclone` if `CLOUD_REMOTE` is configured

Archive names follow the pattern: `<hostname>-<YYYY-MM-DD_HH:MM:SS>`

---

## How to Restore a File or Folder

### Using the Script (Recommended)
```bash
sudo enhanced_automated_backups.sh restore <archive_name> /desired/target
```
This safely extracts the archive to the given target without overwriting live data.  
**Drill mode:** run the restore to a temporary directory like `/tmp/restore_drill` to verify contents.

### Manual Borg Commands
```bash
# List archives
sudo borg list /UKwinikaBackup/borg-repo

# Extract a specific file/folder
sudo borg extract --strip-components 1 /UKwinikaBackup/borg-repo::<archive> path/to/file

# Browse an archive as a filesystem
sudo mkdir -p /mnt/borg-restore

sudo borg mount /UKwinikaBackup/borg-repo /mnt/borg-restore

ls /mnt/borg-restore

sudo borg umount /mnt/borg-restore
```
---

## Database Support

Set `DB_TYPE` in the configuration file to `mysql`, `postgresql`, or `mongodb`.  
For MySQL on Debian/Ubuntu, you may need to create a credentials file:

```bash
sudo bash -c 'cat > /root/.my.cnf <<EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```

---

## Troubleshooting

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| `Borg create failed` | Repository not initialised | Run `sudo enhanced_automated_backups.sh init` |
| Real‑time monitoring not working | `inotify-tools` missing | `sudo make install` (installs it automatically) |
| MySQL access denied | Missing or incorrect `.my.cnf` | Create `/root/.my.cnf` with valid credentials |
| Passphrase prompt during backup | Secrets file missing or incorrect permissions | Ensure `/etc/ukwinika-backup.secrets` exists, is mode `0600`, and contains `BORG_PASSPHRASE` |

---
## Security & Best Practices

- The passphrase and any webhook/email credentials live exclusively in `/etc/ukwinika-backup.secrets` (mode `0600`).
- Borg uses `repokey` encryption – **never lose your passphrase or repository key**.
- The script uses file locking (`flock`) to prevent concurrent executions.
- Rotate logs with the provided logrotate configuration.
- Run monthly restore drills using the checklist in `docs/RESTORE-CHECKLIST.md`.
---
## RHEL‑Specific Notes

- The `Makefile` enables the EPEL repository and installs `borgbackup` via `dnf`.
- Make sure your system is subscribed (RHEL) or that you are using a compatible derivative (Rocky, AlmaLinux, CentOS).
---
> **UKwinika Notable Advice: Remember A Backup is Only as Good as its Last Successful Restore. Test Regularly.**

## License

This project is licensed under the MIT License – see the `LICENSE` file for details.
