Name:           zimbra-backup
Version:        0.2.0
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
if ! getent passwd zimbra >/dev/null 2>&1; then
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
* Mon Nov 02 2026 Zimbra Backup Maintainers <ops@localhost> - 0.2.0-1
- Unified Full & Chain-based Incremental backups, multi-job crontab sync, and granular restore
- Streamlined pure-ASCII English TUI for universal SSH/VM console compatibility
