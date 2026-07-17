# UKwinika Disaster Recovery Runbook

**Scope:** This document covers recovering a **completely lost host** (dead
disk, destroyed VM, stolen hardware) — as opposed to `docs/RESTORE-CHECKLIST.md`,
which covers routine restore *drills* against a still-living system.

If you only need to pull back a file or folder on a working machine, use
`docs/RESTORE-CHECKLIST.md` instead. This document assumes the original host
is gone and you are rebuilding from nothing.

---

## 0. Before disaster strikes — what you must already have off-host

Recovery is only possible if the following survive the disaster **outside**
the host that died:

1. **The Borg repository** — on the USB secondary copy, the cloud tertiary
   copy (`CLOUD_REMOTE`), or both. If both the primary disk and your only
   other copy were on the same site and both were destroyed, you have no
   3-2-1 strategy — this is why the cloud/off-site copy exists.
2. **The Borg repository passphrase** (`BORG_PASSPHRASE` from
   `/etc/ukwinika-backup.secrets`). Store this in a password manager or
   printed in a safe — **not only on the host you're backing up**. Without
   it, the repository is permanently unreadable; there is no recovery path.
3. **The Borg repokey**, if you are relying on `repokey` mode (the key is
   stored *inside* the repository, so if your repository copy survives, the
   key survives with it — but confirm this is true for whichever copy you
   restore from). Consider `borg key export` to a separate secure location
   as a second safety net.
4. **A copy of this repository** (`ukwinika-backups`) itself, or at minimum
   `enhanced_automated_backups.sh`, `backuprestore/ukwinika_automated_restore.sh`,
   and your `/etc/ukwinika-backup.conf` — so you have the tooling to restore
   with, not just the raw archive data.

---

## 1. Provision a replacement host

1. Install a compatible OS (Debian, Ubuntu, RHEL, Rocky, or AlmaLinux — see
   README for supported distributions).
2. Install BorgBackup **1.2.x or newer** (`sudo apt install borgbackup` /
   `sudo dnf install borgbackup`). Confirm with:
   ```bash
   borg --version
   ```
3. Clone or copy this repository onto the new host:
   ```bash
   git clone https://github.com/UkwiNux/ukwinika-backups.git
   cd ukwinika-backups
   sudo make install
   ```
4. Restore `/etc/ukwinika-backup.conf` and `/etc/ukwinika-backup.secrets`
   from your off-host copies (password manager, printed copy, secure vault).
   Set permissions:
   ```bash
   sudo chmod 600 /etc/ukwinika-backup.conf /etc/ukwinika-backup.secrets
   sudo chown root:root /etc/ukwinika-backup.conf /etc/ukwinika-backup.secrets
   ```

---

## 2. Point at the surviving repository copy

If the primary (`BORG_REPO`) copy on the dead host is gone, edit
`/etc/ukwinika-backup.conf` to point at whichever copy survived:

- **From the USB/offsite copy:** attach the drive, mount it, then set
  `BORG_REPO` to the mounted path (e.g. `/mnt/backup_usb/offsite-borg-repo`)
  temporarily, or `rsync` it back to the expected primary path.
- **From cloud (`rclone`):** install and configure `rclone` on the new host
  with the same remote credentials, then pull the repository down before
  proceeding:
  ```bash
  rclone copy "<CLOUD_REMOTE>/borg_repo" /UKwinikaBackup/borg-repo --progress
  ```

Validate the configuration and repository are visible before doing anything
destructive:
```bash
sudo enhanced_automated_backups.sh validate
```

---

## 3. Verify repository integrity before restoring

Never restore from a repository you haven't checked, especially after
pulling it across a network or off removable media:
```bash
sudo enhanced_automated_backups.sh check
```
If this fails, see BorgBackup's own recovery tooling (`borg check --repair`)
as a last resort — repair operations can be lossy, so only use `--repair` if
you have no other surviving copy.

---

## 4. Identify the archive to restore

```bash
sudo enhanced_automated_backups.sh list
```
Pick the most recent archive, or the last known-good one if the most recent
is suspect (e.g. taken during an active incident).

---

## 5. Restore to a staging directory first — never straight to `/`

```bash
sudo enhanced_automated_backups.sh restore <archive_name> /mnt/dr-staging
```
Inspect the staged data before deciding what to copy where. For a full
bare-metal rebuild you will typically need to:

1. Restore `/etc` (users, groups, fstab, network config, SSH host keys) —
   compare against the freshly installed OS's `/etc` and merge carefully;
   do not blindly overwrite systemd/network configuration for hardware that
   may differ from the original host.
2. Restore application data directories (`/home`, `/var/lib/<app>`, etc.)
   directly, since these are rarely hardware-specific.
3. Restore database dumps from the archive's `ukwinika-db-dump` (or
   configured `DB_DUMP_DIR`) directory and reload them with the appropriate
   `mysql`, `psql`, or `mongorestore` tooling — do **not** simply copy raw
   database files unless you're certain the DB engine version matches.

---

## 6. Rebuild scheduling and monitoring on the new host

```bash
sudo make systemd
sudo systemctl enable --now ukwinika-backup.timer
sudo systemctl enable --now ukwinika-restore-test.timer
sudo systemctl enable --now ukwinika-check.timer
```
Confirm Prometheus is scraping the new host's textfile collector directory
and that alert rules (see `prometheus/ukwinika-backup-alerts.yml`) are firing
correctly on the new instance, not still pointed at the dead one.

---

## 7. Run a fresh backup and drill immediately

Do not consider the rebuild complete until a fresh backup and a restore
drill both succeed on the new host:
```bash
sudo enhanced_automated_backups.sh backup
sudo backuprestore/ukwinika_automated_restore.sh test
```

---

## 8. Post-incident

- Update the printed/vaulted copies of the passphrase and secrets if
  anything about them changed during recovery.
- Record the incident, root cause, and recovery time in your own
  maintenance log — this is what the monthly restore drill and this runbook
  exist to make routine rather than improvised.

> **UKwinika Notable Advice:** A Backup is Only as Good as its Last
> Successful Restore — and a restore procedure is only as good as its last
> successful *disaster* drill. Rehearse this runbook against a disposable
> VM at least annually, not just the monthly file-level restore drill.
