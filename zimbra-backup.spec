Name:           zimbra-backup
Version:        0.1.0
Release:        1%{?dist}
Summary:        Interactive Zimbra standalone full backup manager
License:        Unspecified
# Replace with the actual project license before publishing the RPM.
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz
Requires:       bash, coreutils, findutils, tar, gzip, curl, util-linux, cronie, gawk
Requires(pre):  shadow-utils
%description
Menu-driven standalone full backup management for Zimbra. This package also
allows a one-time initial full export for a future incremental workflow.
Full-state incremental backup is NOT implemented or claimed to work: the
original date-filtered REST script cannot capture all Zimbra state changes.

%prep
%setup -q

%build
bash -n zimbra-backup

%install
install -Dpm 0755 zimbra-backup %{buildroot}%{_bindir}/zimbra-backup
install -d -m 0700 %{buildroot}%{_sharedstatedir}/zimbra-backup/logs

%pre
getent passwd zimbra >/dev/null || { echo 'Zimbra user is required' >&2; exit 1; }

%files
%{_bindir}/zimbra-backup
%dir %attr(0700,zimbra,zimbra) %{_sharedstatedir}/zimbra-backup
%dir %attr(0700,zimbra,zimbra) %{_sharedstatedir}/zimbra-backup/logs

%changelog
* Fri Oct 16 2026 Zimbra Backup Project <backup@example.invalid> - 0.1.0-1
- Initial RPM skeleton; incremental full-state mode deliberately disabled
