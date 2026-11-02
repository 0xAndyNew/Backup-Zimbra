#!/usr/bin/env bash
# Multi-job configuration CRUD, flexible calendar/cron builder, and safe zimbra crontab sync.
# Compatible with Bash 4.2+.

ZB_CRON_BEGIN="# BEGIN zimbra-backup (managed - do not edit manually)"
ZB_CRON_END="# END zimbra-backup"

ZB_KEEP_EXPLICIT=0
ZB_PARALLEL_EXPLICIT=0

zb_job_reset_defaults() {
    JOB_ID=""
    JOB_NAME=""
    ENABLED="yes"
    BACKUP_TYPE="full"            # full | incremental
    TARGET_DIR=""                 # empty => inherit DEFAULT_BACKUP_DIR
    JOB_REQUIRE_MOUNT="inherit"   # inherit | yes | no
    SCOPE_MODE="all"              # all | domains | accounts
    SCOPE_VALUES=""               # comma-separated domains or emails
    SCHEDULE_KIND="daily"         # daily | weekly | monthly | custom | off
    SCHED_MINUTE="0"
    SCHED_HOUR="2"
    SCHED_DOM="*"                 # e.g. 1,15 or 1-7
    SCHED_MONTH="*"               # e.g. * or 1,4,7,10
    SCHED_DOW="*"                 # e.g. 0 or 1-5
    CRON_EXPR="0 2 * * *"
    FULL_CYCLE_MODE="max_incr"    # max_incr | weekly | monthly
    FULL_CYCLE_VALUE="6"          # max_incr: 1..60 | weekly: 0..6 | monthly: 1..28
    KEEP_COUNT="7"                # full: snapshots kept | incremental: complete chains kept
    PRUNE_TIMING="after"          # after | before
    PARALLEL_JOBS="2"             # worker count 1..16
    CREATED_AT=""
    UPDATED_AT=""
}

zb_job_file() {
    local id="$1"
    printf '%s/%s.conf' "$ZB_JOBS_DIR" "$id"
}

zb_job_effective_target_dir() {
    if [[ -n "${TARGET_DIR:-}" ]]; then
        printf '%s' "$TARGET_DIR"
    else
        printf '%s' "$DEFAULT_BACKUP_DIR"
    fi
}

zb_job_category_dir() {
    if [[ "${BACKUP_TYPE:-full}" == "incremental" ]]; then
        printf 'incremental'
    else
        printf 'full'
    fi
}

zb_job_storage_root() {
    local base cat_dir base_leaf
    base="$(zb_job_effective_target_dir)"
    cat_dir="$(zb_job_category_dir)"
    base_leaf="${base##*/}"
    if [[ "${base_leaf,,}" == "$cat_dir" ]]; then
        printf '%s/%s' "$base" "$JOB_ID"
    else
        printf '%s/%s/%s' "$base" "$cat_dir" "$JOB_ID"
    fi
}

# Emit storage root `<effective_target_dir>/<full|incremental>/<job_id>` for one job ($1) or all configured jobs.
# When $2 == "1", also emits legacy `<effective_target_dir>/<job_id>` if present on disk for upgrade compatibility.
# Runs in a subshell so `zb_job_load` does not overwrite caller's JOB_* state.
zb_list_job_storage_roots() (
    local filter_jid="${1:-}"
    local include_legacy="${2:-0}"
    zb_load_settings || return 1

    _zb_emit_job_roots() {
        local primary legacy
        primary="$(zb_job_storage_root)"
        printf '%s\n' "$primary"
        if [[ "$include_legacy" == "1" ]]; then
            legacy="$(zb_job_effective_target_dir)/$JOB_ID"
            if [[ "$legacy" != "$primary" && -d "$legacy" ]]; then
                printf '%s\n' "$legacy"
            fi
        fi
    }

    if [[ -n "$filter_jid" ]]; then
        zb_job_load "$filter_jid" || return 1
        _zb_emit_job_roots
        return 0
    fi
    local jid
    while IFS= read -r jid; do
        [[ -n "$jid" ]] || continue
        if zb_job_load "$jid" >/dev/null 2>&1; then
            _zb_emit_job_roots
        fi
    done < <(zb_job_list_ids)
)

zb_job_build_cron_expr() {
    case "$SCHEDULE_KIND" in
        off)
            CRON_EXPR=""
            ;;
        daily)
            CRON_EXPR="${SCHED_MINUTE} ${SCHED_HOUR} * * *"
            ;;
        weekly)
            CRON_EXPR="${SCHED_MINUTE} ${SCHED_HOUR} * * ${SCHED_DOW}"
            ;;
        monthly)
            CRON_EXPR="${SCHED_MINUTE} ${SCHED_HOUR} ${SCHED_DOM} ${SCHED_MONTH} *"
            ;;
        custom)
            CRON_EXPR="$(zb_trim "$CRON_EXPR")"
            ;;
        *)
            zb_err "Invalid SCHEDULE_KIND: $SCHEDULE_KIND"
            return 1
            ;;
    esac
    return 0
}

zb_job_schedule_human() {
    case "$SCHEDULE_KIND" in
        off) printf 'Manual only (no cron)' ;;
        daily) printf 'Daily at %02d:%02d (%s)' "$SCHED_HOUR" "$SCHED_MINUTE" "$CRON_EXPR" ;;
        weekly) printf 'Weekly [DOW=%s] at %02d:%02d (%s)' "$SCHED_DOW" "$SCHED_HOUR" "$SCHED_MINUTE" "$CRON_EXPR" ;;
        monthly) printf 'Calendar [Day=%s Month=%s] at %02d:%02d (%s)' "$SCHED_DOM" "$SCHED_MONTH" "$SCHED_HOUR" "$SCHED_MINUTE" "$CRON_EXPR" ;;
        custom) printf 'Custom cron (%s)' "$CRON_EXPR" ;;
        *) printf '%s' "$CRON_EXPR" ;;
    esac
}

zb_validate_scope_values() {
    local mode="$1" csv="$2"
    if [[ "$mode" == "all" ]]; then
        return 0
    fi
    [[ -n "$csv" ]] || { zb_err "SCOPE_VALUES is required when SCOPE_MODE=$mode"; return 1; }
    local item
    local -a items=()
    IFS=',' read -r -a items <<< "$csv"
    (( ${#items[@]} > 0 )) || { zb_err "Empty SCOPE_VALUES list"; return 1; }
    for item in "${items[@]}"; do
        item="$(zb_trim "$item")"
        if [[ "$mode" == "domains" ]]; then
            zb_valid_domain "$item" || { zb_err "Invalid domain in scope: $item"; return 1; }
        elif [[ "$mode" == "accounts" ]]; then
            zb_valid_email "$item" || { zb_err "Invalid account email in scope: $item"; return 1; }
        fi
    done
    return 0
}

zb_job_validate() {
    zb_valid_slug "$JOB_ID" || { zb_err "Invalid JOB_ID '$JOB_ID' (allowed: letters, digits, '-', '_'; max 48 chars)."; return 1; }
    JOB_NAME="$(zb_sanitize_line "${JOB_NAME:-Backup $JOB_ID}")"
    [[ "$JOB_NAME" != *'$('* && "$JOB_NAME" != *'`'* ]] || { zb_err "JOB_NAME contains disallowed characters."; return 1; }
    [[ "$ENABLED" == "yes" || "$ENABLED" == "no" ]] || { zb_err "ENABLED must be yes or no."; return 1; }
    [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "incremental" ]] || { zb_err "BACKUP_TYPE must be full or incremental."; return 1; }

    if [[ -n "$TARGET_DIR" ]]; then
        zb_valid_safe_path "$TARGET_DIR" || { zb_err "Invalid TARGET_DIR path: $TARGET_DIR"; return 1; }
    fi
    [[ "$JOB_REQUIRE_MOUNT" == "inherit" || "$JOB_REQUIRE_MOUNT" == "yes" || "$JOB_REQUIRE_MOUNT" == "no" ]] || {
        zb_err "JOB_REQUIRE_MOUNT must be inherit, yes, or no."
        return 1
    }

    [[ "$SCOPE_MODE" == "all" || "$SCOPE_MODE" == "domains" || "$SCOPE_MODE" == "accounts" ]] || {
        zb_err "SCOPE_MODE must be all, domains, or accounts."
        return 1
    }
    zb_validate_scope_values "$SCOPE_MODE" "$SCOPE_VALUES" || return 1

    zb_job_build_cron_expr || return 1
    if [[ "$SCHEDULE_KIND" != "off" ]]; then
        zb_valid_cron_expr "$CRON_EXPR" || { zb_err "Invalid 5-field cron expression: '$CRON_EXPR'"; return 1; }
    fi

    case "$FULL_CYCLE_MODE" in
        max_incr)
            [[ "$FULL_CYCLE_VALUE" =~ ^([1-9]|[1-5][0-9]|60)$ ]] || { zb_err "FULL_CYCLE_VALUE (max incrementals per chain) must be 1..60."; return 1; }
            ;;
        weekly)
            [[ "$FULL_CYCLE_VALUE" =~ ^[0-6]$ ]] || { zb_err "FULL_CYCLE_VALUE (weekday for new Full chain) must be 0..6 (0=Sunday)."; return 1; }
            ;;
        monthly)
            [[ "$FULL_CYCLE_VALUE" =~ ^([1-9]|1[0-9]|2[0-8])$ ]] || { zb_err "FULL_CYCLE_VALUE (day of month for new Full chain) must be 1..28."; return 1; }
            ;;
        *)
            zb_err "FULL_CYCLE_MODE must be max_incr, weekly, or monthly."
            return 1
            ;;
    esac

    [[ "$KEEP_COUNT" =~ ^([1-9]|[1-9][0-9]{1,2})$ ]] || { zb_err "KEEP_COUNT must be an integer between 1 and 999."; return 1; }
    [[ "$PRUNE_TIMING" == "after" || "$PRUNE_TIMING" == "before" ]] || { zb_err "PRUNE_TIMING must be after or before."; return 1; }
    [[ "$PARALLEL_JOBS" =~ ^([1-9]|1[0-6])$ ]] || { zb_err "PARALLEL_JOBS must be between 1 and 16."; return 1; }
    return 0
}

zb_job_load() {
    local id="$1"
    zb_valid_slug "$id" || { zb_err "Invalid Job ID: $id"; return 1; }
    local f
    f="$(zb_job_file "$id")"
    [[ -f "$f" ]] || { zb_err "Job not found: $id"; return 1; }

    zb_job_reset_defaults
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        [[ -z "$line" || "$line" == '#'* ]] && continue
        [[ "$line" == *=* ]] || { zb_err "Malformed configuration line in $f: $line"; return 1; }
        key="${line%%=*}"
        value="${line#*=}"
        case "$key" in
            JOB_ID|JOB_NAME|ENABLED|BACKUP_TYPE|TARGET_DIR|JOB_REQUIRE_MOUNT|SCOPE_MODE|SCOPE_VALUES|SCHEDULE_KIND|SCHED_MINUTE|SCHED_HOUR|SCHED_DOM|SCHED_MONTH|SCHED_DOW|CRON_EXPR|FULL_CYCLE_MODE|FULL_CYCLE_VALUE|KEEP_COUNT|PRUNE_TIMING|PARALLEL_JOBS|CREATED_AT|UPDATED_AT)
                printf -v "$key" '%s' "$value"
                ;;
            *)
                zb_err "Disallowed key in $f: $key"
                return 1
                ;;
        esac
    done < "$f"

    JOB_ID="$id"
    zb_job_validate
}

zb_job_save() {
    zb_ensure_state_dirs || return 1
    local now
    now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    [[ -n "$CREATED_AT" ]] || CREATED_AT="$now"
    UPDATED_AT="$now"
    zb_job_validate || return 1

    local f tmp
    f="$(zb_job_file "$JOB_ID")"
    tmp="$(mktemp "$ZB_JOBS_DIR/.job.XXXXXX")" || return 1
    {
        printf '# Zimbra Backup Job Configuration\n'
        printf 'JOB_ID=%s\n' "$JOB_ID"
        printf 'JOB_NAME=%s\n' "$JOB_NAME"
        printf 'ENABLED=%s\n' "$ENABLED"
        printf 'BACKUP_TYPE=%s\n' "$BACKUP_TYPE"
        printf 'TARGET_DIR=%s\n' "$TARGET_DIR"
        printf 'JOB_REQUIRE_MOUNT=%s\n' "$JOB_REQUIRE_MOUNT"
        printf 'SCOPE_MODE=%s\n' "$SCOPE_MODE"
        printf 'SCOPE_VALUES=%s\n' "$SCOPE_VALUES"
        printf 'SCHEDULE_KIND=%s\n' "$SCHEDULE_KIND"
        printf 'SCHED_MINUTE=%s\n' "$SCHED_MINUTE"
        printf 'SCHED_HOUR=%s\n' "$SCHED_HOUR"
        printf 'SCHED_DOM=%s\n' "$SCHED_DOM"
        printf 'SCHED_MONTH=%s\n' "$SCHED_MONTH"
        printf 'SCHED_DOW=%s\n' "$SCHED_DOW"
        printf 'CRON_EXPR=%s\n' "$CRON_EXPR"
        printf 'FULL_CYCLE_MODE=%s\n' "$FULL_CYCLE_MODE"
        printf 'FULL_CYCLE_VALUE=%s\n' "$FULL_CYCLE_VALUE"
        printf 'KEEP_COUNT=%s\n' "$KEEP_COUNT"
        printf 'PRUNE_TIMING=%s\n' "$PRUNE_TIMING"
        printf 'PARALLEL_JOBS=%s\n' "$PARALLEL_JOBS"
        printf 'CREATED_AT=%s\n' "$CREATED_AT"
        printf 'UPDATED_AT=%s\n' "$UPDATED_AT"
    } > "$tmp"
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$f"
}

zb_job_list_ids() {
    zb_ensure_state_dirs || return 1
    local f base
    shopt -s nullglob
    for f in "$ZB_JOBS_DIR"/*.conf; do
        base="${f##*/}"
        printf '%s\n' "${base%.conf}"
    done | LC_ALL=C sort
    shopt -u nullglob
}

# Synchronize managed block into zimbra user's crontab without touching Zimbra's own entries.
zb_cron_sync() (
    zb_ensure_state_dirs || return 1
    command -v crontab >/dev/null 2>&1 || { zb_warn "Command 'crontab' not found; skipping cron sync."; return 0; }

    local cur_cron stripped new_cron
    cur_cron="$(mktemp "$ZB_RUN_DIR/.cron_cur.XXXXXX")" || return 1
    stripped="$(mktemp "$ZB_RUN_DIR/.cron_strip.XXXXXX")" || { rm -f -- "$cur_cron"; return 1; }
    new_cron="$(mktemp "$ZB_RUN_DIR/.cron_new.XXXXXX")" || { rm -f -- "$cur_cron" "$stripped"; return 1; }

    crontab -l > "$cur_cron" 2>/dev/null || : > "$cur_cron"
    awk -v b="$ZB_CRON_BEGIN" -v e="$ZB_CRON_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip { print }
    ' "$cur_cron" > "$stripped"

    cat "$stripped" > "$new_cron"
    # Ensure trailing newline before managed block if file non-empty
    if [[ -s "$new_cron" ]] && [[ "$(tail -c 1 "$new_cron" 2>/dev/null || true)" != "" ]]; then
        printf '\n' >> "$new_cron"
    fi

    local -a active_lines=()
    local jid
    while IFS= read -r jid; do
        [[ -n "$jid" ]] || continue
        if zb_job_load "$jid" >/dev/null 2>&1; then
            if [[ "$ENABLED" == "yes" && "$SCHEDULE_KIND" != "off" && -n "$CRON_EXPR" ]]; then
                active_lines+=("${CRON_EXPR} ${ZB_BIN_PATH} job run ${JOB_ID} --cron >/dev/null 2>&1")
            fi
        fi
    done < <(zb_job_list_ids)

    if (( ${#active_lines[@]} > 0 )); then
        {
            printf '%s\n' "$ZB_CRON_BEGIN"
            local ln
            for ln in "${active_lines[@]}"; do
                printf '%s\n' "$ln"
            done
            printf '%s\n' "$ZB_CRON_END"
        } >> "$new_cron"
    fi

    crontab "$new_cron" || {
        rm -f -- "$cur_cron" "$stripped" "$new_cron"
        zb_err "Failed to update crontab for user '$ZB_ZIMBRA_USER'."
        return 1
    }
    rm -f -- "$cur_cron" "$stripped" "$new_cron"
    return 0
)

zb_cron_print_managed() {
    command -v crontab >/dev/null 2>&1 || { zb_msg "(crontab command not installed)"; return 0; }
    local out
    out="$(crontab -l 2>/dev/null | awk -v b="$ZB_CRON_BEGIN" -v e="$ZB_CRON_END" '
        $0 == b { p = 1 }
        p { print }
        $0 == e { p = 0 }
    ')" || true
    if [[ -z "$out" ]]; then
        zb_msg "(No active zimbra-backup entries in crontab)"
    else
        printf '%s\n' "$out"
    fi
}

zb_job_print_summary_table() (
    zb_load_settings || return 1
    local -a ids=()
    local jid
    while IFS= read -r jid; do
        [[ -n "$jid" ]] && ids+=("$jid")
    done < <(zb_job_list_ids)

    if (( ${#ids[@]} == 0 )); then
        zb_msg "No backup jobs configured yet. Run 'zimbra-backup' -> Create Job, or 'zimbra-backup job add ...'."
        return 0
    fi

    printf '%-18s %-12s %-7s %-10s %-24s %s\n' "JOB ID" "MODE" "ACTIVE" "RETENTION" "STORAGE DIR" "SCHEDULE"
    printf '%s\n' "------------------------------------------------------------------------------------------------------------"
    for jid in "${ids[@]}"; do
        if zb_job_load "$jid"; then
            local keep_unit="snaps"
            [[ "$BACKUP_TYPE" == "incremental" ]] && keep_unit="chains"
            printf '%-18s %-12s %-7s %-10s %-24s %s\n' \
                "$JOB_ID" \
                "$BACKUP_TYPE" \
                "$ENABLED" \
                "${KEEP_COUNT} ${keep_unit}" \
                "$(zb_job_storage_root)" \
                "$(zb_job_schedule_human)"
        fi
    done
)

zb_job_print_detail() (
    local id="$1"
    zb_load_settings || return 1
    zb_job_load "$id" || return 1
    local keep_desc="${KEEP_COUNT} Full snapshots"
    if [[ "$BACKUP_TYPE" == "incremental" ]]; then
        keep_desc="${KEEP_COUNT} complete chains (each chain = 1 Full + Incrementals)"
    fi
    cat <<EOF
============================================================
JOB DETAILS: $JOB_ID
============================================================
  Description        : $JOB_NAME
  Schedule Enabled   : $ENABLED
  Backup Mode        : $BACKUP_TYPE
  Storage Directory  : $(zb_job_storage_root)  (Job override: ${TARGET_DIR:-inherit DEFAULT_BACKUP_DIR})
  Backup Scope       : $SCOPE_MODE ${SCOPE_VALUES:+($SCOPE_VALUES)}
  Schedule           : $(zb_job_schedule_human)
  Full Chain Cycle   : $FULL_CYCLE_MODE (value: $FULL_CYCLE_VALUE)
  Retention Policy   : $keep_desc (prune timing: $PRUNE_TIMING)
  Parallel Workers   : $PARALLEL_JOBS
  Created At (UTC)   : $CREATED_AT
  Updated At (UTC)   : $UPDATED_AT
============================================================
EOF
)

# CLI handler: `zimbra-backup init ...`
zb_cli_init() {
    zb_load_settings || true
    local create_dir="no"
    while (( $# > 0 )); do
        case "$1" in
            --backup-dir) DEFAULT_BACKUP_DIR="$(zb_normalize_dir_input "${2-}")"; shift 2 ;;
            --restore-dir)
                if [[ "${2-}" == "none" || "${2-}" == "-" ]]; then
                    CUSTOM_RESTORE_DIR=""
                else
                    CUSTOM_RESTORE_DIR="$(zb_normalize_dir_input "${2-}")"
                fi
                shift 2
                ;;
            --require-mount) REQUIRE_MOUNTPOINT="${2-}"; shift 2 ;;
            --disk-warn) DISK_WARN_PERCENT="${2-}"; shift 2 ;;
            --disk-min-mb) DISK_MIN_FREE_MB="${2-}"; shift 2 ;;
            --host-label) HOST_LABEL="${2-}"; shift 2 ;;
            --telegram-enabled) TELEGRAM_ENABLED="${2-}"; shift 2 ;;
            --telegram-token) TELEGRAM_TOKEN="${2-}"; shift 2 ;;
            --telegram-chat) TELEGRAM_CHAT_ID="${2-}"; shift 2 ;;
            --telegram-thread) TELEGRAM_THREAD_ID="${2-}"; shift 2 ;;
            --email-enabled) EMAIL_ALERT_ENABLED="${2-}"; shift 2 ;;
            --email-to) EMAIL_ALERT_TO="${2-}"; shift 2 ;;
            --create-dir) create_dir="yes"; shift ;;
            *) zb_err "Unknown init option: $1"; return 1 ;;
        esac
    done

    zb_validate_settings || return 1
    if [[ "$create_dir" == "yes" && "$REQUIRE_MOUNTPOINT" == "no" ]]; then
        mkdir -p -m 700 -- "$DEFAULT_BACKUP_DIR" || true
    fi
    if [[ -d "$DEFAULT_BACKUP_DIR" ]]; then
        zb_check_backup_dir "$DEFAULT_BACKUP_DIR" "$REQUIRE_MOUNTPOINT" "no" || return 1
    else
        zb_warn "Directory '$DEFAULT_BACKUP_DIR' does not exist yet; create or mount it before running backup jobs."
    fi
    zb_save_settings || return 1
    zb_info "Saved global configuration to $ZB_SETTINGS_FILE"
}

# Parse job CLI flags into current JOB_* variables (used by both `job add` and `job edit`)
zb_parse_job_flags() {
    ZB_KEEP_EXPLICIT=0
    ZB_PARALLEL_EXPLICIT=0
    while (( $# > 0 )); do
        case "$1" in
            --name) JOB_NAME="${2-}"; shift 2 ;;
            --enabled) ENABLED="${2-}"; shift 2 ;;
            --type) BACKUP_TYPE="${2-}"; shift 2 ;;
            --target-dir)
                if [[ "${2-}" == "default" || "${2-}" == "-" ]]; then
                    TARGET_DIR=""
                else
                    TARGET_DIR="$(zb_normalize_dir_input "${2-}")"
                fi
                shift 2
                ;;
            --require-mount) JOB_REQUIRE_MOUNT="${2-}"; shift 2 ;;
            --scope) SCOPE_MODE="${2-}"; shift 2 ;;
            --scope-values) SCOPE_VALUES="${2-}"; shift 2 ;;
            --schedule) SCHEDULE_KIND="${2-}"; shift 2 ;;
            --minute) SCHED_MINUTE="${2-}"; shift 2 ;;
            --hour) SCHED_HOUR="${2-}"; shift 2 ;;
            --dom) SCHED_DOM="${2-}"; shift 2 ;;
            --month) SCHED_MONTH="${2-}"; shift 2 ;;
            --dow) SCHED_DOW="${2-}"; shift 2 ;;
            --cron-expr) SCHEDULE_KIND="custom"; CRON_EXPR="${2-}"; shift 2 ;;
            --full-cycle) FULL_CYCLE_MODE="${2-}"; shift 2 ;;
            --full-cycle-value) FULL_CYCLE_VALUE="${2-}"; shift 2 ;;
            --keep) KEEP_COUNT="${2-}"; ZB_KEEP_EXPLICIT=1; shift 2 ;;
            --prune-timing) PRUNE_TIMING="${2-}"; shift 2 ;;
            --parallel) PARALLEL_JOBS="${2-}"; ZB_PARALLEL_EXPLICIT=1; shift 2 ;;
            *) zb_err "Unknown job option: $1"; return 1 ;;
        esac
    done
    return 0
}

zb_cli_job() {
    local action="${1:-list}"
    shift || true
    zb_load_settings || return 1

    case "$action" in
        list|ls)
            zb_job_print_summary_table
            ;;
        show|info)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job show <job_id>"; return 1; }
            zb_job_print_detail "$1"
            ;;
        add|create)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job add <job_id> [options]"; return 1; }
            local new_id="$1"
            shift
            zb_valid_slug "$new_id" || { zb_err "Invalid Job ID: $new_id"; return 1; }
            if [[ -f "$(zb_job_file "$new_id")" ]]; then
                zb_err "Job '$new_id' already exists. Use 'zimbra-backup job edit $new_id' to modify it."
                return 1
            fi
            zb_job_reset_defaults
            JOB_ID="$new_id"
            JOB_NAME="Scheduled backup $new_id"
            zb_parse_job_flags "$@" || return 1
            if [[ "$BACKUP_TYPE" == "incremental" ]]; then
                [[ "$ZB_KEEP_EXPLICIT" == "1" ]] || KEEP_COUNT="2"
                [[ "$ZB_PARALLEL_EXPLICIT" == "1" ]] || PARALLEL_JOBS="4"
            fi
            zb_job_save || return 1
            zb_cron_sync || return 1
            zb_info "Created job '$JOB_ID' and synchronized crontab."
            zb_job_print_detail "$JOB_ID"
            ;;
        edit|update)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job edit <job_id> [options]"; return 1; }
            local edit_id="$1"
            shift
            zb_job_load "$edit_id" || return 1
            zb_parse_job_flags "$@" || return 1
            if [[ "$SCOPE_MODE" == "all" ]]; then
                SCOPE_VALUES=""
            fi
            zb_job_save || return 1
            zb_cron_sync || return 1
            zb_info "Updated job '$JOB_ID' and synchronized crontab."
            zb_job_print_detail "$JOB_ID"
            ;;
        enable)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job enable <job_id>"; return 1; }
            zb_job_load "$1" || return 1
            ENABLED="yes"
            zb_job_save && zb_cron_sync
            zb_info "Enabled cron schedule for job '$JOB_ID'."
            ;;
        disable)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job disable <job_id>"; return 1; }
            zb_job_load "$1" || return 1
            ENABLED="no"
            zb_job_save && zb_cron_sync
            zb_info "Disabled cron schedule for job '$JOB_ID'."
            ;;
        delete|rm)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job delete <job_id> [--yes]"; return 1; }
            local del_id="$1"
            local confirm="${2:-}"
            zb_job_load "$del_id" || return 1
            if [[ "$confirm" != "--yes" && -t 0 ]]; then
                local ans=""
                read -r -p "Delete job configuration '$del_id' (existing backup data on disk is kept)? [y/N]: " ans
                [[ "$ans" =~ ^[Yy]$ ]] || { zb_info "Canceled."; return 0; }
            fi
            rm -f -- "$(zb_job_file "$del_id")"
            zb_cron_sync || return 1
            zb_info "Deleted job '$del_id' and removed its cron entry (backup data at $(zb_job_storage_root) was kept)."
            ;;
        run)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup job run <job_id> [--cron] [--force-full]"; return 1; }
            local run_id="$1"
            shift
            zb_run_job "$run_id" "$@"
            ;;
        *)
            zb_err "Unknown job subcommand: $action"
            return 1
            ;;
    esac
}
