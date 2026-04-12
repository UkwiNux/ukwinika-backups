# UKwinika Backup – Monthly Restore Drill Checklist

**Purpose**: Verify that backups are restorable and data is intact.  
**Frequency**: At least once per month (or after any major change).

### 1. Preparation
- Use a non-production test server or isolated VM.
- Confirm you have the encryption passphrase (or Borg repo key).
- Ensure the target restore location has enough free disk space.
- Back up current critical data on the test system (just in case).

### 2. Select Backup
- List available archives:  
  `sudo borg list /UKwinikaBackup/borg_repo` (or `ls -l /UKwinikaBackup`)
- Choose the most recent successful backup (cross-check with audit log).

### 3. Run Restore in Drill Mode (Recommended)
```bash
sudo enhanced_automated_backups.sh restore drill borg <archive_name>
