# UKwinika Enhanced Automated Backup Script

**Exclusive Production-Ready Linux Backup Solution** with Borg (recommended), real-time monitoring, database consistency, encryption, auditing, restore drills, removable media, Ansible support, and ransomware-resistant design.

**Author:** Urayayi Kwinika  
**Version:** 2.0  
**Last Updated:** April 2026  
**License:** MIT

## Features
- Modes: `backup`, `real-time` (inotify), `restore` (with drill)
- Default tool: **Borg** (deduplication, native AES-256, checkpoints)
- Optional: rsync, rsnapshot, duplicity
- Adaptive DB dumps (MySQL, PostgreSQL, Oracle) + optional LVM snapshots
- External config, pre/post hooks, Prometheus metrics
- Concurrency locking, strict error handling, atomic operations
- Removable media auto-detection, retention policy, audit trail with SHA256
- Systemd + logrotate ready

## Quick Start (Step-by-Step)

1. **Clone & Install**
   ```bash
   git clone https://github.com/UkwiNux/ukwinika-backups.git
   cd ukwinika-backups
   sudo install -m 700 enhanced_automated_backups.sh /usr/local/bin/
