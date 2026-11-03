#!/bin/sh
# RPM %preun scriptlet for zimbra-backup.
# $1 == 0 : full package removal (dnf remove / yum remove / rpm -e)
# $1 >= 1 : package upgrade (rpm -Uvh / dnf upgrade) -> preserve jobs and crontab
#
# Safety guarantees for Zimbra Collaboration Server:
# - Never stops, restarts, reloads, or signals any Zimbra service or daemon.
# - Never modifies anything under /opt/zimbra or any backup storage directory.
# - Aborts removal if a backup or restore operation is actively running.
# - Strips ONLY the '# BEGIN zimbra-backup .. # END zimbra-backup' block from
#   zimbra's crontab after verifying all Zimbra system cron lines remain intact.

set -eu

action="${1:-0}"
case "$action" in
    0|remove|purge) ;;
    *) exit 0 ;;
esac

ZIMBRA_USER="${ZB_ZIMBRA_USER:-zimbra}"
STATE_DIR="/var/lib/zimbra-backup"
if [ "${ZB_TEST_UNINSTALL:-0}" = "1" ] && [ -n "${ZB_STATE_DIR:-}" ]; then
    case "$ZB_STATE_DIR" in
        /tmp/zb_test.*/*) STATE_DIR="$ZB_STATE_DIR" ;;
    esac
fi

# 1. Refuse removal while an active backup or restore holds operation.lock
LOCK_FILE="${STATE_DIR}/operation.lock"
if [ -f "$LOCK_FILE" ] && [ ! -L "$LOCK_FILE" ] && command -v flock >/dev/null 2>&1; then
    if ! ( exec 9>"$LOCK_FILE" && flock -n 9 ) 2>/dev/null; then
        echo "ERROR: A zimbra-backup operation is currently running (${LOCK_FILE} is locked)." >&2
        echo "       Wait for it to finish before removing zimbra-backup." >&2
        exit 1
    fi
fi

# 2. Safely remove ONLY the zimbra-backup managed block from zimbra's crontab
clean_zimbra_crontab() {
    command -v crontab >/dev/null 2>&1 || return 0
    if [ "${ZB_SKIP_USER_CHECK:-0}" != "1" ]; then
        (getent passwd "$ZIMBRA_USER" || id "$ZIMBRA_USER") >/dev/null 2>&1 || return 0
    fi

    TMP_BASE="/tmp"
    if [ -d "${STATE_DIR}/run" ] && [ ! -L "${STATE_DIR}/run" ] && [ -w "${STATE_DIR}/run" ]; then
        TMP_BASE="${STATE_DIR}/run"
    fi

    WORK_TMP="$(mktemp -d "${TMP_BASE}/.zb_uninst.XXXXXX" 2>/dev/null || mktemp -d "/tmp/.zb_uninst.XXXXXX")"
    CUR_CRON="${WORK_TMP}/cur.cron"
    NEW_CRON="${WORK_TMP}/new.cron"

    if [ "${ZB_SKIP_USER_CHECK:-0}" = "1" ] || [ "$(id -un 2>/dev/null || echo '')" = "$ZIMBRA_USER" ]; then
        crontab -l > "$CUR_CRON" 2>/dev/null || { rm -rf -- "$WORK_TMP" 2>/dev/null || true; return 0; }
    else
        crontab -u "$ZIMBRA_USER" -l > "$CUR_CRON" 2>/dev/null || { rm -rf -- "$WORK_TMP" 2>/dev/null || true; return 0; }
    fi

    if ! grep -Eq '^# BEGIN zimbra-backup([[:space:]]|$)' "$CUR_CRON" && ! grep -Fq "zimbra-backup job run " "$CUR_CRON"; then
        rm -rf -- "$WORK_TMP" 2>/dev/null || true
        return 0
    fi

    if grep -Eq '^# BEGIN zimbra-backup([[:space:]]|$)' "$CUR_CRON" && grep -Eq '^# END zimbra-backup([[:space:]]|$)' "$CUR_CRON"; then
        awk '
            index($0, "# BEGIN zimbra-backup") == 1 { skip = 1; next }
            index($0, "# END zimbra-backup") == 1   { skip = 0; next }
            !skip { print }
        ' "$CUR_CRON" > "$NEW_CRON"
    else
        awk '
            index($0, "# BEGIN zimbra-backup") == 1 { next }
            index($0, "# END zimbra-backup") == 1   { next }
            index($0, "/zimbra-backup job run ") > 0 { next }
            { print }
        ' "$CUR_CRON" > "$NEW_CRON"
    fi

    # Safety invariant: every Zimbra system cron line (/opt/zimbra, ZIMBRASTART, ZIMBRAEND)
    # must remain 100% identical before and after stripping.
    ORIG_ZM="${WORK_TMP}/orig.zm"
    NEW_ZM="${WORK_TMP}/new.zm"
    grep -E 'ZIMBRASTART|ZIMBRAEND|/opt/zimbra' "$CUR_CRON" > "$ORIG_ZM" || true
    grep -E 'ZIMBRASTART|ZIMBRAEND|/opt/zimbra' "$NEW_CRON" > "$NEW_ZM" || true

    if cmp -s "$ORIG_ZM" "$NEW_ZM"; then
        if [ "${ZB_SKIP_USER_CHECK:-0}" = "1" ] || [ "$(id -un 2>/dev/null || echo '')" = "$ZIMBRA_USER" ]; then
            crontab "$NEW_CRON" || echo "WARNING: Could not update crontab for ${ZIMBRA_USER}." >&2
        else
            crontab -u "$ZIMBRA_USER" "$NEW_CRON" || echo "WARNING: Could not update crontab for ${ZIMBRA_USER}." >&2
        fi
    else
        echo "WARNING: Aborting crontab cleanup to protect Zimbra system cron entries." >&2
    fi

    rm -rf -- "$WORK_TMP" 2>/dev/null || true
}

clean_zimbra_crontab

# 3. Pre-clean runtime files inside STATE_DIR so RPM rmdir succeeds without
#    'Directory not empty' warnings (empty owned dirs are removed by RPM / %postun)
case "$STATE_DIR" in
    /var/lib/zimbra-backup|/tmp/zb_test.*/*)
        if [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]; then
            for sub in jobs logs run; do
                if [ -d "${STATE_DIR}/${sub}" ] && [ ! -L "${STATE_DIR}/${sub}" ]; then
                    find "${STATE_DIR}/${sub}" -mindepth 1 -exec rm -rf -- {} + 2>/dev/null || true
                fi
            done
            rm -f -- "${STATE_DIR}/settings.conf" "${STATE_DIR}/operation.lock" "${STATE_DIR}/cron.lock" 2>/dev/null || true
        fi
        ;;
esac

exit 0
