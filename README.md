# UKwinika Enhanced Automated Backup Script

**Exclusive Production-Ready Linux Backup Solution** with Borg (recommended), Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media, Ansible Support, and Ransomware-Resistant Design.

**Author:** Urayayi Kwinika  
**Version:** 2.2  
**Last Updated:** April 2026  
**License:** MIT

## Features
- Backup modes: `backup`, `real-time` (inotify), `restore` (with safe drill mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- Optional tools: rsync, rsnapshot, duplicity
- Adaptive DB dumps (MySQL, PostgreSQL, Oracle) with optional LVM snapshots
- External configuration, pre/post hooks, Prometheus metrics export
- Concurrency locking, strict error handling, atomic operations
- Removable USB auto-detection, retention policy, detailed audit trail with SHA256
- Systemd timers + logrotate ready
- **Full Debian/Ubuntu auto-install support** — Makefile installs Borg + inotify-tools
- **Improved Borg lock handling** (v2.2) — `--max-lock-wait 300` + automatic stale lock breaker

## Repository Structure
```bash
ukwinika-backups/
├── README.md
├── LICENSE
├── .gitignore
├── Makefile                  
├── enhanced_automated_backups.sh       # Main production script (v2.2)
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
Get started in minutes using the provided **Makefile**.

### Option 1: From Release Tarball (Recommended for Production)
```bash
tar -xzf ukwinika-backups-v2.2.tar.gz
cd ukwinika-backups-v2.2
sudo make install     # Auto-installs Borg + inotify-tools
sudo make systemd
```

### Option 2: From Git Clone
```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
```

## Where Backups Are Stored
All backups are stored in a **single Borg repository** at:

```
/UKwinikaBackup/borg_repo
```

- Every backup run creates a new **archive** inside this repository.
- Archive names follow the pattern: `system_backup_incremental_YYYYMMDD_HHMMSS` or `system_backup_full_YYYYMMDD_HHMMSS`.
- Borg automatically deduplicates data, so incremental backups remain small and efficient.
- The repository contains the **full history** of all your backups.

To list all archives:
```bash
sudo borg list /UKwinikaBackup/borg_repo
```

## Full Installation & Setup

1. **Install Script & Dependencies**  
   ```bash
   sudo make install
   ```

2. **Create Secure Passphrase**  
   ```bash
   # Remember to set your Pass Phrase Here
   sudo bash -c 'echo "YourStrongPassphraseHere123!" > /etc/ukwinika-backup.secrets'
   sudo chmod 600 /etc/ukwinika-backup.secrets
   ```

3. **Initialize Borg Repository**  
   ```bash
   sudo mkdir -p /UKwinikaBackup
   sudo borg init --encryption=repokey /UKwinikaBackup/borg_repo
   ```

4. **Configure Main Settings**  
   ```bash
   sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
   sudo chmod 600 /etc/ukwinika-backup.conf
   sudo nano /etc/ukwinika-backup.conf
   ```

5. **Deploy Systemd & Logrotate**  
   ```bash
   sudo make systemd
   ```

6. **Test the Backup**  
   ```bash
   sudo enhanced_automated_backups.sh backup incremental borg
   ```

7. **Enable Daily Automation**  
   ```bash
   sudo systemctl enable --now ukwinika-backup.timer
   ```

## How to Restore a File or Folder

### Option 1: Using the UKwinika Script (Recommended)
```bash
# Safe Drill Mode (Preview Only)
sudo enhanced_automated_backups.sh restore drill borg system_backup_incremental_20260420_125524

# Full restore of a specific archive
sudo enhanced_automated_backups.sh restore full borg system_backup_incremental_20260420_125524
```

### Option 2: Manual Borg Commands (Advanced Control)
```bash
# List all backups
sudo borg list /UKwinikaBackup/borg_repo

# Restore a single file (example)
sudo borg extract --strip-components 1 \
    /UKwinikaBackup/borg_repo::system_backup_incremental_20260420_125524 \
    etc/hosts

# Restore an entire folder (example)
sudo borg extract --strip-components 1 \
    /UKwinikaBackup/borg_repo::system_backup_incremental_20260420_125524 \
    home/pafariam

# Safe browse mode (mount as virtual filesystem)
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg_repo /mnt/borg-restore
ls /mnt/borg-restore
# When finished:
sudo borg umount /mnt/borg-restore
```
Always test Restores regularly using the commands above.

## Usage Examples
- Incremental backup: `sudo enhanced_automated_backups.sh backup incremental borg`
- Full backup: `sudo enhanced_automated_backups.sh backup full borg`
- Start real-time monitoring: `sudo systemctl start ukwinika-realtime-backup.service`
- View logs: `sudo tail -f /var/log/UKwinikaBackup.log`

## MySQL Database Fix (Debian)
If you see “Access denied” for mysqldump:
```bash
sudo bash -c 'cat > /root/.my.cnf <<EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```

## Troubleshooting (v2.2)
- **Borg lock timeout**: Fixed with `--max-lock-wait 300` + automatic stale lock breaker
- **Passphrase error**: Verify `/etc/ukwinika-backup.secrets` exists and matches the repo passphrase
- **MySQL access denied**: Use the `.my.cnf` fix above
- **Log file permission**: Use `sudo tail -f /var/log/UKwinikaBackup.log`

## Security & Best Practices
- Passphrase stored securely in `/etc/ukwinika-backup.secrets` (600 permissions)
- Replicate the Borg repo to S3 with Object Lock for immutability
- Run monthly restore drills using the commands above
- Never commit secrets or passphrases

**UKwinika Notable Advice: A Backup is Only as Good as its Last Successful Restore.**
