#!/usr/bin/env bash
# db-backup.sh – Nightly database dump (MySQL example)
set -euo pipefail

JOB_NAME="db-backup"
LOG_FILE="/var/log/monsun_cron/${JOB_NAME}.log"
CONF_FILE="$(dirname "$0")/../conf/${JOB_NAME}.conf"
LOCK_FILE="/var/lock/${JOB_NAME}.lock"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another instance running – exiting."; exit 0; }

log "Starting ${JOB_NAME}..."
BACKUP_DIR="/backup/db"
mkdir -p "$BACKUP_DIR"
mysqldump --all-databases | gzip > "${BACKUP_DIR}/db_$(date +%Y%m%d).sql.gz"
log "Finished ${JOB_NAME}."
