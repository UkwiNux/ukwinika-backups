# UKwinika Enhanced Automated Backup Script

**Exclusive Production-Ready Linux Backup Solution** with Borg (recommended), Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media, Ansible Support, and Ransomware-Resistant Design.

**Author:** Urayayi Kwinika  
**Version:** 2.1  
**Last Updated:** April 2026  
**License:** MIT

## Features
- Backup modes: `backup`, `real-time` (inotify), `restore` (with safe drill mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- Optional tools: rsync, rsnapshot, duplicity
- Adaptive DB dumps (MySQL, PostgreSQL, Oracle) with optional LVM snapshots for hot consistency
- External configuration, pre/post hooks, Prometheus metrics export
- Concurrency locking (`flock`), strict error handling, atomic operations
- Removable USB auto-detection, retention policy, detailed audit trail with SHA256
- Systemd timers + logrotate ready
- **Debian/Ubuntu auto-detection** — Makefile now installs Borg + inotify-tools automatically

## Repository Structure
```bash
ukwinika-backups/
├── README.md
├── LICENSE
├── .gitignore
├── Makefile                  
├── enhanced_automated_backups.sh       # Main production script (v2.1)
├── config/
│   └── ukwinika-backup.conf.example
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
├── .github/
│   └── workflows/
│       └── test.yml
└── CONTRIBUTING.md
```

## Quick Start
Get started in minutes using the provided **Makefile** (recommended for easy installation, systemd deployment, and clean removal).

**New in v2.1:** `sudo make install` now automatically installs BorgBackup **and** inotify-tools on Debian/Ubuntu systems + auto-patches the script for full Borg 1.4 compatibility.

### Option 1: From Release Tarball (Recommended for Production)
1. Download the latest `ukwinika-backups-v2.1.tar.gz` from the [GitHub Releases](https://github.com/UkwiNux/ukwinika-backups/releases) page.
2. Extract it:
   ```bash
   tar -xzf ukwinika-backups-v2.1.tar.gz
   cd ukwinika-backups-v2.1
   ```
3. Install and deploy using the Makefile:
   ```bash
   sudo make install     # Installs script + Borg + inotify-tools (Debian auto-detect)
   sudo make systemd     # Deploys systemd services + logrotate
   ```

### Option 2: From Git Clone (For Development or Latest Changes)
```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
```

**Next steps:** Follow the detailed configuration, Borg initialization, testing, and automation steps in the **Full Installation & Setup** section below. The Makefile also supports `sudo make uninstall` and `sudo make clean` for maintenance.

## Full Installation & Setup (Step-by-Step)

### 1. Prerequisites & Automatic Dependency Installation
The Makefile now **automatically installs**:
- `borgbackup` (Debian 1.4 compatible)
- `inotify-tools` (required for real-time monitoring)

No manual `apt install` commands are needed.

### 2. Install the Script & Dependencies
```bash
cd ukwinika-backups
sudo make install     # ← Automatically installs Borg + inotify-tools + applies Debian fixes
```

### 3. Create Secure Passphrase (Required for Borg encryption)
```bash
# Use a strong, unique passphrase (20+ characters recommended)
sudo bash -c 'echo "YourStrongPassphraseHere123!" > /etc/ukwinika-backup.secrets'
sudo chmod 600 /etc/ukwinika-backup.secrets
```

### 4. Initialize Borg Repository (Debian-compatible)
```bash
sudo mkdir -p /UKwinikaBackup
sudo borg init --encryption=repokey /UKwinikaBackup/borg_repo
# Use the EXACT same passphrase you saved in /etc/ukwinika-backup.secrets
```

### 5. Configure Main Settings
```bash
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
sudo chmod 600 /etc/ukwinika-backup.conf
sudo nano /etc/ukwinika-backup.conf
```

### 6. Deploy Systemd & Logrotate
```bash
sudo make systemd
```

### 7. Test the Backup
```bash
sudo enhanced_automated_backups.sh backup incremental borg
```

### 8. Enable Daily Automation
```bash
sudo systemctl enable --now ukwinika-backup.timer
sudo systemctl status ukwinika-backup.timer
```

## Usage Examples

- **Manual incremental backup**  
  `sudo enhanced_automated_backups.sh backup incremental borg`

- **Full backup**  
  `sudo enhanced_automated_backups.sh backup full borg`

- **Start real-time monitoring** (daemon)  
  `sudo systemctl start ukwinika-realtime-backup.service`

- **Restore in safe drill mode**  
  `sudo enhanced_automated_backups.sh restore drill borg system_backup_full_20260412_140000`

- **Live restore** (emergency)  
  `sudo enhanced_automated_backups.sh restore full borg`

- **View logs**  
  `tail -f /var/log/UKwinikaBackup.log`

## MySQL Database Backup (Important Debian Note)
The script attempts a full `mysqldump`. If you see “Access denied” errors:
```bash
# Create a secure MySQL config (recommended)
sudo bash -c 'cat > /root/.my.cnf <<EOF
[client]
user=root
password=your_mysql_root_password_here
EOF'
sudo chmod 600 /root/.my.cnf
```
Then re-run the backup test. (Replace `your_mysql_root_password_here` with your actual MySQL root password.)

## Scheduling & Automation
- Daily backups via `ukwinika-backup.timer` (runs at ~02:00 with random delay)
- Real-time file monitoring via `ukwinika-realtime-backup.service` (now fully functional)
- Automatic log rotation via logrotate

## Security & Best Practices
- Passphrase stored securely in `/etc/ukwinika-backup.secrets` (600 permissions only)
- Borg uses `repokey` encryption on Debian (fully compatible with Borg 1.4)
- Replicate Borg repo to S3 with **Object Lock** (Compliance mode) for immutability
- Run monthly restore drills (see `docs/RESTORE-CHECKLIST.md`)
- Never commit passphrases or config files containing secrets
- Script v2.1 automatically removes the invalid `--encryption` flag on `borg create`

## Troubleshooting (Debian-Specific)
- **Borg “unrecognized arguments: --encryption”** → Fixed in v2.1 (Makefile patches script automatically)
- **“inotify-tools required”** → Fixed automatically by `sudo make install`
- **MySQL access denied** → See “MySQL Database Backup” section above
- **Passphrase error** → Verify `/etc/ukwinika-backup.secrets` exists and matches the repo passphrase
- **Log file missing** → First successful backup creates `/var/log/UKwinikaBackup.log`
- **Borg health check** → `sudo borg check /UKwinikaBackup/borg_repo`

**ADVICE: A Backup is only as Good as its last Successful Restore.**
