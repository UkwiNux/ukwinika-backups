# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v2.3] - 2026-04-21
### Added
- Full real-time file monitoring using inotify
- Complete restore logic with safe "drill" mode
- Adaptive database dumps for MySQL, PostgreSQL, and Oracle
- Optional LVM snapshots for hot database consistency
- Pre/post backup hook support
- Prometheus metrics export
- Removable USB auto-detection
- Concurrency locking with `flock`
- Detailed audit trail including SHA256 checksums
- Comprehensive Documentation (`UKWINIKA-DOCUMENTATION.md`)

## [v2.2] - 2026-03-10
### Changed
- Improved Borg lock handling (`--max-lock-wait 300` + automatic stale lock breaker)
- Updated configuration example with new options
- Enhanced systemd services with better I/O priority and restart behavior
- Expanded README.md with clear restore instructions and storage location

### Fixed
- Stale lock issues during rapid backup attempts
- Real-time monitoring warnings
- Missing environment variables from earlier versions

## [v2.1] - 2026-02-01
### Added
- Automatic stale lock breaker
- `--max-lock-wait 300` for Borg
- Improved logging and error handling

### Fixed
- Borg "unrecognized arguments: --encryption" error

## [v2.0] - 2026-01-16
### Added
- Automatic Borg + inotify-tools installation via Makefile
- Debian compatibility fixes

### Fixed
- Initial encryption flag issues on Debian

## [v1.0] - 2025-10-01
### Initial Release
- Core Borg backup functionality
- Systemd timer and services
- Basic configuration and logging

---

**Author:** Urayayi Kwinika  
**License:** MIT
