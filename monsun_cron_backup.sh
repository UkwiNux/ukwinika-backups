#!/usr/bin/env bash
# monsun_cron_backup.sh
# -----------------------------------------------------------------------------
# UKwinika Backup + Monsun Cron Job Manager
#
# This script does TWO things:
#   1. Installs the UKwinika Enhanced Backup Script (idempotent) as one of
#      the Monsun cron jobs (full-system-backup).
#   2. Deploys a complete, folder‑based structure for ALL critical cron jobs,
#      using the templates from the `monsun-cron/` directory in this repo.
#
# Idempotent – safe to re‑run. Must be executed as root.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---------------------------- 0. Configuration ------------------------------
REPO_BASE="https://raw.githubusercontent.com/UkwiNux/ukwinika-backups/main"
CRON_BASE="/opt/monsun-cron"               # changed from /opt/enterprise-cron
CRON_USER="root"
LOG_DIR="/var/log/monsun_cron"

CRON_MARKER_START="# BEGIN_MONSUN_CRON_JOBS"
CRON_MARKER_END="# END_MONSUN_CRON_JOBS"

# ---------------------------- Helper Functions ------------------------------
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

backup_crontab() {
    local backup_file="/root/crontab.backup.$(date +%Y%m%d_%H%M%S)"
    if crontab -u "$CRON_USER" -l > /dev/null 2>&1; then
        crontab -u "$CRON_USER" -l > "$backup_file"
        log_info "Backed up current crontab to $backup_file"
    else
        log_info "No existing crontab for $CRON_USER – nothing to back up."
    fi
}

# Download a template script from the repo and make it executable
deploy_job_from_template() {
    local job_path="$1"      # relative path inside monsun-cron/, e.g. "system/clean-tmp"
    local target_dir="${CRON_BASE}/${job_path}"
    mkdir -p "$target_dir"/{bin,conf,logs}

    local script_name=$(basename "$job_path")
    local script_url="${REPO_BASE}/monsun-cron/${job_path}/bin/${script_name}.sh"
    local conf_url="${REPO_BASE}/monsun-cron/${job_path}/conf/${script_name}.conf"

    # Download script if it doesn't exist or force refresh with -f
    curl -fsSL "$script_url" -o "${target_dir}/bin/${script_name}.sh"
    chmod 750 "${target_dir}/bin/${script_name}.sh"

    # Download default config (won't overwrite existing on server, but we store template in repo)
    if [[ ! -f "${target_dir}/conf/${script_name}.conf" ]]; then
        curl -fsSL "$conf_url" -o "${target_dir}/conf/${script_name}.conf"
        chmod 640 "${target_dir}/conf/${script_name}.conf"
    fi
    log_info "Deployed job: $job_path"
}

# ---------------------------- 1. Install UKwinika Backup ----------------------
install_ukwinika_backup() {
    local ukwi_script_url="${REPO_BASE}/enhanced_automated_backups.sh"
    local ukwi_config_url="${REPO_BASE}/config/ukwinika-backup.conf.example"
    local ukwi_secrets_url="${REPO_BASE}/config/ukwinika-backup.secrets.example"

    local ukwi_bin="/usr/local/bin/ukwinika-backup.sh"
    local ukwi_config="/etc/ukwinika-backup.conf"
    local ukwi_secrets="/etc/ukwinika-backup.secrets"

    log_info "Installing UKwinika Enhanced Backup Script..."

    curl -fsSL "$ukwi_script_url" -o "$ukwi_bin"
    chmod 750 "$ukwi_bin"

    [[ ! -f "$ukwi_config" ]] && { curl -fsSL "$ukwi_config_url" -o "$ukwi_config"; chmod 640 "$ukwi_config"; }
    [[ ! -f "$ukwi_secrets" ]] && { curl -fsSL "$ukwi_secrets_url" -o "$ukwi_secrets"; chmod 600 "$ukwi_secrets"; }

    # Create wrapper script inside monsun-cron structure
    mkdir -p "$CRON_BASE/backups/full-system-backup"/{bin,conf,logs}
    cat > "$CRON_BASE/backups/full-system-backup/bin/full-system-backup.sh" <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/ukwinika-backup.sh backup
EOF
    chmod 750 "$CRON_BASE/backups/full-system-backup/bin/full-system-backup.sh"
}

# ---------------------------- 2. Deploy All Monsun Jobs ----------------------
deploy_all_monsun_jobs() {
    # List of all job paths (relative to monsun-cron/ in the repo)
    local jobs=(
        "system/clean-tmp"
        "system/rotate-logs"
        "backups/config-backup"
        "backups/offsite-replication"
        "security/vulnerability-scan"
        "security/integrity-check"
        "security/certbot-renew"
        "database/db-backup"
        "database/db-optimize"
        "database/db-consistency"
        "application/daily-report"
        "application/data-archive"
        "application/inactive-user-cleanup"
        "orchestration/eod-process"
    )
    for job in "${jobs[@]}"; do
        deploy_job_from_template "$job"
    done
}

# ---------------------------- 3. Install Cron Definitions --------------------
install_cron_jobs() {
    local cron_file=$(mktemp)
    crontab -u "$CRON_USER" -l > "$cron_file" 2>/dev/null || touch "$cron_file"

    sed -i "/$CRON_MARKER_START/,/$CRON_MARKER_END/d" "$cron_file"

    cat >> "$cron_file" <<EOF
$CRON_MARKER_START
# All paths absolute – jobs use flock and logging

# System Health
0 3 * * *   $CRON_BASE/system/clean-tmp/bin/clean-tmp.sh
0 0 * * *   $CRON_BASE/system/rotate-logs/bin/rotate-logs.sh

# Backups
0 1 * * *   $CRON_BASE/backups/full-system-backup/bin/full-system-backup.sh
0 1 * * *   $CRON_BASE/backups/config-backup/bin/config-backup.sh
0 4 * * *   $CRON_BASE/backups/offsite-replication/bin/offsite-replication.sh

# Security
0 4 * * *   $CRON_BASE/security/vulnerability-scan/bin/vulnerability-scan.sh
0 5 * * 0   $CRON_BASE/security/integrity-check/bin/integrity-check.sh
30 2 * * *  $CRON_BASE/security/certbot-renew/bin/certbot-renew.sh

# Database
0 2 * * *   $CRON_BASE/database/db-backup/bin/db-backup.sh
0 3 * * 0   $CRON_BASE/database/db-optimize/bin/db-optimize.sh
0 4 * * 0   $CRON_BASE/database/db-consistency/bin/db-consistency.sh

# Application
0 22 * * *  $CRON_BASE/application/daily-report/bin/daily-report.sh
0 2 * * 1   $CRON_BASE/application/data-archive/bin/data-archive.sh
0 0 * * *   $CRON_BASE/application/inactive-user-cleanup/bin/inactive-user-cleanup.sh

# Orchestration
0 1 * * *   $CRON_BASE/orchestration/eod-process/bin/eod-process.sh

$CRON_MARKER_END
EOF

    crontab -u "$CRON_USER" "$cron_file"
    rm -f "$cron_file"
    log_info "Cron jobs installed successfully."
}

# ---------------------------- 4. Apply Monsun Best Practices -----------------
apply_monsun_best_practices() {
    mkdir -p "$LOG_DIR"
    cat > /etc/logrotate.d/monsun-cron <<EOF
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF
    log_info "Logrotate configuration added."

    cat > /etc/cron.d/monsun-env <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=admin@example.com
EOF
    log_info "Global cron environment set in /etc/cron.d/monsun-env"

    echo "root" > /etc/cron.allow
    chmod 640 /etc/cron.allow
    log_info "Restricted crontab access to root only."
}

# ---------------------------- 5. Main ----------------------------------------
main() {
    [[ $EUID -ne 0 ]] && { echo "Must be run as root." >&2; exit 1; }
    log_info "Starting Monsun cron + backup setup..."
    backup_crontab
    install_ukwinika_backup
    deploy_all_monsun_jobs
    install_cron_jobs
    apply_monsun_best_practices
    log_info "Setup complete! Edit /etc/ukwinika-backup.conf and /etc/ukwinika-backup.secrets."
}

main "$@"
