# UKwinika Enhanced Automated Backup Script [EABS]

**A Linux Backup Solution** with Borg (recommended), Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media, Ansible Support etc.

**Author:** Urayayi Kwinika  
**Version:** 2.3  
**Last Updated:** April 2026  
**License:** MIT

## Features (Fully Implemented in v2.3)
- Backup modes: `backup`, `real-time` (inotify), `restore` (with safe drill mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- Optional tools: rsync, rsnapshot, duplicity (ready for expansion)
- Adaptive DB dumps (MySQL, PostgreSQL, Oracle) with optional LVM snapshots
- Pre/post backup hooks
- Prometheus metrics export
- Removable USB auto-detection
- Concurrency locking with `flock`
- Detailed audit trail with SHA256 checksums
- Improved Borg lock handling (`--max-lock-wait 300` + automatic stale lock breaker)
- **Ansible Integration** for idempotent deployment and configuration management
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

## Quick Start – Clone from GitHub (Recommended for Latest Version)

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install     # Auto-installs Borg + inotify-tools + Prometheus directory
sudo make systemd
```

After installation, follow the **Full Installation & Setup** section below.

## Full Installation & Setup

1. **Clone the Repository**  
   ```bash
   git clone https://github.com/UkwiNux/ukwinika-backups.git
   cd ukwinika-backups
   ```

2. **Install Script and Dependencies**  
   ```bash
   sudo make install
   ```

3. **Create Secure Passphrase File**  
   ```bash
   # Remember to set Your Pass Phrase here
   sudo bash -c 'echo "YourStrongPassphraseHere123!" > /etc/ukwinika-backup.secrets'
   sudo chmod 600 /etc/ukwinika-backup.secrets
   ```

4. **Initialize Borg Repository**  
   ```bash
   sudo mkdir -p /UKwinikaBackup
   sudo borg init --encryption=repokey /UKwinikaBackup/borg_repo
   ```

5. **Configure the Script**  
   ```bash
   sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
   sudo chmod 600 /etc/ukwinika-backup.conf
   sudo nano /etc/ukwinika-backup.conf
   ```

6. **Deploy Systemd Services and Logrotate**  
   ```bash
   sudo make systemd
   ```

7. **Test the Backup**  
   ```bash
   sudo enhanced_automated_backups.sh backup incremental borg
   ```

8. **Enable Daily Automation**  
   ```bash
   sudo systemctl enable --now ukwinika-backup.timer
   ```
## Ansible Integration (v2.3)

UKwinika EABS now includes native Ansible support for large-scale, idempotent deployments.

### Using Ansible
1. Place the provided Ansible role (coming in future releases) or create your own.
2. Example playbook snippet:
   ```yaml
   - name: Deploy UKwinika Backup
     hosts: backup_servers
     roles:
       - ukwinika-backup
   ```
Key Ansible features:
- Idempotent installation via `make install`
- Automatic configuration of `/etc/ukwinika-backup.conf`
- Deployment of systemd services and timers
- Optional inventory-based passphrase and config management
- Role variables for customizing DB_TYPE, retention, real-time directories, etc.

See the `ansible/` directory (planned for v2.4) or use the current Makefile for manual Ansible integration.

## Where Backups Are Stored Locally
All backups are stored in a **single Borg repository** at:

```
/UKwinikaBackup/borg_repo
```
Archive names follow the pattern: `system_backup_incremental_YYYYMMDD_HHMMSS` or `system_backup_full_YYYYMMDD_HHMMSS`.

## How to Restore a File or Folder

**Using the script (recommended):**
```bash
# Safe drill mode (preview only)
sudo enhanced_automated_backups.sh restore drill borg system_backup_incremental_20260420_125524

# Full restore
sudo enhanced_automated_backups.sh restore full borg system_backup_incremental_20260420_125524
```

**Manual Borg commands:**
```bash
sudo borg list /UKwinikaBackup/borg_repo
sudo borg extract --strip-components 1 /UKwinikaBackup/borg_repo::ARCHIVE_NAME path/to/file-or-folder
```

**Browse mode:**
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
- **Borg lock timeout** → Fixed in v2.3 (automatic stale lock breaker)
- **Real-time monitoring not working** → Ensure `inotify-tools` is installed
- **MySQL access denied** → Use the `.my.cnf` fix above
- **Passphrase prompt** → Verify `/etc/ukwinika-backup.secrets`

## Security & Best Practices
- Passphrase stored securely in `/etc/ukwinika-backup.secrets` (600 permissions)
- Borg uses `repokey` encryption (AES-256)
- Concurrency locking prevents overlapping backups
- Recommended: Replicate the repository to S3 with Object Lock for immutability
- Run monthly restore drills

**UKwinika Notable Advice: A Backup is Only as Good as its Last Successful Restore.**
