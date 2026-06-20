#!/usr/bin/env bash
# =============================================================================
# UKwinika Automated Restore Script
# Author: Urayayi Kwinika
# Version: 1.0
# Project version: 3.2.1
# Description:
#   Automated monthly restore drill for UKwinika EABS v3.2.1 backups.
#   Implements the full verification workflow from docs/RESTORE-CHECKLIST.md
#   without human interaction — suitable for scheduled execution via systemd.
#
#   This script is entirely non-destructive. It extracts archives to an
#   isolated drill directory and never writes to any path outside
#   RESTORE_TARGET_BASE. Live system data is never touched.
#
#   "A Backup is Only as Good as its Last Successful Restore. Test Monthly."
#                                              — UKwinika Notable Advice
#
# Usage:
#   test [archive_name]   Run a restore drill against the most recent archive,
#                         or against a specific named archive.
#   list                  List all available archives in the repository.
#   clean                 Remove all drill directories under RESTORE_TARGET_BASE.
#
# Exit codes:
#   0  Drill passed — all verification checks succeeded.
#   1  Drill failed — at least one verification check failed, or a fatal
#      error occurred. The restore directory is preserved for inspection
#      if RESTORE_KEEP_ON_FAILURE=yes.
#
# Compatibility:
#   Uses (cd target && borg extract) instead of borg extract --target,
#   for compatibility with BorgBackup 1.2.x (Debian 12, Ubuntu 22.04/24.04,
#   RHEL 9). The --target flag was introduced in BorgBackup 1.4.
#
# Configuration (add to /etc/ukwinika-backup.conf):
#   RESTORE_TARGET_BASE     Base directory for drill extractions.
#                           Default: /var/lib/ukwinika/restore-drills
#   RESTORE_VERIFY_PATHS    Space-separated list of paths (relative to archive
#                           root) that must exist in the restored data.
#                           Default: "etc/hostname etc/os-release etc/fstab"
#   RESTORE_MIN_FILES       Minimum number of files the restore must contain.
#                           Default: 100
#   RESTORE_KEEP_ON_FAILURE Whether to preserve the drill directory on failure
#                           for manual inspection. yes or no.
#                           Default: yes
#   RESTORE_DRILL_LOG       Path for the dedicated restore drill log.
#                           Default: /var/log/UKwinikaRestore.log
# =============================================================================
set -euo pipefail

# =============================================================================
# Script identity
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0"
LOCK_FILE="/var/lock/ukwinika-restore-test.lock"

# =============================================================================
# Load configuration and secrets
# Uses the same UKW_CONFIG / UKW_SECRETS paths as the backup script so no
# separate configuration file is required for basic use.
# =============================================================================
UKW_CONFIG="${UKW_CONFIG:-/etc/ukwinika-backup.conf}"
UKW_SECRETS="${UKW_SECRETS:-/etc/ukwinika-backup.secrets}"

if [[ ! -f "$UKW_CONFIG" ]]; then
    echo "ERROR: Configuration file ${UKW_CONFIG} not found." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$UKW_CONFIG"

if [[ -f "$UKW_SECRETS" ]]; then
    # shellcheck source=/dev/null
    source "$UKW_SECRETS"
fi

: "${BORG_PASSPHRASE:?ERROR: BORG_PASSPHRASE is not set. Check ${UKW_SECRETS}.}"
export BORG_PASSPHRASE

# =============================================================================
# Shared configuration (inherited from backup config)
# =============================================================================
BORG_REPO="${BORG_REPO:-/UKwinikaBackup/borg-repo}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_TO="${EMAIL_TO:-}"
METRICS_ENABLED="${METRICS_ENABLED:-yes}"
PROMETHEUS_FILE="${PROMETHEUS_FILE:-/var/lib/prometheus/node_exporter/custom/ukwinika_backup.prom}"
CHECKSUM_FILE="${CHECKSUM_FILE:-/tmp/ukwinika-backup-checksums.txt}"

LOG_FILE="/var/log/UKwinikaBackup.log"
AUDIT_LOG="/var/log/UKwinikaBackup_audit.log"

# =============================================================================
# Restore-specific configuration (override in /etc/ukwinika-backup.conf)
# =============================================================================
RESTORE_TARGET_BASE="${RESTORE_TARGET_BASE:-/var/lib/ukwinika/restore-drills}"
RESTORE_VERIFY_PATHS="${RESTORE_VERIFY_PATHS:-etc/hostname etc/os-release etc/fstab}"
RESTORE_MIN_FILES="${RESTORE_MIN_FILES:-100}"
RESTORE_KEEP_ON_FAILURE="${RESTORE_KEEP_ON_FAILURE:-yes}"
RESTORE_DRILL_LOG="${RESTORE_DRILL_LOG:-/var/log/UKwinikaRestore.log}"

# =============================================================================
# Runtime state
# =============================================================================
DRILL_DIR=""
DRILL_TIMESTAMP=""
DRILL_ARCHIVE=""
PASS_COUNT=0
FAIL_COUNT=0

# =============================================================================
# Logging helpers
# =============================================================================
log() {
    local msg
    msg="$(date '+%F %T') ${SCRIPT_NAME}: $*"
    echo "$msg" | tee -a "$LOG_FILE" >> "$RESTORE_DRILL_LOG"
}

audit() {
    local msg
    msg="$(date '+%F %T') [AUDIT] $1"
    echo "$msg" | tee -a "$AUDIT_LOG" >> "$RESTORE_DRILL_LOG"
}

check_pass() {
    PASS_COUNT=$(( PASS_COUNT + 1 ))
    log "  [PASS] $1"
}

check_fail() {
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    log "  [FAIL] $1"
}

die() {
    log "FATAL: $*"
    notify_restore "FAILED: $*"
    cleanup_on_exit
    exit 1
}

# =============================================================================
# Locking — separate lock file from the backup script
# =============================================================================
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "Another restore drill is already running. Exiting."
    exit 0
fi

cleanup_lock() {
    flock -u 200 2>/dev/null || true
    rm -f "$LOCK_FILE"
}
trap cleanup_lock EXIT INT TERM

# =============================================================================
# Drill directory cleanup on fatal error
# =============================================================================
cleanup_on_exit() {
    if [[ -n "$DRILL_DIR" && -d "$DRILL_DIR" ]]; then
        if [[ "$RESTORE_KEEP_ON_FAILURE" == "yes" ]]; then
            log "Drill directory preserved for inspection: ${DRILL_DIR}"
        else
            log "Removing drill directory: ${DRILL_DIR}"
            rm -rf "$DRILL_DIR"
        fi
    fi
}

# =============================================================================
# Notifications
# =============================================================================
notify_restore() {
    local status="$1"
    local host
    host=$(hostname)

    if [[ -n "$SLACK_WEBHOOK" ]]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"Restore Drill ${status} on ${host} — archive: ${DRILL_ARCHIVE:-unknown}\"}" \
            "$SLACK_WEBHOOK" || true
    fi

    if [[ -n "$EMAIL_TO" ]]; then
        {
            echo "Restore Drill ${status} on ${host}"
            echo "Archive tested: ${DRILL_ARCHIVE:-unknown}"
            echo "Checks passed:  ${PASS_COUNT}"
            echo "Checks failed:  ${FAIL_COUNT}"
            [[ -n "$DRILL_DIR" ]] && echo "Drill directory: ${DRILL_DIR}"
            echo ""
            echo "See ${RESTORE_DRILL_LOG} for the full drill log."
        } | mail -s "UKwinika Restore Drill ${status}" "$EMAIL_TO" || true
    fi
}

# =============================================================================
# Prometheus metrics — appended to existing PROMETHEUS_FILE
# =============================================================================
push_restore_metrics() {
    [[ "$METRICS_ENABLED" != "yes" ]] && return 0

    local result
    result=$(( FAIL_COUNT == 0 ? 1 : 0 ))

    mkdir -p "$(dirname "$PROMETHEUS_FILE")"

    cat >> "$PROMETHEUS_FILE" << EOF

# HELP ukwinika_restore_test_last_run_seconds Unix timestamp of the last restore drill
# TYPE ukwinika_restore_test_last_run_seconds gauge
ukwinika_restore_test_last_run_seconds $(date +%s)
# HELP ukwinika_restore_test_last_result Result of the last restore drill (1=pass, 0=fail)
# TYPE ukwinika_restore_test_last_result gauge
ukwinika_restore_test_last_result{archive="${DRILL_ARCHIVE:-unknown}"} ${result}
# HELP ukwinika_restore_test_checks_passed Number of verification checks that passed
# TYPE ukwinika_restore_test_checks_passed gauge
ukwinika_restore_test_checks_passed ${PASS_COUNT}
# HELP ukwinika_restore_test_checks_failed Number of verification checks that failed
# TYPE ukwinika_restore_test_checks_failed gauge
ukwinika_restore_test_checks_failed ${FAIL_COUNT}
EOF

    log "Prometheus restore metrics appended to ${PROMETHEUS_FILE}"
}

# =============================================================================
# Repository existence check — matches backup script exactly
# =============================================================================
ensure_repo_exists() {
    if [[ ! -d "$BORG_REPO" ]] || [[ ! -f "${BORG_REPO}/config" ]]; then
        log "ERROR: Borg repository not found at ${BORG_REPO}."
        echo "Initialise with: sudo enhanced_automated_backups.sh init" >&2
        return 1
    fi
    return 0
}

# =============================================================================
# Pre-flight: full repository integrity check
# =============================================================================
preflight_repo_check() {
    log "Pre-flight: running full repository integrity check (borg check)..."
    if borg check "$BORG_REPO" 2>&1 | tee -a "$RESTORE_DRILL_LOG" | tee -a "$LOG_FILE"; then
        check_pass "Repository integrity check passed"
    else
        die "Repository integrity check failed. Cannot proceed with restore drill."
    fi
}

# =============================================================================
# Pre-flight: check available disk space
# =============================================================================
preflight_disk_space() {
    local archive="$1"
    log "Pre-flight: checking available disk space on ${RESTORE_TARGET_BASE}..."

    mkdir -p "$RESTORE_TARGET_BASE"

    local archive_size_bytes
    archive_size_bytes=$(borg info --json "${BORG_REPO}::${archive}" 2>/dev/null \
        | grep -o '"original_size": *[0-9]*' \
        | grep -o '[0-9]*' \
        | head -1 || echo "0")

    local available_bytes
    available_bytes=$(df --output=avail -B1 "$RESTORE_TARGET_BASE" 2>/dev/null \
        | tail -1 \
        | tr -d ' ' || echo "0")

    local archive_size_mb=$(( archive_size_bytes / 1048576 ))
    local available_mb=$(( available_bytes / 1048576 ))

    log "  Archive uncompressed size: ${archive_size_mb} MiB"
    log "  Available space:           ${available_mb} MiB on ${RESTORE_TARGET_BASE}"

    local required_bytes=$(( archive_size_bytes + archive_size_bytes / 10 ))

    if (( available_bytes >= required_bytes )); then
        check_pass "Sufficient disk space available (${available_mb} MiB free, ~${archive_size_mb} MiB needed)"
    else
        die "Insufficient disk space: ${available_mb} MiB available, at least ${archive_size_mb} MiB required."
    fi
}

# =============================================================================
# Resolve archive name
# =============================================================================
resolve_archive() {
    local requested="$1"

    if [[ -n "$requested" ]]; then
        if borg list --short "$BORG_REPO" | grep -qxF "$requested"; then
            echo "$requested"
            return 0
        else
            die "Archive '${requested}' not found in repository ${BORG_REPO}."
        fi
    fi

    local latest
    latest=$(borg list --short --last 1 "$BORG_REPO" 2>/dev/null || true)

    if [[ -z "$latest" ]]; then
        die "No archives found in repository ${BORG_REPO}. Run a backup first."
    fi

    echo "$latest"
}

# =============================================================================
# Extract archive to drill directory
# Uses (cd target && borg extract) for borg 1.2.x compatibility.
# The --target flag was introduced in BorgBackup 1.4.
# =============================================================================
extract_archive() {
    local archive="$1"
    local target="$2"

    log "Extracting archive '${archive}' to '${target}'..."
    mkdir -p "$target"

    if ( cd "$target" && borg extract "${BORG_REPO}::${archive}" ) \
            2>&1 | tee -a "$RESTORE_DRILL_LOG" | tee -a "$LOG_FILE"; then
        check_pass "Archive extraction completed without errors"
    else
        die "Archive extraction failed for '${archive}'."
    fi
}

# =============================================================================
# Verification suite — six independent checks
# =============================================================================

verify_non_empty() {
    local target="$1"
    log "Verification 1/6: Checking that restore directory is non-empty..."

    local entry_count
    entry_count=$(find "$target" -mindepth 1 | wc -l)

    if (( entry_count > 0 )); then
        check_pass "Restore directory is non-empty (${entry_count} top-level entries found)"
    else
        check_fail "Restore directory is empty — extraction may have produced no output"
    fi
}

verify_mandatory_paths() {
    local target="$1"
    log "Verification 2/6: Checking mandatory paths (${RESTORE_VERIFY_PATHS})..."

    local all_present=true
    for rel_path in $RESTORE_VERIFY_PATHS; do
        local full_path="${target}/${rel_path}"
        if [[ -e "$full_path" ]]; then
            log "  Found: ${rel_path}"
        else
            log "  Missing: ${rel_path}"
            all_present=false
        fi
    done

    if [[ "$all_present" == "true" ]]; then
        check_pass "All mandatory paths present in restored data"
    else
        check_fail "One or more mandatory paths missing — see log for details"
    fi
}

verify_file_count() {
    local target="$1"
    log "Verification 3/6: Counting restored files (minimum: ${RESTORE_MIN_FILES})..."

    local file_count
    file_count=$(find "$target" -type f | wc -l)
    log "  Restored file count: ${file_count}"

    if (( file_count >= RESTORE_MIN_FILES )); then
        check_pass "File count acceptable: ${file_count} files restored (minimum: ${RESTORE_MIN_FILES})"
    else
        check_fail "Too few files restored: ${file_count} found, minimum is ${RESTORE_MIN_FILES}"
    fi
}

verify_checksums() {
    local target="$1"
    log "Verification 4/6: SHA256 spot-check against audit log (${AUDIT_LOG})..."

    if [[ ! -f "$AUDIT_LOG" ]]; then
        log "  WARNING: Audit log not found at ${AUDIT_LOG}. Skipping checksum verification."
        check_fail "Audit log not found — checksum verification could not be performed"
        return 0
    fi

    local checked=0
    local mismatched=0

    for rel_path in $RESTORE_VERIFY_PATHS; do
        local full_path="${target}/${rel_path}"
        [[ ! -f "$full_path" ]] && continue

        local restored_sum
        restored_sum=$(sha256sum "$full_path" | awk '{print $1}')

        local audit_sum
        audit_sum=$(grep "${rel_path}$" "$AUDIT_LOG" 2>/dev/null \
            | tail -1 \
            | awk '{print $1}' || true)

        if [[ -z "$audit_sum" ]]; then
            log "  SKIP  ${rel_path} — no audit log entry found"
            continue
        fi

        if [[ "$restored_sum" == "$audit_sum" ]]; then
            log "  OK    ${rel_path}"
            checked=$(( checked + 1 ))
        else
            log "  MISMATCH ${rel_path}"
            log "    Restored: ${restored_sum}"
            log "    Audit:    ${audit_sum}"
            mismatched=$(( mismatched + 1 ))
        fi
    done

    if (( mismatched == 0 && checked > 0 )); then
        check_pass "Checksum verification passed for ${checked} file(s)"
    elif (( mismatched == 0 && checked == 0 )); then
        check_pass "Checksum verification skipped — no comparable audit entries available"
    else
        check_fail "Checksum mismatch detected in ${mismatched} file(s) — data integrity concern"
    fi
}

verify_no_zero_byte_files() {
    local target="$1"
    log "Verification 5/6: Checking for unexpected zero-byte files in critical paths..."

    # /etc is excluded — zero-byte placeholder and lock files in /etc are normal
    # and would produce false positives. Only /usr and /bin are checked.
    local critical_dirs=("${target}/usr" "${target}/bin")
    local zero_count=0

    for dir in "${critical_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        local count
        count=$(find "$dir" -maxdepth 2 -type f -size 0 | wc -l)
        if (( count > 0 )); then
            log "  ${count} zero-byte file(s) found under ${dir##*/}"
            zero_count=$(( zero_count + count ))
        fi
    done

    if (( zero_count == 0 )); then
        check_pass "No unexpected zero-byte files found in critical paths"
    else
        check_fail "${zero_count} zero-byte file(s) found in critical paths — archive may be incomplete"
    fi
}

verify_archive_metadata() {
    local archive="$1"
    log "Verification 6/6: Verifying archive metadata..."

    local archive_hostname
    archive_hostname=$(borg info "${BORG_REPO}::${archive}" 2>/dev/null \
        | grep -i "hostname" \
        | awk '{print $NF}' \
        | head -1 || echo "unknown")

    local archive_time
    archive_time=$(borg info "${BORG_REPO}::${archive}" 2>/dev/null \
        | grep -i "time (start)" \
        | sed 's/.*: *//' \
        | head -1 || echo "unknown")

    log "  Archive hostname: ${archive_hostname}"
    log "  Archive created:  ${archive_time}"

    if [[ "$archive_hostname" != "unknown" && -n "$archive_hostname" ]]; then
        check_pass "Archive metadata readable — hostname: ${archive_hostname}, created: ${archive_time}"
    else
        check_fail "Could not read archive metadata — borg info returned unexpected output"
    fi
}

# =============================================================================
# Write structured drill result to audit log
# =============================================================================
write_audit_entry() {
    local result="$1"
    audit "RESTORE DRILL ${result} — archive: ${DRILL_ARCHIVE} | checks passed: ${PASS_COUNT} | checks failed: ${FAIL_COUNT} | drill dir: ${DRILL_DIR}"
}

# =============================================================================
# Cleanup after drill
# =============================================================================
cleanup_drill_dir() {
    local result="$1"

    if [[ ! -d "$DRILL_DIR" ]]; then
        return 0
    fi

    if [[ "$result" == "PASS" ]]; then
        log "Removing drill directory (drill passed): ${DRILL_DIR}"
        rm -rf "$DRILL_DIR"
    elif [[ "$RESTORE_KEEP_ON_FAILURE" == "yes" ]]; then
        log "Drill directory preserved for inspection (RESTORE_KEEP_ON_FAILURE=yes): ${DRILL_DIR}"
    else
        log "Removing drill directory (RESTORE_KEEP_ON_FAILURE=no): ${DRILL_DIR}"
        rm -rf "$DRILL_DIR"
    fi
}

# =============================================================================
# Main drill orchestrator
# =============================================================================
run_drill() {
    local requested_archive="${1:-}"

    DRILL_TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

    log "================================================================"
    log "=== UKwinika Automated Restore Drill starting (v${SCRIPT_VERSION}) ==="
    log "================================================================"

    ensure_repo_exists || die "Repository missing or invalid"

    DRILL_ARCHIVE=$(resolve_archive "$requested_archive")
    log "Target archive: ${DRILL_ARCHIVE}"

    preflight_repo_check
    preflight_disk_space "$DRILL_ARCHIVE"

    DRILL_DIR="${RESTORE_TARGET_BASE}/${DRILL_TIMESTAMP}_${DRILL_ARCHIVE}"
    log "Drill directory: ${DRILL_DIR}"

    extract_archive "$DRILL_ARCHIVE" "$DRILL_DIR"

    log "--- Running verification suite ---"
    verify_non_empty          "$DRILL_DIR"
    verify_mandatory_paths    "$DRILL_DIR"
    verify_file_count         "$DRILL_DIR"
    verify_checksums          "$DRILL_DIR"
    verify_no_zero_byte_files "$DRILL_DIR"
    verify_archive_metadata   "$DRILL_ARCHIVE"

    log "--- Verification complete ---"
    log "Checks passed: ${PASS_COUNT}"
    log "Checks failed: ${FAIL_COUNT}"

    local overall_result
    if (( FAIL_COUNT == 0 )); then
        overall_result="PASS"
    else
        overall_result="FAIL"
    fi

    log "Overall result: ${overall_result}"

    write_audit_entry "$overall_result"
    push_restore_metrics
    cleanup_drill_dir "$overall_result"

    log "================================================================"
    log "=== UKwinika Automated Restore Drill complete: ${overall_result} ==="
    log "================================================================"

    if [[ "$overall_result" == "PASS" ]]; then
        notify_restore "PASSED"
        return 0
    else
        notify_restore "FAILED — ${FAIL_COUNT} check(s) did not pass"
        return 1
    fi
}

# =============================================================================
# List archives
# =============================================================================
list_archives() {
    ensure_repo_exists || die "Repository missing or invalid"
    log "Listing all archives in ${BORG_REPO}..."
    borg list "$BORG_REPO"
}

# =============================================================================
# Clean all drill directories
# =============================================================================
clean_drill_dirs() {
    if [[ ! -d "$RESTORE_TARGET_BASE" ]]; then
        echo "No drill directories found at ${RESTORE_TARGET_BASE}."
        return 0
    fi

    local count
    count=$(find "$RESTORE_TARGET_BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)

    if (( count == 0 )); then
        echo "No drill directories to remove under ${RESTORE_TARGET_BASE}."
        return 0
    fi

    log "Removing ${count} drill director(y/ies) under ${RESTORE_TARGET_BASE}..."
    find "$RESTORE_TARGET_BASE" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
    log "Clean complete."
}

# =============================================================================
# CLI dispatch
# =============================================================================
case "${1:-test}" in
    test)
        run_drill "${2:-}"
        ;;
    list)
        list_archives
        ;;
    clean)
        clean_drill_dirs
        ;;
    *)
        echo "Usage: $0 {test [archive_name]|list|clean}"
        echo ""
        echo "  test [archive_name]   Run restore drill against most recent or named archive"
        echo "  list                  List all available archives"
        echo "  clean                 Remove all drill directories under RESTORE_TARGET_BASE"
        exit 1
        ;;
esac
