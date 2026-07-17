#!/bin/bash
# =============================================================================
# UKwinika LVM Snapshot Pre-Backup Hook
# Place in /etc/ukwinika/pre_backup_hook.sh and make executable (chmod +x),
# then point PRE_HOOK at it in /etc/ukwinika-backup.conf.
#
# Purpose:
#   The default full-filesystem backup reads live files with no point-in-time
#   guarantee — files can change mid-backup, producing a fuzzy/inconsistent
#   snapshot for anything outside the DB_TYPE-aware dump paths. This hook
#   takes an LVM snapshot of the volume(s) holding your data BEFORE Borg
#   starts reading, giving you a frozen, consistent view for the duration
#   of the backup. Pair with lvm_snapshot_post_backup_hook.sh.example to
#   remove the snapshot afterwards.
#
# Requirements:
#   - The volume group / logical volume must have enough free extents to
#     hold the snapshot's copy-on-write delta for the backup's duration.
#   - BACKUP_PATHS in ukwinika-backup.conf should point at the snapshot
#     mount point (e.g. /mnt/ukwinika-snapshot) rather than the live path,
#     so Borg reads the frozen view, not the live filesystem.
#
# Configure these to match your environment:
# =============================================================================
set -euo pipefail

VG_NAME="${UKW_LVM_VG:-vg0}"
LV_NAME="${UKW_LVM_LV:-data}"
SNAP_NAME="${UKW_LVM_SNAP_NAME:-ukwinika_backup_snap}"
SNAP_SIZE="${UKW_LVM_SNAP_SIZE:-5G}"
SNAP_MOUNT="${UKW_LVM_SNAP_MOUNT:-/mnt/ukwinika-snapshot}"

echo "$(date '+%F %T') [HOOK] LVM pre-backup snapshot hook started" >> /var/log/UKwinikaBackup.log

# Refuse to proceed if a stale snapshot from a previous failed run still exists.
if lvs "/dev/${VG_NAME}/${SNAP_NAME}" >/dev/null 2>&1; then
    echo "$(date '+%F %T') [HOOK] ERROR: stale snapshot ${SNAP_NAME} already exists — remove it manually before retrying" >> /var/log/UKwinikaBackup.log
    exit 1
fi

lvcreate --size "$SNAP_SIZE" --snapshot --name "$SNAP_NAME" "/dev/${VG_NAME}/${LV_NAME}"

mkdir -p "$SNAP_MOUNT"
mount -o ro "/dev/${VG_NAME}/${SNAP_NAME}" "$SNAP_MOUNT"

echo "$(date '+%F %T') [HOOK] LVM snapshot ${SNAP_NAME} created and mounted read-only at ${SNAP_MOUNT}" >> /var/log/UKwinikaBackup.log
echo "$(date '+%F %T') [HOOK] LVM pre-backup snapshot hook completed" >> /var/log/UKwinikaBackup.log
exit 0
