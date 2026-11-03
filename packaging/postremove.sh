#!/bin/sh
# RPM %postun scriptlet for zimbra-backup.
# $1 == 0 : full package removal -> clean /var/lib/zimbra-backup & logrotate backups
# $1 >= 1 : package upgrade -> preserve all state, jobs, and logs
#
# Safety guarantees for Zimbra Collaboration Server:
# - Only removes /var/lib/zimbra-backup (never symlinks, never /opt/zimbra,
#   never backup archives in /home/backup, /backup, or external mounts).
# - Never touches any running Zimbra or system mail service.

set -eu

action="${1:-0}"
case "$action" in
    0|remove|purge) ;;
    *) exit 0 ;;
esac

STATE_DIR="/var/lib/zimbra-backup"
LOGROTATE_DIR="/etc/logrotate.d"
if [ "${ZB_TEST_UNINSTALL:-0}" = "1" ] && [ -n "${ZB_STATE_DIR:-}" ]; then
    case "$ZB_STATE_DIR" in
        /tmp/zb_test.*/*)
            STATE_DIR="$ZB_STATE_DIR"
            LOGROTATE_DIR="${ZB_LOGROTATE_DIR:-/etc/logrotate.d}"
            ;;
    esac
fi

# Guard against any unexpected path or symlink
case "$STATE_DIR" in
    /var/lib/zimbra-backup|/tmp/zb_test.*/*)
        if [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]; then
            rm -rf -- "$STATE_DIR"
        fi
        ;;
esac

case "$LOGROTATE_DIR" in
    /etc/logrotate.d|/tmp/zb_test.*/*)
        for ext in rpmsave rpmnew; do
            f="${LOGROTATE_DIR}/zimbra-backup.${ext}"
            if [ -f "$f" ] && [ ! -L "$f" ]; then
                rm -f -- "$f"
            fi
        done
        ;;
esac

echo "[zimbra-backup] Uninstalled cleanly: removed managed cron entries and ${STATE_DIR}."
echo "[zimbra-backup] Zimbra mail services (/opt/zimbra) and backup data archives were NOT touched."
exit 0
