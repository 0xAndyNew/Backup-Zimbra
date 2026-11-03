#!/usr/bin/env bash
# Backup execution engine: Standalone Full & Chain-based Incremental backups,
# parallel mailbox workers with retry, zb-backup-v2 SHA-256 manifests, and configurable pruning.
# Compatible with Bash 4.2+ (no wait -n, no namerefs).

ZB_SNAP_FORMAT="zb-backup-v2"
ZB_ACTIVE_WORKER_PIDS=()

zb_terminate_active_workers() {
    local p
    for p in "${ZB_ACTIVE_WORKER_PIDS[@]+"${ZB_ACTIVE_WORKER_PIDS[@]}"}"; do
        kill -TERM "$p" 2>/dev/null || true
    done
    for p in "${ZB_ACTIVE_WORKER_PIDS[@]+"${ZB_ACTIVE_WORKER_PIDS[@]}"}"; do
        wait "$p" 2>/dev/null || true
    done
    ZB_ACTIVE_WORKER_PIDS=()
}

# Read a manifest file safely (key=value lines before `# --- sha256 ---`)
zb_read_manifest_meta() {
    local manifest_file="$1"
    MF_FORMAT=""
    MF_BACKUP_ID=""
    MF_JOB_ID=""
    MF_BACKUP_TYPE=""
    MF_CHAIN_ID=""
    MF_CHAIN_SEQ="0"
    MF_PARENT_ID=""
    MF_CREATED_AT=""
    MF_CHECKPOINT_FROM="0"
    MF_CHECKPOINT_TO="0"
    MF_DOMAINS_COUNT="0"
    MF_ACCOUNTS_COUNT="0"
    MF_DL_COUNT="0"
    MF_ARCHIVES_COUNT="0"
    MF_EMPTY_DELTA_COUNT="0"
    MF_TOTAL_BYTES="0"
    MF_HOST=""

    [[ -f "$manifest_file" ]] || return 1
    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line//$'\r'/}"
        [[ "$line" == "# --- sha256 ---" ]] && break
        [[ -z "$line" || "$line" == '#'* ]] && continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        val="${line#*=}"
        case "$key" in
            format) MF_FORMAT="$val" ;;
            backup_id) MF_BACKUP_ID="$val" ;;
            job_id) MF_JOB_ID="$val" ;;
            backup_type|type) MF_BACKUP_TYPE="$val" ;;
            chain_id) MF_CHAIN_ID="$val" ;;
            chain_seq) MF_CHAIN_SEQ="$val" ;;
            parent_id) MF_PARENT_ID="$val" ;;
            created_at|finished_at) MF_CREATED_AT="$val" ;;
            checkpoint_from) MF_CHECKPOINT_FROM="$val" ;;
            checkpoint_to) MF_CHECKPOINT_TO="$val" ;;
            domains_count) MF_DOMAINS_COUNT="$val" ;;
            accounts_count) MF_ACCOUNTS_COUNT="$val" ;;
            dl_count) MF_DL_COUNT="$val" ;;
            archives_count) MF_ARCHIVES_COUNT="$val" ;;
            empty_delta_count) MF_EMPTY_DELTA_COUNT="$val" ;;
            total_bytes) MF_TOTAL_BYTES="$val" ;;
            host) MF_HOST="$val" ;;
        esac
    done < "$manifest_file"
    [[ "$MF_FORMAT" == "zb-backup-v2" || "$MF_FORMAT" == "zb-full-v1" ]]
}

zb_verify_snapshot_dir() {
    local snap_dir="$1"
    local quiet="${2:-0}"
    local filter_file="${3:-}"
    local mf="$snap_dir/manifest"
    [[ -f "$mf" ]] || { [[ "$quiet" == "1" ]] || zb_err "Manifest not found: $mf"; return 1; }
    zb_read_manifest_meta "$mf" || { [[ "$quiet" == "1" ]] || zb_err "Unsupported or corrupted manifest header: $mf"; return 1; }

    local sum_tmp
    sum_tmp="$(mktemp "$ZB_RUN_DIR/.verify_sha.XXXXXX")" || return 1
    awk 'found { print } /^# --- sha256 ---$/ { found = 1 }' "$mf" > "$sum_tmp"

    if [[ -s "$sum_tmp" ]]; then
        if [[ -n "$filter_file" && -s "$filter_file" ]]; then
            local filtered_sum
            filtered_sum="$(mktemp "$ZB_RUN_DIR/.verify_sha_filt.XXXXXX")" || { rm -f -- "$sum_tmp"; return 1; }
            grep -E ' (domains/|dl/|admins/)' "$sum_tmp" >> "$filtered_sum" 2>/dev/null || true
            grep -F -f "$filter_file" "$sum_tmp" >> "$filtered_sum" 2>/dev/null || true
            sort -u "$filtered_sum" -o "$filtered_sum" 2>/dev/null || true
            mv -f -- "$filtered_sum" "$sum_tmp"
        fi
        if [[ -s "$sum_tmp" ]]; then
            if ! (cd "$snap_dir" && sha256sum -c "$sum_tmp" >/dev/null 2>&1); then
                rm -f -- "$sum_tmp"
                [[ "$quiet" == "1" ]] || zb_err "SHA-256 checksum mismatch in backup: $snap_dir"
                return 1
            fi
        fi
    fi
    rm -f -- "$sum_tmp"
    return 0
}

zb_calc_dir_bytes() {
    local dir="$1"
    local kb
    kb="$(du -sk -- "$dir" 2>/dev/null | awk '{print $1}')"
    if [[ "$kb" =~ ^[0-9]+$ ]]; then
        printf '%s' "$(( kb * 1024 ))"
    else
        printf '0'
    fi
}

zb_write_manifest() {
    local snap_dir="$1"
    local backup_id="$2"
    local job_id="$3"
    local btype="$4"
    local chain_id="$5"
    local chain_seq="$6"
    local parent_id="$7"
    local cp_from="$8"
    local cp_to="$9"

    local dom_cnt=0 acc_cnt=0 dl_cnt=0 arch_cnt=0 empty_cnt=0 total_bytes=0
    [[ -f "$snap_dir/domains/domains.txt" ]] && dom_cnt="$(wc -l < "$snap_dir/domains/domains.txt" | awk '{print $1}')"
    [[ -f "$snap_dir/accounts/active_accounts.txt" ]] && acc_cnt="$(wc -l < "$snap_dir/accounts/active_accounts.txt" | awk '{print $1}')"
    [[ -f "$snap_dir/dl/distribution_lists.txt" ]] && dl_cnt="$(wc -l < "$snap_dir/dl/distribution_lists.txt" | awk '{print $1}')"

    shopt -s nullglob
    local -a tgzs=("$snap_dir/mailboxes"/*.tgz)
    local -a empties=("$snap_dir/mailboxes"/*.empty)
    shopt -u nullglob
    arch_cnt="${#tgzs[@]}"
    empty_cnt="${#empties[@]}"
    total_bytes="$(zb_calc_dir_bytes "$snap_dir")"

    local mf="$snap_dir/manifest"
    {
        printf 'format=%s\n' "$ZB_SNAP_FORMAT"
        printf 'version=%s\n' "$ZB_VERSION"
        printf 'backup_id=%s\n' "$backup_id"
        printf 'job_id=%s\n' "$job_id"
        printf 'backup_type=%s\n' "$btype"
        printf 'chain_id=%s\n' "$chain_id"
        printf 'chain_seq=%s\n' "$chain_seq"
        printf 'parent_id=%s\n' "$parent_id"
        printf 'host=%s\n' "$(zb_host_label)"
        printf 'created_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'checkpoint_from=%s\n' "$cp_from"
        printf 'checkpoint_to=%s\n' "$cp_to"
        printf 'domains_count=%s\n' "$dom_cnt"
        printf 'accounts_count=%s\n' "$acc_cnt"
        printf 'dl_count=%s\n' "$dl_cnt"
        printf 'archives_count=%s\n' "$arch_cnt"
        printf 'empty_delta_count=%s\n' "$empty_cnt"
        printf 'total_bytes=%s\n' "$total_bytes"
        printf '# --- sha256 ---\n'
        (
            cd "$snap_dir" && \
            find domains admins dl accounts passwords attributes aliases signatures filters mailboxes \
                -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r sha256sum
        )
    } > "$mf"
    chmod 600 "$mf"
}

# Ensure target directory path does not collide if two runs occur within the same second
zb_unique_path() {
    local candidate="$1"
    if [[ ! -e "$candidate" ]]; then
        printf '%s' "$candidate"
        return 0
    fi
    local n=2
    while [[ -e "${candidate}_${n}" ]]; do
        n=$((n + 1))
    done
    printf '%s_%d' "$candidate" "$n"
}

# List valid completed full snapshot directories for a `full` job (oldest -> newest by manifest timestamp)
zb_list_full_job_snapshots() {
    local job_root="$1"
    local d cp_num
    [[ -d "$job_root" ]] || return 0
    shopt -s nullglob
    for d in \
        "$job_root"/backup-full-* \
        "$job_root"/snapshots/backup-full-* \
        "$job_root"/snapshots/full_*; do
        [[ -d "$d" && ! -L "$d" && -f "$d/manifest" ]] || continue
        if zb_read_manifest_meta "$d/manifest"; then
            cp_num="${MF_CHECKPOINT_TO:-0}"
            [[ "$cp_num" =~ ^[0-9]+$ ]] || cp_num=0
            printf '%012d\t%s\t%s\n' "$cp_num" "${MF_CREATED_AT:-}" "$d"
        fi
    done | LC_ALL=C sort | cut -f3-
    shopt -u nullglob
}

# List valid chains (those containing a completed 000_* full base) for an `incremental` job (oldest -> newest)
zb_list_valid_chains() {
    local job_root="$1"
    local c base_ok f cp_num base_created
    [[ -d "$job_root" ]] || return 0
    shopt -s nullglob
    for c in \
        "$job_root"/chain-* \
        "$job_root"/chain_* \
        "$job_root"/chains/chain-* \
        "$job_root"/chains/chain_*; do
        [[ -d "$c" && ! -L "$c" ]] || continue
        base_ok=0
        cp_num=0
        base_created=""
        for f in "$c"/000_backup-full-* "$c"/000_full_*; do
            if [[ -d "$f" && -f "$f/manifest" ]] && zb_read_manifest_meta "$f/manifest"; then
                base_ok=1
                cp_num="${MF_CHECKPOINT_TO:-0}"
                [[ "$cp_num" =~ ^[0-9]+$ ]] || cp_num=0
                base_created="${MF_CREATED_AT:-}"
                break
            fi
        done
        (( base_ok == 1 )) && printf '%012d\t%s\t%s\n' "$cp_num" "$base_created" "$c"
    done | LC_ALL=C sort | cut -f3-
    shopt -u nullglob
}

# List valid step directories inside a chain (000_backup-full-*, 001_backup-incremental-*, ...) sorted in order
zb_list_chain_steps() {
    local chain_dir="$1"
    local s
    [[ -d "$chain_dir" ]] || return 0
    shopt -s nullglob
    for s in "$chain_dir"/[0-9][0-9][0-9]_*; do
        [[ -d "$s" && ! -L "$s" && -f "$s/manifest" ]] && printf '%s\n' "$s"
    done | LC_ALL=C sort
    shopt -u nullglob
}

# Prune old snapshots/chains according to KEEP_COUNT and timing (`before` reserves 1 slot for upcoming backup)
zb_prune_job_storage() {
    local job_root="$1"
    local btype="$2"
    local keep="$3"
    local phase="$4"   # before | after

    local target_keep="$keep"
    if [[ "$phase" == "before" ]]; then
        # Never delete the sole remaining valid backup/chain before creating a new one!
        if (( keep <= 1 )); then
            zb_log "Retention note: KEEP_COUNT=$keep with PRUNE_TIMING=before -> preserving the last existing backup until the new run completes."
            return 0
        fi
        target_keep=$((keep - 1))
    fi

    local -a items=()
    local it
    if [[ "$btype" == "full" ]]; then
        while IFS= read -r it; do
            [[ -n "$it" ]] && items+=("$it")
        done < <(zb_list_full_job_snapshots "$job_root")
    else
        while IFS= read -r it; do
            [[ -n "$it" ]] && items+=("$it")
        done < <(zb_list_valid_chains "$job_root")
    fi

    local total="${#items[@]}"
    if (( total <= target_keep )); then
        return 0
    fi

    local remove_cnt=$((total - target_keep))
    local idx=0
    while (( idx < remove_cnt )); do
        local victim="${items[$idx]}"
        if [[ -d "$victim" && ! -L "$victim" ]]; then
            zb_log "Pruning expired backup (${phase}, keeping ${keep}): $victim"
            rm -rf -- "$victim"
        fi
        idx=$((idx + 1))
    done
    return 0
}

# Decide whether an `incremental` job should open a new Full chain or append an Incremental step.
# Sets globals: ZB_PLAN_STEP_TYPE (full|incr), ZB_PLAN_CHAIN_DIR, ZB_PLAN_SEQ, ZB_PLAN_PARENT_ID, ZB_PLAN_CP_FROM
zb_plan_incremental_step() {
    local job_root="$1"
    local force_full="${2:-0}"
    local stamp="$3"

    ZB_PLAN_STEP_TYPE="full"
    ZB_PLAN_CHAIN_DIR="$(zb_unique_path "$job_root/chain-${stamp}")"
    ZB_PLAN_SEQ=0
    ZB_PLAN_PARENT_ID="none"
    ZB_PLAN_CP_FROM=0

    if [[ "$force_full" == "1" ]]; then
        zb_log "Force-full requested (--force-full): starting new chain ${ZB_PLAN_CHAIN_DIR##*/}."
        return 0
    fi

    local -a chains=()
    local c
    while IFS= read -r c; do
        [[ -n "$c" ]] && chains+=("$c")
    done < <(zb_list_valid_chains "$job_root")

    if (( ${#chains[@]} == 0 )); then
        zb_log "No existing Full base chain found: automatically starting initial Full chain (${ZB_PLAN_CHAIN_DIR##*/})."
        return 0
    fi

    local latest_chain="${chains[$((${#chains[@]} - 1))]}"
    local -a steps=()
    local s
    while IFS= read -r s; do
        [[ -n "$s" ]] && steps+=("$s")
    done < <(zb_list_chain_steps "$latest_chain")

    if (( ${#steps[@]} == 0 )); then
        return 0
    fi

    local base_step="${steps[0]}"
    local last_step="${steps[$((${#steps[@]} - 1))]}"
    local incr_count=$(( ${#steps[@]} - 1 ))

    zb_read_manifest_meta "$last_step/manifest" || return 0
    local last_cp_to="$MF_CHECKPOINT_TO"
    local last_id="$MF_BACKUP_ID"

    zb_read_manifest_meta "$base_step/manifest" || return 0
    local base_date_ymd
    base_date_ymd="$(date -d "${MF_CREATED_AT:-}" '+%Y-%m-%d' 2>/dev/null || printf '%s' "${MF_CREATED_AT%%T*}")"
    local today_ymd today_dow today_dom
    today_ymd="$(date '+%Y-%m-%d')"
    today_dow="$(date '+%w')"
    today_dom="$(date '+%-d')"

    local need_new_full=0
    case "$FULL_CYCLE_MODE" in
        max_incr)
            if (( incr_count >= FULL_CYCLE_VALUE )); then
                zb_log "Reached FULL_CYCLE_VALUE=$FULL_CYCLE_VALUE incrementals in current chain -> starting new Full chain."
                need_new_full=1
            fi
            ;;
        weekly)
            if [[ "$today_dow" == "$FULL_CYCLE_VALUE" && "$base_date_ymd" != "$today_ymd" ]]; then
                zb_log "Scheduled weekly Full day (DOW=$today_dow) reached -> starting new Full chain."
                need_new_full=1
            fi
            ;;
        monthly)
            if [[ "$today_dom" == "$FULL_CYCLE_VALUE" && "$base_date_ymd" != "$today_ymd" ]]; then
                zb_log "Scheduled monthly Full day (DOM=$today_dom) reached -> starting new Full chain."
                need_new_full=1
            fi
            ;;
    esac

    if (( need_new_full == 1 )); then
        return 0
    fi

    ZB_PLAN_STEP_TYPE="incr"
    ZB_PLAN_CHAIN_DIR="$latest_chain"
    ZB_PLAN_SEQ="${#steps[@]}"
    ZB_PLAN_PARENT_ID="$last_id"
    # Overlap buffer of 300 seconds (5 minutes) prevents boundary mail loss across midnight/clock drift
    if [[ "$last_cp_to" =~ ^[0-9]+$ ]] && (( last_cp_to > 300 )); then
        ZB_PLAN_CP_FROM=$((last_cp_to - 300))
    else
        ZB_PLAN_CP_FROM="$last_cp_to"
    fi
    return 0
}

# Filter active accounts according to SCOPE_MODE / SCOPE_VALUES
zb_filter_accounts_by_scope() {
    local all_file="$1"
    local out_file="$2"
    local scope_mode="$3"
    local scope_values="$4"

    if [[ "$scope_mode" == "all" ]]; then
        cp -f -- "$all_file" "$out_file"
        return 0
    fi

    : > "$out_file"
    local -a targets=()
    local item
    IFS=',' read -r -a targets <<< "$scope_values"
    for item in "${targets[@]}"; do
        item="$(zb_trim "$item")"
        [[ -n "$item" ]] || continue
        if [[ "$scope_mode" == "domains" ]]; then
            awk -v dom="@${item}" '
                length($0) > length(dom) && substr($0, length($0) - length(dom) + 1) == dom { print }
            ' "$all_file" >> "$out_file"
        elif [[ "$scope_mode" == "accounts" ]]; then
            if grep -Fxq -- "$item" "$all_file"; then
                printf '%s\n' "$item" >> "$out_file"
            else
                # Check if account exists even if non-active
                if zmprov -l ga "$item" zimbraId >/dev/null 2>&1; then
                    printf '%s\n' "$item" >> "$out_file"
                else
                    zb_log "WARNING: Scoped account not found on Zimbra server: $item"
                fi
            fi
        fi
    done
    LC_ALL=C sort -u -o "$out_file" "$out_file"
}

# Export global & per-account LDAP metadata into staging snapshot directory
zb_export_metadata_stage() {
    local stage_dir="$1"
    local scope_mode="$2"
    local scope_values="$3"

    mkdir -p -m 700 -- \
        "$stage_dir/domains" \
        "$stage_dir/admins" \
        "$stage_dir/dl" \
        "$stage_dir/accounts" \
        "$stage_dir/passwords" \
        "$stage_dir/attributes" \
        "$stage_dir/aliases" \
        "$stage_dir/signatures" \
        "$stage_dir/filters" \
        "$stage_dir/mailboxes"

    zb_log "Exporting domains, administrators, and distribution lists..."
    local all_doms
    all_doms="$(mktemp "$ZB_RUN_DIR/.doms.XXXXXX")" || return 1
    zmprov -l gad 2>/dev/null | tr -d '\r' | LC_ALL=C sort -u > "$all_doms"

    if [[ "$scope_mode" == "domains" ]]; then
        : > "$stage_dir/domains/domains.txt"
        local -a dlist=()
        local d
        IFS=',' read -r -a dlist <<< "$scope_values"
        for d in "${dlist[@]}"; do
            d="$(zb_trim "$d")"
            grep -Fxq -- "$d" "$all_doms" && printf '%s\n' "$d" >> "$stage_dir/domains/domains.txt"
        done
    elif [[ "$scope_mode" == "accounts" ]]; then
        : > "$stage_dir/domains/domains.txt"
        local -a alist=()
        local a d
        IFS=',' read -r -a alist <<< "$scope_values"
        for a in "${alist[@]}"; do
            a="$(zb_trim "$a")"
            d="${a#*@}"
            if [[ -n "$d" && "$d" != "$a" ]] && grep -Fxq -- "$d" "$all_doms"; then
                printf '%s\n' "$d" >> "$stage_dir/domains/domains.txt"
            fi
        done
        LC_ALL=C sort -u -o "$stage_dir/domains/domains.txt" "$stage_dir/domains/domains.txt"
    else
        cp -f -- "$all_doms" "$stage_dir/domains/domains.txt"
    fi
    rm -f -- "$all_doms"

    local dom
    while IFS= read -r dom <&3; do
        [[ -n "$dom" ]] || continue
        zmprov -l gd "$dom" > "$stage_dir/domains/${dom}.ldif" 2>/dev/null || return 1
    done 3< "$stage_dir/domains/domains.txt"

    zmprov -l gaaa 2>/dev/null | tr -d '\r' | LC_ALL=C sort -u > "$stage_dir/admins/admins.txt" || true

    local all_dls
    all_dls="$(mktemp "$ZB_RUN_DIR/.dls.XXXXXX")" || return 1
    zmprov -l gadl 2>/dev/null | tr -d '\r' | LC_ALL=C sort -u > "$all_dls" || true
    : > "$stage_dir/dl/distribution_lists.txt"
    local dl
    while IFS= read -r dl <&3; do
        [[ -n "$dl" ]] || continue
        if [[ "$scope_mode" == "domains" || "$scope_mode" == "accounts" ]]; then
            local dl_dom="${dl#*@}"
            grep -Fxq -- "$dl_dom" "$stage_dir/domains/domains.txt" || continue
        fi
        printf '%s\n' "$dl" >> "$stage_dir/dl/distribution_lists.txt"
        zmprov -l gdl "$dl" > "$stage_dir/dl/${dl}.ldif" 2>/dev/null || true
        # Extract structured DL attributes, aliases, and members from LDIF
        zb_extract_dl_artifacts "$stage_dir/dl/${dl}.ldif" "$stage_dir" "$dl" || true
        # Fallback to gdlm only if members were not already populated by gdl
        if [[ ! -s "$stage_dir/dl/${dl}.members" ]]; then
            zmprov -l gdlm "$dl" 2>/dev/null | tr -d '\r' | awk '!/^#/ && /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/' > "$stage_dir/dl/${dl}.members" || true
        fi
    done 3< "$all_dls"
    rm -f -- "$all_dls"

    local all_acc
    all_acc="$(mktemp "$ZB_RUN_DIR/.all_acc.XXXXXX")" || return 1
    zb_list_active_accounts "$all_acc" || { rm -f -- "$all_acc"; return 1; }
    zb_filter_accounts_by_scope "$all_acc" "$stage_dir/accounts/active_accounts.txt" "$scope_mode" "$scope_values"
    rm -f -- "$all_acc"

    # Strictly exclude distribution lists / groups so they are never processed as mailbox accounts
    if [[ -s "$stage_dir/dl/distribution_lists.txt" && -s "$stage_dir/accounts/active_accounts.txt" ]]; then
        local filtered_acc
        filtered_acc="$(mktemp "$ZB_RUN_DIR/.filtered_acc.XXXXXX")"
        grep -Fvxf "$stage_dir/dl/distribution_lists.txt" "$stage_dir/accounts/active_accounts.txt" > "$filtered_acc" || true
        mv -f -- "$filtered_acc" "$stage_dir/accounts/active_accounts.txt"
    fi

    if [[ ! -s "$stage_dir/accounts/active_accounts.txt" ]]; then
        zb_err "No active accounts matched backup scope ($scope_mode ${scope_values})."
        return 1
    fi

    local total_acc idx=0 email exported_count=0
    total_acc="$(wc -l < "$stage_dir/accounts/active_accounts.txt" | awk '{print $1}')"
    zb_log "Exporting LDAP metadata, password hashes, signatures, and Sieve filters for $total_acc account(s)..."

    local valid_acc_tmp
    valid_acc_tmp="$(mktemp "$ZB_RUN_DIR/.valid_accs.XXXXXX")" || return 1

    while IFS= read -r email <&3; do
        [[ -n "$email" ]] || continue
        idx=$((idx + 1))
        local ldif_path="$stage_dir/accounts/${email}.ldif"
        if ! zmprov -l ga "$email" > "$ldif_path" 2>/dev/null || [[ ! -s "$ldif_path" ]]; then
            zb_warn "Skipping non-account address or inaccessible mailbox: $email"
            rm -f -- "$ldif_path"
            continue
        fi
        if ! zb_extract_account_artifacts "$ldif_path" "$stage_dir" "$email"; then
            zb_warn "Warning extracting artifacts for account: $email"
        fi
        zb_export_account_signatures "$email" "$stage_dir/signatures/${email}.sigs" || true
        printf '%s\n' "$email" >> "$valid_acc_tmp"
        exported_count=$((exported_count + 1))
    done 3< "$stage_dir/accounts/active_accounts.txt"

    if (( total_acc > 0 && exported_count == 0 )); then
        rm -f -- "$valid_acc_tmp"
        zb_err "Failed to export LDAP record for any account in scope."
        return 1
    fi

    mv -f -- "$valid_acc_tmp" "$stage_dir/accounts/active_accounts.txt"

    return 0
}

# Single account worker invoked in background for parallel mailbox export
zb_backup_mailbox_worker() {
    # Close inherited lock FD 9 and saved stdio FDs 7/8 so workers never hold operation.lock open
    exec 9>&- 7>&- 8>&- 2>/dev/null || true
    local idx="$1"
    local total="$2"
    local email="$3"
    local stage_dir="$4"
    local step_type="$5"
    local cp_from="$6"
    local auth_cfg="$7"
    local fail_dir="$8"

    local out_tgz="$stage_dir/mailboxes/${email}.tgz"
    if zb_export_mailbox_archive "$email" "$out_tgz" "$step_type" "$cp_from" "$auth_cfg"; then
        if [[ -f "$out_tgz" ]]; then
            local sz
            sz="$(wc -c < "$out_tgz" | awk '{print $1}')"
            zb_log "  [OK] ($idx/$total) $email ($(zb_human_bytes "$sz"))"
        else
            zb_log "  [OK] ($idx/$total) $email (incremental: no new items)"
        fi
    else
        zb_log "  [FAIL] ($idx/$total) $email - mailbox export failed after 3 attempts"
        printf '%s\n' "$email" > "$fail_dir/${idx}.fail"
    fi
}

zb_export_mailboxes_parallel() {
    local stage_dir="$1"
    local step_type="$2"
    local cp_from="$3"
    local parallel_limit="$4"

    local acc_file="$stage_dir/accounts/active_accounts.txt"
    local total
    total="$(wc -l < "$acc_file" | awk '{print $1}')"

    # Prepare shared admin auth config (refreshed per batch / elapsed age)
    zb_ensure_auth_cfg 1 || zb_log "WARNING: Could not acquire ZM_ADMIN_AUTH_TOKEN; falling back to zmmailbox CLI."

    local fail_dir
    fail_dir="$(mktemp -d "$ZB_RUN_DIR/.workers_fail.XXXXXX")" || return 1

    zb_log "Exporting mailboxes ($step_type) for $total account(s) with $parallel_limit parallel worker(s)..."

    ZB_ACTIVE_WORKER_PIDS=()
    local -a pids=()
    local idx=0 email batch_counter=0 now_ts=0
    while IFS= read -r email <&3; do
        [[ -n "$email" ]] || continue
        idx=$((idx + 1))
        batch_counter=$((batch_counter + 1))

        # Re-check free disk space every 10 accounts so large runs never fill the filesystem
        if (( idx > 1 && (idx - 1) % 10 == 0 )); then
            if ! zb_check_disk_space "$stage_dir" "$DISK_WARN_PERCENT" "$DISK_MIN_FREE_MB"; then
                zb_terminate_active_workers
                rm -rf -- "$fail_dir"
                return 1
            fi
        fi

        # Refresh admin auth token if older than 1 hour without blocking running workers
        now_ts="$(date +%s)"
        if (( ZB_AUTH_TOKEN_TIME > 0 && (now_ts - ZB_AUTH_TOKEN_TIME) >= 3600 )); then
            zb_ensure_auth_cfg 1 || true
        fi

        zb_backup_mailbox_worker "$idx" "$total" "$email" "$stage_dir" "$step_type" "$cp_from" "${ZB_AUTH_CFG_FILE:-}" "$fail_dir" &
        pids+=("$!")
        ZB_ACTIVE_WORKER_PIDS=("${pids[@]}")

        while (( ${#pids[@]} >= parallel_limit )); do
            local -a still_running=()
            local found_exited=0 p
            for p in "${pids[@]}"; do
                if kill -0 "$p" 2>/dev/null; then
                    still_running+=("$p")
                else
                    wait "$p" || true
                    found_exited=1
                fi
            done
            pids=("${still_running[@]+"${still_running[@]}"}")
            ZB_ACTIVE_WORKER_PIDS=("${pids[@]+"${pids[@]}"}")
            if (( found_exited == 0 && ${#pids[@]} >= parallel_limit )); then
                sleep 0.2
            fi
        done
    done 3< "$acc_file"

    local rem_pid
    for rem_pid in "${pids[@]+"${pids[@]}"}"; do
        wait "$rem_pid" || true
    done
    ZB_ACTIVE_WORKER_PIDS=()

    shopt -s nullglob
    local -a fails=("$fail_dir"/*.fail)
    shopt -u nullglob
    local fail_cnt="${#fails[@]}"
    if (( fail_cnt > 0 )); then
        local failed_emails
        failed_emails="$(cat "$fail_dir"/*.fail | tr '\n' ' ')"
        rm -rf -- "$fail_dir"
        zb_err "Mailbox export failed for ${fail_cnt}/${total} account(s): ${failed_emails}"
        return 1
    fi

    rm -rf -- "$fail_dir"
    return 0
}

# Run a configured job in an isolated subshell so lock FD & tee stdout close cleanly when returning to TUI.
zb_run_job() (
    local job_id="$1"
    shift || true
    local from_cron=0
    local force_full=0

    while (( $# > 0 )); do
        case "$1" in
            --cron) from_cron=1; shift ;;
            --force-full) force_full=1; shift ;;
            *) zb_err "Unknown 'job run' option: $1"; return 1 ;;
        esac
    done

    zb_load_settings || return 1
    zb_job_load "$job_id" || return 1
    zb_require_zimbra_cli || return 1

    zb_acquire_lock || {
        (( from_cron == 1 )) && zb_notify "warn" "Job '$JOB_ID' skipped" "Another backup or restore process is currently holding the lock."
        return 1
    }
    zb_start_run_log "job_${JOB_ID}"

    local start_epoch end_epoch duration_sec
    start_epoch="$(date +%s)"
    local stage_dir=""

    cleanup_job_run() {
        local rc=$?
        trap - EXIT INT TERM HUP
        zb_terminate_active_workers
        zb_cleanup_auth_token
        if [[ -n "${stage_dir:-}" && -d "$stage_dir" && ! -L "$stage_dir" ]]; then
            zb_log "Cleaning up incomplete staging directory: $stage_dir"
            rm -rf -- "$stage_dir"
        fi
        zb_close_run_log
        return "$rc"
    }
    trap cleanup_job_run EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    zb_log "============================================================"
    zb_log "STARTING BACKUP JOB: $JOB_ID ($JOB_NAME) | mode=$BACKUP_TYPE"
    zb_log "============================================================"

    local target_base job_root eff_req_mount="$REQUIRE_MOUNTPOINT"
    if [[ "${JOB_REQUIRE_MOUNT:-inherit}" == "yes" || "${JOB_REQUIRE_MOUNT:-inherit}" == "no" ]]; then
        eff_req_mount="$JOB_REQUIRE_MOUNT"
    fi
    target_base="$(zb_job_effective_target_dir)"
    if ! zb_check_backup_dir "$target_base" "$eff_req_mount" "no"; then
        zb_notify "error" "Backup Job '$JOB_ID' failed" "Target storage check failed: $target_base. Log: $ZB_CURRENT_LOG"
        return 1
    fi
    if ! zb_check_disk_space "$target_base" "$DISK_WARN_PERCENT" "$DISK_MIN_FREE_MB"; then
        zb_notify "error" "Backup Job '$JOB_ID' aborted (low disk space)" "Path: $target_base. Log: $ZB_CURRENT_LOG"
        return 1
    fi
    if zb_same_filesystem "$target_base" "$ZB_ZIMBRA_HOME"; then
        zb_log "WARNING: Backup storage '$target_base' shares the same filesystem as '$ZB_ZIMBRA_HOME'. Consider mounting a dedicated disk/NFS."
    fi

    job_root="$(zb_job_storage_root)"
    zb_check_no_symlinks "$job_root" || return 1
    mkdir -p -m 700 -- "$job_root" || return 1
    [[ ! -L "$job_root" ]] || { zb_err "Job storage root must not be a symlink: $job_root"; return 1; }

    local stamp cp_to final_dir backup_id step_type chain_id chain_seq parent_id cp_from snap_leaf
    stamp="$(date '+%d-%m-%Y_%H%M%S')"
    cp_to="$(date +%s)"

    if [[ "$BACKUP_TYPE" == "full" ]]; then
        if [[ "$PRUNE_TIMING" == "before" ]]; then
            zb_prune_job_storage "$job_root" "$BACKUP_TYPE" "$KEEP_COUNT" "before"
        fi
        step_type="full"
        chain_id="standalone"
        chain_seq="0"
        parent_id="none"
        cp_from="0"
        final_dir="$(zb_unique_path "$job_root/backup-full-${stamp}")"
        snap_leaf="${final_dir##*/}"
        backup_id="full/${JOB_ID}/${snap_leaf}"
        stage_dir="$job_root/.pending.${snap_leaf}.$$"
    else
        zb_plan_incremental_step "$job_root" "$force_full" "$stamp"
        step_type="$ZB_PLAN_STEP_TYPE"
        if [[ "$PRUNE_TIMING" == "before" && "$step_type" == "full" ]]; then
            zb_prune_job_storage "$job_root" "$BACKUP_TYPE" "$KEEP_COUNT" "before"
        fi
        zb_check_no_symlinks "$ZB_PLAN_CHAIN_DIR" || return 1
        mkdir -p -m 700 -- "$ZB_PLAN_CHAIN_DIR" || return 1
        [[ ! -L "$ZB_PLAN_CHAIN_DIR" ]] || { zb_err "Chain directory must not be a symlink: $ZB_PLAN_CHAIN_DIR"; return 1; }
        chain_id="${ZB_PLAN_CHAIN_DIR##*/}"
        chain_seq="$ZB_PLAN_SEQ"
        parent_id="$ZB_PLAN_PARENT_ID"
        cp_from="$ZB_PLAN_CP_FROM"
        local seq_pad step_label
        seq_pad="$(printf '%03d' "$chain_seq")"
        if [[ "$step_type" == "full" ]]; then
            step_label="backup-full"
        else
            step_label="backup-incremental"
        fi
        final_dir="$(zb_unique_path "${ZB_PLAN_CHAIN_DIR}/${seq_pad}_${step_label}-${stamp}")"
        snap_leaf="${final_dir##*/}"
        backup_id="incremental/${JOB_ID}/${chain_id}/${snap_leaf}"
        stage_dir="${ZB_PLAN_CHAIN_DIR}/.pending.${snap_leaf}.$$"
    fi

    mkdir -p -m 700 -- "$stage_dir" || return 1

    local fail_reason=""
    if ! zb_export_metadata_stage "$stage_dir" "$SCOPE_MODE" "$SCOPE_VALUES"; then
        fail_reason="LDAP metadata / account export failed"
    elif ! zb_export_mailboxes_parallel "$stage_dir" "$step_type" "$cp_from" "$PARALLEL_JOBS"; then
        fail_reason="One or more mailbox exports failed"
    else
        zb_write_manifest "$stage_dir" "$backup_id" "$JOB_ID" "$step_type" "$chain_id" "$chain_seq" "$parent_id" "$cp_from" "$cp_to"
    fi

    if [[ -n "$fail_reason" ]]; then
        zb_log "ERROR: Backup Job '$JOB_ID' failed: $fail_reason"
        zb_notify "error" "Backup Job '$JOB_ID' FAILED" "Reason: ${fail_reason}
Log: ${ZB_CURRENT_LOG}"
        return 1
    fi

    mv -- "$stage_dir" "$final_dir"
    stage_dir="" # committed; prevent cleanup_job_run from deleting

    zb_prune_job_storage "$job_root" "$BACKUP_TYPE" "$KEEP_COUNT" "after"

    end_epoch="$(date +%s)"
    duration_sec=$((end_epoch - start_epoch))
    zb_read_manifest_meta "$final_dir/manifest" || true

    local human_sz
    human_sz="$(zb_human_bytes "${MF_TOTAL_BYTES:-0}")"
    zb_log "============================================================"
    zb_log "COMPLETED JOB '$JOB_ID' (${step_type^^}) | Accounts: ${MF_ACCOUNTS_COUNT} | Size: ${human_sz} | Duration: ${duration_sec}s"
    zb_log "Location: $final_dir"
    zb_log "============================================================"

    zb_notify "ok" "Backup Job '$JOB_ID' (${step_type^^}) succeeded" \
"Backup ID: ${backup_id}
Accounts: ${MF_ACCOUNTS_COUNT} (archives: ${MF_ARCHIVES_COUNT}, unchanged: ${MF_EMPTY_DELTA_COUNT})
Size: ${human_sz}
Duration: ${duration_sec}s
Path: ${final_dir}"
    return 0
)

# Ad-hoc single/multi-account Full backup (used from TUI or `zimbra-backup backup user <emails> [--dir <dir>] [--require-mount yes|no]`)
zb_run_adhoc_users() (
    local emails_csv="$1"
    local custom_dir="${2:-}"
    local req_mount_override="${3:-}"

    zb_load_settings || return 1
    zb_require_zimbra_cli || return 1
    zb_validate_scope_values "accounts" "$emails_csv" || return 1

    local base_dir="${custom_dir:-$DEFAULT_BACKUP_DIR}"
    base_dir="$(zb_normalize_dir_input "$base_dir")"
    local stage_dir=""
    zb_acquire_lock || return 1
    zb_start_run_log "adhoc_user"

    cleanup_adhoc() {
        local rc=$?
        trap - EXIT INT TERM HUP
        zb_terminate_active_workers
        zb_cleanup_auth_token
        if [[ -n "${stage_dir:-}" && -d "$stage_dir" && ! -L "$stage_dir" ]]; then
            rm -rf -- "$stage_dir"
        fi
        zb_close_run_log
        return "$rc"
    }
    trap cleanup_adhoc EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    local eff_req_mount="$REQUIRE_MOUNTPOINT"
    if [[ "$req_mount_override" == "yes" || "$req_mount_override" == "no" ]]; then
        eff_req_mount="$req_mount_override"
    fi

    zb_check_backup_dir "$base_dir" "$eff_req_mount" "no" || return 1
    zb_check_disk_space "$base_dir" "$DISK_WARN_PERCENT" "$DISK_MIN_FREE_MB" || return 1
    if zb_same_filesystem "$base_dir" "$ZB_ZIMBRA_HOME"; then
        zb_log "WARNING: Backup storage '$base_dir' shares the same filesystem as '$ZB_ZIMBRA_HOME'. Consider mounting a dedicated disk/NFS."
    fi

    local adhoc_root base_leaf="${base_dir##*/}"
    if [[ "${base_leaf,,}" == "account" ]]; then
        adhoc_root="$base_dir"
    else
        adhoc_root="$base_dir/account"
    fi
    zb_check_no_symlinks "$adhoc_root" || return 1
    mkdir -p -m 700 -- "$adhoc_root" || return 1
    [[ ! -L "$adhoc_root" ]] || { zb_err "Ad-hoc backup directory must not be a symlink: $adhoc_root"; return 1; }

    local -a raw_emails=() clean_emails=()
    local em
    IFS=',' read -r -a raw_emails <<< "$emails_csv"
    for em in "${raw_emails[@]}"; do
        em="$(zb_trim "$em")"
        [[ -n "$em" ]] && clean_emails+=("$em")
    done
    local acct_tag="${clean_emails[0]}"
    if (( ${#clean_emails[@]} > 1 )); then
        acct_tag="${clean_emails[0]}+$(( ${#clean_emails[@]} - 1 ))more"
    fi

    local stamp cp_to final_dir backup_id snap_leaf
    stamp="$(date '+%d-%m-%Y_%H%M%S')"
    cp_to="$(date +%s)"
    final_dir="$(zb_unique_path "$adhoc_root/backup-${acct_tag}-${stamp}")"
    snap_leaf="${final_dir##*/}"
    backup_id="account/${snap_leaf}"
    stage_dir="$adhoc_root/.pending.${snap_leaf}.$$"

    mkdir -p -m 700 -- "$stage_dir"
    zb_log "Starting ad-hoc Full backup for account(s): $emails_csv"
    zb_export_metadata_stage "$stage_dir" "accounts" "$emails_csv" || return 1
    zb_export_mailboxes_parallel "$stage_dir" "full" "0" "2" || return 1
    zb_write_manifest "$stage_dir" "$backup_id" "account" "full" "standalone" "0" "none" "0" "$cp_to"

    mv -- "$stage_dir" "$final_dir"
    stage_dir=""
    zb_log "Completed ad-hoc account backup at: $final_dir"
    return 0
)

# Scan and optionally remove leftover `.pending.*` directories when no backup lock is active
zb_clean_pending_dirs() (
    local scan_dir="${1:-}"
    zb_load_settings || return 1
    if [[ -n "$scan_dir" ]]; then
        scan_dir="$(zb_normalize_dir_input "$scan_dir")"
        zb_valid_safe_path "$scan_dir" || { zb_err "Invalid directory path: $scan_dir"; return 1; }
        zb_check_no_symlinks "$scan_dir" || return 1
    fi
    zb_acquire_lock || return 1

    local -a roots=()
    if [[ -n "$scan_dir" ]]; then
        roots+=("$scan_dir")
    else
        local jroot
        while IFS= read -r jroot; do
            [[ -n "$jroot" ]] && roots+=("$jroot")
        done < <(zb_list_job_storage_roots "" 1)
        if [[ -d "$DEFAULT_BACKUP_DIR/account" ]]; then
            roots+=("$DEFAULT_BACKUP_DIR/account")
        fi
        if [[ -d "$DEFAULT_BACKUP_DIR/manual-accounts" ]]; then
            roots+=("$DEFAULT_BACKUP_DIR/manual-accounts")
        fi
    fi

    local r p count=0
    for r in "${roots[@]+"${roots[@]}"}"; do
        [[ -d "$r" && ! -L "$r" ]] || continue
        zb_check_no_symlinks "$r" || continue
        while IFS= read -r -d '' p; do
            [[ -d "$p" && ! -L "$p" ]] || continue
            zb_info "Removing incomplete staging directory: $p"
            rm -rf -- "$p"
            count=$((count + 1))
        done < <(find "$r" -maxdepth 4 -type d -name '.pending.*' -print0 2>/dev/null)
    done
    zb_info "Cleaned $count incomplete '.pending.*' staging director(ies)."
)
