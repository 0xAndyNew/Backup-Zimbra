#!/usr/bin/env python3
"""Build zimbra-backup RPM package for v0.3.2."""

import gzip
import hashlib
import os
import struct
import subprocess
import time

VERSION = "0.3.2"
RELEASE = "1"
RPM_FILENAME = f"zimbra-backup-{VERSION}-{RELEASE}.noarch.rpm"
BUILD_TIME = 1730635200  # 2026-11-03 12:00:00 UTC (reproducible build)

# Files mapped from repository to RPM path
RPM_FILE_MAP = [
    ("./etc/logrotate.d/zimbra-backup", "packaging/zimbra-backup.logrotate", 0o100644, "root", "root"),
    ("./usr/bin/zimbra-backup", "bin/zimbra-backup", 0o100755, "root", "root"),
    ("./usr/libexec/zimbra-backup/backup.sh", "lib/backup.sh", 0o100644, "root", "root"),
    ("./usr/libexec/zimbra-backup/common.sh", "lib/common.sh", 0o100644, "root", "root"),
    ("./usr/libexec/zimbra-backup/jobs.sh", "lib/jobs.sh", 0o100644, "root", "root"),
    ("./usr/libexec/zimbra-backup/notify.sh", "lib/notify.sh", 0o100644, "root", "root"),
    ("./usr/libexec/zimbra-backup/restore.sh", "lib/restore.sh", 0o100644, "root", "root"),
    ("./usr/libexec/zimbra-backup/tui.sh", "lib/tui.sh", 0o100644, "root", "root"),
    ("./usr/libexec/zimbra-backup/zimbra_api.sh", "lib/zimbra_api.sh", 0o100644, "root", "root"),
    ("./var/lib/zimbra-backup", None, 0o40700, "zimbra", "zimbra"),
    ("./var/lib/zimbra-backup/jobs", None, 0o40700, "zimbra", "zimbra"),
    ("./var/lib/zimbra-backup/logs", None, 0o40700, "zimbra", "zimbra"),
    ("./var/lib/zimbra-backup/run", None, 0o40700, "zimbra", "zimbra"),
]

# Read original RPM from git to preserve exact tag structure
def get_template_rpm():
    return subprocess.check_output(['git', 'show', 'd9a109c:zimbra-backup-0.3.1-1.noarch.rpm'])


def parse_header(raw_data, offset):
    magic, reserved, nindex, ndata = struct.unpack('>4s4sII', raw_data[offset:offset+16])
    idx_off = offset + 16
    data_off = idx_off + nindex * 16
    entries = []
    for i in range(nindex):
        tag, ttype, toff, count = struct.unpack('>IIII', raw_data[idx_off+i*16:idx_off+(i+1)*16])
        val_off = data_off + toff
        # Extract raw value bytes
        entries.append((tag, ttype, toff, count, val_off))
    next_offset = data_off + ndata
    pad = (8 - (next_offset % 8)) % 8
    return entries, data_off, ndata, next_offset + pad


def serialize_header(entries_dict, is_sig=False):
    """Serialize a list/dict of (tag, ttype, value) into RPM header binary format."""
    nindex = len(entries_dict)

    # We must sort tags in ascending order per RPM spec (except immutable tag which is first)
    immutable_tag = 62 if is_sig else 63
    sorted_tags = sorted([t for t in entries_dict if t != immutable_tag])
    all_tags = [immutable_tag] + sorted_tags

    index_records = []
    data_bytes = bytearray()

    for tag in all_tags:
        ttype, val = entries_dict[tag]

        # Align data section if needed
        if ttype in (3,): # INT16
            pad = (2 - (len(data_bytes) % 2)) % 2
            data_bytes.extend(b'\x00' * pad)
        elif ttype in (4,): # INT32
            pad = (4 - (len(data_bytes) % 4)) % 4
            data_bytes.extend(b'\x00' * pad)
        elif ttype in (5,): # INT64
            pad = (8 - (len(data_bytes) % 8)) % 8
            data_bytes.extend(b'\x00' * pad)

        offset = len(data_bytes)

        if tag == immutable_tag:
            # 16-byte immutable tag record
            count = 16
            record_bytes = struct.pack('>iiii', immutable_tag, 7, -(nindex * 16), 16)
            data_bytes.extend(record_bytes)
        elif ttype == 6: # STRING
            count = 1
            data_bytes.extend(val.encode('utf-8') + b'\x00')
        elif ttype in (8, 9): # STRING_ARRAY / I18NSTRING
            count = len(val)
            for s in val:
                data_bytes.extend(s.encode('utf-8') + b'\x00')
        elif ttype == 4: # INT32
            count = len(val)
            for v in val:
                data_bytes.extend(struct.pack('>I', v))
        elif ttype == 3: # INT16
            count = len(val)
            for v in val:
                data_bytes.extend(struct.pack('>H', v))
        elif ttype == 7: # BIN
            count = len(val)
            data_bytes.extend(val)
        else:
            raise ValueError(f"Unsupported tag type {ttype} for tag {tag}")

        index_records.append((tag, ttype, offset, count))

    # Build header binary
    header_buf = bytearray()
    header_buf.extend(b'\x8e\xad\xe8\x01\x00\x00\x00\x00')
    header_buf.extend(struct.pack('>II', len(index_records), len(data_bytes)))
    for tag, ttype, offset, count in index_records:
        header_buf.extend(struct.pack('>IIII', tag, ttype, offset, count))
    header_buf.extend(data_bytes)
    return bytes(header_buf)


def build_cpio_archive(file_contents):
    """Build SVR4 (new ASCII) cpio archive."""
    buf = bytearray()
    ino = 1
    now = BUILD_TIME

    for rpath, src_path, mode, uname, gname in RPM_FILE_MAP:
        content = file_contents[rpath]
        filesize = len(content)
        name_bytes = rpath.encode('utf-8') + b'\x00'
        namesize = len(name_bytes)

        # Format cpio header (110 bytes ASCII hex)
        # magic (6): 070701
        # ino(8), mode(8), uid(8), gid(8), nlink(8), mtime(8), filesize(8),
        # devmajor(8), devminor(8), rdevmajor(8), rdevminor(8), namesize(8), check(8)
        uid = 0 if uname == "root" else 1000
        gid = 0 if gname == "root" else 1000
        nlink = 2 if mode & 0o40000 else 1

        hdr = (
            f"070701"
            f"{ino:08X}"
            f"{mode:08X}"
            f"{uid:08X}"
            f"{gid:08X}"
            f"{nlink:08X}"
            f"{now:08X}"
            f"{filesize:08X}"
            f"{0:08X}"
            f"{0:08X}"
            f"{0:08X}"
            f"{0:08X}"
            f"{namesize:08X}"
            f"{0:08X}"
        ).encode('ascii')

        buf.extend(hdr)
        buf.extend(name_bytes)
        # Pad to 4-byte boundary
        pad = (4 - (len(buf) % 4)) % 4
        buf.extend(b'\x00' * pad)

        if filesize > 0:
            buf.extend(content)
            pad = (4 - (len(buf) % 4)) % 4
            buf.extend(b'\x00' * pad)
        ino += 1

    # Trailer
    trailer_name = b"TRAILER!!!\x00"
    hdr = (
        f"070701"
        f"{0:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{1:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{0:08X}"
        f"{len(trailer_name):08X}"
        f"{0:08X}"
    ).encode('ascii')
    buf.extend(hdr)
    buf.extend(trailer_name)
    pad = (4 - (len(buf) % 4)) % 4
    buf.extend(b'\x00' * pad)
    return bytes(buf)


def main():
    print(f"[+] Loading files from working tree...")
    file_contents = {}
    file_digests = []
    file_sizes = []
    now = BUILD_TIME
    total_size = 0

    for rpath, src_path, mode, uname, gname in RPM_FILE_MAP:
        if src_path:
            with open(src_path, "rb") as f:
                content = f.read().replace(b"\r\n", b"\n")
        else:
            content = b""
        file_contents[rpath] = content
        file_sizes.append(len(content))
        total_size += len(content)
        file_digests.append(hashlib.sha256(content).hexdigest())

    print(f"[+] Building cpio archive and gzip payload...")
    cpio_raw = build_cpio_archive(file_contents)
    cpio_gz = gzip.compress(cpio_raw, compresslevel=9, mtime=0)
    print(f"    CPIO uncompressed: {len(cpio_raw)} bytes")
    print(f"    GZIP compressed:   {len(cpio_gz)} bytes")

    # Read template RPM and parse main header tags
    template_data = get_template_rpm()
    sig_entries, s_doff, s_ndata, off = parse_header(template_data, 96)
    main_entries, m_doff, m_ndata, p_off = parse_header(template_data, off)

    # Extract all existing tags from template main header
    main_dict = {}
    for tag, ttype, toff, count, val_off in main_entries:
        if tag == 63:
            main_dict[tag] = (7, None)
            continue
        if ttype == 6: # STRING
            end = template_data.find(b'\x00', val_off)
            val = template_data[val_off:end].decode('utf-8')
        elif ttype in (8, 9): # STRING_ARRAY
            val = []
            curr = val_off
            for _ in range(count):
                end = template_data.find(b'\x00', curr)
                val.append(template_data[curr:end].decode('utf-8'))
                curr = end + 1
        elif ttype == 4: # INT32
            val = list(struct.unpack(f'>{count}I', template_data[val_off:val_off+count*4]))
        elif ttype == 3: # INT16
            val = list(struct.unpack(f'>{count}H', template_data[val_off:val_off+count*2]))
        elif ttype == 7: # BIN
            val = template_data[val_off:val_off+count]
        else:
            raise ValueError(f"Tag {tag} unknown type {ttype}")
        main_dict[tag] = (ttype, val)

    # Update modified fields
    main_dict[1001] = (6, VERSION) # VERSION
    main_dict[1002] = (6, RELEASE) # RELEASE
    main_dict[1044] = (6, f"zimbra-backup-{VERSION}-{RELEASE}.src.rpm") # SOURCERPM
    main_dict[1113] = (8, [f"{VERSION}-{RELEASE}"]) # DIRINDEXES
    main_dict[1028] = (4, file_sizes) # FILESIZES
    main_dict[1035] = (8, file_digests) # FILEDIGESTS (SHA-256)
    main_dict[1009] = (4, [total_size]) # SIZE
    main_dict[1006] = (4, [now]) # BUILDTIME
    main_dict[1034] = (4, [now] * len(RPM_FILE_MAP)) # FILEMTIMES

    # Update PREIN, PREUN, POSTUN scripts with current packaging files
    with open("packaging/preinstall.sh", "r", encoding="utf-8") as f:
        main_dict[1023] = (6, f.read().replace("\r\n", "\n")) # PREIN
    with open("packaging/preremove.sh", "r", encoding="utf-8") as f:
        main_dict[1025] = (6, f.read().replace("\r\n", "\n")) # PREUN
    with open("packaging/postremove.sh", "r", encoding="utf-8") as f:
        main_dict[1026] = (6, f.read().replace("\r\n", "\n")) # POSTUN

    print(f"[+] Serializing main RPM header...")
    main_header_bytes = serialize_header(main_dict, is_sig=False)
    # 8-byte padding after main header if needed
    main_pad = (8 - (len(main_header_bytes) % 8)) % 8

    # Calculate hashes for signature header
    main_sha1 = hashlib.sha1(main_header_bytes).hexdigest()
    main_sha256 = hashlib.sha256(main_header_bytes).hexdigest()
    body_bytes = main_header_bytes + (b'\x00' * main_pad) + cpio_gz
    pkg_md5 = hashlib.md5(body_bytes).digest()

    # Build signature header
    sig_dict = {
        62: (7, None),
        269: (6, main_sha1),
        273: (6, main_sha256),
        1000: (4, [len(body_bytes)]), # Total payload size including main header
        1004: (7, pkg_md5),
        1007: (4, [len(cpio_raw)]), # Uncompressed CPIO size
    }
    print(f"[+] Serializing signature RPM header...")
    sig_header_bytes = serialize_header(sig_dict, is_sig=True)
    sig_pad = (8 - (len(sig_header_bytes) % 8)) % 8

    # Lead (96 bytes)
    lead = bytearray(template_data[:96])
    # Update name in lead (bytes 10..75 null-padded)
    pkg_name_lead = f"zimbra-backup-{VERSION}-{RELEASE}".encode('ascii')[:65]
    lead[10:10+len(pkg_name_lead)] = pkg_name_lead
    lead[10+len(pkg_name_lead):76] = b'\x00' * (66 - len(pkg_name_lead))

    print(f"[+] Assembling complete RPM package: {RPM_FILENAME}...")
    with open(RPM_FILENAME, "wb") as f:
        f.write(lead)
        f.write(sig_header_bytes)
        f.write(b'\x00' * sig_pad)
        f.write(main_header_bytes)
        f.write(b'\x00' * main_pad)
        f.write(cpio_gz)

    rpm_size = os.path.getsize(RPM_FILENAME)
    rpm_sha256 = hashlib.sha256(open(RPM_FILENAME, "rb").read()).hexdigest()
    print(f"[OK] Successfully built {RPM_FILENAME} ({rpm_size} bytes)")
    print(f"     SHA-256: {rpm_sha256}")


if __name__ == "__main__":
    main()
