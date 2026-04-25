# UKwinika Enhanced Automated Backup Script [EABS v3.0]

**A Linux Backup Solution** with Borg (recommended), Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media, Ansible Support & Cloud Backup Support.

**A Smart, Idempotent 3‑2‑1 Backup Solution for Linux**

**Version:** 3.0  
**Author:** Urayayi Kwinika  
**License:** MIT

## Features 
- **Fully idempotent**: safe to run multiple times without side effects.
- Backup modes: `backup`, `real-time` (inotify), `restore` (with safe drill mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- 3-2-1 Backup Principle: Primary on System, Secondary on Removable USB, Tertiary on Cloud
- Pre/post backup hooks
- Removable USB auto-detection
- **Stale Lock Prevention** – lock file is automatically removed on exit.
- Detailed audit trail with SHA256 checksums
- Systemd timers + logrotate ready
- Full Support for Debian/Ubuntu and RHEL/Rocky/AlmaLinux/CentOS

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
```

## Quick Start – Clone from GitHub (Recommended for Latest Version)

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd

# Then edit config and secrets, initialise Borg repo, and test.
```

After installation, follow the **Setup** section below.

## Setup (Debian or RHEL)

1. **Create Secure Passphrase File**  
   ```bash
   # Remember to set Your Pass Phrase here
   sudo bash -c 'echo "YourStrongPassphraseHere123!" > /etc/ukwinika-backup.secrets'
   sudo chmod 600 /etc/ukwinika-backup.secrets
   ```

2. **Initialize Borg Repository**  
   ```bash
   sudo mkdir -p /UKwinikaBackup
   sudo borg init --encryption=repokey /UKwinikaBackup/borg_repo
   ```

3. **Configure the Script**  
   ```bash
   sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets
   sudo chmod 600 /etc/ukwinika-backup.secrets
   sudo nano /etc/ukwinika-backup.secrets
   sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
   sudo chmod 600 /etc/ukwinika-backup.conf
   sudo nano /etc/ukwinika-backup.conf
   ```

4. **Deploy Systemd Services and Logrotate**  
   ```bash
   sudo make systemd
   ```

5. **Test the Backup**  
   ```bash
   sudo enhanced_automated_backups.sh backup incremental borg
   ```

6. **Enable Daily Automation**  
   ```bash
   sudo systemctl enable --now ukwinika-backup.timer
   ```
## RHEL-Specific Notes

- The Makefile automatically enables the EPEL repository and installs borgbackup via dnf.
- Ensure your system is registered with Red Hat Subscription Manager (or using Rocky/AlmaLinux) for full package access.

## Ansible Integration 

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

See the `ansible/` directory or use the current Makefile for manual Ansible integration.

The script automatically follows the 3-2-1 backup rule:
- After the primary Borg backup completes on the system disk, it will:
   - Copy the new archive to removable USB if present
   - Upload the new archive to the cloud if `CLOUD_REMOTE` is set in the config
     
## Where Backups Are Stored (3-2-1 Principle)
- Primary copy (always): `/UKwinikaBackup/borg_repo` (system disk)
- Secondary copy (if USB detected): `/media/usb` or configured `REMOVABLE_MOUNT`
- Tertiary copy (if configured): Cloud storage via `rclone`
  
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
- **Borg lock timeout** 
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
