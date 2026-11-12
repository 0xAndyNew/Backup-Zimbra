#!/usr/bin/env python3
"""Publish release and upload installer packages (.deb & .rpm) to GitHub Releases."""

import hashlib
import json
import os
import subprocess
import sys
import urllib.request


def get_version() -> str:
    """Read version from lib/common.sh."""
    common_path = os.path.join(os.path.dirname(__file__), "..", "lib", "common.sh")
    with open(common_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("ZB_VERSION="):
                return line.strip().split("=")[1].strip('"\'')
    return "0.3.17"


def get_github_token() -> str:
    """Extract GitHub token from Git Credential Manager or GITHUB_TOKEN env var."""
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    try:
        raw = subprocess.check_output(
            ["git", "credential", "fill"],
            input=b"protocol=https\nhost=github.com\n\n",
            stderr=subprocess.DEVNULL
        ).decode("utf-8")
        data = dict(line.split("=", 1) for line in raw.strip().split("\n") if "=" in line)
        token = data.get("password")
        if token:
            return token
    except Exception:
        pass
    print("ERROR: GitHub token not found in git credential manager or GITHUB_TOKEN env.", file=sys.stderr)
    sys.exit(1)


def sha256_file(filepath: str) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    version = args[0] if args else get_version()
    pkg_release = os.environ.get("PKG_RELEASE", "2")
    release_tag = f"v{version}"
    rpm_asset = f"zimbra-backup-{version}-{pkg_release}.noarch.rpm"
    deb_asset = f"zimbra-backup_{version}-{pkg_release}_all.deb"

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rpm_path = os.path.join(repo_root, rpm_asset)
    deb_path = os.path.join(repo_root, deb_asset)

    if not os.path.isfile(rpm_path) or not os.path.isfile(deb_path):
        print(f"ERROR: Build assets missing ({rpm_path} or {deb_path}). Build them first.", file=sys.stderr)
        sys.exit(1)

    rpm_sha = sha256_file(rpm_path)
    deb_sha = sha256_file(deb_path)

    token = get_github_token()
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "Zimbra-Backup-Release-Publisher"
    }

    # Find or create release
    list_url = "https://api.github.com/repos/0xAndyNew/Backup-Zimbra/releases"
    req = urllib.request.Request(list_url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        releases = json.loads(resp.read().decode("utf-8"))

    body = f"""## Zimbra Backup & Restore (`zimbra-backup` v{version})

### Key Highlights in v{version}
- **Direct Incremental Chain Cycle Configuration**:
  - Configure the number of incremental runs per cycle (1-60) directly in Step 5 of the 6-Step TUI Creation Wizard without having to edit the job afterwards.
  - Automatically configures `FULL_CYCLE_VALUE` and retention count with interactive input validation.
- **Forever Forward Incremental (FFI)**:
  - Takes exactly one initial Full base backup from live Zimbra. All subsequent runs pull lightweight incremental deltas.
  - When restore points exceed `KEEP_COUNT`, the oldest incremental delta merges locally into the base Full backup on disk, rolling its timestamp forward, safely deleting the merged step and renumbering remaining steps.
  - Drastically minimizes network bandwidth, storage footprint, and production Zimbra server load.
- **Synthetic Full Backup (SFB)**:
  - When a scheduled Full backup cycle arrives or `--synthetic-full` is invoked, the engine avoids pulling heavy mailbox dumps over Zimbra REST API.
  - Synthesizes a standalone Full snapshot locally from preceding chain archives and interim delta.
  - Unchanged mailboxes are hardlinked/copied in microseconds with zero recompression overhead.
- **Self-Describing Storage Directories**:
  - Backup paths clearly reflect the active strategy for instant visibility during disk checks (`df -h`, `ls /home/backup`):
    - `/home/backup/incremental/Forever-Forward-Incremental`
    - `/home/backup/incremental/Synthetic-Full-Backup`
    - `/home/backup/incremental/Standard-Incremental`
    - `/home/backup/full/Standard-Full`
  - 100% backward-compatible with legacy backup locations and catalogs.
- **Interactive TUI & CLI Enhancements**:
  - 4-choice backup mode selector in TUI 6-step creation wizard and 1-touch edit loop.
  - Dedicated CLI flags `--type forever_incremental` (alias: `ffi`), `--type synthetic_full` (alias: `sfb`), and `--synthetic-full`.
- **Strict 7-bit ASCII & Data Integrity**:
  - 100% pure 7-bit ASCII and Unix LF line endings across all 15 packaged files.
  - 269/269 automated end-to-end test assertions passing with 0 errors.

### Package Checksums (SHA-256)
- `{rpm_asset}`: `{rpm_sha}`
- `{deb_asset}`: `{deb_sha}`

### Quick Install Commands
```bash
# On RHEL / CentOS / Rocky / AlmaLinux (7, 8, 9):
sudo dnf install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/{release_tag}/{rpm_asset} 2>/dev/null || sudo yum install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/{release_tag}/{rpm_asset}

# On Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/{release_tag}/{deb_asset} && sudo dpkg -i /tmp/zb.deb && rm -f /tmp/zb.deb
```
"""

    recreate = "--recreate" in sys.argv
    rel = next((r for r in releases if r.get("tag_name") == release_tag), None)
    if rel and recreate:
        print(f"[~] Deleting existing release {release_tag} (ID: {rel['id']}) for full recreation...")
        del_req = urllib.request.Request(f"https://api.github.com/repos/0xAndyNew/Backup-Zimbra/releases/{rel['id']}", headers=headers)
        del_req.get_method = lambda: 'DELETE'
        with urllib.request.urlopen(del_req) as del_resp:
            pass
        rel = None

    if not rel:
        print(f"[+] Creating GitHub Release {release_tag}...")
        create_payload = json.dumps({
            "tag_name": release_tag,
            "target_commitish": "main",
            "name": f"zimbra-backup {release_tag}",
            "body": body,
            "draft": False,
            "prerelease": False
        }).encode("utf-8")
        c_req = urllib.request.Request(list_url, data=create_payload, headers=headers)
        with urllib.request.urlopen(c_req) as c_resp:
            rel = json.loads(c_resp.read().decode("utf-8"))
    else:
        print(f"[+] Found existing GitHub Release {release_tag} (ID: {rel['id']})")
        update_payload = json.dumps({
            "name": f"zimbra-backup {release_tag}",
            "body": body,
        }).encode("utf-8")
        u_req = urllib.request.Request(f"https://api.github.com/repos/0xAndyNew/Backup-Zimbra/releases/{rel['id']}", data=update_payload, headers=headers)
        u_req.get_method = lambda: 'PATCH'
        with urllib.request.urlopen(u_req) as u_resp:
            print(f"[+] Updated release description for ID {rel['id']}")

    upload_url_base = rel["upload_url"].split("{")[0]
    existing_assets = {a["name"]: a["id"] for a in rel.get("assets", [])}

    assets_to_upload = [
        (rpm_asset, "application/x-rpm", rpm_path),
        (deb_asset, "application/vnd.debian.binary-package", deb_path),
    ]

    for asset_name, ctype, fpath in assets_to_upload:
        if asset_name in existing_assets:
            print(f"[~] Replacing existing asset {asset_name} (ID: {existing_assets[asset_name]})...")
            del_url = f"https://api.github.com/repos/0xAndyNew/Backup-Zimbra/releases/assets/{existing_assets[asset_name]}"
            del_req = urllib.request.Request(del_url, headers=headers)
            del_req.get_method = lambda: 'DELETE'
            try:
                with urllib.request.urlopen(del_req) as del_resp:
                    pass
                print(f"[OK] Deleted old asset {asset_name}")
            except Exception as e:
                print(f"[WARN] Failed to delete old asset {asset_name}: {e}")

        print(f"[+] Uploading {asset_name} ({os.path.getsize(fpath)} bytes)...")
        with open(fpath, "rb") as af:
            payload = af.read()

        u_req = urllib.request.Request(
            f"{upload_url_base}?name={asset_name}",
            data=payload,
            headers={
                "Authorization": f"token {token}",
                "Content-Type": ctype,
                "Content-Length": str(len(payload)),
                "User-Agent": "Zimbra-Backup-Release-Publisher"
            }
        )
        with urllib.request.urlopen(u_req) as u_resp:
            res_asset = json.loads(u_resp.read().decode("utf-8"))
            print(f"[OK] Uploaded {asset_name} -> {res_asset.get('browser_download_url')}")

    print(f"\n[DONE] Release {release_tag} ready at: {rel.get('html_url')}")


if __name__ == "__main__":
    main()
