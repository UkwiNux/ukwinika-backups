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
- **Full Debian/Ubuntu support** — Makefile auto-installs Borg + inotify-tools
- **Improved Borg lock handling** (v2.2) — automatic stale lock breaker + 5-minute timeout

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
**Recommended for Production**

### Option 1: From Release Tarball
```bash
tar -xzf ukwinika-backups-v2.2.tar.gz && cd ukwinika-backups-v2.2
sudo make install     # Auto-installs Borg + inotify-tools + improved lock handling
sudo make systemd
```

### Option 2: From Git Clone
```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
```

## Full Installation & Setup

1. **Install Script + Dependencies**  
   ```bash
   sudo make install
   ```

2. **Create Secure Passphrase**  
   ```bash
   # Type your Pass Phrase Here
   sudo bash -c 'echo "YourStrongPassphraseHere123!" > /etc/ukwinika-backup.secrets'
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

5. **Deploy Services**  
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

## MySQL Database Fix (Debian)
```bash
sudo bash -c 'cat > /root/.my.cnf <<EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```

## Usage Examples
- Incremental backup: `sudo enhanced_automated_backups.sh backup incremental borg`
- Full backup: `sudo enhanced_automated_backups.sh backup full borg`
- Real-time monitoring: `sudo systemctl start ukwinika-realtime-backup.service`
- View logs: `sudo tail -f /var/log/UKwinikaBackup.log`

## Troubleshooting (v2.2)

- **Borg lock timeout** (`Failed to create/acquire the lock`):  
  Automatically handled in v2.2 with `--max-lock-wait 300` and stale lock breaker.  
  Manual recovery: `sudo borg break-lock /UKwinikaBackup/borg_repo`

- **Borg encryption error**: Fixed since v2.1
- **inotify-tools warning**: Fixed automatically by `make install`
- **MySQL Access denied**: Use the `.my.cnf` fix above
- **Passphrase error**: Verify `/etc/ukwinika-backup.secrets` exists and matches your repo

**New in v2.2**: Automatic stale lock detection and 5-minute lock wait time for more reliable backups.

**UKwinika Notable Advice: A Backup is only as Good as its Last Successful Restore.**
