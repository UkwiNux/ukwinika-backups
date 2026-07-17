# Security Policy

## Supported Versions

Only the current stable release receives security updates. Older versions are
unsupported — please upgrade.

| Version | Supported          |
| ------- | ------------------ |
| 3.3.x   | ✅ Current stable  |
| 3.2.x   | ⚠️ Upgrade recommended |
| 3.1.x   | ⚠️ Security fixes only (until 2026-10-01) |
| 3.0.x   | ❌ No longer supported |
| < 3.0   | ❌ No longer supported |

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately via one of the following methods:

- **GitHub Private Security Advisory:** [Security tab → Report a vulnerability](https://github.com/UkwiNux/ukwinika-backups/security/advisories/new)
- **Email:** Contact the maintainer directly through the profile linked on the repository.

### What to include

- A description of the vulnerability and its potential impact.
- Steps to reproduce (script version, OS, configuration snippet if relevant).
- Any suggested fix or mitigation if you have one.

### What to expect

| Milestone | Timeframe |
|---|---|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 5 business days |
| Patch release (if confirmed) | Within 14 days for critical; 30 days for moderate |
| Public disclosure | Coordinated with the reporter after a patch is available |

Vulnerabilities that are accepted will result in a patched release and a
public advisory. Vulnerabilities that are declined will receive a clear
explanation.

## Scope

This policy covers `enhanced_automated_backups.sh` and the supporting
configuration, systemd units, and hook examples in this repository.
Third-party tools (BorgBackup, rclone, rsync, inotify-tools) have their own
security policies.
