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

## Full Installation & Setup (Step-by-Step Instructions for Using the Backup Script)

1. **Initial Setup**
   Copy the script to:
   ```bash
   /usr/local/bin/enhanced_automated_backups.sh
   and run chmod 700
   sudo chmod 700 /usr/local/bin/enhanced_automated_backups.sh 
   ```

2. **Install the Main Script**
   ```bash
   sudo make install
   ```

3. **Configure**
   ```bash
   sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
   sudo chmod 600 /etc/ukwinika-backup.conf
   sudo nano /etc/ukwinika-backup.conf
   ```

4. **Initialize Borg Repository (first run only)**
   ```bash
   sudo borg init --encryption=repokey-aes256 /UKwinikaBackup/borg_repo
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
  `sudo enhanced_automated_backups.sh restore full borg <archive_name>`

- **View logs**  
  `tail -f /var/log/UKwinikaBackup.log`

## Scheduling & Automation
- Daily backups via `ukwinika-backup.timer` (runs at 02:00 with random delay)
- Real-time daemon via `ukwinika-realtime-backup.service`
- Log rotation handled automatically

## Security & Best Practices
- Use Borg native `repokey-aes256` encryption.
- Replicate Borg repo to S3 with **Object Lock** (Compliance mode) for immutability.
- Run monthly restore drills (see `docs/RESTORE-CHECKLIST.md`).
- Never commit passphrases or config files containing secrets.

## Troubleshooting
- Check `/var/log/UKwinikaBackup.log` and `_audit.log`
- Borg health: `sudo borg check /UKwinikaBackup/borg_repo`
- Common issues: missing dependencies, passphrase errors, insufficient permissions

**A backup is only as good as its last successful restore.**
