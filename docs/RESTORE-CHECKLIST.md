# UKwinika Backup – Monthly Restore Drill Checklist

**Version:** v3.2.2
**Purpose:** Confirm that backups are complete, restorable, and free of silent corruption.
**Frequency:** At least once per month, and after any major system change (OS upgrade, storage migration, configuration overhaul).

This checklist uses the idempotent restore features of UKwinika EABS v3.2.2 — you can repeat the drill without risk to live data.

---

## 1. Pre-flight Check

- [ ] **Verify the repository exists and is structurally intact:**
  ```bash
  sudo enhanced_automated_backups.sh check
  ```
  This runs a full `borg check` on the repository. If it fails, investigate and repair before proceeding.

- [ ] **List all available archives:**
  ```bash
  sudo enhanced_automated_backups.sh list
  ```
  Identify the most recent archive (or a specific one you want to test). Archive names follow the pattern `<hostname>-<YYYY-MM-DD_HH:MM:SS>`.

- [ ] **Ensure enough free space on the target filesystem** (default restore target is `/tmp`).
  The restore directory will be `/tmp/restore_<archive_name>` unless you specify a custom path.

- [ ] **Choose a custom target directory** (optional) if you prefer a dedicated location, e.g.:
  ```bash
  DRILL_TARGET="/mnt/restore-drill/$(date +%Y-%m)"
  ```

---

## 2. Perform the Drill Restore

Run the restore command with a safe target — by default, files are extracted to `/tmp/restore_<archive_name>` and will never touch live data.

```bash
# Default target (recommended for most tests)
sudo enhanced_automated_backups.sh restore <archive_name>

# Custom target
sudo enhanced_automated_backups.sh restore <archive_name> /mnt/restore-drill
```

**Example:**
```bash
sudo enhanced_automated_backups.sh restore debian-2026-06-17_02:00:45 /mnt/restore-drill
```

The extraction is idempotent — running the same command again overwrites the target directory with the exact same contents, leaving it in a consistent state.

> **Note on database dumps:** If `DB_TYPE` is set, database dump files are included inside the archive under the `DB_DUMP_DIR` path (default `/tmp/ukwinika-db-dump`). When comparing the restore against the original filesystem, exclude this path from your diff to avoid false mismatches.

---

## 3. Verify Restored Data

Choose one or more verification methods:

### a) Compare with original files (if the original is still available)
```bash
diff -rq /etc /tmp/restore_<archive_name>/etc
```
No output means the files are identical.

### b) Check SHA256 checksums against the audit log
After each backup, the script records SHA256 hashes of files listed in `RESTORE_VERIFY_PATHS` (e.g. `etc/hostname`) into `/var/log/UKwinikaBackup_audit.log`. Compare a restored file:
```bash
sha256sum /tmp/restore_<archive_name>/etc/hostname
grep "etc/hostname$" /var/log/UKwinikaBackup_audit.log
```
Repository-object checksums are written separately to `CHECKSUM_FILE` (default `/tmp/ukwinika-backup-checksums.txt`).

### c) Spot-check key configuration files
```bash
diff /etc/fstab /tmp/restore_<archive_name>/etc/fstab
cat /tmp/restore_<archive_name>/etc/hostname
```

### d) Browse the extracted archive interactively
```bash
ls -la /tmp/restore_<archive_name>/
cat /tmp/restore_<archive_name>/etc/os-release
```

> **Note:** Avoid browsing sensitive files like `/etc/shadow` interactively in a drill — use checksum comparison (method b) or `diff` (method a) instead.

### e) (Advanced) Mount the archive as a read-only filesystem and compare
```bash
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg-repo::debian-2026-06-17_02:00:45 /mnt/borg-restore
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

If you used a Borg mount for verification, ensure it is unmounted (`borg umount` as above) before removing the mount point.

---

## 5. Document the Drill

- [ ] Record the date, archive name, and result (success / failure) in a maintenance log.
- [ ] Note the script version used (`grep '^# Version' /usr/local/bin/enhanced_automated_backups.sh`).
- [ ] If any discrepancies were found, investigate immediately and consider running a full repository check (`sudo enhanced_automated_backups.sh check`) followed by a fresh backup.

---

> **UKwinika Notable Advice:** Remember — A Backup is Only as Good as its Last Successful Restore. Performing this Drill Monthly Guarantees You Can Recover with Confidence when a Real Disaster Strikes.
