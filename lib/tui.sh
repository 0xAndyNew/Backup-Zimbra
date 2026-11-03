#!/usr/bin/env bash
# Streamlined Interactive English TUI (100% pure 7-bit ASCII for universal SSH/VM console rendering).
# Compatible with Bash 4.2+.

zb_tui_header() {
    local subtitle="${1:-}"
    if [[ -t 1 ]]; then
        clear 2>/dev/null || true
    fi
    zb_msg "============================================================"
    zb_msg "  ZIMBRA BACKUP & RESTORE MANAGER (v${ZB_VERSION}) - $(zb_host_label)"
    if [[ -n "$subtitle" ]]; then
        zb_msg "  >> $subtitle"
    fi
    zb_msg "============================================================"
}

zb_tui_prompt_default() {
    local prompt_text="$1"
    local default_val="$2"
    local ans=""
    if [[ -n "$default_val" ]]; then
        read -r -p "${prompt_text} [${default_val}]: " ans || true
        ans="$(zb_trim "$ans")"
        printf '%s' "${ans:-$default_val}"
    else
        read -r -p "${prompt_text}: " ans || true
        zb_trim "$ans"
    fi
}

zb_tui_prompt_yesno() {
    local prompt_text="$1"
    local default_yn="${2:-yes}" # yes | no
    local hint="[Y/n]"
    [[ "$default_yn" == "no" ]] && hint="[y/N]"
    local ans=""
    while true; do
        read -r -p "${prompt_text} ${hint}: " ans || return 1
        ans="$(zb_trim "$ans")"
        if [[ -z "$ans" ]]; then
            printf '%s' "$default_yn"
            return 0
        fi
        case "${ans,,}" in
            y|yes) printf 'yes'; return 0 ;;
            n|no) printf 'no'; return 0 ;;
            *) zb_warn "Please enter y (yes) or n (no)." ;;
        esac
    done
}

# Single-step HH:MM 24h time prompt (accepts HH:MM, H:M, or HH -> HH:00)
zb_tui_prompt_time() {
    local cur_fmt
    cur_fmt="$(printf '%02d:%02d' "$SCHED_HOUR" "$SCHED_MINUTE")"
    local raw h m
    while true; do
        raw="$(zb_tui_prompt_default "Run time HH:MM (24h)" "$cur_fmt")"
        if [[ "$raw" =~ ^([0-9]{1,2}):([0-9]{1,2})$ ]]; then
            h="${BASH_REMATCH[1]}"
            m="${BASH_REMATCH[2]}"
        elif [[ "$raw" =~ ^([0-9]{1,2})$ ]]; then
            h="${BASH_REMATCH[1]}"
            m="0"
        else
            zb_warn "Invalid time format. Enter HH:MM (e.g. 02:00 or 23:30)."
            continue
        fi
        if (( 10#$h >= 0 && 10#$h <= 23 && 10#$m >= 0 && 10#$m <= 59 )); then
            SCHED_HOUR="$((10#$h))"
            SCHED_MINUTE="$((10#$m))"
            return 0
        fi
        zb_warn "Hour must be 0..23 and minute must be 0..59."
    done
}

zb_tui_edit_advanced_settings() {
    DISK_WARN_PERCENT="$(zb_tui_prompt_default "Disk usage warning threshold (%)" "$DISK_WARN_PERCENT")"
    DISK_MIN_FREE_MB="$(zb_tui_prompt_default "Minimum free disk space required (MB)" "$DISK_MIN_FREE_MB")"
    HOST_LABEL="$(zb_tui_prompt_default "Server label in alerts (blank = hostname)" "$HOST_LABEL")"

    TELEGRAM_ENABLED="$(zb_tui_prompt_yesno "Enable Telegram Bot alerts?" "$TELEGRAM_ENABLED")"
    if [[ "$TELEGRAM_ENABLED" == "yes" ]]; then
        TELEGRAM_TOKEN="$(zb_tui_prompt_default "  Telegram Bot Token" "$TELEGRAM_TOKEN")"
        TELEGRAM_CHAT_ID="$(zb_tui_prompt_default "  Telegram Chat ID" "$TELEGRAM_CHAT_ID")"
        TELEGRAM_THREAD_ID="$(zb_tui_prompt_default "  Topic Thread ID (blank if none)" "$TELEGRAM_THREAD_ID")"
    fi

    EMAIL_ALERT_ENABLED="$(zb_tui_prompt_yesno "Enable Email alerts on failure?" "$EMAIL_ALERT_ENABLED")"
    if [[ "$EMAIL_ALERT_ENABLED" == "yes" ]]; then
        EMAIL_ALERT_TO="$(zb_tui_prompt_default "  Alert recipient email" "$EMAIL_ALERT_TO")"
    fi
}

# Streamlined First-Run Setup: 2 core prompts + optional advanced alerts
zb_tui_first_run_wizard() {
    zb_load_settings || true
    zb_tui_header "QUICK INITIAL SETUP"
    zb_msg "Welcome! Configure your default backup storage in 2 quick steps."
    zb_msg ""

    while true; do
        DEFAULT_BACKUP_DIR="$(zb_tui_prompt_default "1. Default backup directory" "$DEFAULT_BACKUP_DIR")"
        DEFAULT_BACKUP_DIR="$(zb_normalize_dir_input "$DEFAULT_BACKUP_DIR")"
        if ! zb_valid_safe_path "$DEFAULT_BACKUP_DIR"; then
            zb_warn "Invalid path (use an absolute path like /home/backup or /backup, no spaces)."
            continue
        fi

        local mount_default="no"
        if zb_has_mounted_base "$DEFAULT_BACKUP_DIR"; then
            mount_default="yes"
        fi
        zb_msg "   (Tip: Choose 'yes' for external disk/NFS/SAN, or 'no' for a normal local folder)"
        REQUIRE_MOUNTPOINT="$(zb_tui_prompt_yesno "2. Require dedicated mounted disk/NFS?" "$mount_default")"

        if [[ ! -d "$DEFAULT_BACKUP_DIR" && "$REQUIRE_MOUNTPOINT" == "no" ]]; then
            local mk
            mk="$(zb_tui_prompt_yesno "   Directory '$DEFAULT_BACKUP_DIR' does not exist. Create it now?" "yes")"
            if [[ "$mk" == "yes" ]]; then
                mkdir -p -m 700 -- "$DEFAULT_BACKUP_DIR" || zb_warn "Could not create $DEFAULT_BACKUP_DIR (check permissions for user zimbra)."
            fi
        elif [[ "$REQUIRE_MOUNTPOINT" == "yes" ]] && ! zb_has_mounted_base "$DEFAULT_BACKUP_DIR"; then
            zb_warn "Note: '$DEFAULT_BACKUP_DIR' is not currently mounted. Mount your disk before running a job."
        fi

        local adv
        adv="$(zb_tui_prompt_yesno "Configure advanced settings (disk thresholds / Telegram / Email alerts) now?" "no")"
        if [[ "$adv" == "yes" ]]; then
            zb_tui_edit_advanced_settings
        fi

        if zb_save_settings; then
            zb_info "Saved global settings to $ZB_SETTINGS_FILE"
            break
        fi
    done

    zb_msg ""
    local create_first
    create_first="$(zb_tui_prompt_yesno "Create your first scheduled backup job now?" "yes")"
    if [[ "$create_first" == "yes" ]]; then
        zb_tui_job_create
    fi
}

# Interactive schedule builder (single HH:MM time prompt)
zb_tui_configure_schedule() {
    local cur_choice="1"
    case "$SCHEDULE_KIND" in
        daily) cur_choice="1" ;;
        weekly) cur_choice="2" ;;
        monthly) cur_choice="3" ;;
        custom) cur_choice="4" ;;
        off) cur_choice="5" ;;
    esac

    zb_msg "Schedule Options (Zimbra Crontab):"
    zb_msg "  1) Daily   - Every day at HH:MM"
    zb_msg "  2) Weekly  - Selected weekday(s) at HH:MM"
    zb_msg "  3) Monthly - Specific day(s)/month(s) at HH:MM"
    zb_msg "  4) Custom  - Raw 5-field cron expression"
    zb_msg "  5) Manual  - Off (run manually only)"
    local sc
    sc="$(zb_tui_prompt_default "Select schedule (1-5)" "$cur_choice")"
    case "$sc" in
        1)
            SCHEDULE_KIND="daily"
            zb_tui_prompt_time
            ;;
        2)
            SCHEDULE_KIND="weekly"
            [[ "$SCHED_DOW" == "*" ]] && SCHED_DOW="0"
            SCHED_DOW="$(zb_tui_prompt_default "Day of week (0=Sun, 1=Mon..6=Sat, e.g. 0 or 1-5)" "$SCHED_DOW")"
            zb_tui_prompt_time
            ;;
        3)
            SCHEDULE_KIND="monthly"
            [[ "$SCHED_DOM" == "*" ]] && SCHED_DOM="1"
            SCHED_DOM="$(zb_tui_prompt_default "Day of month (1-31, e.g. 1 or 1,15)" "$SCHED_DOM")"
            SCHED_MONTH="$(zb_tui_prompt_default "Month (* = every month, or 1-12 e.g. 1,4,7,10)" "$SCHED_MONTH")"
            zb_tui_prompt_time
            ;;
        4)
            SCHEDULE_KIND="custom"
            CRON_EXPR="$(zb_tui_prompt_default "5-field cron expression (MIN HOUR DOM MON DOW)" "$CRON_EXPR")"
            ;;
        5)
            SCHEDULE_KIND="off"
            ;;
        *)
            zb_warn "Invalid choice; keeping Daily schedule."
            SCHEDULE_KIND="daily"
            zb_tui_prompt_time
            ;;
    esac
    zb_job_build_cron_expr || true
}

zb_tui_edit_backup_mode() {
    local cur="1"
    [[ "$BACKUP_TYPE" == "incremental" ]] && cur="2"
    zb_msg "Backup Mode:"
    zb_msg "  1) full        - Standalone full backup every run (simple, self-contained)"
    zb_msg "  2) incremental - Chain: 1 Full base + daily Incrementals (saves disk & time)"
    local t
    t="$(zb_tui_prompt_default "Select mode (1/2)" "$cur")"
    if [[ "$t" == "2" || "${t,,}" == "incremental" ]]; then
        if [[ "$BACKUP_TYPE" != "incremental" ]]; then
            BACKUP_TYPE="incremental"
            # Switch smart defaults when changing from full -> incremental
            [[ "$KEEP_COUNT" == "7" ]] && KEEP_COUNT="2"
            [[ "$PARALLEL_JOBS" == "2" ]] && PARALLEL_JOBS="4"
        fi
    else
        BACKUP_TYPE="full"
    fi
}

zb_tui_edit_retention() {
    local k_in
    while true; do
        if [[ "$BACKUP_TYPE" == "incremental" ]]; then
            zb_msg "Note: For Incremental mode, 1 chain = 1 Full base + ${FULL_CYCLE_VALUE} Incremental runs."
            k_in="$(zb_tui_prompt_default "Keep how many COMPLETE CHAINS?" "$KEEP_COUNT")"
        else
            k_in="$(zb_tui_prompt_default "Keep how many FULL snapshots?" "$KEEP_COUNT")"
        fi
        if [[ "$k_in" =~ ^([1-9]|[1-9][0-9]{1,2})$ ]]; then
            KEEP_COUNT="$k_in"
            break
        fi
        zb_warn "Invalid retention count '$k_in'. Enter an integer between 1 and 999."
    done
}

zb_tui_edit_full_cycle() {
    zb_msg "Full Chain Cycle (when to start a fresh Full base):"
    zb_msg "  1) After N Incremental runs (recommended: 6 -> 1 Full + 6 Incr = 7 days/chain)"
    zb_msg "  2) Weekly on a fixed weekday (0=Sun .. 6=Sat)"
    zb_msg "  3) Monthly on a fixed day (1..28)"
    local fc="1"
    [[ "$FULL_CYCLE_MODE" == "weekly" ]] && fc="2"
    [[ "$FULL_CYCLE_MODE" == "monthly" ]] && fc="3"
    fc="$(zb_tui_prompt_default "Select cycle (1-3)" "$fc")"
    case "$fc" in
        2)
            FULL_CYCLE_MODE="weekly"
            [[ "$FULL_CYCLE_VALUE" =~ ^[0-6]$ ]] || FULL_CYCLE_VALUE="0"
            FULL_CYCLE_VALUE="$(zb_tui_prompt_default "Weekday to start new Full chain (0=Sun..6=Sat)" "$FULL_CYCLE_VALUE")"
            ;;
        3)
            FULL_CYCLE_MODE="monthly"
            [[ "$FULL_CYCLE_VALUE" =~ ^([1-9]|1[0-9]|2[0-8])$ ]] || FULL_CYCLE_VALUE="1"
            FULL_CYCLE_VALUE="$(zb_tui_prompt_default "Day of month to start new Full chain (1-28)" "$FULL_CYCLE_VALUE")"
            ;;
        *)
            FULL_CYCLE_MODE="max_incr"
            [[ "$FULL_CYCLE_VALUE" =~ ^([1-9]|[1-5][0-9]|60)$ ]] || FULL_CYCLE_VALUE="6"
            FULL_CYCLE_VALUE="$(zb_tui_prompt_default "Max Incremental runs before new Full (1-60)" "$FULL_CYCLE_VALUE")"
            ;;
    esac
}

zb_tui_edit_scope() {
    zb_msg "Backup Scope:"
    zb_msg "  1) All active accounts on server (recommended)"
    zb_msg "  2) Specific domain(s) only"
    zb_msg "  3) Specific email account(s) only"
    local sc="1"
    [[ "$SCOPE_MODE" == "domains" ]] && sc="2"
    [[ "$SCOPE_MODE" == "accounts" ]] && sc="3"
    sc="$(zb_tui_prompt_default "Select scope (1-3)" "$sc")"
    case "$sc" in
        2)
            SCOPE_MODE="domains"
            SCOPE_VALUES="$(zb_tui_prompt_default "Domain list (comma-separated, e.g. corp.vn,sub.corp.vn)" "$SCOPE_VALUES")"
            ;;
        3)
            SCOPE_MODE="accounts"
            SCOPE_VALUES="$(zb_tui_prompt_default "Email list (comma-separated, e.g. a@corp.vn,b@corp.vn)" "$SCOPE_VALUES")"
            ;;
        *)
            SCOPE_MODE="all"
            SCOPE_VALUES=""
            ;;
    esac
}

zb_tui_edit_prune_timing() {
    zb_msg "Prune Timing (when to delete expired backups):"
    zb_msg "  1) after  - Delete oldest AFTER new backup succeeds (safe, recommended)"
    zb_msg "  2) before - Delete oldest BEFORE running new backup (for low disk space)"
    local p="1"
    [[ "$PRUNE_TIMING" == "before" ]] && p="2"
    p="$(zb_tui_prompt_default "Select timing (1/2)" "$p")"
    if [[ "$p" == "2" || "${p,,}" == "before" ]]; then
        PRUNE_TIMING="before"
    else
        PRUNE_TIMING="after"
    fi
}

# Prompt and validate backup storage directory for a Job (creates folder or adjusts local mount override if needed)
zb_tui_prompt_job_storage_dir() {
    local allow_inherit="${1:-0}"
    local default_shown prompt_lbl dir_in
    default_shown="${TARGET_DIR:-$DEFAULT_BACKUP_DIR}"
    if [[ "$allow_inherit" == "1" ]]; then
        prompt_lbl="Backup storage directory ('default' = inherit $DEFAULT_BACKUP_DIR)"
    else
        prompt_lbl="Backup storage directory"
    fi

    while true; do
        dir_in="$(zb_tui_prompt_default "$prompt_lbl" "$default_shown")"
        dir_in="$(zb_normalize_dir_input "$dir_in")"
        if [[ "$allow_inherit" == "1" && ( "$dir_in" == "default" || "$dir_in" == "-" ) ]]; then
            TARGET_DIR=""
            JOB_REQUIRE_MOUNT="inherit"
            dir_in="$DEFAULT_BACKUP_DIR"
        else
            if ! zb_valid_safe_path "$dir_in"; then
                zb_warn "Invalid path '$dir_in'. Enter an absolute path (e.g. /home/backup or /backup, no spaces)."
                continue
            fi
            if ! zb_check_no_symlinks "$dir_in"; then
                continue
            fi
            TARGET_DIR="$dir_in"
        fi

        zb_msg "   -> Snapshots for job '$JOB_ID' will be saved in: $(zb_job_storage_root)"

        local mount_def="no"
        if zb_has_mounted_base "$dir_in"; then
            mount_def="yes"
        fi
        if [[ "${JOB_REQUIRE_MOUNT:-}" == "yes" ]]; then
            mount_def="yes"
        elif [[ "${JOB_REQUIRE_MOUNT:-}" == "no" ]]; then
            mount_def="no"
        fi

        zb_msg "   (Tip: Choose 'yes' for external disk/NFS/SAN, or 'no' for a normal local folder)"
        local req_ans
        req_ans="$(zb_tui_prompt_yesno "   Require dedicated mounted disk/NFS for this job?" "$mount_def")"
        JOB_REQUIRE_MOUNT="$req_ans"

        if [[ "$JOB_REQUIRE_MOUNT" == "yes" ]] && ! zb_has_mounted_base "$dir_in"; then
            zb_warn "Note: '$dir_in' is not currently mounted. Mount your disk before running job '$JOB_ID'."
        fi

        if [[ ! -d "$dir_in" && "$JOB_REQUIRE_MOUNT" == "no" ]]; then
            local mk
            mk="$(zb_tui_prompt_yesno "   Directory '$dir_in' does not exist. Create it now?" "yes")"
            if [[ "$mk" == "yes" ]]; then
                mkdir -p -m 700 -- "$dir_in" 2>/dev/null || mkdir -p -- "$dir_in" 2>/dev/null || true
                if [[ -d "$dir_in" && -w "$dir_in" ]]; then
                    chmod 700 "$dir_in" 2>/dev/null || true
                    zb_info "Created directory: $dir_in"
                else
                    zb_warn "Could not create '$dir_in' as user '$ZB_ZIMBRA_USER'."
                    zb_warn "Run as root first: mkdir -p $dir_in && chown zimbra:zimbra $dir_in"
                fi
            fi
        elif [[ -d "$dir_in" && ! -w "$dir_in" ]]; then
            zb_warn "User '$ZB_ZIMBRA_USER' cannot write to '$dir_in' yet."
            zb_warn "Run as root first: chown zimbra:zimbra $dir_in"
        fi
        break
    done
}

# Interactive Field-by-Field Job Editor (change any single setting & press 's' to save)
zb_tui_job_edit_loop() {
    local mode_label="${1:-EDIT}"
    while true; do
        zb_tui_header "${mode_label} JOB: $JOB_ID"
        local keep_unit="Full snapshots"
        [[ "$BACKUP_TYPE" == "incremental" ]] && keep_unit="complete chains"
        local eff_mount="${JOB_REQUIRE_MOUNT:-inherit}"
        local tgt_disp="${TARGET_DIR:-$DEFAULT_BACKUP_DIR (default)} [mount: $eff_mount] -> $(zb_job_storage_root)"

        zb_msg "  1) Backup Mode        : $BACKUP_TYPE"
        zb_msg "  2) Schedule (Cron)    : $(zb_job_schedule_human)"
        zb_msg "  3) Retention Keep     : $KEEP_COUNT $keep_unit"
        zb_msg "  4) Full Chain Cycle   : $FULL_CYCLE_MODE (value: $FULL_CYCLE_VALUE)"
        zb_msg "  5) Target Directory   : $tgt_disp"
        zb_msg "  6) Backup Scope       : $SCOPE_MODE ${SCOPE_VALUES:+($SCOPE_VALUES)}"
        zb_msg "  7) Prune Timing       : $PRUNE_TIMING"
        zb_msg "  8) Parallel Workers   : $PARALLEL_JOBS"
        zb_msg "  9) Job Description    : $JOB_NAME"
        zb_msg " 10) Schedule Enabled   : $ENABLED"
        zb_msg "------------------------------------------------------------"
        zb_msg "  s) Save & Sync Crontab"
        zb_msg "  0) Cancel (discard changes)"
        zb_msg ""

        local c=""
        read -r -p "Select field to edit (1-10, 's' to save, '0' to cancel): " c || return 0
        c="$(zb_trim "$c")"
        case "${c,,}" in
            1) zb_tui_edit_backup_mode ;;
            2) zb_tui_configure_schedule ;;
            3) zb_tui_edit_retention ;;
            4) zb_tui_edit_full_cycle ;;
            5) zb_tui_prompt_job_storage_dir 1 ;;
            6) zb_tui_edit_scope ;;
            7) zb_tui_edit_prune_timing ;;
            8)
                local p_in
                while true; do
                    p_in="$(zb_tui_prompt_default "Parallel mailbox workers (1-16)" "$PARALLEL_JOBS")"
                    if [[ "$p_in" =~ ^([1-9]|1[0-6])$ ]]; then
                        PARALLEL_JOBS="$p_in"
                        break
                    fi
                    zb_warn "Invalid worker count '$p_in'. Enter an integer between 1 and 16."
                done
                ;;
            9) JOB_NAME="$(zb_tui_prompt_default "Job description" "$JOB_NAME")" ;;
            10) ENABLED="$(zb_tui_prompt_yesno "Enable automatic cron schedule for this job?" "$ENABLED")" ;;
            s|save)
                if zb_job_save && zb_cron_sync; then
                    zb_info "Saved job '$JOB_ID' and synchronized crontab."
                    zb_pause
                    return 0
                fi
                zb_pause
                ;;
            0|q|cancel)
                zb_info "Discarded unsaved changes."
                zb_pause
                return 0
                ;;
            *)
                zb_warn "Invalid selection."
                ;;
        esac
    done
}

# Quick 5-Step Job Creation Wizard
zb_tui_job_create() {
    zb_load_settings || return 1
    zb_job_reset_defaults
    zb_tui_header "CREATE NEW BACKUP JOB (QUICK WIZARD)"

    while true; do
        JOB_ID="$(zb_tui_prompt_default "1. Job ID (letters/digits/-/_)" "daily-backup")"
        if ! zb_valid_slug "$JOB_ID"; then
            zb_warn "Invalid Job ID. Use only letters, digits, '-', '_' (max 48 chars)."
            continue
        fi
        if [[ -f "$(zb_job_file "$JOB_ID")" ]]; then
            zb_warn "Job '$JOB_ID' already exists. Choose another ID or use Edit Job."
            continue
        fi
        break
    done
    JOB_NAME="Scheduled backup $JOB_ID"

    zb_msg ""
    zb_msg "2. Select Backup Mode:"
    zb_msg "   1) full        - Standalone full backup every run (simple, self-contained)"
    zb_msg "   2) incremental - Weekly chain: 1 Full base + 6 daily Incrementals (saves disk/time)"
    local t_ans
    t_ans="$(zb_tui_prompt_default "Select mode (1/2)" "1")"
    if [[ "$t_ans" == "2" || "${t_ans,,}" == "incremental" ]]; then
        BACKUP_TYPE="incremental"
        KEEP_COUNT="2"
        PARALLEL_JOBS="4"
        FULL_CYCLE_MODE="max_incr"
        FULL_CYCLE_VALUE="6"
    else
        BACKUP_TYPE="full"
        KEEP_COUNT="7"
        PARALLEL_JOBS="2"
    fi

    zb_msg ""
    zb_msg "3. Backup Storage Directory:"
    zb_msg "   (Snapshots are stored under <dir>/$(zb_job_category_dir)/${JOB_ID})"
    zb_tui_prompt_job_storage_dir 0

    zb_msg ""
    zb_msg "4. Configure Schedule:"
    zb_tui_configure_schedule

    zb_msg ""
    local k_ans
    if [[ "$BACKUP_TYPE" == "incremental" ]]; then
        zb_msg "5. Retention Policy (1 chain = 1 Full + ${FULL_CYCLE_VALUE} Incrementals):"
        while true; do
            k_ans="$(zb_tui_prompt_default "   Keep how many COMPLETE CHAINS?" "$KEEP_COUNT")"
            if [[ "$k_ans" =~ ^([1-9]|[1-9][0-9]{1,2})$ ]]; then
                KEEP_COUNT="$k_ans"
                break
            fi
            zb_warn "Invalid retention count '$k_ans'. Enter an integer between 1 and 999."
        done
    else
        zb_msg "5. Retention Policy:"
        while true; do
            k_ans="$(zb_tui_prompt_default "   Keep how many FULL snapshots?" "$KEEP_COUNT")"
            if [[ "$k_ans" =~ ^([1-9]|[1-9][0-9]{1,2})$ ]]; then
                KEEP_COUNT="$k_ans"
                break
            fi
            zb_warn "Invalid retention count '$k_ans'. Enter an integer between 1 and 999."
        done
    fi

    zb_msg ""
    local adv
    adv="$(zb_tui_prompt_yesno "Customize advanced options (domain/account filter, full cycle, prune timing, threads)?" "no")"
    if [[ "$adv" == "yes" ]]; then
        zb_tui_job_edit_loop "REVIEW / CUSTOMIZE NEW"
        return 0
    fi

    if zb_job_save && zb_cron_sync; then
        zb_msg ""
        zb_info "Created job '$JOB_ID' and synchronized crontab!"
        zb_job_print_detail "$JOB_ID"
    else
        zb_warn "Validation or crontab sync failed; opening editor so you can review and fix fields."
        zb_pause
        zb_tui_job_edit_loop "REVIEW / FIX NEW"
        return 0
    fi
    zb_pause
}

zb_tui_job_editor() {
    local edit_id="${1:-}"
    if [[ -z "$edit_id" ]]; then
        zb_tui_job_create
    else
        zb_load_settings || return 1
        zb_job_load "$edit_id" || { zb_pause; return 1; }
        zb_tui_job_edit_loop "EDIT"
    fi
}

zb_tui_pick_job_id() {
    local prompt_lbl="${1:-Select Job}"
    ZB_PICKED_JOB=""
    local -a ids=()
    local j
    while IFS= read -r j; do
        [[ -n "$j" ]] && ids+=("$j")
    done < <(zb_job_list_ids)

    if (( ${#ids[@]} == 0 )); then
        zb_warn "No jobs configured yet."
        return 1
    fi

    zb_msg "Configured Jobs:"
    local idx=0
    while (( idx < ${#ids[@]} )); do
        zb_job_load "${ids[$idx]}" >/dev/null 2>&1 || true
        printf '  %2d) %-18s [%s | enabled=%s | %s]\n' \
            "$((idx + 1))" "${ids[$idx]}" "$BACKUP_TYPE" "$ENABLED" "$(zb_job_schedule_human)"
        idx=$((idx + 1))
    done

    local sel
    sel="$(zb_tui_prompt_default "$prompt_lbl (enter number or Job ID, 0 to cancel)" "0")"
    [[ "$sel" == "0" || -z "$sel" ]] && return 1
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#ids[@]} )); then
        ZB_PICKED_JOB="${ids[$((sel - 1))]}"
        return 0
    fi
    if [[ -f "$(zb_job_file "$sel")" ]]; then
        ZB_PICKED_JOB="$sel"
        return 0
    fi
    zb_warn "Job not found: $sel"
    return 1
}

zb_tui_jobs_menu() {
    while true; do
        zb_load_settings || true
        zb_tui_header "JOBS & CRONTAB SCHEDULE"
        zb_job_print_summary_table
        zb_msg ""
        zb_msg "  1) Create new backup job (Quick 5-step wizard)"
        zb_msg "  2) Edit existing job (change schedule, retention, path, scope...)"
        zb_msg "  3) View full job details"
        zb_msg "  4) Enable / Disable job cron schedule"
        zb_msg "  5) Delete job configuration"
        zb_msg "  6) View & re-sync Zimbra crontab"
        zb_msg "  0) Back to main menu"
        zb_msg ""
        local choice=""
        read -r -p "Select [0-6]: " choice || return 0
        case "$(zb_trim "$choice")" in
            1) zb_tui_job_create ;;
            2)
                if zb_tui_pick_job_id "Select job to edit"; then
                    zb_tui_job_editor "$ZB_PICKED_JOB"
                else
                    zb_pause
                fi
                ;;
            3)
                if zb_tui_pick_job_id "Select job to view"; then
                    zb_job_print_detail "$ZB_PICKED_JOB"
                fi
                zb_pause
                ;;
            4)
                if zb_tui_pick_job_id "Select job to toggle"; then
                    if zb_job_load "$ZB_PICKED_JOB"; then
                        if [[ "$ENABLED" == "yes" ]]; then
                            ENABLED="no"
                        else
                            ENABLED="yes"
                        fi
                        if zb_job_save && zb_cron_sync; then
                            zb_info "Job '$JOB_ID' schedule enabled = $ENABLED"
                        fi
                    fi
                fi
                zb_pause
                ;;
            5)
                if zb_tui_pick_job_id "Select job to delete"; then
                    zb_cli_job delete "$ZB_PICKED_JOB" || true
                fi
                zb_pause
                ;;
            6)
                zb_cron_sync || true
                zb_msg "--- Managed crontab block for user '$ZB_ZIMBRA_USER' ---"
                zb_cron_print_managed
                zb_pause
                ;;
            0) return 0 ;;
        esac
    done
}

zb_tui_run_backup_menu() {
    zb_load_settings || true
    zb_tui_header "RUN BACKUP NOW"
    zb_msg "  1) Run a configured Job now"
    zb_msg "  2) Force a new Full chain for an Incremental Job (--force-full)"
    zb_msg "  3) Ad-hoc Full backup for specific email account(s)"
    zb_msg "  0) Back to main menu"
    zb_msg ""
    local c=""
    read -r -p "Select [0-3]: " c || return 0
    case "$(zb_trim "$c")" in
        1)
            if zb_tui_pick_job_id "Select job to run now"; then
                zb_run_job "$ZB_PICKED_JOB" || true
                zb_pause
            fi
            ;;
        2)
            if zb_tui_pick_job_id "Select Incremental job to force Full"; then
                zb_run_job "$ZB_PICKED_JOB" --force-full || true
                zb_pause
            fi
            ;;
        3)
            local emails dir_override tip_dir adhoc_req_mount="$REQUIRE_MOUNTPOINT"
            emails="$(zb_tui_prompt_default "Account email(s) (comma-separated)" "")"
            [[ -n "$emails" ]] || return 0
            while true; do
                dir_override="$(zb_tui_prompt_default "Backup storage directory (saved under <dir>/account)" "$DEFAULT_BACKUP_DIR")"
                dir_override="$(zb_normalize_dir_input "$dir_override")"
                if ! zb_valid_safe_path "$dir_override"; then
                    zb_warn "Invalid path '$dir_override'. Enter an absolute path (e.g. /home/backup or /backup)."
                    continue
                fi
                if ! zb_check_no_symlinks "$dir_override"; then
                    continue
                fi
                adhoc_req_mount="$REQUIRE_MOUNTPOINT"
                if [[ "$adhoc_req_mount" == "yes" ]] && ! zb_has_mounted_base "$dir_override"; then
                    local allow_adhoc_local
                    allow_adhoc_local="$(zb_tui_prompt_yesno "   '$dir_override' is not a mounted disk/NFS. Allow local folder for this run?" "yes")"
                    if [[ "$allow_adhoc_local" == "yes" ]]; then
                        adhoc_req_mount="no"
                    fi
                fi
                if [[ ! -d "$dir_override" && "$adhoc_req_mount" == "no" ]]; then
                    local mk_adhoc
                    mk_adhoc="$(zb_tui_prompt_yesno "   Directory '$dir_override' does not exist. Create it now?" "yes")"
                    if [[ "$mk_adhoc" == "yes" ]]; then
                        mkdir -p -m 700 -- "$dir_override" 2>/dev/null || mkdir -p -- "$dir_override" 2>/dev/null || true
                        if [[ -d "$dir_override" && -w "$dir_override" ]]; then
                            chmod 700 "$dir_override" 2>/dev/null || true
                            zb_info "Created directory: $dir_override"
                        else
                            zb_warn "Run as root first: mkdir -p $dir_override && chown zimbra:zimbra $dir_override"
                        fi
                    fi
                fi
                break
            done
            zb_run_adhoc_users "$emails" "$dir_override" "$adhoc_req_mount" || true
            tip_dir="${dir_override%/}"
            [[ "${tip_dir##*/}" =~ ^[Aa]ccount$ ]] || tip_dir="${tip_dir}/account"
            zb_info "Tip: Use Menu 4 (Restore from Custom Dir -> $tip_dir) to restore account backups."
            zb_pause
            ;;
        0) return 0 ;;
    esac
}

# Interactive account picker within a backup snapshot (supports keyword search, numbers, or emails)
zb_tui_select_users_from_snapshot() {
    local snap_dir="$1"
    ZB_PICKED_USERS_CSV=""
    local acc_file="$snap_dir/accounts/active_accounts.txt"
    [[ -f "$acc_file" ]] || { zb_err "Snapshot does not contain accounts/active_accounts.txt"; return 1; }

    local kw
    kw="$(zb_tui_prompt_default "Filter accounts by keyword/domain (press Enter to list all)" "")"

    local -a matched=()
    local u
    while IFS= read -r u; do
        [[ -n "$u" ]] || continue
        if [[ -z "$kw" || "${u,,}" == *"${kw,,}"* ]]; then
            matched+=("$u")
        fi
    done < "$acc_file"

    if (( ${#matched[@]} == 0 )); then
        zb_warn "No accounts matched keyword '$kw'."
        return 1
    fi

    zb_msg "------------------------------------------------------------"
    local i=0
    while (( i < ${#matched[@]} )); do
        local mail="${matched[$i]}"
        local sz_lbl=""
        if [[ -f "$snap_dir/mailboxes/${mail}.tgz" ]]; then
            local b
            b="$(wc -c < "$snap_dir/mailboxes/${mail}.tgz" | awk '{print $1}')"
            sz_lbl="($(zb_human_bytes "$b"))"
        fi
        printf '  %4d) %-42s %s\n' "$((i + 1))" "$mail" "$sz_lbl"
        i=$((i + 1))
    done
    zb_msg "------------------------------------------------------------"
    local raw_sel
    raw_sel="$(zb_tui_prompt_default "Enter number(s) (e.g. 1,3,5) or email(s) (0 to cancel)" "0")"
    [[ "$raw_sel" == "0" || -z "$raw_sel" ]] && return 1

    local -a chosen=()
    local tok
    local -a toks=()
    IFS=',' read -r -a toks <<< "$raw_sel"
    for tok in "${toks[@]}"; do
        tok="$(zb_trim "$tok")"
        [[ -n "$tok" ]] || continue
        if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#matched[@]} )); then
            chosen+=("${matched[$((tok - 1))]}")
        elif zb_valid_email "$tok"; then
            chosen+=("$tok")
        else
            zb_warn "Skipping invalid entry: $tok"
        fi
    done

    (( ${#chosen[@]} > 0 )) || return 1
    local joined=""
    local c_item
    for c_item in "${chosen[@]}"; do
        joined="${joined:+${joined},}${c_item}"
    done
    ZB_PICKED_USERS_CSV="$joined"
    return 0
}

zb_tui_restore_from_catalog() {
    local custom_dir="${1:-}"
    local filter_job="${2:-}"

    zb_msg ""
    zb_print_backup_catalog "$custom_dir" "$filter_job" || { zb_pause; return 1; }
    if (( ${#ZB_CAT_PATHS[@]} == 0 )); then
        zb_pause
        return 0
    fi

    zb_msg ""
    local sel
    sel="$(zb_tui_prompt_default "Step 1 - Select backup number [NO.] to restore (0 to cancel)" "0")"
    [[ "$sel" == "0" || -z "$sel" ]] && return 0

    zb_resolve_backup_selector "$sel" "$custom_dir" "$filter_job" || { zb_pause; return 1; }
    local chosen_snap="$ZB_SELECTED_DIR"

    zb_msg ""
    zb_msg "Step 2 - Restore Scope:"
    zb_msg "  1) Full server (all domains, accounts, DLs, aliases, signatures, mailboxes)"
    zb_msg "  2) By domain(s)"
    zb_msg "  3) Specific user account(s) (search & select 1 or more users)"
    local sc_c
    sc_c="$(zb_tui_prompt_default "Select scope (1-3)" "3")"

    local -a restore_args=(--from "$chosen_snap")
    [[ -n "$custom_dir" ]] && restore_args+=(--dir "$custom_dir")
    [[ -n "$filter_job" ]] && restore_args+=(--job "$filter_job")

    local single_user_selected=0
    case "$sc_c" in
        1)
            restore_args+=(--all)
            ;;
        2)
            if [[ -f "$chosen_snap/domains/domains.txt" ]]; then
                zb_msg "Domains in snapshot: $(tr '\n' ' ' < "$chosen_snap/domains/domains.txt")"
            fi
            local dom_csv
            dom_csv="$(zb_tui_prompt_default "Enter domain(s) to restore (comma-separated)" "")"
            [[ -n "$dom_csv" ]] || return 0
            restore_args+=(--domain "$dom_csv")
            ;;
        3)
            zb_tui_select_users_from_snapshot "$chosen_snap" || { zb_pause; return 0; }
            restore_args+=(--users "$ZB_PICKED_USERS_CSV")
            [[ "$ZB_PICKED_USERS_CSV" != *,* ]] && single_user_selected=1
            ;;
        *)
            return 0
            ;;
    esac

    local target_u=""
    if (( single_user_selected == 1 )); then
        local redirect_yn
        redirect_yn="$(zb_tui_prompt_yesno "Restore into a DIFFERENT destination email account?" "no")"
        if [[ "$redirect_yn" == "yes" ]]; then
            target_u="$(zb_tui_prompt_default "Destination email address" "")"
            [[ -n "$target_u" ]] && restore_args+=(--target-user "$target_u")
        fi
    fi

    zb_msg ""
    zb_msg "Step 3 - Components & Conflict Handling:"
    zb_msg "  1) Both LDAP account settings + Mailbox data (default)"
    zb_msg "  2) Mailbox data only (.tgz emails, contacts, calendar)"
    zb_msg "  3) LDAP settings only (password hash, quota, aliases, signatures, filters)"
    local comp_c only_part="all"
    comp_c="$(zb_tui_prompt_default "Select components (1-3)" "1")"
    [[ "$comp_c" == "2" ]] && only_part="mailbox"
    [[ "$comp_c" == "3" ]] && only_part="ldap"
    restore_args+=(--only "$only_part")

    if [[ "$only_part" != "ldap" ]]; then
        zb_msg ""
        zb_msg "Mailbox Conflict Mode:"
        zb_msg "  1) skip      - Keep existing emails, import missing items only (safe, recommended)"
        zb_msg "  2) subfolder - Import into a separate folder /Restore_<timestamp> (no overwrite)"
        zb_msg "  3) modify    - Update existing items & add missing items"
        zb_msg "  4) reset     - WIPE current mailbox and replace with backup (!)"
        local m_c mode_val="skip"
        m_c="$(zb_tui_prompt_default "Select mode (1-4)" "1")"
        case "$m_c" in
            2)
                mode_val="subfolder"
                local sf sf_def
                sf_def="Restore_$(date +%Y%m%d_%H%M)"
                while true; do
                    sf="$(zb_tui_prompt_default "Subfolder name" "$sf_def")"
                    sf="${sf#/}"
                    if zb_valid_subfolder_name "$sf"; then
                        break
                    fi
                    zb_warn "Invalid subfolder name '$sf' (allowed: letters, digits, '.', '_', '-', '/'; no '..' or spaces)."
                done
                restore_args+=(--subfolder-name "$sf")
                ;;
            3) mode_val="modify" ;;
            4) mode_val="reset" ;;
            *) mode_val="skip" ;;
        esac
        restore_args+=(--mode "$mode_val")
    fi

    zb_msg ""
    local dry_yn
    dry_yn="$(zb_tui_prompt_yesno "Step 4 - Preview with Dry-Run first (no changes made)?" "no")"
    if [[ "$dry_yn" == "yes" ]]; then
        zb_run_restore "${restore_args[@]}" --dry-run || true
        local go_live
        go_live="$(zb_tui_prompt_yesno "Proceed with LIVE restore now?" "no")"
        [[ "$go_live" == "yes" ]] || { zb_pause; return 0; }
    fi

    zb_run_restore "${restore_args[@]}" || true
    zb_pause
}

zb_tui_restore_job_wizard() {
    zb_load_settings || true
    zb_tui_header "RESTORE FROM BACKUP JOB"

    local -a job_ids=()
    local jid
    while IFS= read -r jid; do
        [[ -n "$jid" ]] && job_ids+=("$jid")
    done < <(zb_job_list_ids)

    if (( ${#job_ids[@]} == 0 )); then
        zb_warn "No backup jobs configured yet. Create a job in Menu 1, or use Menu 4 (Restore from Custom Dir)."
        zb_pause
        return 0
    fi

    zb_msg "Configured Backup Jobs (scans ONLY job storage directories):"
    local idx=0
    while (( idx < ${#job_ids[@]} )); do
        (
            if zb_job_load "${job_ids[$idx]}" >/dev/null 2>&1; then
                printf '  %2d) %-20s [%-11s | %s]\n' "$((idx + 1))" "$JOB_ID" "$BACKUP_TYPE" "$(zb_job_storage_root)"
            fi
        )
        idx=$((idx + 1))
    done
    if (( ${#job_ids[@]} > 1 )); then
        zb_msg "   a) All configured backup jobs"
    fi
    zb_msg "   0) Back to main menu"
    zb_msg ""

    local def_pick="1"
    (( ${#job_ids[@]} > 1 )) && def_pick="a"
    local jpick filter_job=""
    jpick="$(zb_tui_prompt_default "Select job to restore from" "$def_pick")"
    case "$jpick" in
        0|"")
            return 0
            ;;
        a|A|all|ALL)
            filter_job=""
            ;;
        *)
            if [[ "$jpick" =~ ^[0-9]+$ ]] && (( jpick >= 1 && jpick <= ${#job_ids[@]} )); then
                filter_job="${job_ids[$((jpick - 1))]}"
            elif zb_valid_slug "$jpick" && [[ -f "$(zb_job_file "$jpick")" ]]; then
                filter_job="$jpick"
            else
                zb_warn "Invalid job selection: $jpick"
                zb_pause
                return 0
            fi
            ;;
    esac

    zb_tui_restore_from_catalog "" "$filter_job"
}

zb_tui_restore_custom_wizard() {
    while true; do
        zb_load_settings || true
        zb_tui_header "RESTORE FROM CUSTOM DIRECTORY"
        zb_msg "  Configured Custom Restore Dir : ${CUSTOM_RESTORE_DIR:-(not set)}"
        zb_msg "  (Separate from Backup Jobs - supports external NAS/USB, ad-hoc & legacy dirs)"
        zb_msg "------------------------------------------------------------"
        if [[ -n "$CUSTOM_RESTORE_DIR" ]]; then
            zb_msg "  1) Restore from configured Custom Restore Dir ($CUSTOM_RESTORE_DIR)"
        else
            zb_msg "  1) Configure Custom Restore Dir & start restore"
        fi
        zb_msg "  2) Restore from a one-time directory path (do not overwrite config)"
        zb_msg "  3) Set / Change configured Custom Restore Dir"
        zb_msg "  0) Back to main menu"
        zb_msg ""

        local c=""
        read -r -p "Select [0-3]: " c || return 0
        case "$(zb_trim "$c")" in
            1)
                if [[ -z "$CUSTOM_RESTORE_DIR" ]]; then
                    local new_rdir
                    new_rdir="$(zb_tui_prompt_default "Enter Custom Restore Directory path" "/mnt/restore")"
                    new_rdir="$(zb_normalize_dir_input "$new_rdir")"
                    [[ -n "$new_rdir" ]] || continue
                    CUSTOM_RESTORE_DIR="$new_rdir"
                    if ! zb_save_settings; then
                        zb_pause
                        continue
                    fi
                    zb_info "Saved Custom Restore Dir: $CUSTOM_RESTORE_DIR"
                fi
                zb_tui_restore_from_catalog "$CUSTOM_RESTORE_DIR" ""
                return 0
                ;;
            2)
                local once_dir
                once_dir="$(zb_tui_prompt_default "Enter one-time backup directory path" "${CUSTOM_RESTORE_DIR:-$DEFAULT_BACKUP_DIR}")"
                once_dir="$(zb_normalize_dir_input "$once_dir")"
                [[ -n "$once_dir" ]] || continue
                if ! zb_valid_safe_path "$once_dir"; then
                    zb_err "Invalid directory path: $once_dir" || true
                    zb_pause
                    continue
                fi
                zb_tui_restore_from_catalog "$once_dir" ""
                return 0
                ;;
            3)
                local cfg_rdir
                cfg_rdir="$(zb_tui_prompt_default "Custom Restore Directory ('none' to clear)" "${CUSTOM_RESTORE_DIR:-/mnt/restore}")"
                cfg_rdir="$(zb_normalize_dir_input "$cfg_rdir")"
                if [[ "$cfg_rdir" == "none" || "$cfg_rdir" == "-" ]]; then
                    CUSTOM_RESTORE_DIR=""
                else
                    CUSTOM_RESTORE_DIR="$cfg_rdir"
                fi
                if zb_save_settings; then
                    zb_info "Saved Custom Restore Dir: ${CUSTOM_RESTORE_DIR:-(not set)}"
                fi
                zb_pause
                ;;
            0)
                return 0
                ;;
        esac
    done
}

zb_tui_catalog_menu() {
    local view_dir=""
    while true; do
        zb_load_settings || true
        zb_tui_header "BACKUP CATALOG & INTEGRITY CHECK"
        local fs_check_dir="${view_dir:-$DEFAULT_BACKUP_DIR}"
        if [[ -d "$fs_check_dir" ]]; then
            zb_msg "Filesystem usage ($fs_check_dir):"
            df -h -- "$fs_check_dir" 2>/dev/null | sed 's/^/  /' || true
            zb_msg ""
        fi
        if [[ -n "$view_dir" ]]; then
            zb_msg "Catalog Source: Custom Directory ($view_dir)"
        else
            zb_msg "Catalog Source: Configured Backup Jobs (<target_dir>/<full|incremental>/<job_id>)"
        fi
        zb_msg ""
        zb_print_backup_catalog "$view_dir"
        zb_msg ""
        zb_msg "  1) Inspect snapshot details & search accounts inside backup"
        zb_msg "  2) Verify SHA-256 checksums of a backup / chain"
        if [[ -n "$view_dir" ]]; then
            zb_msg "  3) Switch back to Configured Backup Jobs catalog"
        else
            zb_msg "  3) Switch catalog view to a Custom Directory"
        fi
        zb_msg "  4) Clean leftover '.pending.*' staging directories"
        zb_msg "  0) Back to main menu"
        zb_msg ""
        local c=""
        read -r -p "Select [0-4]: " c || return 0
        case "$(zb_trim "$c")" in
            1)
                local idx kw
                idx="$(zb_tui_prompt_default "Enter backup number [NO.]" "1")"
                kw="$(zb_tui_prompt_default "Search account keyword (Enter = show all)" "")"
                zb_inspect_snapshot "$idx" "$view_dir" "$kw" || true
                zb_pause
                ;;
            2)
                local v_idx
                v_idx="$(zb_tui_prompt_default "Enter backup number [NO.] to verify" "1")"
                if [[ -n "$view_dir" ]]; then
                    zb_cli_backup verify "$v_idx" --dir "$view_dir" || true
                else
                    zb_cli_backup verify "$v_idx" || true
                fi
                zb_pause
                ;;
            3)
                if [[ -n "$view_dir" ]]; then
                    view_dir=""
                else
                    local ext_dir
                    ext_dir="$(zb_tui_prompt_default "Custom directory path" "${CUSTOM_RESTORE_DIR:-$DEFAULT_BACKUP_DIR}")"
                    ext_dir="$(zb_normalize_dir_input "$ext_dir")"
                    if [[ -n "$ext_dir" ]] && zb_valid_safe_path "$ext_dir"; then
                        view_dir="$ext_dir"
                    else
                        zb_err "Invalid directory path: $ext_dir" || true
                        zb_pause
                    fi
                fi
                ;;
            4)
                zb_clean_pending_dirs "$view_dir" || true
                zb_pause
                ;;
            0) return 0 ;;
        esac
    done
}

zb_tui_settings_menu() {
    while true; do
        zb_load_settings || true
        zb_tui_header "GLOBAL SETTINGS & ALERTS"
        zb_msg "  1) Default job backup dir   : $DEFAULT_BACKUP_DIR"
        zb_msg "  2) Custom restore directory : ${CUSTOM_RESTORE_DIR:-(not set)}"
        zb_msg "  3) Require mountpoint       : $REQUIRE_MOUNTPOINT"
        zb_msg "  4) Disk warning / Min free  : ${DISK_WARN_PERCENT}% / ${DISK_MIN_FREE_MB} MB"
        zb_msg "  5) Server label (alerts)    : ${HOST_LABEL:-(auto: $(zb_host_label))}"
        zb_msg "  6) Telegram Bot alerts      : $TELEGRAM_ENABLED ${TELEGRAM_CHAT_ID:+(chat: $TELEGRAM_CHAT_ID)}"
        zb_msg "  7) Email failure alerts     : $EMAIL_ALERT_ENABLED ${EMAIL_ALERT_TO:+($EMAIL_ALERT_TO)}"
        zb_msg "  8) Send test Telegram alert"
        zb_msg "  0) Back to main menu"
        zb_msg ""
        local c=""
        read -r -p "Select [0-8]: " c || return 0
        case "$(zb_trim "$c")" in
            1)
                DEFAULT_BACKUP_DIR="$(zb_tui_prompt_default "Default job backup directory" "$DEFAULT_BACKUP_DIR")"
                DEFAULT_BACKUP_DIR="$(zb_normalize_dir_input "$DEFAULT_BACKUP_DIR")"
                if [[ ! -d "$DEFAULT_BACKUP_DIR" && "$REQUIRE_MOUNTPOINT" == "no" ]]; then
                    local mk
                    mk="$(zb_tui_prompt_yesno "Directory does not exist. Create '$DEFAULT_BACKUP_DIR' now?" "yes")"
                    [[ "$mk" == "yes" ]] && mkdir -p -m 700 -- "$DEFAULT_BACKUP_DIR" || true
                fi
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            2)
                local rdir_in
                rdir_in="$(zb_tui_prompt_default "Custom restore directory ('none' to clear)" "${CUSTOM_RESTORE_DIR:-/mnt/restore}")"
                rdir_in="$(zb_normalize_dir_input "$rdir_in")"
                if [[ "$rdir_in" == "none" || "$rdir_in" == "-" ]]; then
                    CUSTOM_RESTORE_DIR=""
                else
                    CUSTOM_RESTORE_DIR="$rdir_in"
                fi
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            3)
                REQUIRE_MOUNTPOINT="$(zb_tui_prompt_yesno "Require dedicated mounted disk/NFS?" "$REQUIRE_MOUNTPOINT")"
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            4)
                DISK_WARN_PERCENT="$(zb_tui_prompt_default "Disk usage warning threshold (%)" "$DISK_WARN_PERCENT")"
                DISK_MIN_FREE_MB="$(zb_tui_prompt_default "Minimum free disk space (MB)" "$DISK_MIN_FREE_MB")"
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            5)
                HOST_LABEL="$(zb_tui_prompt_default "Server label (blank = hostname)" "$HOST_LABEL")"
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            6)
                TELEGRAM_ENABLED="$(zb_tui_prompt_yesno "Enable Telegram Bot alerts?" "$TELEGRAM_ENABLED")"
                if [[ "$TELEGRAM_ENABLED" == "yes" ]]; then
                    TELEGRAM_TOKEN="$(zb_tui_prompt_default "Telegram Bot Token" "$TELEGRAM_TOKEN")"
                    TELEGRAM_CHAT_ID="$(zb_tui_prompt_default "Telegram Chat ID" "$TELEGRAM_CHAT_ID")"
                    TELEGRAM_THREAD_ID="$(zb_tui_prompt_default "Topic Thread ID (blank if none)" "$TELEGRAM_THREAD_ID")"
                fi
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            7)
                EMAIL_ALERT_ENABLED="$(zb_tui_prompt_yesno "Enable Email alerts on failure?" "$EMAIL_ALERT_ENABLED")"
                if [[ "$EMAIL_ALERT_ENABLED" == "yes" ]]; then
                    EMAIL_ALERT_TO="$(zb_tui_prompt_default "Recipient email address" "$EMAIL_ALERT_TO")"
                fi
                if zb_save_settings; then
                    zb_info "Saved."
                fi
                zb_pause
                ;;
            8)
                if zb_send_telegram "[OK] [$(zb_host_label)] Test notification from zimbra-backup v${ZB_VERSION}"; then
                    zb_info "Test Telegram message sent."
                else
                    zb_warn "Failed to send Telegram message (check TELEGRAM_ENABLED, Token, and Chat ID)."
                fi
                zb_pause
                ;;
            0) return 0 ;;
        esac
    done
}

zb_cli_logs() {
    zb_ensure_state_dirs || return 1
    local mode="${1:-latest}"
    local lines="${2:-80}"
    shopt -s nullglob
    local -a logs=("$ZB_LOG_DIR"/*.log)
    shopt -u nullglob
    if (( ${#logs[@]} == 0 )); then
        zb_msg "No log files in $ZB_LOG_DIR yet."
        return 0
    fi

    local latest
    latest="$(ls -1t "$ZB_LOG_DIR"/*.log 2>/dev/null | head -n 1)"
    case "$mode" in
        list)
            ls -lh --time-style=long-iso "$ZB_LOG_DIR"/*.log 2>/dev/null || ls -lh "$ZB_LOG_DIR"/*.log
            ;;
        latest)
            zb_msg "=== Latest log: $latest (last $lines lines) ==="
            tail -n "$lines" -- "$latest"
            ;;
        *)
            if [[ -f "$ZB_LOG_DIR/$mode" ]]; then
                tail -n "$lines" -- "$ZB_LOG_DIR/$mode"
            else
                zb_err "Log file not found: $mode"
                return 1
            fi
            ;;
    esac
}

zb_tui_logs_menu() {
    zb_ensure_state_dirs || true
    zb_tui_header "OPERATIONAL LOGS ($ZB_LOG_DIR)"
    shopt -s nullglob
    local -a logs=()
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] && logs+=("$f")
    done < <(ls -1t "$ZB_LOG_DIR"/*.log 2>/dev/null | head -n 15)
    shopt -u nullglob

    if (( ${#logs[@]} == 0 )); then
        zb_msg "No execution logs recorded yet."
        zb_pause
        return 0
    fi

    local i=0
    while (( i < ${#logs[@]} )); do
        printf '  %2d) %s\n' "$((i + 1))" "${logs[$i]##*/}"
        i=$((i + 1))
    done
    zb_msg ""
    local sel
    sel="$(zb_tui_prompt_default "Select log number to view last 100 lines (0 to go back)" "1")"
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#logs[@]} )); then
        zb_msg "------------------------------------------------------------"
        tail -n 100 -- "${logs[$((sel - 1))]}"
        zb_msg "------------------------------------------------------------"
        zb_pause
    fi
}

zb_tui_main() {
    zb_ensure_state_dirs || return 1
    if ! zb_is_initialized; then
        zb_reset_settings_defaults
        zb_save_settings 2>/dev/null || true
    fi

    while true; do
        zb_load_settings || true
        local job_cnt=0
        job_cnt="$(zb_job_list_ids | wc -l | awk '{print $1}')"
        zb_tui_header "MAIN MENU"
        zb_msg "  Job Storage : $DEFAULT_BACKUP_DIR (mount: $REQUIRE_MOUNTPOINT) | Jobs: $job_cnt | Custom Restore: ${CUSTOM_RESTORE_DIR:-(not set)}"
        if (( job_cnt == 0 )); then
            zb_msg "  (Notice: No backup jobs configured yet. Select 1 to create your first job)"
        fi
        zb_msg "------------------------------------------------------------"
        zb_msg "  1) Jobs & Crontab Schedule   (Create, Edit, Enable/Disable, Delete)"
        zb_msg "  2) Run Backup Now            (Run Job, Force Full, Single Account)"
        zb_msg "  3) Restore from Backup Job   (Select Configured Job -> Snapshot)"
        zb_msg "  4) Restore from Custom Dir   (Configure / Scan Other Directory)"
        zb_msg "  5) Backup Catalog & Verify   (Job Snapshots, Search Users, SHA-256)"
        zb_msg "  6) Global Settings & Alerts  (Storage Paths, Disk Limits, Telegram)"
        zb_msg "  7) View Logs"
        zb_msg "  0) Exit"
        zb_msg "============================================================"
        local ch=""
        read -r -p "Select [0-7]: " ch || return 0
        case "$(zb_trim "$ch")" in
            1) zb_tui_jobs_menu ;;
            2) zb_tui_run_backup_menu ;;
            3) zb_tui_restore_job_wizard ;;
            4) zb_tui_restore_custom_wizard ;;
            5) zb_tui_catalog_menu ;;
            6) zb_tui_settings_menu ;;
            7) zb_tui_logs_menu ;;
            0|q|exit) return 0 ;;
        esac
    done
}
