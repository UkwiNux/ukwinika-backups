#!/usr/bin/env bash
# offsite-replication.sh – Sync backups to off‑site storage (AWS S3)
set -euo pipefail

JOB_NAME="offsite-replication"
LOG_FILE="/var/log/monsun_cron/${JOB_NAME}.log"
CONF_FILE="$(dirname "$0")/../conf/${JOB_NAME}.conf"
LOCK_FILE="/var/lock/${JOB_NAME}.lock"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another instance running – exiting."; exit 0; }

log "Starting ${JOB_NAME}..."
# Replace with your actual S3 bucket
aws s3 sync /backup/ s3://your-bucket/backups/
log "Finished ${JOB_NAME}."
