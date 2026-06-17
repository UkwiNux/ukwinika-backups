# Contributing to UKwinika Enhanced Automated Backup Script

Thank you for your interest in contributing to UKwinika EABS. This project is a production-grade backup solution used on live systems, so contributions are held to a high standard of correctness, clarity, and safety. Please read this document carefully before opening an issue or submitting a pull request.

---

## Table of Contents

1. [Code of Conduct](#1-code-of-conduct)
2. [What We Are Looking For](#2-what-we-are-looking-for)
3. [What We Are Not Looking For](#3-what-we-are-not-looking-for)
4. [Reporting Bugs](#4-reporting-bugs)
5. [Suggesting Features](#5-suggesting-features)
6. [Security Vulnerabilities](#6-security-vulnerabilities)
7. [Development Setup](#7-development-setup)
8. [Coding Standards](#8-coding-standards)
9. [Testing Requirements](#9-testing-requirements)
10. [Submitting a Pull Request](#10-submitting-a-pull-request)
11. [Commit Message Format](#11-commit-message-format)
12. [Documentation Standards](#12-documentation-standards)
13. [Changelog Requirements](#13-changelog-requirements)
14. [Review Process](#14-review-process)
15. [Questions and Discussions](#15-questions-and-discussions)

---

## 1. Code of Conduct

By participating in this project you agree to abide by the [Contributor Covenant Code of Conduct v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Disrespectful, discriminatory, or harmful behaviour will not be tolerated and may result in a permanent ban from the project.

---

## 2. What We Are Looking For

Contributions that are well-aligned with the project's goals are most likely to be accepted:

- **Bug fixes** — verified, minimal, and accompanied by a description of the failure condition.
- **Distribution compatibility** — fixes for Debian, Ubuntu, RHEL, Rocky Linux, AlmaLinux, or CentOS that do not break other supported distributions.
- **Security improvements** — hardening, safer defaults, or reduced attack surface. See [Security Vulnerabilities](#6-security-vulnerabilities) for the correct reporting path.
- **New database engine support** — additional `DB_TYPE` targets in `db_dump()`, following the same validation and abort-on-failure pattern as the existing engines.
- **Restore test improvements** — enhancements to `ukwinika_automated_restore.sh`: additional verification methods, new CLI subcommands, improved Prometheus metrics, or broader distribution coverage. The restore script must remain fully non-destructive and must never write to paths outside `RESTORE_TARGET_BASE`.
- **Documentation improvements** — corrections to factual errors, clearer explanations, or better examples. Documentation must accurately reflect what the code actually does.
- **CI improvements** — additions to `.github/workflows/test.yml` that increase coverage without introducing fragility.
- **Hook examples** — practical, well-commented additions to `hooks/` that demonstrate real-world pre/post-backup scenarios.

---

## 3. What We Are Not Looking For

To avoid wasted effort, please do not open pull requests for the following without first discussing them in a [Discussion](https://github.com/UkwiNux/ukwinika-backups/discussions):

- **Rewriting core logic** in another language or framework. This is intentionally a self-contained bash script with no external runtime dependencies beyond BorgBackup.
- **GUI or web interfaces.** Out of scope.
- **Alternative encryption backends.** BorgBackup's `repokey` encryption is the supported and tested mechanism.
- **Cosmetic-only changes** — whitespace reformatting, renaming variables for style preference, or restructuring that introduces no functional change.
- **Dependency additions** beyond what `make deps` already installs, unless there is a strong functional case and the dependency is available in standard repositories on all supported distributions.

---

## 4. Reporting Bugs

Before opening a bug report, please:

1. Check the [existing issues](https://github.com/UkwiNux/ukwinika-backups/issues) to confirm the bug has not already been reported.
2. Reproduce the issue on the **latest released version** (currently v3.2). Bugs in older versions will not be investigated unless they also affect the current release.
3. Collect the relevant log output from `/var/log/UKwinikaBackup.log`.

When opening a bug report, include all of the following:

| Field | What to provide |
|---|---|
| **Script version** | Output of `grep '^# Version' /usr/local/bin/enhanced_automated_backups.sh` |
| **Operating system** | Distribution name and version (e.g. `Ubuntu 24.04 LTS`, `Rocky Linux 9.3`) |
| **BorgBackup version** | Output of `borg --version` |
| **Exact command** | The full command that triggered the issue |
| **Expected behaviour** | What you expected to happen |
| **Actual behaviour** | What actually happened |
| **Log output** | Relevant lines from `/var/log/UKwinikaBackup.log` (redact any passwords or keys) |
| **Configuration** | Relevant lines from `/etc/ukwinika-backup.conf` (never include the secrets file) |

Incomplete bug reports may be closed without investigation.

---

## 5. Suggesting Features

Feature requests are welcome but must be grounded in the project's design principles:

- **Idempotency** — the script must remain safe to run any number of times without unintended side effects.
- **No silent failures** — every failure path must log a clear message and, where appropriate, send a notification.
- **Secrets stay in the secrets file** — no new configuration variable that could hold a credential should be added to `ukwinika-backup.conf`.
- **Backward compatibility** — new variables must have safe defaults so existing installations continue to function without modification.

When opening a feature request, describe:

1. The problem you are trying to solve, not just the solution you have in mind.
2. How the feature aligns with the principles above.
3. Whether you are willing to implement it yourself.

---

## 6. Security Vulnerabilities

**Do not open a public GitHub issue for security vulnerabilities.**

Please follow the process described in [SECURITY.md](SECURITY.md). In summary: report privately via GitHub's Security Advisory tool or via email, and allow time for a coordinated fix before any public disclosure.

---

## 7. Development Setup

### Prerequisites

The following tools must be available on your development system:

- `bash` 4.3 or later (`bash --version`)
- `borgbackup` 1.2 or later (`borg --version`)
- `rsync` (`rsync --version`)
- `inotify-tools` (provides `inotifywait`)
- `mailutils` or `mailx` (provides the `mail` command)
- `shellcheck` — for static analysis of shell scripts (`shellcheck --version`)

Install all runtime dependencies automatically:

```bash
sudo make deps
```

### Clone and install

```bash
git clone https://github.com/UkwiNux/ukwinika-backups.git
cd ukwinika-backups
sudo make install
sudo make systemd
```

### Verify your environment

Confirm the script passes a syntax check before making any changes:

```bash
bash -n enhanced_automated_backups.sh
shellcheck enhanced_automated_backups.sh
```

Both commands must produce no output and exit 0.

---

## 8. Coding Standards

All contributions to `enhanced_automated_backups.sh` and `ukwinika_automated_restore.sh` must conform to the following standards. Pull requests that do not meet these requirements will be asked to revise before review.

### Shell

- The shebang must remain `#!/usr/bin/env bash`. Do not use `/bin/sh`.
- `set -euo pipefail` must remain on the first executable line. Do not remove or weaken it.
- All variables must be quoted: `"$VAR"`, not `$VAR`. Exceptions require an explicit comment explaining why.
- Arrays must be expanded with `"${ARRAY[@]}"`. Do not use `${ARRAY[*]}`.
- Use `[[ ... ]]` for conditionals, not `[ ... ]` or `test`.
- Use `local` for all variables declared inside functions.
- Do not use `eval`.
- Do not use backtick command substitution. Use `$( ... )` instead.

### Functions

- Every new function must have a comment block explaining its purpose, inputs, and outputs.
- Functions that can fail must call `die "descriptive message"` on failure so that notifications are sent and the lock is released cleanly. Do not use bare `exit 1`.
- Functions that return a value via `echo` must be documented as doing so; callers must capture the output with `var=$(function_name)` rather than relying on side effects.

### Configuration variables

- Every new configuration variable must have a documented default value in the script itself, applied with the `${VAR:-default}` pattern.
- Every new configuration variable must also be added to `config/ukwinika-backup.conf.example` with an inline comment explaining its purpose and valid values.
- Variables that hold paths must be validated before use (check that the path exists or is writable, as appropriate).
- No new variable that could hold a secret or credential may be placed in the main configuration file. It belongs in the secrets file.

### Secrets and sensitive data

- No secret, passphrase, token, or URL may ever appear in a log message, in an argument list visible to `ps`, or in any file other than `/etc/ukwinika-backup.secrets`.
- When in doubt, treat a value as sensitive and put it in the secrets file.

### ShellCheck compliance

Every change must pass `shellcheck enhanced_automated_backups.sh` with zero warnings. If a specific warning cannot be avoided, suppress it with a `# shellcheck disable=SCxxxx` annotation and include a comment explaining the reason.

---

## 9. Testing Requirements

### Before submitting

Run the following checks locally and confirm they all pass:

```bash
# 1. Bash syntax check
bash -n enhanced_automated_backups.sh

# 2. Static analysis
shellcheck enhanced_automated_backups.sh

# 3. Functional smoke test against a temporary repository
REPO=$(mktemp -d)
SECRETS=$(mktemp)
CONFIG=$(mktemp)

echo "BORG_PASSPHRASE=local-test-passphrase" > "$SECRETS"
cat > "$CONFIG" << EOF
BORG_REPO="${REPO}/borg-repo"
BACKUP_PATHS=("/tmp")
EXCLUDE_DIRS=()
RETENTION_DAYS=7
RETENTION_VERSIONS=1
USB_RSYNC_TARGET=""
CLOUD_REMOTE=""
DB_TYPE="none"
DB_DUMP_DIR="${REPO}/db-dump"
CHECKSUM_FILE="${REPO}/checksums.txt"
PRE_HOOK=""
POST_HOOK=""
HOOK_FAIL_ACTION="warn"
REAL_TIME_DIRS=("/tmp")
EMAIL_TO=""
METRICS_ENABLED="no"
PROMETHEUS_FILE="${REPO}/ukwinika_backup.prom"
EOF

export UKW_CONFIG="$CONFIG"
export UKW_SECRETS="$SECRETS"
export BORG_PASSPHRASE="local-test-passphrase"

borg init --encryption=repokey "${REPO}/borg-repo"
bash enhanced_automated_backups.sh list
bash enhanced_automated_backups.sh backup
bash enhanced_automated_backups.sh list
bash enhanced_automated_backups.sh check

rm -rf "$REPO" "$SECRETS" "$CONFIG"
```

All commands must exit 0.

### CI

The CI pipeline (`.github/workflows/test.yml`) runs automatically on every push and pull request to `main`. It performs:

- Bash syntax check (`bash -n`)
- Functional invocation test against a real temporary Borg repository
- Verification that all documented configuration variables are present in `config/ukwinika-backup.conf.example`

A pull request will not be merged if CI is failing. Do not ask for an exception.

### Testing scope

If your change touches any of the following areas, include a description in your pull request of how you tested it, beyond the standard smoke test above:

| Area changed | Additional testing expected |
|---|---|
| `db_dump()` | Test with the relevant database engine running locally |
| `sync_to_usb()` | Test with a real or loopback-mounted USB target |
| `cloud_upload()` | Test with a configured rclone remote |
| `real_time_mode()` | Verify the lock-release/re-acquire cycle does not deadlock |
| `restore_backup()` | Verify restored contents match originals via `diff -rq` |
| `push_metrics()` | Verify the `.prom` file is valid and parseable by Node Exporter |
| Hook execution | Test both `fatal` and `warn` failure action paths |
| Systemd units | Validate with `systemd-analyze verify <unit_file>` |

---

## 10. Submitting a Pull Request

### Before opening a PR

- [ ] Your branch is based on the latest `main`.
- [ ] `bash -n enhanced_automated_backups.sh` exits 0.
- [ ] `shellcheck enhanced_automated_backups.sh` exits 0 with no warnings.
- [ ] The functional smoke test (section 9) passes in full.
- [ ] `CHANGELOG.md` has been updated under `[Unreleased]` (see [Changelog Requirements](#13-changelog-requirements)).
- [ ] `config/ukwinika-backup.conf.example` has been updated if you added or changed any configuration variable.
- [ ] All documentation affected by your change has been updated to reflect the new behaviour.
- [ ] Your commit messages follow the format in [section 11](#11-commit-message-format).

### Branch naming

Use the following conventions:

| Type | Format | Example |
|---|---|---|
| Bug fix | `fix/<short-description>` | `fix/realtime-lock-deadlock` |
| Feature | `feat/<short-description>` | `feat/sqlite-db-support` |
| Documentation | `docs/<short-description>` | `docs/restore-checklist-v32` |
| CI / tooling | `ci/<short-description>` | `ci/add-shellcheck-step` |
| Refactor | `refactor/<short-description>` | `refactor/db-dump-error-handling` |

### Pull request description

Your PR description must include:

1. **What** — a concise summary of the change.
2. **Why** — the problem it solves or the improvement it makes, with a reference to the relevant issue if one exists (e.g. `Closes #42`).
3. **How** — a brief description of the approach taken, including any alternatives considered and rejected.
4. **Testing** — what you tested and how, beyond the standard smoke test.
5. **Breaking changes** — explicitly state `None` or describe any change in behaviour that affects existing installations.

Pull requests with descriptions that do not follow this structure will be asked to revise before review begins.

---

## 11. Commit Message Format

This project uses a simplified form of [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
<type>(<scope>): <short summary>

<body — optional, wrapped at 72 characters>

<footer — optional: references to issues, breaking change notices>
```

### Types

| Type | When to use |
|---|---|
| `fix` | A bug fix |
| `feat` | A new feature or capability |
| `docs` | Documentation only changes |
| `refactor` | Code restructuring with no functional change |
| `ci` | Changes to CI workflows or the Makefile |
| `chore` | Maintenance tasks (e.g. updating `.gitignore`) |
| `security` | A change that addresses a security concern |

### Scope

The scope should identify the area of the codebase affected, for example: `db_dump`, `restore`, `realtime`, `hooks`, `systemd`, `logrotate`, `config`, `ci`.

### Rules

- The short summary must be in the imperative mood: "fix lock deadlock", not "fixed lock deadlock" or "fixes lock deadlock".
- The short summary must not exceed 72 characters.
- Do not end the summary line with a period.
- Reference the relevant issue in the footer: `Closes #42` or `Refs #17`.

### Examples

```
fix(realtime): release parent flock before spawning child backup process

The monitoring loop held the exclusive flock while calling run_backup()
directly. The child process attempted to acquire the same lock and
blocked indefinitely. The fix releases the lock before exec'ing the
child and re-acquires it after the child exits.

Closes #58
```

```
feat(db_dump): add SQLite database dump support

Adds 'sqlite' as a valid DB_TYPE value. Uses sqlite3 .dump to produce
a plain-text SQL backup compatible with standard restore tooling.
Includes strict validation and abort-on-failure consistent with the
existing MySQL/PostgreSQL/MongoDB paths.

Closes #34
```

```
docs(RESTORE-CHECKLIST): update for v3.2 and fix shadow file example
```

---

## 12. Documentation Standards

All documentation in this repository — including `README.md`, `UKWINIKA-DOCUMENTATION.md`, `docs/RESTORE-CHECKLIST.md`, inline comments, and hook examples — must adhere to the following:

- **Accuracy over completeness.** A shorter, correct document is always preferable to a longer, inaccurate one. If you are unsure about a behaviour, test it before documenting it.
- **Reflect the code, not the intent.** Document what the script actually does, not what it was supposed to do or what a future version might do.
- **Commands must be copy-pasteable.** Every shell command shown in documentation must be tested and produce the described result on at least one supported distribution.
- **Paths must be consistent.** All file paths in documentation must match those used in the script, the configuration templates, and the systemd units exactly. Discrepancies between files were a source of bugs in earlier versions and must not be reintroduced.
- **No uncommitted changes referenced.** Documentation must not describe features or options that do not yet exist in the codebase.
- **Sensitive data must never appear.** No example in any document should include a real passphrase, API key, webhook URL, or email address. Use clearly placeholder values such as `YourStrongPassphraseHere123!` or `admin@example.com`.

---

## 13. Changelog Requirements

Every pull request that changes behaviour — including bug fixes, new features, and changes to configuration — must include an update to `CHANGELOG.md`.

- Add your entry under the `## [Unreleased]` section at the top of the file.
- Use the appropriate sub-heading: `### Added`, `### Changed`, or `### Fixed`.
- Write each entry as a complete sentence in the past tense, starting with the name of the function, variable, or feature affected in bold.
- Include enough detail that a system administrator reading the changelog can understand what changed and whether it affects their installation, without having to read the diff.

**Good example:**
```markdown
### Fixed
- **`sync_to_usb()`** — the USB drive was not unmounted if `rsync` exited non-zero,
  leaving the mount point occupied. The function now calls `umount` in a `trap` to
  guarantee cleanup regardless of exit status.
```

**Poor example:**
```markdown
### Fixed
- Fixed USB bug.
```

Documentation-only pull requests (corrections to `README.md`, `UKWINIKA-DOCUMENTATION.md`, etc.) do not require a changelog entry unless they correct a factual error that could have caused a user to misconfigure or misuse the system.

---

## 14. Review Process

All pull requests go through the following process:

1. **CI must pass.** The automated test suite runs on every push. A failing CI run will not be reviewed until it is fixed.
2. **Initial review.** The maintainer will review the PR for alignment with the project's design principles, coding standards, and documentation requirements. Feedback will be provided as review comments; please address all comments before requesting a re-review.
3. **Approval and merge.** Once the PR is approved, it will be squash-merged into `main`. The final commit message will follow the format in [section 11](#11-commit-message-format).

### Response times

This is a personally maintained open-source project. The maintainer aims to respond to new pull requests within **5 business days**. Complex changes or those affecting core logic may take longer.

If a pull request has had no activity for 30 days after feedback was provided and the requested changes have not been made, it may be closed. It can be reopened once the outstanding changes are addressed.

### What a good review looks like

Reviewers — including the maintainer — will evaluate pull requests against these criteria:

- Does the change do what it claims to do?
- Does it break any existing behaviour for users who do not use the new feature?
- Does it introduce any code path that could fail silently?
- Does it follow the coding standards in [section 8](#8-coding-standards)?
- Is the documentation accurate and consistent with the code?
- Is the changelog entry clear and informative?

---

## 15. Questions and Discussions

If you have a question about how to use the script, want to discuss a potential contribution before investing time in it, or want to share how you are using UKwinika in your environment, please use [GitHub Discussions](https://github.com/UkwiNux/ukwinika-backups/discussions) rather than opening an issue.

Issues are reserved for confirmed bugs and accepted feature requests. General questions opened as issues may be converted to discussions or closed without response.

---

Thank you for taking the time to contribute. Every improvement — whether a one-line documentation fix or a new database engine — makes the project more reliable for everyone who depends on it.
