#!/usr/bin/env bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script – Smart Idempotent Edition
# Author: Urayayi Kwinika
# Version: 3.3.0
# Description:
#   - Fully idempotent 3‑2‑1 backup (Borg → USB → Cloud)
#   - Safe restore with dedicated target directory
#   - Stale‑lock prevention via cleanup trap
#   - Secrets separated from configuration
#   - Strict DB type validation
#   - Consistent variable naming & single source of excludes
#   - Repository lightweight existence check (no full integrity scan on every run)
#   - Real-time monitoring uses a child process to avoid lock re-acquisition
#   - Failure notifications alongside success notifications
#   - borg extract uses cd subshell for borg 1.2.x compatibility (no --target flag)
#   - Minimum borg version enforcement
#   - Retry/backoff for cloud upload and USB mount (transient failure tolerance)
#   - Config validation subcommand (no side effects)
#   - Dry-run mode for backup
#   - Scheduled consistency-check due-date tracking (borgmatic-style "checks")
# Usage:
#   backup [--dry-run]          Run full backup cycle
#   restore <archive> [target]  Restore archive to target (default /tmp/restore_<archive>)
#   list                        List archives
#   check                       Force a full repository integrity check now
#   check-if-due                Run repository check only if CHECK_INTERVAL_DAYS has elapsed
#   validate                    Validate configuration and environment; no side effects
#   real-time                   Monitor directories and backup on changes
#   init                        Initialise a new Borg repository
# =============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOCK_FILE="/var/lock/ukwinika-backup.lock"
LOG_FILE="/var/log/UKwinikaBackup.log"
AUDIT_LOG="/var/log/UKwinikaBackup_audit.log"

UKW_CONFIG="${UKW_CONFIG:-/etc/ukwinika-backup.conf}"
UKW_SECRETS="${UKW_SECRETS:-/etc/ukwinika-backup.secrets}"

# ---- Load configuration ----
if [[ ! -f "$UKW_CONFIG" ]]; then
    echo "ERROR: Configuration file ${UKW_CONFIG} not found." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$UKW_CONFIG"

if [[ -f "$UKW_SECRETS" ]]; then
    # shellcheck source=/dev/null
    source "$UKW_SECRETS"
fi

# BORG_PASSPHRASE must be set (either from secrets file or environment).
# Not exported globally — passed only to borg subprocesses via run_borg().
: "${BORG_PASSPHRASE:?ERROR: BORG_PASSPHRASE is not set. Check ${UKW_SECRETS}.}"

# ---- Configuration defaults ----
BORG_REPO="${BORG_REPO:-/UKwinikaBackup/borg-repo}"

# Default arrays – declared only if the config did not set them.
if [[ -z "${BACKUP_PATHS+x}" ]]; then
    BACKUP_PATHS=("/")
fi
if [[ -z "${EXCLUDE_DIRS+x}" ]]; then
    EXCLUDE_DIRS=("/proc" "/sys" "/dev" "/tmp" "/run" "/mnt" "/media" "/lost+found")
fi

RETENTION_DAYS="${RETENTION_DAYS:-90}"
RETENTION_VERSIONS="${RETENTION_VERSIONS:-5}"

USB_MOUNT="${USB_MOUNT:-/mnt/backup_usb}"
USB_RSYNC_TARGET="${USB_RSYNC_TARGET:-}"
CLOUD_REMOTE="${CLOUD_REMOTE:-}"
DB_TYPE="${DB_TYPE:-none}"

PRE_HOOK="${PRE_HOOK:-}"
POST_HOOK="${POST_HOOK:-}"
HOOK_FAIL_ACTION="${HOOK_FAIL_ACTION:-fatal}"

REAL_TIME_DIRS=("${REAL_TIME_DIRS[@]:-/etc /home}")
REAL_TIME_DEBOUNCE_SEC="${REAL_TIME_DEBOUNCE_SEC:-60}"
RESTORE_VERIFY_PATHS="${RESTORE_VERIFY_PATHS:-etc/hostname etc/os-release etc/fstab}"

SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_TO="${EMAIL_TO:-}"
METRICS_ENABLED="${METRICS_ENABLED:-yes}"
PROMETHEUS_FILE="${PROMETHEUS_FILE:-/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom}"

DB_DUMP_DIR="${DB_DUMP_DIR:-/tmp/ukwinika-db-dump}"
CHECKSUM_FILE="${CHECKSUM_FILE:-/tmp/ukwinika-backup-checksums.txt}"

# ---- Borg version enforcement ----
MIN_BORG_VERSION="${MIN_BORG_VERSION:-1.2.0}"

# ---- Retry/backoff for transient failures (USB mount, cloud upload) ----
USB_RETRY_ATTEMPTS="${USB_RETRY_ATTEMPTS:-3}"
USB_RETRY_DELAY_SEC="${USB_RETRY_DELAY_SEC:-5}"
CLOUD_RETRY_ATTEMPTS="${CLOUD_RETRY_ATTEMPTS:-3}"
CLOUD_RETRY_DELAY_SEC="${CLOUD_RETRY_DELAY_SEC:-15}"

# ---- Scheduled consistency-check due-date tracking (borgmatic-style) ----
CHECK_STATE_FILE="${CHECK_STATE_FILE:-/var/lib/ukwinika/last-check-timestamp}"
CHECK_INTERVAL_DAYS="${CHECK_INTERVAL_DAYS:-7}"

# ---- Dry-run flag (set by CLI dispatch, not meant to be set in config) ----
DRY_RUN="${DRY_RUN:-0}"

# =============================================================================
# Security helpers
# =============================================================================
run_borg() {
    env BORG_PASSPHRASE="$BORG_PASSPHRASE" borg "$@"
}

validate_config_security() {
    [[ "${UKW_SKIP_CONFIG_SECURITY:-}" == "1" ]] && return 0
    local f perm owner
    for f in "$UKW_CONFIG" "$UKW_SECRETS"; do
        [[ ! -f "$f" ]] && continue
        perm=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%OLp' "$f" 2>/dev/null || echo "")
        owner=$(stat -c '%u' "$f" 2>/dev/null || stat -f '%u' "$f" 2>/dev/null || echo "")
        case "$perm" in
            600|400) ;;
            *)
                echo "FATAL: Refusing to run: ${f} has insecure mode ${perm} (required 600 or 400)" >&2
                exit 1
                ;;
        esac
        if [[ "$owner" != "0" ]]; then
            echo "FATAL: Refusing to run: ${f} must be owned by root (uid 0)" >&2
            exit 1
        fi
    done
}

check_borg_version() {
    command -v borg >/dev/null 2>&1 || die "borg is not installed or not on PATH"
    local ver
    ver=$(borg --version 2>/dev/null | awk '{print $2}')
    [[ -z "$ver" ]] && die "Unable to determine installed borg version"
    if [[ "$(printf '%s\n%s\n' "$MIN_BORG_VERSION" "$ver" | sort -V | head -1)" != "$MIN_BORG_VERSION" ]]; then
        die "borg version ${ver} is older than the required minimum ${MIN_BORG_VERSION}. Upgrade borgbackup."
    fi
    log "borg version check passed (${ver} >= required ${MIN_BORG_VERSION})"
}

# retry <attempts> <delay_sec> -- <command...>
# Generic retry/backoff wrapper for transient failures (network mounts, cloud
# uploads). Does not retry logic/validation errors, only the command's exit code.
retry() {
    local attempts="$1" delay="$2"
    shift 2
    local n=1
    until "$@"; do
        if (( n >= attempts )); then
            log "WARNING: command failed after ${attempts} attempt(s): $*"
            return 1
        fi
        log "WARNING: command failed (attempt ${n}/${attempts}). Retrying in ${delay}s: $*"
        sleep "$delay"
        n=$(( n + 1 ))
    done
    return 0
}

ensure_borg_repo_excluded() {
    local dir repo_parent
    repo_parent="$(dirname "$BORG_REPO")"
    for dir in "${EXCLUDE_DIRS[@]}"; do
        [[ "$dir" == "$BORG_REPO" || "$dir" == "$repo_parent" || "$dir" == "${repo_parent}/" ]] && return 0
    done
    EXCLUDE_DIRS+=("$BORG_REPO")
    log "Auto-excluded BORG_REPO from backup paths: ${BORG_REPO}"
}

# =============================================================================
# Logging helpers
# =============================================================================
log()   { echo "$(date '+%F %T') $SCRIPT_NAME: $*" | tee -a "$LOG_FILE"; }
audit() {
    echo "$(date '+%F %T') [AUDIT] $1" | tee -a "$AUDIT_LOG"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        sha256sum "$2" >> "$AUDIT_LOG"
    fi
}
die()   { log "FATAL: $*"; notify "FAILED: $*"; exit 1; }

validate_config_security
ensure_borg_repo_excluded

# =============================================================================
# Locking
# =============================================================================
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another backup instance is already running. Exiting."
    exit 0
fi
cleanup_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE"
}
trap cleanup_lock EXIT INT TERM

# =============================================================================
# Hook runner
# =============================================================================
run_hook() {
    local hook="$1"
    [[ -z "$hook" || ! -x "$hook" ]] && return 0
    log "Running hook: $hook"
    if "$hook"; then
        log "Hook succeeded: $hook"
    else
        if [[ "$HOOK_FAIL_ACTION" == "fatal" ]]; then
            die "Hook '$hook' failed"
        else
            log "WARNING: Hook '$hook' failed (non-fatal)"
        fi
    fi
}

# =============================================================================
# Database dump
# Returns the dump directory path, or empty string if DB_TYPE=none.
# =============================================================================
db_dump() {
    if [[ "$DB_TYPE" == "none" ]]; then
        echo ""
        return 0
    fi

    rm -rf "$DB_DUMP_DIR"
    mkdir -p "$DB_DUMP_DIR"

    case "$DB_TYPE" in
        mysql)
            log "Dumping all MySQL databases..."
            mysqldump --all-databases --single-transaction \
                      --quick --lock-tables=false \
                      > "${DB_DUMP_DIR}/mysql-all.sql" \
                || die "MySQL dump failed"
            ;;
        postgresql)
            log "Dumping all PostgreSQL databases..."
            # shellcheck disable=SC2024
            # Rationale: this script always runs as root (systemd User=root),
            # so the redirect's file descriptor is opened by the parent (root)
            # shell BEFORE sudo drops privilege to `postgres`; pg_dumpall
            # inherits the already-open fd, so the dump is written correctly
            # regardless of postgres's own filesystem permissions on DB_DUMP_DIR.
            sudo -u postgres pg_dumpall \
                > "${DB_DUMP_DIR}/postgresql-all.sql" \
                || die "PostgreSQL dump failed"
            ;;
        mongodb)
            log "Dumping MongoDB..."
            mongodump --out "${DB_DUMP_DIR}/mongo" \
                || die "MongoDB dump failed"
            ;;
        *)
            die "Unsupported DB_TYPE='${DB_TYPE}'. Aborting for data safety."
            ;;
    esac

    echo "$DB_DUMP_DIR"
}

# =============================================================================
# Borg archive creation + pruning
# =============================================================================
borg_backup() {
    local dump_path="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H:%M:%S')
    local archive_name="${HOSTNAME:-$(hostname)}-${timestamp}"

    local exclude_args=()
    for dir in "${EXCLUDE_DIRS[@]}"; do
        exclude_args+=(--exclude "$dir")
    done

    local extra_paths=()
    [[ -n "$dump_path" ]] && extra_paths+=("$dump_path")

    local paths_to_backup=()
    if [[ "${UKW_REALTIME_TRIGGER:-}" == "1" ]]; then
        paths_to_backup=("${REAL_TIME_DIRS[@]}")
        log "Real-time trigger: backing up monitored paths only: ${paths_to_backup[*]}"
    else
        paths_to_backup=("${BACKUP_PATHS[@]}")
    fi

    local dry_run_args=()
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        dry_run_args+=(--dry-run)
        log "DRY RUN: Simulating Borg archive creation for '${archive_name}' (no data will be written)..."
    else
        log "Creating Borg archive '${archive_name}'..."
    fi

    run_borg create              \
        --verbose            \
        --filter AME         \
        --list               \
        --stats              \
        --show-rc            \
        --compression lz4    \
        --exclude-caches     \
        "${dry_run_args[@]}" \
        "${exclude_args[@]}" \
        "${BORG_REPO}::${archive_name}" \
        "${paths_to_backup[@]}" \
        "${extra_paths[@]}"  \
        || die "borg create failed"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log "DRY RUN: Skipping prune (no archive was actually created)."
        return 0
    fi

    log "Pruning old archives (keep-within ${RETENTION_DAYS}d, keep-last ${RETENTION_VERSIONS})..."
    run_borg prune               \
        --list               \
        --show-rc            \
        --keep-within "${RETENTION_DAYS}d" \
        --keep-last  "$RETENTION_VERSIONS" \
        "$BORG_REPO"         \
        || die "borg prune failed"
}

# =============================================================================
# USB secondary copy
# =============================================================================
validate_usb_mount() {
    local root_dev usb_dev usb_fstype

    if ! mountpoint -q "$USB_MOUNT"; then
        log "Mounting USB at ${USB_MOUNT} (up to ${USB_RETRY_ATTEMPTS} attempt(s))..."
        retry "$USB_RETRY_ATTEMPTS" "$USB_RETRY_DELAY_SEC" mount "$USB_MOUNT" \
            || die "Failed to mount USB at ${USB_MOUNT} after ${USB_RETRY_ATTEMPTS} attempts"
    fi

    usb_fstype=$(findmnt -n -o FSTYPE --target "$USB_MOUNT" 2>/dev/null || true)
    if [[ -z "$usb_fstype" ]]; then
        die "USB_MOUNT (${USB_MOUNT}) is not a mounted filesystem"
    fi

    root_dev=$(findmnt -n -o SOURCE --target / 2>/dev/null || true)
    usb_dev=$(findmnt -n -o SOURCE --target "$USB_MOUNT" 2>/dev/null || true)
    if [[ -n "$root_dev" && "$root_dev" == "$usb_dev" ]]; then
        die "USB_MOUNT (${USB_MOUNT}) is on the same block device as / — refusing rsync --delete"
    fi
}

validate_usb_target() {
    local resolved_mount resolved_target

    resolved_mount=$(realpath -m "$USB_MOUNT")
    resolved_target=$(realpath -m "$USB_RSYNC_TARGET")

    # BUGFIX (v3.3.0): previously the success branch of this case statement
    # did `return 0` immediately, which meant the mkdir auto-creation block
    # below could never execute (confirmed dead code via ShellCheck SC2317).
    # The case now only validates containment; directory creation always
    # runs afterwards for the valid path.
    case "${resolved_target}/" in
        "${resolved_mount}/"*) ;;
        *)
            die "USB_RSYNC_TARGET (${USB_RSYNC_TARGET}) must be inside USB_MOUNT (${USB_MOUNT})"
            ;;
    esac

    if [[ ! -d "$USB_RSYNC_TARGET" ]]; then
        log "Creating USB rsync target directory: ${USB_RSYNC_TARGET}"
        mkdir -p "$USB_RSYNC_TARGET" || die "Failed to create USB_RSYNC_TARGET (${USB_RSYNC_TARGET})"
    fi
}

sync_to_usb() {
    if [[ -z "$USB_RSYNC_TARGET" ]]; then
        log "No USB target configured. Skipping secondary copy."
        return 0
    fi

    validate_usb_mount
    validate_usb_target

    log "Syncing Borg repository to USB (rsync -a --delete)..."
    rsync -a --delete "${BORG_REPO}/" "${USB_RSYNC_TARGET}/" \
        || die "USB rsync failed"
    sync

    umount "$USB_MOUNT" || log "WARNING: Could not unmount USB at ${USB_MOUNT}"
}

# =============================================================================
# Cloud tertiary copy
# =============================================================================
cloud_upload() {
    if [[ -z "$CLOUD_REMOTE" ]]; then
        log "No cloud remote configured. Skipping tertiary copy."
        return 0
    fi

    if ! command -v rclone >/dev/null 2>&1; then
        log "WARNING: rclone not found. Skipping cloud upload."
        return 0
    fi

    log "Uploading to cloud: ${CLOUD_REMOTE} (up to ${CLOUD_RETRY_ATTEMPTS} attempt(s))..."
    if retry "$CLOUD_RETRY_ATTEMPTS" "$CLOUD_RETRY_DELAY_SEC" \
        rclone copy "$BORG_REPO" "${CLOUD_REMOTE}/borg_repo" --progress; then
        log "Cloud upload succeeded."
    else
        log "WARNING: Cloud upload failed after ${CLOUD_RETRY_ATTEMPTS} attempts. The backup is still available locally and on USB."
    fi
}

# =============================================================================
# Audit – SHA256 checksums of repository objects + restore drill paths
# =============================================================================
audit_checksum() {
    log "Generating SHA256 checksums of repository..."
    find "$BORG_REPO" -type f -exec sha256sum {} + > "$CHECKSUM_FILE"
    audit "Checksums saved to ${CHECKSUM_FILE}" "$CHECKSUM_FILE"
}

audit_verify_path_checksums() {
    local rel_path live_path
    local -a verify_paths=()

    read -r -a verify_paths <<< "$RESTORE_VERIFY_PATHS"

    audit "Recording SHA256 checksums for restore drill verification paths"
    for rel_path in "${verify_paths[@]}"; do
        live_path="/${rel_path}"
        if [[ -f "$live_path" ]]; then
            sha256sum "$live_path" >> "$AUDIT_LOG"
        else
            log "WARNING: RESTORE_VERIFY_PATHS entry not found on live system: ${live_path}"
        fi
    done
}

# =============================================================================
# Prometheus metrics (atomic full-file rewrite; preserves restore metrics)
# =============================================================================
_prom_read_scalar() {
    local name="$1" default="$2"
    if [[ -f "$PROMETHEUS_FILE" ]]; then
        grep -E "^${name} " "$PROMETHEUS_FILE" 2>/dev/null | awk '{print $2}' | tail -1 || echo "$default"
    else
        echo "$default"
    fi
}

_prom_read_restore_archive() {
    if [[ -f "$PROMETHEUS_FILE" ]]; then
        grep -E '^ukwinika_restore_test_last_result{' "$PROMETHEUS_FILE" 2>/dev/null \
            | sed -n 's/.*archive="\([^"]*\)".*/\1/p' | tail -1 || echo "unknown"
    else
        echo "unknown"
    fi
}

_prom_read_restore_result() {
    if [[ -f "$PROMETHEUS_FILE" ]]; then
        grep -E '^ukwinika_restore_test_last_result{' "$PROMETHEUS_FILE" 2>/dev/null \
            | sed -n 's/.*} \([0-9]*\)$/\1/p' | tail -1 || echo "0"
    else
        echo "0"
    fi
}

write_prometheus_metrics() {
    [[ "$METRICS_ENABLED" != "yes" ]] && return 0

    local last_archive backup_ts
    local restore_ts restore_result restore_passed restore_failed restore_archive

    last_archive=$(run_borg list --short --last 1 "$BORG_REPO" 2>/dev/null || echo "none")
    backup_ts=$(date +%s)

    restore_ts=$(_prom_read_scalar "ukwinika_restore_test_last_run_seconds" "0")
    restore_result=$(_prom_read_restore_result)
    restore_passed=$(_prom_read_scalar "ukwinika_restore_test_checks_passed" "0")
    restore_failed=$(_prom_read_scalar "ukwinika_restore_test_checks_failed" "0")
    restore_archive=$(_prom_read_restore_archive)

    mkdir -p "$(dirname "$PROMETHEUS_FILE")"
    cat > "$PROMETHEUS_FILE" << EOF
# HELP ukwinika_backup_last_success_seconds Unix timestamp of the last successful backup
# TYPE ukwinika_backup_last_success_seconds gauge
ukwinika_backup_last_success_seconds ${backup_ts}
# HELP ukwinika_backup_latest_archive Label carrying the name of the most recent archive
# TYPE ukwinika_backup_latest_archive gauge
ukwinika_backup_latest_archive{name="${last_archive}"} 1
# HELP ukwinika_restore_test_last_run_seconds Unix timestamp of the last restore drill
# TYPE ukwinika_restore_test_last_run_seconds gauge
ukwinika_restore_test_last_run_seconds ${restore_ts}
# HELP ukwinika_restore_test_last_result Result of the last restore drill (1=pass, 0=fail)
# TYPE ukwinika_restore_test_last_result gauge
ukwinika_restore_test_last_result{archive="${restore_archive}"} ${restore_result}
# HELP ukwinika_restore_test_checks_passed Number of verification checks that passed
# TYPE ukwinika_restore_test_checks_passed gauge
ukwinika_restore_test_checks_passed ${restore_passed}
# HELP ukwinika_restore_test_checks_failed Number of verification checks that failed
# TYPE ukwinika_restore_test_checks_failed gauge
ukwinika_restore_test_checks_failed ${restore_failed}
EOF
    log "Prometheus metrics written to ${PROMETHEUS_FILE}"
}

push_metrics() {
    write_prometheus_metrics
}

# =============================================================================
# Notifications (Slack + email) – called on both success and failure
# =============================================================================
notify() {
    local status="$1"
    local host
    host=$(hostname)

    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Backup ${status} on ${host}\"}" \
            "$SLACK_WEBHOOK" || true
    fi

    if [[ -n "$EMAIL_TO" ]]; then
        echo "Backup ${status} on ${host}" \
            | mail -s "UKwinika Backup ${status}" "$EMAIL_TO" || true
    fi
}

# =============================================================================
# Real-time monitoring
# =============================================================================
real_time_mode() {
    log "Starting real-time monitoring (inotify) on: ${REAL_TIME_DIRS[*]} (debounce: ${REAL_TIME_DEBOUNCE_SEC}s)"
    command -v inotifywait >/dev/null 2>&1 \
        || die "inotify-tools not installed. Run: sudo make install"

    while true; do
        inotifywait -r -e modify,create,delete,move \
            "${REAL_TIME_DIRS[@]}" 2>/dev/null || true
        log "Change detected – coalescing for ${REAL_TIME_DEBOUNCE_SEC}s before backup."
        while inotifywait -r -t "$REAL_TIME_DEBOUNCE_SEC" \
            -e modify,create,delete,move \
            "${REAL_TIME_DIRS[@]}" 2>/dev/null; do
            log "Additional changes detected – extending debounce window."
        done
        log "Debounce complete – triggering scoped backup in child process."
        flock -u 200 2>/dev/null || true
        UKW_REALTIME_TRIGGER=1 "$0" backup
        flock -n 200 || true
    done
}

# =============================================================================
# Restore
# Uses a cd subshell instead of --target for compatibility with borg 1.2.x.
# The --target flag was introduced in BorgBackup 1.4 and is not available on
# distributions shipping borg 1.2.x (Debian 12, Ubuntu 22.04/24.04, RHEL 9).
# =============================================================================
restore_backup() {
    local archive="$1"
    local target="${2:-/tmp/restore_${archive}}"
    log "Restoring archive '${archive}' to '${target}'..."
    mkdir -p "$target"
    ( cd "$target" && run_borg extract "${BORG_REPO}::${archive}" ) \
        || die "borg extract failed"
    log "Restore completed successfully to ${target}"
}

# =============================================================================
# Convenience wrappers
# =============================================================================
list_archives() {
    run_borg list "$BORG_REPO" || die "Cannot list archives"
}

check_repo() {
    run_borg check "$BORG_REPO" || die "Repository check failed"
}

# =============================================================================
# Scheduled consistency-check due-date tracking (borgmatic-style "checks")
# A full `borg check` walks and verifies every object in the repository and
# can be expensive on large repos. Rather than running it on every backup
# (or relying purely on human memory), this tracks the last check timestamp
# and only performs one when CHECK_INTERVAL_DAYS has elapsed. Intended to be
# invoked frequently (e.g. daily, alongside the backup) via `check-if-due`.
# =============================================================================
check_if_due() {
    local now last_check_ts age_days
    now=$(date +%s)
    if [[ -f "$CHECK_STATE_FILE" ]]; then
        last_check_ts=$(cat "$CHECK_STATE_FILE" 2>/dev/null || echo 0)
        [[ "$last_check_ts" =~ ^[0-9]+$ ]] || last_check_ts=0
    else
        last_check_ts=0
    fi
    age_days=$(( (now - last_check_ts) / 86400 ))

    if (( age_days >= CHECK_INTERVAL_DAYS )); then
        log "Repository check is due (last check ${age_days}d ago; interval ${CHECK_INTERVAL_DAYS}d). Running 'borg check'..."
        check_repo
        mkdir -p "$(dirname "$CHECK_STATE_FILE")"
        echo "$now" > "$CHECK_STATE_FILE"
        log "Repository check completed and recorded at ${CHECK_STATE_FILE}."
    else
        log "Repository check not due yet (last check ${age_days}d ago; interval ${CHECK_INTERVAL_DAYS}d). Skipping."
    fi
}

# =============================================================================
# Configuration validation — no side effects, safe to run at any time.
# Mirrors borgmatic's `config validate` behaviour: verifies required
# variables, checks the borg binary/version, and reports repository state
# without touching it.
# =============================================================================
validate_configuration() {
    local ok=1

    echo "UKW_CONFIG:          ${UKW_CONFIG}"
    echo "UKW_SECRETS:         ${UKW_SECRETS}"
    echo "BORG_REPO:           ${BORG_REPO}"
    echo "BACKUP_PATHS:        ${BACKUP_PATHS[*]}"
    echo "EXCLUDE_DIRS:        ${EXCLUDE_DIRS[*]}"
    echo "RETENTION_DAYS:      ${RETENTION_DAYS}"
    echo "RETENTION_VERSIONS:  ${RETENTION_VERSIONS}"
    echo "DB_TYPE:             ${DB_TYPE}"
    echo "USB_RSYNC_TARGET:    ${USB_RSYNC_TARGET:-<none>}"
    echo "CLOUD_REMOTE:        ${CLOUD_REMOTE:-<none>}"
    echo "CHECK_INTERVAL_DAYS: ${CHECK_INTERVAL_DAYS}"
    echo "MIN_BORG_VERSION:    ${MIN_BORG_VERSION}"

    if command -v borg >/dev/null 2>&1; then
        echo "borg version:        $(borg --version)"
    else
        echo "borg version:        NOT FOUND"
        ok=0
    fi

    if [[ -d "$BORG_REPO" && -f "${BORG_REPO}/config" ]]; then
        echo "Repository state:    exists at ${BORG_REPO}"
    else
        echo "Repository state:    does not exist yet (run: sudo $0 init)"
    fi

    case "$DB_TYPE" in
        none|mysql|postgresql|mongodb) ;;
        *)
            echo "ERROR: DB_TYPE='${DB_TYPE}' is not one of none|mysql|postgresql|mongodb"
            ok=0
            ;;
    esac

    if (( ok )); then
        echo "✅ Configuration valid."
        return 0
    else
        echo "❌ Configuration has errors — see above."
        return 1
    fi
}

# =============================================================================
# Repository existence check
# =============================================================================
ensure_repo_exists() {
    if [[ ! -d "$BORG_REPO" ]] || [[ ! -f "${BORG_REPO}/config" ]]; then
        log "ERROR: Borg repository not found at ${BORG_REPO}."
        echo "Run: sudo $0 init" >&2
        return 1
    fi
    return 0
}

# =============================================================================
# Full backup cycle
# =============================================================================
run_backup() {
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log "=== Starting UKwinika Enhanced Backup (DRY RUN) ==="
    else
        log "=== Starting UKwinika Enhanced Backup ==="
    fi

    run_hook "$PRE_HOOK"
    local dump_path
    dump_path=$(db_dump)
    borg_backup "$dump_path"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log "=== DRY RUN complete — no changes made to the repository, USB, cloud, or metrics ==="
        return 0
    fi

    audit_verify_path_checksums
    sync_to_usb
    cloud_upload
    audit_checksum
    push_metrics
    notify "SUCCESS"
    run_hook "$POST_HOOK"
    log "=== Backup completed successfully ==="
}

# =============================================================================
# CLI dispatch
# =============================================================================
# Config validation and the usage message shouldn't be gated on a working
# borg binary/version; everything else should be.
case "${1:-}" in
    validate|"")
        ;;
    *)
        check_borg_version
        ;;
esac

case "${1:-}" in
    backup)
        ensure_repo_exists || die "Repository missing or invalid"
        if [[ "${2:-}" == "--dry-run" ]]; then
            DRY_RUN=1 run_backup
        else
            run_backup
        fi
        ;;
    restore)
        ensure_repo_exists || die "Repository missing or invalid"
        restore_backup "${2:?Archive name required}" "${3:-}"
        ;;
    list)
        ensure_repo_exists || die "Repository missing or invalid"
        list_archives
        ;;
    check)
        ensure_repo_exists || die "Repository missing or invalid"
        check_repo
        ;;
    check-if-due)
        ensure_repo_exists || die "Repository missing or invalid"
        check_if_due
        ;;
    validate)
        validate_configuration
        ;;
    real-time)
        ensure_repo_exists || die "Repository missing or invalid"
        real_time_mode
        ;;
    init)
        if [[ -d "$BORG_REPO" && -f "${BORG_REPO}/config" ]]; then
            log "Repository already exists at ${BORG_REPO} – nothing to initialise."
            exit 0
        fi
        log "Initialising new Borg repository at ${BORG_REPO}..."
        mkdir -p "$(dirname "$BORG_REPO")"
        run_borg init --encryption=repokey "$BORG_REPO" \
            || die "borg init failed"
        log "Repository initialised successfully at ${BORG_REPO}."
        ;;
    *)
        echo "Usage: $0 {backup [--dry-run]|restore <archive> [target]|list|check|check-if-due|validate|real-time|init}"
        exit 1
        ;;
esac
