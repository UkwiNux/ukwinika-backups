#!/usr/bin/env bash
# clean-tmp.sh – Remove stale files from /tmp
set -euo pipefail

JOB_NAME="clean-tmp"
LOG_FILE="/var/log/monsun_cron/${JOB_NAME}.log"
CONF_FILE="$(dirname "$0")/../conf/${JOB_NAME}.conf"
LOCK_FILE="/var/lock/${JOB_NAME}.lock"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another instance running – exiting."; exit 0; }

log "Starting ${JOB_NAME}..."
# -----------------------------------------------------------------
# Example: delete files in /tmp older than 3 days
find /tmp -type f -atime +3 -delete 2>>"$LOG_FILE"
# -----------------------------------------------------------------
log "Finished ${JOB_NAME}."
