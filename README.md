# Zimbra Backup & Restore (`zimbra-backup` v0.3.18)

[![Release](https://img.shields.io/github/v/release/0xAndyNew/Backup-Zimbra?color=brightgreen&label=Release)](https://github.com/0xAndyNew/Backup-Zimbra/releases)
[![CI](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml/badge.svg)](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zimbra OSE](https://img.shields.io/badge/Zimbra_OSE-8.8.15_%7C_9_%7C_10-orange.svg)](https://www.zimbra.com/)
[![OS Support](https://img.shields.io/badge/OS-Ubuntu_%7C_RHEL_%7C_CentOS_%7C_Rocky_%7C_Alma-blue.svg)]()
[![Packages](https://img.shields.io/badge/Packages-RPM_%7C_DEB-success.svg)]()
[![Bash](https://img.shields.io/badge/Bash-4.2%2B-lightgrey.svg)]()
[![Encoding](https://img.shields.io/badge/Encoding-100%25_Pure_7--bit_ASCII-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-306%2F306_Passing-brightgreen.svg)]()

> 🌐 **[English Documentation](README_EN.md)** | **[Tài liệu Tiếng Việt](README.md)** | **[Hướng dẫn sử dụng chi tiết từng bước](HUONG_DAN_SU_DUNG.md)**

Bộ công cụ đóng gói `.rpm` và `.deb` hợp nhất chuyên nghiệp dành cho máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** trên **Ubuntu 18.04, 20.04, 22.04 LTS** và **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**. Trang bị **Giao diện Menu tương tác TUI (100% Pure 7-bit ASCII — không bao giờ lỗi font `□` trên mọi SSH / VM Console)** cùng hệ thống **CLI tự động hóa** đầy đủ và cơ chế an toàn `--yes`.

---

## ⚡ Cài đặt nhanh trong 1 dòng lệnh (Quick Install)

Áp dụng cho cả **Cài mới** lẫn **Nâng cấp** từ phiên bản cũ (tự động giữ nguyên toàn bộ cấu hình, Job và lịch sao lưu).

### 1. Trên RHEL / CentOS / Rocky Linux / AlmaLinux (7, 8, 9):
```bash
curl -fSL -o /tmp/zb.rpm https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.18/zimbra-backup-0.3.18-1.noarch.rpm && sudo rpm -Uvh /tmp/zb.rpm && rm -f /tmp/zb.rpm
```
*(Cài đặt trực tiếp gói đơn qua `rpm -Uvh`, hoàn toàn không động tới repo hệ điều hành hay bất kỳ lệnh cập nhật hệ thống nào).*

### 2. Trên Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
```bash
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.18/zimbra-backup_0.3.18-1_all.deb && sudo dpkg -i /tmp/zb.deb && rm -f /tmp/zb.deb
```
*(Tuyệt đối không chạy `apt update` hay cập nhật hệ điều hành trên máy chủ Zimbra; từ v0.3.18 gói DEB chỉ phụ thuộc `mawk | gawk` có sẵn mặc định trên Ubuntu nên `dpkg -i` cài thành công ngay không cần `apt`).*

### 3. Khởi động giao diện & Kiểm tra cập nhật:
```bash
zimbra-backup                # Mở Menu TUI (mục 8 để kiểm tra/cập nhật phiên bản)
zimbra-backup update --check # Chỉ kiểm tra xem đã là bản mới nhất chưa
sudo zimbra-backup update    # Kiểm tra & hỏi xác nhận [y/N] trước khi cập nhật riêng zimbra-backup
```

> **Lưu ý:** Máy chủ đang cài `v0.3.17` trở về trước cần nâng cấp thủ công **1 lần** lên `v0.3.18` bằng lệnh ở mục 1 hoặc 2; từ `v0.3.18` trở đi có thể cập nhật ngay trong TUI hoặc CLI.

---

## 🗑️ Gỡ cài đặt hoàn toàn (Uninstall)

Quá trình gỡ bỏ tự động xóa binary, thư viện, khối cron riêng `# BEGIN zimbra-backup .. # END zimbra-backup` và `/var/lib/zimbra-backup`, **cam kết không chạm tới** `/opt/zimbra`, dịch vụ Zimbra đang chạy, cron hệ thống Zimbra (`# ZIMBRASTART..# ZIMBRAEND`) và toàn bộ dữ liệu sao lưu (`/home/backup`, ổ ngoài...):

```bash
# Trên RHEL / CentOS / Rocky Linux / AlmaLinux:
sudo rpm -e zimbra-backup

# Trên Ubuntu / Debian (gỡ sạch cả file cấu hình logrotate):
sudo dpkg -P zimbra-backup
# (Hoặc dùng 'sudo dpkg -r zimbra-backup' nếu muốn giữ lại /etc/logrotate.d/zimbra-backup)
```

*(Nếu đang có tiến trình backup/restore giữ `operation.lock`, lệnh gỡ sẽ tự động chặn để tránh làm gián đoạn tác vụ đang chạy).*

---

## 🖥️ Giao diện tương tác TUI trực quan (Pure ASCII)

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.18) - mail.domain.com
  >> MAIN MENU
============================================================
  Job Storage : /home/backup (mount: no) | Jobs: 2 | Custom Restore: (not set)
------------------------------------------------------------
  1) Jobs & Crontab Schedule   (Create, Edit, Enable/Disable, Delete)
  2) Run Backup Now            (Run Job, Force Full, Single Account)
  3) Restore from Backup Job   (Select Configured Job -> Snapshot)
  4) Restore from Custom Dir   (Configure / Scan Other Directory)
  5) Backup Catalog & Verify   (Job Snapshots, Search Users, SHA-256)
  6) Global Settings & Alerts  (Storage, Disk Limits, Alerts)
  7) View Logs
  8) Check for Updates         (Compare with latest GitHub release)
  0) Exit
============================================================
Select [0-8]:
```

---

## 📊 Bảng so sánh tính năng vượt trội

| Tính năng cốt lõi | Script rời thông thường | Zimbra Network Edition ($$$) | `zimbra-backup` v0.3.18 |
|---|:---:|:---:|:---:|
| **Chi phí bản quyền** | Miễn phí | Rất đắt đỏ theo năm | **100% Miễn phí & Open Source (MIT)** |
| **Gói cài đặt chuẩn OS** | ❌ Không có (file rời) | Có | **✅ Đầy đủ gói RPM & DEB** |
| **Forever Forward Incremental (FFI)** | ❌ Không hỗ trợ | Có | **✅ Tự động gộp cục bộ, tiết kiệm tối đa đĩa/CPU** |
| **Synthetic Full Backup (SFB)** | ❌ Không hỗ trợ | Có | **✅ Tổng hợp Full cục bộ 0 tải JVM Zimbra** |
| **Thư mục tự định danh trực quan** | ❌ Đặt tên lộn xộn | Cố định nội bộ | **✅ Tự tạo folder theo chiến lược backup** |
| **Giao diện Menu TUI tương tác** | ❌ Chỉ chạy CLI | Web Admin GUI | **✅ Menu TUI ASCII 1 chạm trực quan** |
| **Kiểm tra & tự cập nhật (`update`)** | ❌ Tải đè thủ công | Qua gói Zimbra | **✅ Kiểm tra GitHub + hỏi `[y/N]` + SHA-256** |
| **Lưu trữ từ xa (FTP / SFTP)** | ❌ Cần viết thêm script | ⚠️ Cần cấu hình ngoài | **✅ Port 21/22 tự động đẩy offsite** |
| **Tốc độ (Khử JVM Cold-Start)** | ❌ Bật/tắt Java liên tục | Tích hợp sẵn | **✅ Cache Auth Token & LDAP In-memory** |
| **Hàng đợi đa luồng không nghẽn** | ❌ Xử lý tuần tự | Có | **✅ Non-blocking Worker Pool** |
| **Thông báo Email & Telegram** | ⚠️ Thô sơ hoặc lỗi | Tích hợp sẵn | **✅ Chuẩn hóa chi tiết mọi thông số** |
| **Bảo toàn tiếng Việt UTF-8** | ⚠️ Thường lỗi font có dấu | ✅ Có | **✅ Giải mã Base64 RFC 2849 chuẩn xác** |
| **Bảo toàn quyền Admin & Mật khẩu** | ❌ Thường thiếu sót | ✅ Có | **✅ 100% Đầy đủ SSHA/SHA512 & Admin** |
| **Bảo toàn nhóm (Distribution Lists)** | ❌ Bỏ qua | ✅ Có | **✅ Đầy đủ Attributes, Aliases & Members** |
| **Xử lý tài khoản đóng (Closed)** | ❌ Lỗi REST Inactive | ✅ Có | **✅ Cơ chế Deferred Status thông minh** |
| **Cơ chế an toàn chống xóa nhầm** | ❌ Nguy hiểm | Cảnh báo Web | **✅ Bắt buộc `--yes` & gõ `RESET`** |
| **Kiểm tra toàn vẹn dữ liệu** | ⚠️ Chỉ đo kích thước | Có | **✅ Mã băm SHA-256 từng tài khoản** |

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.18

1. **Kiểm Tra & Tự Cập Nhật Phiên Bản Có Xác Nhận (`TUI Mục 8` & `zimbra-backup update`)**:
   - Bổ sung mục **`8) Check for Updates`** trong Main Menu TUI và lệnh **`zimbra-backup update [--check] [--yes]`** trên CLI.
   - Tự động đối chiếu phiên bản `VERSION-RELEASE` với bản mới nhất trên GitHub Releases (có cơ chế fallback qua redirect + `SHA256SUMS` khi gặp rate-limit API).
   - Luôn hiển thị chi tiết phiên bản cũ/mới và hỏi **`Update now? [y/N]`** (mặc định **No**) trước khi thực hiện.
   - Cơ chế **Root Supervisor (exit 42)**: tiến trình `root` bàn giao giao diện về user `zimbra` như thường lệ; khi bạn chọn **Yes**, `root` giữ khóa `operation.lock`, tải gói về thư mục riêng của `root`, kiểm tra mã **SHA-256** + tên gói, rồi cài **chỉ riêng gói `zimbra-backup`** qua `rpm -Uvh` hoặc `dpkg -i`.
   - **Tuyệt đối an toàn cho server email**: không chạy `apt update`, `dnf update`, `yum update`, không động tới `/opt/zimbra` hay dịch vụ mail đang chạy, giữ nguyên toàn bộ cấu hình Job & Crontab.

2. **Tương Thích Hoàn Hảo Ubuntu Zero-APT (`mawk | gawk`)**:
   - Chuẩn hóa toàn bộ biểu thức `awk` tương thích `mawk` (mặc định trên Ubuntu 18.04 / 20.04 / 22.04 LTS) và cập nhật phụ thuộc DEB thành `mawk | gawk`, giúp lệnh `dpkg -i` chạy thành công ngay trên Ubuntu mà không cần `apt`.

3. **Hỗ Trợ Forever Forward Incremental (FFI) & Synthetic Full Backup (SFB)**:
   - FFI kéo Full duy nhất 1 lần đầu, các lần sau kéo delta siêu nhẹ và tự động merge cục bộ khi vượt `KEEP_COUNT`.
   - SFB tổng hợp bản Full mới cục bộ từ chain và delta trước đó với 0 tải JVM lên Zimbra live, kèm thư mục tự định danh (`Forever-Forward-Incremental`, `Synthetic-Full-Backup`, `Standard-Incremental`, `Standard-Full`).

4. **Bảo Toàn Tuyệt Đối Chuẩn 100% Pure 7-bit ASCII & 306/306 Bài Kiểm Thử Đạt**:
   - Đạt 306/306 bài kiểm thử tự động đầu-cuối với 0 lỗi.
   - Toàn bộ 16 file đóng gói giữ vững 100% Pure 7-bit ASCII và chuẩn xuống dòng Unix LF (`\n`).

---

## 🏗️ Kiến trúc & Tính năng cốt lõi

1. **Giao diện Menu TUI tiếng Anh tinh gọn (100% Pure 7-bit ASCII)**:
   - Tự động khởi tạo cấu hình chuẩn trong nền với thư mục lưu trữ mặc định `/home/backup`.
   - **Tạo Job nhanh 6 bước đầy đủ**: `Job ID` -> `Chế độ (Full / Incremental)` -> `Đường dẫn lưu trữ & Kiểm tra mount riêng` -> `Lịch chạy (HH:MM)` -> `Chu kỳ chuỗi & Số bản lưu giữ` -> `Cấu hình Remote Storage (FTP/SFTP)`.
   - **Chỉnh sửa Job 1 chạm**: Menu đánh số `1..11` hiển thị trực tiếp giá trị hiện tại của từng trường — bấm số mục cần sửa và bấm `s` để lưu.
   - Toàn bộ giao diện, CLI và log dùng bảng mã **7-bit ASCII thuần**, loại bỏ triệt để hiện tượng ô vuông `□` trên console VMware/Proxmox/PuTTY hoặc môi trường `LANG=C` của `cron`.

2. **Quản lý Đa Job & Đồng bộ Crontab tự động theo quyền `zimbra`**:
   - Tạo, xem, **chỉnh sửa (`edit`)**, bật/tắt, xóa và kích hoạt chạy ngay nhiều Job độc lập (`full` hoặc `incremental`).
   - Tự động chuyển quyền `runuser -u zimbra` và tự động cập nhật khối `# BEGIN zimbra-backup ... # END zimbra-backup` trong `crontab` của user `zimbra` mà không chạm vào khối `# ZIMBRASTART..# ZIMBRAEND` của hệ thống Zimbra.

3. **Tùy chỉnh ngày tháng & lịch chạy linh hoạt**:
   - Hỗ trợ lịch **Hằng ngày** (`HH:MM`), **Hằng tuần** (chọn thứ `0-6` + `HH:MM`), **Theo ngày/tháng cụ thể** (ngày `1-31`, tháng `*` hoặc `1-12` + `HH:MM`), biểu thức **Cron 5 trường**, hoặc tắt lịch tự động (`off`).

4. **Tách riêng 3 phân vùng lưu trữ rút gọn dưới thư mục gốc (`/home/backup`)**:
   - `full/full-DD-MM-YYYY/`
   - `incremental/full-DD-MM-YYYY/` & `incremental/001-incremental-DD-MM-YYYY/`
   - `account/backup-<email>-DD-MM-YYYY/` (sao lưu lẻ từng tài khoản)

5. **Lưu trữ Từ xa FTP / SFTP theo từng Job & Tự động Dọn dẹp Bản lưu Cũ**:
   - Mỗi Job tự chọn có đẩy FTP/SFTP hay không (`[y/N]`), cấu hình máy chủ, port (21/22), tài khoản và thư mục đích riêng.
   - Hỗ trợ FTPS (SSL/TLS) và SFTP qua SSH với backend `curl` tích hợp sẵn.
   - Quản lý số bản lưu FTP độc lập (`FTP_KEEP_COUNT`), tự động dọn dẹp file cũ trên FTP và bảo toàn 100% bản lưu cục bộ tại Local.
   - Chống Safe Links URL rewriting: loại bỏ tiền tố `://` trong thông báo, ngăn chặn Microsoft 365 Defender ATP làm vỡ layout email.

6. **Sao lưu & Khôi phục chuẩn xác 100% dữ liệu Zimbra**:
   - Giải mã dòng gập LDIF chuẩn RFC 2849 + Base64 UTF-8, bảo toàn tên hiển thị tiếng Việt (`displayName`), mật khẩu băm (`userPassword`), hạn ngạch (`zimbraMailQuota`), Alias, thành viên Distribution List (`zmprov -l gdlm`), chữ ký HTML/text (`zmprov -l gsig`), quyền Admin và bộ lọc Sieve nhiều dòng.
   - Thuộc tính đa trị (`zimbraMailForwardingAddress`) được bảo toàn với tiền tố `+` khi khôi phục để không ghi đè dữ liệu cũ.
   - Tài khoản `closed` được khôi phục qua cơ chế *Deferred Status* (tạm thời đặt `maintenance` khi nạp mailbox để tránh lỗi REST `account.ACCOUNT_INACTIVE`, sau đó hoàn trả `closed`).

7. **Khôi phục linh hoạt đa kịch bản**:
   - Khôi phục **Toàn bộ máy chủ**, **Theo Domain**, hoặc **Chọn 1 / nhiều User cụ thể**.
   - Hỗ trợ khôi phục sang **tài khoản đích khác** (`--target-user`), khôi phục vào **thư mục con riêng** (`/Restore_<timestamp>`), chọn riêng **Hộp thư** hoặc **Cấu hình LDAP**, và chạy thử **`--dry-run`**.
   - Hỗ trợ quét đệ quy khôi phục từ bất kỳ ổ cứng ngoài, NAS, hoặc thư mục backup của script cũ.

8. **Tối ưu Hiệu năng Vượt trội & Khử Bão Java JVM**:
   - Streaming native REST qua SOAP `DelegateAuthRequest`: cấp token trong ~10ms, curl stream trực tiếp từ cổng mailbox (8443/443), hạ tải CPU từ 85%+ xuống dưới 2%.
   - Xuất metadata LDAP hàng loạt bằng `zmprov -l -f` (1 tiến trình JVM duy nhất thay vì 140+ tiến trình tuần tự).
   - Kiểm tra thuộc tính chữ ký trước khi gọi `zmprov -l gsig` (khử 70+ JVM cold-start).
   - Tự động hạ độ ưu tiên tiến trình (`nice -n 19`, `ionice -c 2 -n 7`), tuyệt đối không chiếm tài nguyên production.

9. **Cơ chế An toàn & Xác thực Toàn vẹn Dữ liệu**:
   - Khóa độc quyền `flock` chống chạy trùng lặp giữa các Job và tiến trình khôi phục.
   - Xác thực toàn vẹn bằng `tar -tzf`, `gzip -t` và đối soát mã băm SHA-256 qua file `manifest` cho từng tài khoản.
   - Cơ chế bảo vệ khôi phục: bắt buộc cờ `--yes` trên CLI hoặc gõ xác nhận `RESET` trong TUI để ngăn ngừa thao tác nhầm lẫn.

---

## 📖 Cẩm nang dòng lệnh CLI tóm tắt

Xem trợ giúp chi tiết:
```bash
zimbra-backup --help
```

### 1. Tạo và quản lý Job tự động:
```bash
# Tạo Job Forever Forward Incremental (FFI) giữ 7 điểm khôi phục:
zimbra-backup job add daily-ffi --type forever_incremental --schedule daily --hour 1 --minute 0 --keep 7 --parallel 4

# Tạo Job Synthetic Full Backup (SFB) giữ 2 chuỗi (tổng hợp Full cục bộ hằng tuần):
zimbra-backup job add daily-sfb --type synthetic_full --schedule daily --hour 1 --minute 30 --full-cycle weekly --full-cycle-value 0 --keep 2 --parallel 4

# Tạo Job Incremental truyền thống:
zimbra-backup job add daily-incr --type incremental --schedule daily --hour 2 --minute 0 --full-cycle max_incr --full-cycle-value 6 --keep 2 --parallel 4

# Kích hoạt chạy ngay Job hoặc kích hoạt tạo Synthetic Full tức thời:
zimbra-backup job run daily-ffi
zimbra-backup job run daily-sfb --synthetic-full
```

### 2. Sao lưu lẻ tài khoản khẩn cấp:
```bash
zimbra-backup backup user "giamdoc@domain.com,ketoan@domain.com"
```

### 3. Khôi phục dữ liệu (Restore):
```bash
# Khôi phục 1 tài khoản với cơ chế skip (không mất mail mới nhận):
zimbra-backup restore --from 1 --users "user@domain.com" --mode skip --yes

# Bàn giao hòm thư nhân viên cũ vào thư mục con của quản lý:
zimbra-backup restore --from 1 --users "nv_cu@domain.com" --target-user "quanly@domain.com" --only mailbox --mode subfolder --subfolder-name "BanGiao_NVCU" --yes

# Khôi phục toàn bộ server từ ổ gắn ngoài /backup:
zimbra-backup restore --dir /backup --from 1 --all --mode skip --yes
```

### 4. Kiểm tra & Cập nhật phiên bản:
```bash
# Kiểm tra bản mới nhất trên GitHub (không tự cài):
zimbra-backup update --check

# Kiểm tra và hỏi xác nhận [y/N] trước khi cập nhật riêng gói zimbra-backup:
sudo zimbra-backup update
```

> 📄 **Xem hướng dẫn sử dụng chi tiết toàn diện tại**: [`HUONG_DAN_SU_DUNG.md`](HUONG_DAN_SU_DUNG.md).

---

## 🛠️ Đóng gói & Kiểm thử từ mã nguồn

Chạy bộ kiểm thử tự động đầu-cuối 306 bài test:
```bash
bash tests/run_tests.sh
```

Đóng gói binary `.deb` và `.rpm` bằng công cụ Python có sẵn:
```bash
python packaging/build_deb.py
python packaging/build_rpm.py
```

---

## ☕ Ủng hộ tác giả (Buy Me a Coffee)

Nếu công cụ `zimbra-backup` giúp ích cho công việc quản trị hệ thống và bảo vệ dữ liệu Zimbra của bạn, bạn có thể ủng hộ tác giả một ly cà phê qua các kênh dưới đây:

| 💎 USDT (BEP20) | 🪙 Bitcoin (BTC) |
|:---:|:---:|
| <img src="docs/images/donate-usdt-bsc.png" width="220" alt="USDT (BSC)"> | <img src="docs/images/donate-btc.png" width="220" alt="Bitcoin (BTC)"> |
| **Mạng BSC (BEP20)**<br>`0x1b1817cc4f6eb49adb051c25d0f82e77f66c8514` | **Mạng BTC**<br>`14enMJBiXgk7jLc187qXB5qucBBSfsYuVG` |

---

## 📄 Bản quyền (License)

Dự án được phân phối dưới giấy phép mã nguồn mở [MIT License](LICENSE). Tự do sử dụng, chỉnh sửa và triển khai trong môi trường doanh nghiệp.
