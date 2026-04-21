# Contributing to UKwinika Enhanced Automated Backup Script

Thank you for considering contributing to UKwinika!

## Code of Conduct

By participating in this project, you agree to abide by the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## How Can I Contribute?

### Reporting Bugs
1. Check the [Issues](https://github.com/UkwiNux/ukwinika-backups/issues) to see if the bug has already been reported.
2. If not, open a new issue using the **Bug Report** template.
3. Include:
   - Ubuntu/Debian version
   - Script version (`enhanced_automated_backups.sh --version`)
   - Exact command used
   - Log output from `/var/log/UKwinikaBackup.log`

### Suggesting Features
1. Open a new issue using the **Feature Request** template.
2. Clearly describe the feature and its benefit.

### Submitting Pull Requests
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/amazing-feature`).
3. Make your changes.
4. Ensure the script passes manual testing.
5. Update `CHANGELOG.md` under the `[Unreleased]` section.
6. Submit a Pull Request with a clear title and description.

### Development Setup
```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
