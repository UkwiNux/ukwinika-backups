#!/usr/bin/env bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script – Smart Idempotent Edition
# Version: 3.0
# Author: Urayayi Kwinika (refined per security & idempotency audit)
# Description:
#   - Fully idempotent 3‑2‑1 backup (Borg → USB → Cloud)
#   - Safe restore with dedicated target directory
#   - Stale‑lock prevention via cleanup trap
#   - Secrets separated from configuration
#   - Strict DB type validation
#   - Consistent variable naming & single source of excludes
# Usage:
#   backup                 Run full backup cycle
#   restore <archive> [target]  Restore archive to target (default /tmp/restore_<archive>)
#   list                   List archives
#   check                  Verify repository integrity
#   real-time              Monitor directories and backup on changes
# =============================================================================
set -euo pipefail

# ===================== Early defaults (overridden by config) ===============
SCRIPT_NAME="$(basename "$0")"
LOCK_FILE="/var/lock/ukwinika-backup.lock"
LOG_FILE="/var/log/UKwinikaBackup.log"
AUDIT_LOG="/var/log/UKwinikaBackup_audit.log"
PROMETHEUS_FILE="/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom"

# ===================== Configuration loading ===============================
# Allow overriding config location via environment variable
UKW_CONFIG="${UKW_CONFIG:-/etc/ukwinika-backup.conf}"
UKW_SECRETS="${UKW_SECRETS:-/etc/ukwinika-backup.secrets}"

if [[ ! -f "$UKW_CONFIG" ]]; then
    echo "ERROR: Configuration file ${UKW_CONFIG} not found!" >&2
    exit 1
fi
# shellcheck source=/etc/ukwinika-backup.conf
source "$UKW_CONFIG"

# Load secrets (must be mode 0600) – overrides any matching variable
if [[ -f "$UKW_SECRETS" ]]; then
    # shellcheck source=/etc/ukwinika-backup.secrets
    source "$UKW_SECRETS"
fi

# ===================== Mandatory secrets ===================================
BORG_PASSPHRASE="${BORG_PASSPHRASE:?}"
export BORG_PASSPHRASE

# ===================== Settings with safe defaults =========================
# BORG_REPO is the root of the Borg repository (primary copy)
BORG_REPO="${BORG_REPO:-/var/backups/borg-repo}"

# Paths to include (default: entire filesystem)
# Can be overridden in config as an array, e.g.: BACKUP_PATHS=("/etc" "/home")
BACKUP_PATHS=("${BACKUP_PATHS[@]:-/}")

# Exclude patterns (array) – defined ONLY here from config
EXCLUDE_DIRS=("${EXCLUDE_DIRS[@]:-/proc /sys /dev /tmp /run /mnt /media /lost+found}")

# Retention policies
RETENTION_DAYS="${RETENTION_DAYS:-90}"                # keep archives within this many days
RETENTION_VERSIONS="${RETENTION_VERSIONS:-5}"         # also keep at least N latest archives

# USB off‑site copy
USB_MOUNT="${USB_MOUNT:-/mnt/backup_usb}"
USB_RSYNC_TARGET="${USB_RSYNC_TARGET:-}"             # destination path on the mounted USB

# Cloud (rclone)
CLOUD_REMOTE="${CLOUD_REMOTE:-}"

# Database dump type
DB_TYPE="${DB_TYPE:-none}"                           # none | mysql | postgresql | mongodb

# Hooks
PRE_HOOK="${PRE_HOOK:-}"
POST_HOOK="${POST_HOOK:-}"
HOOK_FAIL_ACTION="${HOOK_FAIL_ACTION:-fatal}"        # fatal or warn

# Real‑time monitoring directories
REAL_TIME_DIRS=("${REAL_TIME_DIRS[@]:-/etc /home}")

# Notifications (no secrets in config – overridden by secrets file)
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_TO="${EMAIL_TO:-}"

# Prometheus
METRICS_ENABLED="${METRICS_ENABLED:-yes}"

# ===================== Logging & helpers ===================================
log()   { echo "$(date '+%F %T') $SCRIPT_NAME: $*" | tee -a "$LOG_FILE"; }
audit() {
    echo "$(date '+%F %T') [AUDIT] $1" | tee -a "$AUDIT_LOG"
    # If a file is passed as second argument, append its SHA256 sum
    [[ -n "${2:-}" && -f "$2" ]] && sha256sum "$2" >> "$AUDIT_LOG" || true
}
die()  { log "FATAL: $*"; exit 1; }

# ===================== Idempotent lock with cleanup trap ===================
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another Backup Instance is already running. Exiting."
    exit 0
fi
# Remove lock file on any exit – prevents stale locks
cleanup_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE"
}
trap cleanup_lock EXIT INT TERM

# ===================== Hook runner =========================================
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

# ===================== Database dump (idempotent) ==========================
db_dump() {
    local dump_dir="/tmp/ukwinika-db-dump"
    rm -rf "$dump_dir"                # always start fresh
    mkdir -p "$dump_dir"

    case "$DB_TYPE" in
        none)     return 0 ;;         # no database to dump
        mysql)
            log "Dumping all MySQL databases..."
            mysqldump --all-databases --single-transaction --quick --lock-tables=false \
                > "$dump_dir/mysql-all.sql" || die "MySQL dump failed"
            ;;
        postgresql)
            log "Dumping all PostgreSQL databases..."
            sudo -u postgres pg_dumpall > "$dump_dir/postgresql-all.sql" \
                || die "PostgreSQL dump failed"
            ;;
        mongodb)
            log "Dumping MongoDB..."
            mongodump --out "$dump_dir/mongo" || die "MongoDB dump failed"
            ;;
        *)
            # Unknown DB_TYPE – abort to prevent silent data loss
            die "Unsupported DB_TYPE='$DB_TYPE'. Aborting for data safety."
            ;;
    esac
    echo "$dump_dir"
}

# ===================== Borg backup (idempotent, deduplicated) ==============
borg_backup() {
    local dump_path="$1"
    local timestamp; timestamp=$(date '+%Y-%m-%d_%H:%M:%S')
    local archive_name="${HOSTNAME:-$(hostname)}-${timestamp}"

    # Build exclusion arguments from the array
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
        "$BORG_REPO"                    || die "Borg prune failed"
}

# ===================== USB rsync (idempotent mirror) =======================
sync_to_usb() {
    [[ -z "$USB_RSYNC_TARGET" ]] && { log "No USB target configured. Skipping."; return 0; }

    # Mount if needed
    if mountpoint -q "$USB_MOUNT"; then
        log "USB already mounted at $USB_MOUNT"
    else
        log "Mounting USB..."
        mount "$USB_MOUNT" || die "Failed to mount USB"
    fi

    log "Syncing Borg Repository to USB (rsync -a --delete)..."
    rsync -a --delete "$BORG_REPO"/ "$USB_RSYNC_TARGET"/ || die "USB rsync failed"
    sync
    umount "$USB_MOUNT" || log "Warning: could not unmount USB"
}

# ===================== Cloud upload (rclone) ===============================
cloud_upload() {
    if [[ -n "$CLOUD_REMOTE" ]] && command -v rclone >/dev/null; then
        log "Uploading to cloud: $CLOUD_REMOTE"
        rclone copy "$BORG_REPO" "${CLOUD_REMOTE}/borg_repo" --progress || log "WARNING: Cloud Upload failed"
    fi
}

# ===================== Audit checksum ======================================
audit_checksum() {
    log "Generating SHA256 checksums of repository..."
    find "$BORG_REPO" -type f -exec sha256sum {} + > /tmp/ukwinika-backup-checksums.txt
    audit "Checksums saved to /tmp/ukwinika-backup-checksums.txt"
}

# ===================== Prometheus metrics ==================================
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
    log "Prometheus metrics written to $PROMETHEUS_FILE"
}

# ===================== Notifications =======================================
notify() {
    local status="$1"
    # Slack
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' --data \
            "{\"text\":\"Backup ${status} on $(hostname)\"}" "$SLACK_WEBHOOK" || true
    fi
    # Email
    if [[ -n "$EMAIL_TO" ]]; then
        echo "Backup ${status}" | mail -s "Backup ${status}" "$EMAIL_TO" || true
    fi
}

# ===================== Real‑time monitoring ================================
real_time_mode() {
    log "Starting Real-Time Monitoring (inotify)"
    command -v inotifywait >/dev/null || die "inotify-tools not installed"
    while true; do
        inotifywait -r -e modify,create,delete "${REAL_TIME_DIRS[@]}" 2>/dev/null || true
        log "Change detected – triggering incremental backup"
        run_backup
    done
}

# ===================== Restore (fully idempotent) ==========================
restore_backup() {
    local archive="$1"
    local target="${2:-/tmp/restore_$archive}"

    log "Restoring archive '$archive' to '$target'..."
    mkdir -p "$target"
    # borg extract with --target ensures idempotent, repeatable extraction
    borg extract "$BORG_REPO"::"$archive" --target "$target" || die "Restore failed"
    log "Restore Completed successfully to $target"
}

list_archives() {
    borg list "$BORG_REPO" || die "Cannot list archives"
}

check_repo() {
    borg check "$BORG_REPO" || die "Repository Check failed"
}

# ===================== Main backup workflow ================================
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
    log "=== Backup Completed!!! ==="
}

# ===================== CLI dispatch ========================================
case "${1:-}" in
    backup)    run_backup ;;
    restore)   restore_backup "${2:?Archive name required}" "${3:-}" ;;
    list)      list_archives ;;
    check)     check_repo ;;
    real-time) real_time_mode ;;
    *)
        echo "Usage: $0 {backup|restore <archive> [target]|list|check|real-time}"
        exit 1
        ;;
esac
