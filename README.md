# UKwinika Enhanced Automated Backup Script (EABS)

**A 3‑2‑1 Backup Solution** with Borg, Real-Time Monitoring, Automated Restore Drills, Database Consistency, Encryption, Auditing, Retry/Backoff, and Cloud Support.

**Author:** **Urayayi Kwinika** | **Version:** 3.3.0 | **License:** MIT

---

## Features

- **Fully Idempotent** – Safe to run any number of times without side effects.
- **3‑2‑1 Backup Principle** – Primary on disk, secondary on removable USB, tertiary to cloud.
- **BorgBackup** – Deduplication, AES‑256 encryption, compression, and mountable archives. Minimum version (`MIN_BORG_VERSION`, default `1.2.0`) is enforced before any operation runs.
- **Automated Restore Drills** – a dedicated script (`backuprestore/ukwinika_automated_restore.sh`) runs six independent verification checks monthly, so "can we actually restore?" is answered continuously, not assumed.
- **Configuration Validation (`validate`)** – checks required variables, `DB_TYPE`, the installed borg version, and current repository state with **zero side effects**.
- **Dry-Run Mode (`backup --dry-run`)** – simulates a full backup cycle without writing an archive, pruning, syncing, uploading, or notifying.
- **Scheduled Consistency Checks (`check-if-due`)** – borgmatic-style due-date tracking runs a full `borg check` only once `CHECK_INTERVAL_DAYS` has elapsed, instead of on every backup.
- **Retry/Backoff** – transient USB-mount and cloud-upload failures are retried with a configurable delay instead of failing the whole backup outright.
- **Real‑Time Monitoring** (inotify) – instant backups on file changes, with lock-contention-safe child-process spawning.
- **Database‑Aware** – adaptive dumps for MySQL, PostgreSQL, and MongoDB, with strict `DB_TYPE` validation to prevent silent data loss.
- **LVM Snapshot Hooks** – example pre/post hooks for point-in-time filesystem consistency on hosts beyond DB-aware dumps.
- **Pre/Post Hooks** – custom scripts before and after every backup, with configurable fatal/warn failure handling.
- **Prometheus Metrics + Alerting Rules** – exposes backup and restore-drill health, with a ready-to-use `prometheus/ukwinika-backup-alerts.yml` so staleness and failures actually page someone.
- **Audit Trail** – SHA256 checksums logged after every backup and cross-checked during restore drills.
- **Stale Lock Prevention** – lock file is automatically removed on exit.
- **Config/Secrets Security Validation** – refuses to run unless `/etc/ukwinika-backup.conf` and `/etc/ukwinika-backup.secrets` are root-owned and correctly permissioned.
- **Systemd & Logrotate** – hardened units (`ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp`) ready for scheduled execution, restore drills, consistency checks, and log rotation.
- **Cross‑Distribution Support** – Debian, Ubuntu, RHEL, Rocky, AlmaLinux, CentOS.

---

## Repository Structure
```
ukwinika-backups/
├── README.md
├── UKWINIKA-DOCUMENTATION.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
├── .shellcheckrc
├── Makefile
├── enhanced_automated_backups.sh           # Main backup script (v3.3.0)
├── config/
│   ├── ukwinika-backup.conf.example        # Configuration template
│   └── ukwinika-backup.secrets.example     # Secrets template
├── systemd/
│   ├── ukwinika-backup.service             # Daily backup (oneshot)
│   ├── ukwinika-backup.timer               # Daily @ 02:00 ± 30 min
│   ├── ukwinika-realtime-backup.service     # inotify real-time monitoring
│   ├── ukwinika-check.service              # Scheduled consistency-check evaluation
│   └── ukwinika-check.timer                # Daily @ 03:30 (only runs `borg check` when due)
├── backuprestore/
│   ├── ukwinika_automated_restore.sh       # Automated monthly restore drill
│   ├── ukwinika-restore-test.service
│   └── ukwinika-restore-test.timer         # Monthly, 15th @ 04:00
├── hooks/
│   ├── pre_backup_hook.sh.example
│   ├── post_backup_hook.sh.example
│   ├── lvm_snapshot_pre_backup_hook.sh.example   # Point-in-time snapshot before backup
│   └── lvm_snapshot_post_backup_hook.sh.example  # Snapshot cleanup after backup
├── prometheus/
│   └── ukwinika-backup-alerts.yml          # Alerting rules for backup/restore health
├── logrotate/
│   └── ukwinika-backup
├── docs/
│   ├── RESTORE-CHECKLIST.md                # Monthly file-level restore drill checklist
│   └── DISASTER-RECOVERY.md                # Full bare-metal / total-host-loss runbook
└── .github/
    ├── dependabot.yml
    └── workflows/
        ├── release.yml
        └── test.yml
```

---

## Quick Start

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install        # Installs script, dependencies, and Prometheus textfile dir
sudo make systemd        # Deploys all systemd units, logrotate, and /var/lib/ukwinika
```

Then follow **Full Setup** below.

---

## Full Setup (Debian / RHEL)

### 1. Copy and Edit Configuration Files
```bash
# Secrets file (must be 600!)
sudo cp config/ukwinika-backup.secrets.example /etc/ukwinika-backup.secrets
sudo chmod 600 /etc/ukwinika-backup.secrets
sudo nano /etc/ukwinika-backup.secrets
```
Set the passphrase and, optionally, the Slack webhook URL and email address.

```bash
# Main configuration
sudo cp config/ukwinika-backup.conf.example /etc/ukwinika-backup.conf
sudo chmod 600 /etc/ukwinika-backup.conf
sudo nano /etc/ukwinika-backup.conf
```
Adjust paths, retention, USB mount point, database type, retry/backoff counts, minimum borg version, and consistency-check interval as needed.

### 2. Validate Before Doing Anything Else
```bash
sudo enhanced_automated_backups.sh validate
```
This has **zero side effects** — it checks your config, secrets, `DB_TYPE`, and installed `borg` version, and reports whether the repository already exists, without touching anything.

### 3. Initialise the Borg Repository
```bash
sudo enhanced_automated_backups.sh init
```
The repository is created at `BORG_REPO` (default `/UKwinikaBackup/borg-repo`) using `repokey` encryption. **Back up the passphrase and, ideally, an exported key, somewhere off this host** — see `docs/DISASTER-RECOVERY.md`.

### 4. Deploy Systemd Services, Timers, and Logrotate
```bash
sudo make systemd
```
Installs: the daily backup timer, the real-time monitoring service, the monthly restore-drill timer, the scheduled consistency-check timer, and the logrotate configuration.

### 5. Dry-Run, Then Run a Real Backup
```bash
sudo enhanced_automated_backups.sh backup --dry-run   # simulates only, writes nothing
sudo enhanced_automated_backups.sh backup             # the real thing
sudo tail -f /var/log/UKwinikaBackup.log
```

### 6. Enable Scheduled Automation
```bash
sudo systemctl enable --now ukwinika-backup.timer
sudo systemctl enable --now ukwinika-restore-test.timer
sudo systemctl enable --now ukwinika-check.timer
```

### 7. (Optional) Real-Time Monitoring
```bash
sudo systemctl start ukwinika-realtime-backup.service
```
Monitors directories in `REAL_TIME_DIRS` (default `/etc` and `/home`) and triggers a full backup on change, debounced to avoid a backup storm.

---

## Usage

| Command | Description |
|--------|-------------|
| `sudo enhanced_automated_backups.sh validate` | Validate configuration and environment. **No side effects.** |
| `sudo enhanced_automated_backups.sh backup [--dry-run]` | Full backup cycle, or simulate one without writing anything |
| `sudo enhanced_automated_backups.sh restore <archive> [target]` | Restore an archive to a target directory |
| `sudo enhanced_automated_backups.sh list` | List all archives |
| `sudo enhanced_automated_backups.sh check` | Force a full repository integrity check now |
| `sudo enhanced_automated_backups.sh check-if-due` | Run a full check only if `CHECK_INTERVAL_DAYS` has elapsed since the last one |
| `sudo enhanced_automated_backups.sh init` | Initialise a new Borg repository |
| `sudo enhanced_automated_backups.sh real-time` | Start real‑time monitoring manually |
| `sudo backuprestore/ukwinika_automated_restore.sh test` | Run a full restore drill with six verification checks now |

**Examples:**
```bash
# Validate config with no side effects
sudo enhanced_automated_backups.sh validate

# See what a backup would do without doing it
sudo enhanced_automated_backups.sh backup --dry-run

# Run a backup
sudo enhanced_automated_backups.sh backup

# Safe restore (files go to /tmp/restore_<archive> by default)
sudo enhanced_automated_backups.sh restore debian-2026-07-16_08:20:17 /mnt/restore-test

# List available archives
sudo enhanced_automated_backups.sh list

# Run the consistency check only if it's actually due
sudo enhanced_automated_backups.sh check-if-due
```

---

## Where Backups Are Stored (3‑2‑1)

- **Primary copy:** `BORG_REPO`, default `/UKwinikaBackup/borg-repo` (system disk)
- **Secondary copy:** Removable USB at `USB_RSYNC_TARGET`, mirrored with `rsync -a --delete` (retried on transient mount failures)
- **Tertiary copy:** Cloud storage via `rclone` if `CLOUD_REMOTE` is configured (retried on transient upload failures)

Archive names follow the pattern: `<hostname>-<YYYY-MM-DD_HH:MM:SS>`

---

## Restoring Data

### Routine restore or drill
```bash
sudo enhanced_automated_backups.sh restore <archive_name> /desired/target
```
Extracts safely to the given target; live data is never overwritten unless you point at it explicitly. See `docs/RESTORE-CHECKLIST.md` for the full monthly drill procedure, and `backuprestore/ukwinika_automated_restore.sh test` to run the automated version of that drill on demand.

### Total host loss (disaster recovery)
If the original host is gone entirely — not just a file you need back — see **`docs/DISASTER-RECOVERY.md`**, which covers what must already exist off-host, provisioning a replacement, and rebuilding from the surviving USB or cloud copy.

### Manual Borg Commands
```bash
sudo borg list /UKwinikaBackup/borg-repo
sudo borg extract --strip-components 1 /UKwinikaBackup/borg-repo::<archive> path/to/file
sudo mkdir -p /mnt/borg-restore
sudo borg mount /UKwinikaBackup/borg-repo /mnt/borg-restore
ls /mnt/borg-restore
sudo borg umount /mnt/borg-restore
```

---

## Filesystem-Consistent Backups (LVM Snapshots)

For data outside the DB-aware dump paths, copy the example hooks and point `PRE_HOOK`/`POST_HOOK` at them:
```bash
sudo cp hooks/lvm_snapshot_pre_backup_hook.sh.example /etc/ukwinika/pre_backup_hook.sh
sudo cp hooks/lvm_snapshot_post_backup_hook.sh.example /etc/ukwinika/post_backup_hook.sh
sudo chmod +x /etc/ukwinika/pre_backup_hook.sh /etc/ukwinika/post_backup_hook.sh
```
Edit the `UKW_LVM_VG`/`UKW_LVM_LV`/`UKW_LVM_SNAP_MOUNT` variables inside each script to match your volume group, and point `BACKUP_PATHS` at the snapshot mount rather than the live path.

---

## Database Support

Set `DB_TYPE` in the configuration file to `mysql`, `postgresql`, or `mongodb`. An unrecognised value causes an immediate abort to prevent silent data loss. For MySQL on Debian/Ubuntu:
```bash
sudo bash -c 'cat > /root/.my.cnf <<EOF
[client]
user=root
password=your_mysql_root_password
EOF'
sudo chmod 600 /root/.my.cnf
```

---

## Monitoring

- **Prometheus metrics** are written to `PROMETHEUS_FILE` (default `/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom`) by both the backup and restore-drill scripts.
- **Alerting rules** in `prometheus/ukwinika-backup-alerts.yml` cover: stale backups, missing metrics entirely, failed restore drills, stale restore drills, and individual failing verification checks. Copy into your Prometheus rule directory and reference it from `prometheus.yml`.
- **Slack/email notifications** fire on both backup success and failure.

---

## Troubleshooting

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| `borg version X is older than required minimum` | Outdated `borgbackup` package | `sudo apt install --only-upgrade borgbackup` / `sudo dnf upgrade borgbackup` |
| `Borg create failed` | Repository not initialised | Run `sudo enhanced_automated_backups.sh init` |
| Real‑time monitoring not working | `inotify-tools` missing | `sudo make install` (installs it automatically) |
| MySQL access denied | Missing or incorrect `.my.cnf` | Create `/root/.my.cnf` with valid credentials |
| Passphrase prompt during backup | Secrets file missing or incorrect permissions | Ensure `/etc/ukwinika-backup.secrets` exists, is mode `0600`, and contains `BORG_PASSPHRASE` |
| USB mount fails intermittently | Slow-to-enumerate USB controller | Increase `USB_RETRY_ATTEMPTS` / `USB_RETRY_DELAY_SEC` |
| Cloud upload fails intermittently | Transient network issue | Increase `CLOUD_RETRY_ATTEMPTS` / `CLOUD_RETRY_DELAY_SEC` — the backup still succeeds locally/USB either way |
| `check-if-due` never runs a real check | `CHECK_STATE_FILE` directory not writable | Ensure `/var/lib/ukwinika` exists and is writable by root (created automatically by `sudo make systemd`) |

---

## Security & Best Practices

- The passphrase and any webhook/email credentials live exclusively in `/etc/ukwinika-backup.secrets` (mode `0600`); the script refuses to run otherwise.
- Borg uses `repokey` encryption – **never lose your passphrase or repository key**; export a copy with `borg key export` and store it off-host (see `docs/DISASTER-RECOVERY.md`).
- The script uses file locking (`flock`) to prevent concurrent executions, and enforces a minimum Borg version before any repository operation.
- Systemd units use `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges=true`, and `PrivateTmp=true` wherever the operation allows it.
- Run monthly restore drills (`docs/RESTORE-CHECKLIST.md` / `ukwinika-restore-test.timer`) and rehearse the disaster-recovery runbook (`docs/DISASTER-RECOVERY.md`) at least annually.
- See `SECURITY.md` for the vulnerability reporting process and supported-version table.

---

## RHEL‑Specific Notes

- The `Makefile` enables the EPEL repository and installs `borgbackup` via `dnf`.
- Ensure your system is subscribed (RHEL) or that you are using a compatible derivative (Rocky, AlmaLinux, CentOS).

---

## Further Reading

- **`UKWINIKA-DOCUMENTATION.md`** – full technical reference: architecture, every configuration variable, workflow internals, and version history.
- **`docs/RESTORE-CHECKLIST.md`** – monthly file-level restore drill checklist.
- **`docs/DISASTER-RECOVERY.md`** – total-host-loss recovery runbook.
- **`CHANGELOG.md`** – full version history.
- **`SECURITY.md`** – supported versions and vulnerability reporting.

> **UKwinika Notable Advice:** A Backup is Only as Good as its Last Successful Restore. Test Regularly — and rehearse disaster recovery, not just file restores.

## License

This project is licensed under the MIT License – see the `LICENSE` file for details.
