# Zimbra Backup & Restore (`zimbra-backup` v0.3.17)

[![Release](https://img.shields.io/github/v/release/0xAndyNew/Backup-Zimbra?color=brightgreen&label=Release)](https://github.com/0xAndyNew/Backup-Zimbra/releases)
[![CI](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml/badge.svg)](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zimbra OSE](https://img.shields.io/badge/Zimbra_OSE-8.8.15_%7C_9_%7C_10-orange.svg)](https://www.zimbra.com/)
[![OS Support](https://img.shields.io/badge/OS-Ubuntu_%7C_RHEL_%7C_CentOS_%7C_Rocky_%7C_Alma-blue.svg)]()
[![Packages](https://img.shields.io/badge/Packages-RPM_%7C_DEB-success.svg)]()
[![Bash](https://img.shields.io/badge/Bash-4.2%2B-lightgrey.svg)]()
[![Encoding](https://img.shields.io/badge/Encoding-100%25_Pure_7--bit_ASCII-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-238%2F238_Passing-brightgreen.svg)]()

> 🌐 **[English Documentation](README_EN.md)** | **[Tài liệu Tiếng Việt](README.md)** | **[Hướng dẫn sử dụng chi tiết từng bước](HUONG_DAN_SU_DUNG.md)**

Bộ công cụ đóng gói `.rpm` và `.deb` hợp nhất chuyên nghiệp dành cho máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** trên **Ubuntu 18.04, 20.04, 22.04 LTS** và **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**. Trang bị **Giao diện Menu tương tác TUI (100% Pure 7-bit ASCII — không bao giờ lỗi font `□` trên mọi SSH / VM Console)** cùng hệ thống **CLI tự động hóa** đầy đủ và cơ chế an toàn `--yes`.

---

## ⚡ Cài đặt nhanh trong 1 dòng lệnh (Quick Install)

### Trên RHEL / CentOS / Rocky Linux / AlmaLinux (7, 8, 9):
```bash
sudo dnf install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.17/zimbra-backup-0.3.17-1.noarch.rpm
# Hoặc trên CentOS 7:
# sudo yum install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.17/zimbra-backup-0.3.17-1.noarch.rpm
```

### Trên Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
```bash
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.17/zimbra-backup_0.3.17-1_all.deb && sudo dpkg -i /tmp/zb.deb && rm -f /tmp/zb.deb
```

Khởi động giao diện quản lý ngay:
```bash
zimbra-backup
```

---

## 🖥️ Giao diện tương tác TUI trực quan (Pure ASCII)

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.17) - mail.domain.com
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
  0) Exit
============================================================
Select [0-7]:
```

---

## 📊 Bảng so sánh tính năng vượt trội

| Tính năng cốt lõi | Script rời thông thường | Zimbra Network Edition ($$$) | `zimbra-backup` v0.3.17 |
|---|:---:|:---:|:---:|
| **Chi phí bản quyền** | Miễn phí | Rất đắt đỏ theo năm | **100% Miễn phí & Open Source (MIT)** |
| **Gói cài đặt chuẩn OS** | ❌ Không có (file rời) | Có | **✅ Đầy đủ gói RPM & DEB** |
| **Forever Forward Incremental (FFI)** | ❌ Không hỗ trợ | Có | **✅ Tự động gộp cục bộ, tiết kiệm tối đa đĩa/CPU** |
| **Synthetic Full Backup (SFB)** | ❌ Không hỗ trợ | Có | **✅ Tổng hợp Full cục bộ 0 tải JVM Zimbra** |
| **Thư mục tự định danh trực quan** | ❌ Đặt tên lộn xộn | Cố định nội bộ | **✅ Tự tạo folder theo chiến lược backup** |
| **Giao diện Menu TUI tương tác** | ❌ Chỉ chạy CLI | Web Admin GUI | **✅ Menu TUI ASCII 1 chạm trực quan** |
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

## 🌟 Điểm nổi bật trong phiên bản v0.3.17

1. **Hỗ Trợ Forever Forward Incremental (FFI)**:
   - Kéo Full từ máy chủ Zimbra duy nhất 1 lần đầu tiên. Toàn bộ các lần chạy sau chỉ kéo Incremental delta siêu nhẹ.
   - Khi vượt quá số điểm lưu trữ (`KEEP_COUNT`), hệ thống tự động gộp (merge) delta cũ nhất vào bản Full gốc ngay trên ổ cứng backup, đẩy mốc ngày của Full tiến lên và xóa delta cũ đã gộp.
   - Tiết kiệm tối đa băng thông mạng, I/O đĩa và giải phóng hoàn toàn áp lực tải lên máy chủ Zimbra live.

2. **Hỗ Trợ Synthetic Full Backup (SFB)**:
   - Khi đến chu kỳ tạo Full mới hoặc chạy với cờ `--synthetic-full`, hệ thống **không** kéo lại toàn bộ mailbox qua REST API/JVM của Zimbra.
   - Tự động tổng hợp (synthesize) bản Full mới độc lập ngay tại chỗ từ chuỗi backup trước đó và delta giao thời. Các hộp thư không có thư mới được hardlink/copy tức thời với 0 chi phí nén/giải nén.

3. **Cấu Trúc Thư Mục Tự Định Danh Trực Quan (Self-Describing Directories)**:
   - Tự động tạo thư mục lưu trữ mang tên chiến lược backup đang áp dụng để quản trị viên kiểm tra `df -h` hoặc `ls /home/backup` là nhận biết được ngay:
     - `/home/backup/incremental/Forever-Forward-Incremental`
     - `/home/backup/incremental/Synthetic-Full-Backup`
     - `/home/backup/incremental/Standard-Incremental`
     - `/home/backup/full/Standard-Full`
   - Tương thích ngược 100% với các bản sao lưu cũ.

4. **Nâng Cấp Wizard TUI & Lệnh CLI**:
   - Menu TUI 4 lựa chọn trực quan trong Wizard Tạo Job và Chỉnh sửa Job.
   - Hỗ trợ tham số CLI `--type forever_incremental` (alias: `ffi`), `--type synthetic_full` (alias: `sfb`), và cờ `--synthetic-full`.

5. **Bảo Toàn Tuyệt Đối Chuẩn 100% Pure 7-bit ASCII & 238/238 Bài Kiểm Thử Đạt**:
   - Đạt 238/238 bài kiểm thử tự động đầu-cuối với 0 lỗi.
   - Toàn bộ 15 file đóng gói giữ vững 100% Pure 7-bit ASCII và chuẩn xuống dòng Unix LF (`\n`).
   - Toàn bộ 15 file đóng gói giữ vững 100% Pure 7-bit ASCII và chuẩn xuống dòng Unix LF (`\n`).

---

## 🏗️ Kiến trúc & Tính năng cốt lõi

1. **Giao diện Menu TUI tiếng Anh tinh gọn (100% Pure 7-bit ASCII)**:
   - Tự động khởi tạo cấu hình chuẩn trong nền với thư mục lưu trữ mặc định `/home/backup`.
   - **Tạo Job nhanh 6 bước đầy đủ**: `Job ID` -> `Chế độ (Full / Incremental)` -> `Đường dẫn lưu trữ & Kiểm tra mount riêng` -> `Lịch chạy (HH:MM)` -> `Số bản lưu giữ` -> `Cấu hình Remote Storage (FTP/SFTP)`.
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

> 📄 **Xem hướng dẫn sử dụng chi tiết toàn diện tại**: [`HUONG_DAN_SU_DUNG.md`](HUONG_DAN_SU_DUNG.md).

---

## 🛠️ Đóng gói & Kiểm thử từ mã nguồn

Chạy bộ kiểm thử tự động đầu-cuối 238 bài test:
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
