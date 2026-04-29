#!/usr/bin/env bash
# rotate-logs.sh – Trigger logrotate manually
set -euo pipefail

JOB_NAME="rotate-logs"
LOG_FILE="/var/log/monsun_cron/${JOB_NAME}.log"
CONF_FILE="$(dirname "$0")/../conf/${JOB_NAME}.conf"
LOCK_FILE="/var/lock/${JOB_NAME}.lock"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another instance running – exiting."; exit 0; }

log "Starting ${JOB_NAME}..."
/usr/sbin/logrotate /etc/logrotate.conf
log "Finished ${JOB_NAME}."
