Name:           zimbra-backup
Version:        0.3.1
Release:        1%{?dist}
Summary:        Unified multi-job backup and granular restore manager for Zimbra OSE (8.8.15/9/10)
License:        MIT
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

Requires(pre):  shadow-utils
Requires:       bash >= 4.2
Requires:       coreutils
Requires:       findutils
Requires:       gawk
Requires:       grep
Requires:       sed
Requires:       tar
Requires:       gzip
Requires:       curl
Requires:       cronie
Requires:       util-linux

%description
Unified backup and restore package for Zimbra Collaboration Open Source Edition
(8.8.15, 9, and 10) on CentOS/RHEL/AlmaLinux/Rocky 7, 8, and 9.
Features a streamlined pure-ASCII English TUI and CLI automation, zimbra user
privilege enforcement, automatic crontab synchronization, full and chain-based
incremental backups, flexible calendar/cron scheduling, configurable retention,
SHA-256 verification, and granular restore (full server, domain, or selected users).

%prep
%setup -q

%build
# Shell-based noarch package

%pre
if ! (getent passwd zimbra >/dev/null 2>&1 || id zimbra >/dev/null 2>&1); then
    echo "ERROR: System user 'zimbra' not found. Install Zimbra Collaboration before zimbra-backup." >&2
    exit 1
fi

%install
install -D -m 0755 bin/zimbra-backup %{buildroot}%{_bindir}/zimbra-backup
install -D -m 0644 lib/common.sh %{buildroot}%{_libexecdir}/zimbra-backup/common.sh
install -D -m 0644 lib/notify.sh %{buildroot}%{_libexecdir}/zimbra-backup/notify.sh
install -D -m 0644 lib/zimbra_api.sh %{buildroot}%{_libexecdir}/zimbra-backup/zimbra_api.sh
install -D -m 0644 lib/jobs.sh %{buildroot}%{_libexecdir}/zimbra-backup/jobs.sh
install -D -m 0644 lib/backup.sh %{buildroot}%{_libexecdir}/zimbra-backup/backup.sh
install -D -m 0644 lib/restore.sh %{buildroot}%{_libexecdir}/zimbra-backup/restore.sh
install -D -m 0644 lib/tui.sh %{buildroot}%{_libexecdir}/zimbra-backup/tui.sh
install -D -m 0644 packaging/zimbra-backup.logrotate %{buildroot}%{_sysconfdir}/logrotate.d/zimbra-backup
install -d -m 0700 %{buildroot}%{_sharedstatedir}/zimbra-backup
install -d -m 0700 %{buildroot}%{_sharedstatedir}/zimbra-backup/jobs
install -d -m 0700 %{buildroot}%{_sharedstatedir}/zimbra-backup/logs
install -d -m 0700 %{buildroot}%{_sharedstatedir}/zimbra-backup/run

%preun
if [ "${1:-0}" -eq 0 ]; then
    STATE_DIR="%{_sharedstatedir}/zimbra-backup"
    LOCK_FILE="${STATE_DIR}/operation.lock"
    if [ -f "$LOCK_FILE" ] && [ ! -L "$LOCK_FILE" ] && command -v flock >/dev/null 2>&1; then
        if ! ( exec 9>"$LOCK_FILE" && flock -n 9 ) 2>/dev/null; then
            echo "ERROR: A zimbra-backup operation is currently running (${LOCK_FILE} is locked)." >&2
            echo "       Wait for it to finish before removing zimbra-backup." >&2
            exit 1
        fi
    fi
    if command -v crontab >/dev/null 2>&1 && (getent passwd zimbra >/dev/null 2>&1 || id zimbra >/dev/null 2>&1); then
        TMP_BASE="/tmp"
        if [ -d "${STATE_DIR}/run" ] && [ ! -L "${STATE_DIR}/run" ] && [ -w "${STATE_DIR}/run" ]; then
            TMP_BASE="${STATE_DIR}/run"
        fi
        WORK_TMP="$(mktemp -d "${TMP_BASE}/.zb_uninst.XXXXXX" 2>/dev/null || mktemp -d /tmp/.zb_uninst.XXXXXX)"
        if crontab -u zimbra -l > "${WORK_TMP}/cur.cron" 2>/dev/null; then
            if grep -Eq '^# BEGIN zimbra-backup([[:space:]]|$)' "${WORK_TMP}/cur.cron" || grep -Fq "zimbra-backup job run " "${WORK_TMP}/cur.cron"; then
                if grep -Eq '^# BEGIN zimbra-backup([[:space:]]|$)' "${WORK_TMP}/cur.cron" && grep -Eq '^# END zimbra-backup([[:space:]]|$)' "${WORK_TMP}/cur.cron"; then
                    awk 'index($0, "# BEGIN zimbra-backup") == 1 { skip = 1; next } index($0, "# END zimbra-backup") == 1 { skip = 0; next } !skip { print }' "${WORK_TMP}/cur.cron" > "${WORK_TMP}/new.cron"
                else
                    awk 'index($0, "# BEGIN zimbra-backup") == 1 || index($0, "# END zimbra-backup") == 1 || index($0, "/zimbra-backup job run ") > 0 { next } { print }' "${WORK_TMP}/cur.cron" > "${WORK_TMP}/new.cron"
                fi
                grep -E 'ZIMBRASTART|ZIMBRAEND|/opt/zimbra' "${WORK_TMP}/cur.cron" > "${WORK_TMP}/orig.zm" || true
                grep -E 'ZIMBRASTART|ZIMBRAEND|/opt/zimbra' "${WORK_TMP}/new.cron" > "${WORK_TMP}/new.zm" || true
                if cmp -s "${WORK_TMP}/orig.zm" "${WORK_TMP}/new.zm"; then
                    crontab -u zimbra "${WORK_TMP}/new.cron" 2>/dev/null || true
                fi
            fi
        fi
        rm -rf -- "$WORK_TMP" 2>/dev/null || true
    fi
    if [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ]; then
        for sub in jobs logs run; do
            if [ -d "${STATE_DIR}/${sub}" ] && [ ! -L "${STATE_DIR}/${sub}" ]; then
                find "${STATE_DIR}/${sub}" -mindepth 1 -exec rm -rf -- {} + 2>/dev/null || true
            fi
        done
        rm -f -- "${STATE_DIR}/settings.conf" "${STATE_DIR}/operation.lock" "${STATE_DIR}/cron.lock" 2>/dev/null || true
    fi
fi

%postun
if [ "${1:-0}" -eq 0 ]; then
    if [ -d "%{_sharedstatedir}/zimbra-backup" ] && [ ! -L "%{_sharedstatedir}/zimbra-backup" ]; then
        rm -rf -- "%{_sharedstatedir}/zimbra-backup"
    fi
    for ext in rpmsave rpmnew; do
        f="%{_sysconfdir}/logrotate.d/zimbra-backup.${ext}"
        if [ -f "$f" ] && [ ! -L "$f" ]; then
            rm -f -- "$f"
        fi
    done
    echo "[zimbra-backup] Uninstalled cleanly: removed managed cron entries and %{_sharedstatedir}/zimbra-backup."
    echo "[zimbra-backup] Zimbra mail services (/opt/zimbra) and backup data archives were NOT touched."
fi

%files
%doc README.md
%{_bindir}/zimbra-backup
%dir %{_libexecdir}/zimbra-backup
%{_libexecdir}/zimbra-backup/*.sh
%config(noreplace) %{_sysconfdir}/logrotate.d/zimbra-backup
%attr(0700,zimbra,zimbra) %dir %{_sharedstatedir}/zimbra-backup
%attr(0700,zimbra,zimbra) %dir %{_sharedstatedir}/zimbra-backup/jobs
%attr(0700,zimbra,zimbra) %dir %{_sharedstatedir}/zimbra-backup/logs
%attr(0700,zimbra,zimbra) %dir %{_sharedstatedir}/zimbra-backup/run

%changelog
* Mon Nov 02 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.1-1
- Harden system safety: close lock/log FDs in workers, throttle fallback zmmailbox JVMs, and cache LDAP lookups on restore
- Preserve locked/maintenance/closed user accounts while excluding system/calendar resource accounts
- Refresh expiring ZM_ADMIN_AUTH_TOKEN on long runs, support dual HTML+text signatures, and keep legacy LDIF restores read-only
- Harden crontab marker verification, UTF-8 locale under cron, logrotate cleanup, and TUI/CLI input validation

* Mon Nov 02 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.0-1
- Separate backup directories (full/, incremental/, account/) with DD-MM-YYYY_HHMMSS naming
- Require explicit Backup Storage Directory in TUI Create Job wizard and support recursive custom-dir restore
- Add clean one-command RPM uninstall hooks (%preun/%postun) with Zimbra cron and lock safety guards

* Sun Nov 01 2026 Zimbra Backup Maintainers <ops@localhost> - 0.2.0-1
- Unified Full & Chain-based Incremental backups, multi-job crontab sync, and granular restore
- Streamlined pure-ASCII English TUI for universal SSH/VM console compatibility
