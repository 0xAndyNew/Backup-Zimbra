#!/usr/bin/env bash
# Notification helpers: Telegram Bot API and optional Email alerts with hostname context.
# Compatible with Bash 4.2+.

zb_send_telegram() {
    [[ "${TELEGRAM_ENABLED:-no}" == "yes" && -n "${TELEGRAM_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
    local text="$1"
    local cfg
    zb_ensure_state_dirs || return 1
    cfg="$(mktemp "$ZB_RUN_DIR/.tg_curl.XXXXXX")" || return 1
    chmod 600 "$cfg"
    # Hide bot token URL from process table (ps aux) via curl -K config file
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_TOKEN" > "$cfg"

    local -a args=(--silent --show-error --connect-timeout 8 --max-time 20 -K "$cfg" --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$text")
    if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
        args+=(--data-urlencode "message_thread_id=$TELEGRAM_THREAD_ID")
    fi

    local rc=0 tg_resp=""
    set +e
    tg_resp="$(curl "${args[@]}" 2>&1)"
    rc=$?
    set -e
    rm -f -- "$cfg"

    ZB_LAST_TELEGRAM_ERR=""
    if (( rc != 0 )); then
        ZB_LAST_TELEGRAM_ERR="Network/curl error (code $rc): ${tg_resp:-connection failed}"
        zb_log "WARNING: Failed to send Telegram alert: $ZB_LAST_TELEGRAM_ERR"
        return 1
    elif [[ -n "$tg_resp" && "$tg_resp" == *'"ok":false'* ]]; then
        local desc=""
        if [[ "$tg_resp" =~ \"description\":\"([^\"]+)\" ]]; then
            desc="${BASH_REMATCH[1]}"
        else
            desc="$tg_resp"
        fi
        ZB_LAST_TELEGRAM_ERR="Telegram API error: $desc"
        zb_log "WARNING: Failed to send Telegram alert: $ZB_LAST_TELEGRAM_ERR"
        return 1
    fi
    return 0
}

zb_send_email_alert() {
    [[ "${EMAIL_ALERT_ENABLED:-no}" == "yes" && -n "${EMAIL_ALERT_TO:-}" ]] || return 0
    local subject="$1"
    local body="$2"
    local sm_bin="" host_from
    # Prefer Zimbra's bundled Postfix sendmail (system sendmail is often absent on Zimbra hosts)
    if [[ -x "$ZB_ZIMBRA_HOME/common/sbin/sendmail" ]]; then
        sm_bin="$ZB_ZIMBRA_HOME/common/sbin/sendmail"
    elif command -v sendmail >/dev/null 2>&1; then
        sm_bin="$(command -v sendmail)"
    else
        zb_log "WARNING: 'sendmail' binary not found for email alerts."
        return 1
    fi
    host_from="$(zb_host_label)"
    local mail_from_domain="$host_from"
    # If host label is an IP address, fallback to valid FQDN/hostname so MTAs don't reject the From header
    if [[ "$mail_from_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$mail_from_domain" =~ : ]]; then
        local cand=""
        if [[ -x "$ZB_ZIMBRA_BIN/zmhostname" ]]; then
            cand="$("$ZB_ZIMBRA_BIN/zmhostname" 2>/dev/null || true)"
        fi
        [[ -n "$cand" ]] || cand="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
        if [[ -n "$cand" && ! "$cand" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            mail_from_domain="$cand"
        else
            mail_from_domain="localhost"
        fi
    fi
    local sm_err="" sm_rc=0
    set +e
    sm_err="$({
        printf 'From: zimbra-backup <%s@%s>\n' "$ZB_ZIMBRA_USER" "$mail_from_domain"
        printf 'To: %s\n' "$EMAIL_ALERT_TO"
        printf 'Subject: %s\n' "$subject"
        printf 'Date: %s\n' "$(LC_ALL=C date -R 2>/dev/null || LC_ALL=C date)"
        printf 'MIME-Version: 1.0\n'
        printf 'Content-Type: text/plain; charset=UTF-8\n\n'
        printf '%s\n' "$body"
    } | "$sm_bin" -t 2>&1)"
    sm_rc=$?
    set -e
    ZB_LAST_EMAIL_ERR="$sm_err"
    if (( sm_rc != 0 )); then
        zb_log "WARNING: Failed to send email alert to $EMAIL_ALERT_TO via $sm_bin (exit code=$sm_rc): $sm_err"
        return 1
    fi
    return 0
}

zb_test_email() {
    [[ "${EMAIL_ALERT_ENABLED:-no}" == "yes" && -n "${EMAIL_ALERT_TO:-}" ]] || {
        zb_err "Email alerts are not enabled or EMAIL_ALERT_TO is not set."
        return 1
    }
    local host
    host="$(zb_host_label)"
    local subject="[TEST] Zimbra Backup (${host}): Email notification test"
    local body="[TEST] [${host}] Email notification test
============================================================
Event      : Email Alert Delivery Test
Server     : ${host}
Recipient  : ${EMAIL_ALERT_TO}
Alert Level: ${EMAIL_ALERT_LEVEL:-all}
Status     : OK
Timestamp  : $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
Engine     : zimbra-backup v${ZB_VERSION}
------------------------------------------------------------
If you received this email, email notifications for
Zimbra Backup are configured and functioning properly.
============================================================"
    zb_info "Dispatching test email to $EMAIL_ALERT_TO..."
    if zb_send_email_alert "$subject" "$body"; then
        zb_info "Test email sent successfully to $EMAIL_ALERT_TO."
        return 0
    else
        zb_err "Failed to dispatch test email to $EMAIL_ALERT_TO: ${ZB_LAST_EMAIL_ERR:-check sendmail / Postfix logs}."
        return 1
    fi
}

zb_test_telegram() {
    if [[ "${TELEGRAM_ENABLED:-no}" != "yes" || -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        zb_err "Telegram alerts are not enabled or token/chat ID is missing."
        return 1
    fi
    local host
    host="$(zb_host_label)"
    zb_info "Sending test Telegram message to chat ${TELEGRAM_CHAT_ID}..."
    local test_msg="[OK] [${host}] Test notification from zimbra-backup v${ZB_VERSION}
============================================================
Event      : Telegram Alert Delivery Test
Server     : ${host}
Chat ID    : ${TELEGRAM_CHAT_ID}
Status     : OK
Timestamp  : $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
Engine     : zimbra-backup v${ZB_VERSION}
------------------------------------------------------------
If you received this message, Telegram notifications
for Zimbra Backup are configured and functioning properly.
============================================================"
    if zb_send_telegram "$test_msg"; then
        zb_info "Test Telegram message sent successfully to chat ${TELEGRAM_CHAT_ID}."
        return 0
    else
        zb_err "Failed to send Telegram message: ${ZB_LAST_TELEGRAM_ERR:-check token, chat ID, bot permissions in group, and network connectivity}."
        return 1
    fi
}

zb_test_ftp() {
    local target_job="${1:-}"
    if [[ -n "$target_job" ]]; then
        if ! zb_job_load "$target_job"; then
            zb_err "Cannot load job '$target_job' for FTP test."
            return 1
        fi
    fi
    if [[ -z "${FTP_HOST:-}" || -z "${FTP_USER:-}" ]]; then
        zb_err "Remote storage is not configured (missing FTP_HOST or FTP_USER). Specify a job: zimbra-backup notify test-ftp <job_id>"
        return 1
    fi
    local proto="${FTP_PROTOCOL:-ftp}"
    local port="${FTP_PORT:-21}"
    if [[ "$proto" == "sftp" && "$port" == "21" ]]; then
        port="22"
    fi
    zb_info "Testing remote $proto connection to $FTP_HOST:$port (user: $FTP_USER)..."

    local cfg
    zb_ensure_state_dirs || return 1
    cfg="$(mktemp "$ZB_RUN_DIR/.ftp_test.XXXXXX")" || return 1
    chmod 600 "$cfg"
    # Technical Invariant #2: Hide credentials from process table
    printf 'user = "%s:%s"\n' "$(zb_curl_escape "$FTP_USER")" "$(zb_curl_escape "$FTP_PASSWORD")" > "$cfg"

    local remote_path="${FTP_REMOTE_DIR:-/}"
    [[ "$remote_path" == /* ]] || remote_path="/$remote_path"
    [[ "$remote_path" == */ ]] || remote_path="$remote_path/"

    local -a curl_args=(
        --fail --silent --show-error
        --connect-timeout 10 --max-time 30
        -K "$cfg"
    )

    local target_url=""
    if [[ "$proto" == "sftp" ]]; then
        target_url="sftp://${FTP_HOST}:${port}${remote_path}"
        curl_args+=(--insecure)
    else
        target_url="ftp://${FTP_HOST}:${port}${remote_path}"
        if [[ "${FTP_SSL:-no}" == "yes" ]]; then
            curl_args+=(--ssl-reqd --insecure)
        fi
    fi

    local curl_out="" curl_rc=0
    set +e
    curl_out="$(curl "${curl_args[@]}" "$target_url" 2>&1)"
    curl_rc=$?
    set -e
    rm -f -- "$cfg"

    if (( curl_rc == 0 )); then
        zb_info "Connection test SUCCESSFUL to $proto://$FTP_HOST:$port$remote_path"
        return 0
    else
        zb_err "Connection test FAILED to $proto://$FTP_HOST:$port (curl exit code=$curl_rc): $curl_out"
        return 1
    fi
}

zb_notify() {
    local status_tag="$1"
    local title="$2"
    local details="$3"
    local host icon
    host="$(zb_host_label)"
    case "$status_tag" in
        ok) icon="[OK]" ;;
        warn) icon="[WARN]" ;;
        *) icon="[ERROR]" ;;
    esac
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"

    local full_msg="${icon} [${host}] ${title}
============================================================
${details}
------------------------------------------------------------
Server         : ${host}
Timestamp      : ${ts}
Engine         : zimbra-backup v${ZB_VERSION}
============================================================"
    zb_send_telegram "$full_msg" || true
    local send_email=0
    if [[ "${EMAIL_ALERT_ENABLED:-no}" == "yes" && -n "${EMAIL_ALERT_TO:-}" ]]; then
        if [[ "${EMAIL_ALERT_LEVEL:-all}" == "all" ]]; then
            send_email=1
        elif [[ "$status_tag" != "ok" ]]; then
            send_email=1
        fi
    fi
    if (( send_email == 1 )); then
        zb_send_email_alert "${icon} Zimbra Backup (${host}): ${title}" "$full_msg" || true
    fi
}
