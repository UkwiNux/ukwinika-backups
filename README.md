# UKwinika Enhanced Automated Backup Script [EABS]

**A 3‑2‑1 Backup Strategy Solution** with Borg, Real-time Monitoring, Database Consistency, Encryption, Auditing, Restore Drills, Removable Media & Cloud Backup Support.

**Author:** Urayayi Kwinika  
**License:** MIT

## Features 
- **Fully Idempotent**: safe to run multiple times without side effects.
- Backup Modes: `backup`, `real-time` (inotify), `restore` (with Safe Drill Mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- 3-2-1 Backup Principle: Primary on System, Secondary on Removable USB, Tertiary on Cloud
- Pre/Post Backup Hooks
- Removable USB Auto-Detection
- **Stale Lock Prevention** – Lock File is automatically removed on exit.
- Detailed Audit Trail with SHA256 checksums
- Systemd Timers + Logrotate ready
- Full Support for Debian/Ubuntu and RHEL/Rocky/AlmaLinux/CentOS

## Repository Structure
```bash
ukwinika-backups/
├── README.md
├── LICENSE
├── .gitignore
├── Makefile                  
├── enhanced_automated_backups.sh       
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

## Quick Start – Clone from GitHub 

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd

# Then edit config and secrets, initialise Borg repo, and test.
```

After installation, follow the following steps

## Setup (Debian or RHEL)

1. **Create Secure Passphrase File**  
   ```bash
   # Remember to set Your Pass Phrase here
   sudo bash -c 'echo "YourStrongPassphraseHere123!" > /etc/ukwinika-backup.secrets'
   sudo chmod 600 /etc/ukwinika-backup.secrets
   
   sudo nano /etc/ukwinika-backup.secrets
   ```

2. **Initialize Borg Repository**  
   ```bash
   sudo borg init --encryption=repokey /UKwinikaBackup/borg-repo
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
   
7. **Enable Real-Time monitoring**
   ```bash
    sudo systemctl start ukwinika-realtime-backup.service
   ```
   
## RHEL-Specific Notes

- The Makefile automatically enables the EPEL repository and installs borgbackup via dnf.
- Ensure your system is registered with Red Hat Subscription Manager (or using Rocky/AlmaLinux) for full package access.

## Ansible Integration 

UKwinika EABS includes native Ansible support for large-scale, idempotent deployments.

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
- Primary copy (always): `/UKwinikaBackup/borg-repo` (system disk)
- Secondary copy (if USB detected): `/media/usb` or configured `REMOVABLE_MOUNT`
- Tertiary copy (if configured): Cloud storage via `rclone`
  
Archive names follow the pattern: `system_backup_incremental_YYYYMMDD_HHMMSS` or `system_backup_full_YYYYMMDD_HHMMSS`.

**Manual Borg commands:**
```bash
sudo borg list /UKwinikaBackup/borg-repo
sudo borg extract --strip-components 1 /UKwinikaBackup/borg-repo::ARCHIVE_NAME path/to/file-or-folder
```

**Browse mode:**
```bash
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg-repo /mnt/borg-restore
ls /mnt/borg-restore
sudo borg umount /mnt/borg-restore
```
Always test Restores regularly using the commands above.

## Usage Examples
- Incremental backup: `sudo enhanced_automated_backups.sh backup incremental borg`
- Full backup: `sudo enhanced_automated_backups.sh backup full borg`
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
