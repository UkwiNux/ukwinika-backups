#!/usr/bin/env bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script – Smart Idempotent Edition
# Version: 3.1
# Author: Urayayi Kwinika (refined per security & idempotency audit)
# Description:
#   - Fully idempotent 3‑2‑1 backup (Borg → USB → Cloud)
#   - Safe restore with dedicated target directory
#   - Stale‑lock prevention via cleanup trap
#   - Secrets separated from configuration
#   - Strict DB type validation
#   - Consistent variable naming & single source of excludes
#   - Repository auto‑check and initialisation support
# Usage:
#   backup                 Run full backup cycle
#   restore <archive> [target]  Restore archive to target (default /tmp/restore_<archive>)
#   list                   List archives
#   check                  Verify repository integrity
#   real-time              Monitor directories and backup on changes
#   init                   Initialise a new Borg repository
# =============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOCK_FILE="/var/lock/ukwinika-backup.lock"
LOG_FILE="/var/log/UKwinikaBackup.log"
AUDIT_LOG="/var/log/UKwinikaBackup_audit.log"
PROMETHEUS_FILE="/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom"

UKW_CONFIG="${UKW_CONFIG:-/etc/ukwinika-backup.conf}"
UKW_SECRETS="${UKW_SECRETS:-/etc/ukwinika-backup.secrets}"

if [[ ! -f "$UKW_CONFIG" ]]; then
    echo "ERROR: Configuration file ${UKW_CONFIG} not found!" >&2
    exit 1
fi
source "$UKW_CONFIG"

if [[ -f "$UKW_SECRETS" ]]; then
    source "$UKW_SECRETS"
fi

BORG_PASSPHRASE="${BORG_PASSPHRASE:?}"
export BORG_PASSPHRASE

BORG_REPO="${BORG_REPO:-/var/backups/borg-repo}"
BACKUP_PATHS=("${BACKUP_PATHS[@]:-/}")
EXCLUDE_DIRS=("${EXCLUDE_DIRS[@]:-/proc /sys /dev /tmp /run /mnt /media /lost+found}")

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

log()   { echo "$(date '+%F %T') $SCRIPT_NAME: $*" | tee -a "$LOG_FILE"; }
audit() {
    echo "$(date '+%F %T') [AUDIT] $1" | tee -a "$AUDIT_LOG"
    [[ -n "${2:-}" && -f "$2" ]] && sha256sum "$2" >> "$AUDIT_LOG" || true
}
die()  { log "FATAL: $*"; exit 1; }

# ---- Locking ----
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another Backup instance is already running. Exiting."
    exit 0
fi
cleanup_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE"
}
trap cleanup_lock EXIT INT TERM

run_hook() {
    local hook="$1"
    if [[ -n "$hook" && -x "$hook" ]]; then
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
    fi
}

db_dump() {
    local dump_dir="/tmp/ukwinika-db-dump"
    rm -rf "$dump_dir"
    mkdir -p "$dump_dir"
    case "$DB_TYPE" in
        none) return 0 ;;
        mysql)
            log "Dumping all MySQL Databases..."
            mysqldump --all-databases --single-transaction --quick --lock-tables=false \
                > "$dump_dir/mysql-all.sql" || die "MySQL dump failed"
            ;;
        postgresql)
            log "Dumping all PostgreSQL Databases..."
            sudo -u postgres pg_dumpall > "$dump_dir/postgresql-all.sql" \
                || die "PostgreSQL dump failed"
            ;;
        mongodb)
            log "Dumping MongoDB..."
            mongodump --out "$dump_dir/mongo" || die "MongoDB dump failed"
            ;;
        *)
            die "Unsupported DB_TYPE='$DB_TYPE'. Aborting for Data Safety."
            ;;
    esac
    echo "$dump_dir"
}

borg_backup() {
    local dump_path="$1"
    local timestamp; timestamp=$(date '+%Y-%m-%d_%H:%M:%S')
    local archive_name="${HOSTNAME:-$(hostname)}-${timestamp}"

    local exclude_args=()
    for dir in "${EXCLUDE_DIRS[@]}"; do
        exclude_args+=(--exclude "$dir")
    done

    log "Creating Borg archive '$archive_name'..."
    borg create                          \
        --verbose                        \
        --filter AME                     \
        --list                           \
        --stats                          \
        --show-rc                        \
        --compression lz4                \
        --exclude-caches                 \
        "${exclude_args[@]}"             \
        "$BORG_REPO"::"$archive_name"    \
        "${BACKUP_PATHS[@]}"             \
        ${dump_path:+"$dump_path"}       || die "Borg create failed"

    log "Pruning old archives (keep-within ${RETENTION_DAYS}d, keep-daily ${RETENTION_DAYS}, keep-last ${RETENTION_VERSIONS})..."
    borg prune                         \
        --list                          \
        --show-rc                       \
        --keep-within "${RETENTION_DAYS}d" \
        --keep-daily "$RETENTION_DAYS"  \
        --keep-last "$RETENTION_VERSIONS" \
        "$BORG_REPO"                    || die "Borg Prune failed"
}

sync_to_usb() {
    [[ -z "$USB_RSYNC_TARGET" ]] && { log "No USB target configured. Skipping."; return 0; }
    if mountpoint -q "$USB_MOUNT"; then
        log "USB already mounted at $USB_MOUNT"
    else
        log "Mounting USB..."
        mount "$USB_MOUNT" || die "Failed to mount USB"
    fi
    log "Syncing Borg repository to USB (rsync -a --delete)..."
    rsync -a --delete "$BORG_REPO"/ "$USB_RSYNC_TARGET"/ || die "USB rsync failed"
    sync
    umount "$USB_MOUNT" || log "Warning: could not unmount USB"
}

cloud_upload() {
    if [[ -n "$CLOUD_REMOTE" ]] && command -v rclone >/dev/null; then
        log "Uploading to cloud: $CLOUD_REMOTE"
        rclone copy "$BORG_REPO" "${CLOUD_REMOTE}/borg_repo" --progress || log "WARNING: Cloud upload failed"
    fi
}

audit_checksum() {
    log "Generating SHA256 checksums of repository..."
    find "$BORG_REPO" -type f -exec sha256sum {} + > /tmp/ukwinika-backup-checksums.txt
    audit "Checksums saved to /tmp/ukwinika-backup-checksums.txt"
}

push_metrics() {
    [[ "$METRICS_ENABLED" != "yes" ]] && return 0
    local last_archive; last_archive=$(borg list --short --last 1 "$BORG_REPO" 2>/dev/null || echo "none")
    cat > "$PROMETHEUS_FILE" <<EOF
# HELP ukwinika_backup_last_success_seconds Time of last successful backup
# TYPE ukwinika_backup_last_success_seconds gauge
ukwinika_backup_last_success_seconds $(date +%s)
# HELP ukwinika_backup_latest_archive Latest archive name
# TYPE ukwinika_backup_latest_archive gauge
ukwinika_backup_latest_archive{name="$last_archive"} 1
EOF
    log "Prometheus Metrics written to $PROMETHEUS_FILE"
}

notify() {
    local status="$1"
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' --data \
            "{\"text\":\"Backup ${status} on $(hostname)\"}" "$SLACK_WEBHOOK" || true
    fi
    if [[ -n "$EMAIL_TO" ]]; then
        echo "Backup ${status}" | mail -s "Backup ${status}" "$EMAIL_TO" || true
    fi
}

real_time_mode() {
    log "Starting Real-Time Monitoring (inotify)"
    command -v inotifywait >/dev/null || die "inotify-tools not installed"
    while true; do
        inotifywait -r -e modify,create,delete "${REAL_TIME_DIRS[@]}" 2>/dev/null || true
        log "Change detected – triggering Incremental Backup"
        run_backup
    done
}

restore_backup() {
    local archive="$1"
    local target="${2:-/tmp/restore_$archive}"
    log "Restoring Archive '$archive' to '$target'..."
    mkdir -p "$target"
    borg extract "$BORG_REPO"::"$archive" --target "$target" || die "Restore failed"
    log "Restore Completed successfully to $target"
}

list_archives() {
    borg list "$BORG_REPO" || die "Cannot list archives"
}

check_repo() {
    borg check "$BORG_REPO" || die "Repository check failed"
}

run_backup() {
    log "=== Starting Enhanced Backup ==="
    run_hook "$PRE_HOOK"
    local dump_path; dump_path=$(db_dump)
    borg_backup "$dump_path"
    sync_to_usb
    cloud_upload
    audit_checksum
    push_metrics
    notify "SUCCESS"
    run_hook "$POST_HOOK"
    log "=== Backup Completed ==="
}

# ===================== Repository check ===================================
ensure_repo_exists() {
    if [[ ! -d "$BORG_REPO" ]]; then
        log "ERROR: Borg Repository $BORG_REPO does not exist."
        echo "Run: sudo $0 init" >&2
        return 1
    fi
    # Quick sanity check that it is a Borg repo
    if ! borg check --info "$BORG_REPO" >/dev/null 2>&1; then
        log "ERROR: $BORG_REPO is not a valid Borg Repository or is corrupted."
        return 1
    fi
    return 0
}

# ===================== CLI dispatch =======================================
case "${1:-}" in
    backup)    ensure_repo_exists || die "Repository missing or invalid"
               run_backup ;;
    restore)   ensure_repo_exists || die "Repository missing or invalid"
               restore_backup "${2:?Archive name required}" "${3:-}" ;;
    list)      ensure_repo_exists || die "Repository missing or invalid"
               list_archives ;;
    check)     ensure_repo_exists || die "Repository missing or invalid"
               check_repo ;;
    real-time) ensure_repo_exists || die "Repository missing or invalid"
               real_time_mode ;;
    init)
        if [[ -d "$BORG_REPO" ]] && borg check --info "$BORG_REPO" >/dev/null 2>&1; then
            log "Repository already exists at $BORG_REPO – nothing to initialise."
            exit 0
        fi
        log "Initialising new Borg Repository at $BORG_REPO"
        mkdir -p "$(dirname "$BORG_REPO")"
        borg init --encryption=repokey "$BORG_REPO" || die "Borg init failed"
        log "Repository initialised successfully."
        ;;
    *)
        echo "Usage: $0 {backup|restore <archive> [target]|list|check|real-time|init}"
        exit 1
        ;;
esac
