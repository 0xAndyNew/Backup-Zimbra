# Zimbra Backup & Restore (`zimbra-backup` v0.3.8)

[![Release](https://img.shields.io/github/v/release/0xAndyNew/Backup-Zimbra?color=brightgreen&label=Release)](https://github.com/0xAndyNew/Backup-Zimbra/releases)
[![CI](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml/badge.svg)](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zimbra OSE](https://img.shields.io/badge/Zimbra_OSE-8.8.15_%7C_9_%7C_10-orange.svg)](https://www.zimbra.com/)
[![OS Support](https://img.shields.io/badge/OS-Ubuntu_%7C_RHEL_%7C_CentOS_%7C_Rocky_%7C_Alma-blue.svg)]()
[![Packages](https://img.shields.io/badge/Packages-RPM_%7C_DEB-success.svg)]()
[![Bash](https://img.shields.io/badge/Bash-4.2%2B-lightgrey.svg)]()
[![Encoding](https://img.shields.io/badge/Encoding-100%25_Pure_7--bit_ASCII-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-156%2F156_Passing-brightgreen.svg)]()

> 🌐 **[English Documentation](README_EN.md)** | **[Tài liệu Tiếng Việt](README.md)** | **[Hướng dẫn sử dụng chi tiết (VI)](HUONG_DAN_SU_DUNG.md)**

A unified, production-grade backup & restore solution packaged as `.rpm` and `.deb` for **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** on **Ubuntu 18.04, 20.04, 22.04 LTS** and **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**. Features a lightweight **100% pure 7-bit ASCII interactive TUI menu (zero font glitches on any SSH or VM console)**, comprehensive **CLI automation**, and an enterprise-grade safety confirmation mechanism (`--yes`).

---

## ⚡ Quick Install (1-Line Command)

### On RHEL / CentOS / Rocky Linux / AlmaLinux (7, 8, 9):
```bash
sudo dnf install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.8/zimbra-backup-0.3.8-1.noarch.rpm
# Or on CentOS / RHEL 7:
# sudo yum install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.8/zimbra-backup-0.3.8-1.noarch.rpm
```

### On Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
```bash
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.8/zimbra-backup_0.3.8-1_all.deb && sudo apt update && sudo apt install -y /tmp/zb.deb && rm -f /tmp/zb.deb
```

Launch the interactive management console:
```bash
zimbra-backup
```

---

## 🖥️ Interactive ASCII TUI Console

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.8) - mail.domain.com
  >> MAIN MENU
============================================================
  Job Storage : /home/backup (mount: no) | Jobs: 2 | Custom Restore: (not set)
------------------------------------------------------------
  1) Jobs & Crontab Schedule   (Create, Edit, Enable/Disable, Delete)
  2) Run Backup Now            (Run Job, Force Full, Single Account)
  3) Restore from Backup Job   (Select Configured Job -> Snapshot)
  4) Restore from Custom Dir   (Configure / Scan Other Directory)
  5) Backup Catalog & Verify   (Job Snapshots, Search Users, SHA-256)
  6) Global Settings & Alerts  (Storage, Disk Limits, Alerts)
  7) View Logs
  0) Exit
============================================================
Select [0-7]:
```

---

## 📊 Feature Comparison Matrix

| Core Feature | Generic Shell Scripts | Zimbra Network Edition ($$$) | `zimbra-backup` v0.3.8 |
|---|:---:|:---:|:---:|
| **License Cost** | Free | High Annual Subscription | **100% Free & Open Source (MIT)** |
| **Native Packages** | ❌ None (scattered files) | Included | **✅ Native RPM & DEB packages** |
| **Interactive TUI Console** | ❌ CLI only | Web Admin GUI | **✅ 1-touch ASCII TUI Menu** |
| **Remote Storage (FTP / SFTP)** | ❌ External script needed | ⚠️ Custom setup | **✅ Native Port 21/22 automated upload** |
| **Zero JVM Cold-Start** | ❌ Spawns Java repeatedly | Native Engine | **✅ Cached Token & In-Memory LDAP** |
| **Non-blocking Worker Pool** | ❌ Sequential execution | Supported | **✅ Concurrent multi-thread pool** |
| **Email & Telegram Alerts** | ⚠️ Basic or broken | Supported | **✅ Standardized comprehensive metrics** |
| **UTF-8 Diacritics Preservation** | ⚠️ Often corrupted | ✅ Supported | **✅ RFC 2849 Base64 decoding** |
| **Password & Global Admin Rights** | ❌ Often missed | ✅ Supported | **✅ SSHA/SHA512 hashes & Admin roles** |
| **Distribution Lists Backup** | ❌ Omitted | ✅ Supported | **✅ Attributes, Aliases & Members** |
| **Closed / Inactive Account Handling** | ❌ REST Inactive error | ✅ Supported | **✅ Deferred Account Status mechanism** |
| **Destructive Mode Safeguard** | ❌ Risky overwrites | Web Prompt | **✅ Strict `--yes` & `RESET` confirmation** |
| **Integrity Verification** | ⚠️ File size only | Supported | **✅ SHA-256 manifest per mailbox** |

---

## 🌟 Key Architecture & Capabilities (v0.3.8)

1. **Per-Job Remote Storage Configuration (FTP / SFTP)**:
   - Configured independently per job: choose whether each individual job replicates offsite (`[y/N]`), target remote server, port, credentials, and distinct remote directory (`/<job_id>`).
   - Seamless protocol support for standard FTP, explicit FTPS (SSL/TLS on port 21), and SFTP over SSH (port 22) powered by native `curl`.
   - **Strict Credential Isolation**: Remote passwords are transferred via ephemeral `0600` config files with `curl -K`, completely hidden from `ps aux` and process listings.

2. **Independent Remote Retention (`FTP_KEEP_COUNT`) & Automated Remote Pruning**:
   - Remote snapshot retention on FTP (`FTP_KEEP_COUNT`) is managed **completely independently** from local retention (`KEEP_COUNT`).
   - Automated remote pruning (`zb_prune_remote_storage`): scans remote job archives and automatically executes standard `DELE` (FTP) or `rm` (SFTP) commands to delete expired `.tar` and `.manifest` pairs.
   - **Zero Local Snapshot Deletion**: Remote backups serve as offsite disaster-recovery replicas. Local snapshots are never wiped upon upload and remain preserved according to the job's local `KEEP_COUNT`.

3. **Refined ASCII TUI & CLI Experience**:
   - **6-Step Job Creation Wizard**: Step 6 provides seamless interactive setup for Remote Storage and FTP retention count.
   - **1-Touch Job Editor (Fields 1..11)**: Option 11 enables instant modification of FTP credentials, protocol, path, and retention.
   - Cleaned up Menu 6 (Global Settings) to focus purely on local storage defaults, disk thresholds, and alert destinations.
   - Direct connection test CLI: `zimbra-backup notify test-ftp [job_id]`.

1. **Lightweight ASCII TUI & Streamlined First Run**:
   - Automatically initializes global configuration in the background with `/home/backup` as default storage.
   - **5-Step Job Wizard**: `Job ID` -> `Mode (Full / Incremental)` -> `Storage Path & Mountpoint Check` -> `Schedule (HH:MM)` -> `Retention & Parallel Workers`.
   - **1-Touch Job Editor**: Numbered fields `1..10` display current settings directly; press field number to update and `s` to save.
   - Built with **100% pure 7-bit ASCII** to guarantee zero character distortion (`□`) on remote SSH consoles, VM consoles, or `cron` environments (`LANG=C`).

2. **Automated Multi-Job & Crontab Management**:
   - Manages multiple concurrent jobs under isolated `flock` locks (`operation.lock`).
   - Automatically drops privileges to user `zimbra` (`runuser -u zimbra`) when executed as `root`.
   - Automatically synchronizes the `# BEGIN zimbra-backup ... # END zimbra-backup` crontab block without modifying Zimbra's core `# ZIMBRASTART..# ZIMBRAEND` jobs.

3. **Flexible Scheduling**:
   - Supports **Daily** (`HH:MM`), **Weekly** (select days `0-6` + `HH:MM`), **Monthly** (specific days `1-31` + `HH:MM`), custom **5-field Cron expressions**, or manual-only (`off`).

4. **Structured Storage Hierarchy**:
   - `full/<job_id>/backup-full-DD-MM-YYYY_HHMMSS/`
   - `incremental/<job_id>/chain-DD-MM-YYYY_HHMMSS/000_backup-full-...` & `001_backup-incremental-...`
   - `account/backup-<email>-DD-MM-YYYY_HHMMSS/` (ad-hoc single account backups)

5. **Complete Data & Metadata Preservation**:
   - **LDAP & Metadata**: Domains, accounts, password hashes (`userPassword`), display names (UTF-8), account quotas, email aliases, Distribution Lists (names, aliases, members), signatures (HTML & plain text), Sieve mail filters, and global admin roles (`zimbraIsAdminAccount TRUE`).
   - **Multi-valued Attributes**: Extended attributes (such as `zimbraMailForwardingAddress`) are preserved and restored with `+` prefix to prevent overwriting existing entries.
   - **Deferred Account Status**: Accounts backed up as `closed` are temporarily placed in `maintenance` status during mailbox restore to bypass Zimbra REST `account.ACCOUNT_INACTIVE` rejections, and restored to `closed` upon completion.

6. **Versatile Disaster Recovery**:
   - Restore **Full Server**, **By Domain**, or **Specific Accounts**.
   - Redirect restore to an **alternate destination mailbox** (`--target-user`).
   - Restore into an **isolated subfolder** (`--mode subfolder --subfolder-name <name>`).
   - Recursive scanning from any external drive, NAS, or legacy script directory.

---

## 📖 CLI Command Reference

Display full help:
```bash
zimbra-backup --help
```

### 1. Job Management:
```bash
# Add a nightly incremental job at 01:30 AM with weekly full cycles:
zimbra-backup job add daily-incr --type incremental --schedule daily --hour 1 --minute 30 --full-cycle weekly --full-cycle-value 0 --keep 2 --parallel 4

# Edit schedule to 02:00 AM:
zimbra-backup job edit daily-incr --hour 2 --minute 0

# Trigger job execution immediately:
zimbra-backup job run daily-incr
```

### 2. Ad-hoc Account Backup:
```bash
zimbra-backup backup user "ceo@domain.com,finance@domain.com"
```

### 3. Restore Scenarios:
```bash
# Restore an account with skip mode (preserves newly arrived emails):
zimbra-backup restore --from 1 --users "user@domain.com" --mode skip --yes

# Restore former employee's emails into a manager's subfolder:
zimbra-backup restore --from 1 --users "former_emp@domain.com" --target-user "manager@domain.com" --only mailbox --mode subfolder --subfolder-name "Handoff_Archive" --yes

# Full server disaster recovery from external storage (/mnt/nas):
zimbra-backup restore --dir /mnt/nas --from 1 --all --mode skip --yes
```

### 4. Alerting & Notification Testing:
```bash
# Test Email delivery through local MTA (Postfix / sendmail):
zimbra-backup notify test-email

# Test Telegram Bot alert:
zimbra-backup notify test-telegram
```

---

## 🛠️ Building from Source & Testing

Execute end-to-end automated test suite (149 tests):
```bash
bash tests/run_tests.sh
```

Build binary `.deb` and `.rpm` packages (requires Python 3):
```bash
python packaging/build_deb.py
python packaging/build_rpm.py
```

---

## ☕ Support the Project (Buy Me a Coffee)

If `zimbra-backup` has helped simplify your system administration tasks and protected your Zimbra mail server, consider supporting the maintenance and development of this project:

| 💎 USDT (BEP20) | 🪙 Bitcoin (BTC) |
|:---:|:---:|
| <img src="docs/images/donate-usdt-bsc.png" width="220" alt="USDT (BSC)"> | <img src="docs/images/donate-btc.png" width="220" alt="Bitcoin (BTC)"> |
| **BSC Network (BEP20)**<br>`0x1b1817cc4f6eb49adb051c25d0f82e77f66c8514` | **BTC Network**<br>`14enMJBiXgk7jLc187qXB5qucBBSfsYuVG` |

---

## 📄 License

Distributed under the [MIT License](LICENSE). Free for personal, commercial, and enterprise deployment.
