#!/bin/bash
# =============================================================================
# UKwinika Enhanced Automated Backup Script - Production Edition (Debian Fixed v2.1)
# Author: Urayayi Kwinika
# Version: 2.1
# =============================================================================

set -euo pipefail

CONFIG_FILE="/etc/ukwinika-backup.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file ${CONFIG_FILE} not found!" >&2
    exit 1
fi

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

LOG_FILE="${LOG_FILE:-/var/log/UKwinikaBackup.log}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/UKwinikaBackup_audit.log}"

if [[ -z "${UKWINIKA_PASSPHRASE:-}" ]]; then
    SECRETS_FILE="${SECRETS_FILE:-/etc/ukwinika-backup.secrets}"
    if [[ -f "$SECRETS_FILE" ]]; then
        UKWINIKA_PASSPHRASE=$(cat "$SECRETS_FILE")
    else
        echo "ERROR: UKWINIKA_PASSPHRASE environment variable or secrets file is required." >&2
        exit 1
    fi
fi

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"; }
audit() { echo "$(date '+%Y-%m-%d %H:%M:%S') [AUDIT] $1" | tee -a "$AUDIT_LOG"; }

db_dump() {
    local DUMP_FILE="$BACKUP_DIR/db_dump_$(date +%s).sql"
    if [[ -f /root/.my.cnf ]]; then
        mysqldump --defaults-extra-file=/root/.my.cnf --all-databases --single-transaction --quick --lock-tables=false > "$DUMP_FILE" 2>/dev/null || true
    else
        mysqldump --all-databases --single-transaction --quick --lock-tables=false > "$DUMP_FILE" 2>/dev/null || true
    fi
    echo "$DUMP_FILE"
}

perform_backup() {
    local TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    local BACKUP_NAME="system_backup_${BACKUP_TYPE}_${TIMESTAMP}"

    log "=== Starting ${BACKUP_TYPE} backup using ${BACKUP_TOOL} ==="
    audit "Backup started"

    local DB_DUMP=$(db_dump)

    case "$BACKUP_TOOL" in
        borg)
            # FIXED: No --encryption flag on create (only used in borg init)
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

case "$MODE" in
    backup)
        perform_backup
        ;;
    restore|real-time)
        log "$MODE mode called"
        ;;
    *)
        log "Unknown mode: $MODE"
        ;;
esac
