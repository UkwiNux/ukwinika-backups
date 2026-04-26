# UKwinika Enhanced Automated Backup Script
**UKwinika Enhanced Automated Backup Script Documentation**

**Author:** Urayayi Kwinika  
**Date:** April 2026  
**License:** MIT

## 1. Overview

UKwinika Enhanced Automated Backup Script is a light open-source, automated backup solution designed for Linux environment(s). It implements the industry-standard **3-2-1 Backup Principle** while providing real-time monitoring, database consistency, encryption, auditing, and enterprise features.

The script is fully compatible with Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, and CentOS Stream.

## 2. 3-2-1 Backup Principle 

UKwinika Enhanced Automated Backup Script strictly follows the 3-2-1 Backup Rule:

- **3 copies** of your data  
- **2 different media types**  
- **1 off-site** (cloud)

| Copy | Location                  | Purpose                     | Triggered When |
|------|---------------------------|-----------------------------|----------------|
| 1    |`/UKwinikaBackup/borg-repo`| Primary (system disk)       | Always         |
| 2    | Removable USB             | Secondary (local)           | USB detected   |
| 3    | Cloud (rclone)            | Tertiary (off-site)         |`CLOUD_REMOTE` defined |

## 3. Fully Implemented Features

- Backup modes: `backup`, `real-time` (inotify), `restore` (with safe drill mode)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints, mountable archives)
- Adaptive DB dumps (MySQL, PostgreSQL, Oracle) with optional LVM snapshots
- Pre/post backup hooks
- Prometheus metrics export
- Removable USB auto-detection
- Concurrency locking with `flock`
- Detailed audit trail with SHA256 checksums
- Improved Borg lock handling (`--max-lock-wait 300` + automatic stale lock breaker)
- Ansible Integration support
- Systemd timers + logrotate ready
- Full Debian/Ubuntu and RHEL/Rocky/AlmaLinux support

## 4. Installation

See the main `README.md` for step-by-step instructions.

## 5. Configuration ( `/etc/ukwinika-backup.conf` )

Key new parameters:
- `REMOVABLE_MOUNT` – Path for secondary USB copy
- `CLOUD_REMOTE` – rclone remote for tertiary cloud copy (e.g., `s3:mybucket`)

## 6. Backup Storage & 3-2-1 Flow

- Primary backup is **always** written to `/UKwinikaBackup/borg-repo`
- After successful primary backup:
  - If removable media is detected → secondary copy is made via `rsync`
  - If `CLOUD_REMOTE` is configured → tertiary copy is uploaded via `rclone`

## 7. Restore Procedures

See the main `README.md` → “How to Restore a File or Folder”.

## 8. Real-Time Monitoring

The `ukwinika-realtime-backup.service` monitors directories defined in `REAL_TIME_DIRS` and triggers incremental backups on file changes.

## 9. Hooks

- Pre-backup: `/etc/ukwinika/pre_backup_hook.sh`
- Post-backup: `/etc/ukwinika/post_backup_hook.sh`

## 10. Prometheus Metrics

Metrics are exported to:
```
/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom
```

## 11. Logging and Auditing

- Main log: `/var/log/UKwinikaBackup.log`
- Audit log: `/var/log/UKwinikaBackup_audit.log` (includes SHA256 checksums)

## 12. Security Considerations

- Passphrase stored in `/etc/ukwinika-backup.secrets` (600 permissions)
- Borg uses `repokey` encryption (AES-256)
- Concurrency locking prevents overlapping backups
- Recommended: Replicate the primary repository to immutable cloud storage

**Important:** A Backup is Only as Good as its Last Successful Restore. Test Restores Regularly using the Drill Mode.
