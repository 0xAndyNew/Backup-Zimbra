#!/usr/bin/env bash
# Core utilities, configuration parser, privilege switching, locking, and storage guards.
# Compatible with Bash 4.2+ (CentOS/RHEL 7, 8, 9).

ZB_VERSION="0.3.11"
ZB_STATE_DIR="${ZB_STATE_DIR:-/var/lib/zimbra-backup}"
ZB_SETTINGS_FILE="$ZB_STATE_DIR/settings.conf"
ZB_JOBS_DIR="$ZB_STATE_DIR/jobs"
ZB_LOG_DIR="$ZB_STATE_DIR/logs"
ZB_RUN_DIR="$ZB_STATE_DIR/run"
ZB_LOCK_FILE="$ZB_STATE_DIR/operation.lock"
ZB_CRON_LOCK_FILE="$ZB_STATE_DIR/cron.lock"

ZB_ZIMBRA_HOME="${ZB_ZIMBRA_HOME:-/opt/zimbra}"
ZB_ZIMBRA_BIN="${ZB_ZIMBRA_BIN:-$ZB_ZIMBRA_HOME/bin}"
ZB_ZIMBRA_USER="${ZB_ZIMBRA_USER:-zimbra}"
ZB_SKIP_USER_CHECK="${ZB_SKIP_USER_CHECK:-0}"
ZB_SKIP_ZMSHUTIL="${ZB_SKIP_ZMSHUTIL:-0}"
ZB_BIN_PATH="${ZB_BIN_PATH:-/usr/bin/zimbra-backup}"

# Global settings defaults
DEFAULT_BACKUP_DIR="/home/backup"
CUSTOM_RESTORE_DIR=""
REQUIRE_MOUNTPOINT="no"
DISK_WARN_PERCENT="85"
DISK_MIN_FREE_MB="1024"
TELEGRAM_ENABLED="no"
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_THREAD_ID=""
EMAIL_ALERT_ENABLED="no"
EMAIL_ALERT_TO=""
EMAIL_ALERT_LEVEL="all"
HOST_LABEL=""
FTP_ENABLED="no"
FTP_PROTOCOL="ftp"
FTP_HOST=""
FTP_PORT="21"
FTP_USER=""
FTP_PASSWORD=""
FTP_REMOTE_DIR="/"
FTP_SSL="no"

ZB_CURRENT_LOG=""
ZB_LOCK_ACQUIRED=0
ZB_LOG_ACTIVE=0

zb_msg() { printf '%s\n' "$*"; }
zb_info() { printf '[INFO] %s\n' "$*"; }
zb_warn() { printf '[WARN] %s\n' "$*" >&2; }
zb_err() { printf '[ERROR] %s\n' "$*" >&2; return 1; }
zb_log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

zb_pause() {
    if [[ -t 0 ]]; then
        read -r -p 'Press Enter to continue... ' _ || true
    fi
}

zb_trim() {
    local s="${1-}"
    s="${s//$'\r'/}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

zb_sanitize_line() {
    local s="${1-}"
    s="${s//$'\r'/}"
    s="${s//$'\n'/ }"
    printf '%s' "$s"
}

zb_curl_escape() {
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

zb_human_bytes() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ")
        i = 1
        while (b >= 1024 && i < 5) { b = b / 1024; i++ }
        if (i == 1) printf "%d %s", b, u[i]
        else printf "%.2f %s", b, u[i]
    }'
}

zb_host_label() {
    if [[ -n "${HOST_LABEL:-}" ]]; then
        printf '%s' "$HOST_LABEL"
        return 0
    fi
    hostname -f 2>/dev/null || hostname 2>/dev/null || printf 'zimbra-host'
}

zb_ensure_utf8_ctype() {
    local cur_ctype="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$cur_ctype" in
        *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) return 0 ;;
    esac
    if [[ "${LC_ALL:-}" == "C" || "${LC_ALL:-}" == "POSIX" ]]; then
        export LANG="${LANG:-C}"
        unset LC_ALL
    fi
    if command -v locale >/dev/null 2>&1; then
        local avail pick=""
        avail="$(locale -a 2>/dev/null || true)"
        if printf '%s\n' "$avail" | grep -Eixq 'C\.utf-?8'; then
            pick="C.UTF-8"
        elif printf '%s\n' "$avail" | grep -Eixq 'en_US\.utf-?8'; then
            pick="en_US.UTF-8"
        else
            pick="$(printf '%s\n' "$avail" | grep -Ei '\.utf-?8$' | head -n 1 || true)"
        fi
        if [[ -n "$pick" ]]; then
            export LC_CTYPE="$pick"
        fi
    fi
}

zb_load_zimbra_env() {
    zb_ensure_utf8_ctype
    PATH="$ZB_ZIMBRA_BIN:$ZB_ZIMBRA_HOME/common/bin:$ZB_ZIMBRA_HOME/common/sbin:$ZB_ZIMBRA_HOME/libexec:$PATH"
    export PATH
    if [[ "$ZB_SKIP_ZMSHUTIL" != "1" && -f "$ZB_ZIMBRA_BIN/zmshutil" ]]; then
        # zmshutil references positional args without default; guard against set -u.
        set +u +e
        # shellcheck disable=SC1090,SC1091
        . "$ZB_ZIMBRA_BIN/zmshutil" >/dev/null 2>&1
        if declare -F zmsetvars >/dev/null 2>&1; then
            zmsetvars >/dev/null 2>&1
        fi
        set -eu
    fi
    zb_ensure_utf8_ctype
}

zb_require_zimbra() {
    if [[ "$ZB_SKIP_USER_CHECK" == "1" ]]; then
        zb_load_zimbra_env
        return 0
    fi
    local cur_user
    cur_user="$(id -un 2>/dev/null || printf '')"
    if [[ "$cur_user" == "$ZB_ZIMBRA_USER" ]]; then
        export HOME="$ZB_ZIMBRA_HOME"
        zb_load_zimbra_env
        return 0
    fi
    if (( EUID == 0 )); then
        id "$ZB_ZIMBRA_USER" >/dev/null 2>&1 || { zb_err "System user '$ZB_ZIMBRA_USER' not found (install Zimbra first)."; return 1; }
        if command -v runuser >/dev/null 2>&1; then
            exec runuser -u "$ZB_ZIMBRA_USER" -- "$0" "$@"
        else
            local quoted_cmd
            quoted_cmd="$(printf '%q ' "$0" "$@")"
            exec su - "$ZB_ZIMBRA_USER" -c "$quoted_cmd"
        fi
    fi
    zb_err "Please run this command as root or user '$ZB_ZIMBRA_USER'."
}

zb_ensure_state_dirs() {
    umask 077
    mkdir -p -m 700 -- "$ZB_STATE_DIR" "$ZB_JOBS_DIR" "$ZB_LOG_DIR" "$ZB_RUN_DIR" || {
        zb_err "Failed to initialize state directory: $ZB_STATE_DIR"
        return 1
    }
}

zb_normalize_dir_input() {
    local p
    p="$(zb_trim "${1:-}")"
    while [[ "$p" != "/" && "$p" == */ ]]; do
        p="${p%/}"
    done
    printf '%s' "$p"
}

zb_valid_safe_path() {
    local p="${1-}"
    [[ -n "$p" && "$p" =~ ^/[A-Za-z0-9._@+/-]+$ && "$p" != "/" && "$p" != *//* && "$p" != */ && "$p" != *..* ]]
}

zb_valid_subfolder_name() {
    local s="${1-}"
    [[ -n "$s" && "$s" =~ ^[A-Za-z0-9._/-]{1,128}$ && "$s" != /* && "$s" != */ && "$s" != *//* && "$s" != *..* ]]
}

zb_same_filesystem() {
    local p1="${1-}" p2="${2-}"
    [[ -e "$p1" && -e "$p2" ]] || return 1
    local d1 d2
    d1="$(df -P -- "$p1" 2>/dev/null | awk 'NR==2 {print $1}')" || return 1
    d2="$(df -P -- "$p2" 2>/dev/null | awk 'NR==2 {print $1}')" || return 1
    [[ -n "$d1" && "$d1" == "$d2" ]]
}

zb_valid_slug() {
    local s="${1-}"
    [[ "$s" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}$ ]]
}

zb_valid_email() {
    local e="${1-}"
    [[ "$e" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

zb_valid_domain() {
    local d="${1-}"
    [[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

zb_valid_cron_field() {
    local field="${1-}" min_v="${2:-0}" max_v="${3:-59}"
    [[ -n "$field" && "$field" =~ ^[0-9*,/-]+$ ]] || return 1
    local part base step lo hi
    local -a parts=()
    IFS=',' read -r -a parts <<< "$field"
    (( ${#parts[@]} > 0 )) || return 1
    for part in "${parts[@]}"; do
        [[ -n "$part" ]] || return 1
        step=""
        base="$part"
        if [[ "$part" == */* ]]; then
            base="${part%/*}"
            step="${part#*/}"
            [[ "$step" =~ ^[1-9][0-9]*$ ]] || return 1
        fi
        if [[ "$base" == "*" ]]; then
            continue
        elif [[ "$base" =~ ^[0-9]+$ ]]; then
            (( 10#$base >= min_v && 10#$base <= max_v )) || return 1
        elif [[ "$base" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            lo="${BASH_REMATCH[1]}"
            hi="${BASH_REMATCH[2]}"
            (( 10#$lo >= min_v && 10#$hi <= max_v && 10#$lo <= 10#$hi )) || return 1
        else
            return 1
        fi
    done
    return 0
}

zb_valid_cron_expr() {
    local expr="${1-}"
    local -a f=()
    IFS=' ' read -r -a f <<< "$expr"
    [[ "${#f[@]}" -eq 5 ]] || return 1
    zb_valid_cron_field "${f[0]}" 0 59 || return 1
    zb_valid_cron_field "${f[1]}" 0 23 || return 1
    zb_valid_cron_field "${f[2]}" 1 31 || return 1
    zb_valid_cron_field "${f[3]}" 1 12 || return 1
    zb_valid_cron_field "${f[4]}" 0 7 || return 1
    return 0
}

zb_is_initialized() {
    [[ -f "$ZB_SETTINGS_FILE" ]]
}

zb_reset_settings_defaults() {
    DEFAULT_BACKUP_DIR="/home/backup"
    CUSTOM_RESTORE_DIR=""
    REQUIRE_MOUNTPOINT="no"
    DISK_WARN_PERCENT="85"
    DISK_MIN_FREE_MB="1024"
    TELEGRAM_ENABLED="no"
    TELEGRAM_TOKEN=""
    TELEGRAM_CHAT_ID=""
    TELEGRAM_THREAD_ID=""
    EMAIL_ALERT_ENABLED="no"
    EMAIL_ALERT_TO=""
    EMAIL_ALERT_LEVEL="all"
    HOST_LABEL=""
    FTP_ENABLED="no"
    FTP_PROTOCOL="ftp"
    FTP_HOST=""
    FTP_PORT="21"
    FTP_USER=""
    FTP_PASSWORD=""
    FTP_REMOTE_DIR="/"
    FTP_SSL="no"
}

zb_validate_settings() {
    zb_valid_safe_path "$DEFAULT_BACKUP_DIR" || { zb_err "Invalid default backup directory path: $DEFAULT_BACKUP_DIR"; return 1; }
    if [[ -n "$CUSTOM_RESTORE_DIR" ]]; then
        zb_valid_safe_path "$CUSTOM_RESTORE_DIR" || { zb_err "Invalid custom restore directory path: $CUSTOM_RESTORE_DIR"; return 1; }
    fi
    [[ "$REQUIRE_MOUNTPOINT" == "yes" || "$REQUIRE_MOUNTPOINT" == "no" ]] || { zb_err "REQUIRE_MOUNTPOINT must be yes or no"; return 1; }
    [[ "$DISK_WARN_PERCENT" =~ ^([1-9]|[1-9][0-9])$ ]] || { zb_err "DISK_WARN_PERCENT must be between 1 and 99"; return 1; }
    [[ "$DISK_MIN_FREE_MB" =~ ^[0-9]{1,8}$ ]] || { zb_err "Invalid DISK_MIN_FREE_MB value"; return 1; }
    [[ "$TELEGRAM_ENABLED" == "yes" || "$TELEGRAM_ENABLED" == "no" ]] || { zb_err "TELEGRAM_ENABLED must be yes or no"; return 1; }
    [[ "$TELEGRAM_TOKEN" =~ ^[A-Za-z0-9_:-]*$ ]] || { zb_err "TELEGRAM_TOKEN contains invalid characters"; return 1; }
    [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]*$ ]] || { zb_err "Invalid TELEGRAM_CHAT_ID"; return 1; }
    [[ "$TELEGRAM_THREAD_ID" =~ ^[0-9]*$ ]] || { zb_err "Invalid TELEGRAM_THREAD_ID"; return 1; }
    [[ "$EMAIL_ALERT_ENABLED" == "yes" || "$EMAIL_ALERT_ENABLED" == "no" ]] || { zb_err "EMAIL_ALERT_ENABLED must be yes or no"; return 1; }
    [[ "$EMAIL_ALERT_LEVEL" == "all" || "$EMAIL_ALERT_LEVEL" == "failure" ]] || { zb_err "EMAIL_ALERT_LEVEL must be all or failure"; return 1; }
    if [[ -n "$EMAIL_ALERT_TO" ]]; then
        zb_valid_email "$EMAIL_ALERT_TO" || { zb_err "Invalid alert email address: $EMAIL_ALERT_TO"; return 1; }
    fi
    if [[ "$TELEGRAM_ENABLED" == "yes" ]]; then
        [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]] || { zb_err "TELEGRAM_ENABLED=yes requires both TELEGRAM_TOKEN and TELEGRAM_CHAT_ID"; return 1; }
    fi
    if [[ "$EMAIL_ALERT_ENABLED" == "yes" ]]; then
        [[ -n "$EMAIL_ALERT_TO" ]] || { zb_err "EMAIL_ALERT_ENABLED=yes requires EMAIL_ALERT_TO"; return 1; }
    fi
    [[ "$HOST_LABEL" =~ ^[A-Za-z0-9._-]*$ ]] || { zb_err "HOST_LABEL only allows letters, digits, dots, underscores, and hyphens"; return 1; }
    [[ "$FTP_ENABLED" == "yes" || "$FTP_ENABLED" == "no" ]] || { zb_err "FTP_ENABLED must be yes or no"; return 1; }
    [[ "$FTP_PROTOCOL" == "ftp" || "$FTP_PROTOCOL" == "sftp" ]] || { zb_err "FTP_PROTOCOL must be ftp or sftp"; return 1; }
    [[ "$FTP_PORT" =~ ^[0-9]{1,5}$ ]] && (( 10#$FTP_PORT >= 1 && 10#$FTP_PORT <= 65535 )) || { zb_err "FTP_PORT must be between 1 and 65535"; return 1; }
    [[ "$FTP_SSL" == "yes" || "$FTP_SSL" == "no" ]] || { zb_err "FTP_SSL must be yes or no"; return 1; }
    [[ "$FTP_PASSWORD" != *$'\n'* && "$FTP_PASSWORD" != *$'\r'* ]] || { zb_err "FTP_PASSWORD cannot contain newlines"; return 1; }
    if [[ "$FTP_ENABLED" == "yes" ]]; then
        [[ -n "$FTP_HOST" ]] || { zb_err "FTP_ENABLED=yes requires FTP_HOST"; return 1; }
        [[ "$FTP_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || { zb_err "FTP_HOST contains invalid characters"; return 1; }
        [[ -n "$FTP_USER" ]] || { zb_err "FTP_ENABLED=yes requires FTP_USER"; return 1; }
        [[ "$FTP_USER" =~ ^[A-Za-z0-9._%@+-]+$ ]] || { zb_err "FTP_USER contains invalid characters"; return 1; }
        [[ -n "$FTP_REMOTE_DIR" ]] || { zb_err "FTP_ENABLED=yes requires FTP_REMOTE_DIR"; return 1; }
        [[ "$FTP_REMOTE_DIR" =~ ^[A-Za-z0-9._/-]+$ ]] || { zb_err "FTP_REMOTE_DIR contains invalid characters"; return 1; }
    fi
    return 0
}

# Migrate legacy v0.1.0 /var/lib/zimbra-backup/settings automatically if settings.conf not created yet.
zb_load_settings() {
    zb_reset_settings_defaults
    local cfg_file="$ZB_SETTINGS_FILE"
    if [[ ! -f "$cfg_file" && -f "$ZB_STATE_DIR/settings" ]]; then
        cfg_file="$ZB_STATE_DIR/settings"
    fi
    [[ -f "$cfg_file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        [[ -z "$line" || "$line" == '#'* ]] && continue
        [[ "$line" == *=* ]] || { zb_err "Malformed configuration line: $line"; return 1; }
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            DEFAULT_BACKUP_DIR) DEFAULT_BACKUP_DIR="$value" ;;
            STORE_ROOT) DEFAULT_BACKUP_DIR="$value" ;; # legacy key alias
            CUSTOM_RESTORE_DIR|REQUIRE_MOUNTPOINT|DISK_WARN_PERCENT|DISK_MIN_FREE_MB|TELEGRAM_ENABLED|TELEGRAM_TOKEN|TELEGRAM_CHAT_ID|TELEGRAM_THREAD_ID|EMAIL_ALERT_ENABLED|EMAIL_ALERT_TO|EMAIL_ALERT_LEVEL|HOST_LABEL|FTP_ENABLED|FTP_PROTOCOL|FTP_HOST|FTP_PORT|FTP_USER|FTP_PASSWORD|FTP_REMOTE_DIR|FTP_SSL)
                printf -v "$key" '%s' "$value"
                ;;
            KEEP_FULL_COUNT|FULL_SCHEDULE|FULL_DAY|FULL_HOUR|FULL_MINUTE)
                # Ignore legacy v0.1.0 single-job keys safely
                ;;
            *)
                zb_err "Disallowed configuration key in $cfg_file: $key"
                return 1
                ;;
        esac
    done < "$cfg_file"
    zb_validate_settings
}

zb_save_settings() {
    zb_ensure_state_dirs || return 1
    zb_validate_settings || return 1
    local tmp
    tmp="$(mktemp "$ZB_STATE_DIR/.settings.XXXXXX")" || return 1
    {
        printf '# Zimbra Backup Global Configuration\n'
        printf 'DEFAULT_BACKUP_DIR=%s\n' "$DEFAULT_BACKUP_DIR"
        printf 'CUSTOM_RESTORE_DIR=%s\n' "$CUSTOM_RESTORE_DIR"
        printf 'REQUIRE_MOUNTPOINT=%s\n' "$REQUIRE_MOUNTPOINT"
        printf 'DISK_WARN_PERCENT=%s\n' "$DISK_WARN_PERCENT"
        printf 'DISK_MIN_FREE_MB=%s\n' "$DISK_MIN_FREE_MB"
        printf 'TELEGRAM_ENABLED=%s\n' "$TELEGRAM_ENABLED"
        printf 'TELEGRAM_TOKEN=%s\n' "$TELEGRAM_TOKEN"
        printf 'TELEGRAM_CHAT_ID=%s\n' "$TELEGRAM_CHAT_ID"
        printf 'TELEGRAM_THREAD_ID=%s\n' "$TELEGRAM_THREAD_ID"
        printf 'EMAIL_ALERT_ENABLED=%s\n' "$EMAIL_ALERT_ENABLED"
        printf 'EMAIL_ALERT_TO=%s\n' "$EMAIL_ALERT_TO"
        printf 'EMAIL_ALERT_LEVEL=%s\n' "$EMAIL_ALERT_LEVEL"
        printf 'HOST_LABEL=%s\n' "$HOST_LABEL"
        printf 'FTP_ENABLED=%s\n' "$FTP_ENABLED"
        printf 'FTP_PROTOCOL=%s\n' "$FTP_PROTOCOL"
        printf 'FTP_HOST=%s\n' "$FTP_HOST"
        printf 'FTP_PORT=%s\n' "$FTP_PORT"
        printf 'FTP_USER=%s\n' "$FTP_USER"
        printf 'FTP_PASSWORD=%s\n' "$FTP_PASSWORD"
        printf 'FTP_REMOTE_DIR=%s\n' "$FTP_REMOTE_DIR"
        printf 'FTP_SSL=%s\n' "$FTP_SSL"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$ZB_SETTINGS_FILE"
}

zb_check_no_symlinks() {
    local target="$1"
    local cur="$target"
    while [[ -n "$cur" && "$cur" != "/" ]]; do
        if [[ -L "$cur" ]]; then
            zb_err "Symlinks are not allowed in backup path: $cur"
            return 1
        fi
        cur="${cur%/*}"
    done
    return 0
}

zb_has_mounted_base() {
    local target="$1"
    local cur="$target"
    while [[ -n "$cur" && "$cur" != "/" ]]; do
        if [[ -d "$cur" ]] && mountpoint -q -- "$cur" 2>/dev/null; then
            return 0
        fi
        cur="${cur%/*}"
    done
    return 1
}

zb_check_backup_dir() {
    local dir="$1"
    local req_mount="${2:-$REQUIRE_MOUNTPOINT}"
    local create_if_missing="${3:-no}"

    zb_valid_safe_path "$dir" || { zb_err "Invalid backup directory path: $dir"; return 1; }
    zb_check_no_symlinks "$dir" || return 1

    if [[ "$req_mount" == "yes" ]]; then
        zb_has_mounted_base "$dir" || {
            zb_err "Backup path '$dir' (or its parent) is not a dedicated mountpoint. Mount the external disk/NFS first, or set REQUIRE_MOUNTPOINT=no for local folders."
            return 1
        }
    fi

    if [[ ! -d "$dir" ]]; then
        if [[ "$create_if_missing" == "yes" ]]; then
            mkdir -p -m 700 -- "$dir" || { zb_err "Failed to create backup directory: $dir"; return 1; }
        else
            zb_err "Backup directory does not exist: $dir"
            return 1
        fi
    fi

    [[ ! -L "$dir" ]] || { zb_err "Backup directory must not be a symlink: $dir"; return 1; }
    [[ -w "$dir" ]] || { zb_err "User '$ZB_ZIMBRA_USER' does not have write permission on: $dir (run: chown zimbra:zimbra $dir)"; return 1; }
    return 0
}

zb_check_disk_space() {
    local dir="$1"
    local warn_pct="${2:-$DISK_WARN_PERCENT}"
    local min_mb="${3:-$DISK_MIN_FREE_MB}"

    local df_line avail_mb used_pct
    df_line="$(df -Pm -- "$dir" 2>/dev/null | tail -n 1)" || return 0
    avail_mb="$(printf '%s\n' "$df_line" | awk '{print $4}')"
    used_pct="$(printf '%s\n' "$df_line" | awk '{gsub("%","",$5); print $5}')"

    if [[ "$used_pct" =~ ^[0-9]+$ ]] && (( used_pct >= warn_pct )); then
        zb_log "WARNING: Filesystem for '$dir' is ${used_pct}% full (warning threshold: ${warn_pct}%)."
    fi
    if [[ "$avail_mb" =~ ^[0-9]+$ && "$min_mb" =~ ^[0-9]+$ ]] && (( avail_mb < min_mb )); then
        zb_err "Insufficient free disk space on '$dir': ${avail_mb} MB available (minimum required: ${min_mb} MB)."
        return 1
    fi
    return 0
}

zb_acquire_lock() {
    zb_ensure_state_dirs || return 1
    local lock_file="${1:-$ZB_LOCK_FILE}"
    command -v flock >/dev/null 2>&1 || { zb_err "Command 'flock' not found (install util-linux)."; return 1; }
    exec 9>"$lock_file" || { zb_err "Cannot open lock file: $lock_file"; return 1; }
    if ! flock -n 9; then
        zb_err "Another backup or restore process is currently running (lock: $lock_file)."
        return 1
    fi
    ZB_LOCK_ACQUIRED=1
}

zb_start_run_log() {
    local prefix="${1:-run}"
    zb_ensure_state_dirs || return 1
    if [[ -d "$ZB_LOG_DIR" && ! -L "$ZB_LOG_DIR" ]]; then
        find "$ZB_LOG_DIR" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.gz' \) -mtime +90 -delete 2>/dev/null || true
    fi
    ZB_CURRENT_LOG="$ZB_LOG_DIR/${prefix}_$(date +%Y%m%d_%H%M%S)_$$.log"
    touch "$ZB_CURRENT_LOG"
    chmod 600 "$ZB_CURRENT_LOG"
    exec 7>&1 8>&2
    ZB_LOG_ACTIVE=1
    exec > >(tee -a "$ZB_CURRENT_LOG") 2>&1
}

zb_close_run_log() {
    if [[ "${ZB_LOG_ACTIVE:-0}" == "1" ]]; then
        ZB_LOG_ACTIVE=0
        exec 1>&7 2>&8 7>&- 8>&- 2>/dev/null || true
    fi
}
