#!/usr/bin/env python3
"""Publish release and upload installer packages (.deb & .rpm) to GitHub Releases."""

import hashlib
import json
import os
import subprocess
import sys
import urllib.request


def get_pkg_meta() -> tuple[str, str]:
    """Read ZB_VERSION and ZB_PKG_RELEASE from lib/common.sh."""
    version = "0.3.18"
    pkg_release = "1"
    common_path = os.path.join(os.path.dirname(__file__), "..", "lib", "common.sh")
    with open(common_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("ZB_VERSION="):
                version = line.strip().split("=", 1)[1].strip('"\'')
            elif line.startswith("ZB_PKG_RELEASE="):
                pkg_release = line.strip().split("=", 1)[1].strip('"\'')
    return version, pkg_release


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
    default_ver, default_rel = get_pkg_meta()
    version = args[0] if args else default_ver
    pkg_release = os.environ.get("PKG_RELEASE", default_rel)
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
    sha256sums_bytes = f"{rpm_sha}  {rpm_asset}\n{deb_sha}  {deb_asset}\n".encode("utf-8")

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
- **Built-in Version Check & Self-Update (`TUI 8` & `zimbra-backup update`)**:
  - Added `8) Check for Updates` in the Main TUI Menu and CLI `zimbra-backup update [--check] [--yes]`.
  - Compares installed package `VERSION-RELEASE` against the latest GitHub Release (with redirect + `SHA256SUMS` fallback if API rate-limited) and prompts `Update now? [y/N]` before making any changes.
  - Uses a root supervisor hand-off for the TUI, holds `operation.lock` during installation, verifies SHA-256 and package name metadata, and installs only the single package via `rpm -Uvh` / `dpkg -i` without touching OS repositories or Zimbra services.
- **Ubuntu Zero-APT Compatibility**:
  - Updated DEB dependencies (`mawk | gawk`) and standardized `awk` expressions to POSIX ERE so `dpkg -i` succeeds cleanly on Ubuntu 18.04 / 20.04 / 22.04 LTS without installing `gawk` or running `apt`.
- **Forever Forward Incremental (FFI) & Synthetic Full Backup (SFB)**:
  - Self-describing directories, local delta merge (FFI), and local Full synthesis (SFB) with zero live Zimbra JVM load.
- **Strict 7-bit ASCII & Data Integrity**:
  - 100% pure 7-bit ASCII and Unix LF line endings across all 16 packaged files.

### Package Checksums (SHA-256)
- `{rpm_asset}`: `{rpm_sha}`
- `{deb_asset}`: `{deb_sha}`
- Also published as `SHA256SUMS` release asset for automated verification.

### Quick Install / Upgrade Commands (Zero OS Repo / System Updates)
```bash
# On RHEL / CentOS / Rocky / AlmaLinux (7, 8, 9):
curl -fSL -o /tmp/zb.rpm https://github.com/0xAndyNew/Backup-Zimbra/releases/download/{release_tag}/{rpm_asset} && sudo rpm -Uvh /tmp/zb.rpm && rm -f /tmp/zb.rpm

# On Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/{release_tag}/{deb_asset} && sudo dpkg -i /tmp/zb.deb && rm -f /tmp/zb.deb
```

### Uninstall Commands
```bash
# RHEL / CentOS / Rocky / AlmaLinux:
sudo rpm -e zimbra-backup

# Ubuntu / Debian:
sudo dpkg -P zimbra-backup
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

    with open(rpm_path, "rb") as rf:
        rpm_bytes = rf.read()
    with open(deb_path, "rb") as df:
        deb_bytes = df.read()

    assets_to_upload = [
        (rpm_asset, "application/x-rpm", rpm_bytes),
        (deb_asset, "application/vnd.debian.binary-package", deb_bytes),
        ("SHA256SUMS", "text/plain", sha256sums_bytes),
    ]

    for asset_name, ctype, payload in assets_to_upload:
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

        print(f"[+] Uploading {asset_name} ({len(payload)} bytes)...")

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
