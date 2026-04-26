# UKwinika Backup – Monthly Restore Drill Checklist

**Purpose**: Verify that backups are restorable and data is intact.  
**Frequency**: At least once per month (or after any major change).

### 1. Select an Archive
```bash
sudo enhanced_automated_backups.sh list
```

### 2. Restore to a Test Location (Drill)
```bash
sudo enhanced_automated_backups.sh restore <archive_name> /tmp/restore_drill
```
Files are now safely extracted to `/tmp/restore_drill` – this can be repeated without harm.

### 3. Verify Integrity
```bash
diff -rq /original/path /tmp/restore_drill/original/path
```

### 4. Clean Up
```bash
rm -rf /tmp/restore_drill
```
