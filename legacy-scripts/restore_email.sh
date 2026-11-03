#!/bin/bash
# ==============================================================================
# Script: zimbra_restore_all.sh (V2 - Chong Treo / Fast LDAP Mode)
# Muc dich: Restore TOAN DIEN Zimbra (Khac phuc loi treo o buoc 1/8)
# ==============================================================================

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")")"
if [ "$(id -u)" -ne "$(id -u zimbra 2>/dev/null || echo -1)" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "[*] Phat hien quyen root. Dang tu dong chuyen sang user zimbra..."
        chmod 755 "${SCRIPT_PATH}" 2>/dev/null || true
        exec su - zimbra -c "bash \"${SCRIPT_PATH}\" \"$@\""
    else
        exit 1
    fi
fi

set -eo pipefail

if [ "$#" -ne 1 ]; then
    echo "Cach dung: $0 <DUONG_DAN_THU_MUC_BACKUP>"
    exit 1
fi

RESTORE_DIR="$1"
if [ ! -d "${RESTORE_DIR}" ]; then
    echo "[!] Khong tim thay thu muc: ${RESTORE_DIR}"; exit 1
fi

# NHAN DIEN FILE
DOMAIN_FILE="${RESTORE_DIR}/domains.txt"
[ ! -f "$DOMAIN_FILE" ] && DOMAIN_FILE="${RESTORE_DIR}/domains/domains.txt"
ACCOUNT_FILE="${RESTORE_DIR}/emails.txt"
[ ! -f "$ACCOUNT_FILE" ] && ACCOUNT_FILE="${RESTORE_DIR}/accounts/active_accounts.txt"
ADMIN_FILE="${RESTORE_DIR}/admins.txt"
[ ! -f "$ADMIN_FILE" ] && ADMIN_FILE="${RESTORE_DIR}/admins/admins.txt"
DL_FILE="${RESTORE_DIR}/distributinlist.txt"
[ ! -f "$DL_FILE" ] && DL_FILE="${RESTORE_DIR}/dl/distribution_lists.txt"
DL_MEMBERS_DIR="${RESTORE_DIR}/distributinlist_members"
[ ! -d "$DL_MEMBERS_DIR" ] && DL_MEMBERS_DIR="${RESTORE_DIR}/distribution_lists"
MAILBOX_DIR="${RESTORE_DIR}/mailbox"
[ ! -d "$MAILBOX_DIR" ] && MAILBOX_DIR="${RESTORE_DIR}/mailboxes"
PASS_DIR="${RESTORE_DIR}/userpass"
ALIAS_DIR="${RESTORE_DIR}/alias"
FILTER_DIR="${RESTORE_DIR}/filter"
QUOTA_DIR="${RESTORE_DIR}/quota"
USERDATA_DIR="${RESTORE_DIR}/userdata"
SIG_DIR="${RESTORE_DIR}/signature"
DEFAULT_TEMP_PASS="Temp@ZimbraRestore2026!"

LOG_FILE="${RESTORE_DIR}/restore_full.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[+] ==========================================================="
echo "[+] BAT DAU TIEN TRINH RESTORE TOAN DIEN (V2)"
echo "[+] ==========================================================="

# 1. KHOI PHUC DOMAINS (DUNG FD3)
echo "[+] --- 1/8: Khoi phuc Domains ---"
if [ -f "$DOMAIN_FILE" ]; then
    while IFS= read -r dom <&3; do
        dom=$(echo "$dom" | tr -d '\r\n ')
        [ -z "$dom" ] && continue
        # Dung -l de query LDAP truc tiep (Sieu nhanh, khong the treo)
        if ! zmprov -l gd "$dom" >/dev/null 2>&1; then
            echo " -> Dang tao domain: $dom"
            zmprov cd "$dom" </dev/null || true
        else
            echo " -> Da ton tai: $dom"
        fi
    done 3< "$DOMAIN_FILE"
fi

# 2. ACCOUNTS & PASSWORDS (DUNG FD3)
echo "[+] --- 2/8: Khoi phuc Accounts & Metadata ---"
if [ -f "$ACCOUNT_FILE" ]; then
    while IFS= read -r acc <&3; do
        acc=$(echo "$acc" | tr -d '\r\n ')
        [ -z "$acc" ] && continue
        
        if ! zmprov -l ga "$acc" >/dev/null 2>&1; then
            echo " -> Dang tao account: $acc"
            zmprov ca "$acc" "${DEFAULT_TEMP_PASS}" </dev/null || true
        fi

        if [ -s "${PASS_DIR}/${acc}.shadow" ]; then
            pass_hash=$(cat "${PASS_DIR}/${acc}.shadow" | tr -d '\r\n')
            [ -n "$pass_hash" ] && zmprov ma "$acc" userPassword "$pass_hash" </dev/null >/dev/null 2>&1 || true
        fi
        
        if [ -s "${QUOTA_DIR}/${acc}.txt" ]; then
            quota_val=$(cat "${QUOTA_DIR}/${acc}.txt" | tr -d '\r\n ')
            [ -n "$quota_val" ] && zmprov ma "$acc" zimbraMailQuota "$quota_val" </dev/null >/dev/null 2>&1 || true
        fi

        if [ -s "${USERDATA_DIR}/${acc}.txt" ]; then
            display_name=$(grep -i '^displayName:' "${USERDATA_DIR}/${acc}.txt" | sed 's/^displayName: //I' | tr -d '\r\n' || true)
            [ -n "$display_name" ] && zmprov ma "$acc" displayName "$display_name" </dev/null >/dev/null 2>&1 || true
        fi
    done 3< "$ACCOUNT_FILE"
fi

# 3. KHOI PHUC ALIASES
echo "[+] --- 3/8: Khoi phuc Mail Aliases ---"
if [ -d "$ALIAS_DIR" ]; then
    for alias_file in "${ALIAS_DIR}/"*.txt; do
        [ -f "$alias_file" ] || continue
        acc=$(basename "$alias_file" .txt)
        while IFS= read -r alias <&3; do
            alias=$(echo "$alias" | tr -d '\r\n ')
            [ -z "$alias" ] && continue
            echo " -> Them alias: $alias cho account: $acc"
            zmprov aaa "$acc" "$alias" </dev/null >/dev/null 2>&1 || true
        done 3< "$alias_file"
    done
fi

# 4. KHOI PHUC DL BATCH
echo "[+] --- 4/8: Khoi phuc Distribution Lists (Batch Mode) ---"
if [ -f "$DL_FILE" ]; then
    BATCH_FILE="/tmp/zimbra_dl_batch.zmp"
    rm -f "${BATCH_FILE}" && touch "${BATCH_FILE}"

    while IFS= read -r dl <&3; do
        dl=$(echo "$dl" | tr -d '\r\n ')
        [ -z "$dl" ] && continue
        
        echo "cdl $dl" >> "${BATCH_FILE}"
        member_file="${DL_MEMBERS_DIR}/${dl}.txt"
        if [ -f "$member_file" ]; then
            members=$(grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$member_file" | grep -v -i -x "$dl" || true)
            for m in $members; do
                [ -z "$m" ] && continue
                echo "adlm $dl $m" >> "${BATCH_FILE}"
            done
        fi
    done 3< "$DL_FILE"
    
    echo " -> Dang nap hang loat Groups..."
    zmprov -f "${BATCH_FILE}" </dev/null >/dev/null 2>&1 || true
    rm -f "${BATCH_FILE}"
fi

# 5. KHOI PHUC SIGNATURES
echo "[+] --- 5/8: Khoi phuc Chu ky ---"
if [ -d "$SIG_DIR" ]; then
    for sig_file in "${SIG_DIR}/"*.signature; do
        [ -f "$sig_file" ] || continue
        acc=$(basename "$sig_file" .signature)
        name_file="${SIG_DIR}/${acc}.name"
        
        sig_content=$(cat "$sig_file" 2>/dev/null || true)
        sig_name="Default"
        [ -s "$name_file" ] && sig_name=$(cat "$name_file" | head -n 1 | tr -d '\r\n')

        if [ -n "$sig_content" ]; then
            zmprov csig "$acc" "$sig_name" zimbraPrefMailSignatureHTML "$sig_content" </dev/null >/dev/null 2>&1 || true
        fi
    done
fi

# 6. KHOI PHUC FILTERS
echo "[+] --- 6/8: Khoi phuc Sieve Filters ---"
if [ -d "$FILTER_DIR" ]; then
    for filter_file in "${FILTER_DIR}/"*.filter; do
        [ -f "$filter_file" ] || continue
        acc=$(basename "$filter_file" .filter)
        filter_content=$(cat "$filter_file")
        if [ -n "$filter_content" ]; then
            zmprov ma "$acc" zimbraMailSieveScript "$filter_content" </dev/null >/dev/null 2>&1 || true
        fi
    done
fi

# 7. KHOI PHUC ADMIN
echo "[+] --- 7/8: Khoi phuc quyen Admin ---"
if [ -f "$ADMIN_FILE" ]; then
    while IFS= read -r admin <&3; do
        admin=$(echo "$admin" | tr -d '\r\n ')
        [ -z "$admin" ] && continue
        zmprov ma "$admin" zimbraIsAdminAccount TRUE </dev/null >/dev/null 2>&1 || true
    done 3< "$ADMIN_FILE"
fi

# 8. IMPORT MAILBOX (cURL NATIVE)
echo "[+] --- 8/8: Khoi phuc Mailbox (.tgz) bang cURL Native ---"
if [ -d "$MAILBOX_DIR" ]; then
    MAIL_PORT=$(zmprov gcf zimbraMailSSLPort 2>/dev/null | awk '{print $2}' || true)
    [ -z "$MAIL_PORT" ] && MAIL_PORT="8443"
    if ! curl -k -s "https://127.0.0.1:${MAIL_PORT}/" >/dev/null 2>&1; then MAIL_PORT="7071"; fi
    
    get_auth_token() {
        local token=$(zmsoap -z -v AuthRequest 2>/dev/null | grep -oPm1 "(?<=<authToken>)[^<]+" || true)
        [ -z "$token" ] && token=$(zmprov gao </dev/null | grep -E '^authToken:' | awk '{print $2}' || true)
        echo "$token"
    }

    ADMIN_TOKEN=$(get_auth_token)
    
    if [ -n "$ADMIN_TOKEN" ]; then
        ACCOUNT_LIST=$(ls -1 "${MAILBOX_DIR}" | grep '\.tgz$' | sed 's/\.tgz$//')
        TOTAL_ACC=$(echo "${ACCOUNT_LIST}" | grep -v '^$' | wc -l)
        CURRENT=0

        for email in ${ACCOUNT_LIST}; do
            [ -z "$email" ] && continue
            CURRENT=$((CURRENT + 1))
            tgz_file="${MAILBOX_DIR}/${email}.tgz"
            
            size=$(stat -c%s "${tgz_file}" 2>/dev/null || echo 0)
            if [ "$size" -lt 200 ]; then continue; fi

            echo " -> [IMPORTING] ($CURRENT/$TOTAL_ACC) $email | Size: $(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size}B)..."
            
            if [ $((CURRENT % 50)) -eq 0 ]; then ADMIN_TOKEN=$(get_auth_token); fi

            HTTP_STATUS=$(curl -k -s -w "%{http_code}" -o /dev/null \
                --max-time 0 --connect-timeout 60 -X POST -T "${tgz_file}" \
                -H "Cookie: ZM_ADMIN_AUTH_TOKEN=${ADMIN_TOKEN}" \
                "https://127.0.0.1:${MAIL_PORT}/service/home/${email}/?fmt=tgz&resolve=skip" 2>/dev/null || echo "ERROR")

            if [ "$HTTP_STATUS" == "200" ]; then
                echo "    [OK] Thanh cong."
            else
                echo "    [FAIL] Loi HTTP: ${HTTP_STATUS}. Fallback qua zmmailbox..."
                zmmailbox -t 10800 -z -m "$email" postRestURL "/?fmt=tgz&resolve=skip" "${tgz_file}" </dev/null >/dev/null 2>&1 || echo "    [FAIL] That bai!"
            fi
        done
    else
        echo " [!] Loi: Khong the tao Admin Token. Bo qua Mailbox."
    fi
fi

echo "[+] ==========================================================="
echo "[+] HOAN TAT TOAN BO TIEN TRINH RESTORE LUC: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[+] ==========================================================="
