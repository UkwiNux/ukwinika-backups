#!/usr/bin/env bash
# certbot-renew.sh – Renew Let's Encrypt certificates
set -euo pipefail

JOB_NAME="certbot-renew"
LOG_FILE="/var/log/monsun_cron/${JOB_NAME}.log"
CONF_FILE="$(dirname "$0")/../conf/${JOB_NAME}.conf"
LOCK_FILE="/var/lock/${JOB_NAME}.lock"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
flock -n 9 || { log "Another instance running – exiting."; exit 0; }

log "Starting ${JOB_NAME}..."
/usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'
log "Finished ${JOB_NAME}."
