Name:           zimbra-backup
Version:        0.3.17
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
* Wed Nov 11 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.17-1
- Add Forever Forward Incremental (FFI) backup mode with automated delta merging, checkpoint rolling and step renumbering
- Add Synthetic Full Backup (SFB) mode with local mailbox archive synthesis without live Zimbra server load
- Implement self-describing backup storage directories (incremental/Forever-Forward-Incremental, incremental/Synthetic-Full-Backup)
- Update TUI 6-step creation wizard and edit loop with 4 backup modes and dynamic retention prompts
- Maintain 100% pure 7-bit ASCII and LF line endings across all 15 packaged files
- Pass all 238 automated end-to-end tests with 0 errors

* Tue Nov 10 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.16-1
- Support multiple email alert recipients separated by comma with semicolon normalization and trimming
- Enforce RFC 5322 validation and format To header for Postfix sendmail -t
- Update TUI Setup Wizard and CLI help for multi-recipient configuration
- Maintain 100% pure 7-bit ASCII and LF line endings across all 15 packaged files
- Pass all 233 automated end-to-end tests with 0 errors

* Mon Nov 09 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.15-1
- Sanitize Remote Storage notification formatting to prevent Microsoft 365 Defender Safe Links URL rewriting
- Align all notification card labels strictly to Column 16 with human-readable elapsed duration (seconds & minutes)
- Optimize signature export by detecting LDAP signature attributes before spawning zmprov gsig (eliminate 70 redundant JVMs)
- Maintain 100% pure 7-bit ASCII and LF line endings across all 15 packaged files

* Mon Nov 09 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.14-1
- Batch LDAP metadata export via zmprov -l -f (consolidate 140+ sequential JVM invocations into 1 single JVM command)
- Enforce strict SOAP 1.1 Envelope namespace and text/xml content-type for DelegateAuthRequest compliant with Zimbra SoapServlet
- Pre-detect and export ZB_REST_PORT, ZB_ADMIN_PORT, and ZB_SERVER_HOST preventing worker subshells from spawning redundant zmprov commands
- Settle high CPU load (drop from 93% to <3%) and accelerate total backup time by 25x (from 13.5m to <30s)
- Maintain 100% pure 7-bit ASCII and LF line endings across all 15 packaged files

* Mon Nov 09 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.13-1
- Fix 100% mailbox export failure caused by &auth=admin disabling cookie auth in Zimbra UserServlet (QP_AUTH)
- Implement zero-JVM native REST mailbox streaming via SOAP DelegateAuthRequest on port 7071
- Securely fetch delegated user tokens in ~10ms per account, streaming via curl with Cookie: ZM_AUTH_TOKEN
- Eliminate Java JVM startup storms during backups, reducing CPU load from 85%+ to <2% across all mailboxes
- Strictly serialize fallback zmmailbox execution via exclusive lock file (.jvm_worker.lock)
- Maintain 100% pure 7-bit ASCII and LF line endings across all 15 packaged files

* Mon Nov 09 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.12-1
- Fix high CPU utilization by correcting REST port detection to target mailbox UserServlet ports (8443, 443) instead of admin port 7071
- Include Host header, dual auth cookies (ZM_ADMIN_AUTH_TOKEN and ZM_AUTH_TOKEN), and auth=admin query parameter to enable 100% native curl REST streaming
- Prevent Java JVM cold-start CPU spikes by eliminating unnecessary zmmailbox CLI fallback
- Lower backup and restore process and I/O scheduling priority (nice 19, ionice class 2 priority 7) so production services are never starved
- Pass all 230 automated end-to-end tests with 0 errors and preserve 100% pure 7-bit ASCII and LF endings

* Sun Nov 08 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.11-1
- Flatten and shorten backup storage paths: full/full-DD-MM-YYYY, incremental/full-DD-MM-YYYY + incremental/NNN-incremental-DD-MM-YYYY, and account/backup-<email>-DD-MM-YYYY
- Preserve full backward compatibility for discovering, verifying, and restoring legacy directory layouts
- Fix chronological sorting of DD-MM-YYYY backup filenames across month boundaries during remote FTP/SFTP pruning and strip SFTP ls -l columns
- Escape backslashes and double quotes in FTP/SFTP credentials inside temporary curl -K config files
- Enhance notification design with structured ASCII card layout and metadata footer

* Fri Nov 06 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.10-1
- Prioritize Zimbra admin port 7071 over proxy 8443 for REST mailbox export with admin auth token
- Properly handle HTTP 204 No Content / zmmailbox status=204 as empty incremental delta instead of fatal failure
- Eliminate JVM process retry storm on unchanged mailboxes, reducing CPU load from 86% to <5%

* Thu Nov 05 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.9-1
- Add smart fallback for email sender From header when HOST_LABEL is configured as an IP address
- Enhance Telegram Bot error reporting with direct API descriptions (e.g. chat not found, bot permissions)
- Add comprehensive documentation and troubleshooting guide for .manifest files and notifications

* Thu Nov 05 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.8-1
- Shift FTP/SFTP remote storage configuration from global settings to per-job configuration
- Add per-job remote retention management (FTP_KEEP_COUNT) independent of local retention
- Implement automatic remote pruning (zb_prune_remote_storage) for full and incremental archives via DELE/rm and RMD/rmdir
- Preserve local backup snapshots completely intact (no local wipe) on remote upload
- Add Step 6 in Job Creation Wizard and Field 11 in Job Editor for remote storage
- Clean up Menu 6 to focus strictly on local global settings and alerts

* Thu Nov 05 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.7-1
- Add remote FTP and SFTP storage integration supporting port 21 and port 22 via curl -K
- Add dedicated Remote Storage configuration submenu in Menu 6 (Global Settings)
- Add 'notify test-ftp' CLI and TUI command for testing remote storage connectivity
- Standardize and enhance backup notifications across all jobs to report Job Name, Mode (FULL/INCREMENTAL), Accounts count, Total Size, Duration, and Remote FTP status

* Wed Nov 04 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.6-1
- Add EMAIL_ALERT_LEVEL setting ('all' vs 'failure') to support email notifications on successful backups
- Capture stderr and detailed exit codes on sendmail execution for improved mail delivery troubleshooting
- Add test email capability ('zimbra-backup notify test-email' and TUI Menu option 9)
- Hook notification dispatch into ad-hoc single/multi-account backups upon completion or failure
- Bump package version to v0.3.6

* Tue Nov 03 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.5-1
- Fix head-of-line blocking in parallel workers using non-blocking PID polling for Bash 4.2
- Cache admin auth token across operations to eliminate repeated JVM cold-starts
- Cache LDAP metadata (domains, accounts, DLs) during backup to avoid redundant zmprov queries
- Restore multi-valued LDAP attributes without overwriting by prefixing with +
- Selective integrity verification: check SHA-256 only for targeted restore accounts
- Require explicit --yes confirmation flag for non-interactive restore execution
- Bump package version to v0.3.5

* Tue Nov 03 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.4-1
- Automatically preserve and restore administrator privileges (zimbraIsAdminAccount) across all restore scopes
- Track and restore extended user attributes: forwarding, auto-reply, hideInGal, password flags, contact details
- Resilient per-attribute fallback on restore if bulk zmprov ma encounters unsupported attributes
- Deferred account status restoration for closed accounts to bypass REST ACCOUNT_INACTIVE errors while preserving locked and closed states
- Bump package version to v0.3.4

* Tue Nov 03 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.3-1
- Eliminate blocking first-run setup wizard; initialize defaults silently in background
- Move 'Require dedicated mounted disk/NFS' option into Job Storage Directory wizard
- Set default REQUIRE_MOUNTPOINT to 'no' for hassle-free local directory setups
- Fix RPM immutable header region trailer placement to prevent headerRead tag mismatch

* Tue Nov 03 2026 Zimbra Backup Maintainers <ops@localhost> - 0.3.2-1
- Comprehensive Distribution List (group) backup and restore: preserve displayName (UTF-8), status, hideInGal, notes, policies, owner, and reply-to attributes
- Preserve Distribution List aliases (zmprov adla) and member forward addresses (zmprov adlm)
- Two-pass Distribution List restoration (cdl -> mdl -> adla -> adlm) handling nested groups cleanly
- Strictly isolate distribution lists from user mailboxes to prevent zmprov ga NO_SUCH_ACCOUNT failures

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
