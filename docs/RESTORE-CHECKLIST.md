# UKwinika Backup – Monthly Restore Drill Checklist

**Purpose:** Ensure that backups are complete, restorable, and that no silent corruption has occurred.  
**Frequency:** At least once per month, and after any major system change (OS upgrade, storage migration, configuration overhaul).

This checklist uses the idempotent restore features of UKwinika EABS v3.1 – you can repeat the drill without risk to live data.

---

## 1. Pre‑flight Check

- [ ] **Confirm the backup repository exists and is healthy:**
  ```bash
  sudo enhanced_automated_backups.sh check
  ```
  If the check fails, investigate and repair the repository before proceeding.

- [ ] **List all available archives:**
  ```bash
  sudo enhanced_automated_backups.sh list
  ```
  Identify the most recent archive (or a specific one you want to test).

- [ ] **Ensure enough free space on the target filesystem** (default is `/tmp`).  
  The restore directory will be `/tmp/restore_<archive_name>` unless you specify a custom path.

- [ ] **Choose a custom target directory** (optional) if you prefer a dedicated location, e.g.:
  ```bash
  DRILL_TARGET="/mnt/restore-drill/$(date +%Y-%m)"
  ```

---

## 2. Perform the Drill Restore

Run the restore command **with a safe target** – by default, files are extracted to `/tmp/restore_<archive_name>` and will never overwrite live data.

```bash
# Using the default target (recommended for most tests)
sudo enhanced_automated_backups.sh restore <archive_name>

# Or with a custom target
sudo enhanced_automated_backups.sh restore <archive_name> /mnt/restore-drill
```

**Example:**
```bash
sudo enhanced_automated_backups.sh restore debian-2026-04-25_08:20:17 /mnt/restore-drill
```

The extraction is idempotent – running the same command again will overwrite the target directory with the exact same contents, leaving it in a consistent state.

---

## 3. Verify Restored Data

Choose one or more verification methods:

### a) Compare with original files (if the original is still available)
```bash
diff -rq /original/path /tmp/restore_<archive_name>/original/path
```
No output means the files are identical.

### b) Check SHA256 checksums against the audit log
The audit log (`/var/log/UKwinikaBackup_audit.log`) contains checksums of all repository files at backup time. You can compare specific files:
```bash
sha256sum /tmp/restore_<archive_name>/path/to/file
grep "path/to/file" /var/log/UKwinikaBackup_audit.log
```

### c) Spot‑check key configuration files
```bash
diff /etc/fstab /tmp/restore_<archive_name>/etc/fstab
cat /tmp/restore_<archive_name>/etc/hostname
```

### d) Browse the extracted archive interactively
```bash
ls -la /tmp/restore_<archive_name>/
less /tmp/restore_<archive_name>/etc/shadow
```

### e) (Advanced) Mount the entire archive as a filesystem and compare
```bash
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg-repo::debian-2026-04-25_08:20:17 /mnt/borg-restore
diff -rq /etc /mnt/borg-restore/etc
sudo borg umount /mnt/borg-restore
```

---

## 4. Clean Up

Remove the drill directory to free space:

```bash
rm -rf /tmp/restore_<archive_name>
# or
rm -rf /mnt/restore-drill
```

If you used a Borg mount for verification, ensure it is unmounted (`borg umount` as above).

---

## 5. Document the Drill

- [ ] Record the date, archive name, and result (success / failure) in a maintenance log.
- [ ] If any discrepancies were found, investigate immediately and consider running a full repository check and a fresh backup.

---

> **UKwinika Notable Advice:** Remember A Backup is Only as Good as its Last Successful Restore. Performing this Drill Monthly Guarantees you can Recover with confidence when a Real Disaster Strikes.
```
