#!/usr/bin/env bash
# Backup catalog discovery, inspection, chain resolution, and granular restore engine.
# Supports zb-backup-v2 (Full & Incremental chains), zb-full-v1, and legacy auto_full_backup.sh dirs.
# Compatible with Bash 4.2+.

ZB_CAT_PATHS=()
ZB_CAT_IDS=()
ZB_CAT_JOBS=()
ZB_CAT_TYPES=()
ZB_CAT_DATES=()
ZB_CAT_ACCOUNTS=()
ZB_CAT_BYTES=()
ZB_CAT_FORMATS=()
ZB_CAT_CHAINS=()
ZB_CAT_SEQS=()

zb_try_register_catalog_entry() {
    local dir="$1"
    # Avoid duplicate paths
    local existing
    for existing in "${ZB_CAT_PATHS[@]+"${ZB_CAT_PATHS[@]}"}"; do
        [[ "$existing" == "$dir" ]] && return 0
    done

    if [[ -f "$dir/manifest" ]] && zb_read_manifest_meta "$dir/manifest"; then
        ZB_CAT_PATHS+=("$dir")
        ZB_CAT_IDS+=("${MF_BACKUP_ID:-${dir##*/}}")
        ZB_CAT_JOBS+=("${MF_JOB_ID:-external}")
        ZB_CAT_TYPES+=("${MF_BACKUP_TYPE:-full}")
        ZB_CAT_DATES+=("${MF_CREATED_AT:-unknown}")
        ZB_CAT_ACCOUNTS+=("${MF_ACCOUNTS_COUNT:-0}")
        ZB_CAT_BYTES+=("${MF_TOTAL_BYTES:-$(zb_calc_dir_bytes "$dir")}")
        ZB_CAT_FORMATS+=("$MF_FORMAT")
        ZB_CAT_CHAINS+=("${MF_CHAIN_ID:-standalone}")
        ZB_CAT_SEQS+=("${MF_CHAIN_SEQ:-0}")
        return 0
    fi

    # Legacy auto_full_backup.sh format detection
    if [[ -f "$dir/accounts/active_accounts.txt" && -d "$dir/mailboxes" ]]; then
        local acc_cnt sz mtime_iso
        acc_cnt="$(wc -l < "$dir/accounts/active_accounts.txt" | awk '{print $1}')"
        sz="$(zb_calc_dir_bytes "$dir")"
        mtime_iso="$(date -u -r "$dir/accounts/active_accounts.txt" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'legacy')"
        ZB_CAT_PATHS+=("$dir")
        ZB_CAT_IDS+=("legacy/${dir##*/}")
        ZB_CAT_JOBS+=("legacy")
        ZB_CAT_TYPES+=("legacy-full")
        ZB_CAT_DATES+=("$mtime_iso")
        ZB_CAT_ACCOUNTS+=("$acc_cnt")
        ZB_CAT_BYTES+=("$sz")
        ZB_CAT_FORMATS+=("legacy-v0")
        ZB_CAT_CHAINS+=("standalone")
        ZB_CAT_SEQS+=("0")
        return 0
    fi

    return 1
}

zb_register_catalog_entry() {
    zb_try_register_catalog_entry "$1" || true
}

zb_scan_job_storage_root() {
    local job_root="$1"
    [[ -d "$job_root" && ! -L "$job_root" ]] || return 0

    local p
    shopt -s nullglob
    for p in \
        "$job_root"/backup-full-* \
        "$job_root"/snapshots/backup-full-* \
        "$job_root"/snapshots/full_* \
        "$job_root"/chain-*/[0-9][0-9][0-9]_* \
        "$job_root"/chain_*/[0-9][0-9][0-9]_* \
        "$job_root"/chains/chain-*/[0-9][0-9][0-9]_* \
        "$job_root"/chains/chain_*/[0-9][0-9][0-9]_*; do
        [[ -d "$p" && ! -L "$p" && "${p##*/}" != .pending.* ]] || continue
        zb_register_catalog_entry "$p"
    done
    shopt -u nullglob
}

# Recursively discover valid backup snapshots under ANY user-supplied directory path.
# Stops descending as soon as a snapshot root is matched so mailboxes/accounts are never walked.
_zb_walk_custom_dir() {
    local cur="$1"
    local depth="$2"
    local max_depth="$3"

    [[ -d "$cur" ]] || return 0
    if (( depth > 0 )); then
        [[ ! -L "$cur" ]] || return 0
        local base="${cur##*/}"
        if [[ "$base" == .* || "$base" == "proc" || "$base" == "sys" || "$base" == "dev" || "$base" == "run" ]]; then
            return 0
        fi
    fi

    if zb_try_register_catalog_entry "$cur"; then
        return 0
    fi

    (( depth < max_depth )) || return 0

    local child
    for child in "$cur"/*; do
        [[ -d "$child" && ! -L "$child" ]] || continue
        _zb_walk_custom_dir "$child" "$((depth + 1))" "$max_depth"
    done
}

zb_scan_root_for_backups() {
    local root="${1%/}"
    [[ -n "$root" ]] || root="/"
    [[ -d "$root" && ! -L "$root" ]] || return 0

    local had_nullglob=0
    shopt -q nullglob && had_nullglob=1
    shopt -s nullglob
    _zb_walk_custom_dir "$root" 0 5
    (( had_nullglob == 1 )) || shopt -u nullglob
}

# Populate ZB_CAT_* arrays sorted newest -> oldest.
# When custom_dir is empty, scans ONLY configured backup jobs' storage roots (<target_dir>/<job_id>).
zb_discover_backups() {
    local custom_dir="${1:-}"
    local filter_job="${2:-}"
    ZB_CAT_PATHS=()
    ZB_CAT_IDS=()
    ZB_CAT_JOBS=()
    ZB_CAT_TYPES=()
    ZB_CAT_DATES=()
    ZB_CAT_ACCOUNTS=()
    ZB_CAT_BYTES=()
    ZB_CAT_FORMATS=()
    ZB_CAT_CHAINS=()
    ZB_CAT_SEQS=()

    zb_load_settings || true

    if [[ -n "$custom_dir" && -n "$filter_job" ]]; then
        zb_err "Cannot combine --dir and --job; choose either a backup job or a custom directory."
        return 1
    fi

    if [[ -n "$custom_dir" ]]; then
        zb_scan_root_for_backups "$custom_dir"
    else
        if [[ -n "$filter_job" ]]; then
            zb_job_load "$filter_job" >/dev/null || return 1
        fi
        local jroot
        while IFS= read -r jroot; do
            [[ -n "$jroot" ]] || continue
            zb_scan_job_storage_root "$jroot"
        done < <(zb_list_job_storage_roots "$filter_job" 1)
    fi

    local count="${#ZB_CAT_PATHS[@]}"
    (( count > 1 )) || return 0

    # Sort indices by CREATED_AT descending, then path descending
    local sort_tmp
    sort_tmp="$(mktemp "$ZB_RUN_DIR/.cat_sort.XXXXXX")" || return 0
    local i=0
    while (( i < count )); do
        printf '%s\t%s\t%d\n' "${ZB_CAT_DATES[$i]}" "${ZB_CAT_PATHS[$i]}" "$i" >> "$sort_tmp"
        i=$((i + 1))
    done

    local -a new_paths=() new_ids=() new_jobs=() new_types=() new_dates=() new_accs=() new_bytes=() new_fmts=() new_chains=() new_seqs=()
    local _d _p orig_idx
    while IFS=$'\t' read -r _d _p orig_idx; do
        new_paths+=("${ZB_CAT_PATHS[$orig_idx]}")
        new_ids+=("${ZB_CAT_IDS[$orig_idx]}")
        new_jobs+=("${ZB_CAT_JOBS[$orig_idx]}")
        new_types+=("${ZB_CAT_TYPES[$orig_idx]}")
        new_dates+=("${ZB_CAT_DATES[$orig_idx]}")
        new_accs+=("${ZB_CAT_ACCOUNTS[$orig_idx]}")
        new_bytes+=("${ZB_CAT_BYTES[$orig_idx]}")
        new_fmts+=("${ZB_CAT_FORMATS[$orig_idx]}")
        new_chains+=("${ZB_CAT_CHAINS[$orig_idx]}")
        new_seqs+=("${ZB_CAT_SEQS[$orig_idx]}")
    done < <(LC_ALL=C sort -r "$sort_tmp")
    rm -f -- "$sort_tmp"

    ZB_CAT_PATHS=("${new_paths[@]}")
    ZB_CAT_IDS=("${new_ids[@]}")
    ZB_CAT_JOBS=("${new_jobs[@]}")
    ZB_CAT_TYPES=("${new_types[@]}")
    ZB_CAT_DATES=("${new_dates[@]}")
    ZB_CAT_ACCOUNTS=("${new_accs[@]}")
    ZB_CAT_BYTES=("${new_bytes[@]}")
    ZB_CAT_FORMATS=("${new_fmts[@]}")
    ZB_CAT_CHAINS=("${new_chains[@]}")
    ZB_CAT_SEQS=("${new_seqs[@]}")
}

zb_print_backup_catalog() {
    local custom_dir="${1:-}"
    local filter_job="${2:-}"
    zb_discover_backups "$custom_dir" "$filter_job" || return 1
    local total="${#ZB_CAT_PATHS[@]}"
    if (( total == 0 )); then
        if [[ -n "$custom_dir" ]]; then
            zb_msg "No backups found in custom directory: $custom_dir"
        elif [[ -n "$filter_job" ]]; then
            local jroot
            jroot="$(zb_list_job_storage_roots "$filter_job" 2>/dev/null || printf '')"
            zb_msg "No backups found for job '$filter_job' (${jroot:-unknown path})."
        elif [[ -z "$(zb_job_list_ids)" ]]; then
            zb_msg "No backup jobs configured yet (create a job first, or use --dir <path> / Menu 4 for custom directories)."
        else
            zb_msg "No backups found in configured backup job directories."
        fi
        return 0
    fi

    printf '%-4s %-15s %-12s %-21s %-7s %-11s %s\n' "NO." "JOB" "TYPE" "CREATED (UTC)" "USERS" "SIZE" "BACKUP ID / PATH"
    printf '%s\n' "--------------------------------------------------------------------------------------------------------------------"
    local i=0
    while (( i < total )); do
        local num=$((i + 1))
        local type_lbl="${ZB_CAT_TYPES[$i]}"
        if [[ "$type_lbl" == "incr" ]]; then
            type_lbl="incr(#${ZB_CAT_SEQS[$i]})"
        fi
        printf '%-4s %-15s %-12s %-21s %-7s %-11s %s\n' \
            "[$num]" \
            "${ZB_CAT_JOBS[$i]}" \
            "$type_lbl" \
            "${ZB_CAT_DATES[$i]}" \
            "${ZB_CAT_ACCOUNTS[$i]}" \
            "$(zb_human_bytes "${ZB_CAT_BYTES[$i]}")" \
            "${ZB_CAT_IDS[$i]}"
        i=$((i + 1))
    done
}

# Resolve user selector (1-based catalog index, backup_id, or direct directory path) -> sets ZB_SELECTED_IDX & ZB_SELECTED_DIR
zb_resolve_backup_selector() {
    local selector="$1"
    local custom_dir="${2:-}"
    local filter_job="${3:-}"
    ZB_SELECTED_IDX=-1
    ZB_SELECTED_DIR=""

    if [[ -z "$custom_dir" && -z "$filter_job" && -d "$selector" ]]; then
        zb_discover_backups "$selector"
        if (( ${#ZB_CAT_PATHS[@]} == 1 )); then
            ZB_SELECTED_IDX=0
            ZB_SELECTED_DIR="${ZB_CAT_PATHS[0]}"
            return 0
        fi
    fi

    zb_discover_backups "$custom_dir" "$filter_job" || return 1
    local total="${#ZB_CAT_PATHS[@]}"
    (( total > 0 )) || { zb_err "No backups available to select."; return 1; }

    if [[ "$selector" =~ ^[0-9]+$ ]]; then
        local idx=$((selector - 1))
        if (( idx >= 0 && idx < total )); then
            ZB_SELECTED_IDX="$idx"
            ZB_SELECTED_DIR="${ZB_CAT_PATHS[$idx]}"
            return 0
        fi
    fi

    local i=0
    while (( i < total )); do
        if [[ "${ZB_CAT_IDS[$i]}" == "$selector" || "${ZB_CAT_PATHS[$i]}" == "$selector" || "${ZB_CAT_PATHS[$i]##*/}" == "$selector" ]]; then
            ZB_SELECTED_IDX="$i"
            ZB_SELECTED_DIR="${ZB_CAT_PATHS[$i]}"
            return 0
        fi
        i=$((i + 1))
    done

    zb_err "Backup not found for selector: '$selector'"
    return 1
}

# Given a selected snapshot directory, build ordered array ZB_RESTORE_CHAIN_DIRS=(base_full ... target_incr)
zb_resolve_restore_chain() {
    local target_dir="$1"
    ZB_RESTORE_CHAIN_DIRS=()

    if [[ -f "$target_dir/manifest" ]] && zb_read_manifest_meta "$target_dir/manifest"; then
        if [[ "$MF_BACKUP_TYPE" == "incr" ]]; then
            local chain_parent="${target_dir%/*}"
            local target_seq="$MF_CHAIN_SEQ"
            local -a all_steps=()
            local s
            while IFS= read -r s; do
                [[ -n "$s" ]] && all_steps+=("$s")
            done < <(zb_list_chain_steps "$chain_parent")

            (( ${#all_steps[@]} > 0 )) || { zb_err "Chain directory is empty or missing 000_full base: $chain_parent"; return 1; }
            zb_read_manifest_meta "${all_steps[0]}/manifest" || return 1
            [[ "$MF_BACKUP_TYPE" == "full" && "$MF_CHAIN_SEQ" == "0" ]] || {
                zb_err "Chain '$chain_parent' is missing its 000_full base snapshot; cannot safely restore incremental step."
                return 1
            }

            local step
            for step in "${all_steps[@]}"; do
                zb_read_manifest_meta "$step/manifest" || return 1
                if (( 10#$MF_CHAIN_SEQ <= 10#$target_seq )); then
                    ZB_RESTORE_CHAIN_DIRS+=("$step")
                fi
            done
            return 0
        fi
    fi

    ZB_RESTORE_CHAIN_DIRS=("$target_dir")
    return 0
}

zb_inspect_snapshot() {
    local selector="$1"
    local custom_dir="${2:-}"
    local search_kw="${3:-}"
    local filter_job="${4:-}"

    zb_resolve_backup_selector "$selector" "$custom_dir" "$filter_job" || return 1
    local i="$ZB_SELECTED_IDX"
    local dir="$ZB_SELECTED_DIR"

    zb_resolve_restore_chain "$dir" || true

    zb_msg "============================================================"
    zb_msg "BACKUP SNAPSHOT DETAILS"
    zb_msg "============================================================"
    zb_msg "  Backup ID          : ${ZB_CAT_IDS[$i]}"
    zb_msg "  Job                : ${ZB_CAT_JOBS[$i]}"
    zb_msg "  Format / Type      : ${ZB_CAT_FORMATS[$i]} / ${ZB_CAT_TYPES[$i]}"
    zb_msg "  Created At (UTC)   : ${ZB_CAT_DATES[$i]}"
    zb_msg "  Snapshot Size      : $(zb_human_bytes "${ZB_CAT_BYTES[$i]}")"
    zb_msg "  Directory Path     : $dir"
    if (( ${#ZB_RESTORE_CHAIN_DIRS[@]} > 1 )); then
        zb_msg "  Restore Chain      : ${#ZB_RESTORE_CHAIN_DIRS[@]} sequential steps (000_full -> ... -> ${dir##*/})"
    fi

    if [[ -f "$dir/domains/domains.txt" ]]; then
        local dom_inline
        dom_inline="$(tr '\n' ' ' < "$dir/domains/domains.txt")"
        zb_msg "  Domains            : $dom_inline"
    fi

    zb_msg "------------------------------------------------------------"
    zb_msg "ACCOUNTS IN SNAPSHOT (${ZB_CAT_ACCOUNTS[$i]}):"
    if [[ -f "$dir/accounts/active_accounts.txt" ]]; then
        local u idx=0 shown=0
        while IFS= read -r u; do
            [[ -n "$u" ]] || continue
            idx=$((idx + 1))
            if [[ -n "$search_kw" && "${u,,}" != *"${search_kw,,}"* ]]; then
                continue
            fi
            local mbox_note="(no .tgz)"
            if [[ -f "$dir/mailboxes/${u}.tgz" ]]; then
                local bsz
                bsz="$(wc -c < "$dir/mailboxes/${u}.tgz" | awk '{print $1}')"
                mbox_note="$(zb_human_bytes "$bsz")"
            elif [[ -f "$dir/mailboxes/${u}.empty" ]]; then
                mbox_note="(unchanged delta)"
            fi
            printf '  %4d) %-42s %s\n' "$idx" "$u" "$mbox_note"
            shown=$((shown + 1))
        done < "$dir/accounts/active_accounts.txt"
        if [[ -n "$search_kw" ]]; then
            zb_msg "  -> Matched $shown account(s) for keyword '$search_kw'."
        fi
    fi
    zb_msg "============================================================"
}

# Build filtered list of accounts from snapshot according to restore scope (`all` | `domain` | `users`)
zb_select_restore_accounts() {
    local snap_dir="$1"
    local scope_kind="$2"
    local scope_arg="$3"
    local out_file="$4"

    local src_acc="$snap_dir/accounts/active_accounts.txt"
    [[ -f "$src_acc" ]] || { zb_err "Snapshot is missing accounts/active_accounts.txt: $snap_dir"; return 1; }
    : > "$out_file"

    case "$scope_kind" in
        all)
            cp -f -- "$src_acc" "$out_file"
            ;;
        domain)
            local -a doms=()
            local d
            IFS=',' read -r -a doms <<< "$scope_arg"
            for d in "${doms[@]}"; do
                d="$(zb_trim "$d")"
                [[ -n "$d" ]] || continue
                awk -v sfx="@${d}" '
                    length($0) > length(sfx) && substr($0, length($0) - length(sfx) + 1) == sfx { print }
                ' "$src_acc" >> "$out_file"
            done
            LC_ALL=C sort -u -o "$out_file" "$out_file"
            ;;
        users)
            local -a usrs=()
            local u
            IFS=',' read -r -a usrs <<< "$scope_arg"
            for u in "${usrs[@]}"; do
                u="$(zb_trim "$u")"
                [[ -n "$u" ]] || continue
                if grep -Fxq -- "$u" "$src_acc" || [[ -f "$snap_dir/mailboxes/${u}.tgz" || -f "$snap_dir/accounts/${u}.ldif" ]]; then
                    printf '%s\n' "$u" >> "$out_file"
                else
                    zb_warn "Account '$u' not found in backup snapshot ($snap_dir)."
                fi
            done
            LC_ALL=C sort -u -o "$out_file" "$out_file"
            ;;
        *)
            zb_err "Invalid restore scope: $scope_kind"
            return 1
            ;;
    esac

    [[ -s "$out_file" ]] || { zb_err "No matching accounts found in backup for restore."; return 1; }
    return 0
}

zb_domain_exists() {
    local dom="$1"
    zmprov -l gd "$dom" zimbraId </dev/null >/dev/null 2>&1
}

zb_account_exists() {
    local email="$1"
    zmprov -l ga "$email" zimbraId </dev/null >/dev/null 2>&1
}

zb_dl_exists() {
    local dl="$1"
    zmprov -l gdl "$dl" zimbraId </dev/null >/dev/null 2>&1
}

zb_find_password_file() {
    local snap_dir="$1" email="$2"
    if [[ -s "$snap_dir/passwords/${email}.shadow" ]]; then
        printf '%s' "$snap_dir/passwords/${email}.shadow"
    elif [[ -s "$snap_dir/userpass/${email}.shadow" ]]; then
        printf '%s' "$snap_dir/userpass/${email}.shadow"
    fi
}

zb_find_alias_file() {
    local snap_dir="$1" email="$2"
    if [[ -s "$snap_dir/aliases/${email}.txt" ]]; then
        printf '%s' "$snap_dir/aliases/${email}.txt"
    elif [[ -s "$snap_dir/alias/${email}.txt" ]]; then
        printf '%s' "$snap_dir/alias/${email}.txt"
    fi
}

zb_find_sieve_in_file() {
    local snap_dir="$1" email="$2"
    if [[ -s "$snap_dir/filters/${email}.sieve" ]]; then
        printf '%s' "$snap_dir/filters/${email}.sieve"
    elif [[ -s "$snap_dir/filter/${email}.sieve" ]]; then
        printf '%s' "$snap_dir/filter/${email}.sieve"
    fi
}

# Restore LDAP metadata (domains, accounts, attrs, hashes, aliases, DLs, signatures, Sieve, admins)
zb_restore_ldap_metadata() {
    local snap_dir="$1"
    local scope_kind="$2"
    local acc_list_file="$3"
    local target_user_override="${4:-}"

    # Collect required domains
    local req_doms
    req_doms="$(mktemp "$ZB_RUN_DIR/.rest_doms.XXXXXX")" || return 1
    if [[ -n "$target_user_override" ]]; then
        printf '%s\n' "${target_user_override#*@}" > "$req_doms"
    elif [[ "$scope_kind" == "all" && -f "$snap_dir/domains/domains.txt" ]]; then
        cp -f -- "$snap_dir/domains/domains.txt" "$req_doms"
    else
        awk -F'@' 'NF == 2 { print $2 }' "$acc_list_file" | LC_ALL=C sort -u > "$req_doms"
    fi

    zb_log "[LDAP 1/7] Checking / creating domains..."
    local dom
    while IFS= read -r dom <&3; do
        [[ -n "$dom" ]] || continue
        if ! zb_domain_exists "$dom"; then
            zb_log "  + Creating domain: $dom"
            zmprov cd "$dom" </dev/null >/dev/null 2>&1 || zb_warn "Could not create domain: $dom"
        fi
    done 3< "$req_doms"

    zb_log "[LDAP 2/7] Restoring accounts, UTF-8 attributes, quotas, and password hashes..."
    local src_email dest_email
    while IFS= read -r src_email <&3; do
        [[ -n "$src_email" ]] || continue
        dest_email="${target_user_override:-$src_email}"

        if ! zb_account_exists "$dest_email"; then
            local tmp_pass
            tmp_pass="Tmp$(date +%s)$$Aa1!"
            zb_log "  + Creating account: $dest_email"
            zmprov ca "$dest_email" "$tmp_pass" </dev/null >/dev/null 2>&1 || {
                zb_warn "Failed to create account: $dest_email"
                continue
            }
        fi

        # When redirecting restore to a different existing target user, do not overwrite their password/aliases!
        if [[ -n "$target_user_override" && "$target_user_override" != "$src_email" ]]; then
            continue
        fi

        # Restore attributes fromzb-backup-v2 `.attrs` (or unfold legacy `.ldif` on the fly)
        local attrs_file="$snap_dir/attributes/${src_email}.attrs"
        local temp_attrs=""
        if [[ ! -f "$attrs_file" && -f "$snap_dir/accounts/${src_email}.ldif" ]]; then
            temp_attrs="$(mktemp "$ZB_RUN_DIR/.legacy_attrs.XXXXXX")"
            zb_extract_account_artifacts "$snap_dir/accounts/${src_email}.ldif" "$snap_dir" "$src_email" 2>/dev/null || true
            attrs_file="$snap_dir/attributes/${src_email}.attrs"
        fi

        if [[ -s "$attrs_file" ]]; then
            local -a ma_args=()
            local attr val_b64 val_decoded
            while IFS=$'\t' read -r attr val_b64 <&4; do
                [[ -n "$attr" && -n "$val_b64" ]] || continue
                val_decoded="$(printf '%s' "$val_b64" | base64 -d 2>/dev/null || printf '%s' "$val_b64" | base64 --decode 2>/dev/null || true)"
                ma_args+=("$attr" "$val_decoded")
            done 4< "$attrs_file"
            if (( ${#ma_args[@]} > 0 )); then
                zmprov ma "$dest_email" "${ma_args[@]}" </dev/null >/dev/null 2>&1 || zb_warn "Warning applying attributes for $dest_email"
            fi
        fi
        [[ -n "$temp_attrs" ]] && rm -f -- "$temp_attrs"

        local pw_file
        pw_file="$(zb_find_password_file "$snap_dir" "$src_email")"
        if [[ -n "$pw_file" && -s "$pw_file" ]]; then
            local shadow_hash
            shadow_hash="$(head -n 1 "$pw_file" | tr -d '\r\n')"
            shadow_hash="${shadow_hash#userPassword:}"
            shadow_hash="$(zb_trim "$shadow_hash")"
            if [[ -n "$shadow_hash" ]]; then
                zmprov ma "$dest_email" userPassword "$shadow_hash" </dev/null >/dev/null 2>&1 || zb_warn "Failed to restore password hash for $dest_email"
            fi
        fi
    done 3< "$acc_list_file"

    # Skip aliases, DLs, signatures, filters, admin grants when redirecting to a different target account
    if [[ -n "$target_user_override" ]]; then
        rm -f -- "$req_doms"
        return 0
    fi

    zb_log "[LDAP 3/7] Restoring account aliases..."
    while IFS= read -r src_email <&3; do
        [[ -n "$src_email" ]] || continue
        local alias_file alias_addr
        alias_file="$(zb_find_alias_file "$snap_dir" "$src_email")"
        [[ -n "$alias_file" && -s "$alias_file" ]] || continue
        while IFS= read -r alias_addr <&4; do
            alias_addr="$(zb_trim "$alias_addr")"
            [[ -n "$alias_addr" && "$alias_addr" != "$src_email" ]] || continue
            zmprov aaa "$src_email" "$alias_addr" </dev/null >/dev/null 2>&1 || true
        done 4< "$alias_file"
    done 3< "$acc_list_file"

    if [[ "$scope_kind" == "all" || "$scope_kind" == "domain" ]]; then
        zb_log "[LDAP 4/7] Restoring Distribution Lists and members..."
        if [[ -s "$snap_dir/dl/distribution_lists.txt" ]]; then
            local dl dl_dom member
            while IFS= read -r dl <&3; do
                dl="$(zb_trim "$dl")"
                [[ -n "$dl" ]] || continue
                dl_dom="${dl#*@}"
                grep -Fxq -- "$dl_dom" "$req_doms" || continue
                if ! zb_dl_exists "$dl"; then
                    zmprov cdl "$dl" </dev/null >/dev/null 2>&1 || true
                fi
                if [[ -s "$snap_dir/dl/${dl}.members" ]]; then
                    while IFS= read -r member <&4; do
                        member="$(zb_trim "$member")"
                        [[ -n "$member" ]] && zmprov adlm "$dl" "$member" </dev/null >/dev/null 2>&1 || true
                    done 4< "$snap_dir/dl/${dl}.members"
                fi
            done 3< "$snap_dir/dl/distribution_lists.txt"
        fi
    else
        zb_log "[LDAP 4/7] Skipping Distribution Lists (single-account scope)."
    fi

    zb_log "[LDAP 5/7] Restoring email signatures..."
    while IFS= read -r src_email <&3; do
        [[ -n "$src_email" ]] || continue
        local sig_file="$snap_dir/signatures/${src_email}.sigs"
        if [[ -s "$sig_file" ]]; then
            local name_b64 sig_attr content_b64 sig_name sig_body
            while IFS=$'\t' read -r name_b64 sig_attr content_b64 <&4; do
                [[ -n "$name_b64" && -n "$content_b64" ]] || continue
                sig_name="$(printf '%s' "$name_b64" | base64 -d 2>/dev/null || printf 'Default')"
                sig_body="$(printf '%s' "$content_b64" | base64 -d 2>/dev/null || printf '')"
                zmprov csig "$src_email" "$sig_name" "$sig_attr" "$sig_body" </dev/null >/dev/null 2>&1 || \
                    zmprov msig "$src_email" "$sig_name" "$sig_attr" "$sig_body" </dev/null >/dev/null 2>&1 || true
            done 4< "$sig_file"
        elif [[ -s "$snap_dir/signature/${src_email}.sig" ]]; then
            # Legacy signature fallback
            local legacy_sig
            legacy_sig="$(cat "$snap_dir/signature/${src_email}.sig")"
            [[ -n "$legacy_sig" ]] && zmprov csig "$src_email" "Restored" zimbraPrefMailSignatureHTML "$legacy_sig" </dev/null >/dev/null 2>&1 || true
        fi
    done 3< "$acc_list_file"

    zb_log "[LDAP 6/7] Restoring Sieve mail filters..."
    while IFS= read -r src_email <&3; do
        [[ -n "$src_email" ]] || continue
        local sieve_in
        sieve_in="$(zb_find_sieve_in_file "$snap_dir" "$src_email")"
        if [[ -n "$sieve_in" && -s "$sieve_in" ]]; then
            zmprov ma "$src_email" zimbraMailSieveScript "$(cat "$sieve_in")" </dev/null >/dev/null 2>&1 || true
        fi
        if [[ -s "$snap_dir/filters/${src_email}.out.sieve" ]]; then
            zmprov ma "$src_email" zimbraMailOutgoingSieveScript "$(cat "$snap_dir/filters/${src_email}.out.sieve")" </dev/null >/dev/null 2>&1 || true
        fi
    done 3< "$acc_list_file"

    if [[ "$scope_kind" == "all" && -s "$snap_dir/admins/admins.txt" ]]; then
        zb_log "[LDAP 7/7] Restoring global administrator privileges..."
        local adm
        while IFS= read -r adm <&3; do
            adm="$(zb_trim "$adm")"
            [[ -n "$adm" ]] || continue
            zmprov ma "$adm" zimbraIsAdminAccount TRUE </dev/null >/dev/null 2>&1 || true
        done 3< "$snap_dir/admins/admins.txt"
    else
        zb_log "[LDAP 7/7] Skipping global admin role changes (non-full-server scope)."
    fi

    rm -f -- "$req_doms"
    return 0
}

# Main restore execution (runs inside isolated subshell for lock & log safety)
zb_run_restore() (
    local from_selector=""
    local custom_dir=""
    local filter_job=""
    local scope_kind=""
    local scope_arg=""
    local target_user=""
    local only_part="all"       # all | mailbox | ldap
    local mode="skip"           # skip | modify | subfolder | reset
    local subfolder_name=""
    local dry_run=0
    local assume_yes=0

    while (( $# > 0 )); do
        case "$1" in
            --from) from_selector="$(zb_normalize_dir_input "${2-}")"; shift 2 ;;
            --dir) custom_dir="$(zb_normalize_dir_input "${2-}")"; shift 2 ;;
            --job) filter_job="${2-}"; shift 2 ;;
            --all) scope_kind="all"; scope_arg=""; shift ;;
            --domain|--domains) scope_kind="domain"; scope_arg="${2-}"; shift 2 ;;
            --users|--user) scope_kind="users"; scope_arg="${2-}"; shift 2 ;;
            --target-user) target_user="${2-}"; shift 2 ;;
            --only) only_part="${2-}"; shift 2 ;;
            --mode) mode="${2-}"; shift 2 ;;
            --subfolder-name) subfolder_name="${2-}"; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            --yes|-y) assume_yes=1; shift ;;
            *) zb_err "Unknown restore option: $1"; return 1 ;;
        esac
    done

    [[ -n "$from_selector" ]] || { zb_err "Missing --from <index|backup_id|path>."; return 1; }
    [[ -n "$scope_kind" ]] || { zb_err "Specify restore scope: --all, --domain <d1,d2>, or --users <u1,u2>."; return 1; }
    [[ "$only_part" == "all" || "$only_part" == "mailbox" || "$only_part" == "ldap" ]] || {
        zb_err "--only must be: all, mailbox, or ldap."
        return 1
    }
    [[ "$mode" == "skip" || "$mode" == "modify" || "$mode" == "subfolder" || "$mode" == "reset" ]] || {
        zb_err "--mode must be: skip, modify, subfolder, or reset."
        return 1
    }

    zb_load_settings || true
    zb_ensure_state_dirs || return 1
    zb_resolve_backup_selector "$from_selector" "$custom_dir" "$filter_job" || return 1
    local target_snap="$ZB_SELECTED_DIR"

    zb_resolve_restore_chain "$target_snap" || return 1
    local chain_len="${#ZB_RESTORE_CHAIN_DIRS[@]}"

    local acc_list
    acc_list="$(mktemp "$ZB_RUN_DIR/.rest_accs.XXXXXX")" || return 1
    cleanup_restore() {
        local rc=$?
        zb_cleanup_auth_token
        rm -f -- "$acc_list"
        return "$rc"
    }
    trap cleanup_restore EXIT

    zb_select_restore_accounts "$target_snap" "$scope_kind" "$scope_arg" "$acc_list" || return 1
    local acc_count
    acc_count="$(wc -l < "$acc_list" | awk '{print $1}')"

    if [[ -n "$target_user" ]]; then
        zb_valid_email "$target_user" || { zb_err "Invalid --target-user email address: $target_user"; return 1; }
        if (( acc_count != 1 )); then
            zb_err "--target-user is only allowed when restoring a single source account (selected: $acc_count)."
            return 1
        fi
    fi

    if [[ "$mode" == "subfolder" && -z "$subfolder_name" ]]; then
        subfolder_name="Restore_$(date +%Y%m%d_%H%M%S)"
    fi

    zb_msg "============================================================"
    zb_msg "ZIMBRA RESTORE EXECUTION PLAN"
    zb_msg "============================================================"
    zb_msg "  Selected Snapshot  : $target_snap"
    zb_msg "  Restore Chain      : $chain_len step(s)"
    local s_idx=0
    while (( s_idx < chain_len )); do
        zb_msg "    Step $((s_idx + 1))/$chain_len        : ${ZB_RESTORE_CHAIN_DIRS[$s_idx]}"
        s_idx=$((s_idx + 1))
    done
    zb_msg "  Scope              : $scope_kind ${scope_arg:+($scope_arg)} -> $acc_count account(s)"
    [[ -n "$target_user" ]] && zb_msg "  Redirect To User   : $target_user"
    zb_msg "  Components         : $only_part"
    zb_msg "  Conflict Mode      : $mode ${subfolder_name:+(folder: /$subfolder_name)}"
    zb_msg "  Dry-Run Mode       : $( (( dry_run == 1 )) && printf 'YES (preview only, no changes)' || printf 'NO (live restore)')"
    zb_msg "------------------------------------------------------------"
    zb_msg "  Accounts to restore:"
    sed 's/^/    - /' "$acc_list" | head -n 30
    (( acc_count > 30 )) && zb_msg "    ... and $((acc_count - 30)) more account(s)."
    zb_msg "============================================================"

    if (( dry_run == 1 )); then
        zb_info "Dry-run completed: no changes were made on the Zimbra server."
        return 0
    fi

    zb_require_zimbra_cli || return 1

    if (( assume_yes == 0 )) && [[ -t 0 ]]; then
        local confirm=""
        if [[ "$mode" == "reset" ]]; then
            read -r -p "WARNING: Mode 'reset' WIPES current mailbox data before importing! Type 'RESET' to confirm: " confirm
            [[ "$confirm" == "RESET" ]] || { zb_info "Restore canceled."; return 0; }
        else
            read -r -p "Proceed with restore now? [y/N]: " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { zb_info "Restore canceled."; return 0; }
        fi
    fi

    zb_acquire_lock || return 1
    zb_start_run_log "restore"

    local start_ts step_dir
    start_ts="$(date +%s)"
    zb_log "Verifying backup chain integrity before restore ($chain_len step(s))..."
    for step_dir in "${ZB_RESTORE_CHAIN_DIRS[@]}"; do
        if [[ -f "$step_dir/manifest" ]]; then
            zb_verify_snapshot_dir "$step_dir" "0" || return 1
        fi
    done

    # Restore LDAP metadata from the target point-in-time snapshot (latest state in chain)
    if [[ "$only_part" == "all" || "$only_part" == "ldap" ]]; then
        zb_restore_ldap_metadata "$target_snap" "$scope_kind" "$acc_list" "$target_user" || return 1
    fi

    local fail_mbox=0
    if [[ "$only_part" == "all" || "$only_part" == "mailbox" ]]; then
        local step_num=0
        for step_dir in "${ZB_RESTORE_CHAIN_DIRS[@]}"; do
            step_num=$((step_num + 1))
            local step_mode="$mode"
            # Critical: if user selected `reset` on an incremental chain, only step 1 (000_full) resets;
            # subsequent incremental steps MUST use `modify` or they would wipe the base full!
            if [[ "$mode" == "reset" && "$step_num" -gt 1 ]]; then
                step_mode="modify"
            fi

            zb_log "Importing mailboxes - Chain step ${step_num}/${chain_len}: ${step_dir##*/} (mode=$step_mode)"
            local u_idx=0 src_u dest_u
            while IFS= read -r src_u <&3; do
                [[ -n "$src_u" ]] || continue
                u_idx=$((u_idx + 1))
                dest_u="${target_user:-$src_u}"
                local tgz="$step_dir/mailboxes/${src_u}.tgz"

                if [[ -f "$step_dir/mailboxes/${src_u}.empty" ]]; then
                    zb_log "  ($u_idx/$acc_count) $src_u -> unchanged in step ${step_num}, skipping."
                    continue
                fi
                if [[ ! -f "$tgz" ]]; then
                    zb_log "  ($u_idx/$acc_count) $src_u -> no archive in step ${step_num}, skipping."
                    continue
                fi

                if ! zb_account_exists "$dest_u"; then
                    zb_log "  + Destination account '$dest_u' missing; creating automatically before mailbox import..."
                    zmprov ca "$dest_u" "Tmp$(date +%s)$$Aa1!" </dev/null >/dev/null 2>&1 || true
                fi

                zb_log "  ($u_idx/$acc_count) Importing ${tgz##*/} -> $dest_u ..."
                if ! zb_import_mailbox_archive "$dest_u" "$tgz" "$step_mode" "$subfolder_name"; then
                    zb_warn "Failed importing mailbox $src_u (step $step_num)."
                    fail_mbox=$((fail_mbox + 1))
                fi
            done 3< "$acc_list"
        done
    fi

    local elapsed=$(( $(date +%s) - start_ts ))
    if (( fail_mbox > 0 )); then
        zb_log "FINISHED RESTORE WITH $fail_mbox MAILBOX ERROR(S) (${elapsed}s). Log: $ZB_CURRENT_LOG"
        zb_notify "warn" "Restore completed with warnings (${fail_mbox} error(s))" "Snapshot: ${target_snap}
Accounts: ${acc_count}
Log: ${ZB_CURRENT_LOG}"
        return 1
    fi

    zb_log "============================================================"
    zb_log "RESTORE COMPLETED SUCCESSFULLY ($acc_count account(s), ${elapsed}s)"
    zb_log "Log: $ZB_CURRENT_LOG"
    zb_log "============================================================"
    zb_notify "ok" "Restore completed successfully" "Snapshot: ${target_snap}
Accounts: ${acc_count}
Mode: ${mode} (${only_part})
Duration: ${elapsed}s"
    return 0
)

# CLI handler: `zimbra-backup backup ...`
zb_cli_backup() {
    local sub="${1:-list}"
    shift || true
    local custom_dir=""
    local filter_job=""

    case "$sub" in
        list|ls)
            while (( $# > 0 )); do
                case "$1" in
                    --dir) custom_dir="$(zb_normalize_dir_input "${2-}")"; shift 2 ;;
                    --job) filter_job="${2-}"; shift 2 ;;
                    *) zb_err "Unknown option: $1"; return 1 ;;
                esac
            done
            zb_print_backup_catalog "$custom_dir" "$filter_job"
            ;;
        inspect|show)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup backup inspect <index|backup_id|path> [--job <id>|--dir <path>] [--search <kw>]"; return 1; }
            local sel="$1" search_kw=""
            shift
            while (( $# > 0 )); do
                case "$1" in
                    --dir) custom_dir="$(zb_normalize_dir_input "${2-}")"; shift 2 ;;
                    --job) filter_job="${2-}"; shift 2 ;;
                    --search) search_kw="${2-}"; shift 2 ;;
                    *) zb_err "Unknown option: $1"; return 1 ;;
                esac
            done
            zb_inspect_snapshot "$sel" "$custom_dir" "$search_kw" "$filter_job"
            ;;
        verify)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup backup verify <index|backup_id|path> [--job <id>|--dir <path>]"; return 1; }
            local vsel="$1"
            shift
            while (( $# > 0 )); do
                case "$1" in
                    --dir) custom_dir="$(zb_normalize_dir_input "${2-}")"; shift 2 ;;
                    --job) filter_job="${2-}"; shift 2 ;;
                    *) zb_err "Unknown option: $1"; return 1 ;;
                esac
            done
            zb_ensure_state_dirs || return 1
            zb_resolve_backup_selector "$vsel" "$custom_dir" "$filter_job" || return 1
            zb_resolve_restore_chain "$ZB_SELECTED_DIR" || return 1
            local s
            for s in "${ZB_RESTORE_CHAIN_DIRS[@]}"; do
                zb_info "Verifying SHA-256 checksums: $s ..."
                zb_verify_snapshot_dir "$s" "0" || return 1
            done
            zb_info "Verification PASSED (${#ZB_RESTORE_CHAIN_DIRS[@]} step(s) verified)."
            ;;
        user|users)
            [[ $# -ge 1 ]] || { zb_err "Usage: zimbra-backup backup user <email1,email2> [--dir <path>]"; return 1; }
            local emails="$1"
            shift
            [[ "${1:-}" == "--dir" ]] && { custom_dir="$(zb_normalize_dir_input "${2-}")"; shift 2; }
            zb_run_adhoc_users "$emails" "$custom_dir"
            ;;
        clean-pending)
            [[ "${1:-}" == "--dir" ]] && { custom_dir="$(zb_normalize_dir_input "${2-}")"; shift 2; }
            zb_clean_pending_dirs "$custom_dir"
            ;;
        *)
            zb_err "Unknown backup subcommand: $sub"
            return 1
            ;;
    esac
}
