#!/usr/bin/env python3
"""Build a standard Debian binary package (.deb) for zimbra-backup.

Debian packages use the classic BSD ar format containing:
  1. debian-binary  (text "2.0\n")
  2. control.tar.gz (control file, maintainer scripts, conffiles)
  3. data.tar.gz    (payload files)
"""

import gzip
import io
import os
import stat
import struct
import tarfile
import time

VERSION = "0.3.6-1"
PKG_NAME = "zimbra-backup"
DEB_FILENAME = f"{PKG_NAME}_{VERSION}_all.deb"
BUILD_TIME = 1730635200  # 2026-11-03 12:00:00 UTC (reproducible build)


def make_ar_header(name: str, size: int, mtime: int = BUILD_TIME, mode: int = 0o100644) -> bytes:
    """Format standard 60-byte ar header."""
    file_id = f"{name:<16}"
    mod_time = f"{mtime:<12}"
    owner_id = f"{0:<6}"
    group_id = f"{0:<6}"
    file_mode = f"{oct(mode)[2:]:<8}"
    file_size = f"{size:<10}"
    trailer = "`\n"
    header = f"{file_id}{mod_time}{owner_id}{group_id}{file_mode}{file_size}{trailer}".encode("ascii")
    if len(header) != 60:
        raise ValueError(f"ar header length is {len(header)}, expected 60")
    return header


def build_control_tar() -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        # 1. control
        control_content = f"""Package: {PKG_NAME}
Version: {VERSION}
Architecture: all
Maintainer: Zimbra Backup Maintainers <ops@localhost>
Section: admin
Priority: optional
Homepage: https://github.com/0xAndyNew/Backup-Zimbra
Depends: bash (>= 4.2), coreutils, findutils, gawk, grep, sed, tar, gzip, curl, cron, util-linux
Description: Unified backup and granular restore manager for Zimbra Collaboration OSE
 Provides streamlined pure-ASCII English TUI and automation CLI with multi-job crontab
 scheduling, chain-based incremental backups, SHA-256 manifest verification, and per-user restore.
 Compatible with Ubuntu 18.04, 20.04, 22.04 LTS and CentOS/RHEL/AlmaLinux/Rocky 7, 8, 9.
""".encode("utf-8")

        ti = tarfile.TarInfo(name="./control")
        ti.size = len(control_content)
        ti.mtime = BUILD_TIME
        ti.mode = 0o644
        ti.uname = "root"
        ti.gname = "root"
        tar.addfile(ti, io.BytesIO(control_content))

        # 2. conffiles
        conffiles = b"/etc/logrotate.d/zimbra-backup\n"
        ti = tarfile.TarInfo(name="./conffiles")
        ti.size = len(conffiles)
        ti.mtime = BUILD_TIME
        ti.mode = 0o644
        ti.uname = "root"
        ti.gname = "root"
        tar.addfile(ti, io.BytesIO(conffiles))

        # 3. preinst, prerm, postrm
        script_map = [
            ("./preinst", "packaging/preinstall.sh"),
            ("./prerm", "packaging/preremove.sh"),
            ("./postrm", "packaging/postremove.sh"),
        ]
        for tar_name, src_path in script_map:
            with open(src_path, "rb") as f:
                content = f.read().replace(b"\r\n", b"\n")
            ti = tarfile.TarInfo(name=tar_name)
            ti.size = len(content)
            ti.mtime = BUILD_TIME
            ti.mode = 0o755
            ti.uname = "root"
            ti.gname = "root"
            tar.addfile(ti, io.BytesIO(content))

    return gzip.compress(buf.getvalue(), compresslevel=9, mtime=BUILD_TIME)


def build_data_tar() -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
        # Directories
        dirs = [
            ("./usr", 0o755, "root", "root"),
            ("./usr/bin", 0o755, "root", "root"),
            ("./usr/libexec", 0o755, "root", "root"),
            ("./usr/libexec/zimbra-backup", 0o755, "root", "root"),
            ("./etc", 0o755, "root", "root"),
            ("./etc/logrotate.d", 0o755, "root", "root"),
            ("./var", 0o755, "root", "root"),
            ("./var/lib", 0o755, "root", "root"),
            ("./var/lib/zimbra-backup", 0o700, "zimbra", "zimbra"),
            ("./var/lib/zimbra-backup/jobs", 0o700, "zimbra", "zimbra"),
            ("./var/lib/zimbra-backup/logs", 0o700, "zimbra", "zimbra"),
            ("./var/lib/zimbra-backup/run", 0o700, "zimbra", "zimbra"),
        ]
        for name, mode, uname, gname in dirs:
            ti = tarfile.TarInfo(name=name)
            ti.type = tarfile.DIRTYPE
            ti.mode = mode
            ti.uname = uname
            ti.gname = gname
            ti.mtime = BUILD_TIME
            tar.addfile(ti)

        # Files
        files = [
            ("./usr/bin/zimbra-backup", "bin/zimbra-backup", 0o755, "root", "root"),
            ("./usr/libexec/zimbra-backup/common.sh", "lib/common.sh", 0o644, "root", "root"),
            ("./usr/libexec/zimbra-backup/notify.sh", "lib/notify.sh", 0o644, "root", "root"),
            ("./usr/libexec/zimbra-backup/zimbra_api.sh", "lib/zimbra_api.sh", 0o644, "root", "root"),
            ("./usr/libexec/zimbra-backup/jobs.sh", "lib/jobs.sh", 0o644, "root", "root"),
            ("./usr/libexec/zimbra-backup/backup.sh", "lib/backup.sh", 0o644, "root", "root"),
            ("./usr/libexec/zimbra-backup/restore.sh", "lib/restore.sh", 0o644, "root", "root"),
            ("./usr/libexec/zimbra-backup/tui.sh", "lib/tui.sh", 0o644, "root", "root"),
            ("./etc/logrotate.d/zimbra-backup", "packaging/zimbra-backup.logrotate", 0o644, "root", "root"),
        ]
        for tar_name, src_path, mode, uname, gname in files:
            with open(src_path, "rb") as f:
                content = f.read().replace(b"\r\n", b"\n")
            ti = tarfile.TarInfo(name=tar_name)
            ti.size = len(content)
            ti.mode = mode
            ti.uname = uname
            ti.gname = gname
            ti.mtime = BUILD_TIME
            tar.addfile(ti, io.BytesIO(content))

    return gzip.compress(buf.getvalue(), compresslevel=9, mtime=BUILD_TIME)


def main():
    print(f"[+] Assembling Debian package {DEB_FILENAME}...")
    control_gz = build_control_tar()
    data_gz = build_data_tar()
    deb_binary = b"2.0\n"

    with open(DEB_FILENAME, "wb") as deb:
        # Magic
        deb.write(b"!<arch>\n")

        # 1. debian-binary
        deb.write(make_ar_header("debian-binary", len(deb_binary)))
        deb.write(deb_binary)
        if len(deb_binary) % 2 != 0:
            deb.write(b"\n")

        # 2. control.tar.gz
        deb.write(make_ar_header("control.tar.gz", len(control_gz)))
        deb.write(control_gz)
        if len(control_gz) % 2 != 0:
            deb.write(b"\n")

        # 3. data.tar.gz
        deb.write(make_ar_header("data.tar.gz", len(data_gz)))
        deb.write(data_gz)
        if len(data_gz) % 2 != 0:
            deb.write(b"\n")

    size = os.path.getsize(DEB_FILENAME)
    print(f"[OK] Successfully built {DEB_FILENAME} ({size} bytes)")


if __name__ == "__main__":
    main()
