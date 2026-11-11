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

# Ensure target directory path does not collide if multiple runs occur on the same day
zb_unique_path() {
    local candidate="$1"
    local max_n=0 p sfx
    if [[ -e "$candidate" ]]; then
        max_n=1
    fi
    shopt -s nullglob
    for p in "${candidate}"_[0-9]*; do
        sfx="${p#"${candidate}_"}"
        if [[ "$sfx" =~ ^[0-9]+$ ]] && (( 10#$sfx > max_n )); then
            max_n=$((10#$sfx))
        fi
    done
    shopt -u nullglob
    if (( max_n == 0 )); then
        printf '%s' "$candidate"
        return 0
    fi
    printf '%s_%d' "$candidate" "$((max_n + 1))"
}

# List valid completed full snapshot directories for a `full` job (oldest -> newest by manifest timestamp)
zb_list_full_job_snapshots() {
    local job_root="$1"
    local filter_jid="${2:-}"
    local d cp_num
    [[ -d "$job_root" ]] || return 0
    shopt -s nullglob
    for d in \
        "$job_root"/full-* \
        "$job_root"/backup-full-* \
        "$job_root"/snapshots/backup-full-* \
        "$job_root"/snapshots/full_*; do
        [[ -d "$d" && ! -L "$d" && -f "$d/manifest" ]] || continue
        if zb_read_manifest_meta "$d/manifest"; then
            if [[ -n "$filter_jid" && -n "${MF_JOB_ID:-}" && "$MF_JOB_ID" != "$filter_jid" ]]; then
                continue
            fi
            cp_num="${MF_CHECKPOINT_TO:-0}"
            [[ "$cp_num" =~ ^[0-9]+$ ]] || cp_num=0
            printf '%012d\t%s\t%s\n' "$cp_num" "${MF_CREATED_AT:-}" "$d"
        fi
    done | LC_ALL=C sort | cut -f3-
    shopt -u nullglob
}

# List valid chains (flat base `full-*` or legacy `chain-*` containing a completed 000_* full base)
# for an `incremental` job (oldest -> newest)
zb_list_valid_chains() {
    local job_root="$1"
    local filter_jid="${2:-}"
    local c base_ok f cp_num base_created
    [[ -d "$job_root" ]] || return 0
    shopt -s nullglob
    {
        for f in "$job_root"/full-*; do
            [[ -d "$f" && ! -L "$f" && -f "$f/manifest" ]] || continue
            if zb_read_manifest_meta "$f/manifest"; then
                [[ "${MF_BACKUP_TYPE:-}" == "full" && "${MF_CHAIN_SEQ:-0}" == "0" ]] || continue
                if [[ -n "$filter_jid" && -n "${MF_JOB_ID:-}" && "$MF_JOB_ID" != "$filter_jid" ]]; then
                    continue
                fi
                cp_num="${MF_CHECKPOINT_TO:-0}"
                [[ "$cp_num" =~ ^[0-9]+$ ]] || cp_num=0
                base_created="${MF_CREATED_AT:-}"
                printf '%012d\t%s\t%s\n' "$cp_num" "$base_created" "$f"
            fi
        done
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
                    if [[ -n "$filter_jid" && -n "${MF_JOB_ID:-}" && "$MF_JOB_ID" != "$filter_jid" ]]; then
                        continue
                    fi
                    base_ok=1
                    cp_num="${MF_CHECKPOINT_TO:-0}"
                    [[ "$cp_num" =~ ^[0-9]+$ ]] || cp_num=0
                    base_created="${MF_CREATED_AT:-}"
                    break
                fi
            done
            (( base_ok == 1 )) && printf '%012d\t%s\t%s\n' "$cp_num" "$base_created" "$c"
        done
    } | LC_ALL=C sort | cut -f3-
    shopt -u nullglob
}

# List valid step directories inside a chain (flat `full-*` + `NNN-incremental-*` sharing chain_id,
# or legacy `000_backup-full-*`, `001_backup-incremental-*` inside `chain-*`) sorted in sequence order.
zb_list_chain_steps() {
    local chain_ref="$1"
    local explicit_chain_id="${2:-}"
    local s parent_dir target_chain_id seq_num
    [[ -d "$chain_ref" ]] || return 0
    shopt -s nullglob
    if [[ -f "$chain_ref/manifest" ]]; then
        parent_dir="${chain_ref%/*}"
        target_chain_id="$explicit_chain_id"
        if [[ -z "$target_chain_id" ]] && zb_read_manifest_meta "$chain_ref/manifest"; then
            target_chain_id="${MF_CHAIN_ID:-}"
        fi
        [[ -n "$target_chain_id" ]] || target_chain_id="${chain_ref##*/}"
        for s in \
            "$parent_dir"/full-* \
            "$parent_dir"/[0-9][0-9][0-9]-incremental-* \
            "$parent_dir"/[0-9][0-9][0-9]_*; do
            [[ -d "$s" && ! -L "$s" && -f "$s/manifest" ]] || continue
            if zb_read_manifest_meta "$s/manifest"; then
                if [[ "${MF_CHAIN_ID:-}" == "$target_chain_id" ]]; then
                    seq_num="${MF_CHAIN_SEQ:-0}"
                    [[ "$seq_num" =~ ^[0-9]+$ ]] || seq_num=0
                    printf '%06d\t%s\n' "$((10#$seq_num))" "$s"
                fi
            fi
        done | LC_ALL=C sort | cut -f2-
    elif [[ -n "$explicit_chain_id" && "$explicit_chain_id" != "${chain_ref##*/}" ]]; then
        for s in \
            "$chain_ref"/full-* \
            "$chain_ref"/[0-9][0-9][0-9]-incremental-* \
            "$chain_ref"/[0-9][0-9][0-9]_*; do
            [[ -d "$s" && ! -L "$s" && -f "$s/manifest" ]] || continue
            if zb_read_manifest_meta "$s/manifest"; then
                if [[ "${MF_CHAIN_ID:-}" == "$explicit_chain_id" ]]; then
                    seq_num="${MF_CHAIN_SEQ:-0}"
                    [[ "$seq_num" =~ ^[0-9]+$ ]] || seq_num=0
                    printf '%06d\t%s\n' "$((10#$seq_num))" "$s"
                fi
            fi
        done | LC_ALL=C sort | cut -f2-
    else
        for s in "$chain_ref"/[0-9][0-9][0-9]_*; do
            [[ -d "$s" && ! -L "$s" && -f "$s/manifest" ]] && printf '%s\n' "$s"
        done | LC_ALL=C sort
    fi
    shopt -u nullglob
}

# Prune old snapshots/chains according to KEEP_COUNT and timing (`before` reserves 1 slot for upcoming backup)
zb_prune_job_storage() {
    local job_root="$1"
    local btype="$2"
    local keep="$3"
    local phase="$4"   # before | after
    local filter_jid="${5:-}"

    if [[ "$btype" == "forever_incremental" ]]; then
        zb_ffi_prune_and_merge "$job_root" "$keep" "$phase" "$filter_jid"
        return $?
    fi

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
        done < <(zb_list_full_job_snapshots "$job_root" "$filter_jid")
    else
        while IFS= read -r it; do
            [[ -n "$it" ]] && items+=("$it")
        done < <(zb_list_valid_chains "$job_root" "$filter_jid")
    fi

    local total="${#items[@]}"
    if (( total <= target_keep )); then
        return 0
    fi

    local remove_cnt=$((total - target_keep))
    local idx=0
    while (( idx < remove_cnt )); do
        local victim="${items[$idx]}"
        if [[ ("$btype" == "incremental" || "$btype" == "synthetic_full") && -f "$victim/manifest" ]]; then
            local step_dir
            while IFS= read -r step_dir; do
                if [[ -d "$step_dir" && ! -L "$step_dir" ]]; then
                    zb_log "Pruning expired backup chain step (${phase}, keeping ${keep} chains): $step_dir"
                    rm -rf -- "$step_dir"
                fi
            done < <(zb_list_chain_steps "$victim")
            if [[ -d "$victim" && ! -L "$victim" ]]; then
                rm -rf -- "$victim"
            fi
        elif [[ -d "$victim" && ! -L "$victim" ]]; then
            zb_log "Pruning expired backup (${phase}, keeping ${keep}): $victim"
            rm -rf -- "$victim"
        fi
        idx=$((idx + 1))
    done
    return 0
}

# Decide whether an incremental/FFI/synthetic_full job should open a new Full chain, synthesize a Full, or append an Incremental step.
# Sets globals: ZB_PLAN_STEP_TYPE (full|synth_full|incr), ZB_PLAN_CHAIN_DIR, ZB_PLAN_CHAIN_ID, ZB_PLAN_SEQ, ZB_PLAN_PARENT_ID, ZB_PLAN_CP_FROM
zb_plan_incremental_step() {
    local job_root="$1"
    local force_full="${2:-0}"
    local stamp="$3"
    local filter_jid="${4:-}"
    local synthetic_full_flag="${5:-0}"

    ZB_PLAN_STEP_TYPE="full"
    ZB_PLAN_CHAIN_DIR="$job_root"
    ZB_PLAN_CHAIN_ID=""
    ZB_PLAN_SEQ=0
    ZB_PLAN_PARENT_ID="none"
    ZB_PLAN_CP_FROM=0

    local -a chains=()
    local c
    while IFS= read -r c; do
        [[ -n "$c" ]] && chains+=("$c")
    done < <(zb_list_valid_chains "$job_root" "$filter_jid")

    if (( ${#chains[@]} == 0 )); then
        zb_log "No existing Full base chain found: automatically starting initial Full chain in ${job_root}."
        if [[ "$BACKUP_TYPE" == "forever_incremental" ]]; then
            ZB_PLAN_CHAIN_ID="ffi-${filter_jid:-${JOB_ID:-default}}"
        fi
        return 0
    fi

    if [[ "$force_full" == "1" ]]; then
        if [[ "$BACKUP_TYPE" == "synthetic_full" ]]; then
            zb_log "Force-full requested on Synthetic Full job: triggering local Synthetic Full backup."
            synthetic_full_flag=1
        else
            zb_log "Force-full requested (--force-full): starting new Full chain in ${job_root}."
            return 0
        fi
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
    local base_chain_id="${MF_CHAIN_ID:-${base_step##*/}}"
    local base_date_ymd
    base_date_ymd="$(date -d "${MF_CREATED_AT:-}" '+%Y-%m-%d' 2>/dev/null || printf '%s' "${MF_CREATED_AT%%T*}")"
    local today_ymd today_dow today_dom
    today_ymd="$(date '+%Y-%m-%d')"
    today_dow="$(date '+%w')"
    today_dom="$(date '+%-d')"

    local need_new_full=0
    if [[ "$synthetic_full_flag" == "1" ]]; then
        need_new_full=1
    elif [[ "$BACKUP_TYPE" == "forever_incremental" ]]; then
        # Forever Forward Incremental never triggers a new Full from Zimbra
        need_new_full=0
    elif [[ "$BACKUP_TYPE" == "synthetic_full" ]]; then
        case "$FULL_CYCLE_MODE" in
            max_incr)
                if (( incr_count >= FULL_CYCLE_VALUE )); then
                    zb_log "Reached FULL_CYCLE_VALUE=$FULL_CYCLE_VALUE incrementals in current chain -> starting Synthetic Full."
                    need_new_full=1
                fi
                ;;
            weekly)
                if [[ "$today_dow" == "$FULL_CYCLE_VALUE" && "$base_date_ymd" != "$today_ymd" ]]; then
                    zb_log "Scheduled weekly Full day (DOW=$today_dow) reached -> starting Synthetic Full."
                    need_new_full=1
                fi
                ;;
            monthly)
                if [[ "$today_dom" == "$FULL_CYCLE_VALUE" && "$base_date_ymd" != "$today_ymd" ]]; then
                    zb_log "Scheduled monthly Full day (DOM=$today_dom) reached -> starting Synthetic Full."
                    need_new_full=1
                fi
                ;;
        esac
    else
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
    fi

    if (( need_new_full == 1 )); then
        if [[ "$BACKUP_TYPE" == "synthetic_full" || "$synthetic_full_flag" == "1" ]]; then
            ZB_PLAN_STEP_TYPE="synth_full"
            ZB_PLAN_CHAIN_DIR="$job_root"
            ZB_PLAN_CHAIN_ID=""
            ZB_PLAN_SEQ=0
            ZB_PLAN_PARENT_ID="none"
            if [[ "$last_cp_to" =~ ^[0-9]+$ ]] && (( last_cp_to > 300 )); then
                ZB_PLAN_CP_FROM=$((last_cp_to - 300))
            else
                ZB_PLAN_CP_FROM="$last_cp_to"
            fi
            return 0
        fi
        return 0
    fi

    ZB_PLAN_STEP_TYPE="incr"
    if [[ "$BACKUP_TYPE" == "forever_incremental" ]]; then
        ZB_PLAN_CHAIN_DIR="$job_root"
        ZB_PLAN_CHAIN_ID="ffi-${filter_jid:-${JOB_ID:-default}}"
    elif [[ -f "$latest_chain/manifest" ]]; then
        ZB_PLAN_CHAIN_DIR="$job_root"
        ZB_PLAN_CHAIN_ID="$base_chain_id"
    else
        ZB_PLAN_CHAIN_DIR="$latest_chain"
        ZB_PLAN_CHAIN_ID="$base_chain_id"
    fi
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

    # High-performance batch export via zmprov -l -f
    # Launches 1 single JVM command for all accounts instead of spawning 140+ separate JVM processes
    local batch_file batch_out batch_ok=0
    batch_file="$(mktemp "$ZB_RUN_DIR/.zmprov_ga_batch.XXXXXX")" || return 1
    batch_out="$(mktemp "$ZB_RUN_DIR/.zmprov_ga_out.XXXXXX")" || { rm -f -- "$batch_file"; return 1; }

    awk '{ print "ga " $1 }' "$stage_dir/accounts/active_accounts.txt" > "$batch_file"

    if zmprov -l -f "$batch_file" > "$batch_out" 2>/dev/null && [[ -s "$batch_out" ]]; then
        local split_accs_tmp
        split_accs_tmp="$(mktemp "$ZB_RUN_DIR/.split_accs.XXXXXX")" || return 1
        awk -v out_dir="$stage_dir/accounts" -v acc_list="$split_accs_tmp" '
            /^# name / {
                if (cur_out != "") close(cur_out)
                cur_email = $3
                sub(/\r$/, "", cur_email)
                if (cur_email != "") {
                    cur_out = out_dir "/" cur_email ".ldif"
                    print cur_email >> acc_list
                }
            }
            {
                if (cur_out != "") print > cur_out
            }
            END {
                if (cur_out != "") close(cur_out)
            }
        ' "$batch_out"

        if [[ -s "$split_accs_tmp" ]]; then
            while IFS= read -r email <&3; do
                [[ -n "$email" ]] || continue
                local ldif_path="$stage_dir/accounts/${email}.ldif"
                [[ -s "$ldif_path" ]] || continue
                if ! zb_extract_account_artifacts "$ldif_path" "$stage_dir" "$email"; then
                    zb_warn "Warning extracting artifacts for account: $email"
                fi
                if grep -qiE 'zimbraSignatureId|zimbraPrefMailSignature' "$ldif_path"; then
                    zb_export_account_signatures "$email" "$stage_dir/signatures/${email}.sigs" || true
                fi
                printf '%s\n' "$email" >> "$valid_acc_tmp"
                exported_count=$((exported_count + 1))
            done 3< "$split_accs_tmp"
            batch_ok=1
        fi
        rm -f -- "$split_accs_tmp"
    fi
    rm -f -- "$batch_file" "$batch_out"

    if (( batch_ok == 0 )); then
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
            if grep -qiE 'zimbraSignatureId|zimbraPrefMailSignature' "$ldif_path"; then
                zb_export_account_signatures "$email" "$stage_dir/signatures/${email}.sigs" || true
            fi
            printf '%s\n' "$email" >> "$valid_acc_tmp"
            exported_count=$((exported_count + 1))
        done 3< "$stage_dir/accounts/active_accounts.txt"
    fi

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

    # Pre-detect and export port & host configuration once so background worker subshells
    # never repeatedly spawn `zmprov` or `zmhostname` processes (eliminating 350+ JVM invocations)
    export ZB_REST_PORT="$(zb_detect_rest_port)"
    export ZB_ADMIN_PORT="$(zb_detect_admin_port)"
    export ZB_SERVER_HOST="$(zmhostname 2>/dev/null || hostname -f 2>/dev/null || printf 'localhost')"

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

# Merge a base mailbox archive and an incremental delta archive into an updated full archive
zb_merge_mailbox_archives() {
    local base_tgz="$1"
    local incr_tgz="$2"
    local out_tgz="$3"

    if [[ ! -f "$incr_tgz" ]]; then
        if [[ -f "$base_tgz" ]]; then
            ln "$base_tgz" "$out_tgz" 2>/dev/null || cp -p -- "$base_tgz" "$out_tgz" || return 1
        fi
        return 0
    fi

    if [[ ! -f "$base_tgz" ]]; then
        ln "$incr_tgz" "$out_tgz" 2>/dev/null || cp -p -- "$incr_tgz" "$out_tgz" || return 1
        return 0
    fi

    local work_dir
    work_dir="$(mktemp -d "$ZB_RUN_DIR/.merge_box.XXXXXX")" || return 1
    if ! tar -xzf "$base_tgz" -C "$work_dir" 2>/dev/null; then
        zb_err "Corrupted base archive during mailbox merge: $base_tgz"
        rm -rf -- "$work_dir"
        return 1
    fi
    if ! tar -xzf "$incr_tgz" -C "$work_dir" 2>/dev/null; then
        zb_err "Corrupted delta archive during mailbox merge: $incr_tgz"
        rm -rf -- "$work_dir"
        return 1
    fi
    if ! tar -czf "$out_tgz" -C "$work_dir" . 2>/dev/null; then
        zb_err "Failed to recompress merged mailbox archive: $out_tgz"
        rm -rf -- "$work_dir"
        return 1
    fi
    rm -rf -- "$work_dir"
    return 0
}

# Synthesize a single account mailbox archive by combining base and incremental steps in order
zb_synthesize_account_mailbox() {
    local email="$1"
    local out_tgz="$2"
    shift 2
    local -a src_dirs=("$@")

    local -a tgz_list=()
    local d tgz_file empty_file
    for d in "${src_dirs[@]}"; do
        tgz_file="$d/mailboxes/${email}.tgz"
        empty_file="$d/mailboxes/${email}.empty"
        if [[ -f "$tgz_file" ]]; then
            tgz_list+=("$tgz_file")
        fi
    done

    # Case 1: Account has 0 tar archives across the whole chain (all .empty or non-existent)
    if (( ${#tgz_list[@]} == 0 )); then
        touch "${out_tgz%.tgz}.empty"
        return 0
    fi

    # Case 2: Only 1 archive exists across all sources (unchanged since base, or only in 1 incr)
    if (( ${#tgz_list[@]} == 1 )); then
        local single_tgz="${tgz_list[0]}"
        ln "$single_tgz" "$out_tgz" 2>/dev/null || cp -p -- "$single_tgz" "$out_tgz" || return 1
        return 0
    fi

    # Case 3: Exactly 2 archives -> merge directly
    if (( ${#tgz_list[@]} == 2 )); then
        zb_merge_mailbox_archives "${tgz_list[0]}" "${tgz_list[1]}" "$out_tgz"
        return $?
    fi

    # Case 4: 3 or more archives -> unpack sequentially and recompress
    local work_dir
    work_dir="$(mktemp -d "$ZB_RUN_DIR/.synth_${email//[^A-Za-z0-9]/_}.XXXXXX")" || return 1

    local tgz_item
    for tgz_item in "${tgz_list[@]}"; do
        if ! tar -xzf "$tgz_item" -C "$work_dir" 2>/dev/null; then
            zb_err "Corrupted archive while synthesizing mailbox for $email: $tgz_item"
            rm -rf -- "$work_dir"
            return 1
        fi
    done

    if ! tar -czf "$out_tgz" -C "$work_dir" . 2>/dev/null; then
        zb_err "Failed to compress synthesized mailbox for $email"
        rm -rf -- "$work_dir"
        return 1
    fi

    rm -rf -- "$work_dir"
    return 0
}

# Worker for background mailbox synthesis
zb_synthesize_account_worker() {
    exec 9>&- 7>&- 8>&- 2>/dev/null || true
    local idx="$1"
    local total="$2"
    local email="$3"
    local stage_dir="$4"
    local fail_dir="$5"
    shift 5
    local -a src_dirs=("$@")

    local out_tgz="$stage_dir/mailboxes/${email}.tgz"
    if zb_synthesize_account_mailbox "$email" "$out_tgz" "${src_dirs[@]}"; then
        if [[ -f "$out_tgz" ]]; then
            local sz
            sz="$(wc -c < "$out_tgz" 2>/dev/null | awk '{print $1}')"
            zb_log "  [OK] ($idx/$total) $email (synthesized $(zb_human_bytes "$sz"))"
        else
            zb_log "  [OK] ($idx/$total) $email (synthesized: no items)"
        fi
    else
        zb_log "  [FAIL] ($idx/$total) $email - mailbox synthesis failed"
        printf '%s\n' "$email" > "$fail_dir/${idx}.fail"
    fi
}

# Synthesize all account mailboxes in parallel
zb_synthesize_mailboxes_parallel() {
    local stage_dir="$1"
    local parallel_limit="$2"
    shift 2
    local -a src_dirs=("$@")

    mkdir -p -m 700 -- "$stage_dir/mailboxes" || return 1
    local acc_file="$stage_dir/accounts/active_accounts.txt"
    if [[ ! -s "$acc_file" ]]; then
        local d f acc
        local tmp_acc
        tmp_acc="$(mktemp "$ZB_RUN_DIR/.synth_accs.XXXXXX")" || return 1
        for d in "${src_dirs[@]}"; do
            shopt -s nullglob
            for f in "$d/mailboxes"/*.tgz "$d/mailboxes"/*.empty; do
                acc="${f##*/}"
                acc="${acc%.tgz}"
                acc="${acc%.empty}"
                [[ -n "$acc" ]] && printf '%s\n' "$acc" >> "$tmp_acc"
            done
            shopt -u nullglob
        done
        mkdir -p -m 700 -- "$stage_dir/accounts"
        LC_ALL=C sort -u -o "$stage_dir/accounts/active_accounts.txt" "$tmp_acc"
        rm -f -- "$tmp_acc"
    fi

    local total
    total="$(wc -l < "$acc_file" | awk '{print $1}')"
    if (( total == 0 )); then
        zb_log "No accounts found for mailbox synthesis."
        return 0
    fi

    local fail_dir
    fail_dir="$(mktemp -d "$ZB_RUN_DIR/.synth_fail.XXXXXX")" || return 1

    zb_log "Synthesizing mailboxes for $total account(s) using $parallel_limit parallel worker(s)..."

    local -a pids=()
    local idx=0 email
    while IFS= read -r email <&3; do
        [[ -n "$email" ]] || continue
        idx=$((idx + 1))

        if (( idx > 1 && (idx - 1) % 10 == 0 )); then
            if ! zb_check_disk_space "$stage_dir" "$DISK_WARN_PERCENT" "$DISK_MIN_FREE_MB"; then
                zb_terminate_active_workers
                rm -rf -- "$fail_dir"
                return 1
            fi
        fi

        zb_synthesize_account_worker "$idx" "$total" "$email" "$stage_dir" "$fail_dir" "${src_dirs[@]}" &
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
        zb_err "Mailbox synthesis failed for ${fail_cnt}/${total} account(s): ${failed_emails}"
        return 1
    fi

    rm -rf -- "$fail_dir"
    return 0
}

# Forever Forward Incremental: merge oldest incremental into base full when restore points exceed KEEP_COUNT
zb_ffi_prune_and_merge() {
    local job_root="$1"
    local keep="$2"
    local phase="$3"   # before | after
    local filter_jid="${4:-}"

    local target_keep="$keep"
    if [[ "$phase" == "before" ]]; then
        if (( keep <= 1 )); then
            zb_log "Retention note: KEEP_COUNT=$keep with PRUNE_TIMING=before -> preserving existing FFI chain until new run completes."
            return 0
        fi
        target_keep=$((keep - 1))
    fi

    local -a chains=()
    local c
    while IFS= read -r c; do
        [[ -n "$c" ]] && chains+=("$c")
    done < <(zb_list_valid_chains "$job_root" "$filter_jid")

    if (( ${#chains[@]} == 0 )); then
        return 0
    fi

    local base_full="${chains[0]}"
    local -a steps=()
    local s
    while IFS= read -r s; do
        [[ -n "$s" ]] && steps+=("$s")
    done < <(zb_list_chain_steps "$base_full")

    local total_points="${#steps[@]}"
    if (( total_points <= target_keep || total_points < 2 )); then
        return 0
    fi

    zb_log "FFI retention: current restore points ($total_points) exceed target ($target_keep). Rolling forward base full..."

    while (( total_points > target_keep && total_points >= 2 )); do
        base_full="${steps[0]}"
        local oldest_incr="${steps[1]}"

        zb_log "FFI merge: merging oldest incremental (${oldest_incr##*/}) into base full (${base_full##*/})..."

        zb_read_manifest_meta "$oldest_incr/manifest" || {
            zb_err "Cannot read manifest of oldest incremental step: $oldest_incr"
            return 1
        }
        local oldest_cp_to="${MF_CHECKPOINT_TO:-0}"
        local oldest_leaf="${oldest_incr##*/}"
        local incr_stamp="${oldest_leaf##*-}"
        [[ -n "$incr_stamp" ]] || incr_stamp="$(date '+%d-%m-%Y')"

        local stage_dir="$job_root/.pending.merge_ffi.$$"
        rm -rf -- "$stage_dir"
        mkdir -p -m 700 -- "$stage_dir" || return 1

        # 1. Copy latest metadata snapshot from oldest_incr (since incremental holds full LDAP state at that checkpoint)
        local meta_sub
        for meta_sub in domains admins dl accounts passwords attributes aliases signatures filters; do
            if [[ -d "$oldest_incr/$meta_sub" ]]; then
                cp -a -- "$oldest_incr/$meta_sub" "$stage_dir/"
            elif [[ -d "$base_full/$meta_sub" ]]; then
                cp -a -- "$base_full/$meta_sub" "$stage_dir/"
            fi
        done

        # 2. Synthesize mailboxes from base_full + oldest_incr into stage_dir
        if ! zb_synthesize_mailboxes_parallel "$stage_dir" "$PARALLEL_JOBS" "$base_full" "$oldest_incr"; then
            zb_err "FFI mailbox merge failed"
            rm -rf -- "$stage_dir"
            return 1
        fi

        # 3. Write new manifest for updated base full
        local new_base_name="full-${incr_stamp}"
        local final_base_dir="$(zb_unique_path "$job_root/${new_base_name}")"
        local final_leaf="${final_base_dir##*/}"
        local ffi_chain_id="ffi-${filter_jid:-${JOB_ID:-default}}"

        zb_write_manifest "$stage_dir" "incremental/${final_leaf}" "${filter_jid:-${JOB_ID:-default}}" \
            "full" "$ffi_chain_id" "0" "none" "0" "$oldest_cp_to"

        # 4. Commit new base full and delete merged steps
        mv -- "$stage_dir" "$final_base_dir"
        rm -rf -- "$base_full" "$oldest_incr"
        zb_log "FFI merge committed: new base full is $final_leaf (checkpoint up to $(date -d "@$oldest_cp_to" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '%s' "$oldest_cp_to"))."

        # 5. Renumber remaining incremental steps (002 -> 001, 003 -> 002, etc.)
        local rem_idx=2
        local new_seq=1
        local prev_parent_id="incremental/${final_leaf}"
        while (( rem_idx < ${#steps[@]} )); do
            local cur_dir="${steps[$rem_idx]}"
            if [[ -d "$cur_dir" && ! -L "$cur_dir" ]]; then
                local cur_leaf="${cur_dir##*/}"
                local cur_stamp="${cur_leaf##*-}"
                local new_seq_pad
                new_seq_pad="$(printf '%03d' "$new_seq")"
                local renamed_dir="${job_root}/${new_seq_pad}-incremental-${cur_stamp}"
                if [[ "$cur_dir" != "$renamed_dir" ]]; then
                    mv -- "$cur_dir" "$renamed_dir"
                    cur_dir="$renamed_dir"
                fi

                # Update manifest metadata in place
                if [[ -f "$cur_dir/manifest" ]]; then
                    local mf_tmp
                    mf_tmp="$(mktemp "$ZB_RUN_DIR/.mf_upd.XXXXXX")" || return 1
                    awk -v new_seq="$new_seq" -v new_parent="$prev_parent_id" -v new_bid="incremental/${cur_dir##*/}" '
                        /^chain_seq=/ { print "chain_seq=" new_seq; next }
                        /^parent_id=/ { print "parent_id=" new_parent; next }
                        /^backup_id=/ { print "backup_id=" new_bid; next }
                        { print }
                    ' "$cur_dir/manifest" > "$mf_tmp" && mv -f -- "$mf_tmp" "$cur_dir/manifest"
                    chmod 600 "$cur_dir/manifest"
                fi
                prev_parent_id="incremental/${cur_dir##*/}"
                new_seq=$((new_seq + 1))
            fi
            rem_idx=$((rem_idx + 1))
        done

        # Re-scan chain steps for next iteration if needed
        steps=()
        while IFS= read -r s; do
            [[ -n "$s" ]] && steps+=("$s")
        done < <(zb_list_chain_steps "$final_base_dir" "$ffi_chain_id")
        total_points="${#steps[@]}"
    done

    zb_log "FFI retention complete. Current restore points in chain: ${total_points}/${keep}."
    return 0
}

# Synthetic Full Backup: synthesize full snapshot locally from previous chain and interim delta
zb_execute_synthetic_full_stage() {
    local job_root="$1"
    local stage_dir="$2"
    local snap_leaf="$3"
    local cp_from="$4"
    local cp_to="$5"
    local parallel_limit="$6"

    zb_log "Starting Synthetic Full Backup: synthesizing full snapshot locally from previous chain..."

    # 1. Export fresh LDAP metadata directly from Zimbra
    if ! zb_export_metadata_stage "$stage_dir" "$SCOPE_MODE" "$SCOPE_VALUES"; then
        zb_err "Failed to export LDAP metadata for Synthetic Full backup"
        return 1
    fi

    # 2. Identify the active chain to synthesize from
    local -a chains=()
    local c
    while IFS= read -r c; do
        [[ -n "$c" ]] && chains+=("$c")
    done < <(zb_list_valid_chains "$job_root" "$JOB_ID")

    if (( ${#chains[@]} == 0 )); then
        zb_err "No previous chain found in $job_root to synthesize from"
        return 1
    fi

    local latest_chain="${chains[$((${#chains[@]} - 1))]}"
    local -a chain_steps=()
    local s
    while IFS= read -r s; do
        [[ -n "$s" ]] && chain_steps+=("$s")
    done < <(zb_list_chain_steps "$latest_chain")

    if (( ${#chain_steps[@]} == 0 )); then
        zb_err "No steps found in chain $latest_chain to synthesize from"
        return 1
    fi

    # 3. Pull interim delta from Zimbra for any mail changes since last step
    local delta_stage="$job_root/.pending.delta.${snap_leaf}.$$"
    rm -rf -- "$delta_stage"
    mkdir -p -m 700 -- "$delta_stage/accounts" "$delta_stage/mailboxes" || return 1
    cp -f -- "$stage_dir/accounts/active_accounts.txt" "$delta_stage/accounts/active_accounts.txt"

    zb_log "Pulling incremental delta from live Zimbra since checkpoint ($cp_from)..."
    if ! zb_export_mailboxes_parallel "$delta_stage" "incr" "$cp_from" "$parallel_limit"; then
        zb_err "Failed to export interim mailbox delta for Synthetic Full backup"
        rm -rf -- "$delta_stage"
        return 1
    fi

    # 4. Synthesize all mailboxes from chain steps + interim delta into stage_dir
    local -a all_sources=("${chain_steps[@]}" "$delta_stage")
    zb_log "Synthesizing mailboxes locally from ${#chain_steps[@]} chain step(s) plus today's delta..."
    if ! zb_synthesize_mailboxes_parallel "$stage_dir" "$parallel_limit" "${all_sources[@]}"; then
        zb_err "Failed to synthesize mailboxes for Synthetic Full backup"
        rm -rf -- "$delta_stage"
        return 1
    fi

    rm -rf -- "$delta_stage"

    # 5. Write manifest for Synthetic Full (standalone full, chain_seq=0, chain_id=$snap_leaf)
    zb_write_manifest "$stage_dir" "incremental/${snap_leaf}" "$JOB_ID" "full" "$snap_leaf" "0" "none" "0" "$cp_to"
    zb_log "Synthetic Full Backup synthesis completed successfully for $snap_leaf."
    return 0
}

# Upload snapshot to remote FTP / SFTP storage (if enabled)
TRANSFER_STATUS=""
TRANSFER_BYTES=0
TRANSFER_DURATION=0
TRANSFER_ERROR=""

zb_upload_snapshot() {
    local snap_dir="$1"
    local job_id="$2"
    local step_type="$3"
    local chain_sub="${4:-}"

    TRANSFER_STATUS="failed"
    TRANSFER_BYTES=0
    TRANSFER_DURATION=0
    TRANSFER_ERROR=""

    local upload_enabled="${FTP_UPLOAD:-${FTP_ENABLED:-no}}"
    if [[ "$upload_enabled" != "yes" ]]; then
        TRANSFER_STATUS="disabled"
        return 0
    fi

    if [[ -z "${FTP_HOST:-}" || -z "${FTP_USER:-}" ]]; then
        TRANSFER_ERROR="FTP_HOST or FTP_USER not configured"
        zb_log "WARNING: Remote storage upload skipped: $TRANSFER_ERROR"
        return 1
    fi

    local snap_leaf="${snap_dir##*/}"
    local proto="${FTP_PROTOCOL:-ftp}"
    local port="${FTP_PORT:-21}"
    if [[ "$proto" == "sftp" && "$port" == "21" ]]; then
        port="22"
    fi

    local cat_sub="full"
    if [[ "$job_id" == "account" ]]; then
        cat_sub="account"
    elif [[ "${BACKUP_TYPE:-full}" == "incremental" || "${BACKUP_TYPE:-full}" == "forever_incremental" || "${BACKUP_TYPE:-full}" == "synthetic_full" || "$step_type" == "incr" || "$step_type" == "incremental" || "$step_type" == "synth_full" ]]; then
        cat_sub="incremental"
    fi

    local remote_base="${FTP_REMOTE_DIR:-/}"
    [[ "$remote_base" == /* ]] || remote_base="/$remote_base"
    remote_base="${remote_base%/}"

    local remote_dir=""
    if [[ "${remote_base##*/}" == "$cat_sub" ]]; then
        remote_dir="${remote_base}/"
    else
        remote_dir="${remote_base}/${cat_sub}/"
    fi
    [[ "$remote_dir" == /* ]] || remote_dir="/$remote_dir"

    local tar_name="${snap_leaf}.tar"
    local manifest_name="${snap_leaf}.manifest"

    local snap_bytes=0
    snap_bytes="$(zb_calc_dir_bytes "$snap_dir")"
    TRANSFER_BYTES="$snap_bytes"

    local cfg
    zb_ensure_state_dirs || return 1
    cfg="$(mktemp "$ZB_RUN_DIR/.ftp_up.XXXXXX")" || return 1
    chmod 600 "$cfg"
    printf 'user = "%s:%s"\n' "$(zb_curl_escape "$FTP_USER")" "$(zb_curl_escape "$FTP_PASSWORD")" > "$cfg"

    local -a curl_args=(
        --fail --silent --show-error
        --connect-timeout 15 --max-time 14400
        --ftp-create-dirs
        -K "$cfg"
    )

    local base_url=""
    if [[ "$proto" == "sftp" ]]; then
        base_url="sftp://${FTP_HOST}:${port}"
        curl_args+=(--insecure)
    else
        base_url="ftp://${FTP_HOST}:${port}"
        if [[ "${FTP_SSL:-no}" == "yes" ]]; then
            curl_args+=(--ssl-reqd --insecure)
        fi
    fi

    local target_tar_url="${base_url}${remote_dir}${tar_name}"
    local target_mf_url="${base_url}${remote_dir}${manifest_name}"

    zb_log "Streaming snapshot archive via $proto ($port) to: $target_tar_url (~$(zb_human_bytes "$snap_bytes"))"
    local up_start up_end up_rc=0 up_err=""
    up_start="$(date +%s)"

    local err_file="$ZB_RUN_DIR/.ftp_err.$$.log"
    set +e
    (
        tar -cf - -C "$snap_dir" . | curl "${curl_args[@]}" -T - "$target_tar_url"
    ) 2>"$err_file"
    up_rc=$?
    if (( up_rc == 0 )) && [[ -f "$snap_dir/manifest" ]]; then
        curl "${curl_args[@]}" -T "$snap_dir/manifest" "$target_mf_url" >/dev/null 2>&1 || true
    fi
    set -e

    up_end="$(date +%s)"
    TRANSFER_DURATION=$((up_end - up_start))

    if [[ -f "$err_file" ]]; then
        up_err="$(head -n 5 "$err_file" | tr '\n' ' ')"
        rm -f -- "$err_file"
    fi
    rm -f -- "$cfg"

    if (( up_rc == 0 )); then
        TRANSFER_STATUS="ok"
        zb_log "Remote upload SUCCESS: $(zb_human_bytes "$snap_bytes") streamed in ${TRANSFER_DURATION}s"
        return 0
    else
        TRANSFER_STATUS="failed"
        TRANSFER_ERROR="Upload failed (exit code=$up_rc): ${up_err:-Transfer interrupted}"
        zb_log "ERROR: Remote upload to $proto://$FTP_HOST:$port failed: $TRANSFER_ERROR"
        return 1
    fi
}

# Sort backup archive / directory names chronologically (handles DD-MM-YYYY, YYYYMMDD, step prefixes, and _N suffixes)
zb_sort_backup_names_chronologically() {
    awk '
        NF {
            name = $0
            stem = name
            sub(/\.(tar|manifest)$/, "", stem)
            step = 0
            if (match(stem, /^[0-9][0-9][0-9][_-]/)) {
                step = substr(stem, 1, 3) + 0
            }
            sfx = 1
            if (match(stem, /_[0-9]{1,5}$/)) {
                sfx = substr(stem, RSTART + 1) + 0
                stem = substr(stem, 1, RSTART - 1)
            }
            hms = "000000"
            if (match(stem, /[_-][0-9]{6}$/)) {
                hms = substr(stem, RSTART + 1, 6)
                stem = substr(stem, 1, RSTART - 1)
            }
            ymd = "00000000"
            if (match(stem, /[0-9]{2}-[0-9]{2}-[0-9]{4}$/)) {
                dd = substr(stem, RSTART, 2)
                mm = substr(stem, RSTART + 3, 2)
                yyyy = substr(stem, RSTART + 6, 4)
                ymd = yyyy mm dd
            } else if (match(stem, /[0-9]{8}$/)) {
                ymd = substr(stem, RSTART, 8)
            }
            printf "%s_%s_%03d_%06d\t%s\n", ymd, hms, step, sfx, name
        }
    ' | LC_ALL=C sort | cut -f2-
}

# Automatically prune old remote .tar and .manifest files on FTP/SFTP server according to FTP_KEEP_COUNT.
# Completely independent of local KEEP_COUNT; preserves all local backups untouched.
zb_prune_remote_storage() {
    local job_id="$1"
    local btype="$2"
    local chain_sub="${3:-}"
    local keep="${4:-7}"

    local upload_enabled="${FTP_UPLOAD:-${FTP_ENABLED:-no}}"
    if [[ "$upload_enabled" != "yes" ]]; then
        return 0
    fi
    if [[ -z "${FTP_HOST:-}" || -z "${FTP_USER:-}" ]]; then
        return 0
    fi
    [[ "$keep" =~ ^[0-9]+$ ]] && (( keep >= 1 )) || keep=7

    local proto="${FTP_PROTOCOL:-ftp}"
    local port="${FTP_PORT:-21}"
    if [[ "$proto" == "sftp" && "$port" == "21" ]]; then
        port="22"
    fi

    local remote_base="${FTP_REMOTE_DIR:-/}"
    [[ "$remote_base" == /* ]] || remote_base="/$remote_base"
    remote_base="${remote_base%/}"

    local cfg
    zb_ensure_state_dirs || return 1
    cfg="$(mktemp "$ZB_RUN_DIR/.ftp_prune.XXXXXX")" || return 1
    chmod 600 "$cfg"
    printf 'user = "%s:%s"\n' "$(zb_curl_escape "$FTP_USER")" "$(zb_curl_escape "$FTP_PASSWORD")" > "$cfg"

    local -a curl_base=(
        --fail --silent --show-error
        --connect-timeout 15 --max-time 120
        -K "$cfg"
    )

    local base_url=""
    if [[ "$proto" == "sftp" ]]; then
        base_url="sftp://${FTP_HOST}:${port}"
        curl_base+=(--insecure)
    else
        base_url="ftp://${FTP_HOST}:${port}"
        if [[ "${FTP_SSL:-no}" == "yes" ]]; then
            curl_base+=(--ssl-reqd --insecure)
        fi
    fi

    local cat_sub="full"
    if [[ "$job_id" == "account" ]]; then
        cat_sub="account"
    elif [[ "$btype" == "incremental" || "$btype" == "forever_incremental" || "$btype" == "synthetic_full" ]]; then
        cat_sub="incremental"
    fi

    local target_dir=""
    if [[ "${remote_base##*/}" == "$cat_sub" ]]; then
        target_dir="${remote_base}/"
    else
        target_dir="${remote_base}/${cat_sub}/"
    fi
    [[ "$target_dir" == /* ]] || target_dir="/$target_dir"

    # Query existing entries on remote server
    local list_raw
    list_raw="$(curl "${curl_base[@]}" --list-only "${base_url}${target_dir}" 2>/dev/null || true)"
    if [[ -z "$list_raw" ]]; then
        rm -f -- "$cfg"
        return 0
    fi

    local -a chain_items=() tar_items=()
    local line
    while IFS= read -r line; do
        line="$(zb_trim "$line")"
        line="${line##* }"
        line="${line##*/}"
        [[ -n "$line" ]] || continue
        if [[ "$line" == chain-* ]]; then
            chain_items+=("$line")
        elif [[ "$line" == *.tar ]]; then
            tar_items+=("$line")
        fi
    done <<< "$list_raw"

    if (( ${#chain_items[@]} > 0 )); then
        local -a sorted_chains=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && sorted_chains+=("$line")
        done < <(printf '%s\n' "${chain_items[@]}" | zb_sort_backup_names_chronologically)

        local total_chains="${#sorted_chains[@]}"
        if (( total_chains > keep )); then
            local remove_cnt=$((total_chains - keep))
            local i=0
            while (( i < remove_cnt )); do
                local victim_chain="${sorted_chains[$i]}"
                local chain_dir="${target_dir}${victim_chain}/"
                local cfiles_raw
                cfiles_raw="$(curl "${curl_base[@]}" --list-only "${base_url}${chain_dir}" 2>/dev/null || true)"
                if [[ -n "$cfiles_raw" ]]; then
                    local f
                    while IFS= read -r f; do
                        f="$(zb_trim "$f")"
                        f="${f##* }"
                        f="${f##*/}"
                        [[ -n "$f" ]] || continue
                        if [[ "$proto" == "sftp" ]]; then
                            curl "${curl_base[@]}" -Q "rm ${chain_dir}${f}" "${base_url}/" >/dev/null 2>&1 || true
                        else
                            curl "${curl_base[@]}" -Q "DELE ${chain_dir}${f}" "${base_url}/" >/dev/null 2>&1 || true
                        fi
                    done <<< "$cfiles_raw"
                fi
                if [[ "$proto" == "sftp" ]]; then
                    curl "${curl_base[@]}" -Q "rmdir ${target_dir}${victim_chain}" "${base_url}/" >/dev/null 2>&1 || true
                else
                    curl "${curl_base[@]}" -Q "RMD ${target_dir}${victim_chain}" "${base_url}/" >/dev/null 2>&1 || true
                fi
                zb_log "[FTP] Pruned expired remote chain: ${victim_chain} (retained ${keep} remote chains)"
                i=$((i + 1))
            done
        fi
    fi

    if (( ${#tar_items[@]} > 0 )); then
        local -a sorted_tars=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && sorted_tars+=("$line")
        done < <(printf '%s\n' "${tar_items[@]}" | zb_sort_backup_names_chronologically)

        local total_tars="${#sorted_tars[@]}"
        if (( total_tars > keep )); then
            local remove_cnt=$((total_tars - keep))
            local i=0
            while (( i < remove_cnt )); do
                local victim_tar="${sorted_tars[$i]}"
                local victim_stem="${victim_tar%.tar}"
                if [[ "$proto" == "sftp" ]]; then
                    curl "${curl_base[@]}" -Q "rm ${target_dir}${victim_tar}" "${base_url}/" >/dev/null 2>&1 || true
                    curl "${curl_base[@]}" -Q "rm ${target_dir}${victim_stem}.manifest" "${base_url}/" >/dev/null 2>&1 || true
                else
                    curl "${curl_base[@]}" -Q "DELE ${target_dir}${victim_tar}" "${base_url}/" >/dev/null 2>&1 || true
                    curl "${curl_base[@]}" -Q "DELE ${target_dir}${victim_stem}.manifest" "${base_url}/" >/dev/null 2>&1 || true
                fi
                zb_log "[FTP] Pruned expired remote archive: ${victim_tar} (retained ${keep} remote archives)"
                i=$((i + 1))
            done
        fi
    fi

    rm -f -- "$cfg"
    return 0
}

# Run a configured job in an isolated subshell so lock FD & tee stdout close cleanly when returning to TUI.
zb_run_job() (
    local job_id="$1"
    shift || true
    local from_cron=0
    local force_full=0
    local force_synth_full=0

    while (( $# > 0 )); do
        case "$1" in
            --cron) from_cron=1; shift ;;
            --force-full) force_full=1; shift ;;
            --synthetic-full|--force-synthetic-full) force_synth_full=1; shift ;;
            *) zb_err "Unknown 'job run' option: $1"; return 1 ;;
        esac
    done

    zb_load_settings || return 1
    zb_job_load "$job_id" || return 1
    zb_require_zimbra_cli || return 1

    zb_acquire_lock || {
        (( from_cron == 1 )) && zb_notify "warn" "Job '$JOB_ID' skipped" "Job Name   : ${JOB_NAME:-$JOB_ID}
Status     : SKIPPED
Reason     : Another backup or restore process is holding operation.lock"
        return 1
    }
    zb_start_run_log "job_${JOB_ID}"
    zb_lower_process_priority

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
        zb_notify "error" "Backup Job '$JOB_ID' failed" "Job Name   : ${JOB_NAME:-$JOB_ID}
Status     : FAILED
Reason     : Target storage check failed: $target_base
Log File   : ${ZB_CURRENT_LOG}"
        return 1
    fi
    if ! zb_check_disk_space "$target_base" "$DISK_WARN_PERCENT" "$DISK_MIN_FREE_MB"; then
        zb_notify "error" "Backup Job '$JOB_ID' aborted (low disk space)" "Job Name   : ${JOB_NAME:-$JOB_ID}
Status     : ABORTED (Low disk space)
Path       : ${target_base}
Log File   : ${ZB_CURRENT_LOG}"
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
    stamp="$(date '+%d-%m-%Y')"
    cp_to="$(date +%s)"

    if [[ "$BACKUP_TYPE" == "full" ]]; then
        if [[ "$PRUNE_TIMING" == "before" ]]; then
            zb_prune_job_storage "$job_root" "$BACKUP_TYPE" "$KEEP_COUNT" "before" "$JOB_ID"
        fi
        step_type="full"
        chain_id="standalone"
        chain_seq="0"
        parent_id="none"
        cp_from="0"
        final_dir="$(zb_unique_path "$job_root/full-${stamp}")"
        snap_leaf="${final_dir##*/}"
        backup_id="full/${snap_leaf}"
        stage_dir="$job_root/.pending.${snap_leaf}.$$"
    else
        zb_plan_incremental_step "$job_root" "$force_full" "$stamp" "$JOB_ID" "$force_synth_full"
        step_type="$ZB_PLAN_STEP_TYPE"
        if [[ "$PRUNE_TIMING" == "before" ]]; then
            if [[ "$BACKUP_TYPE" == "forever_incremental" || "$step_type" == "full" || "$step_type" == "synth_full" ]]; then
                zb_prune_job_storage "$job_root" "$BACKUP_TYPE" "$KEEP_COUNT" "before" "$JOB_ID"
            fi
        fi
        zb_check_no_symlinks "$ZB_PLAN_CHAIN_DIR" || return 1
        mkdir -p -m 700 -- "$ZB_PLAN_CHAIN_DIR" || return 1
        [[ ! -L "$ZB_PLAN_CHAIN_DIR" ]] || { zb_err "Chain directory must not be a symlink: $ZB_PLAN_CHAIN_DIR"; return 1; }
        chain_seq="$ZB_PLAN_SEQ"
        parent_id="$ZB_PLAN_PARENT_ID"
        cp_from="$ZB_PLAN_CP_FROM"
        local seq_pad
        seq_pad="$(printf '%03d' "$chain_seq")"
        if [[ "$step_type" == "full" || "$step_type" == "synth_full" ]]; then
            final_dir="$(zb_unique_path "$job_root/full-${stamp}")"
            snap_leaf="${final_dir##*/}"
            if [[ "$BACKUP_TYPE" == "forever_incremental" ]]; then
                chain_id="${ZB_PLAN_CHAIN_ID:-ffi-${JOB_ID}}"
            else
                chain_id="$snap_leaf"
            fi
            backup_id="incremental/${snap_leaf}"
            stage_dir="$job_root/.pending.${snap_leaf}.$$"
        else
            final_dir="$(zb_unique_path "${ZB_PLAN_CHAIN_DIR}/${seq_pad}-incremental-${stamp}")"
            snap_leaf="${final_dir##*/}"
            chain_id="${ZB_PLAN_CHAIN_ID:-${ZB_PLAN_CHAIN_DIR##*/}}"
            backup_id="incremental/${snap_leaf}"
            stage_dir="${ZB_PLAN_CHAIN_DIR}/.pending.${snap_leaf}.$$"
        fi
    fi

    mkdir -p -m 700 -- "$stage_dir" || return 1

    local fail_reason=""
    if [[ "$step_type" == "synth_full" ]]; then
        if ! zb_execute_synthetic_full_stage "$job_root" "$stage_dir" "$snap_leaf" "$cp_from" "$cp_to" "$PARALLEL_JOBS"; then
            fail_reason="Synthetic Full Backup synthesis failed"
        fi
    else
        if ! zb_export_metadata_stage "$stage_dir" "$SCOPE_MODE" "$SCOPE_VALUES"; then
            fail_reason="LDAP metadata / account export failed"
        elif ! zb_export_mailboxes_parallel "$stage_dir" "$step_type" "$cp_from" "$PARALLEL_JOBS"; then
            fail_reason="One or more mailbox exports failed"
        else
            zb_write_manifest "$stage_dir" "$backup_id" "$JOB_ID" "$step_type" "$chain_id" "$chain_seq" "$parent_id" "$cp_from" "$cp_to"
        fi
    fi

    if [[ -n "$fail_reason" ]]; then
        zb_log "ERROR: Backup Job '$JOB_ID' (${step_type^^}) failed: $fail_reason"
        zb_notify "error" "Job '${JOB_NAME:-$JOB_ID}' (${step_type^^}) FAILED" \
"Job Name   : ${JOB_NAME:-$JOB_ID}
Backup Mode: ${step_type^^}
Status     : FAILED
Reason     : ${fail_reason}
Log File   : ${ZB_CURRENT_LOG}"
        return 1
    fi

    mv -- "$stage_dir" "$final_dir"
    stage_dir="" # committed; prevent cleanup_job_run from deleting

    zb_prune_job_storage "$job_root" "$BACKUP_TYPE" "$KEEP_COUNT" "after" "$JOB_ID"

    end_epoch="$(date +%s)"
    duration_sec=$((end_epoch - start_epoch))
    zb_read_manifest_meta "$final_dir/manifest" || true

    local human_sz
    human_sz="$(zb_human_bytes "${MF_TOTAL_BYTES:-0}")"

    # Remote FTP / SFTP upload hook (if enabled for this job)
    local ftp_line=""
    local notify_tag="ok"
    local job_ftp_enabled="${FTP_UPLOAD:-${FTP_ENABLED:-no}}"
    if [[ "$job_ftp_enabled" == "yes" ]]; then
        local chain_sub=""
        if [[ "$BACKUP_TYPE" == "incremental" || "$BACKUP_TYPE" == "forever_incremental" || "$BACKUP_TYPE" == "synthetic_full" ]]; then
            chain_sub="${chain_id}"
        fi
        if zb_upload_snapshot "$final_dir" "$JOB_ID" "$step_type" "$chain_sub"; then
            local ftp_keep="${FTP_KEEP_COUNT:-7}"
            zb_prune_remote_storage "$JOB_ID" "$BACKUP_TYPE" "$chain_sub" "$ftp_keep" || true
            ftp_line="Remote Storage : OK [${FTP_PROTOCOL^^} ${FTP_HOST}:${FTP_PORT} | in ${TRANSFER_DURATION}s | Retained: ${ftp_keep} remote]"
        else
            local safe_err="${TRANSFER_ERROR//:\/\//: }"
            ftp_line="Remote Storage : FAILED [${FTP_PROTOCOL^^} ${FTP_HOST}:${FTP_PORT} | Error: ${safe_err}]"
            notify_tag="warn"
        fi
    fi

    local display_mode="${step_type^^}"
    if [[ "$step_type" == "synth_full" ]]; then
        display_mode="SYNTHETIC FULL"
    elif [[ "$BACKUP_TYPE" == "forever_incremental" ]]; then
        display_mode="FFI (${step_type^^})"
    fi

    zb_log "============================================================"
    zb_log "COMPLETED JOB '$JOB_ID' (${display_mode}) | Accounts: ${MF_ACCOUNTS_COUNT} | Size: ${human_sz} | Duration: ${duration_sec}s"
    zb_log "Location: $final_dir"
    [[ -n "$ftp_line" ]] && zb_log "$ftp_line"
    zb_log "============================================================"

    local notify_title="Job '${JOB_NAME:-$JOB_ID}' (${display_mode}) completed - ${MF_ACCOUNTS_COUNT} accounts, ${human_sz}"
    if [[ "$notify_tag" == "warn" ]]; then
        notify_title="Job '${JOB_NAME:-$JOB_ID}' (${display_mode}) completed (remote upload failed)"
    fi

    local dur_desc="${duration_sec}s"
    if (( duration_sec >= 60 )); then
        dur_desc="${duration_sec}s ($((duration_sec / 60))m $((duration_sec % 60))s)"
    fi

    local notify_body="Job Name       : ${JOB_NAME:-$JOB_ID}
Backup Mode    : ${display_mode}
Accounts       : ${MF_ACCOUNTS_COUNT} (new/changed: ${MF_ARCHIVES_COUNT}, unchanged: ${MF_EMPTY_DELTA_COUNT})
Total Size     : ${human_sz}
Duration       : ${dur_desc}
Local Path     : ${final_dir}"

    if [[ -n "$ftp_line" ]]; then
        notify_body="${notify_body}
${ftp_line}"
    fi

    zb_notify "$notify_tag" "$notify_title" "$notify_body"
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
    zb_lower_process_priority

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
    stamp="$(date '+%d-%m-%Y')"
    cp_to="$(date +%s)"
    final_dir="$(zb_unique_path "$adhoc_root/backup-${acct_tag}-${stamp}")"
    snap_leaf="${final_dir##*/}"
    backup_id="account/${snap_leaf}"
    stage_dir="$adhoc_root/.pending.${snap_leaf}.$$"

    mkdir -p -m 700 -- "$stage_dir"
    zb_log "Starting ad-hoc Full backup for account(s): $emails_csv"
    if ! zb_export_metadata_stage "$stage_dir" "accounts" "$emails_csv"; then
        zb_notify "error" "Ad-hoc account backup FAILED for: $emails_csv" \
"Job Name   : adhoc-account
Backup Mode: FULL
Status     : FAILED
Reason     : Metadata export failed
Log File   : ${ZB_CURRENT_LOG}"
        return 1
    fi
    if ! zb_export_mailboxes_parallel "$stage_dir" "full" "0" "2"; then
        zb_notify "error" "Ad-hoc account backup FAILED for: $emails_csv" \
"Job Name   : adhoc-account
Backup Mode: FULL
Status     : FAILED
Reason     : Mailbox export failed
Log File   : ${ZB_CURRENT_LOG}"
        return 1
    fi
    zb_write_manifest "$stage_dir" "$backup_id" "account" "full" "standalone" "0" "none" "0" "$cp_to"

    mv -- "$stage_dir" "$final_dir"
    stage_dir=""
    zb_read_manifest_meta "$final_dir/manifest" || true
    local human_sz
    human_sz="$(zb_human_bytes "${MF_TOTAL_BYTES:-0}")"

    # Remote FTP / SFTP upload hook (if enabled)
    local ftp_line=""
    local notify_tag="ok"
    if [[ "${FTP_ENABLED:-no}" == "yes" ]]; then
        if zb_upload_snapshot "$final_dir" "account" "full"; then
            ftp_line="Remote Storage : OK [${FTP_PROTOCOL^^} ${FTP_HOST}:${FTP_PORT} | in ${TRANSFER_DURATION}s]"
        else
            local safe_err="${TRANSFER_ERROR//:\/\//: }"
            ftp_line="Remote Storage : FAILED [${FTP_PROTOCOL^^} ${FTP_HOST}:${FTP_PORT} | Error: ${safe_err}]"
            notify_tag="warn"
        fi
    fi

    zb_log "Completed ad-hoc account backup at: $final_dir (Size: $human_sz)"
    [[ -n "$ftp_line" ]] && zb_log "$ftp_line"

    local notify_title="Ad-hoc account backup succeeded - ${MF_ACCOUNTS_COUNT} accounts, ${human_sz}"
    if [[ "$notify_tag" == "warn" ]]; then
        notify_title="Ad-hoc account backup succeeded (remote upload failed)"
    fi

    local notify_body="Job Name       : adhoc-account
Backup Mode    : FULL
Accounts       : ${MF_ACCOUNTS_COUNT} (archives: ${MF_ARCHIVES_COUNT})
Total Size     : ${human_sz}
Local Path     : ${final_dir}"

    if [[ -n "$ftp_line" ]]; then
        notify_body="${notify_body}
${ftp_line}"
    fi

    zb_notify "$notify_tag" "$notify_title" "$notify_body"
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
