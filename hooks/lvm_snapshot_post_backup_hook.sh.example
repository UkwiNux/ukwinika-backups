#!/bin/bash
# =============================================================================
# UKwinika LVM Snapshot Post-Backup Hook
# Place in /etc/ukwinika/post_backup_hook.sh and make executable (chmod +x),
# then point POST_HOOK at it in /etc/ukwinika-backup.conf.
#
# Purpose:
#   Unmounts and removes the LVM snapshot created by
#   lvm_snapshot_pre_backup_hook.sh.example, once Borg has finished reading
#   from it. Must use the same VG_NAME/LV_NAME/SNAP_NAME/SNAP_MOUNT values
#   as the pre-backup hook.
# =============================================================================
set -euo pipefail

VG_NAME="${UKW_LVM_VG:-vg0}"
SNAP_NAME="${UKW_LVM_SNAP_NAME:-ukwinika_backup_snap}"
SNAP_MOUNT="${UKW_LVM_SNAP_MOUNT:-/mnt/ukwinika-snapshot}"

echo "$(date '+%F %T') [HOOK] LVM post-backup cleanup hook started" >> /var/log/UKwinikaBackup.log

if mountpoint -q "$SNAP_MOUNT"; then
    umount "$SNAP_MOUNT"
fi

if lvs "/dev/${VG_NAME}/${SNAP_NAME}" >/dev/null 2>&1; then
    lvremove --force "/dev/${VG_NAME}/${SNAP_NAME}"
fi

echo "$(date '+%F %T') [HOOK] LVM snapshot ${SNAP_NAME} unmounted and removed" >> /var/log/UKwinikaBackup.log
echo "$(date '+%F %T') [HOOK] LVM post-backup cleanup hook completed" >> /var/log/UKwinikaBackup.log
exit 0
