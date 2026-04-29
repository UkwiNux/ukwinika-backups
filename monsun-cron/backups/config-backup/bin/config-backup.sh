#!/usr/bin/env bash
# config-backup.sh – Compress critical configuration directories
set -euo pipefail

JOB_NAME="config-backup"
LOG_FILE="/var/log/monsun_cron/${JOB_NAME}.log"
CONF_FILE="$(dirname "$0")/../conf/${JOB_NAME}.conf"
LOCK_FILE="/var/lock/${JOB_NAME}.lock"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another instance running – exiting."; exit 0; }

log "Starting ${JOB_NAME}..."
BACKUP_DIR="/backup/config_backups"
mkdir -p "$BACKUP_DIR"
tar czf "${BACKUP_DIR}/config_$(date +%Y%m%d).tar.gz" /etc/nginx /etc/docker /etc/haproxy 2>/dev/null || true
log "Finished ${JOB_NAME}."
