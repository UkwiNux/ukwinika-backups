# UKwinika Enhanced Automated Backup Script

**A Linux Backup Solution** with Borg (recommended), Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media and Ansible Support.

**Author:** Urayayi Kwinika  
**Version:** 2.3  
**Last Updated:** April 2026  
**License:** MIT

## Features (Fully Implemented in v2.3)
- Backup modes: `backup`, `real-time` (inotify), `restore` (with safe drill mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- Optional tools: rsync, rsnapshot, duplicity (ready for future expansion)
- Adaptive DB dumps (MySQL, PostgreSQL, Oracle) with optional LVM snapshots for hot consistency
- Pre/post backup hooks support
- Prometheus metrics export
- Removable USB auto-detection
- Concurrency locking (`flock`)
- Detailed audit trail with SHA256 checksums
- Improved Borg lock handling (`--max-lock-wait 300` + automatic stale lock breaker)
- Systemd timers + logrotate ready
- Full Debian/Ubuntu auto-install support

## Repository Structure
```bash
ukwinika-backups/
├── README.md
├── LICENSE
├── .gitignore
├── Makefile                  
├── enhanced_automated_backups.sh       # Main production script (v2.3)
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
```bash
sudo make install     # Auto-installs Borg + inotify-tools + creates Prometheus directory
sudo make systemd
```

## Full Installation & Setup

1. **Install Script & Dependencies**  
   ```bash
   sudo make install
   ```

2. **Create Secure Passphrase**  
   ```bash
   # Remember to set your Pass Phrase Here
   sudo bash -c 'echo "YourStrongPassPhraseHere123!" > /etc/ukwinika-backup.secrets'
   sudo chmod 600 /etc/ukwinika-backup.secrets
   ```

3. **Initialize Borg Repository**  
   ```bash
   sudo mkdir -p /UKwinikaBackup
   sudo borg init --encryption=repokey /UKwinikaBackup/borg_repo
   ```

4. **Configure**  
   ```bash
   sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
   sudo chmod 600 /etc/ukwinika-backup.conf
   sudo nano /etc/ukwinika-backup.conf
   ```

5. **Deploy Systemd & Logrotate**  
   ```bash
   sudo make systemd
   ```

6. **Test Backup**  
   ```bash
   sudo enhanced_automated_backups.sh backup incremental borg
   ```

7. **Enable Daily Automation**  
   ```bash
   sudo systemctl enable --now ukwinika-backup.timer
   ```
## Where Backups Are Stored
All backups are stored in a **single Borg repository** at:

```
/UKwinikaBackup/borg_repo
```

Archive names follow the pattern: `system_backup_incremental_YYYYMMDD_HHMMSS` or `system_backup_full_YYYYMMDD_HHMMSS`.

## How to Restore a File or Folder

**Using the Script (Recommended):**
```bash
# Safe Drill Mode (Preview Only)
sudo enhanced_automated_backups.sh restore drill borg system_backup_incremental_20260420_125524

# Full Restore
sudo enhanced_automated_backups.sh restore full borg system_backup_incremental_20260420_125524
```

**Manual Borg commands:**
```bash
sudo borg list /UKwinikaBackup/borg_repo
sudo borg extract --strip-components 1 /UKwinikaBackup/borg_repo::ARCHIVE_NAME path/to/file-or-folder
```

**Browse Mode:**
```bash
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg_repo /mnt/borg-restore
ls /mnt/borg-restore
sudo borg umount /mnt/borg-restore
```
Always test Restores regularly using the commands above.

## Usage Examples
- Incremental backup: `sudo enhanced_automated_backups.sh backup incremental borg`
- Full backup: `sudo enhanced_automated_backups.sh backup full borg`
- Real-time monitoring: `sudo systemctl start ukwinika-realtime-backup.service`
- View logs: `sudo tail -f /var/log/UKwinikaBackup.log`

## MySQL / Database Fix (Debian)
```bash
sudo bash -c 'cat > /root/.my.cnf <<EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```
## Troubleshooting
- Borg lock timeout → Fixed in v2.3
- Real-time not working → Ensure `inotify-tools` is installed
- MySQL access denied → Use the `.my.cnf` fix above

**UKwinika Notable Advice: A Backup is Only as Good as its Last Successful Restore.**
