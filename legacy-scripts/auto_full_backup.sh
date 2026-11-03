#!/bin/bash
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")")"
if [ "$(id -u)" -ne "$(id -u zimbra 2>/dev/null || echo -1)" ]; then
    chmod 755 "${SCRIPT_PATH}" 2>/dev/null || true
    exec su - zimbra -c "bash \"${SCRIPT_PATH}\" \"$@\""
fi
set -eo pipefail

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/mnt/backup/full/${DATE}"
LOG_FILE="${BACKUP_DIR}/backup.log"
PARALLEL_JOBS=2

find /mnt/backup/full/ -mindepth 1 -maxdepth 1 -type d -mtime +8 -exec rm -rf {} + 2>/dev/null || true
find /mnt/backup/incremental/ -mindepth 1 -maxdepth 1 -type d -mtime +8 -exec rm -rf {} + 2>/dev/null || true

mkdir -p "${BACKUP_DIR}"/{domains,admins,dl,accounts,passwords,aliases,signatures,filters,distribution_lists,mailboxes}
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[+] ==========================================================="
echo "[+] BAT DAU FULL BACKUP (Optimized zmmailbox Stable)"
echo "[+] ==========================================================="

echo "[+] --- 2/4: Backup Metadata & Accounts ---"
zmprov gad > "${BACKUP_DIR}/domains/domains.txt"
zmprov gaaa > "${BACKUP_DIR}/admins/admins.txt"
zmprov gadl > "${BACKUP_DIR}/dl/distribution_lists.txt"
zmprov -l gaa | grep '@' | grep -E -v '^(galsync\.|spam\.|ham\.|virus-quarantine\.)' | tr -d '\r' | sort > "${BACKUP_DIR}/accounts/active_accounts.txt"

while IFS= read -r dl; do
    [ -n "$dl" ] && zmprov -l gdlm "$dl" > "${BACKUP_DIR}/dl/${dl}.txt"
done < "${BACKUP_DIR}/dl/distribution_lists.txt"

while IFS= read -r acc; do
    [ -z "$acc" ] && continue
    zmprov -l ga "$acc" > "${BACKUP_DIR}/accounts/${acc}.ldif" 2>/dev/null || true
    if [ -s "${BACKUP_DIR}/accounts/${acc}.ldif" ]; then
        grep -E '^userPassword:' "${BACKUP_DIR}/accounts/${acc}.ldif" | awk '{print $2}' > "${BACKUP_DIR}/passwords/${acc}.shadow" || true
        grep -E '^zimbraMailAlias:' "${BACKUP_DIR}/accounts/${acc}.ldif" | awk '{print $2}' > "${BACKUP_DIR}/aliases/${acc}.txt" || true
        [ ! -s "${BACKUP_DIR}/aliases/${acc}.txt" ] && rm -f "${BACKUP_DIR}/aliases/${acc}.txt"
        zmprov -l gs "$acc" > "${BACKUP_DIR}/signatures/${acc}.sig" 2>/dev/null || true
        [ ! -s "${BACKUP_DIR}/signatures/${acc}.sig" ] && rm -f "${BACKUP_DIR}/signatures/${acc}.sig"
        zmprov ga "$acc" zimbraMailSieveScript 2>/dev/null | sed -e '1d' -e 's/^zimbraMailSieveScript: //g' > "${BACKUP_DIR}/filters/${acc}.filter" || true
        [ ! -s "${BACKUP_DIR}/filters/${acc}.filter" ] && rm -f "${BACKUP_DIR}/filters/${acc}.filter"
    fi
done < "${BACKUP_DIR}/accounts/active_accounts.txt"

echo "[+] --- 3/4: Backup Mailbox data (With Retry Mechanism) ---"
export BACKUP_DIR

backup_full_native() {
    local email="$1"
    local output_file="${BACKUP_DIR}/mailboxes/${email}.tgz"
    local attempt=1
    local success=0
    
    echo " -> Dang tai: ${email}"
    while [ $attempt -le 3 ]; do
        zmmailbox -z -m "${email}" getRestURL "/?fmt=tgz" > "${output_file}" 2>/dev/null
        if [ -f "${output_file}" ]; then
            local size=$(stat -c%s "${output_file}" 2>/dev/null || echo 0)
            if [ "$size" -gt 200 ]; then
                success=1
                break
            fi
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $success -eq 0 ]; then
        echo "    [FAIL] Loi trich xuat voi ${email} sau 3 lan thu"
        rm -f "${output_file}"
    fi
}
export -f backup_full_native
cat "${BACKUP_DIR}/accounts/active_accounts.txt" | xargs -P "${PARALLEL_JOBS}" -I {} bash -c 'backup_full_native "$@"' _ {}

echo "[+] --- 4/4: HOAN TAT FULL BACKUP LUC: $(date '+%Y-%m-%d %H:%M:%S') ---"
