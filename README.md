# UKwinika Enhanced Automated Backup Script

**Exclusive Production-Ready Linux Backup Solution** with Borg (recommended), Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media, Ansible Support, and Ransomware-Resistant Design.

**Author:** Urayayi Kwinika  
**Version:** 2.0  
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

## Repository Structure
```bash
ukwinika-backups/
├── README.md
├── LICENSE
├── .gitignore
├── Makefile                  
├── enhanced_automated_backups.sh       # Main production script
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

**New in this update:** `sudo make install` now automatically installs BorgBackup on Debian/Ubuntu systems.

### Option 1: From Release Tarball (Recommended for Production)
1. Download the latest `ukwinika-backups-v2.0.tar.gz` from the [GitHub Releases](https://github.com/UkwiNux/ukwinika-backups/releases) page.
2. Extract it:
   ```bash
   tar -xzf ukwinika-backups-v2.0.tar.gz
   cd ukwinika-backups-v2.0
   ```
3. Install and deploy using the Makefile:
   ```bash
   sudo make install     # Installs script + Borg (Debian auto-detect)
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
The Makefile now **automatically installs BorgBackup** on Debian/Ubuntu during `sudo make install`. No manual `apt install` needed.

### 2. Install the Script & Borg
```bash
cd ukwinika-backups
sudo make install     # ← Automatically installs Borg on Debian + patches script for compatibility
```

### 3. Create Secure Passphrase (Required for Borg encryption)
```bash
# Use a strong, unique passphrase (20+ characters)
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

## Scheduling & Automation
- Daily backups via `ukwinika-backup.timer` (runs at 02:00 with random delay)
- Real-time daemon via `ukwinika-realtime-backup.service`
- Log rotation handled automatically

## Security & Best Practices
- Passphrase is stored securely in `/etc/ukwinika-backup.secrets` (600 permissions)
- Borg uses `repokey` encryption on Debian (fully compatible with 1.4)
- Replicate Borg repo to S3 with **Object Lock** (Compliance mode) for immutability
- Run monthly restore drills (see `docs/RESTORE-CHECKLIST.md`)
- Never commit passphrases or config files containing secrets

## Troubleshooting
- **Passphrase error** → Check `/etc/ukwinika-backup.secrets` exists and matches the repo passphrase
- **Borg not found** → Re-run `sudo make install` (auto-fixes)
- **Log file missing** → First backup creates `/var/log/UKwinikaBackup.log`
- **Debian-specific** → The Makefile automatically patches the script for Borg 1.4 compatibility
- Borg health check: `sudo borg check /UKwinikaBackup/borg_repo`


**UKwinika's Notable Advice: A Backup is Only as Good as its Last Successful Restore.**
