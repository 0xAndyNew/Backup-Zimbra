#!/bin/bash
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")")"
if [ "$(id -u)" -ne "$(id -u zimbra 2>/dev/null || echo -1)" ]; then
    chmod 755 "${SCRIPT_PATH}" 2>/dev/null || true
    exec su - zimbra -c "bash \"${SCRIPT_PATH}\" \"$@\""
fi
set -eo pipefail

DATE=$(date +%Y%m%d_%H%M%S)
TODAY_FORMAT=$(date +'%m/%d/%Y')
BACKUP_DIR="/mnt/backup/incremental/${DATE}"
LOG_FILE="${BACKUP_DIR}/incr_backup.log"
PARALLEL_JOBS=4

# 1. DON DEP TRUOC KHI BACKUP
find /mnt/backup/full/ -mindepth 1 -maxdepth 1 -type d -mtime +8 -exec rm -rf {} + 2>/dev/null || true
find /mnt/backup/incremental/ -mindepth 1 -maxdepth 1 -type d -mtime +8 -exec rm -rf {} + 2>/dev/null || true

mkdir -p "${BACKUP_DIR}"/mailboxes
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[+] ==========================================================="
echo "[+] BAT DAU INCREMENTAL BACKUP"
echo "[+] ==========================================================="

# Lay accounts active bang LDAP (nhanh gap 10 lan)
zmprov -l sa '(zimbraAccountStatus=active)' | grep -E -v '^(galsync\.|spam\.|ham\.|virus-quarantine\.)' | sort > "${BACKUP_DIR}/emails.txt"

export BACKUP_DIR
export TODAY_FORMAT
export MAIL_PORT=$(zmprov gcf zimbraMailSSLPort 2>/dev/null | awk '{print $2}' || echo "8443")
export TOKEN_FILE="/tmp/zimbra_admin_token.txt"

# Lay Auth Token chuan
zmsoap -z -v AuthRequest 2>/dev/null | grep -oPm1 "(?<=<authToken>)[^<]+" > "$TOKEN_FILE"

backup_delta_curl() {
    local email="$1"
    local output_file="${BACKUP_DIR}/mailboxes/${email}.tgz"
    local token=$(cat "$TOKEN_FILE")
    
    # Query dung date:>= (Không dùng after:)
    local http_code=$(curl -k -s -w "%{http_code}" -o "${output_file}" -H "Cookie: ZM_ADMIN_AUTH_TOKEN=${token}" \
    "https://127.0.0.1:${MAIL_PORT}/service/home/${email}/?fmt=tgz&query=date:>=${TODAY_FORMAT}")
    
    # Renew token neu 401
    if [ "$http_code" == "401" ]; then
        zmsoap -z -v AuthRequest 2>/dev/null | grep -oPm1 "(?<=<authToken>)[^<]+" > "$TOKEN_FILE"
        token=$(cat "$TOKEN_FILE")
        http_code=$(curl -k -s -w "%{http_code}" -o "${output_file}" -H "Cookie: ZM_ADMIN_AUTH_TOKEN=${token}" \
        "https://127.0.0.1:${MAIL_PORT}/service/home/${email}/?fmt=tgz&query=date:>=${TODAY_FORMAT}")
    fi

    # Kiem tra ket qua va xoa file rong (duoi 200 bytes)
    if [ "$http_code" == "200" ]; then
        local size=$(stat -c%s "${output_file}" 2>/dev/null || echo 0)
        if [ "$size" -lt 200 ]; then rm -f "${output_file}"; fi
    else
        rm -f "${output_file}"
    fi
}
export -f backup_delta_curl
cat "${BACKUP_DIR}/emails.txt" | xargs -P "${PARALLEL_JOBS}" -I {} bash -c 'backup_delta_curl "$@"' _ {}

echo "[+] HOAN TAT INCREMENTAL LUC: $(date '+%Y-%m-%d %H:%M:%S')"
