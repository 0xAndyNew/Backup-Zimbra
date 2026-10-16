# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

This repository contains three original Bash scripts (`auto_full_backup.sh`, `auto_incr_backup.sh`, `restore_email.sh`) and an **unverified RPM prototype** (`zimbra-backup`, `zimbra-backup.spec`). A prototype RPM is built with nFPM but not installed or integration-tested; there is no runnable test suite or verified Zimbra 10 integration. Do not claim full-state incremental or production-ready restore from these sources. `README.md` describes the current scope and Linux build steps.

The original scripts are reference material, not packaged by the prototype. Both original backup scripts delete directories older than eight days before backup (`auto_full_backup.sh:14-15`, `auto_incr_backup.sh:16-17`). The original incremental script queries mail with `date:>=` for the current day (`auto_incr_backup.sh:43-44`), which is not a full-state delta from the last successful run. The original restore script reads metadata from paths that do not consistently match the full backup script and imports one backup directory rather than a chain. Treat these as compatibility and data-integrity issues, not mere packaging changes.

## Intended product model

An unattended RPM install followed by interactive configuration through `zimbra-backup` with four top-level areas: Backup, Restore, Backup information, Logs. Configuration belongs to the selected backup job; a job can later be viewed/edited. Two independent stores are required:

- `standalone-full/`: scheduled daily or weekly full backups, each independently restorable. User sets the number of completed copies to retain; user specifically chose removal of the oldest copy **before** a new backup, accepting that a failed new backup reduces the number of available copies.
- `incremental/base/` + `incremental/daily/`: one initial full baseline, then daily changes since the last successful checkpoint. No automatic deletion of the baseline or any delta, because removing a link breaks later restore. Full-state incremental (including deletions, moves, flags, and metadata) requires an edition/version-specific Zimbra 10 mechanism and end-to-end validation; currently **disabled**.

Manual account full backups live separately under `manual-accounts/` and are excluded from the standalone retention count. Telegram is optional. The storage root must be a mounted path, not an unmounted fallback directory.

## Prototype implementation

`zimbra-backup` is a single Bash entrypoint with configuration in `/var/lib/zimbra-backup/settings`, logs in `/var/lib/zimbra-backup/logs`, and a lock at `/var/lib/zimbra-backup/operation.lock`. It attempts standalone full exports, account-specific full exports, a one-time baseline export, count-based pre-backup pruning, cron management for the standalone job, and Telegram notices. It disables incremental and restore. Do not enable these by reusing the date-filtered export or by running the original restore script directly. A manifest and mailbox checksums do not prove the completeness of Zimbra metadata.

`nfpm.yaml` builds the prototype noarch binary RPM using nFPM (usable on the Windows build host). `zimbra-backup.spec` is an untested alternative source/binary RPM recipe for Linux `rpm-build`. The installed CLI path is `/usr/bin/zimbra-backup`; the package creates `/var/lib/zimbra-backup` owned by `zimbra`. No interactive configuration or cron entry is created by RPM install.

## Development commands (Linux)

```bash
bash -n zimbra-backup
```

```bash
shellcheck zimbra-backup
```

```bash
mkdir -p "$HOME/rpmbuild/SOURCES" zimbra-backup-0.1.0
cp zimbra-backup zimbra-backup-0.1.0/
tar czf "$HOME/rpmbuild/SOURCES/zimbra-backup-0.1.0.tar.gz" zimbra-backup-0.1.0
rpmbuild -ba zimbra-backup.spec
```

There is currently no test runner or single-test command. Add mock-backed shell tests before enabling destructive retention on production data; verify backup/restore against the exact Zimbra edition and version on an isolated server. On Windows, `bash -n zimbra-backup` passed and nFPM built `zimbra-backup-0.1.0-1.noarch.rpm`; neither `rpmbuild` nor Linux installation/integration tests have run.
