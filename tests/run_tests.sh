#!/usr/bin/env bash
# End-to-end automated test suite for zimbra-backup v0.3.10
# Uses mock Zimbra CLI + REST + crontab + mountpoint binaries — safe to run on Windows Git Bash or Linux without root.

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$msg"
    else
        printf -- '--- Expected to find: %s\n--- Actual output:\n%s\n' "$needle" "$haystack" >&2
        fail "$msg"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$msg"
    else
        printf -- '--- Expected NOT to find: %s\n--- Actual output:\n%s\n' "$needle" "$haystack" >&2
        fail "$msg"
    fi
}

assert_file_exists() {
    [[ -f "$1" ]] && pass "$2" || fail "$2 (missing file: $1)"
}

printf '=== 1. Kiểm tra cú pháp Bash & chuẩn dòng LF ===\n'
for f in \
    "$REPO_ROOT/zimbra-backup" \
    "$REPO_ROOT/bin/zimbra-backup" \
    "$REPO_ROOT"/lib/*.sh \
    "$REPO_ROOT/packaging/preinstall.sh" \
    "$REPO_ROOT/packaging/preremove.sh" \
    "$REPO_ROOT/packaging/postremove.sh" \
    "$REPO_ROOT/packaging/zimbra-backup.logrotate" \
    "$REPO_ROOT/nfpm.yaml" \
    "$REPO_ROOT/zimbra-backup.spec" \
    "$REPO_ROOT/tests/run_tests.sh"; do
    if LC_ALL=C grep -q $'\r' "$f"; then
        fail "Phát hiện ký tự CRLF trong $f"
    fi
done
pass "Tất cả file script và cấu hình đóng gói đều giữ chuẩn LF"

bash -n "$REPO_ROOT/zimbra-backup" "$REPO_ROOT/bin/zimbra-backup" "$REPO_ROOT"/lib/*.sh "$REPO_ROOT/tests/run_tests.sh"
sh -n "$REPO_ROOT/packaging/preinstall.sh" "$REPO_ROOT/packaging/preremove.sh" "$REPO_ROOT/packaging/postremove.sh"
pass "Kiểm tra cú pháp bash -n / sh -n thành công"

# Setup isolated test workspace
TEST_TMP="$(mktemp -d "/tmp/zb_test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT

STATE_DIR="$TEST_TMP/state"
STORE_DIR="$TEST_TMP/store"
ALT_STORE_DIR="$TEST_TMP/store_alt"
UNMOUNTED_DIR="$TEST_TMP/unmounted_store"
MOCK_BIN="$TEST_TMP/mock_bin"
MOCK_DATA="$TEST_TMP/mock_data"
export MOCK_LOG="$TEST_TMP/mock_calls.log"
export MOCK_CRONTAB_FILE="$TEST_TMP/zimbra.crontab"
export MOCK_MOUNTED_FILE="$TEST_TMP/mounted_paths.txt"
export MOCK_DATA

mkdir -p "$STATE_DIR" "$STORE_DIR" "$ALT_STORE_DIR" "$UNMOUNTED_DIR" "$MOCK_BIN" "$MOCK_DATA/empty_dir" "$MOCK_DATA/mail_dir/Inbox"
: > "$MOCK_LOG"

# Pre-create realistic .tgz fixtures (including a <200-byte empty tar.gz!)
printf 'From: sender@example.com\nSubject: Full Mail\n\nHello Zimbra!\n' > "$MOCK_DATA/mail_dir/Inbox/msg1.eml"
tar -czf "$MOCK_DATA/normal_mail.tgz" -C "$MOCK_DATA/mail_dir" .
tar -czf "$MOCK_DATA/empty_mail.tgz" -C "$MOCK_DATA/empty_dir" .

mkdir -p "$MOCK_DATA/delta_dir/Inbox"
printf 'From: delta@example.com\nSubject: Delta Mail\n\nIncremental body!\n' > "$MOCK_DATA/delta_dir/Inbox/msg_delta.eml"
tar -czf "$MOCK_DATA/delta_mail.tgz" -C "$MOCK_DATA/delta_dir" .

empty_sz="$(wc -c < "$MOCK_DATA/empty_mail.tgz" | tr -d '[:space:]')"
(( empty_sz < 200 )) || fail "Fixture empty_mail.tgz cần nhỏ hơn 200 bytes (thực tế: $empty_sz)"
pass "Tạo fixture hộp thư rỗng hợp lệ (${empty_sz} bytes < 200 bytes)"

# Seed Zimbra system crontab
cat > "$MOCK_CRONTAB_FILE" <<'EOF'
# ZIMBRASTART -- DO NOT EDIT ANYTHING BETWEEN THIS LINE AND ZIMBRAEND
0 1 * * * /opt/zimbra/libexec/zmstatuslog > /dev/null 2>&1
# ZIMBRAEND -- DO NOT EDIT ANYTHING BETWEEN THIS LINE AND ZIMBRAEND
EOF

# Register mounted paths
printf '%s\n%s\n' "$STORE_DIR" "$ALT_STORE_DIR" > "$MOCK_MOUNTED_FILE"

# Mock flock when running on Windows Git Bash (where util-linux flock is not bundled)
if ! command -v flock >/dev/null 2>&1; then
    cat > "$MOCK_BIN/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN/flock"
fi

# Mock mountpoint
cat > "$MOCK_BIN/mountpoint" <<'EOF'
#!/usr/bin/env bash
target="${!#}"
grep -Fxq "$target" "$MOCK_MOUNTED_FILE"
EOF
chmod +x "$MOCK_BIN/mountpoint"

# Mock crontab
cat > "$MOCK_BIN/crontab" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
    shift 2
fi
if [[ "${1:-}" == "-l" ]]; then
    cat "$MOCK_CRONTAB_FILE"
    exit 0
fi
if [[ -n "${1:-}" && -f "${1:-}" ]]; then
    cp -- "$1" "$MOCK_CRONTAB_FILE"
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/crontab"

# Mock zmhostname
cat > "$MOCK_BIN/zmhostname" <<'EOF'
#!/usr/bin/env bash
printf 'mail.example.com\n'
EOF
chmod +x "$MOCK_BIN/zmhostname"

# Mock zmsoap
cat > "$MOCK_BIN/zmsoap" <<'EOF'
#!/usr/bin/env bash
printf 'ZMSOAP %s\n' "$*" >> "$MOCK_LOG"
cat <<XML
<AuthResponse xmlns="urn:zimbraAdmin">
  <authToken>MOCK_ADMIN_TOKEN_SECRET_999</authToken>
</AuthResponse>
XML
EOF
chmod +x "$MOCK_BIN/zmsoap"

# Mock zmprov (includes folded UTF-8 Base64 LDIF, multi-line Sieve, gsig, gdlm)
cat > "$MOCK_BIN/zmprov" <<'EOF'
#!/usr/bin/env bash
printf 'ZMPROV %s\n' "$*" >> "$MOCK_LOG"
if [[ "${1:-}" == "-f" ]]; then
    while IFS= read -r line; do
        printf 'ZMPROV_BATCH %s\n' "$line" >> "$MOCK_LOG"
    done < "$2"
    exit 0
fi
[[ "${1:-}" == "-l" ]] && shift
sub="${1:-}"
shift || true
case "$sub" in
    gs|gcf)
        # Server SSL/Admin port lookup
        printf 'zimbraAdminPort: 7071\nzimbraMailSSLPort: 8443\n'
        ;;
    gad)
        printf 'example.com\nsub.example.com\n'
        ;;
    gd)
        printf '# name %s\nzimbraDomainStatus: active\n' "${1:-example.com}"
        ;;
    gaaa)
        printf 'admin@example.com\n'
        ;;
    gadl)
        if [[ -n "${MOCK_GADL_EMPTY:-}" ]]; then
            exit 0
        fi
        printf 'all@example.com\n'
        ;;
    gdl)
        dl="${1:-all@example.com}"
        # Base64 for "Ban Thu ky" is "QmFuIFRodSBreQ=="
        cat <<LDIF
# distributionList ${dl} memberCount=2
cn: Ban Thu ky
displayName:: QmFuIFRodSBreQ==
mail: ${dl}
objectClass: zimbraDistributionList
objectClass: zimbraMailRecipient
zimbraMailStatus: enabled
zimbraHideInGal: FALSE
zimbraMailAlias: tatca@example.com
zimbraMailForwardingAddress: user1@example.com
zimbraMailForwardingAddress: empty@example.com

members
user1@example.com
empty@example.com
LDIF
        ;;
    gdlm)
        cat <<LDIF
# distributionList ${1:-all@example.com} memberCount=2
members
user1@example.com
empty@example.com
LDIF
        ;;
    sa)
        printf 'admin@example.com\nuser1@example.com\nempty@example.com\nsales@sub.example.com\nspam.xyz@example.com\ngalsync.sync@example.com\nall@example.com\n'
        if [[ -n "${MOCK_SA_EXTRA:-}" ]]; then
            for extra_acc in $MOCK_SA_EXTRA; do
                printf '%s\n' "$extra_acc"
            done
        fi
        ;;
    gaa)
        if [[ -n "${1:-}" ]]; then
            if [[ "$1" == "example.com" ]]; then
                printf 'admin@example.com\nuser1@example.com\nempty@example.com\n'
            elif [[ "$1" == "sub.example.com" ]]; then
                printf 'sales@sub.example.com\n'
            fi
        else
            printf 'admin@example.com\nuser1@example.com\nempty@example.com\nsales@sub.example.com\n'
        fi
        ;;
    ga)
        email="${1:-user1@example.com}"
        if [[ "$email" == "all@example.com" ]]; then
            echo "ERROR: account.NO_SUCH_ACCOUNT (no such account: $email)" >&2
            exit 1
        fi
        # Base64 for "Nguyễn Văn A" is "Tmd1eeG7hW4gVsSDbiBB" (folded across 2 lines per RFC 2849!)
        # Base64 for "{SSHA}secretHash123" is "e1NTSEF9c2VjcmV0SGFzaDEyMw=="
        cat <<LDIF
# name ${email}
userPassword:: e1NTSEF9c2VjcmV0SGFzaDEyMw==
displayName:: Tmd1eeG7hW4g
 VsSDbiBB
zimbraAccountStatus: active
zimbraMailQuota: 2147483648
zimbraMailAlias: alias_${email}
zimbraMailForwardingAddress: fwd_${email}
zimbraHideInGal: TRUE
zimbraPrefOutOfOfficeReplyEnabled: TRUE
zimbraMailSieveScript: require ["fileinto"];
 if header :contains "Subject" "[SPAM]" {
   fileinto "Junk";
 }
LDIF
        if [[ "$email" == "admin@example.com" ]]; then
            printf 'zimbraIsAdminAccount: TRUE\n'
        fi
        ;;
    gsig)
        email="${1:-}"
        if [[ "$email" == "user1@example.com" ]]; then
            cat <<SIG
# name Chữ ký Công ty
zimbraSignatureId: sig-001
zimbraSignatureName: Chữ ký Công ty
zimbraPrefMailSignatureHTML: <div>Trân trọng,<br>Nguyễn Văn A</div>
zimbraPrefMailSignature: Trân trọng, Nguyễn Văn A
SIG
        fi
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$MOCK_BIN/zmprov"

# Mock zmmailbox
cat > "$MOCK_BIN/zmmailbox" <<'EOF'
#!/usr/bin/env bash
printf 'ZMMAILBOX %s\n' "$*" >> "$MOCK_LOG"
if [[ -n "${MOCK_ZMMAILBOX_FAIL_204:-}" && "$*" == *"query=after:"* ]]; then
    printf 'ERROR: service.FAILURE (system failure: GET from https://mail.example.com:8443/home/... failed, status=204.  No Content)\n' >&2
    exit 2
fi
if [[ -n "${MOCK_ZMMAILBOX_FAIL_REAL:-}" ]]; then
    printf 'ERROR: service.FAILURE (system failure: connection refused)\n' >&2
    exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN/zmmailbox"

# Mock sendmail
cat > "$MOCK_BIN/sendmail" <<'EOF'
#!/usr/bin/env bash
printf 'SENDMAIL %s\n' "$*" >> "$MOCK_LOG"
cat >> "$MOCK_LOG"
printf '\n---END-SENDMAIL---\n' >> "$MOCK_LOG"
exit 0
EOF
chmod +x "$MOCK_BIN/sendmail"

# Mock curl (validates -K 0600 config usage, hides secrets from argv, serves REST tgz & imports)
cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == *"MOCK_ADMIN_TOKEN_SECRET_999"* || "$arg" == *"TG_SECRET_BOT_TOKEN"* || "$arg" == *"FTP_SECRET_PW"* ]]; then
        printf 'SECURITY_LEAK: secret exposed on curl command line: %s\n' "$arg" >&2
        exit 99
    fi
done

cfg_file=""
out_file=""
write_fmt=""
upload_file=""
pos_url=""
is_post=0
is_list_only=0
quote_cmds=()

while (( $# > 0 )); do
    case "$1" in
        -K) cfg_file="$2"; shift 2 ;;
        -o) out_file="$2"; shift 2 ;;
        -w) write_fmt="$2"; shift 2 ;;
        -X) [[ "$2" == "POST" ]] && is_post=1; shift 2 ;;
        -T|--data-binary) upload_file="$2"; is_post=1; shift 2 ;;
        -Q|--quote) quote_cmds+=("$2"); shift 2 ;;
        --list-only) is_list_only=1; shift ;;
        --data-urlencode) shift 2 ;;
        --connect-timeout|--max-time) shift 2 ;;
        -k|-s|-sS|-ks|-sk|--ftp-create-dirs|--insecure|--ssl-reqd|--show-error|--fail|--silent) shift ;;
        http://*|https://*|ftp://*|sftp://*) pos_url="$1"; shift ;;
        *) shift ;;
    esac
done

# Unauthenticated port probe (no -K required)
if [[ -z "$cfg_file" && "$pos_url" == https://127.0.0.1:* ]]; then
    [[ -n "$out_file" && "$out_file" != "/dev/null" ]] && : > "$out_file"
    [[ -n "$write_fmt" ]] && printf '200'
    exit 0
fi

[[ -n "$cfg_file" && -f "$cfg_file" ]] || { echo "Missing curl -K file" >&2; exit 2; }
url_line="$(grep '^url = ' "$cfg_file" || true)"
effective_url="${pos_url:-$url_line}"
printf 'CURL post=%d url=%s upload=%s\n' "$is_post" "$effective_url" "$upload_file" >> "$MOCK_LOG"

# Telegram endpoint
if [[ "$effective_url" == *"api.telegram.org"* ]]; then
    [[ -n "$out_file" && "$out_file" != "/dev/null" ]] && printf '{"ok":true}' > "$out_file"
    [[ -n "$write_fmt" ]] && printf '200'
    exit 0
fi

# FTP / SFTP endpoint
if [[ "$effective_url" == ftp://* || "$effective_url" == sftp://* ]]; then
    grep -q 'user = "' "$cfg_file" || { echo "Missing user credentials in FTP curl config" >&2; exit 4; }
    if ((${#quote_cmds[@]} > 0)); then
        for qc in "${quote_cmds[@]}"; do
            printf 'FTP_QUOTE: %s\n' "$qc" >> "$MOCK_LOG"
        done
    fi
    if (( is_list_only == 1 )); then
        if [[ -n "${MOCK_FTP_LIST_DATA:-}" ]]; then
            printf '%s\n' "$MOCK_FTP_LIST_DATA"
        elif [[ -n "${MOCK_FTP_LIST_FILE:-}" && -f "$MOCK_FTP_LIST_FILE" ]]; then
            cat "$MOCK_FTP_LIST_FILE"
        fi
        exit 0
    fi
    if [[ "$upload_file" == "-" ]]; then
        cat >/dev/null
    fi
    [[ -n "$out_file" && "$out_file" != "/dev/null" ]] && printf '200' > "$out_file"
    [[ -n "$write_fmt" ]] && printf '200'
    exit 0
fi

grep -q 'MOCK_ADMIN_TOKEN_SECRET_999' "$cfg_file" || { echo "Missing admin auth cookie" >&2; exit 3; }

if [[ -n "${MOCK_EXPIRE_ONCE_FILE:-}" && -f "$MOCK_EXPIRE_ONCE_FILE" && "$is_post" -eq 0 ]]; then
    rm -f -- "$MOCK_EXPIRE_ONCE_FILE"
    [[ -n "$out_file" && "$out_file" != "/dev/null" ]] && : > "$out_file"
    printf '401'
    exit 0
fi

if (( is_post == 1 )); then
    [[ -n "$out_file" && "$out_file" != "/dev/null" ]] && : > "$out_file"
    printf '200'
    exit 0
fi

# Export GET
if [[ "$effective_url" == *"query=after:"* ]]; then
    if [[ "$effective_url" == *"/empty@example.com/"* ]]; then
        : > "$out_file"
        printf '204'
        exit 0
    fi
    cp -- "$MOCK_DATA/delta_mail.tgz" "$out_file"
    printf '200'
    exit 0
else
    if [[ "$effective_url" == *"/empty@example.com/"* ]]; then
        cp -- "$MOCK_DATA/empty_mail.tgz" "$out_file"
    else
        cp -- "$MOCK_DATA/normal_mail.tgz" "$out_file"
    fi
    printf '200'
    exit 0
fi
EOF
chmod +x "$MOCK_BIN/curl"

export PATH="$MOCK_BIN:$PATH"
export ZB_STATE_DIR="$STATE_DIR"
export ZB_ZIMBRA_BIN="$MOCK_BIN"
export ZB_BIN_PATH="/usr/bin/zimbra-backup"
export ZB_SKIP_USER_CHECK=1
export ZB_SKIP_ZMSHUTIL=1
export ZB_FORCE_REST_PORT=8443

ZB_CMD="$REPO_ROOT/bin/zimbra-backup"
ver_out="$("$ZB_CMD" --version)"
assert_contains "$ver_out" "zimbra-backup 0.3.10" "Phiên bản CLI hiển thị đúng zimbra-backup 0.3.10"

printf '\n=== 2. Kiểm tra khởi tạo (init) & Chặn đường dẫn chưa mount / symlink ===\n'
status_before_init="$("$ZB_CMD" status)"
assert_contains "$status_before_init" "Default Backup Dir   : /home/backup" \
    "Thư mục sao lưu mặc định khi chưa khởi tạo là /home/backup"

"$ZB_CMD" init \
    --backup-dir "$STORE_DIR" \
    --require-mount yes \
    --disk-warn 95 \
    --disk-min-mb 10 \
    --host-label "zimbra-node-01" \
    --telegram-enabled yes \
    --telegram-token "TG_SECRET_BOT_TOKEN" \
    --telegram-chat "-100123456"

assert_file_exists "$STATE_DIR/settings.conf" "Tạo settings.conf sau lệnh init"

# Unmounted directory must fail when REQUIRE_MOUNTPOINT=yes
"$ZB_CMD" job add bad-unmounted --type full --target-dir "$UNMOUNTED_DIR" --schedule off
if "$ZB_CMD" job run bad-unmounted >/dev/null 2>&1; then
    fail "Phải chặn chạy backup vào thư mục chưa được mount khi REQUIRE_MOUNTPOINT=yes"
else
    pass "Chặn thành công thư mục đích chưa được mount riêng"
fi
"$ZB_CMD" job delete bad-unmounted --yes >/dev/null

# Symlink directory must fail (use MSYS=winsymlinks:lnk so Git Bash on Windows creates a real -L link instead of copying)
MSYS=winsymlinks:lnk ln -s "$STORE_DIR" "$TEST_TMP/symlink_store"
"$ZB_CMD" job add bad-symlink --type full --target-dir "$TEST_TMP/symlink_store" --require-mount no --schedule off
if "$ZB_CMD" job run bad-symlink >/dev/null 2>&1; then
    fail "Phải từ chối đường dẫn backup chứa symlink"
else
    pass "Chặn thành công đường dẫn backup là symlink"
fi
"$ZB_CMD" job delete bad-symlink --yes >/dev/null

printf '\n=== 3. Kiểm tra Đa Job CRUD, Chỉnh ngày tháng lịch & Đồng bộ Crontab ===\n'
"$ZB_CMD" job add full-daily \
    --name "Full hằng ngày" \
    --type full \
    --target-dir "$STORE_DIR" \
    --schedule daily --hour 1 --minute 30 \
    --keep 2 --prune-timing after --parallel 2

"$ZB_CMD" job add incr-main \
    --name "Chuỗi Incremental" \
    --type incremental \
    --target-dir "$ALT_STORE_DIR" \
    --scope domains --scope-values "example.com" \
    --schedule weekly --dow 1,3,5 --hour 2 --minute 0 \
    --full-cycle max_incr --full-cycle-value 2 \
    --keep 1 --prune-timing before --parallel 2

# Edit incr-main to monthly date-specific schedule ("chỉnh ngày tháng backup")
"$ZB_CMD" job edit incr-main \
    --schedule monthly --dom 1,15 --month 3,6,9,12 --hour 3 --minute 45

cron_content="$(cat "$MOCK_CRONTAB_FILE")"
assert_contains "$cron_content" "zmstatuslog" "Giữ nguyên vẹn khối cron hệ thống ZIMBRASTART..ZIMBRAEND"
assert_contains "$cron_content" "30 1 * * * /usr/bin/zimbra-backup job run full-daily --cron" "Sinh đúng cron hằng ngày cho full-daily"
assert_contains "$cron_content" "45 3 1,15 3,6,9,12 * /usr/bin/zimbra-backup job run incr-main --cron" "Cập nhật đúng cron ngày/tháng sau khi edit job incr-main"

"$ZB_CMD" job disable full-daily >/dev/null
cron_after_disable="$(cat "$MOCK_CRONTAB_FILE")"
assert_not_contains "$cron_after_disable" "job run full-daily" "Tắt job tự động gỡ dòng cron tương ứng"
"$ZB_CMD" job enable full-daily >/dev/null

printf '\n=== 4. Kiểm tra Full Backup, Giải mã UTF-8 LDIF, Chữ ký gsig, Hộp thư rỗng <200B & Xóa bản cũ (after) ===\n'
"$ZB_CMD" job run full-daily
sleep 1
"$ZB_CMD" job run full-daily
sleep 1
"$ZB_CMD" job run full-daily

snap_count="$(find "$STORE_DIR/full/full-daily" -mindepth 1 -maxdepth 1 -type d -name 'backup-full-*' | wc -l | tr -d '[:space:]')"
[[ "$snap_count" == "2" ]] && pass "Tách thư mục full/full-daily/backup-full-DD-MM-YYYY_HHMMSS & giữ đúng KEEP_COUNT=2 (after)" \
    || fail "Số bản Full thực tế ($snap_count) khác 2"

latest_full="$(find "$STORE_DIR/full/full-daily" -mindepth 1 -maxdepth 1 -type d -name 'backup-full-*' | LC_ALL=C sort | tail -n 1)"
[[ "${latest_full##*/}" =~ ^backup-full-[0-9]{2}-[0-9]{2}-[0-9]{4}_[0-9]{6}$ ]] \
    && pass "Đặt tên thư mục Full đúng chuẩn backup-full-ngay-thang-nam (${latest_full##*/})" \
    || fail "Tên thư mục Full sai định dạng: ${latest_full##*/}"

# Verify chronological pruning across month boundary (28-10-2026 older than 02-11-2026 despite '02' < '28')
FAKE_OLD_OCT="$STORE_DIR/full/full-daily/backup-full-28-10-2020_010000"
cp -r -- "$latest_full" "$FAKE_OLD_OCT"
sed -i 's/^created_at=.*/created_at=2020-10-28T01:00:00Z/; s/^checkpoint_to=.*/checkpoint_to=1603846800/' "$FAKE_OLD_OCT/manifest"
sleep 1
"$ZB_CMD" job run full-daily
[[ ! -d "$FAKE_OLD_OCT" ]] \
    && pass "Xóa bản cũ theo đúng thứ tự thời gian thực (28-10-2020 bị xóa trước bản tháng 11 mới hơn)" \
    || fail "Bản cũ 28-10-2020 chưa được xóa khi vượt KEEP_COUNT=2"
latest_full="$("$ZB_CMD" backup list --job full-daily | awk 'NR==3 {print $NF}')"
latest_full="$STORE_DIR/full/full-daily/${latest_full##*/}"

assert_file_exists "$latest_full/mailboxes/empty@example.com.tgz" "Không xóa nhầm hộp thư rỗng <200 bytes (empty@example.com.tgz)"
assert_file_exists "$latest_full/signatures/user1@example.com.sigs" "Xuất chữ ký người dùng bằng zmprov gsig thành công"
assert_file_exists "$latest_full/dl/all@example.com.members" "Xuất danh sách thành viên Distribution List (gdlm) thành công"

decoded_dn="$(awk -F'\t' '$1 == "displayName" { print $2 }' "$latest_full/attributes/user1@example.com.attrs" | base64 -d)"
assert_contains "$decoded_dn" "Nguyễn Văn A" "Giải mã chuẩn LDIF đa dòng + Base64 UTF-8 tiếng Việt (Nguyễn Văn A)"
sieve_txt="$(cat "$latest_full/filters/user1@example.com.sieve")"
assert_contains "$sieve_txt" 'fileinto "Junk";' "Giải mã đầy đủ bộ lọc Sieve đa dòng từ LDIF"

"$ZB_CMD" backup verify "$latest_full" >/dev/null
pass "Kiểm tra toàn vẹn SHA-256 + tar -tzf (backup verify) thành công"

leftover_tokens="$(find "$STATE_DIR/run" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
[[ "$leftover_tokens" == "0" ]] && pass "Tự động dọn sạch file chứa token tạm trong $STATE_DIR/run sau khi chạy" \
    || fail "Còn sót file token trong $STATE_DIR/run"

printf '\n=== 5. Kiểm tra Chuỗi Incremental (000_backup-full -> 001_backup-incremental -> 002_backup-incremental) ===\n'
"$ZB_CMD" job run incr-main # Chain 1: 000_backup-full
sleep 1
"$ZB_CMD" job run incr-main # Chain 1: 001_backup-incremental
sleep 1
"$ZB_CMD" job run incr-main # Chain 1: 002_backup-incremental

chain1_dir="$(find "$ALT_STORE_DIR/incremental/incr-main" -mindepth 1 -maxdepth 1 -type d -name 'chain-*' | head -n 1)"
step_count="$(find "$chain1_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')"
[[ "$step_count" == "3" ]] && pass "Tách thư mục incremental/incr-main/chain-* gồm 1 bản Full gốc + 2 bản Incremental" \
    || fail "Số bước trong chuỗi 1 ($step_count) khác 3"

incr2_dir="$(find "$chain1_dir" -mindepth 1 -maxdepth 1 -type d -name '002_backup-incremental-*' | head -n 1)"
[[ "${incr2_dir##*/}" =~ ^002_backup-incremental-[0-9]{2}-[0-9]{2}-[0-9]{4}_[0-9]{6}$ ]] \
    && pass "Đặt tên bước Incremental đúng chuẩn 002_backup-incremental-ngay-thang-nam (${incr2_dir##*/})" \
    || fail "Tên thư mục Incremental sai định dạng: ${incr2_dir##*/}"
assert_file_exists "$incr2_dir/mailboxes/empty@example.com.empty" "Ghi nhận trạng thái empty-delta cho hộp thư không phát sinh mail mới"

# Test Restore from Incremental step BEFORE rolling over chain 1
printf '\n=== 6. Kiểm tra Restore: Dry-run, Ghép chuỗi Full+Incr, Đổi email đích & Subfolder ===\n'
: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$incr2_dir" --users "user1@example.com" --mode reset --dry-run
dry_calls="$(grep -c 'ZMPROV \|CURL post=1' "$MOCK_LOG" || true)"
[[ "$dry_calls" == "0" ]] && pass "Chế độ Restore --dry-run không thực hiện bất kỳ lệnh ghi nào vào Zimbra" \
    || fail "Dry-run đã gọi lệnh ghi ($dry_calls lệnh)"

: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$incr2_dir" --users "user1@example.com" --mode reset --yes
restore_log="$(cat "$MOCK_LOG")"
assert_contains "$restore_log" "ZMPROV ma user1@example.com userPassword {SSHA}secretHash123" "Khôi phục đúng hash mật khẩu gốc của user"
assert_contains "$restore_log" "displayName Nguyễn Văn A" "Khôi phục đúng displayName tiếng Việt có dấu"
assert_contains "$restore_log" "ZMPROV csig user1@example.com Chữ ký Công ty zimbraPrefMailSignatureHTML" "Khôi phục đồng thời cả chữ ký HTML và chữ ký Text trong 1 lệnh zmprov csig"
assert_contains "$restore_log" "zimbraPrefMailSignature Trân trọng, Nguyễn Văn A" "Bảo toàn phần chữ ký văn bản thuần (zimbraPrefMailSignature) bên cạnh HTML"
assert_not_contains "$restore_log" "ZMPROV -l ga " "Cache danh sách LDAP giúp Restore không phải gọi zmprov ga từng user"
assert_contains "$restore_log" "resolve=reset" "Bước 1 (000_full) dùng resolve=reset khi chọn chế độ reset"
assert_contains "$restore_log" "resolve=modify" "Các bước Incremental (001_incr, 002_incr) tự chuyển sang resolve=modify để bồi đắp dữ liệu"

# Cross-account subfolder restore (only mailbox)
: > "$MOCK_LOG"
"$ZB_CMD" restore \
    --from "$latest_full" \
    --users "user1@example.com" \
    --target-user "manager@example.com" \
    --only mailbox \
    --mode subfolder --subfolder-name "BanGiao_User1" \
    --yes
sub_log="$(cat "$MOCK_LOG")"
assert_contains "$sub_log" "/service/home/manager@example.com/BanGiao_User1?fmt=tgz&resolve=skip" \
    "Khôi phục hộp thư sang tài khoản đích khác vào thư mục riêng (/BanGiao_User1)"
assert_not_contains "$sub_log" "ZMPROV ma manager@example.com userPassword" \
    "Chế độ --only mailbox giữ nguyên mật khẩu hiện tại của tài khoản đích"

# Now run 4th time on incr-main (max_incr=2 reached -> opens Chain 2, PRUNE_TIMING=before with KEEP_COUNT=1 deletes Chain 1)
sleep 1
"$ZB_CMD" job run incr-main
chains_remaining="$(find "$ALT_STORE_DIR/incremental/incr-main" -mindepth 1 -maxdepth 1 -type d -name 'chain-*' | wc -l | tr -d '[:space:]')"
[[ "$chains_remaining" == "1" ]] && pass "Chu kỳ tạo chuỗi Full mới + xóa chuỗi cũ theo KEEP_COUNT=1 (before) hoạt động chính xác" \
    || fail "Số chuỗi còn lại ($chains_remaining) khác 1"

# Ad-hoc user backup + pending cleanup + job-only discovery isolation + legacy directory restore
printf '\n=== 7. Kiểm tra Tách thư mục account/, Đặt tên backup-<email>-ngay-thang-nam & Thư mục Restore riêng ===\n'
"$ZB_CMD" backup user "user1@example.com"
single_adhoc="$(find "$STORE_DIR/account" -mindepth 1 -maxdepth 1 -type d -name 'backup-user1@example.com-*' | head -n 1)"
[[ -n "$single_adhoc" && "${single_adhoc##*/}" =~ ^backup-user1@example\.com-[0-9]{2}-[0-9]{2}-[0-9]{4}_[0-9]{6}$ ]] \
    && pass "Sao lưu lẻ 1 email lưu vào account/backup-user1@example.com-ngay-thang-nam (${single_adhoc##*/})" \
    || fail "Tên thư mục sao lưu lẻ 1 email không đúng: ${single_adhoc:-none}"

"$ZB_CMD" backup user "user1@example.com,empty@example.com"
multi_adhoc="$(find "$STORE_DIR/account" -mindepth 1 -maxdepth 1 -type d -name 'backup-user1@example.com+1more-*' | head -n 1)"
[[ -n "$multi_adhoc" ]] && pass "Sao lưu lẻ nhiều email lưu vào account/backup-<email>+<N>more-ngay-thang-nam" \
    || fail "Không tìm thấy bản sao lưu lẻ nhiều email trong $STORE_DIR/account"

# Create a stray unconfigured backup folder inside STORE_DIR to verify default discovery ignores non-job dirs
STRAY_SNAP="$STORE_DIR/unconfigured-folder/snapshots/full_20990101_000000"
mkdir -p "$STRAY_SNAP"/{accounts,mailboxes}
printf 'user1@example.com\n' > "$STRAY_SNAP/accounts/active_accounts.txt"
cp -- "$MOCK_DATA/normal_mail.tgz" "$STRAY_SNAP/mailboxes/user1@example.com.tgz"

default_cat="$("$ZB_CMD" backup list)"
assert_contains "$default_cat" "full-daily" "Danh sách mặc định lấy đúng thư mục của Job full-daily"
assert_contains "$default_cat" "incr-main" "Danh sách mặc định lấy đúng thư mục của Job incr-main"
assert_not_contains "$default_cat" "account/backup-" "Danh sách Job mặc định KHÔNG quét lẫn thư mục sao lưu lẻ account/"
assert_not_contains "$default_cat" "20990101_000000" "Danh sách Job mặc định KHÔNG quét tràn lan thư mục lạ ngoài Job trên cùng ổ đĩa"

single_job_cat="$("$ZB_CMD" backup list --job full-daily)"
assert_contains "$single_job_cat" "full-daily" "Lọc theo --job full-daily hiển thị đúng các bản sao lưu của Job đó"
assert_not_contains "$single_job_cat" "incr-main" "Lọc theo --job full-daily không lẫn bản sao lưu của Job khác"

adhoc_cat="$("$ZB_CMD" backup list --dir "$STORE_DIR/account")"
assert_contains "$adhoc_cat" "backup-user1@example.com-" "Quét riêng --dir account/ nhận diện đúng bản sao lưu lẻ theo email"

mkdir -p "$STORE_DIR/full/full-daily/.pending.99999"
"$ZB_CMD" backup clean-pending >/dev/null
[[ ! -d "$STORE_DIR/full/full-daily/.pending.99999" ]] && pass "Dọn sạch thư mục tạm .pending.* bị dở dang" \
    || fail "Chưa xóa được thư mục .pending.99999"

# Legacy auto_full_backup.sh layout compatibility (including nested /backup/full/<timestamp>) & CUSTOM_RESTORE_DIR
LEGACY_DIR="$TEST_TMP/legacy_root/full/20260101_020000"
mkdir -p "$LEGACY_DIR"/{domains,accounts,userpass,alias,signatures,filter,mailboxes}
printf 'example.com\n' > "$LEGACY_DIR/domains/domains.txt"
printf 'legacy@example.com\n' > "$LEGACY_DIR/accounts/active_accounts.txt"
printf 'userPassword: {SSHA}legacyHash\n' > "$LEGACY_DIR/userpass/legacy@example.com.shadow"
cp -- "$MOCK_DATA/normal_mail.tgz" "$LEGACY_DIR/mailboxes/legacy@example.com.tgz"

"$ZB_CMD" init --backup-dir "$STORE_DIR" --restore-dir "$TEST_TMP/legacy_root" --require-mount no >/dev/null
assert_contains "$(cat "$STATE_DIR/settings.conf")" "CUSTOM_RESTORE_DIR=$TEST_TMP/legacy_root" \
    "Lưu cấu hình thư mục Restore riêng (CUSTOM_RESTORE_DIR) độc lập với DEFAULT_BACKUP_DIR"

cat_out="$("$ZB_CMD" backup list --dir "$TEST_TMP/legacy_root")"
assert_contains "$cat_out" "legacy-full" "Quét đệ quy từ đường dẫn bất kỳ người dùng nhập vào tự động tìm thấy thư mục con bên trong"
cat_direct_out="$("$ZB_CMD" backup list --dir "$TEST_TMP/legacy_root/full")"
assert_contains "$cat_direct_out" "legacy-full" "Gõ trực tiếp thư mục cấp con vẫn nhận diện bình thường"

# Arbitrary user-supplied path & arbitrary non-numeric folder names (no hardcoded /backup or /full)
ARB_DIR="$TEST_TMP/duong_dan_tuy_chon/server_cu/kho_thang_10/ban_sao_luu_zimbra"
mkdir -p "$ARB_DIR"/{domains,accounts,mailboxes}
printf 'corp.vn\n' > "$ARB_DIR/domains/domains.txt"
printf 'vip@corp.vn\n' > "$ARB_DIR/accounts/active_accounts.txt"
cp -- "$MOCK_DATA/normal_mail.tgz" "$ARB_DIR/mailboxes/vip@corp.vn.tgz"
arb_cat="$("$ZB_CMD" backup list --dir "$TEST_TMP/duong_dan_tuy_chon")"
assert_contains "$arb_cat" "legacy/ban_sao_luu_zimbra" \
    "Tự động dò nhiều cấp từ bất kỳ đường dẫn nào người dùng cung cấp (không phụ thuộc tên /backup hay /full)"

: > "$MOCK_LOG"
"$ZB_CMD" restore --dir "$TEST_TMP/legacy_root" --from 1 --users "legacy@example.com" --yes
assert_contains "$(cat "$MOCK_LOG")" "ZMPROV ma legacy@example.com userPassword {SSHA}legacyHash" \
    "Khôi phục thành công mật khẩu & hộp thư từ thư mục định dạng cũ (userpass/)"

printf '\n=== 8. Kiểm tra chuẩn 100%% Pure 7-bit ASCII, LF line-endings & mặc định Incremental KEEP_COUNT=2 ===\n'
add_out="$("$ZB_CMD" job add incr-defaults --type incremental --schedule daily --hour 2 --minute 15)"
assert_contains "$add_out" "Created job 'incr-defaults'" \
    "zb_cron_sync không làm ghi đè biến toàn cục JOB_ID khi tạo Job mới"
assert_contains "$(cat "$STATE_DIR/jobs/incr-defaults.conf")" "KEEP_COUNT=2" \
    "Job Incremental mới mặc định KEEP_COUNT=2 chuỗi (~2 tuần) khi không truyền --keep"
assert_contains "$(cat "$STATE_DIR/jobs/incr-defaults.conf")" "PARALLEL_JOBS=4" \
    "Job Incremental mới mặc định PARALLEL_JOBS=4 luồng khi không truyền --parallel"

# Test interactive 5-step Job Creation Wizard (Step 3 Backup Storage Directory + auto-mkdir + trailing slash normalization)
TUI_CUSTOM_STORE="$TEST_TMP/tui_custom_store"
(
    export ZB_LIB_DIR="$REPO_ROOT/lib"
    . "$REPO_ROOT/lib/common.sh"
    . "$REPO_ROOT/lib/notify.sh"
    . "$REPO_ROOT/lib/zimbra_api.sh"
    . "$REPO_ROOT/lib/jobs.sh"
    . "$REPO_ROOT/lib/backup.sh"
    . "$REPO_ROOT/lib/restore.sh"
    . "$REPO_ROOT/lib/tui.sh"
    zb_tui_job_create <<EOF >/dev/null
backup-1
1
${TUI_CUSTOM_STORE}/
n
y
2
6
02:00
1
n

EOF
)
assert_file_exists "$STATE_DIR/jobs/backup-1.conf" "TUI Wizard 5 bước tạo thành công file cấu hình backup-1.conf"
assert_contains "$(cat "$STATE_DIR/jobs/backup-1.conf")" "TARGET_DIR=$TUI_CUSTOM_STORE" \
    "TUI Wizard Bước 3 lưu đúng đường dẫn nơi lưu trữ TARGET_DIR (tự chuẩn hóa dấu '/' cuối)"
assert_contains "$(cat "$STATE_DIR/jobs/backup-1.conf")" "JOB_REQUIRE_MOUNT=no" \
    "TUI Wizard Bước 3 lưu đúng cấu hình mount riêng JOB_REQUIRE_MOUNT=no"
[[ -d "$TUI_CUSTOM_STORE" ]] && pass "TUI Wizard tự động tạo thư mục lưu trữ mới khi chưa tồn tại" \
    || fail "TUI Wizard chưa tạo thư mục $TUI_CUSTOM_STORE"
"$ZB_CMD" job run backup-1 >/dev/null
tui_snap="$(find "$TUI_CUSTOM_STORE/full/backup-1" -mindepth 1 -maxdepth 1 -type d -name 'backup-full-*' | head -n 1)"
[[ -n "$tui_snap" ]] && pass "Job tạo từ TUI Wizard chạy lưu đúng vào $TUI_CUSTOM_STORE/full/backup-1/backup-full-*" \
    || fail "Không tìm thấy bản backup trong $TUI_CUSTOM_STORE/full/backup-1"

# Test that running TUI with uninitialized state creates settings.conf and goes straight to Main Menu
TUI_TEST_STATE="$TEST_TMP/tui_test_state"
mkdir -p "$TUI_TEST_STATE"
(
    export ZB_STATE_DIR="$TUI_TEST_STATE"
    export ZB_LIB_DIR="$REPO_ROOT/lib"
    . "$REPO_ROOT/lib/common.sh"
    . "$REPO_ROOT/lib/notify.sh"
    . "$REPO_ROOT/lib/zimbra_api.sh"
    . "$REPO_ROOT/lib/jobs.sh"
    . "$REPO_ROOT/lib/backup.sh"
    . "$REPO_ROOT/lib/restore.sh"
    . "$REPO_ROOT/lib/tui.sh"
    zb_tui_main <<< "0" >/dev/null
)
assert_file_exists "$TUI_TEST_STATE/settings.conf" "TUI mở lần đầu tự động khởi tạo settings.conf và vào thẳng Main Menu"

printf '\n=== 9. Kiểm tra gỡ cài đặt sạch tự động (preremove / postremove) & An toàn tuyệt đối cho Zimbra ===\n'
MOCK_LOGROTATE_DIR="$TEST_TMP/logrotate.d"
mkdir -p "$MOCK_LOGROTATE_DIR"
printf '# modified logrotate\n' > "$MOCK_LOGROTATE_DIR/zimbra-backup.rpmsave"

# 9a. Chế độ nâng cấp gói RPM ($1 = 1) -> tuyệt đối giữ nguyên cấu hình, Job và Crontab
ZB_TEST_UNINSTALL=1 ZB_LOGROTATE_DIR="$MOCK_LOGROTATE_DIR" sh "$REPO_ROOT/packaging/preremove.sh" 1
ZB_TEST_UNINSTALL=1 ZB_LOGROTATE_DIR="$MOCK_LOGROTATE_DIR" sh "$REPO_ROOT/packaging/postremove.sh" 1
assert_file_exists "$STATE_DIR/settings.conf" "Khi nâng cấp RPM (\$1=1): giữ nguyên settings.conf"
assert_file_exists "$STATE_DIR/jobs/backup-1.conf" "Khi nâng cấp RPM (\$1=1): giữ nguyên cấu hình các Job"
assert_contains "$(cat "$MOCK_CRONTAB_FILE")" "# BEGIN zimbra-backup" "Khi nâng cấp RPM (\$1=1): giữ nguyên lịch Crontab"

# 9b. Chế độ gỡ cài đặt hoàn toàn ($1 = 0) -> gỡ sạch cron zimbra-backup & state, KHÔNG chạm Zimbra & dữ liệu backup
mock_calls_before="$(wc -l < "$MOCK_LOG" | tr -d '[:space:]')"
ZB_TEST_UNINSTALL=1 ZB_LOGROTATE_DIR="$MOCK_LOGROTATE_DIR" sh "$REPO_ROOT/packaging/preremove.sh" 0
ZB_TEST_UNINSTALL=1 ZB_LOGROTATE_DIR="$MOCK_LOGROTATE_DIR" sh "$REPO_ROOT/packaging/postremove.sh" 0 >/dev/null
mock_calls_after="$(wc -l < "$MOCK_LOG" | tr -d '[:space:]')"

[[ "$mock_calls_before" == "$mock_calls_after" ]] \
    && pass "Gỡ gói hoàn toàn KHÔNG gọi bất kỳ lệnh nào tác động tới dịch vụ Zimbra (zmprov/zmmailbox/zmsoap)" \
    || fail "Phát hiện lệnh gọi Zimbra ngoài ý muốn trong quá trình gỡ gói"

cron_after_uninstall="$(cat "$MOCK_CRONTAB_FILE")"
assert_not_contains "$cron_after_uninstall" "# BEGIN zimbra-backup" "Gỡ gói (\$1=0) xóa sạch khối # BEGIN zimbra-backup khỏi crontab"
assert_not_contains "$cron_after_uninstall" "zimbra-backup job run" "Gỡ gói (\$1=0) xóa sạch mọi dòng lệnh lập lịch zimbra-backup"
assert_contains "$cron_after_uninstall" "# ZIMBRASTART -- DO NOT EDIT ANYTHING BETWEEN THIS LINE AND ZIMBRAEND" \
    "Gỡ gói (\$1=0) bảo toàn nguyên vẹn 100% khối # ZIMBRASTART của hệ thống email Zimbra"
assert_contains "$cron_after_uninstall" "0 1 * * * /opt/zimbra/libexec/zmstatuslog > /dev/null 2>&1" \
    "Gỡ gói (\$1=0) bảo toàn nguyên vẹn tác vụ định kỳ gốc của Zimbra (/opt/zimbra/libexec/zmstatuslog)"

[[ ! -e "$STATE_DIR" ]] && pass "Gỡ gói (\$1=0) dọn sạch hoàn toàn thư mục cấu hình & log ($STATE_DIR)" \
    || fail "Thư mục cấu hình $STATE_DIR vẫn còn sót sau khi gỡ"
[[ ! -e "$MOCK_LOGROTATE_DIR/zimbra-backup.rpmsave" ]] && pass "Gỡ gói (\$1=0) dọn sạch file rác logrotate .rpmsave" \
    || fail "File zimbra-backup.rpmsave vẫn còn sót"
[[ -d "$tui_snap" && -d "$STORE_DIR/account" ]] \
    && pass "Gỡ gói (\$1=0) giữ nguyên an toàn tuyệt đối toàn bộ dữ liệu các bản backup đã sao lưu" \
    || fail "Dữ liệu backup bị ảnh hưởng khi gỡ gói"

printf '\n=== 10. Kiểm tra hồi quy bảo vệ hệ thống v0.3.1 (HTTP 401 refresh, Read-only LDIF, Subfolder Guard, Cron Repair, Locked Accounts) ===\n'
mkdir -p "$STATE_DIR"
"$ZB_CMD" init --backup-dir "$STORE_DIR" --require-mount yes --disk-warn 95 --disk-min-mb 10 >/dev/null

# 10a. Ad-hoc backup --require-mount override
if "$ZB_CMD" backup user "user1@example.com" --dir "$UNMOUNTED_DIR" >/dev/null 2>&1; then
    fail "Phải chặn backup user vào thư mục chưa mount khi REQUIRE_MOUNTPOINT=yes và không truyền --require-mount no"
else
    pass "Chặn đúng backup user vào thư mục chưa mount khi mặc định REQUIRE_MOUNTPOINT=yes"
fi
"$ZB_CMD" backup user "user1@example.com" --dir "$UNMOUNTED_DIR" --require-mount no >/dev/null
pass "Cho phép ghi đè --require-mount no khi sao lưu lẻ account vào thư mục cục bộ"

# 10b. HTTP 401 expired admin token auto-refresh inside worker without falling back to heavy zmmailbox JVM
: > "$MOCK_LOG"
EXPIRE_MARKER="$TEST_TMP/expire_401.once"
printf '1\n' > "$EXPIRE_MARKER"
MOCK_EXPIRE_ONCE_FILE="$EXPIRE_MARKER" "$ZB_CMD" backup user "user1@example.com" --dir "$UNMOUNTED_DIR" --require-mount no >/dev/null
zmsoap_401_cnt="$(grep -c '^ZMSOAP ' "$MOCK_LOG" || true)"
zmmbox_401_cnt="$(grep -c '^ZMMAILBOX ' "$MOCK_LOG" || true)"
(( zmsoap_401_cnt >= 2 )) && [[ "$zmmbox_401_cnt" == "0" ]] \
    && pass "Worker tự xin lại ZM_ADMIN_AUTH_TOKEN khi gặp HTTP 401 mà không phải rơi xuống chạy JVM zmmailbox nặng" \
    || fail "Xử lý HTTP 401 chưa chuẩn (zmsoap=$zmsoap_401_cnt, zmmailbox=$zmmbox_401_cnt)"
leftover_401="$(find "$STATE_DIR/run" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
[[ "$leftover_401" == "0" ]] && pass "Dọn sạch hoàn toàn file token tạm của worker sau khi refresh HTTP 401" \
    || fail "Còn sót file tạm trong $STATE_DIR/run sau khi xử lý HTTP 401"

# 10c. Non-active accounts (locked/maintenance/closed) included while system/galsync/spam accounts excluded
MOCK_SA_EXTRA="locked_user@example.com" "$ZB_CMD" job add sec10-full --type full --target-dir "$STORE_DIR" --schedule daily --hour 4 --minute 0 >/dev/null
MOCK_SA_EXTRA="locked_user@example.com" "$ZB_CMD" job run sec10-full >/dev/null
sec10_snap="$(find "$STORE_DIR/full/sec10-full" -mindepth 1 -maxdepth 1 -type d -name 'backup-full-*' | head -n 1)"
sec10_accs="$(cat "$sec10_snap/accounts/active_accounts.txt")"
assert_contains "$sec10_accs" "locked_user@example.com" "Sao lưu đầy đủ cả tài khoản người dùng đang ở trạng thái locked/maintenance/closed"
assert_not_contains "$sec10_accs" "spam.xyz@example.com" "Loại bỏ chính xác tài khoản hệ thống spam.*"
assert_not_contains "$sec10_accs" "galsync.sync@example.com" "Loại bỏ chính xác tài khoản hệ thống galsync.*"

# 10d. Reject path traversal / query injection in --subfolder-name before touching Zimbra
: > "$MOCK_LOG"
if "$ZB_CMD" restore --from "$sec10_snap" --users "user1@example.com" --mode subfolder --subfolder-name "../Evil&resolve=reset" --yes >/dev/null 2>&1; then
    fail "Phải từ chối --subfolder-name chứa '..' hoặc ký tự chèn query URL"
else
    pass "Chặn thành công --subfolder-name chứa '..' / ký tự chèn query URL"
fi
inj_writes="$(grep -c 'ZMPROV \|CURL post=1' "$MOCK_LOG" || true)"
[[ "$inj_writes" == "0" ]] && pass "Từ chối --subfolder-name không hợp lệ ngay từ đầu trước khi chạm vào Zimbra" \
    || fail "Đã phát sinh lệnh gọi Zimbra khi --subfolder-name không hợp lệ"

# 10e. Legacy .ldif restore never writes into snapshot directory (Read-Only NFS safe)
RO_SNAP="$TEST_TMP/ro_legacy_snap/20260102_030000"
mkdir -p "$RO_SNAP"/{domains,accounts,mailboxes}
printf 'example.com\n' > "$RO_SNAP/domains/domains.txt"
printf 'ro_user@example.com\n' > "$RO_SNAP/accounts/active_accounts.txt"
cat > "$RO_SNAP/accounts/ro_user@example.com.ldif" <<'EOF'
# name ro_user@example.com
userPassword:: e1NTSEF9cm9IYXNoNzg5
displayName:: VHLhuqduIFRo4buLIEI=
zimbraMailQuota: 1073741824
zimbraMailAlias: ro_alias@example.com
zimbraMailSieveScript: require ["fileinto"];
EOF
cp -- "$MOCK_DATA/normal_mail.tgz" "$RO_SNAP/mailboxes/ro_user@example.com.tgz"
chmod 555 "$RO_SNAP/accounts" "$RO_SNAP/mailboxes" "$RO_SNAP/domains" "$RO_SNAP"
: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$RO_SNAP" --users "ro_user@example.com" --yes >/dev/null
chmod 755 "$RO_SNAP" "$RO_SNAP/accounts" "$RO_SNAP/mailboxes" "$RO_SNAP/domains"
[[ ! -e "$RO_SNAP/attributes" && ! -e "$RO_SNAP/passwords" ]] \
    && pass "Khôi phục từ bản sao lưu LDIF đời cũ hoàn toàn Read-Only (không ghi file tạm vào thư mục nguồn)" \
    || fail "Đã ghi thêm thư mục phụ vào trong thư mục nguồn Read-Only"
ro_log="$(cat "$MOCK_LOG")"
assert_contains "$ro_log" "ZMPROV ma ro_user@example.com userPassword {SSHA}roHash789" \
    "Giải mã và khôi phục đúng mật khẩu từ file .ldif đời cũ trong vùng nhớ tạm an toàn"
assert_contains "$ro_log" "ZMPROV aaa ro_user@example.com ro_alias@example.com" \
    "Giải mã và khôi phục đúng Alias từ file .ldif đời cũ"

# 10f. Unbalanced crontab marker recovery preserves Zimbra system cron 100%
cat > "$MOCK_CRONTAB_FILE" <<'EOF'
# BEGIN zimbra-backup (managed automatically - do not edit inside this block)
0 4 * * * /usr/bin/zimbra-backup job run orphan --cron >/dev/null 2>&1
# ZIMBRASTART -- DO NOT EDIT ANYTHING BETWEEN THIS LINE AND ZIMBRAEND
0 1 * * * /opt/zimbra/libexec/zmstatuslog > /dev/null 2>&1
# ZIMBRAEND -- DO NOT EDIT ANYTHING BETWEEN THIS LINE AND ZIMBRAEND
EOF
"$ZB_CMD" cron sync >/dev/null 2>&1
repaired_cron="$(cat "$MOCK_CRONTAB_FILE")"
assert_contains "$repaired_cron" "0 1 * * * /opt/zimbra/libexec/zmstatuslog > /dev/null 2>&1" \
    "Khi crontab bị mất dòng đóng # END, cron sync tự phục hồi an toàn mà KHÔNG làm mất cron hệ thống Zimbra"
assert_not_contains "$repaired_cron" "job run orphan" \
    "Tự dọn sạch dòng job mồ côi khi sửa lại khối crontab bị lệch thẻ đóng"
assert_contains "$repaired_cron" "# END zimbra-backup" \
    "Tái lập đầy đủ cặp thẻ # BEGIN / # END zimbra-backup chuẩn xác"

printf '\n=== 11. Sao lưu & Khôi phục toàn diện Nhóm / Distribution List (Attributes, Aliases, Members) ===\n'

# 11a. Distribution List artifacts exported completely with attributes, aliases, members
assert_file_exists "$latest_full/dl/distribution_lists.txt" "Tạo file danh sách Distribution List (dl/distribution_lists.txt)"
assert_file_exists "$latest_full/dl/all@example.com.attrs" "Trích xuất đầy đủ thuộc tính Distribution List (displayName, status, hideInGal)"
assert_file_exists "$latest_full/dl/all@example.com.aliases" "Trích xuất Alias của Distribution List (tatca@example.com)"
assert_file_exists "$latest_full/dl/all@example.com.members" "Trích xuất danh sách thành viên Distribution List (user1, empty)"

dl_attrs="$(cat "$latest_full/dl/all@example.com.attrs")"
assert_contains "$dl_attrs" "displayName" "File thuộc tính DL chứa trường displayName"
decoded_dl_dn="$(awk -F'\t' '$1 == "displayName" { print $2 }' "$latest_full/dl/all@example.com.attrs" | base64 -d)"
assert_contains "$decoded_dl_dn" "Ban Thu ky" "Bảo toàn nguyên vẹn displayName tiếng Việt UTF-8 của Distribution List (Ban Thu ky)"
decoded_status="$(awk -F'\t' '$1 == "zimbraMailStatus" { print $2 }' "$latest_full/dl/all@example.com.attrs" | base64 -d)"
assert_contains "$decoded_status" "enabled" "Bảo toàn trạng thái zimbraMailStatus của DL (enabled)"
decoded_gal="$(awk -F'\t' '$1 == "zimbraHideInGal" { print $2 }' "$latest_full/dl/all@example.com.attrs" | base64 -d)"
assert_contains "$decoded_gal" "FALSE" "Bảo toàn thiết lập ẩn GAL zimbraHideInGal của DL (FALSE)"

dl_alias="$(cat "$latest_full/dl/all@example.com.aliases")"
assert_contains "$dl_alias" "tatca@example.com" "Bảo toàn alias tatca@example.com của Distribution List"

dl_members="$(cat "$latest_full/dl/all@example.com.members")"
assert_contains "$dl_members" "user1@example.com" "Thành viên DL chứa user1@example.com"
assert_contains "$dl_members" "empty@example.com" "Thành viên DL chứa empty@example.com"

# 11b. Distribution list strictly isolated from user accounts (never treated as mailbox)
assert_not_contains "$(cat "$latest_full/accounts/active_accounts.txt")" "all@example.com" \
    "Distribution List (all@example.com) được loại bỏ hoàn toàn khỏi active_accounts.txt dù LDAP trả về"
[[ ! -f "$latest_full/mailboxes/all@example.com.tgz" ]] \
    && pass "Không bao giờ cố xuất mailbox .tgz cho Distribution List" \
    || fail "Đã tạo nhầm file mailbox cho Distribution List"
manifest_txt="$(cat "$latest_full/manifest")"
assert_contains "$manifest_txt" "dl_count=1" "Manifest ghi nhận chính xác số lượng Distribution List (dl_count=1)"

# 11c. Full restore restores Distribution List with 2-pass workflow (cdl -> mdl -> adla -> adlm)
: > "$MOCK_LOG"
MOCK_GADL_EMPTY=1 "$ZB_CMD" restore --from "$latest_full" --all --yes >/dev/null
full_rest_log="$(cat "$MOCK_LOG")"
assert_contains "$full_rest_log" "ZMPROV cdl all@example.com" "Khôi phục nhóm: Tạo Distribution List bằng zmprov cdl khi chưa tồn tại"
assert_contains "$full_rest_log" "ZMPROV mdl all@example.com" "Khôi phục nhóm: Cập nhật đầy đủ thuộc tính bằng zmprov mdl"
assert_contains "$full_rest_log" "Ban Thu ky" "Khôi phục nhóm: Nạp đúng displayName của DL qua zmprov mdl"
assert_contains "$full_rest_log" "ZMPROV adla all@example.com tatca@example.com" "Khôi phục nhóm: Thêm Alias cho DL bằng zmprov adla"
assert_contains "$full_rest_log" "ZMPROV adlm all@example.com user1@example.com" "Khôi phục nhóm: Thêm thành viên #1 bằng zmprov adlm"
assert_contains "$full_rest_log" "ZMPROV adlm all@example.com empty@example.com" "Khôi phục nhóm: Thêm thành viên #2 bằng zmprov adlm"
assert_not_contains "$full_rest_log" "ZMPROV adlm all@example.com #" "Khôi phục nhóm: Lọc sạch dòng chú thích # không nạp nhầm vào thành viên"
assert_not_contains "$full_rest_log" "ZMPROV ca all@example.com" "Khôi phục: Tuyệt đối không gọi zmprov ca (tạo account) cho DL"
assert_not_contains "$full_rest_log" "all@example.com?fmt=tgz" "Khôi phục: Tuyệt đối không gọi REST import mailbox cho DL"

# 11d. Selective restore for Distribution List via --users "all@example.com"
: > "$MOCK_LOG"
MOCK_GADL_EMPTY=1 "$ZB_CMD" restore --from "$latest_full" --users "all@example.com" --yes >/dev/null
sel_dl_log="$(cat "$MOCK_LOG")"
assert_contains "$sel_dl_log" "ZMPROV cdl all@example.com" "Khôi phục đích danh DL: Tạo DL bằng zmprov cdl"
assert_contains "$sel_dl_log" "ZMPROV adlm all@example.com" "Khôi phục đích danh DL: Nạp thành viên bằng zmprov adlm"
assert_not_contains "$sel_dl_log" "ZMPROV ca user1@example.com" "Khôi phục đích danh DL: Không khôi phục tài khoản người dùng khác"

# 11e. Existing Distribution List on target skips cdl but updates attributes and members
: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --users "all@example.com" --yes >/dev/null
exist_dl_log="$(cat "$MOCK_LOG")"
assert_not_contains "$exist_dl_log" "ZMPROV cdl all@example.com" "Bỏ qua zmprov cdl khi Distribution List đã tồn tại sẵn trên server đích"
assert_contains "$exist_dl_log" "ZMPROV mdl all@example.com" "Vẫn cập nhật đầy đủ thuộc tính zmprov mdl khi DL đã tồn tại"
assert_contains "$exist_dl_log" "ZMPROV adlm all@example.com" "Vẫn cập nhật thành viên zmprov adlm khi DL đã tồn tại"

printf '\n=== 12. Kiểm tra bảo toàn quyền Administrator & Thuộc tính mở rộng v0.3.4 ===\n'

# 12a. Verify extended attributes in backup snapshot
assert_file_exists "$latest_full/admins/admins.txt" "Tạo file danh sách Administrator (admins/admins.txt)"
assert_contains "$(cat "$latest_full/admins/admins.txt")" "admin@example.com" "admins/admins.txt ghi nhận đúng admin@example.com"

user1_attrs="$latest_full/attributes/user1@example.com.attrs"
assert_file_exists "$user1_attrs" "Tạo file thuộc tính user1@example.com.attrs"

decoded_fwd="$(awk -F'\t' '$1 == "zimbraMailForwardingAddress" { print $2 }' "$user1_attrs" | base64 -d 2>/dev/null || true)"
assert_contains "$decoded_fwd" "fwd_user1@example.com" "Trích xuất và giải mã đúng thuộc tính zimbraMailForwardingAddress"

decoded_gal="$(awk -F'\t' '$1 == "zimbraHideInGal" { print $2 }' "$user1_attrs" | base64 -d 2>/dev/null || true)"
assert_contains "$decoded_gal" "TRUE" "Trích xuất và giải mã đúng thuộc tính zimbraHideInGal"

decoded_ooo="$(awk -F'\t' '$1 == "zimbraPrefOutOfOfficeReplyEnabled" { print $2 }' "$user1_attrs" | base64 -d 2>/dev/null || true)"
assert_contains "$decoded_ooo" "TRUE" "Trích xuất và giải mã đúng thuộc tính zimbraPrefOutOfOfficeReplyEnabled"

# 12b. Single-user restore for Administrator preserves zimbraIsAdminAccount TRUE
: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --users "admin@example.com" --yes >/dev/null
admin_rest_log="$(cat "$MOCK_LOG")"
assert_contains "$admin_rest_log" "ZMPROV ma admin@example.com zimbraIsAdminAccount TRUE" \
    "Khôi phục tài khoản lẻ (Specific users): Tự động khôi phục quyền Administrator (zimbraIsAdminAccount TRUE) khi user là admin"

# 12c. Single-user restore for regular non-admin user does NOT grant admin privileges
: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --users "user1@example.com" --yes >/dev/null
user1_rest_log="$(cat "$MOCK_LOG")"
assert_not_contains "$user1_rest_log" "ZMPROV ma user1@example.com zimbraIsAdminAccount TRUE" \
    "Khôi phục tài khoản lẻ: Không cấp quyền admin nhầm cho người dùng thông thường (user1@example.com)"
assert_not_contains "$user1_rest_log" "ZMPROV ma admin@example.com" \
    "Khôi phục tài khoản lẻ: Không tác động ngoài phạm vi tài khoản được chỉ định"
assert_contains "$user1_rest_log" "ZMPROV ma user1@example.com zimbraMailSieveScript" \
    "Khôi phục tài khoản lẻ: Khôi phục đầy đủ bộ lọc Sieve script"

# 12d. Domain restore preserves admin privileges for admin accounts in that domain
: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --domain "example.com" --yes >/dev/null
dom_rest_log="$(cat "$MOCK_LOG")"
assert_contains "$dom_rest_log" "ZMPROV ma admin@example.com zimbraIsAdminAccount TRUE" \
    "Khôi phục theo domain: Khôi phục quyền admin cho tài khoản admin thuộc domain"

printf '\n=== 13. Kiểm tra bảo toàn trạng thái tài khoản (locked, closed) & Deferred Status ===\n'

# 13a. Mock account with locked status restores directly to locked
cat > "$latest_full/attributes/locked@example.com.attrs" <<'EOF'
displayName	TG9ja2VkIFVzZXI=
zimbraAccountStatus	bG9ja2Vk
EOF
cp "$MOCK_DATA/normal_mail.tgz" "$latest_full/mailboxes/locked@example.com.tgz"
printf 'locked@example.com\n' >> "$latest_full/accounts/active_accounts.txt"
(
    cd "$latest_full"
    sed -i '/^# --- sha256 ---$/q' manifest
    find domains admins dl accounts passwords attributes aliases signatures filters mailboxes \
        -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r sha256sum >> manifest
)

: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --users "locked@example.com" --yes >/dev/null
locked_rest_log="$(cat "$MOCK_LOG")"
assert_contains "$locked_rest_log" "ZMPROV ma locked@example.com" "Khôi phục tài khoản locked: Gọi zmprov ma cho locked@example.com"
assert_contains "$locked_rest_log" "zimbraAccountStatus locked" "Khôi phục tài khoản locked: Giữ nguyên trạng thái locked"

# 13b. Mock account with closed status uses deferred restoration (maintenance during import -> closed at end)
cat > "$latest_full/attributes/closed@example.com.attrs" <<'EOF'
displayName	Q2xvc2VkIFVzZXI=
zimbraAccountStatus	Y2xvc2Vk
EOF
cp "$MOCK_DATA/normal_mail.tgz" "$latest_full/mailboxes/closed@example.com.tgz"
printf 'closed@example.com\n' >> "$latest_full/accounts/active_accounts.txt"
(
    cd "$latest_full"
    sed -i '/^# --- sha256 ---$/q' manifest
    find domains admins dl accounts passwords attributes aliases signatures filters mailboxes \
        -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r sha256sum >> manifest
)

: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --users "closed@example.com" --yes >/dev/null
closed_rest_log="$(cat "$MOCK_LOG")"
assert_contains "$closed_rest_log" "zimbraAccountStatus active" \
    "Deferred status: Tam thoi dam bao trang thai active trong khi import hop thu"
assert_contains "$closed_rest_log" "service/home/closed@example.com" \
    "Deferred status: Hop thu duoc import thanh cong qua REST ma khong bi chan"
assert_contains "$closed_rest_log" "zimbraAccountStatus closed" \
    "Deferred status: Tu dong ap dat lai trang thai closed sau khi hoan tat import"

printf '\n=== 14. Kiểm tra tối ưu & An toàn v0.3.5 (Non-interactive confirmation & Multi-value attrs) ===\n'

# 14a. Non-interactive restore without --yes must abort safely
if "$ZB_CMD" restore --from "$latest_full" --users "user1@example.com" </dev/null >/dev/null 2>&1; then
    fail "Restore không có cờ --yes trong môi trường không tương tác (non-interactive) phải từ chối chạy để đảm bảo an toàn"
else
    pass "Restore không có cờ --yes trong môi trường non-interactive tự động từ chối chạy để tránh phá hủy dữ liệu"
fi

# 14b. Multi-valued attribute prefixing with + (multiple zimbraMailForwardingAddress)
cat > "$latest_full/attributes/multival@example.com.attrs" <<'EOF'
displayName	TXVsdGkgVmFsdWVkIFVzZXI=
zimbraMailForwardingAddress	ZndkMUBleGFtcGxlLmNvbQ==
zimbraMailForwardingAddress	ZndkMkBleGFtcGxlLmNvbQ==
EOF
cp "$MOCK_DATA/normal_mail.tgz" "$latest_full/mailboxes/multival@example.com.tgz"
printf 'multival@example.com\n' >> "$latest_full/accounts/active_accounts.txt"
(
    cd "$latest_full"
    sed -i '/^# --- sha256 ---$/q' manifest
    find domains admins dl accounts passwords attributes aliases signatures filters mailboxes \
        -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r sha256sum >> manifest
)

: > "$MOCK_LOG"
"$ZB_CMD" restore --from "$latest_full" --users "multival@example.com" --yes >/dev/null
multival_rest_log="$(cat "$MOCK_LOG")"
assert_contains "$multival_rest_log" "zimbraMailForwardingAddress fwd1@example.com" \
    "Giá trị thuộc tính đầu tiên được nạp chuẩn xác: zimbraMailForwardingAddress fwd1@example.com"
assert_contains "$multival_rest_log" "+zimbraMailForwardingAddress fwd2@example.com" \
    "Thuộc tính đa trị xuất hiện từ lần 2 được tiền tố dấu +: +zimbraMailForwardingAddress fwd2@example.com"

printf '\n=== 15. Kiểm tra cơ chế gửi Email thông báo (EMAIL_ALERT_LEVEL & Test Email) v0.3.6 ===\n'

# 15a. Config validation & CLI init with email-level
"$ZB_CMD" init \
    --backup-dir "$STORE_DIR" \
    --require-mount yes \
    --disk-warn 95 \
    --disk-min-mb 10 \
    --email-enabled yes \
    --email-to "alert@example.com" \
    --email-level all \
    --telegram-enabled yes \
    --telegram-token "mock_tg_token" \
    --telegram-chat "12345678" >/dev/null

cfg_content="$(cat "$STATE_DIR/settings.conf")"
assert_contains "$cfg_content" "EMAIL_ALERT_ENABLED=yes" "Init lưu đúng EMAIL_ALERT_ENABLED=yes"
assert_contains "$cfg_content" "EMAIL_ALERT_TO=alert@example.com" "Init lưu đúng EMAIL_ALERT_TO=alert@example.com"
assert_contains "$cfg_content" "EMAIL_ALERT_LEVEL=all" "Init lưu đúng EMAIL_ALERT_LEVEL=all"
assert_contains "$cfg_content" "TELEGRAM_ENABLED=yes" "Init lưu đúng TELEGRAM_ENABLED=yes"

# 15b. Test email command
: > "$MOCK_LOG"
"$ZB_CMD" notify test-email >/dev/null
test_mail_log="$(cat "$MOCK_LOG")"
assert_contains "$test_mail_log" "SENDMAIL -t" "Lệnh 'zimbra-backup notify test-email' gọi sendmail với cờ -t"
assert_contains "$test_mail_log" "To: alert@example.com" "Email test gửi đúng địa chỉ alert@example.com"
assert_contains "$test_mail_log" "Subject: [TEST] Zimbra Backup" "Email test có tiêu đề [TEST] Zimbra Backup"

# 15c. Test telegram command
: > "$MOCK_LOG"
"$ZB_CMD" notify test-telegram >/dev/null
assert_contains "$(cat "$MOCK_LOG")" "api.telegram.org" "Lệnh 'zimbra-backup notify test-telegram' gọi API Telegram"

# 15d. Backup success dispatches email when EMAIL_ALERT_LEVEL=all
"$ZB_CMD" job add mail-test --type full --schedule off --target-dir "$STORE_DIR" >/dev/null
: > "$MOCK_LOG"
"$ZB_CMD" job run mail-test >/dev/null
job_all_log="$(cat "$MOCK_LOG")"
assert_contains "$job_all_log" "SENDMAIL -t" "Backup thành công phát sinh email thông báo khi EMAIL_ALERT_LEVEL=all"
assert_contains "$job_all_log" "Subject: [OK] Zimbra Backup" "Email thông báo backup thành công mang tag [OK]"

# 15e. Backup success suppresses email when EMAIL_ALERT_LEVEL=failure
"$ZB_CMD" init --backup-dir "$STORE_DIR" --require-mount yes --email-enabled yes --email-to "alert@example.com" --email-level failure >/dev/null
: > "$MOCK_LOG"
"$ZB_CMD" job run mail-test >/dev/null
job_fail_log="$(cat "$MOCK_LOG")"
assert_not_contains "$job_fail_log" "SENDMAIL -t" "Backup thành công KHÔNG gửi email khi EMAIL_ALERT_LEVEL=failure"

# 15f. Ad-hoc backup dispatches notification on completion
"$ZB_CMD" init --backup-dir "$STORE_DIR" --require-mount yes --email-enabled yes --email-to "alert@example.com" --email-level all >/dev/null
: > "$MOCK_LOG"
"$ZB_CMD" backup user "user1@example.com" --dir "$STORE_DIR" >/dev/null
adhoc_mail_log="$(cat "$MOCK_LOG")"
assert_contains "$adhoc_mail_log" "SENDMAIL -t" "Sao lưu lẻ (Ad-hoc) phát sinh email thông báo khi hoàn tất"
assert_contains "$adhoc_mail_log" "Ad-hoc account backup succeeded" "Email thông báo ghi nhận thành công cho sao lưu lẻ"

printf '\n=== 16. Kiem tra co che sao luu tu xa FTP / SFTP & Chuan hoa thong bao v0.3.7 ===\n'

# 16a. Cau hinh FTP qua CLI init
"$ZB_CMD" init --backup-dir "$STORE_DIR" --require-mount yes \
    --ftp-enabled yes --ftp-protocol ftp --ftp-host "ftp.example.com" \
    --ftp-port 21 --ftp-user "ftpuser" --ftp-password "FTP_SECRET_PW" \
    --ftp-dir "/backups" --ftp-ssl yes >/dev/null

assert_file_exists "$ZB_STATE_DIR/settings.conf" "settings.conf ton tai sau khi init FTP"
ftp_cfg="$(cat "$ZB_STATE_DIR/settings.conf")"
assert_contains "$ftp_cfg" "FTP_ENABLED=yes" "Cau hinh FTP_ENABLED duoc luu la yes"
assert_contains "$ftp_cfg" "FTP_PROTOCOL=ftp" "Cau hinh FTP_PROTOCOL duoc luu la ftp"
assert_contains "$ftp_cfg" "FTP_HOST=ftp.example.com" "Cau hinh FTP_HOST duoc luu chinh xac"
assert_contains "$ftp_cfg" "FTP_PORT=21" "Cau hinh FTP_PORT duoc luu la 21"
assert_contains "$ftp_cfg" "FTP_USER=ftpuser" "Cau hinh FTP_USER duoc luu chinh xac"
assert_contains "$ftp_cfg" "FTP_PASSWORD=FTP_SECRET_PW" "Cau hinh FTP_PASSWORD duoc luu chinh xac"
assert_contains "$ftp_cfg" "FTP_REMOTE_DIR=/backups" "Cau hinh FTP_REMOTE_DIR duoc luu chinh xac"
assert_contains "$ftp_cfg" "FTP_SSL=yes" "Cau hinh FTP_SSL duoc luu la yes"

# 16b. Kiem tra notify test-ftp voi FTP va SFTP
: > "$MOCK_LOG"
test_ftp_out="$("$ZB_CMD" notify test-ftp 2>&1)"
assert_contains "$test_ftp_out" "SUCCESSFUL" "Lenh 'notify test-ftp' bao ket noi thanh cong"
mock_ftp_log="$(cat "$MOCK_LOG")"
assert_contains "$mock_ftp_log" "url=ftp://ftp.example.com:21/backups/" "curl thuc hien ket noi toi ftp:// URL dung port va thu muc"
assert_not_contains "$mock_ftp_log" "SECURITY_LEAK" "Khong lo mat khau FTP_SECRET_PW tren dong lenh curl"

# Chuyen sang SFTP port 22
"$ZB_CMD" init --ftp-protocol sftp --ftp-port 22 >/dev/null
: > "$MOCK_LOG"
test_sftp_out="$("$ZB_CMD" notify test-ftp 2>&1)"
assert_contains "$test_sftp_out" "SUCCESSFUL" "Lenh 'notify test-ftp' bao ket noi SFTP thanh cong"
mock_sftp_log="$(cat "$MOCK_LOG")"
assert_contains "$mock_sftp_log" "url=sftp://ftp.example.com:22/backups/" "curl thuc hien ket noi toi sftp:// URL tren port 22"

# 16c. Sao luu Job voi Remote Storage bat (FTP upload) va kiem tra dinh dang thong bao
"$ZB_CMD" init --backup-dir "$STORE_DIR" --require-mount yes \
    --email-enabled yes --email-to "alert@example.com" --email-level all \
    --telegram-enabled yes --telegram-token "TG_SECRET_BOT_TOKEN" --telegram-chat-id "123456789" \
    --ftp-enabled yes --ftp-protocol ftp --ftp-host "ftp.example.com" --ftp-port 21 \
    --ftp-user "ftpuser" --ftp-password "FTP_SECRET_PW" --ftp-dir "/backups" >/dev/null

"$ZB_CMD" job edit mail-test --ftp-upload yes --ftp-protocol ftp --ftp-host "ftp.example.com" \
    --ftp-port 21 --ftp-user "ftpuser" --ftp-password "FTP_SECRET_PW" --ftp-dir "/backups" >/dev/null

: > "$MOCK_LOG"
"$ZB_CMD" job run mail-test >/dev/null

job_ftp_log="$(cat "$MOCK_LOG")"
assert_contains "$job_ftp_log" "upload=" "Tien trinh backup thuc hien upload snapshot len FTP"
assert_contains "$job_ftp_log" ".tar" "Upload file archive .tar cua snapshot"
assert_contains "$job_ftp_log" "manifest" "Upload file manifest cua snapshot"
assert_contains "$job_ftp_log" "SENDMAIL -t" "Gui email thong bao sau khi upload FTP hoan tat"
assert_contains "$job_ftp_log" "Job Name   : Scheduled backup mail-test" "Thong bao chua Job Name day du"
assert_contains "$job_ftp_log" "Backup Mode: FULL" "Thong bao chua Backup Mode FULL"
assert_contains "$job_ftp_log" "Accounts   :" "Thong bao chua thong tin so luong Accounts"
assert_contains "$job_ftp_log" "Total Size :" "Thong bao chua Total Size"
assert_contains "$job_ftp_log" "Duration   :" "Thong bao chua Duration"
assert_contains "$job_ftp_log" "Local Path :" "Thong bao chua Local Path"
assert_contains "$job_ftp_log" "Remote Storage : OK (FTP://ftp.example.com:21" "Thong bao xac nhan Remote Storage OK kem host va port"

# 16d. Sao luu Job thong thuong (FTP disabled) van giu nguyen chuan hoa thong bao
"$ZB_CMD" init --ftp-enabled no >/dev/null
"$ZB_CMD" job edit mail-test --ftp-upload no >/dev/null
: > "$MOCK_LOG"
"$ZB_CMD" job run mail-test >/dev/null

job_local_log="$(cat "$MOCK_LOG")"
assert_contains "$job_local_log" "SENDMAIL -t" "Email duoc gui cho job local-only"
assert_contains "$job_local_log" "Job Name   : Scheduled backup mail-test" "Local job thong bao co Job Name"
assert_contains "$job_local_log" "Backup Mode: FULL" "Local job thong bao co Backup Mode"
assert_contains "$job_local_log" "Accounts   :" "Local job thong bao co Accounts"
assert_contains "$job_local_log" "Total Size :" "Local job thong bao co Total Size"
assert_contains "$job_local_log" "Duration   :" "Local job thong bao co Duration"
assert_contains "$job_local_log" "Local Path :" "Local job thong bao co Local Path"
assert_not_contains "$job_local_log" "Remote Storage : OK" "Local job khong bao Remote Storage OK khi FTP tat"

# 16e. Kiem tra lenh status hien thi Remote Storage
status_out="$("$ZB_CMD" status)"
assert_contains "$status_out" "Remote Storage" "Lenh 'status' hien thi muc Remote Storage"

printf '\n=== 17. Kiem tra cau hinh FTP theo tung Job & Tu dong don dep FTP theo FTP_KEEP_COUNT v0.3.8 ===\n'

# 17a. Them Job voi cau hinh FTP rieng
"$ZB_CMD" job add job-ftp-test \
    --type full \
    --schedule off \
    --target-dir "$STORE_DIR" \
    --ftp-upload yes \
    --ftp-protocol ftp \
    --ftp-host "ftp.remote.org" \
    --ftp-port 21 \
    --ftp-user "jobuser" \
    --ftp-password "JobSecretPass" \
    --ftp-dir "/remote/custom" \
    --ftp-ssl yes \
    --ftp-keep 3 >/dev/null

assert_file_exists "$ZB_STATE_DIR/jobs/job-ftp-test.conf" "Tao job-ftp-test.conf thanh cong"
job_ftp_cfg="$(cat "$ZB_STATE_DIR/jobs/job-ftp-test.conf")"
assert_contains "$job_ftp_cfg" "FTP_UPLOAD=yes" "Job luu dung FTP_UPLOAD=yes"
assert_contains "$job_ftp_cfg" "FTP_PROTOCOL=ftp" "Job luu dung FTP_PROTOCOL=ftp"
assert_contains "$job_ftp_cfg" "FTP_HOST=ftp.remote.org" "Job luu dung FTP_HOST=ftp.remote.org"
assert_contains "$job_ftp_cfg" "FTP_PORT=21" "Job luu dung FTP_PORT=21"
assert_contains "$job_ftp_cfg" "FTP_USER=jobuser" "Job luu dung FTP_USER=jobuser"
assert_contains "$job_ftp_cfg" "FTP_PASSWORD=JobSecretPass" "Job luu dung FTP_PASSWORD=JobSecretPass"
assert_contains "$job_ftp_cfg" "FTP_REMOTE_DIR=/remote/custom" "Job luu dung FTP_REMOTE_DIR=/remote/custom"
assert_contains "$job_ftp_cfg" "FTP_SSL=yes" "Job luu dung FTP_SSL=yes"
assert_contains "$job_ftp_cfg" "FTP_KEEP_COUNT=3" "Job luu dung FTP_KEEP_COUNT=3"

# Kiem tra job show hien thi thong tin FTP
job_show_out="$("$ZB_CMD" job show job-ftp-test)"
assert_contains "$job_show_out" "YES [ftp://ftp.remote.org:21/remote/custom | Keep: 3 remote snapshots]" \
    "Lenh 'job show' hien thi dung cau hinh Remote FTP kem retention"

# 17b. Kiem tra test-ftp voi job_id cu the
: > "$MOCK_LOG"
test_job_ftp_out="$("$ZB_CMD" notify test-ftp job-ftp-test 2>&1)"
assert_contains "$test_job_ftp_out" "SUCCESSFUL" "Lenh 'notify test-ftp job-ftp-test' bao ket noi thanh cong"
mock_job_ftp_log="$(cat "$MOCK_LOG")"
assert_contains "$mock_job_ftp_log" "url=ftp://ftp.remote.org:21/remote/custom/" \
    "curl test-ftp dung dia chi ftp://ftp.remote.org:21/remote/custom/"

# 17c. Them Job khong co FTP (FTP_UPLOAD=no)
"$ZB_CMD" job add job-local-only \
    --type full \
    --schedule off \
    --target-dir "$STORE_DIR" \
    --ftp-upload no >/dev/null

assert_file_exists "$ZB_STATE_DIR/jobs/job-local-only.conf" "Tao job-local-only.conf thanh cong"
assert_contains "$(cat "$ZB_STATE_DIR/jobs/job-local-only.conf")" "FTP_UPLOAD=no" "Job local luu FTP_UPLOAD=no"
job_local_show="$("$ZB_CMD" job show job-local-only)"
assert_contains "$job_local_show" "Remote FTP Upload  : Disabled" "Job local hien thi Remote FTP Upload: Disabled"

# 17d. Chay backup job co FTP: kiem tra upload va bao toan local snapshot
: > "$MOCK_LOG"
"$ZB_CMD" job run job-ftp-test >/dev/null
job_run_ftp_log="$(cat "$MOCK_LOG")"
assert_contains "$job_run_ftp_log" "upload=" "Job backup day thanh cong snapshot len FTP"
assert_contains "$job_run_ftp_log" "ftp://ftp.remote.org:21/remote/custom/full/job-ftp-test/" \
    "Snapshot duoc day dung vao thu muc remote cua Job"

# Kiem tra thu muc local van giu nguyen 100% (tuyet doi khong bi xoa)
local_snaps=( "$STORE_DIR/full/job-ftp-test"/backup-full-* )
[[ ${#local_snaps[@]} -ge 1 && -d "${local_snaps[0]}" ]] \
    && pass "Bao toan 100% ban backup cuc bo tai local sau khi upload FTP (tuyet doi khong xoa)" \
    || fail "Bao toan local that bai: snapshot cuc bo bi mat sau khi upload FTP"
assert_file_exists "${local_snaps[0]}/manifest" "Snapshot cuc bo van con nguyen ven manifest tai local"

# 17e. Kiem tra co che tu dong don dep FTP (zb_prune_remote_storage) theo FTP_KEEP_COUNT
export MOCK_FTP_LIST_DATA="backup-full-20261101-010000.tar
backup-full-20261101-010000.manifest
backup-full-20261102-010000.tar
backup-full-20261102-010000.manifest
backup-full-20261103-010000.tar
backup-full-20261103-010000.manifest
backup-full-20261104-010000.tar
backup-full-20261104-010000.manifest
backup-full-20261105-010000.tar
backup-full-20261105-010000.manifest"

: > "$MOCK_LOG"
"$ZB_CMD" job run job-ftp-test >/dev/null
prune_log="$(cat "$MOCK_LOG")"
assert_contains "$prune_log" "FTP_QUOTE: DELE /remote/custom/full/job-ftp-test/backup-full-20261101-010000.tar" \
    "Don dep FTP: Goi DELE xoa file .tar cu nhat (#1) tren FTP server"
assert_contains "$prune_log" "FTP_QUOTE: DELE /remote/custom/full/job-ftp-test/backup-full-20261101-010000.manifest" \
    "Don dep FTP: Goi DELE xoa file .manifest cu nhat (#1) tren FTP server"
assert_contains "$prune_log" "FTP_QUOTE: DELE /remote/custom/full/job-ftp-test/backup-full-20261102-010000.tar" \
    "Don dep FTP: Goi DELE xoa file .tar cu nhat (#2) tren FTP server"
assert_contains "$prune_log" "FTP_QUOTE: DELE /remote/custom/full/job-ftp-test/backup-full-20261102-010000.manifest" \
    "Don dep FTP: Goi DELE xoa file .manifest cu nhat (#2) tren FTP server"
assert_not_contains "$prune_log" "backup-full-20261103-010000.tar" \
    "Don dep FTP: Giu lai ban archive moi hon trong pham vi FTP_KEEP_COUNT=3"
unset MOCK_FTP_LIST_DATA

printf '\n=== 18. Kiểm tra ưu tiên zimbraAdminPort (7071) & xử lý HTTP 204 No Content trên zmmailbox ===\n'
export ZB_LIB_DIR="$REPO_ROOT/lib"
. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/notify.sh"
. "$REPO_ROOT/lib/zimbra_api.sh"
. "$REPO_ROOT/lib/jobs.sh"
. "$REPO_ROOT/lib/backup.sh"

# Test port detection logic prioritizes 7071
orig_force_port="${ZB_FORCE_REST_PORT:-}"
orig_rest_port="${ZB_REST_PORT:-}"
unset ZB_FORCE_REST_PORT ZB_REST_PORT
detected_p="$(zb_detect_rest_port)"
[[ "$detected_p" == "7071" ]] && pass "Dò cổng REST ưu tiên zimbraAdminPort 7071 cho ZM_ADMIN_AUTH_TOKEN" \
    || fail "Dò cổng REST phát hiện sai cổng: $detected_p (kỳ vọng: 7071)"
[[ -n "$orig_force_port" ]] && export ZB_FORCE_REST_PORT="$orig_force_port"
ZB_REST_PORT="$orig_rest_port"

# Test zmmailbox fallback handling status=204 No Content
export MOCK_ZMMAILBOX_FAIL_204=1
test_out_tgz="$TEST_TMP/zmm_204_test.tgz"
rm -f -- "$test_out_tgz" "${test_out_tgz%.tgz}.empty"
# Call with empty auth_cfg so curl is skipped and zmmailbox is tested directly
if zb_export_mailbox_archive "empty@example.com" "$test_out_tgz" "incr" "1793863982" ""; then
    pass "zmmailbox fallback: Nhận diện mã 204 No Content (exit code 2) là empty delta hợp lệ"
else
    fail "zmmailbox fallback: Xử lý sai mã 204 No Content trên zmmailbox"
fi
assert_file_exists "${test_out_tgz%.tgz}.empty" "zmmailbox fallback: Tạo đúng file marker .empty cho delta rỗng"
[[ ! -f "$test_out_tgz" ]] && pass "zmmailbox fallback: Dọn sạch file .tgz khi không có mail mới" \
    || fail "zmmailbox fallback: Còn sót file .tgz rỗng"
rm -f -- "${test_out_tgz%.tgz}.empty"
unset MOCK_ZMMAILBOX_FAIL_204

# Test zmmailbox fallback failing properly on real error
export MOCK_ZMMAILBOX_FAIL_REAL=1
test_fail_tgz="$TEST_TMP/zmm_fail_test.tgz"
rm -f -- "$test_fail_tgz" "${test_fail_tgz%.tgz}.empty"
if zb_export_mailbox_archive "empty@example.com" "$test_fail_tgz" "incr" "1793863982" ""; then
    fail "zmmailbox fallback: Phải thất bại khi zmmailbox gặp lỗi thật"
else
    pass "zmmailbox fallback: Báo lỗi chính xác khi zmmailbox gặp lỗi hệ thống thật"
fi
rm -f -- "$test_fail_tgz" "${test_fail_tgz%.tgz}.empty"
unset MOCK_ZMMAILBOX_FAIL_REAL

PACKAGED_FILES=(
    "$REPO_ROOT/zimbra-backup"
    "$REPO_ROOT/bin/zimbra-backup"
    "$REPO_ROOT/lib/common.sh"
    "$REPO_ROOT/lib/notify.sh"
    "$REPO_ROOT/lib/zimbra_api.sh"
    "$REPO_ROOT/lib/jobs.sh"
    "$REPO_ROOT/lib/backup.sh"
    "$REPO_ROOT/lib/restore.sh"
    "$REPO_ROOT/lib/tui.sh"
    "$REPO_ROOT/packaging/preinstall.sh"
    "$REPO_ROOT/packaging/preremove.sh"
    "$REPO_ROOT/packaging/postremove.sh"
    "$REPO_ROOT/packaging/zimbra-backup.logrotate"
    "$REPO_ROOT/nfpm.yaml"
    "$REPO_ROOT/zimbra-backup.spec"
)

non_ascii_hit=""
crlf_hit=""
for pf in "${PACKAGED_FILES[@]}"; do
    bad_bytes="$(LC_ALL=C tr -d '\11\12\40-\176' < "$pf" | wc -c | tr -d '[:space:]')"
    if [[ "$bad_bytes" != "0" ]]; then
        non_ascii_hit="$pf ($bad_bytes bytes)"
        break
    fi
    if LC_ALL=C grep -q $'\r' "$pf"; then
        crlf_hit="$pf"
        break
    fi
done
[[ -z "$non_ascii_hit" ]] && pass "Toàn bộ 15 file đóng gói RPM đều đạt chuẩn 100% Pure 7-bit ASCII (không bao giờ lỗi font □)" \
    || fail "Phát hiện ký tự ngoài bảng mã ASCII 7-bit trong: $non_ascii_hit"
[[ -z "$crlf_hit" ]] && pass "Toàn bộ 15 file đóng gói RPM đều giữ chuẩn xuống dòng LF (\\n)" \
    || fail "Phát hiện ký tự CRLF (\\r\\n) trong: $crlf_hit"

printf '\n============================================================\n'
printf 'HOÀN TẤT KIỂM THỬ TỰ ĐỘNG: %d/%d bài kiểm tra ĐẠT (0 lỗi)\n' "$PASS_COUNT" "$PASS_COUNT"
printf '============================================================\n'
