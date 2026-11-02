#!/usr/bin/env bash
# End-to-end automated test suite for zimbra-backup v0.2.0
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
        printf '--- Expected to find: %s\n--- Actual output:\n%s\n' "$needle" "$haystack" >&2
        fail "$msg"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$msg"
    else
        printf '--- Expected NOT to find: %s\n--- Actual output:\n%s\n' "$needle" "$haystack" >&2
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
sh -n "$REPO_ROOT/packaging/preinstall.sh"
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
    gs)
        # Server SSL port lookup
        printf 'zimbraMailSSLPort: 8443\n'
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
        printf 'all@example.com\n'
        ;;
    gdl)
        exit 1
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
        printf 'admin@example.com\nuser1@example.com\nempty@example.com\nsales@sub.example.com\nspam.xyz@example.com\n'
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
zimbraMailSieveScript: require ["fileinto"];
 if header :contains "Subject" "[SPAM]" {
   fileinto "Junk";
 }
LDIF
        ;;
    gsig)
        email="${1:-}"
        if [[ "$email" == "user1@example.com" ]]; then
            cat <<SIG
# name Chữ ký Công ty
zimbraSignatureId: sig-001
zimbraSignatureName: Chữ ký Công ty
zimbraPrefMailSignatureHTML: <div>Trân trọng,<br>Nguyễn Văn A</div>
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
exit 0
EOF
chmod +x "$MOCK_BIN/zmmailbox"

# Mock curl (validates -K 0600 config usage, hides secrets from argv, serves REST tgz & imports)
cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    if [[ "$arg" == *"MOCK_ADMIN_TOKEN_SECRET_999"* || "$arg" == *"TG_SECRET_BOT_TOKEN"* ]]; then
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

while (( $# > 0 )); do
    case "$1" in
        -K) cfg_file="$2"; shift 2 ;;
        -o) out_file="$2"; shift 2 ;;
        -w) write_fmt="$2"; shift 2 ;;
        -X) [[ "$2" == "POST" ]] && is_post=1; shift 2 ;;
        -T|--data-binary) upload_file="$2"; is_post=1; shift 2 ;;
        --data-urlencode) shift 2 ;;
        --connect-timeout|--max-time) shift 2 ;;
        -k|-s|-sS|-ks|-sk) shift ;;
        http://*|https://*) pos_url="$1"; shift ;;
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

grep -q 'MOCK_ADMIN_TOKEN_SECRET_999' "$cfg_file" || { echo "Missing admin auth cookie" >&2; exit 3; }

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

snap_count="$(find "$STORE_DIR/full-daily/snapshots" -mindepth 1 -maxdepth 1 -type d -name 'full_*' | wc -l | tr -d '[:space:]')"
[[ "$snap_count" == "2" ]] && pass "Giới hạn lưu trữ KEEP_COUNT=2 (after) giữ đúng 2 bản Full mới nhất" \
    || fail "Số bản Full thực tế ($snap_count) khác 2"

latest_full="$(find "$STORE_DIR/full-daily/snapshots" -mindepth 1 -maxdepth 1 -type d -name 'full_*' | LC_ALL=C sort | tail -n 1)"
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

printf '\n=== 5. Kiểm tra Chuỗi Incremental (000_full -> 001_incr -> 002_incr) & Xoay chuỗi mới (before) ===\n'
"$ZB_CMD" job run incr-main # Chain 1: 000_full
sleep 1
"$ZB_CMD" job run incr-main # Chain 1: 001_incr
sleep 1
"$ZB_CMD" job run incr-main # Chain 1: 002_incr

chain1_dir="$(find "$ALT_STORE_DIR/incr-main/chains" -mindepth 1 -maxdepth 1 -type d -name 'chain_*' | head -n 1)"
step_count="$(find "$chain1_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')"
[[ "$step_count" == "3" ]] && pass "Tạo chuỗi Incremental gồm 1 bản Full gốc + 2 bản Incremental kế tiếp" \
    || fail "Số bước trong chuỗi 1 ($step_count) khác 3"

incr2_dir="$(find "$chain1_dir" -mindepth 1 -maxdepth 1 -type d -name '002_incr_*' | head -n 1)"
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
assert_contains "$restore_log" "ZMPROV csig user1@example.com Chữ ký Công ty" "Khôi phục chữ ký người dùng bằng zmprov csig"
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
chains_remaining="$(find "$ALT_STORE_DIR/incr-main/chains" -mindepth 1 -maxdepth 1 -type d -name 'chain_*' | wc -l | tr -d '[:space:]')"
[[ "$chains_remaining" == "1" ]] && pass "Chu kỳ tạo chuỗi Full mới + xóa chuỗi cũ theo KEEP_COUNT=1 (before) hoạt động chính xác" \
    || fail "Số chuỗi còn lại ($chains_remaining) khác 1"

# Ad-hoc user backup + pending cleanup + job-only discovery isolation + legacy directory restore
printf '\n=== 7. Kiểm tra Cô lập thư mục theo Job, Backup lẻ, Dọn .pending.* & Thư mục Restore riêng ===\n'
"$ZB_CMD" backup user "user1@example.com,empty@example.com"
adhoc_count="$(find "$STORE_DIR/manual-accounts/snapshots" -mindepth 1 -maxdepth 1 -type d -name 'adhoc_*' | wc -l | tr -d '[:space:]')"
[[ "$adhoc_count" == "1" ]] && pass "Sao lưu nhanh tài khoản lẻ (manual-accounts) độc lập với giới hạn của Job" \
    || fail "Không tìm thấy bản sao lưu lẻ"

# Create a stray unconfigured backup folder inside STORE_DIR to verify default discovery ignores non-job dirs
STRAY_SNAP="$STORE_DIR/unconfigured-folder/snapshots/full_20990101_000000"
mkdir -p "$STRAY_SNAP"/{accounts,mailboxes}
printf 'user1@example.com\n' > "$STRAY_SNAP/accounts/active_accounts.txt"
cp -- "$MOCK_DATA/normal_mail.tgz" "$STRAY_SNAP/mailboxes/user1@example.com.tgz"

default_cat="$("$ZB_CMD" backup list)"
assert_contains "$default_cat" "full-daily" "Danh sách mặc định lấy đúng thư mục của Job full-daily"
assert_contains "$default_cat" "incr-main" "Danh sách mặc định lấy đúng thư mục của Job incr-main"
assert_not_contains "$default_cat" "manual-accounts" "Danh sách Job mặc định KHÔNG quét lẫn thư mục sao lưu lẻ manual-accounts"
assert_not_contains "$default_cat" "20990101_000000" "Danh sách Job mặc định KHÔNG quét tràn lan thư mục lạ ngoài Job trên cùng ổ đĩa"

single_job_cat="$("$ZB_CMD" backup list --job full-daily)"
assert_contains "$single_job_cat" "full-daily" "Lọc theo --job full-daily hiển thị đúng các bản sao lưu của Job đó"
assert_not_contains "$single_job_cat" "incr-main" "Lọc theo --job full-daily không lẫn bản sao lưu của Job khác"

adhoc_cat="$("$ZB_CMD" backup list --dir "$STORE_DIR/manual-accounts")"
assert_contains "$adhoc_cat" "manual-accounts" "Quét riêng --dir nhận diện đúng bản sao lưu lẻ (manual-accounts)"

mkdir -p "$STORE_DIR/full-daily/snapshots/.pending.99999"
"$ZB_CMD" backup clean-pending >/dev/null
[[ ! -d "$STORE_DIR/full-daily/snapshots/.pending.99999" ]] && pass "Dọn sạch thư mục tạm .pending.* bị dở dang" \
    || fail "Chưa xóa được thư mục .pending.99999"

# Legacy auto_full_backup.sh layout compatibility & separate CUSTOM_RESTORE_DIR setting
LEGACY_DIR="$TEST_TMP/legacy_root/20260101_020000"
mkdir -p "$LEGACY_DIR"/{domains,accounts,userpass,alias,signatures,filter,mailboxes}
printf 'example.com\n' > "$LEGACY_DIR/domains/domains.txt"
printf 'legacy@example.com\n' > "$LEGACY_DIR/accounts/active_accounts.txt"
printf 'userPassword: {SSHA}legacyHash\n' > "$LEGACY_DIR/userpass/legacy@example.com.shadow"
cp -- "$MOCK_DATA/normal_mail.tgz" "$LEGACY_DIR/mailboxes/legacy@example.com.tgz"

"$ZB_CMD" init --backup-dir "$STORE_DIR" --restore-dir "$TEST_TMP/legacy_root" --require-mount no >/dev/null
assert_contains "$(cat "$STATE_DIR/settings.conf")" "CUSTOM_RESTORE_DIR=$TEST_TMP/legacy_root" \
    "Lưu cấu hình thư mục Restore riêng (CUSTOM_RESTORE_DIR) độc lập với DEFAULT_BACKUP_DIR"

cat_out="$("$ZB_CMD" backup list --dir "$TEST_TMP/legacy_root")"
assert_contains "$cat_out" "legacy-full" "Nhận diện và hiển thị được thư mục backup định dạng cũ (auto_full_backup.sh)"

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
[[ -z "$non_ascii_hit" ]] && pass "Toàn bộ 13 file đóng gói RPM đều đạt chuẩn 100% Pure 7-bit ASCII (không bao giờ lỗi font □)" \
    || fail "Phát hiện ký tự ngoài bảng mã ASCII 7-bit trong: $non_ascii_hit"
[[ -z "$crlf_hit" ]] && pass "Toàn bộ 13 file đóng gói RPM đều giữ chuẩn xuống dòng LF (\\n)" \
    || fail "Phát hiện ký tự CRLF (\\r\\n) trong: $crlf_hit"

printf '\n============================================================\n'
printf 'HOÀN TẤT KIỂM THỬ TỰ ĐỘNG: %d/%d bài kiểm tra ĐẠT (0 lỗi)\n' "$PASS_COUNT" "$PASS_COUNT"
printf '============================================================\n'
