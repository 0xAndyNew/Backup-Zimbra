# Zimbra Backup & Restore (`zimbra-backup` v0.3.6)

[![Release](https://img.shields.io/github/v/release/0xAndyNew/Backup-Zimbra?color=brightgreen&label=Release)](https://github.com/0xAndyNew/Backup-Zimbra/releases)
[![CI](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml/badge.svg)](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zimbra OSE](https://img.shields.io/badge/Zimbra_OSE-8.8.15_%7C_9_%7C_10-orange.svg)](https://www.zimbra.com/)
[![OS Support](https://img.shields.io/badge/OS-Ubuntu_%7C_RHEL_%7C_CentOS_%7C_Rocky_%7C_Alma-blue.svg)]()
[![Packages](https://img.shields.io/badge/Packages-RPM_%7C_DEB-success.svg)]()
[![Bash](https://img.shields.io/badge/Bash-4.2%2B-lightgrey.svg)]()
[![Encoding](https://img.shields.io/badge/Encoding-100%25_Pure_7--bit_ASCII-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-149%2F149_Passing-brightgreen.svg)]()

> 🌐 **[English Documentation](README_EN.md)** | **[Tài liệu Tiếng Việt](README.md)** | **[Hướng dẫn sử dụng chi tiết từng bước](HUONG_DAN_SU_DUNG.md)**

Bộ công cụ đóng gói `.rpm` và `.deb` hợp nhất chuyên nghiệp dành cho máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** trên **Ubuntu 18.04, 20.04, 22.04 LTS** và **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**. Trang bị **Giao diện Menu tương tác TUI (100% Pure 7-bit ASCII — không bao giờ lỗi font `□` trên mọi SSH / VM Console)** cùng hệ thống **CLI tự động hóa** đầy đủ và cơ chế an toàn `--yes`.

---

## ⚡ Cài đặt nhanh trong 1 dòng lệnh (Quick Install)

### Trên RHEL / CentOS / Rocky Linux / AlmaLinux (7, 8, 9):
```bash
sudo dnf install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.6/zimbra-backup-0.3.6-1.noarch.rpm
# Hoặc trên CentOS 7:
# sudo yum install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.6/zimbra-backup-0.3.6-1.noarch.rpm
```

### Trên Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
```bash
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.6/zimbra-backup_0.3.6-1_all.deb && sudo apt update && sudo apt install -y /tmp/zb.deb && rm -f /tmp/zb.deb
```

Khởi động giao diện quản lý ngay:
```bash
zimbra-backup
```

---

## 🖥️ Giao diện tương tác TUI trực quan (Pure ASCII)

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.6) - mail.domain.com
  >> MAIN MENU
============================================================
  Job Storage : /home/backup (mount: no) | Jobs: 2 | Custom Restore: (not set)
------------------------------------------------------------
  1) Jobs & Crontab Schedule   (Create, Edit, Enable/Disable, Delete)
  2) Run Backup Now            (Run Job, Force Full, Single Account)
  3) Restore from Backup Job   (Select Configured Job -> Snapshot)
  4) Restore from Custom Dir   (Configure / Scan Other Directory)
  5) Backup Catalog & Verify   (Job Snapshots, Search Users, SHA-256)
  6) Global Settings & Alerts  (Storage Paths, Disk Limits, Telegram, Email)
  7) View Logs
  0) Exit
============================================================
Select [0-7]:
```

---

## 📊 Bảng so sánh tính năng vượt trội

| Tính năng cốt lõi | Script rời thông thường | Zimbra Network Edition ($$$) | `zimbra-backup` v0.3.6 |
|---|:---:|:---:|:---:|
| **Chi phí bản quyền** | Miễn phí | Rất đắt đỏ theo năm | **100% Miễn phí & Open Source (MIT)** |
| **Gói cài đặt chuẩn OS** | ❌ Không có (file rời) | Có | **✅ Đầy đủ gói RPM & DEB** |
| **Giao diện Menu TUI tương tác** | ❌ Chỉ chạy CLI | Web Admin GUI | **✅ Menu TUI ASCII 1 chạm trực quan** |
| **Tốc độ (Khử JVM Cold-Start)** | ❌ Bật/tắt Java liên tục | Tích hợp sẵn | **✅ Cache Auth Token & LDAP In-memory** |
| **Hàng đợi đa luồng không nghẽn** | ❌ Xử lý tuần tự | Có | **✅ Non-blocking Worker Pool** |
| **Thông báo Email & Telegram** | ⚠️ Thô sơ hoặc lỗi | Tích hợp sẵn | **✅ Đầy đủ mức all/failure & Test gửi** |
| **Bảo toàn tiếng Việt UTF-8** | ⚠️ Thường lỗi font có dấu | ✅ Có | **✅ Giải mã Base64 RFC 2849 chuẩn xác** |
| **Bảo toàn quyền Admin & Mật khẩu** | ❌ Thường thiếu sót | ✅ Có | **✅ 100% Đầy đủ SSHA/SHA512 & Admin** |
| **Bảo toàn nhóm (Distribution Lists)** | ❌ Bỏ qua | ✅ Có | **✅ Đầy đủ Attributes, Aliases & Members** |
| **Xử lý tài khoản đóng (Closed)** | ❌ Lỗi REST Inactive | ✅ Có | **✅ Cơ chế Deferred Status thông minh** |
| **Cơ chế an toàn chống xóa nhầm** | ❌ Nguy hiểm | Cảnh báo Web | **✅ Bắt buộc `--yes` & gõ `RESET`** |
| **Kiểm tra toàn vẹn dữ liệu** | ⚠️ Chỉ đo kích thước | Có | **✅ Mã băm SHA-256 từng tài khoản** |

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.6

1. **Cơ chế Thông báo Email & Telegram Toàn diện**:
   - Hỗ trợ lựa chọn mức kích hoạt `EMAIL_ALERT_LEVEL`: `all` (gửi thông báo cho mọi bản sao lưu bao gồm thành công) hoặc `failure` (chỉ gửi khi có cảnh báo/lỗi).
   - Bổ sung lệnh kiểm tra gửi thử email và telegram ngay lập tức: `zimbra-backup notify test-email` và `zimbra-backup notify test-telegram` (hoặc phím số `9` và `8` trong Menu Cài đặt TUI).
   - Tự động bắt lỗi và ghi chi tiết `stderr` từ Postfix/sendmail vào log giúp khắc phục nhanh sự cố máy chủ thư không gửi được mail ra ngoài.
   - Tự động gửi thông báo cho cả các tác vụ sao lưu tài khoản lẻ (Ad-hoc account backup).

1. **Menu TUI tiếng Anh tinh gọn, hiển thị chuẩn trên mọi Terminal**:
   - Tự động khởi tạo cấu hình chuẩn trong nền với thư mục lưu trữ mặc định `/home/backup`.
   - **Tạo Job nhanh 5 bước đầy đủ**: `Job ID` -> `Chế độ (Full / Incremental)` -> `Đường dẫn lưu trữ & Kiểm tra mount riêng` -> `Lịch chạy (HH:MM)` -> `Số bản lưu giữ`.
   - **Chỉnh sửa Job 1 chạm**: Menu đánh số `1..10` hiển thị trực tiếp giá trị hiện tại của từng trường — bấm số mục cần sửa và bấm `s` để lưu.
   - Toàn bộ giao diện, CLI và log dùng bảng mã **7-bit ASCII thuần**, loại bỏ triệt để hiện tượng ô vuông `□` trên console VMware/Proxmox/PuTTY hoặc môi trường `LANG=C` của `cron`.

2. **Quản lý Đa Job & Đồng bộ Crontab tự động theo quyền `zimbra`**:
   - Tạo, xem, **chỉnh sửa (`edit`)**, bật/tắt, xóa và kích hoạt chạy ngay nhiều Job độc lập (`full` hoặc `incremental`).
   - Tự động chuyển quyền `runuser -u zimbra` và tự động cập nhật khối `# BEGIN zimbra-backup ... # END zimbra-backup` trong `crontab` của user `zimbra` mà không chạm vào khối `# ZIMBRASTART..# ZIMBRAEND` của hệ thống Zimbra.

3. **Tùy chỉnh ngày tháng & lịch chạy linh hoạt**:
   - Hỗ trợ lịch **Hằng ngày** (`HH:MM`), **Hằng tuần** (chọn thứ `0-6` + `HH:MM`), **Theo ngày/tháng cụ thể** (ngày `1-31`, tháng `*` hoặc `1-12` + `HH:MM`), biểu thức **Cron 5 trường**, hoặc tắt lịch tự động (`off`).

4. **Tách riêng 3 phân vùng lưu trữ dưới thư mục gốc (`/home/backup`)**:
   - `full/<job_id>/backup-full-DD-MM-YYYY_HHMMSS/`
   - `incremental/<job_id>/chain-DD-MM-YYYY_HHMMSS/000_backup-full-...` & `001_backup-incremental-...`
   - `account/backup-<email>-DD-MM-YYYY_HHMMSS/` (sao lưu lẻ từng tài khoản)

5. **Sao lưu & Khôi phục chuẩn xác 100% dữ liệu Zimbra**:
   - Giải mã dòng gập LDIF chuẩn RFC 2849 + Base64 UTF-8, bảo toàn tên hiển thị tiếng Việt (`displayName`), mật khẩu băm (`userPassword`), hạn ngạch (`zimbraMailQuota`), Alias, thành viên Distribution List (`zmprov -l gdlm`), chữ ký HTML/text (`zmprov -l gsig`), quyền Admin và bộ lọc Sieve nhiều dòng.
   - Thuộc tính đa trị (`zimbraMailForwardingAddress`) được bảo toàn với tiền tố `+` khi khôi phục để không ghi đè dữ liệu cũ.
   - Tài khoản `closed` được khôi phục qua cơ chế *Deferred Status* (tạm thời đặt `maintenance` khi nạp mailbox để tránh lỗi REST `account.ACCOUNT_INACTIVE`, sau đó hoàn trả `closed`).

6. **Khôi phục linh hoạt đa kịch bản**:
   - Khôi phục **Toàn bộ máy chủ**, **Theo Domain**, hoặc **Chọn 1 / nhiều User cụ thể**.
   - Hỗ trợ khôi phục sang **tài khoản đích khác** (`--target-user`), khôi phục vào **thư mục con riêng** (`/Restore_<timestamp>`), chọn riêng **Hộp thư** hoặc **Cấu hình LDAP**, và chạy thử **`--dry-run`**.
   - Hỗ trợ quét đệ quy khôi phục từ bất kỳ ổ cứng ngoài, NAS, hoặc thư mục backup của script cũ.

---

## 📖 Cẩm nang dòng lệnh CLI tóm tắt

Xem trợ giúp chi tiết:
```bash
zimbra-backup --help
```

### 1. Tạo và quản lý Job tự động:
```bash
# Tạo Job Incremental mỗi đêm 01:30, Chủ Nhật mở Full mới, giữ 2 chuỗi (~14 ngày):
zimbra-backup job add daily-incr --type incremental --schedule daily --hour 1 --minute 30 --full-cycle weekly --full-cycle-value 0 --keep 2 --parallel 4

# Sửa giờ chạy sang 02:00:
zimbra-backup job edit daily-incr --hour 2 --minute 0

# Chạy ngay Job:
zimbra-backup job run daily-incr
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

Chạy bộ kiểm thử tự động đầu-cuối 136 bài test:
```bash
bash tests/run_tests.sh
```

Đóng gói binary `.deb` và `.rpm` bằng công cụ Python có sẵn:
```bash
python packaging/build_deb.py
python packaging/build_rpm.py
```

---

## 📄 Bản quyền (License)

Dự án được phân phối dưới giấy phép mã nguồn mở [MIT License](LICENSE). Tự do sử dụng, chỉnh sửa và triển khai trong môi trường doanh nghiệp.
