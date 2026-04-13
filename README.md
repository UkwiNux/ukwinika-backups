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

## Quick Start
Get started in minutes using the provided **Makefile** (recommended for easy installation, systemd deployment, and clean removal).

### Option 1: From Release Tarball (Recommended for Production)
1. Download the latest `ukwinika-backups-v2.0.tar.gz` from the [GitHub Releases](https://github.com/UkwiNux/ukwinika-backups/releases) page.
2. Extract it:
   ```bash
   tar -xzf ukwinika-backups-v2.0.tar.gz
   cd ukwinika-backups-v2.0
   ```
3. Install and deploy using the Makefile:
   ```bash
   sudo make install     # Installs the main script to /usr/local/bin
   sudo make systemd     # Deploys systemd services + logrotate
   ```

### Option 2: From Git Clone (For Development or Latest Changes)
```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
```

**Next steps:** Follow the detailed configuration, Borg initialization, testing, and automation steps in the **Full Installation & Setup** section below. The Makefile also supports `sudo make uninstall` and `sudo make clean` for maintenance.

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
  `sudo enhanced_automated_backups.sh restore full borg`
```

Here is the GitHub Actions release workflow that automatically creates and attaches `ukwinika-backups-vX.Y.tar.gz` (with a clean top-level directory structure, excluding VCS and CI files) whenever you publish a release on a tag (e.g., `v2.0`).

Create the file `.github/workflows/release.yml` in your repository and paste the following content exactly:

```yaml
name: Create Release Tarball

on:
  release:
    types: [published]

jobs:
  build-tarball:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: Checkout repository at release tag
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.release.tag_name }}

      - name: Create ukwinika-backups-vX.Y.tar.gz (clean distribution archive)
        run: |
          TAG="${{ github.event.release.tag_name }}"
          tar -czf "ukwinika-backups-${TAG}.tar.gz" \
            --exclude-vcs \
            --exclude='.github' \
            --transform "s|^|ukwinika-backups-${TAG}/|" \
            .

      - name: Upload tarball as release asset
        uses: softprops/action-gh-release@v2
        with:
          files: ukwinika-backups-${{ github.event.release.tag_name }}.tar.gz
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### How it works (key nuances and edge cases covered)
- **Trigger**: Fires automatically only when a release is **published** (not on every tag push). This ensures the release already exists on GitHub so the workflow can safely attach the asset.
- **Tarball details**: 
  - Named exactly `ukwinika-backups-v2.0.tar.gz` (or whatever your release tag is).
  - Includes a top-level folder `ukwinika-backups-v2.0/` when extracted (thanks to `--transform`).
  - Excludes `.git`, `.github` (including test.yml and this workflow itself) and any other VCS noise for a clean, production-ready distribution.
- **Permissions**: `contents: write` is required to upload the asset.
- **Idempotency & safety**: The workflow runs only on published releases, uses the exact tag from the release event, and produces a deterministic archive.
- **Testing the workflow**: After merging this file, create a test release (or use an existing tag) and verify the asset appears under the release page. The Quick Start section above already points users to this exact asset.
- **Related considerations**: If you later want to include additional files (e.g., pre-built binaries or docs), simply adjust the `tar` command. GitHub also auto-generates source code `.tar.gz` and `.zip` archives, but this custom one matches your requested naming and structure.

You can now commit the updated README.md and the new `release.yml` workflow. Once pushed, every future release tag will automatically ship the ready-to-use `ukwinika-backups-vX.Y.tar.gz`.
