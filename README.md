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

**This content (the Quick Start section through to Usage Examples) belongs in one specific location:**

**File path (exact):**  
`README.md`

This is the main readme file in the **root** of your repository (not inside any subfolder).  
GitHub automatically displays the content of `README.md` as the landing page when someone visits https://github.com/UkwiNux/ukwinika-backups.

### Why this exact file and location?
- The Quick Start + Usage Examples are **core user-facing instructions**. They must live in README.md so visitors see them immediately (GitHub renders markdown automatically).
- Your current README.md already has a Repository Structure section followed by Full Installation & Setup and Usage Examples. The new block you asked about fits **perfectly right after** the Repository Structure section.
- Placing it anywhere else (e.g., a new file like QUICKSTART.md or inside .github/) would break the intended flow and make it harder for users to find.

### Step-by-step: How to paste it using the GitHub web interface (easiest method)
1. Go to your repository: https://github.com/UkwiNux/ukwinika-backups
2. Click on the file `README.md`.
3. Click the pencil icon **Edit this file** (top right).
4. Scroll down in the editor until you see the end of the **Repository Structure** section (it ends with the last line of the directory tree).
5. Place your cursor **immediately after** that Repository Structure block (right before the current `## Full Installation & Setup` line).
6. Paste the clean block below **exactly** where the cursor is.
7. (Optional but recommended) You can keep the existing Full Installation section that follows, or delete the old one if you want the README to match the final version I gave earlier — both work fine.
8. Scroll to the bottom of the page.
9. In the commit message box, type exactly:  
   `Add Quick Start section with Makefile instructions (up to Usage Examples)`
10. Click **Commit changes**.

### Clean copy-paste block (copy **everything** below this line)
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

### Important notes & edge cases
- **Markdown formatting stays intact** — the code blocks and bold text will render perfectly on GitHub.
- **No red underlines** — this is pure markdown, not YAML, so GitHub’s editor will stay happy.
- **If you prefer to replace the entire old sections** — after pasting, you can delete the old `## Full Installation & Setup` and old `## Usage Examples` if you want a cleaner README (the pasted block already includes updated versions).
- **Using git locally instead?**  
  Just edit the same `README.md` file in your cloned repo, commit with the message above, and `git push`.

Once you commit this change, refresh the repository page and you will see the new Quick Start appear right after the repository tree — exactly where users expect it. The Makefile instructions will now guide everyone to the easiest production setup.

If you want me to give you the **full final README.md** (with this section already inserted in the right place plus the later sections from your current repo) as one clean block, or if you need help with anything else (e.g., creating the first release tag), just say the word!
