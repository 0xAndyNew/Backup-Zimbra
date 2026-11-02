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

    local -a args=(--fail --silent --connect-timeout 8 --max-time 20 -K "$cfg" --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$text")
    if [[ -n "${TELEGRAM_THREAD_ID:-}" ]]; then
        args+=(--data-urlencode "message_thread_id=$TELEGRAM_THREAD_ID")
    fi

    local rc=0
    curl "${args[@]}" >/dev/null 2>&1 || rc=$?
    rm -f -- "$cfg"
    if (( rc != 0 )); then
        zb_log "WARNING: Failed to send Telegram alert (curl exit code=$rc)."
        return 1
    fi
    return 0
}

zb_send_email_alert() {
    [[ "${EMAIL_ALERT_ENABLED:-no}" == "yes" && -n "${EMAIL_ALERT_TO:-}" ]] || return 0
    local subject="$1"
    local body="$2"
    if command -v sendmail >/dev/null 2>&1; then
        {
            printf 'To: %s\n' "$EMAIL_ALERT_TO"
            printf 'Subject: %s\n' "$subject"
            printf 'Content-Type: text/plain; charset=UTF-8\n\n'
            printf '%s\n' "$body"
        } | sendmail -t >/dev/null 2>&1 || {
            zb_log "WARNING: Failed to send email alert to $EMAIL_ALERT_TO."
            return 1
        }
    elif [[ -x "$ZB_ZIMBRA_HOME/common/sbin/sendmail" ]]; then
        {
            printf 'To: %s\n' "$EMAIL_ALERT_TO"
            printf 'Subject: %s\n' "$subject"
            printf 'Content-Type: text/plain; charset=UTF-8\n\n'
            printf '%s\n' "$body"
        } | "$ZB_ZIMBRA_HOME/common/sbin/sendmail" -t >/dev/null 2>&1 || {
            zb_log "WARNING: Failed to send email alert via Zimbra sendmail."
            return 1
        }
    else
        zb_log "WARNING: 'sendmail' binary not found for email alerts."
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
    local full_msg="${icon} [${host}] ${title}
${details}"
    zb_send_telegram "$full_msg" || true
    if [[ "$status_tag" != "ok" ]]; then
        zb_send_email_alert "${icon} Zimbra Backup (${host}): ${title}" "$full_msg" || true
    fi
}
