# UKwinika Enhanced Automated Backup Script
**UKwinika Enhanced Automated Backup Script – Version 2.3**

**Author:** Urayayi Kwinika  
**Version:** 2.3  
**Date:** April 2026  
**License:** MIT

## 1. Overview

UKwinika Enhanced Automated Backup Script is a light open-source, automated backup solution designed for Linux environment(s). It combines the power of BorgBackup with Real-Time Monitoring, Database Consistency guarantees, comprehensive auditing, and enterprise-grade features.

The script is fully compatible with Debian, Ubuntu, and other systemd-based distributions.

## 2. Implemented Features

| Feature                              | Status     | Implementation Details |
|--------------------------------------|------------|------------------------|
| Backup Modes                         | Full       | `backup`, `real-time`, `restore` |
| Default Backup Tool                  | Full       | Borg (deduplication + AES-256) |
| Optional Tools                       | Stub       | rsync, rsnapshot, duplicity (ready for expansion) |
| Adaptive Database Dumps              | Full       | MySQL, PostgreSQL, Oracle |
| LVM Snapshots for Hot Consistency    | Supported  | Configurable via `USE_LVM_SNAPSHOT` |
| Real-time Monitoring                 | Full       | inotify-based |
| Restore with Safe Drill Mode         | Full       | Script + manual Borg commands |
| Pre/Post Backup Hooks                | Full       | Executable scripts in `/etc/ukwinika/` |
| Prometheus Metrics Export            | Full       | Custom metrics file |
| Removable USB Auto-Detection         | Full       | Automatic fallback to USB |
| Concurrency Locking                  | Full       | `flock` mechanism |
| Detailed Audit Trail                 | Full       | Timestamped logs + SHA256 checksums |
| Retention Policy                     | Full       | Borg `prune` with configurable days/versions |
| Improved Borg Lock Handling          | Full       | `--max-lock-wait 300` + stale lock breaker |
| Systemd Integration                  | Full       | Timer + real-time service |
| Debian/Ubuntu Auto-Install           | Full       | Makefile handles dependencies |

## 3. Installation

See the main `README.md` for step-by-step instructions.

## 4. Configuration (`/etc/ukwinika-backup.conf`)

All settings are defined in `/etc/ukwinika-backup.conf`.  
A complete example is provided in `config/ukwinika-backup.conf.example`.

## 5. Backup Storage Location

All backups are stored in the Borg repository at:
```
/UKwinikaBackup/borg_repo
```

## 6. Restore Procedures

See the main `README.md` → “How to Restore a File or Folder”.

## 7. Real-Time Monitoring

The `ukwinika-realtime-backup.service` monitors the directories defined in `REAL_TIME_DIRS` and automatically triggers an incremental backup on any file change.

## 8. Hooks

- Pre-backup hook: `/etc/ukwinika/pre_backup_hook.sh`
- Post-backup hook: `/etc/ukwinika/post_backup_hook.sh`

Both are executable and receive the same environment variables as the main script.

## 9. Prometheus Metrics

Metrics are written to:
```
/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom
```

## 10. Logging and Auditing

- Main log: `/var/log/UKwinikaBackup.log`
- Audit log: `/var/log/UKwinikaBackup_audit.log` (includes SHA256 checksums)

## 11. Troubleshooting

Refer to the main `README.md` → Troubleshooting section.

## 12. Security Considerations

- Passphrase stored in `/etc/ukwinika-backup.secrets` (600 permissions)
- Borg uses `repokey` encryption (AES-256)
- Concurrency locking prevents overlapping backups
- Recommended: Replicate the repository to immutable storage (S3 Object Lock)

**UKwinika Noteable Advice:**  
A Backup is Only as Good as its last Successful Restore. Test Restores Regularly using the provided Drill Mode.
