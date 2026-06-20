#!/usr/bin/env bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script – Smart Idempotent Edition
# Author: Urayayi Kwinika
# Version: 3.2.1
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
# Usage:
#   backup                      Run full backup cycle
#   restore <archive> [target]  Restore archive to target (default /tmp/restore_<archive>)
#   list                        List archives
#   check                       Verify repository integrity
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

# BORG_PASSPHRASE must be set (either from secrets file or environment)
: "${BORG_PASSPHRASE:?ERROR: BORG_PASSPHRASE is not set. Check ${UKW_SECRETS}.}"
export BORG_PASSPHRASE

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
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_TO="${EMAIL_TO:-}"
METRICS_ENABLED="${METRICS_ENABLED:-yes}"
PROMETHEUS_FILE="${PROMETHEUS_FILE:-/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom}"

DB_DUMP_DIR="${DB_DUMP_DIR:-/tmp/ukwinika-db-dump}"
CHECKSUM_FILE="${CHECKSUM_FILE:-/tmp/ukwinika-backup-checksums.txt}"

# =============================================================================
# Logging helpers
# =============================================================================
log()   { echo "$(date '+%F %T') $SCRIPT_NAME: $*" | tee -a "$LOG_FILE"; }
audit() {
    echo "$(date '+%F %T') [AUDIT] $1" | tee -a "$AUDIT_LOG"
    [[ -n "${2:-}" && -f "$2" ]] && sha256sum "$2" >> "$AUDIT_LOG" || true
}
die()   { log "FATAL: $*"; notify "FAILED: $*"; exit 1; }

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

    log "Creating Borg archive '${archive_name}'..."
    borg create              \
        --verbose            \
        --filter AME         \
        --list               \
        --stats              \
        --show-rc            \
        --compression lz4    \
        --exclude-caches     \
        "${exclude_args[@]}" \
        "${BORG_REPO}::${archive_name}" \
        "${BACKUP_PATHS[@]}" \
        "${extra_paths[@]}"  \
        || die "borg create failed"

    log "Pruning old archives (keep-within ${RETENTION_DAYS}d, keep-last ${RETENTION_VERSIONS})..."
    borg prune               \
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
sync_to_usb() {
    if [[ -z "$USB_RSYNC_TARGET" ]]; then
        log "No USB target configured. Skipping secondary copy."
        return 0
    fi

    if mountpoint -q "$USB_MOUNT"; then
        log "USB already mounted at ${USB_MOUNT}."
    else
        log "Mounting USB at ${USB_MOUNT}..."
        mount "$USB_MOUNT" || die "Failed to mount USB at ${USB_MOUNT}"
    fi

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

    log "Uploading to cloud: ${CLOUD_REMOTE}..."
    rclone copy "$BORG_REPO" "${CLOUD_REMOTE}/borg_repo" --progress \
        || log "WARNING: Cloud upload failed. The backup is still available locally and on USB."
}

# =============================================================================
# Audit – SHA256 checksums of all repository objects
# =============================================================================
audit_checksum() {
    log "Generating SHA256 checksums of repository..."
    find "$BORG_REPO" -type f -exec sha256sum {} + > "$CHECKSUM_FILE"
    audit "Checksums saved to ${CHECKSUM_FILE}"
}

# =============================================================================
# Prometheus metrics
# =============================================================================
push_metrics() {
    [[ "$METRICS_ENABLED" != "yes" ]] && return 0

    local last_archive
    last_archive=$(borg list --short --last 1 "$BORG_REPO" 2>/dev/null || echo "none")

    mkdir -p "$(dirname "$PROMETHEUS_FILE")"
    cat > "$PROMETHEUS_FILE" << EOF
# HELP ukwinika_backup_last_success_seconds Unix timestamp of the last successful backup
# TYPE ukwinika_backup_last_success_seconds gauge
ukwinika_backup_last_success_seconds $(date +%s)
# HELP ukwinika_backup_latest_archive Label carrying the name of the most recent archive
# TYPE ukwinika_backup_latest_archive gauge
ukwinika_backup_latest_archive{name="${last_archive}"} 1
EOF
    log "Prometheus metrics written to ${PROMETHEUS_FILE}"
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
    log "Starting real-time monitoring (inotify) on: ${REAL_TIME_DIRS[*]}"
    command -v inotifywait >/dev/null 2>&1 \
        || die "inotify-tools not installed. Run: sudo make install"

    while true; do
        inotifywait -r -e modify,create,delete \
            "${REAL_TIME_DIRS[@]}" 2>/dev/null || true
        log "Change detected – triggering backup in child process."
        flock -u 200 2>/dev/null || true
        "$0" backup
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
    ( cd "$target" && borg extract "${BORG_REPO}::${archive}" ) \
        || die "borg extract failed"
    log "Restore completed successfully to ${target}"
}

# =============================================================================
# Convenience wrappers
# =============================================================================
list_archives() {
    borg list "$BORG_REPO" || die "Cannot list archives"
}

check_repo() {
    borg check "$BORG_REPO" || die "Repository check failed"
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
    log "=== Starting UKwinika Enhanced Backup ==="
    run_hook "$PRE_HOOK"
    local dump_path
    dump_path=$(db_dump)
    borg_backup "$dump_path"
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
case "${1:-}" in
    backup)
        ensure_repo_exists || die "Repository missing or invalid"
        run_backup
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
        borg init --encryption=repokey "$BORG_REPO" \
            || die "borg init failed"
        log "Repository initialised successfully at ${BORG_REPO}."
        ;;
    *)
        echo "Usage: $0 {backup|restore <archive> [target]|list|check|real-time|init}"
        exit 1
        ;;
esac
