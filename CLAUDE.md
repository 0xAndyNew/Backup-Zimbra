# CLAUDE.md

Tài liệu này hướng dẫn Claude Code (claude.ai/code) khi làm việc với mã nguồn trong repository này.

## Tổng quan kiến trúc (`zimbra-backup` v0.3.16)

Repository đóng gói công cụ sao lưu & khôi phục **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** trên **Ubuntu 18.04, 20.04, 22.04 LTS** (gói DEB `.deb`) và **CentOS/RHEL/AlmaLinux/Rocky 7, 8, 9** (gói RPM `.rpm` `noarch`), phân phối tại mục GitHub Releases, hợp nhất và khắc phục triệt để các lỗi toàn vẹn dữ liệu của các script sao lưu truyền thống.

### Phân tách module

| Đường dẫn trong Repo | Đường dẫn khi cài RPM | Vai trò |
|---|---|---|
| `bin/zimbra-backup` | `/usr/bin/zimbra-backup` | Entrypoint chính: kiểm tra quyền `zimbra`, điều phối CLI và mở Menu TUI tiếng Anh (Pure ASCII) |
| `zimbra-backup` | *(chỉ trong repo)* | Wrapper mỏng gọi `exec bin/zimbra-backup "$@"` khi chạy trực tiếp từ cây mã nguồn |
| `lib/common.sh` | `/usr/libexec/zimbra-backup/common.sh` | Chuyển quyền `runuser -u zimbra`, nạp `zmshutil`, parser cấu hình allowlist, khóa `flock` FD 9, kiểm tra mountpoint/symlink/dung lượng đĩa |
| `lib/notify.sh` | `/usr/libexec/zimbra-backup/notify.sh` | Gửi cảnh báo Telegram (`curl -K` ẩn Bot Token) và Email (`sendmail`) kèm `HOST_LABEL` |
| `lib/zimbra_api.sh` | `/usr/libexec/zimbra-backup/zimbra_api.sh` | Dò cổng SSL (`8443`/`443`/`7071`), xoay vòng `ZM_ADMIN_AUTH_TOKEN`, giải mã LDIF RFC 2849 + Base64 UTF-8, xuất/nạp `zmprov`/`zmmailbox`/REST |
| `lib/jobs.sh` | `/usr/libexec/zimbra-backup/jobs.sh` | CRUD đa Job (`/var/lib/zimbra-backup/jobs/<id>.conf`), bộ lập lịch ngày/tuần/tháng/cron tùy chỉnh, đồng bộ khối `# BEGIN zimbra-backup .. # END zimbra-backup` trong `crontab` của `zimbra` |
| `lib/backup.sh` | `/usr/libexec/zimbra-backup/backup.sh` | Engine sao lưu tách 3 thư mục rút gọn `full/full-DD-MM-YYYY`, `incremental/full-DD-MM-YYYY` + `incremental/NNN-incremental-DD-MM-YYYY`, `account/backup-<email>-DD-MM-YYYY`, chạy song song `PARALLEL_JOBS`, ghi/kiểm tra `manifest` `zb-backup-v2`, xóa bản cũ `after`/`before` |
| `lib/restore.sh` | `/usr/libexec/zimbra-backup/restore.sh` | Quét kho backup của Job hoặc quét đệ quy thư mục ngoài (`CUSTOM_RESTORE_DIR` / `--dir`), ghép chuỗi `000_full + 001..k_incr`, khôi phục toàn server / domain / danh sách user / sang tài khoản khác / thư mục con |
| `lib/tui.sh` | `/usr/libexec/zimbra-backup/tui.sh` | Giao diện Menu tương tác tiếng Anh rút gọn (Pure 7-bit ASCII): Wizard thiết lập 2 bước, Tạo Job 6 bước (bắt buộc cấu hình đường dẫn lưu trữ), Sửa Job chọn trường `1..11` |
| `packaging/preinstall.sh` | *(script `%pre` của RPM)* | Kiểm tra sự tồn tại của user hệ thống `zimbra` trước khi cài gói |
| `packaging/preremove.sh` | *(script `%preun` của RPM)* | Khi gỡ hẳn (`$1 == 0`): chặn nếu `operation.lock` đang bận, gỡ riêng khối cron `zimbra-backup` (kiểm chứng `cmp -s` bảo toàn cron Zimbra) và dọn trước file con trong `/var/lib/zimbra-backup` |
| `packaging/postremove.sh` | *(script `%postun` của RPM)* | Khi gỡ hẳn (`$1 == 0`): xóa `/var/lib/zimbra-backup` và `.rpmsave`/`.rpmnew`, giữ nguyên `/opt/zimbra` và dữ liệu backup |
| `packaging/zimbra-backup.logrotate` | `/etc/logrotate.d/zimbra-backup` | Xoay vòng log tuần cho `/var/lib/zimbra-backup/logs/*.log` (`su zimbra zimbra`, `0600`) |

## Các bất biến kỹ thuật & an toàn bắt buộc giữ vững

1. **Tương thích Bash 4.2 & CentOS 7 (`curl 7.29`)**:
   - Không dùng `local -n` (nameref), `wait -n`, `grep -P`, hay `${var@Q}`.
   - Dưới `set -Eeuo pipefail`: dùng `var=$((var + 1))` thay vì `((var++))` khi biến có thể bằng `0`; kiểm tra mảng rỗng trước khi mở rộng dưới `set -u`; bọc `set +u +e ... set -eu` quanh `/opt/zimbra/bin/zmshutil`.
   - Khi tách chuỗi theo dấu phẩy trong hàm, luôn dùng tiền tố lệnh `IFS=',' read -r -a arr <<< "$csv"`, **tuyệt đối không dùng `local IFS=','`** vì phạm vi động (dynamic scope) của Bash sẽ làm rò `IFS=','` sang các hàm con được gọi bên dưới (như `zb_valid_cron_expr`).
2. **Không `source` cấu hình & Bảo mật Token**:
   - Mọi file cấu hình (`settings.conf`, `jobs/*.conf`, `manifest`) đều phải đọc qua parser `key=value` allowlist kèm kiểm tra định dạng đầu vào, không bao giờ `source` trực tiếp.
   - `ZM_ADMIN_AUTH_TOKEN` và `TELEGRAM_TOKEN` chỉ được ghi vào file cấu hình tạm quyền `0600` trong `$ZB_RUN_DIR` (`/var/lib/zimbra-backup/run/`) để truyền qua `curl -K <cfg>` và phải dọn sạch bằng `trap` khi thoát; không bao giờ đặt trên dòng lệnh `curl` (lộ qua `ps aux`) hoặc trong `/tmp`.
3. **Cô lập khóa `flock`, luồng log và biến toàn cục bằng hàm Subshell**:
   - `zb_run_job() ( ... )`, `zb_run_adhoc_users() ( ... )`, `zb_clean_pending_dirs() ( ... )` trong `lib/backup.sh`, `zb_run_restore() ( ... )` trong `lib/restore.sh`, và `zb_cron_sync() ( ... )`, `zb_job_print_summary_table() ( ... )`, `zb_job_print_detail() ( ... )` trong `lib/jobs.sh` được khai báo bằng cặp ngoặc đơn `( ... )` có chủ đích để FD 9 (`flock -n 9`), `exec > >(tee -a "$ZB_CURRENT_LOG") 2>&1` và các lần gọi `zb_job_load` nội bộ không rò rỉ ra ngoài khi quay lại Menu TUI. Mọi hàm `trap ... EXIT` bên trong subshell phải lưu `local rc=$?` ở dòng đầu và kết thúc bằng `return "$rc"`.
4. **Toàn vẹn dữ liệu Zimbra & Giới hạn của Incremental OSE**:
   - Giải mã LDIF luôn đi qua `zb_ldif_unfold` (`lib/zimbra_api.sh`) để nối dòng gập RFC 2849 và giải mã Base64 (`attr::`), bảo toàn tiếng Việt UTF-8 (`displayName`), chữ ký (`zmprov -l gsig`), danh sách thành viên DL (`zmprov -l gdlm`) và bộ lọc Sieve nhiều dòng.
   - Không xóa file `.tgz` dựa trên kích thước `<200 bytes` (hộp thư mới tạo hợp lệ chỉ khoảng 45–150 bytes); xác minh bằng `tar -tzf` + SHA-256 trong `manifest`.
   - Bản Incremental trên Zimbra OSE xuất toàn bộ snapshot LDAP tại thời điểm chạy + hộp thư qua REST `?fmt=tgz&query=after:<(last_checkpoint_to - 300) * 1000>`. Cơ chế này chống sót mail giao thời/mất điện, nhưng theo đặc thù REST API của Zimbra OSE, nó là **bản bồi đắp mục mới/thay đổi** (không tự xóa các email mà người dùng đã xóa tay giữa 2 lần chạy khi nạp đè bằng `resolve=modify`). Khi khôi phục chuỗi với `--mode reset`, bước `000_full` chạy `resolve=reset` và các bước `001_incr..k_incr` tự chuyển sang `resolve=modify`.
5. **100% Pure 7-bit ASCII cho toàn bộ mã đóng gói & Chuẩn xuống dòng LF (`\n`)**:
   - Tất cả 15 file đóng gói vào RPM (`zimbra-backup`, `bin/zimbra-backup`, `lib/*.sh`, `packaging/*`, `nfpm.yaml`, `zimbra-backup.spec`) bắt buộc chỉ chứa ký tự ASCII 7-bit (`0x09`, `0x0A`, `0x20..0x7E`) để hiển thị sạch trên mọi SSH client, console VM và `cron` (`LANG=C`); được kiểm tra tự động trong `tests/run_tests.sh`.
   - `.gitattributes` cưỡng bức `eol=lf` cho toàn bộ script, `.spec`, `.yaml`, `packaging/*`. Khi sửa file trên Windows, tuyệt đối không ghi CRLF (`\r\n`) vì sẽ làm hỏng shebang và `%pre` khi cài RPM trên Linux.

## Các lệnh phát triển, kiểm thử & đóng gói

Kiểm tra cú pháp Bash & POSIX sh:

```bash
bash -n zimbra-backup bin/zimbra-backup lib/*.sh tests/run_tests.sh
```

```bash
sh -n packaging/preinstall.sh packaging/preremove.sh packaging/postremove.sh
```

Chạy bộ kiểm thử tự động đầu-cuối (giả lập `zmprov`, `zmmailbox`, `zmsoap`, `curl`, `crontab`, `mountpoint` — chạy an toàn trên cả Windows Git Bash và Linux không cần root):

```bash
bash tests/run_tests.sh
```

Phân tích tĩnh bằng ShellCheck (nếu môi trường có cài `shellcheck`):

```bash
shellcheck -x bin/zimbra-backup lib/*.sh tests/run_tests.sh
```

Đóng gói gói binary RPM `noarch` bằng nFPM (trên Windows hoặc Linux):

```bash
nfpm package --config nfpm.yaml --packager rpm
```

Đóng gói bằng `rpmbuild` trên máy chủ Linux có `rpm-build`:

```bash
mkdir -p "$HOME/rpmbuild/SOURCES" zimbra-backup-0.3.16 && \
cp -r bin lib packaging README.md zimbra-backup-0.3.16/ && \
tar czf "$HOME/rpmbuild/SOURCES/zimbra-backup-0.3.16.tar.gz" zimbra-backup-0.3.16 && \
rpmbuild -ba zimbra-backup.spec
```

### Biến môi trường phục vụ kiểm thử cô lập

Khi chạy thử hoặc viết thêm bài test trong `tests/`, có thể ghi đè:
- `ZB_STATE_DIR`: thư mục chứa `settings.conf`, `jobs/`, `logs/`, `run/`, `operation.lock`.
- `ZB_ZIMBRA_BIN`: thư mục chứa binary/mock `zmprov`, `zmmailbox`, `zmsoap`, `zmhostname`.
- `ZB_SKIP_USER_CHECK=1` và `ZB_SKIP_ZMSHUTIL=1`: bỏ qua kiểm tra user hệ thống `zimbra` và `zmshutil` trên máy phát triển.
- `ZB_FORCE_REST_PORT=8443`: cố định cổng REST cục bộ trong môi trường mock.
