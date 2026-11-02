#!/usr/bin/env bash
# Zimbra CLI & REST API wrapper: port auto-detection, secure ZM_ADMIN_AUTH_TOKEN handling,
# RFC-2849 LDIF unfolding + Base64 decoding, metadata export/import, and mailbox .tgz transfer.
# Compatible with Zimbra 8.8.15, 9, and 10 OSE on CentOS/RHEL 7, 8, 9 (Bash 4.2+, curl 7.29+).

ZB_REST_PORT=""
ZB_AUTH_CFG_FILE=""
ZB_AUTH_TOKEN_TIME=0
ZB_AUTH_TOKEN_USES=0

# Tracked attributes restored cleanly per account from unfolded LDIF
ZB_ACCOUNT_ATTR_KEYS=(
    displayName
    givenName
    sn
    initials
    company
    title
    description
    zimbraMailQuota
    zimbraAccountStatus
    zimbraPrefFromDisplay
    zimbraPrefMailForwardingAddress
    zimbraNotes
)

zb_require_zimbra_cli() {
    command -v zmprov >/dev/null 2>&1 || { zb_err "Command 'zmprov' not found in PATH ($PATH)"; return 1; }
    command -v zmmailbox >/dev/null 2>&1 || { zb_err "Command 'zmmailbox' not found in PATH ($PATH)"; return 1; }
    return 0
}

zb_detect_rest_port() {
    if [[ -n "$ZB_REST_PORT" ]]; then
        printf '%s' "$ZB_REST_PORT"
        return 0
    fi
    if [[ -n "${ZB_FORCE_REST_PORT:-}" ]]; then
        ZB_REST_PORT="$ZB_FORCE_REST_PORT"
        printf '%s' "$ZB_REST_PORT"
        return 0
    fi

    local p0 p1 p2 cand srv_host
    srv_host="$(zmhostname 2>/dev/null || hostname -f 2>/dev/null || printf 'localhost')"
    p0="$(zmprov -l gs "$srv_host" zimbraMailSSLPort 2>/dev/null | awk '/^zimbraMailSSLPort:/ {print $2; exit}')" || true
    p1="$(zmprov -l gcf zimbraMailSSLPort 2>/dev/null | awk '/^zimbraMailSSLPort:/ {print $2; exit}')" || true
    p2="$(zmprov -l gcf zimbraMailProxySSLPort 2>/dev/null | awk '/^zimbraMailProxySSLPort:/ {print $2; exit}')" || true

    local -a candidates=()
    [[ "$p0" =~ ^[0-9]+$ ]] && candidates+=("$p0")
    [[ "$p1" =~ ^[0-9]+$ ]] && candidates+=("$p1")
    [[ "$p2" =~ ^[0-9]+$ ]] && candidates+=("$p2")
    candidates+=("8443" "443" "7071")

    for cand in "${candidates[@]}"; do
        if curl -k -s --connect-timeout 3 --max-time 6 -o /dev/null "https://127.0.0.1:${cand}/" 2>/dev/null; then
            ZB_REST_PORT="$cand"
            printf '%s' "$ZB_REST_PORT"
            return 0
        fi
    done

    ZB_REST_PORT="${p1:-8443}"
    printf '%s' "$ZB_REST_PORT"
}

zb_cleanup_auth_token() {
    if [[ -n "${ZB_AUTH_CFG_FILE:-}" && -f "$ZB_AUTH_CFG_FILE" ]]; then
        rm -f -- "$ZB_AUTH_CFG_FILE"
    fi
    ZB_AUTH_CFG_FILE=""
    ZB_AUTH_TOKEN_TIME=0
    ZB_AUTH_TOKEN_USES=0
}

zb_fetch_raw_admin_token() {
    local token=""
    if command -v zmsoap >/dev/null 2>&1; then
        token="$(zmsoap -z -v AuthRequest 2>/dev/null | awk '
            match($0, /<authToken>[^<]+<\/authToken>/) {
                s = substr($0, RSTART + 11, RLENGTH - 23)
                print s
                exit
            }
        ')" || true
    fi
    if [[ -z "$token" ]]; then
        token="$(zmprov gao </dev/null 2>/dev/null | awk '/^authToken:/ {print $2; exit}')" || true
    fi
    token="$(zb_trim "$token")"
    [[ -n "$token" ]] || return 1
    printf '%s' "$token"
}

zb_ensure_auth_cfg() {
    local force="${1:-0}"
    local now
    now="$(date +%s)"
    if [[ "$force" != "1" && -n "$ZB_AUTH_CFG_FILE" && -f "$ZB_AUTH_CFG_FILE" ]]; then
        if (( (now - ZB_AUTH_TOKEN_TIME) < 1500 && ZB_AUTH_TOKEN_USES < 50 )); then
            ZB_AUTH_TOKEN_USES=$((ZB_AUTH_TOKEN_USES + 1))
            return 0
        fi
    fi

    zb_cleanup_auth_token
    local token
    token="$(zb_fetch_raw_admin_token)" || return 1
    zb_ensure_state_dirs || return 1

    ZB_AUTH_CFG_FILE="$(mktemp "$ZB_RUN_DIR/.zm_auth.XXXXXX")" || return 1
    chmod 600 "$ZB_AUTH_CFG_FILE"
    {
        printf 'insecure\n'
        printf 'silent\n'
        printf 'header = "Cookie: ZM_ADMIN_AUTH_TOKEN=%s"\n' "$token"
    } > "$ZB_AUTH_CFG_FILE"
    ZB_AUTH_TOKEN_TIME="$now"
    ZB_AUTH_TOKEN_USES=1
    return 0
}

# Unfold RFC-2849 LDIF continuation lines (leading single space) into one record per line:
# Output format: <attrName>\t<mode: plain|b64>\t<rawOrBase64Value>
zb_ldif_unfold() {
    local ldif_file="$1"
    awk '
        function flush_line(   idx, rest, attr, mode) {
            if (buf == "" || substr(buf, 1, 1) == "#") { buf = ""; return }
            idx = index(buf, ":")
            if (idx <= 1) { buf = ""; return }
            attr = substr(buf, 1, idx - 1)
            rest = substr(buf, idx + 1)
            if (substr(rest, 1, 1) == ":") {
                mode = "b64"
                rest = substr(rest, 2)
            } else {
                mode = "plain"
            }
            sub(/^[[:space:]]+/, "", rest)
            print attr "\t" mode "\t" rest
            buf = ""
        }
        {
            sub(/\r$/, "")
            if ($0 == "") {
                flush_line()
                next
            }
            if (substr($0, 1, 1) == " ") {
                buf = buf substr($0, 2)
            } else {
                flush_line()
                buf = $0
            }
        }
        END { flush_line() }
    ' "$ldif_file"
}

zb_decode_field_to_stdout() {
    local mode="$1" payload="$2"
    if [[ "$mode" == "b64" ]]; then
        printf '%s' "$payload" | base64 -d 2>/dev/null || printf '%s' "$payload" | base64 --decode 2>/dev/null
    else
        printf '%s' "$payload"
    fi
}

zb_encode_b64_single_line() {
    base64 2>/dev/null | tr -d '\r\n'
}

# Parse unfolded <email>.ldif and emit normalized restore artifacts:
# - passwords/<email>.shadow
# - aliases/<email>.txt
# - filters/<email>.sieve & filters/<email>.out.sieve
# - attributes/<email>.attrs  (each line: <attrName>\t<base64DecodedThenReencodedSingleLine>)
zb_extract_account_artifacts() {
    local ldif_file="$1" snap_dir="$2" email="$3"
    local out_root="${4:-$snap_dir}"
    mkdir -p -m 700 -- \
        "$out_root/passwords" \
        "$out_root/aliases" \
        "$out_root/filters" \
        "$out_root/attributes" || return 1

    local unfolded
    unfolded="$(mktemp "$ZB_RUN_DIR/.ldif_unfold.XXXXXX")" || return 1
    zb_ldif_unfold "$ldif_file" > "$unfolded"

    local attr mode payload decoded b64_line
    : > "$out_root/aliases/$email.txt"
    : > "$out_root/attributes/$email.attrs"

    while IFS=$'\t' read -r attr mode payload <&3; do
        [[ -n "$attr" ]] || continue
        case "$attr" in
            userPassword)
                zb_decode_field_to_stdout "$mode" "$payload" > "$out_root/passwords/$email.shadow"
                printf '\n' >> "$out_root/passwords/$email.shadow"
                ;;
            zimbraMailAlias)
                decoded="$(zb_decode_field_to_stdout "$mode" "$payload")"
                [[ -n "$decoded" ]] && printf '%s\n' "$decoded" >> "$out_root/aliases/$email.txt"
                ;;
            zimbraMailSieveScript)
                zb_decode_field_to_stdout "$mode" "$payload" > "$out_root/filters/$email.sieve"
                ;;
            zimbraMailOutgoingSieveScript)
                zb_decode_field_to_stdout "$mode" "$payload" > "$out_root/filters/$email.out.sieve"
                ;;
            displayName|givenName|sn|initials|company|title|description|zimbraMailQuota|zimbraAccountStatus|zimbraPrefFromDisplay|zimbraPrefMailForwardingAddress|zimbraNotes)
                b64_line="$(zb_decode_field_to_stdout "$mode" "$payload" | zb_encode_b64_single_line)"
                if [[ -n "$b64_line" ]]; then
                    printf '%s\t%s\n' "$attr" "$b64_line" >> "$out_root/attributes/$email.attrs"
                fi
                ;;
        esac
    done 3< "$unfolded"

    rm -f -- "$unfolded"
    [[ -s "$out_root/aliases/$email.txt" ]] || rm -f -- "$out_root/aliases/$email.txt"
    [[ -s "$out_root/attributes/$email.attrs" ]] || rm -f -- "$out_root/attributes/$email.attrs"
    [[ -s "$out_root/passwords/$email.shadow" ]] || rm -f -- "$out_root/passwords/$email.shadow"
    [[ -s "$out_root/filters/$email.sieve" ]] || rm -f -- "$out_root/filters/$email.sieve"
    [[ -s "$out_root/filters/$email.out.sieve" ]] || rm -f -- "$out_root/filters/$email.out.sieve"
    return 0
}

# Export account signatures using `zmprov -l gsig <email>` (NOT `gs` which is getServer!)
# Output file format (`signatures/<email>.sigs`):
# <b64(sigName)>\t<attr: zimbraPrefMailSignatureHTML|zimbraPrefMailSignature>\t<b64(sigContent)>
zb_export_account_signatures() {
    local email="$1" out_file="$2"
    local raw
    raw="$(mktemp "$ZB_RUN_DIR/.gsig.XXXXXX")" || return 1
    if ! zmprov -l gsig "$email" > "$raw" 2>/dev/null || [[ ! -s "$raw" ]]; then
        rm -f -- "$raw"
        return 0
    fi

    # Split gsig blocks on `# name ...` lines and unfold each block
    local parsed
    parsed="$(mktemp "$ZB_RUN_DIR/.gsig_parsed.XXXXXX")" || { rm -f -- "$raw"; return 1; }
    awk '
        function emit_entry(   idx, attr, rest, mode) {
            if (buf == "") return
            idx = index(buf, ":")
            if (idx > 1) {
                attr = substr(buf, 1, idx - 1)
                rest = substr(buf, idx + 1)
                if (substr(rest, 1, 1) == ":") { mode = "b64"; rest = substr(rest, 2) }
                else { mode = "plain" }
                sub(/^[[:space:]]+/, "", rest)
                print block_id "\t" attr "\t" mode "\t" rest
            }
            buf = ""
        }
        BEGIN { block_id = 0 }
        {
            sub(/\r$/, "")
            if ($0 ~ /^# name /) {
                emit_entry()
                block_id++
                next
            }
            if ($0 == "" || substr(buf, 1, 1) == "#") {
                emit_entry()
                next
            }
            if (substr($0, 1, 1) == " ") {
                buf = buf substr($0, 2)
            } else {
                emit_entry()
                buf = $0
            }
        }
        END { emit_entry() }
    ' "$raw" > "$parsed"

    : > "$out_file"
    local cur_blk="" sig_name="" html_b64="" text_b64=""
    local blk attr mode payload val_b64
    flush_sig_block() {
        [[ -n "$sig_name" ]] || return 0
        local name_b64
        name_b64="$(printf '%s' "$sig_name" | zb_encode_b64_single_line)"
        if [[ -n "$html_b64" ]]; then
            printf '%s\tzimbraPrefMailSignatureHTML\t%s\n' "$name_b64" "$html_b64" >> "$out_file"
        fi
        if [[ -n "$text_b64" ]]; then
            printf '%s\tzimbraPrefMailSignature\t%s\n' "$name_b64" "$text_b64" >> "$out_file"
        fi
    }

    while IFS=$'\t' read -r blk attr mode payload <&3; do
        [[ -n "$blk" ]] || continue
        if [[ "$blk" != "$cur_blk" ]]; then
            flush_sig_block
            cur_blk="$blk"
            sig_name=""
            html_b64=""
            text_b64=""
        fi
        case "$attr" in
            zimbraSignatureName)
                sig_name="$(zb_decode_field_to_stdout "$mode" "$payload")"
                ;;
            zimbraPrefMailSignatureHTML)
                val_b64="$(zb_decode_field_to_stdout "$mode" "$payload" | zb_encode_b64_single_line)"
                html_b64="$val_b64"
                ;;
            zimbraPrefMailSignature)
                val_b64="$(zb_decode_field_to_stdout "$mode" "$payload" | zb_encode_b64_single_line)"
                text_b64="$val_b64"
                ;;
        esac
    done 3< "$parsed"
    flush_sig_block

    rm -f -- "$raw" "$parsed"
    [[ -s "$out_file" ]] || rm -f -- "$out_file"
    return 0
}

# List all non-system Zimbra user accounts (including active, locked, lockout, maintenance, closed)
# while excluding internal system/resource accounts (galsync, spam, ham, virus-quarantine, calendar resources).
zb_list_active_accounts() {
    local out_file="$1"
    local raw
    raw="$(mktemp "$ZB_RUN_DIR/.acc_raw.XXXXXX")" || return 1
    if ! zmprov -l sa '(&(!(zimbraIsSystemAccount=TRUE))(!(zimbraIsSystemResource=TRUE))(!(objectClass=zimbraCalendarResource)))' > "$raw" 2>/dev/null || [[ ! -s "$raw" ]]; then
        zmprov -l gaa > "$raw" || { rm -f -- "$raw"; return 1; }
    fi
    LC_ALL=C sort -u "$raw" | tr -d '\r' | awk '
        /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/ &&
        !/^(galsync\.|spam\.|ham\.|virus-quarantine\.)/ { print }
    ' > "$out_file"
    rm -f -- "$raw"
    return 0
}

# Throttle heavy Java CLI `zmmailbox` fallback to at most 2 concurrent JVMs across workers
# so a REST outage during parallel backup cannot trigger an OOM storm on mailboxd.
zb_run_zmmailbox_throttled() {
    if command -v flock >/dev/null 2>&1 && [[ -d "$ZB_RUN_DIR" && ! -L "$ZB_RUN_DIR" ]]; then
        local slot=$(( $$ % 2 ))
        local slot_lock="$ZB_RUN_DIR/.jvm_slot_${slot}.lock"
        (
            exec 6>"$slot_lock" || exit 1
            flock 6
            zmmailbox "$@"
        )
    else
        zmmailbox "$@"
    fi
}

# Export mailbox .tgz for full or incremental mode.
# Returns:
#   0 -> success (either valid .tgz created, or empty-delta marker created when incremental has 0 items)
#   1 -> failed after retries
zb_export_mailbox_archive() {
    local email="$1"
    local out_tgz="$2"
    local mode="$3"              # full | incr
    local query_from_epoch="${4:-0}"
    local auth_cfg="${5:-}"      # optional shared curl -K file

    local rest_query="/?fmt=tgz"
    if [[ "$mode" == "incr" ]]; then
        local epoch_ms="${query_from_epoch}000"
        rest_query="/?fmt=tgz&query=after:${epoch_ms}"
    fi

    local port attempt=1 http_code="" ok=0 empty_delta=0 entry_cnt=""
    local cur_auth_cfg="$auth_cfg" priv_auth_cfg=""
    port="$(zb_detect_rest_port)"

    while (( attempt <= 3 )); do
        rm -f -- "$out_tgz"
        http_code=""
        if [[ -n "$cur_auth_cfg" && -f "$cur_auth_cfg" ]]; then
            http_code="$(curl -K "$cur_auth_cfg" -w '%{http_code}' -o "$out_tgz" \
                --connect-timeout 30 --max-time 7200 \
                "https://127.0.0.1:${port}/service/home/${email}${rest_query}" 2>/dev/null || printf '000')"
            if [[ "$http_code" == "401" ]]; then
                local fresh_tok=""
                fresh_tok="$(zb_fetch_raw_admin_token 2>/dev/null || true)"
                if [[ -n "$fresh_tok" ]]; then
                    [[ -n "$priv_auth_cfg" ]] && rm -f -- "$priv_auth_cfg"
                    priv_auth_cfg="$(mktemp "$ZB_RUN_DIR/.zm_auth_w.XXXXXX" 2>/dev/null || printf '')"
                    if [[ -n "$priv_auth_cfg" ]]; then
                        chmod 600 "$priv_auth_cfg"
                        {
                            printf 'insecure\n'
                            printf 'silent\n'
                            printf 'header = "Cookie: ZM_ADMIN_AUTH_TOKEN=%s"\n' "$fresh_tok"
                        } > "$priv_auth_cfg"
                        cur_auth_cfg="$priv_auth_cfg"
                        rm -f -- "$out_tgz"
                        http_code="$(curl -K "$cur_auth_cfg" -w '%{http_code}' -o "$out_tgz" \
                            --connect-timeout 30 --max-time 7200 \
                            "https://127.0.0.1:${port}/service/home/${email}${rest_query}" 2>/dev/null || printf '000')"
                    fi
                fi
            fi
            if [[ "$http_code" == "204" && "$mode" == "incr" ]]; then
                rm -f -- "$out_tgz"
                empty_delta=1
                ok=1
                break
            fi
            if [[ "$http_code" == "200" && -f "$out_tgz" ]]; then
                if [[ ! -s "$out_tgz" && "$mode" == "incr" ]]; then
                    rm -f -- "$out_tgz"
                    empty_delta=1
                    ok=1
                    break
                fi
                if entry_cnt="$(set -o pipefail; tar -tzf "$out_tgz" 2>/dev/null | awk 'END { print NR }')"; then
                    if [[ "$mode" == "incr" && "$entry_cnt" == "0" ]]; then
                        rm -f -- "$out_tgz"
                        empty_delta=1
                    fi
                    ok=1
                    break
                fi
            fi
        fi

        # Fallback via throttled zmmailbox CLI (max 2 concurrent JVMs)
        rm -f -- "$out_tgz"
        if zb_run_zmmailbox_throttled -z -m "$email" getRestURL "$rest_query" > "$out_tgz" 2>/dev/null; then
            if [[ ! -s "$out_tgz" && "$mode" == "incr" ]]; then
                rm -f -- "$out_tgz"
                empty_delta=1
                ok=1
                break
            fi
            if [[ -f "$out_tgz" ]] && entry_cnt="$(set -o pipefail; tar -tzf "$out_tgz" 2>/dev/null | awk 'END { print NR }')"; then
                if [[ "$mode" == "incr" && "$entry_cnt" == "0" ]]; then
                    rm -f -- "$out_tgz"
                    empty_delta=1
                fi
                ok=1
                break
            fi
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    [[ -n "$priv_auth_cfg" ]] && rm -f -- "$priv_auth_cfg"

    if (( ok == 0 )); then
        rm -f -- "$out_tgz"
        return 1
    fi
    if (( empty_delta == 1 )); then
        touch "${out_tgz%.tgz}.empty"
    fi
    return 0
}

# Import mailbox .tgz into destination account with conflict handling:
# mode: skip | modify | reset | subfolder
zb_import_mailbox_archive() {
    local dest_email="$1"
    local tgz_file="$2"
    local mode="${3:-skip}"
    local subfolder_name="${4:-}"

    [[ -f "$tgz_file" ]] || { zb_err "Mailbox archive file not found: $tgz_file"; return 1; }
    tar -tzf "$tgz_file" >/dev/null 2>&1 || { zb_err "Corrupted mailbox archive (tar validation failed): $tgz_file"; return 1; }

    local rest_path="/?fmt=tgz&resolve=skip"
    case "$mode" in
        skip) rest_path="/?fmt=tgz&resolve=skip" ;;
        modify) rest_path="/?fmt=tgz&resolve=modify" ;;
        reset) rest_path="/?fmt=tgz&resolve=reset" ;;
        subfolder)
            subfolder_name="${subfolder_name#/}"
            [[ -n "$subfolder_name" ]] || subfolder_name="Restore_$(date +%Y%m%d_%H%M%S)"
            zb_valid_subfolder_name "$subfolder_name" || {
                zb_err "Invalid subfolder name '$subfolder_name' (allowed: letters, digits, '.', '_', '-', '/'; no '..' or query characters)."
                return 1
            }
            zb_run_zmmailbox_throttled -z -m "$dest_email" cf "/$subfolder_name" </dev/null >/dev/null 2>&1 || true
            rest_path="/${subfolder_name}?fmt=tgz&resolve=skip"
            ;;
        *)
            zb_err "Invalid mailbox restore mode: $mode"
            return 1
            ;;
    esac

    local port http_code=""
    port="$(zb_detect_rest_port)"
    if zb_ensure_auth_cfg 0; then
        http_code="$(curl -K "$ZB_AUTH_CFG_FILE" -w '%{http_code}' -o /dev/null \
            --connect-timeout 60 --max-time 10800 -X POST -T "$tgz_file" \
            "https://127.0.0.1:${port}/service/home/${dest_email}${rest_path}" 2>/dev/null || printf '000')"
        if [[ "$http_code" == "401" ]] && zb_ensure_auth_cfg 1; then
            http_code="$(curl -K "$ZB_AUTH_CFG_FILE" -w '%{http_code}' -o /dev/null \
                --connect-timeout 60 --max-time 10800 -X POST -T "$tgz_file" \
                "https://127.0.0.1:${port}/service/home/${dest_email}${rest_path}" 2>/dev/null || printf '000')"
        fi
        if [[ "$http_code" == "200" || "$http_code" == "204" ]]; then
            return 0
        fi
        zb_log "WARNING: cURL returned HTTP $http_code for $dest_email, falling back to zmmailbox..."
    fi

    zb_run_zmmailbox_throttled -t 10800 -z -m "$dest_email" postRestURL "$rest_path" "$tgz_file" </dev/null >/dev/null 2>&1 || {
        zb_err "Mailbox restore failed for account: $dest_email"
        return 1
    }
    return 0
}
