#!/bin/bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script
# Version: 2.4
# Author: Urayayi Kwinika
# Last Updated: April 2026
# Description: Full 3-2-1 backup (Primary on system, Secondary on USB, Tertiary on cloud)
# =============================================================================

set -euo pipefail

# ====================== LOAD CONFIG ======================
CONFIG_FILE="/etc/ukwinika-backup.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file ${CONFIG_FILE} not found!" >&2
    exit 1
fi

# ====================== DEFAULTS ======================
MODE="${1:-backup}"
BACKUP_TYPE="${2:-incremental}"
BACKUP_TOOL="${3:-borg}"
RESTORE_FILE="${4:-}"

PRIMARY_BORG_REPO="/UKwinikaBackup/borg_repo"

INCLUDE_DIRS=("${INCLUDE_DIRS[@]:-/etc /home /var/www /var/lib/mysql /var/lib/postgresql /opt/oracle}")
EXCLUDE_DIRS=("${EXCLUDE_DIRS[@]:---exclude=/home/*/tmp --exclude=/var/cache --exclude=/proc --exclude=/sys --exclude=/dev}")

RETENTION_DAYS="${RETENTION_DAYS:-7}"
RETENTION_VERSIONS="${RETENTION_VERSIONS:-5}"

LOG_FILE="${LOG_FILE:-/var/log/UKwinikaBackup.log}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/UKwinikaBackup_audit.log}"
PROMETHEUS_FILE="${PROMETHEUS_FILE:-/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom}"
LOCK_FILE="/var/lock/ukwinika-backup.lock"

# Passphrase
if [[ -z "${UKWINIKA_PASSPHRASE:-}" ]]; then
    SECRETS_FILE="${SECRETS_FILE:-/etc/ukwinika-backup.secrets}"
    if [[ -f "$SECRETS_FILE" ]]; then
        UKWINIKA_PASSPHRASE=$(cat "$SECRETS_FILE")
    else
        echo "ERROR: UKWINIKA_PASSPHRASE or secrets file is required." >&2
        exit 1
    fi
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"; }
audit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [AUDIT] $1" | tee -a "$AUDIT_LOG"
    [[ -n "${2:-}" ]] && sha256sum "$2" 2>/dev/null >> "$AUDIT_LOG" || true
}

prometheus_metric() {
    echo "ukwinika_backup{status=\"$1\",tool=\"$BACKUP_TOOL\",mode=\"$MODE\"} $(date +%s)" > "$PROMETHEUS_FILE"
}

acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "ERROR: Another backup is already running"
        exit 1
    fi
}

detect_removable_media() {
    if lsblk -o NAME,RM | grep -q "1"; then
        log "Removable media detected → Secondary copy to USB"
        REMOVABLE_PATH="${REMOVABLE_MOUNT:-/media/usb}"
        mkdir -p "$REMOVABLE_PATH"
        return 0
    fi
    return 1
}

upload_to_cloud() {
    if [[ -n "${CLOUD_REMOTE:-}" ]] && command -v rclone >/dev/null; then
        log "Uploading to cloud: ${CLOUD_REMOTE}"
        rclone copy "${PRIMARY_BORG_REPO}" "${CLOUD_REMOTE}/borg_repo" --progress || true
    fi
}

run_hook() {
    local hook="$1"
    if [[ -x "$hook" ]]; then
        log "Running hook: $hook"
        "$hook" || log "Warning: Hook failed"
    fi
}

db_dump() {
    local DUMP_FILE="$BACKUP_DIR/db_dump_$(date +%s).sql"
    local DB_TYPE="${DB_TYPE:-mysql}"

    case "$DB_TYPE" in
        mysql)
            if [[ -f /root/.my.cnf ]]; then
                mysqldump --defaults-extra-file=/root/.my.cnf --all-databases --single-transaction --quick --lock-tables=false > "$DUMP_FILE" 2>/dev/null || true
            else
                mysqldump --all-databases --single-transaction --quick --lock-tables=false > "$DUMP_FILE" 2>/dev/null || true
            fi
            ;;
        postgresql)
            pg_dumpall --clean --if-exists > "$DUMP_FILE" 2>/dev/null || true
            ;;
        oracle)
            log "Oracle DB dump not fully implemented yet"
            ;;
        *)
            log "Unknown DB_TYPE: $DB_TYPE – skipping DB dump"
            ;;
    esac
    audit "Database dumped" "$DUMP_FILE"
    echo "$DUMP_FILE"
}

# ====================== MAIN BACKUP (3-2-1) ======================
perform_backup() {
    acquire_lock

    local TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    local BACKUP_NAME="system_backup_${BACKUP_TYPE}_${TIMESTAMP}"

    log "=== Starting ${BACKUP_TYPE} backup using ${BACKUP_TOOL} (Primary on system) ==="
    audit "Backup started"

    run_hook "/etc/ukwinika/pre_backup_hook.sh"

    local DB_DUMP=$(db_dump)

    # PRIMARY BACKUP - System disk
    borg create --compression=lz4 --checkpoint-interval=300 \
        --max-lock-wait 300 --progress \
        "${PRIMARY_BORG_REPO}::${BACKUP_NAME}" \
        "${INCLUDE_DIRS[@]}" "$DB_DUMP" "${EXCLUDE_DIRS[@]}"

    borg prune --keep-daily "$RETENTION_DAYS" --keep-last "$RETENTION_VERSIONS" --stats "${PRIMARY_BORG_REPO}"

    log "Primary backup completed on system disk"

    # SECONDARY - USB
    if detect_removable_media; then
        log "Creating secondary copy on removable media"
        rsync -a --info=progress2 "${PRIMARY_BORG_REPO}" "${REMOVABLE_PATH}/" || log "Warning: USB copy failed"
    fi

    # TERTIARY - Cloud
    upload_to_cloud

    run_hook "/etc/ukwinika/post_backup_hook.sh"
    prometheus_metric "success"

    log "=== 3-2-1 backup completed successfully ==="
}

# Real-time and Restore modes (unchanged from v2.3)
real_time_mode() {
    log "Starting real-time monitoring (inotify)"
    command -v inotifywait >/dev/null || { log "ERROR: inotify-tools not installed"; exit 1; }
    prometheus_metric "realtime_started"
    while true; do
        inotifywait -r -e modify,create,delete "${REAL_TIME_DIRS[@]}" 2>/dev/null || true
        log "Change detected – triggering incremental backup"
        perform_backup
    done
}

restore_mode() {
    if [[ "$MODE" == "restore" && -z "$RESTORE_FILE" ]]; then
        log "ERROR: RESTORE_FILE argument is required"
        exit 1
    fi
    if [[ "${2:-}" == "drill" ]]; then
        log "=== SAFE DRILL RESTORE MODE (preview only) ==="
        sudo borg list "${PRIMARY_BORG_REPO}" | tail -n 10
    else
        log "=== FULL RESTORE STARTED ==="
        borg extract --strip-components 1 "${PRIMARY_BORG_REPO}::${RESTORE_FILE}" "${INCLUDE_DIRS[@]}"
    fi
    prometheus_metric "restore_completed"
}

# ====================== MAIN ======================
case "$MODE" in
    backup)
        perform_backup
        ;;
    real-time)
        real_time_mode
        ;;
    restore)
        restore_mode
        ;;
    *)
        log "Unknown mode: $MODE. Available: backup, real-time, restore"
        exit 1
        ;;
esac
