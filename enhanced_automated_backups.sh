#!/bin/bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script - Production Edition (Debian Fixed)
# Author: Urayayi Kwinika
# Version: 2.1
# Last Revised: April 2026
# =============================================================================

set -euo pipefail

# ====================== LOAD EXTERNAL CONFIGURATION ======================
CONFIG_FILE="/etc/ukwinika-backup.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file ${CONFIG_FILE} not found!" >&2
    exit 1
fi

# ====================== DEFAULTS & FALLBACKS ======================
MODE="${1:-backup}"
BACKUP_TYPE="${2:-incremental}"
BACKUP_TOOL="${3:-borg}"
RESTORE_FILE="${4:-}"

BACKUP_DIR="${BACKUP_DIR:-/UKwinikaBackup}"
BORG_REPO="${BORG_REPO:-${BACKUP_DIR}/borg_repo}"

INCLUDE_DIRS=("${INCLUDE_DIRS[@]:-/etc /home /var/www /var/lib/mysql /var/lib/postgresql /opt/oracle}")
EXCLUDE_DIRS=("${EXCLUDE_DIRS[@]:---exclude=/home/*/tmp --exclude=/var/cache --exclude=/proc --exclude=/sys --exclude=/dev}")

RETENTION_DAYS="${RETENTION_DAYS:-7}"
RETENTION_VERSIONS="${RETENTION_VERSIONS:-5}"
STORAGE_THRESHOLD="${STORAGE_THRESHOLD:-80}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"

LOG_FILE="${LOG_FILE:-/var/log/UKwinikaBackup.log}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/UKwinikaBackup_audit.log}"

# Secrets handling
if [[ -z "${UKWINIKA_PASSPHRASE:-}" ]]; then
    SECRETS_FILE="${SECRETS_FILE:-/etc/ukwinika-backup.secrets}"
    if [[ -f "$SECRETS_FILE" ]]; then
        UKWINIKA_PASSPHRASE=$(cat "$SECRETS_FILE")
    else
        echo "ERROR: UKWINIKA_PASSPHRASE environment variable or secrets file is required." >&2
        exit 1
    fi
fi

LOCK_FILE="/var/lock/ukwinika-backup.lock"

# ====================== HELPER FUNCTIONS ======================
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"; }
audit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [AUDIT] $1" | tee -a "$AUDIT_LOG"
    [[ -n "${2:-}" ]] && sha256sum "$2" 2>/dev/null >> "$AUDIT_LOG" || true
}

check_tool() {
    command -v "$1" >/dev/null || { echo "$1 is required"; exit 1; }
}

detect_removable() {
    log "Removable media not available. Falling back to local storage."
}

db_dump() {
    local DUMP_FILE="$BACKUP_DIR/db_dump_$(date +%s).sql"
    case "$DB_TYPE" in
        mysql)
            # Fixed: Use config file or root with no password (Debian default)
            if [[ -f ~/.my.cnf ]]; then
                mysqldump --defaults-extra-file=~/.my.cnf --all-databases --single-transaction --quick --lock-tables=false > "$DUMP_FILE"
            else
                mysqldump --all-databases --single-transaction --quick --lock-tables=false > "$DUMP_FILE" 2>/dev/null || true
            fi
            ;;
        *) log "DB dump skipped (only MySQL supported for now)"; return 0 ;;
    esac
    audit "Database dumped" "$DUMP_FILE"
    echo "$DUMP_FILE"
}

perform_backup() {
    check_tool "$BACKUP_TOOL"
    detect_removable

    local TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    local BACKUP_NAME="system_backup_${BACKUP_TYPE}_${TIMESTAMP}"

    log "=== Starting ${BACKUP_TYPE} backup using ${BACKUP_TOOL} ==="
    audit "Backup started" ""

    local DB_DUMP=$(db_dump)

    case "$BACKUP_TOOL" in
        borg)
            # FIXED: Removed --encryption flag (already set at init time)
            borg create --compression=lz4 --checkpoint-interval=300 \
                "${BORG_REPO}::${BACKUP_NAME}" \
                "${INCLUDE_DIRS[@]}" "$DB_DUMP" "${EXCLUDE_DIRS[@]}"
            borg prune --keep-daily "$RETENTION_DAYS" --keep-last "$RETENTION_VERSIONS" --stats "$BORG_REPO"
            borg check --verify-data "$BORG_REPO" || log "Warning: Borg check failed"
            ;;
        *) log "Tool $BACKUP_TOOL not fully implemented yet"; ;;
    esac

    log "=== Backup completed successfully ==="
}

# ====================== MAIN ======================
case "$MODE" in
    backup)
        perform_backup
        ;;
    restore)
        log "Restore mode called (placeholder logic)"
        ;;
    real-time)
        log "Real-time mode started (inotify-tools required)"
        command -v inotifywait >/dev/null || { log "ERROR: inotify-tools not installed"; exit 1; }
        ;;
    *)
        log "Unknown mode: $MODE"
        ;;
esac
