# TÀI LIỆU HƯỚNG DẪN SỬ DỤNG CHI TIẾT `zimbra-backup` (v0.3.15)

Tài liệu này hướng dẫn **toàn diện từng bước, từng màn hình Menu TUI và từng câu lệnh CLI kèm ví dụ thực tế** cho bộ công cụ sao lưu & khôi phục hợp nhất **`zimbra-backup` v0.3.15** trên máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** chạy **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9** và **Ubuntu 18.04, 20.04, 22.04 LTS**.

---

## MỤC LỤC

1. [Tổng quan tính năng & Thành phần dữ liệu sao lưu](#1-tổng-quan-tính-năng--thành-phần-dữ-liệu-sao-lưu)
   - [1.1. Dữ liệu được bảo toàn đầy đủ khi sao lưu](#11-dữ-liệu-được-bảo-toàn-đầy-đủ-khi-sao-lưu)
   - [1.2. Cấu trúc thư mục chuẩn hóa trên máy chủ](#12-cấu-trúc-thư-mục-chuẩn-hóa-trên-máy-chủ)
   - [1.3. Cơ chế tối ưu hiệu năng, Remote Storage FTP/SFTP theo Job và tự động dọn dẹp v0.3.8](#13-cơ-chế-tối-ưu-hiệu-năng-remote-storage-ftpsftp-theo-job-và-tự-động-dọn-dẹp-v038)
2. [Cài đặt, Nâng cấp & Gỡ bỏ](#2-cài-đặt-nâng-cấp--gỡ-bỏ)
   - [2.1. Phân quyền thư mục lưu trữ cho user zimbra](#21-phân-quyền-thư-mục-lưu-trữ-cho-user-zimbra)
   - [2.2. Cài đặt trên RHEL / CentOS / Rocky / AlmaLinux (Gói RPM)](#22-cài-đặt-trên-rhel--centos--rocky--almalinux-gói-rpm)
   - [2.3. Cài đặt trên Ubuntu / Debian (Gói DEB)](#23-cài-đặt-trên-ubuntu--debian-gói-deb)
3. [Hướng dẫn chi tiết Giao diện tương tác TUI (`zimbra-backup`)](#3-hướng-dẫn-chi-tiết-giao-diện-tương-tác-tui-zimbra-backup)
   - [Khởi động & Màn hình Main Menu](#khởi-động--màn-hình-main-menu)
   - [Menu 1: Jobs & Crontab Schedule (Quản lý Job & Lịch tự động)](#menu-1-jobs--crontab-schedule-quản-lý-job--lịch-tự-động)
   - [Menu 2: Run Backup Now (Chạy sao lưu thủ công tức thời)](#menu-2-run-backup-now-chạy-sao-lưu-thủ-công-tức-thời)
   - [Menu 3: Restore from Backup Job (Khôi phục từ Job đã cấu hình)](#menu-3-restore-from-backup-job-khôi-phục-từ-job-đã-cấu-hình)
   - [Menu 4: Restore from Custom Dir (Khôi phục từ ổ cứng ngoài / NAS / bản cũ)](#menu-4-restore-from-custom-dir-khôi-phục-từ-ổ-cứng-ngoài--nas--bản-cũ)
   - [Menu 5: Backup Catalog & Verify (Tra cứu User, Kiểm tra SHA-256 & Dọn rác)](#menu-5-backup-catalog--verify-tra-cứu-user-kiểm-tra-sha-256--dọn-rác)
   - [Menu 6: Global Settings & Alerts (Cấu hình chung, Giới hạn đĩa & Cảnh báo)](#menu-6-global-settings--alerts-cấu-hình-chung-giới-hạn-đĩa--cảnh-báo)
   - [Menu 7: View Logs (Xem nhật ký thực thi)](#menu-7-view-logs-xem-nhật-ký-thực-thi)
4. [Cẩm nang toàn bộ câu lệnh CLI (`zimbra-backup <lệnh>`) & Ví dụ](#4-cẩm-nang-toàn-bộ-câu-lệnh-cli-zimbra-backup-lệnh--ví-dụ)
   - [4.1. Lệnh `init` — Khởi tạo cấu hình hệ thống](#41-lệnh-init--khởi-tạo-cấu-hình-hệ-thống)
   - [4.2. Lệnh `job` — CRUD Job, chỉnh sửa lịch & kích hoạt](#42-lệnh-job--crud-job-chỉnh-sửa-lịch--kích-hoạt)
   - [4.3. Lệnh `cron` — Xem & đồng bộ lại Crontab Zimbra](#43-lệnh-cron--xem--đồng-bộ-lại-crontab-zimbra)
   - [4.4. Lệnh `backup` — Xem danh sách, tra cứu User, verify SHA-256 & sao lưu lẻ](#44-lệnh-backup--xem-danh-sách-tra-cứu-user-verify-sha-256--sao-lưu-lẻ)
   - [4.5. Lệnh `restore` — Khôi phục chuyên sâu bằng dòng lệnh](#45-lệnh-restore--khôi-phục-chuyên-sâu-bằng-dòng-lệnh)
   - [4.6. Cơ chế an toàn `--yes` và các cờ bảo vệ dữ liệu](#46-cơ-chế-an-toàn---yes-và-các-cờ-bảo-vệ-dữ-liệu)
   - [4.7. Lệnh `status` & `logs` — Trạng thái hệ thống và xem Log](#47-lệnh-status--logs--trạng-thái-hệ-thống-và-xem-log)
   - [4.8. Lệnh `notify` — Kiểm tra thông báo Email và Telegram](#48-lệnh-notify--kiểm-tra-thông-báo-email-và-telegram)
5. [Các kịch bản thực chiến hay gặp nhất (Step-by-Step)](#5-các-kịch-bản-thực-chiến-hay-gặp-nhất-step-by-step)
   - [Kịch bản 1: Khôi phục toàn bộ server mới dựng (Disaster Recovery)](#kịch-bản-1-khôi-phục-toàn-bộ-server-mới-dựng-disaster-recovery)
   - [Kịch bản 2: Khôi phục hộp thư bị nhân viên xóa nhầm mà không mất mail mới](#kịch-bản-2-khôi-phục-hộp-thư-bị-nhân-viên-xóa-nhầm-mà-không-mất-mail-mới)
   - [Kịch bản 3: Bàn giao hòm thư nhân viên nghỉ việc vào thư mục con của Trưởng phòng](#kịch-bản-3-bàn-giao-hòm-thư-nhân-viên-nghỉ-việc-vào-thư-mục-con-của-trưởng-phòng)
   - [Kịch bản 4: Chiến lược sao lưu chuẩn Production cho doanh nghiệp (50 - 1000 Users)](#kịch-bản-4-chiến-lược-sao-lưu-chuẩn-production-cho-doanh-nghiệp-50---1000-users)
   - [Kịch bản 5: Khôi phục từ thư mục của tool cũ `auto_full_backup.sh`](#kịch-bản-5-khôi-phục-từ-thư-mục-của-tool-cũ-auto_full_backupsh)
6. [Lưu ý kỹ thuật quan trọng & Xử lý sự cố thường gặp](#6-lưu-ý-kỹ-thuật-quan-trọng--xử-lý-sự-cố-thường-gặp)

---

## 1. Tổng quan tính năng & Thành phần dữ liệu sao lưu

### 1.1. Dữ liệu được bảo toàn đầy đủ khi sao lưu

Mỗi bản sao lưu (`Full` hoặc `Incremental`) tự động thu thập và bảo vệ **2 nhóm dữ liệu toàn vẹn**:

1. **Cấu hình OpenLDAP & Metadata tài khoản**:
   - **Tên miền (Domains)**: Danh sách tên miền (`domains/domains.txt`) và thuộc tính domain.
   - **Danh sách tài khoản (Accounts)**: Tài khoản đang hoạt động (`accounts/active_accounts.txt` — tự động lọc sạch các tài khoản hệ thống `spam.*`, `ham.*`, `virus-quarantine.*`, `galsync.*`).
   - **Bảo toàn trạng thái tài khoản**: Giữ nguyên tài khoản ở trạng thái `locked`, `maintenance`, hoặc `closed`. Khi restore, tài khoản `closed` được nạp qua cơ chế *Deferred Status* (tạm thời đặt `maintenance` để tránh lỗi REST `account.ACCOUNT_INACTIVE`, sau đó hoàn trả đúng trạng thái `closed`).
   - **Mật khẩu gốc (`userPassword`)**: Lưu trữ nguyên vẹn chuỗi băm SSHA / SHA512 trong `passwords/<email>.shadow`. Khôi phục sang máy chủ mới người dùng đăng nhập ngay bằng mật khẩu cũ.
   - **Tên hiển thị tiếng Việt UTF-8 (`displayName`)** và hạn ngạch dung lượng (`zimbraMailQuota`): Xử lý nối dòng gập chuẩn RFC 2849 và giải mã Base64 UTF-8, không bao giờ bị lỗi font tiếng Việt có dấu.
   - **Thuộc tính đa trị (Multi-valued attributes)**: Các trường chuyển tiếp thư (`zimbraMailForwardingAddress`), quyền đại diện, thuộc tính mở rộng được bảo toàn và nạp với tiền tố `+` khi khôi phục để không ghi đè các giá trị cũ.
   - **Bí danh Email (Mail Aliases)**: Trích xuất và nạp lại đầy đủ từ `aliases/<email>.txt`.
   - **Nhóm gửi thư (Distribution Lists / DL)**: Trích xuất riêng biệt trong `dl/` (gồm thuộc tính hiển thị UTF-8, trạng thái, ẩn danh bạ GAL, bí danh nhóm, và toàn bộ thành viên).
   - **Chữ ký Email (Signatures)**: Sao lưu đồng thời cả chữ ký HTML và chữ ký Text thuần (`zmprov -l gsig`) trong `signatures/`.
   - **Bộ lọc thư (Sieve Filters)**: Giữ nguyên các kịch bản lọc thư nhiều dòng phức tạp trong `filters/`.
   - **Quyền Quản trị viên (Global Admin)**: Ghi nhận danh sách tài khoản Admin trong `admins/admins.txt` và tự động cấp lại cờ `zimbraIsAdminAccount TRUE` khi khôi phục.

2. **Dữ liệu Hộp thư (Mailbox Data qua HTTPS REST API nội bộ)**:
   - Toàn bộ Email ở mọi thư mục: Hộp thư đến (Inbox), Đã gửi (Sent), Thư nháp (Drafts), Thùng rác (Trash), và toàn bộ cây thư mục con người dùng tự tạo.
   - Danh bạ cá nhân (Contacts), Lịch hẹn/Lịch làm việc (Calendar), Công việc cần làm (Tasks), Cặp tài liệu (Briefcase).
   - File nén `.tgz` chuẩn REST của Zimbra MailboxServlet.
   - Danh mục mã băm **`manifest` (`SHA-256`)** cho từng file `.tgz` giúp phát hiện lỗi hỏng file (bit-rot) hoặc copy thiếu dung lượng.

---

### 1.2. Cấu trúc thư mục chuẩn hóa trên máy chủ

Khi cài đặt gói RPM/DEB, hệ thống phân tách rành mạch thành các phân vùng:

```text
/usr/bin/zimbra-backup                  # File nhị phân điều phối chính
/usr/libexec/zimbra-backup/*.sh         # Thư viện module chức năng (common, backup, restore, jobs...)
/etc/logrotate.d/zimbra-backup          # Cấu hình logrotate tự động nén & xoay vòng log

/var/lib/zimbra-backup/                 # Vùng trạng thái hệ thống (quyền 0700 zimbra:zimbra)
  ├── settings.conf                     # Cấu hình chung toàn cục (thư mục gốc, Telegram, Email, cảnh báo đĩa)
  ├── operation.lock                    # Khóa flock chống trùng lặp tiến trình
  ├── jobs/                             # Cấu hình từng Job sao lưu (<job_id>.conf)
  ├── logs/                             # Toàn bộ file log chi tiết theo từng phiên chạy
  └── run/                              # Token bảo mật tạm thời quyền 0600 (tự dọn sạch sau khi chạy)

/home/backup/                           # Thư mục lưu trữ backup mặc định (DEFAULT_BACKUP_DIR)
  ├── full/                             # [1] Phân loại các bản Backup FULL độc lập
  │     ├── full-01-11-2026/
  │     └── full-02-11-2026/
  ├── incremental/                      # [2] Phân loại các chuỗi Backup INCREMENTAL
  │     ├── full-01-11-2026/                  # Bản Full gốc đầu chuỗi
  │     ├── 001-incremental-02-11-2026/       # Bản Incr ngày 1
  │     └── 002-incremental-03-11-2026/       # Bản Incr ngày 2
  └── account/                          # [3] Phân loại các bản Backup LẺ theo Email người dùng
        ├── backup-giamdoc@hdll.vn-02-11-2026/             # Sao lưu 1 email
        └── backup-giamdoc@hdll.vn+1more-02-11-2026/       # Sao lưu nhiều email gộp
```

> **Quy tắc phân loại và đặt tên:**
> - Tên thư mục luôn mang mốc ngày tháng rút gọn **`DD-MM-YYYY`** theo giờ địa phương, không kèm chuỗi giờ phút giây hay thư mục trung gian `<job_id>` / `chain-*`, cực kỳ ngắn gọn và dễ quan sát qua `ls`. (Nếu chạy nhiều lần trong cùng một ngày sẽ tự động đánh hậu tố `_2`, `_3`...).
> - Cơ chế xoay vòng dọn dẹp (`KEEP_COUNT` và `FTP_KEEP_COUNT`) đối chiếu trực tiếp mốc thời gian thực (YYYY-MM-DD / `manifest`), không phụ thuộc vào thứ tự chữ cái, đảm bảo an toàn tuyệt đối khi bước qua tháng mới hoặc năm mới.

---

### 1.3. Cơ chế tối ưu hiệu năng, Remote Storage FTP/SFTP theo Job và tự động dọn dẹp v0.3.8

1. **Lưu trữ từ xa độc lập theo từng Job (Per-Job Remote Storage FTP / SFTP):**
   Mỗi Job có thể được cấu hình đẩy sang một máy chủ FTP/SFTP riêng biệt hoặc chỉ lưu cục bộ. Toàn bộ thông số (Protocol, Host, Port, User, Password ẩn, Thư mục từ xa `/<job_id>`, FTPS SSL) được tùy biến theo từng Job. Dữ liệu nén `.tar` được stream trực tiếp qua pipe `tar | curl -T -` giúp không tốn dung lượng đĩa tạm thời ở local. Mật khẩu được bảo vệ an toàn qua file tạm `0600` với `curl -K`, không lộ qua `ps aux`.
2. **Quản lý Bản lưu FTP Độc lập (`FTP_KEEP_COUNT`) & Tự động Dọn dẹp (`zb_prune_remote_storage`):**
   Số lượng bản lưu trên FTP (`FTP_KEEP_COUNT`) hoàn toàn độc lập với số bản lưu ở cục bộ (`KEEP_COUNT`). Sau khi upload thành công, hệ thống tự động quét thư mục Job trên FTP và gửi lệnh `DELE` (FTP) hoặc `rm` (SFTP) xóa các file `.tar` và `.manifest` cũ vượt quá `FTP_KEEP_COUNT`.
3. **Bảo toàn 100% Bản lưu Cục bộ tại Local (Tuyệt đối không xóa local khi đẩy FTP):**
   Bản sao lưu trên FTP chỉ là bản dự phòng ngoài site (offsite replica). Hệ thống tuyệt đối không xóa bản backup ở local sau khi upload sang FTP, giữ nguyên vẹn số bản local theo đúng `KEEP_COUNT` của Job.
4. **Chuẩn hóa Thông báo Toàn diện (Universal Notifications):**
   Mọi bản tin thông báo (Email và Telegram) của tất cả các Job sao lưu (Full, Incremental, Ad-hoc) đều hiển thị chi tiết: Tên Job/ID, Chế độ (FULL / INCREMENTAL), Số tài khoản (chi tiết có thư mới / không đổi), Tổng dung lượng sao lưu (MiB/GiB), Thời gian chạy (giây), Trạng thái đẩy FTP/SFTP từ xa, và Thư mục lưu cục bộ.
5. **Triệt tiêu độ trễ khởi động Java JVM (Zero JVM Cold-Start):**
   Tự động lưu và tái sử dụng `ZM_ADMIN_AUTH_TOKEN` trong tối đa 3600 giây qua file tạm quyền `0600` (tự động làm mới nếu gặp HTTP 401). Tránh việc bật/tắt máy ảo Java `zmprov`/`zmmailbox` hàng trăm lần cho từng tài khoản.
6. **Bộ điều phối luồng song song không nghẽn hàng đợi (Non-blocking Worker Pool):**
   Khắc phục giới hạn thiếu `wait -n` trên Bash 4.2 của CentOS 7 bằng vòng lặp kiểm tra trạng thái PID (`kill -0` và `wait "$pid"`). Khi một luồng hoàn thành hộp thư nhỏ, hệ thống lập tức nạp ngay tài khoản kế tiếp, duy trì hiệu suất tối đa của `PARALLEL_JOBS`.
7. **Bộ nhớ đệm LDAP (In-memory LDAP Cache):**
   Quét danh sách Domains, Accounts, Distribution Lists một lần duy nhất lúc bắt đầu phiên, giảm tải hơn 90% truy vấn trực tiếp vào OpenLDAP của Zimbra.
8. **Kiểm tra toàn vẹn có chọn lọc (Selective SHA-256 Verification):**
   Khi chạy khôi phục, hệ thống chỉ kiểm tra mã băm SHA-256 của đúng những tài khoản/domain được chỉ định, không tốn thời gian kiểm tra lại các tài khoản không liên quan trong bản backup.
9. **Cơ chế an toàn `--yes`:**
   Mọi thao tác khôi phục nguy hiểm (đặc biệt là `--mode reset`) trong môi trường không tương tác (Crontab/Script) bắt buộc phải có cờ `--yes`, tránh việc chạy nhầm làm ghi đè hòm thư người dùng.
10. **Cơ chế Thông báo Email & Telegram Đa Kênh (`EMAIL_ALERT_LEVEL`):**
   Cho phép cấu hình gửi email thông báo định kỳ cho cả những bản sao lưu thành công (`EMAIL_ALERT_LEVEL=all`) hoặc chỉ khi có sự cố (`EMAIL_ALERT_LEVEL=failure`). Bắt chi tiết lỗi `stderr` từ Postfix/sendmail, tích hợp lệnh kiểm tra tức thời `zimbra-backup notify test-email`, `test-telegram`, `test-ftp [job_id]` và tự động gửi thông báo cho cả sao lưu lẻ tài khoản.

---

## 2. Cài đặt, Nâng cấp & Gỡ bỏ

### 2.1. Phân quyền thư mục lưu trữ cho user zimbra

Mọi tiến trình của `zimbra-backup` đều tự động chuyển quyền từ `root` sang tài khoản hệ thống `zimbra` (`runuser -u zimbra`) để thao tác an toàn với mail store. Vì vậy, thư mục lưu trữ cần thuộc quyền sở hữu của user `zimbra`:

```bash
mkdir -p /home/backup
chown -R zimbra:zimbra /home/backup
chmod 700 /home/backup
```

*(Nếu dùng ổ cứng ngoài hoặc thư mục khác như `/backup`, `/mnt/nas`, hãy chạy lệnh `chown -R zimbra:zimbra <đường_dẫn>` tương tự).*

---

### 2.2. Cài đặt trên RHEL / CentOS / Rocky / AlmaLinux (Gói RPM)

Hỗ trợ các bản phân phối RHEL, CentOS, Rocky Linux, AlmaLinux phiên bản **7, 8, 9**:

**Tải gói RPM mới nhất (v0.3.15):**
```bash
curl -fSL -o zimbra-backup-0.3.15-1.noarch.rpm \
  https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.15/zimbra-backup-0.3.15-1.noarch.rpm
```

**Cài đặt mới hoặc nâng cấp:**
```bash
# Trên Rocky Linux / AlmaLinux / RHEL / CentOS 8, 9:
dnf install -y ./zimbra-backup-0.3.15-1.noarch.rpm

# Hoặc nâng cấp đè:
dnf upgrade -y ./zimbra-backup-0.3.15-1.noarch.rpm

# Trên CentOS 7 / RHEL 7:
yum install -y ./zimbra-backup-0.3.15-1.noarch.rpm

# Hoặc dùng lệnh RPM chuẩn:
rpm -Uvh ./zimbra-backup-0.3.15-1.noarch.rpm
```

**Gỡ cài đặt hoàn toàn:**
```bash
dnf remove -y zimbra-backup
# hoặc: rpm -e zimbra-backup
```
*Quá trình gỡ bỏ tự động dọn sạch khối cron `zimbra-backup` và thư mục `/var/lib/zimbra-backup`, cam kết không chạm tới dịch vụ Zimbra (`/opt/zimbra`) hay dữ liệu sao lưu của bạn.*

---

### 2.3. Cài đặt trên Ubuntu / Debian (Gói DEB)

Hỗ trợ **Ubuntu 18.04, 20.04, 22.04 LTS**:

**Tải gói DEB mới nhất (v0.3.15):**
```bash
curl -fSL -o zimbra-backup_0.3.15-1_all.deb \
  https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.15/zimbra-backup_0.3.15-1_all.deb
```

**Cài đặt qua `apt` (khuyến nghị tự động nạp dependencies):**
```bash
sudo apt update && sudo apt install -y ./zimbra-backup_0.3.15-1_all.deb
```

**Hoặc cài đặt qua `dpkg`:**
```bash
sudo dpkg -i ./zimbra-backup_0.3.15-1_all.deb
sudo apt-get install -f -y
```

**Gỡ cài đặt trên Ubuntu:**
```bash
sudo apt remove -y zimbra-backup
```

---

## 3. Hướng dẫn chi tiết Giao diện tương tác TUI (`zimbra-backup`)

### Khởi động & Màn hình Main Menu

Chỉ cần gõ lệnh:
```bash
zimbra-backup
```
Hệ thống tự khởi tạo cấu hình chuẩn trong nền (thư mục mặc định `/home/backup`, kiểm tra ổ mount `no`) và đưa bạn vào ngay **MAIN MENU**:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.6) - mail.hdll.vn
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

### Menu 1: Jobs & Crontab Schedule (Quản lý Job & Lịch tự động)

Bấm phím **`1`** từ Main Menu để quản lý danh sách các tác vụ sao lưu tự động:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.6) - mail.hdll.vn
  >> BACKUP JOBS & CRONTAB SCHEDULE
============================================================
ID               MODE         SCHEDULE             KEEP   PAR   EN   TARGET DIRECTORY
--------------------------------------------------------------------------------------------
daily-incr       incremental  daily (02:00)        2 ch   4     yes  (default: /home/backup)
weekly-full      full         weekly (dow=0 01:30) 4      2     yes  (default: /home/backup)
--------------------------------------------------------------------------------------------
  1) Create new backup job (6-step wizard)
  2) Edit existing job
  3) Enable / Disable a job
  4) Delete a job (keeps backup files on disk)
  5) View full job configuration details
  6) Synchronize crontab now (re-apply all enabled jobs)
  0) Back to main menu
============================================================
Select [0-6]:
```

#### Tạo Job mới nhanh chóng qua 6 bước (Bấm `1`):
1. **Bước 1: Nhập Job ID & Tên gợi nhớ**: Nhập mã định danh không dấu (ví dụ `prod-daily-incr`).
2. **Bước 2: Chọn Chế độ sao lưu**:
   - `1` — `full`: Bản sao lưu độc lập, đầy đủ 100% dữ liệu.
   - `2` — `incremental`: Chuỗi sao lưu gia tăng (1 bản Full gốc đầu chuỗi + các bản bồi đắp theo ngày).
3. **Bước 3: Chọn Đường dẫn lưu trữ & Kiểm tra ổ mount**:
   - Bấm Enter để dùng mặc định `/home/backup`, hoặc nhập đường dẫn riêng (ví dụ `/mnt/nas/zimbra`).
   - Nếu lưu trên ổ ngoài/NFS, chọn `yes` để bắt buộc kiểm tra trạng thái mountpoint trước khi chạy; nếu lưu thư mục cục bộ thì chọn `no`.
4. **Bước 4: Thiết lập Lịch chạy tự động**:
   - `1` — `daily`: Chạy hằng ngày, chỉ cần nhập `HH:MM` (ví dụ `01:30`).
   - `2` — `weekly`: Chạy theo tuần, chọn các thứ trong tuần (`0-6`, với `0` là Chủ Nhật) + giờ chạy.
   - `3` — `monthly`: Chạy theo ngày/tháng cụ thể (ví dụ ngày `1,15` lúc `03:00`).
   - `4` — `custom`: Nhập biểu thức Cron 5 trường chuẩn Linux.
   - `5` — `off`: Tắt lịch tự động (chỉ chạy bằng tay).
5. **Bước 5: Số bản lưu giữ & Số luồng chạy song song**:
   - Nhập số bản giữ lại tại cục bộ (`KEEP_COUNT`, mặc định `7` cho Full, `2` chuỗi cho Incremental).
   - Nhập số luồng song song (`PARALLEL_JOBS`, khuyến nghị `2` đến `4`).
6. **Bước 6: Cấu hình Lưu trữ Từ xa FTP / SFTP (Tùy chọn)**:
   - Chọn `yes` nếu muốn tự động đẩy snapshot sang server FTP/SFTP dự phòng ngoài site, hoặc `no` nếu chỉ lưu cục bộ.
   - Nếu chọn `yes`: Chọn giao thức (`ftp` hoặc `sftp`), Host/IP, Port (21 hoặc 22), Username, Password (ẩn ký tự), Thư mục từ xa (mặc định `/<job_id>`), mã hóa FTPS SSL, **Số bản lưu giữ trên FTP (`FTP_KEEP_COUNT`, mặc định 7, độc lập với local)**, và kiểm tra kết nối ngay.

#### Chỉnh sửa Job 1 chạm (Bấm `2`):
Màn hình hiển thị toàn bộ 11 trường dữ liệu hiện tại đánh số `1..11`:
- Mục `1..10`: Tên Job, Bật/tắt, Loại sao lưu, Lịch chạy, Thư mục lưu, Kiểm tra mount, Số bản lưu local, Số luồng song song, Domain, Danh sách User.
- Mục `11`: Cấu hình Remote FTP Upload (Bật/tắt, Protocol, Server, Port, User, Password, Remote Dir, FTPS SSL, Retention `FTP_KEEP_COUNT`, Test kết nối tức thì).
Bấm số mục cần sửa và bấm `s` để lưu và đồng bộ Crontab ngay lập tức.

---

### Menu 2: Run Backup Now (Chạy sao lưu thủ công tức thời)

Bấm phím **`2`** từ Main Menu khi muốn sao lưu ngay mà không cần đợi lịch Cron:
- **Mục 1 (`Run a configured backup job`)**: Chọn Job muốn chạy ngay.
- **Mục 2 (`Force FULL run on an incremental job`)**: Ép buộc Job Incremental mở ngay chuỗi Full mới (`full-DD-MM-YYYY`).
- **Mục 3 (`Ad-hoc single account backup`)**: Sao lưu riêng 1 hoặc vài email quan trọng trước khi nâng cấp hòm thư hoặc xử lý sự cố.

---

### Menu 3: Restore from Backup Job (Khôi phục từ Job đã cấu hình)

Bấm phím **`3`** để khôi phục dữ liệu từ các Job sao lưu đã có:
1. **Bước 1**: Chọn Job sao lưu cần khôi phục -> Hệ thống liệt kê danh sách snapshot với mã băm SHA-256.
2. **Bước 2**: Chọn Snapshot cần lấy (ví dụ số `1` là bản mới nhất).
3. **Bước 3**: Chọn Phạm vi khôi phục:
   - `1` — **Toàn bộ máy chủ (`Full server`)**: Khôi phục tất cả tài khoản, domain, cấu hình.
   - `2` — **Theo Tên miền (`Domain`)**: Khôi phục các user thuộc domain `hdll.vn`.
   - `3` — **Danh sách User cụ thể (`Specific users`)**: Tra cứu và chọn chính xác 1 hoặc nhiều tài khoản.
4. **Bước 4**: Chọn Thành phần: Cả LDAP + Mailbox, hoặc chỉ Mailbox, hoặc chỉ cấu hình LDAP.
5. **Bước 5**: Chọn Chế độ giải quyết xung đột:
   - `skip` *(mặc định)*: Chỉ nạp thêm thư còn thiếu, không ghi đè thư đã có.
   - `modify`: Cập nhật thư thay đổi và thêm thư mới.
   - `subfolder`: Nạp toàn bộ dữ liệu vào một thư mục con riêng (ví dụ `/KhoiPhuc_2026`).
   - `reset`: Xóa trắng hộp thư hiện tại trên server rồi nạp mới hoàn toàn.
6. **Bước 6**: Chạy thử `Dry-run` kiểm tra trước và xác nhận thực thi.

---

### Menu 4: Restore from Custom Dir (Khôi phục từ ổ cứng ngoài / NAS / bản cũ)

Bấm phím **`4`** khi bạn gắn ổ cứng di động, mount thư mục NFS (`/mnt/nas`), hoặc muốn khôi phục từ thư mục backup cũ của script `auto_full_backup.sh`:
- Hệ thống hỗ trợ **quét đệ quy thông minh**: Dù bạn chỉ nhập `/backup`, hệ thống sẽ tự động tìm thấy các thư mục con chứa bản sao lưu hợp lệ và hiển thị danh sách cho bạn chọn.

---

### Menu 5: Backup Catalog & Verify (Tra cứu User, Kiểm tra SHA-256 & Dọn rác)

Bấm phím **`5`**:
- **Mục 1 & 2**: Liệt kê bản backup theo Job hoặc theo đường dẫn ngoài.
- **Mục 3 (`Inspect snapshot & search accounts`)**: Tìm kiếm tài khoản trong bản backup, xem dung lượng hộp thư của từng người.
- **Mục 4 (`Verify SHA-256 integrity`)**: Đối chiếu mã băm SHA-256 của toàn bộ chuỗi snapshot để phát hiện sớm lỗi ổ đĩa hỏng bit.
- **Mục 5 (`Clean leftover pending directories`)**: Tự động dọn dẹp các thư mục tạm `.pending.*` nếu server từng bị mất điện giữa chừng.

---

### Menu 6: Global Settings & Alerts (Cấu hình chung, Giới hạn đĩa & Cảnh báo)

Bấm phím **`6`**:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.10) - mail.hdll.vn
  >> GLOBAL SETTINGS & ALERTS
============================================================
  1) Default job backup dir   : /home/backup
  2) Custom restore directory : (not set)
  3) Require mountpoint       : no
  4) Disk warning / Min free  : 85% / 1024 MB
  5) Server label (alerts)    : (auto: mail.hdll.vn)
  6) Telegram Bot alerts      : yes
  7) Email alerts             : yes [all]
  8) Send test Telegram alert
  9) Send test Email alert
  0) Back to main menu
============================================================
Select [0-9]:
```
- **Cấu hình Telegram Bot (Mục 6 & 8)**: Nhập Bot Token và Chat ID. Bấm mục `8` để gửi tin nhắn thử nghiệm ngay trên điện thoại.
- **Cấu hình Email Alerts (Mục 7 & 9)**: Bật/tắt gửi email và chọn mức kích hoạt `EMAIL_ALERT_LEVEL` (`all` để gửi mọi bản sao lưu bao gồm thành công, hoặc `failure` để chỉ gửi khi có cảnh báo/lỗi). Bấm mục `9` để kiểm tra khả năng gửi thư của Postfix/sendmail trên máy chủ.
- **Bảo vệ ổ đĩa (Mục 4)**: Cảnh báo khi đĩa vượt ngưỡng 85% và từ chối chạy nếu dung lượng trống dưới 1024 MB (tránh làm đầy ổ đĩa 100%).
- *(Lưu ý: Kể từ v0.3.8, tính năng Lưu trữ từ xa FTP / SFTP được phân quyền cấu hình độc lập theo từng Job tại Menu 1 › Mục 11 hoặc Bước 6 khi tạo Job, giúp mỗi Job có thể gửi tới một server FTP và thư mục lưu khác nhau).*

#### Cấu hình Lưu trữ từ xa (FTP / SFTP) riêng của từng Job (Menu 1 › Mục 2 › Chọn Job › Mục 11):
```text
============================================================
  REMOTE FTP/SFTP CONFIGURATION: daily-full
============================================================
  1) Enable Remote Storage    : yes / no
  2) Protocol                 : ftp / sftp (auto-toggles port 21 / 22)
  3) Server Host / IP         : backup.server.com
  4) Port                     : 22 (hoặc 21 cho FTP)
  5) Remote Directory Path    : /backups/daily-full
  6) Username                 : backup_user
  7) Password                 : ******** (nhập an toàn không hiện ký tự)
  8) FTPS (SSL encryption)    : yes / no (chỉ cho FTP: --ssl-reqd)
  9) Retention Keep on FTP    : 7 remote archives (độc lập với local)
 10) Test connection now      : kiểm tra kết nối tới server FTP
  0) Done (return to Job editor)
============================================================
```

---

### Menu 7: View Logs (Xem nhật ký thực thi)

Bấm phím **`7`**: Liệt kê 15 file log gần nhất. Bạn chỉ cần gõ số thứ tự (ví dụ `1`) để đọc ngay 100 dòng nhật ký mới nhất mà không cần thoát ra gõ lệnh terminal.

---

## 4. Cẩm nang toàn bộ câu lệnh CLI (`zimbra-backup <lệnh>`) & Ví dụ

Mọi thao tác trên Menu TUI đều có câu lệnh CLI tương ứng để phục vụ quản trị qua SSH, viết script tự động hoặc tích hợp Ansible.

Xem trợ giúp nhanh:
```bash
zimbra-backup --help
```

---

### 4.1. Lệnh `init` — Khởi tạo cấu hình hệ thống

**Cú pháp:**
```text
zimbra-backup init [--backup-dir <path>] [--restore-dir <path|none>]
                   [--require-mount <yes|no>] [--create-dir]
                   [--disk-warn <1-99>] [--disk-min-mb <MB>]
                   [--host-label <label>]
                   [--telegram-enabled <yes|no>] [--telegram-token <token>]
                   [--telegram-chat <chat_id>] [--telegram-thread <thread_id>]
                   [--email-enabled <yes|no>] [--email-to <email>]
                   [--email-level <all|failure>]
                   [--ftp-enabled <yes|no>] [--ftp-protocol <ftp|sftp>]
                   [--ftp-host <host>] [--ftp-port <port>]
                   [--ftp-user <user>] [--ftp-password <pass>]
                   [--ftp-dir <path>] [--ftp-ssl <yes|no>]
```

**Ví dụ:**
```bash
# Khởi tạo thư mục nội bộ /home/backup không yêu cầu mount riêng:
zimbra-backup init --backup-dir /home/backup --require-mount no --create-dir

# Khởi tạo kèm cảnh báo Telegram:
zimbra-backup init \
  --backup-dir /home/backup \
  --require-mount no \
  --host-label "Mail-HN-Prod" \
  --telegram-enabled yes \
  --telegram-token "123456789:AAExampleBotTokenString" \
  --telegram-chat "-1001234567890" \
  --disk-warn 85 --disk-min-mb 2048

# Khởi tạo kèm đẩy dữ liệu sang máy chủ lưu trữ SFTP từ xa (port 22):
zimbra-backup init \
  --ftp-enabled yes \
  --ftp-protocol sftp \
  --ftp-host "backup.storage.vn" \
  --ftp-port 22 \
  --ftp-user "zimbrabackup" \
  --ftp-password "MatKhauSieuKho123" \
  --ftp-dir "/backups/zimbra"
```

---

### 4.2. Lệnh `job` — CRUD Job, chỉnh sửa lịch & kích hoạt

| Lệnh con | Mô tả |
|---|---|
| `zimbra-backup job list` | Liệt kê bảng danh sách toàn bộ các Job sao lưu. |
| `zimbra-backup job show <id>` | Xem chi tiết cấu hình và đường dẫn lưu trữ của 1 Job. |
| `zimbra-backup job add <id> [options]` | Tạo Job sao lưu mới và tự động cập nhật Crontab. |
| `zimbra-backup job edit <id> [options]` | Chỉnh sửa tham số của Job và đồng bộ lại Crontab. |
| `zimbra-backup job enable <id>` | Kích hoạt lại lịch chạy tự động cho Job. |
| `zimbra-backup job disable <id>` | Tạm dừng lịch chạy tự động của Job. |
| `zimbra-backup job delete <id> [--yes]` | Xóa Job khỏi cấu hình và Crontab (giữ nguyên file backup). |
| `zimbra-backup job run <id> [--force-full]` | Chạy ngay lập tức một Job. |

**Ví dụ tạo Job:**
```bash
# 1. Tạo Job Full hằng ngày lúc 01:30 sáng, giữ 7 bản gần nhất:
zimbra-backup job add daily-full \
  --name "Daily Full Backup" \
  --type full \
  --schedule daily --hour 1 --minute 30 \
  --keep 7 --prune-timing after --parallel 2

# 2. Tạo Job Incremental mỗi đêm lúc 02:00, Chủ Nhật mở chuỗi Full mới, giữ 2 chuỗi:
zimbra-backup job add daily-incr \
  --name "Nightly Incremental" \
  --type incremental \
  --schedule daily --hour 2 --minute 0 \
  --full-cycle weekly --full-cycle-value 0 \
  --keep 2 --parallel 4

# 3. Tạo Job Full kèm sao lưu từ xa qua SFTP (port 22), giữ 7 bản local và 14 bản trên SFTP:
zimbra-backup job add offsite-full \
  --name "Offsite Full Backup" \
  --type full \
  --schedule daily --hour 3 --minute 0 \
  --keep 7 \
  --ftp-upload yes \
  --ftp-protocol sftp \
  --ftp-host "backup.server.com" \
  --ftp-port 22 \
  --ftp-user "backup_user" \
  --ftp-password "secret_pass" \
  --ftp-dir "/backups/mail" \
  --ftp-keep 14

# 4. Sửa giờ chạy của Job daily-full sang 00:30:
zimbra-backup job edit daily-full --hour 0 --minute 30

# 5. Kích hoạt chạy ngay một Job Incremental nhưng ép mở chuỗi Full mới:
zimbra-backup job run daily-incr --force-full
```

---

### 4.3. Lệnh `cron` — Xem & đồng bộ lại Crontab Zimbra

```bash
# Xem các dòng cron đang được quản lý bởi zimbra-backup:
zimbra-backup cron show

# Đồng bộ lại crontab từ các file cấu hình Job (dùng sau khi nâng cấp Zimbra):
zimbra-backup cron sync
```

---

### 4.4. Lệnh `backup` — Xem danh sách, tra cứu User, verify SHA-256 & sao lưu lẻ

```bash
# 1. Liệt kê toàn bộ các bản sao lưu hiện có:
zimbra-backup backup list

# 2. Liệt kê các bản sao lưu thuộc thư mục ngoài:
zimbra-backup backup list --dir /backup

# 3. Tìm kiếm tài khoản "ketoan" trong bản backup số 1:
zimbra-backup backup inspect 1 --search ketoan

# 4. Kiểm tra toàn vẹn mã băm SHA-256 của bản backup số 1:
zimbra-backup backup verify 1

# 5. Sao lưu lẻ khẩn cấp cho 2 tài khoản trước giờ bảo trì:
zimbra-backup backup user "giamdoc@hdll.vn,ketoan@hdll.vn"

# 6. Dọn sạch các thư mục tạm treo (.pending.*):
zimbra-backup backup clean-pending
```

---

### 4.5. Lệnh `restore` — Khôi phục chuyên sâu bằng dòng lệnh

**Cú pháp đầy đủ:**
```text
zimbra-backup restore
  --from <NO. | backup_id | đường_dẫn_snapshot>
  [--job <job_id> | --dir <thư_mục_ngoài>]
  (--all | --domain <d1,d2> | --users <u1,u2>)
  [--target-user <email_đích_khác>]
  [--only <all|mailbox|ldap>]
  [--mode <skip|subfolder|modify|reset>]
  [--subfolder-name <tên_thư_mục_con>]
  [--dry-run]
  [--yes]
```

**Các tham số quan trọng:**
- `--from`: Chỉ định bản snapshot bằng số thứ tự `NO.` (trong `backup list`), hoặc mã ID, hoặc đường dẫn thư mục.
- `--all`: Khôi phục toàn bộ máy chủ.
- `--domain <d1,d2>`: Khôi phục toàn bộ tài khoản và nhóm thuộc tên miền.
- `--users <u1,u2>`: Khôi phục danh sách tài khoản chỉ định.
- `--target-user <email>`: Nạp dữ liệu vào một tài khoản đích khác (chỉ dùng khi `--users` truyền đúng 1 email).
- `--only`: `all` (cả LDAP + Mailbox), `mailbox` (chỉ nạp hộp thư), `ldap` (chỉ nạp mật khẩu, chữ ký, bộ lọc, quota).
- `--mode`: `skip` (chỉ bù mail thiếu), `modify` (bồi đắp mail mới & sửa), `subfolder` (nạp vào thư mục con), `reset` (xóa trắng hộp thư hiện tại rồi nạp lại).
- `--subfolder-name`: Tên thư mục con khi dùng `--mode subfolder`.
- `--dry-run`: Chạy thử mô phỏng kiểm tra kế hoạch, không can thiệp máy chủ.
- `--yes` (`-y`): Tự động xác nhận thực thi, bắt buộc khi chạy trong kịch bản tự động.

---

### 4.6. Cơ chế an toàn `--yes` và các cờ bảo vệ dữ liệu

Nhằm ngăn chặn tối đa rủi ro thao tác nhầm làm mất dữ liệu hộp thư của người dùng, hệ thống áp dụng cơ chế xác nhận đa tầng:

1. **Khi chạy có bàn phím tương tác (`Interactive Terminal`):**
   - Với chế độ bình thường (`skip`, `modify`, `subfolder`): Hệ thống hỏi `Proceed with restore now? [y/N]:` (phải bấm `y` hoặc `Y`).
   - Với chế độ nguy hiểm (`--mode reset`): Hệ thống yêu cầu gõ chính xác chữ hoa **`RESET`** để xác nhận xóa trắng hòm thư trước khi nạp lại.
2. **Khi chạy tự động trong kịch bản / Crontab (`Non-interactive Shell`):**
   - Nếu **không có `--yes`**, hệ thống **lập tức từ chối chạy** và báo lỗi an toàn:
     ```text
     [ERROR] Refusing to execute live restore in non-interactive shell without '--yes'.
     ```
   - Nếu **có cờ `--yes`**, hệ thống hiểu rằng quản trị viên đã chủ động cho phép và tiến hành khôi phục tự động.
3. **Khuyến nghị an toàn:** Luôn kết hợp `--dry-run` để kiểm tra số lượng tài khoản trước khi chạy thực tế.

---

### 4.7. Lệnh `status` & `logs` — Trạng thái hệ thống và xem Log

```bash
# Xem trạng thái tổng thể hệ thống, dung lượng đĩa và các Job:
zimbra-backup status

# Xem 80 dòng cuối của file log mới nhất:
zimbra-backup logs

# Xem 200 dòng cuối của file log mới nhất:
zimbra-backup logs latest 200

# Xem danh sách các file log có sẵn:
zimbra-backup logs list

# Đọc file log cụ thể theo tên:
zimbra-backup logs job_daily-full_20261103_013000.log 100
```

---

### 4.8. Lệnh `notify` — Kiểm tra thông báo Email, Telegram và Remote Storage

Kiểm tra ngay khả năng kết nối và gửi cảnh báo mà không cần chờ chạy xong một tiến trình sao lưu:

```bash
# Gửi thư thử nghiệm qua Postfix / sendmail nội bộ:
zimbra-backup notify test-email

# Gửi tin nhắn thử nghiệm tới Telegram Bot:
zimbra-backup notify test-telegram

# Kiểm tra kết nối tới máy chủ lưu trữ từ xa (FTP / SFTP) của một Job:
zimbra-backup notify test-ftp [job_id]
```

> 💡 **Mẹo:** Lệnh `notify test-telegram` từ v0.3.9 sẽ in ra chính xác phản hồi từ Telegram API (như `Bad Request: chat not found`, `Forbidden: bot is not a member of the supergroup chat`), giúp chẩn đoán sự cố phân quyền Bot chỉ trong vài giây.

---

## 5. Các kịch bản thực chiến hay gặp nhất (Step-by-Step)

### Kịch bản 1: Khôi phục toàn bộ server mới dựng (Disaster Recovery)

Giả sử máy chủ cũ bị sự cố phần cứng, bạn đã dựng một máy chủ Zimbra mới cùng phiên bản và gắn ổ backup chứa dữ liệu cũ tại `/backup`:

1. **Bước 1: Chạy mô phỏng trước để kiểm tra danh sách tài khoản:**
   ```bash
   zimbra-backup restore --dir /backup --from 1 --all --only all --mode skip --dry-run
   ```
2. **Bước 2: Tiến hành khôi phục thật:**
   ```bash
   zimbra-backup restore --dir /backup --from 1 --all --only all --mode skip --yes
   ```
3. **Kết quả:** Hệ thống tự động tạo lại Domains -> Accounts -> Khôi phục mật khẩu gốc -> Khôi phục Tên hiển thị tiếng Việt UTF-8 -> Aliases -> Nhóm mail & Thành viên -> Chữ ký -> Bộ lọc Sieve -> Phục hồi quyền Admin -> Import toàn bộ email của tất cả tài khoản.

---

### Kịch bản 2: Khôi phục hộp thư bị nhân viên xóa nhầm mà không mất mail mới

Một nhân viên lỡ tay xóa mất nhiều email quan trọng trong tuần qua, nhưng từ sáng nay đã nhận thêm một số email mới từ đối tác:

```bash
zimbra-backup restore \
  --job daily-incr \
  --from 1 \
  --users "nhanvien@hdll.vn" \
  --only mailbox \
  --mode skip \
  --yes
```
- Chế độ **`--mode skip`** chỉ nạp lại những email có trong bản backup mà hòm thư hiện tại đang thiếu, **giữ nguyên vẹn các email mới nhận sáng nay**.

---

### Kịch bản 3: Bàn giao hòm thư nhân viên nghỉ việc vào thư mục con của Trưởng phòng

Nhân viên `nv_cu@hdll.vn` nghỉ việc. Cần nạp toàn bộ email cũ của nhân viên này vào một thư mục riêng tên `/BanGiao_NVCU` bên trong hộp thư của Trưởng phòng `truongphong@hdll.vn` mà không làm xáo trộn email hiện tại hay đổi mật khẩu của Trưởng phòng:

```bash
zimbra-backup restore \
  --from 1 \
  --users "nv_cu@hdll.vn" \
  --target-user "truongphong@hdll.vn" \
  --only mailbox \
  --mode subfolder \
  --subfolder-name "BanGiao_NVCU" \
  --yes
```

---

### Kịch bản 4: Chiến lược sao lưu chuẩn Production cho doanh nghiệp (50 - 1000 Users)

Chiến lược tối ưu nhất về dung lượng đĩa và khả năng phục hồi theo từng mốc ngày là kết hợp **1 Job Incremental hằng đêm** + **1 Job Full lưu trữ đầu tháng**:

```bash
# 1. Khởi tạo cấu hình gốc:
zimbra-backup init --backup-dir /home/backup --require-mount no --create-dir --disk-warn 85 --disk-min-mb 5120

# 2. Job 1: Incremental mỗi đêm lúc 01:30 sáng, Chủ Nhật mở Full mới, lưu giữ 2 chuỗi (~14 ngày):
zimbra-backup job add prod-daily-incr \
  --name "Nightly Incremental (14 days)" \
  --type incremental \
  --schedule daily --hour 1 --minute 30 \
  --full-cycle weekly --full-cycle-value 0 \
  --keep 2 --prune-timing after --parallel 4

# 3. Job 2: Full độc lập mùng 1 hằng tháng lúc 03:00 sáng, lưu giữ 3 tháng gần nhất:
zimbra-backup job add prod-monthly-full \
  --name "Monthly Standalone Full (3 months)" \
  --type full \
  --schedule monthly --dom 1 --month "*" --hour 3 --minute 0 \
  --keep 3 --prune-timing after --parallel 2

# 4. Kiểm tra lịch crontab:
zimbra-backup cron show
```

---

### Kịch bản 5: Khôi phục từ thư mục của tool cũ `auto_full_backup.sh`

Nếu bạn có thư mục backup từ script cũ dạng `/backup/full/20261031_174042`:

```bash
zimbra-backup restore --dir /backup --from 1 --all --yes
```
Hệ thống tự động nhận diện định dạng LDIF legacy, trích xuất an toàn trong bộ nhớ tạm `$ZB_RUN_DIR` (ở chế độ Read-Only, không ghi đè vào thư mục nguồn) và khôi phục đầy đủ dữ liệu.

---

## 6. Lưu ý kỹ thuật quan trọng & Xử lý sự cố thường gặp

1. **Đặc thù Incremental trên Zimbra Open Source Edition:**
   - Trích xuất qua REST API với truy vấn `query=after:<checkpoint - 300s>` (lùi đệm 5 phút chống sót thư lúc giao thời).
   - Đây là cơ chế sao lưu **bồi đắp mục mới và sửa đổi**. Nếu người dùng tự xóa email giữa 2 lần chạy, email đó vẫn tồn tại trong bản Full đầu chuỗi.
2. **Khóa vận hành `operation.lock`:**
   - Tại một thời điểm chỉ cho phép **1 tiến trình backup hoặc restore duy nhất** hoạt động để tránh nghẽn I/O và quá tải máy chủ.
   - Nếu tiến trình trước chưa xong, lệnh chạy sau sẽ dừng an toàn. Khi tiến trình hoàn thành hoặc bị tắt, nhân Linux tự động giải phóng khóa `flock`.
3. **Lỗi phân quyền thư mục lưu trữ:**
   - Nếu gặp lỗi `Directory '...' is not writable by user 'zimbra'`, hãy chạy lệnh:
     ```bash
     chown -R zimbra:zimbra /home/backup
     ```
4. **Lịch tự động không chạy sau khi nâng cấp hệ điều hành hoặc nâng cấp Zimbra:**
   - Chạy lệnh sau để đồng bộ lại toàn bộ Crontab từ các file cấu hình Job đã lưu:
     ```bash
     zimbra-backup cron sync
     ```
5. **Ý nghĩa và vai trò của file `.manifest` trên máy chủ FTP / SFTP từ xa:**
   - Khi sao lưu đẩy sang FTP/SFTP, bên cạnh file nén `.tar` dung lượng lớn (hàng chục đến hàng trăm GB) luôn xuất hiện một file đi kèm mang đuôi `.manifest` (dung lượng chỉ khoảng vài chục KB, ví dụ `full-05-11-2026.manifest`).
   - **File này có 4 chức năng quan trọng:**
     1. **Tra cứu mục lục siêu tốc (Instant Catalog Inspection):** File `.manifest` là file văn bản thuần lưu danh sách toàn bộ tài khoản email, dung lượng từng hòm thư và mốc thời gian hoàn thành. Khi cần kiểm tra nội dung bản backup trên FTP, bạn chỉ cần mở file `.manifest` đọc trực tiếp mà không cần tải file `.tar` hàng chục GB về máy.
     2. **Phục vụ chuỗi sao lưu Incremental:** Bản Incremental tiếp theo cần đọc checkpoint timestamp (`last_checkpoint_to`) từ manifest này để xác định mốc kéo email mới phát sinh.
     3. **Kiểm tra toàn vẹn dữ liệu (Integrity Verification):** File ghi nhận mã băm SHA-256 của từng tài khoản, giúp lệnh `zimbra-backup catalog verify` đối soát tính toàn vẹn, chống suy hao/lỗi file khi truyền tải qua mạng.
     4. **Dọn dẹp đồng bộ:** Cơ chế dọn dẹp tự động trên FTP (`zb_prune_remote_storage`) sẽ xóa đồng thời cả cặp `.tar` và `.manifest` tương ứng khi bản sao lưu vượt quá hạn lưu giữ (`FTP_KEEP_COUNT`).
6. **Hướng dẫn cấu hình & Khắc phục sự cố Thông báo (Email & Telegram):**
   - **Kênh Telegram Bot:**
     - Bot Token được cấp từ `@BotFather`, Chat ID cá nhân là số dương, Chat ID của Group/Channel luôn là số âm bắt đầu bằng `-100...` (ví dụ: `-1002416073803`).
     - **Nguyên nhân phổ biến nhất không nhận được tin nhắn:** Bot **chưa được thêm (Add) vào Group/Channel** hoặc chưa được phân quyền **Administrator** (quyền *Send Messages* / *Post Messages*).
     - **Cách kiểm tra:** Chạy `zimbra-backup notify test-telegram` hoặc vào Menu 6 bấm phím `8`. Hệ thống sẽ in ra thông báo lỗi chi tiết từ Telegram API nếu Bot bị chặn hoặc chưa vào nhóm.
   - **Kênh Email Alerts:**
     - Thiết lập địa chỉ nhận thư tại `EMAIL_ALERT_TO` và chọn mức cảnh báo (`all` - gửi mọi kết quả, hoặc `failure` - chỉ gửi khi có cảnh báo/lỗi).
     - **Lưu ý về Server Label (Alerts):** Nếu bạn đặt Server Label là địa chỉ IP thô (ví dụ: `1.55.212.58`), hệ thống mail bên ngoài (như FPT, Google, Microsoft 365) hoặc chính Postfix của Zimbra có thể từ chối nhận (reject) do vi phạm chuẩn RFC (địa chỉ người gửi không được dùng IP thuần `@1.55.212.58`).
     - **Cơ chế tối ưu từ v0.3.9:** Tiêu đề `From:` sẽ tự động sử dụng FQDN/domain hợp lệ của máy chủ (`zmhostname` hoặc `hostname -f`), trong khi nhãn IP vẫn được hiển thị rõ ràng trong tiêu đề và nội dung email thông báo để bạn dễ dàng nhận diện máy chủ.
     - **Cách kiểm tra:** Chạy `zimbra-backup notify test-email` hoặc vào Menu 6 bấm phím `9`. Nếu không nhận được thư, kiểm tra hàng đợi Postfix bằng lệnh `mailq` hoặc xem log `/var/log/zimbra.log`.

---

## 7. ☕ Ủng hộ tác giả (Buy Me a Coffee)

Nếu công cụ `zimbra-backup` giúp ích cho công việc quản trị hệ thống và bảo vệ dữ liệu Zimbra của bạn, bạn có thể ủng hộ tác giả một ly cà phê qua các kênh dưới đây:

| 💎 USDT (BEP20) | 🪙 Bitcoin (BTC) |
|:---:|:---:|
| <img src="docs/images/donate-usdt-bsc.png" width="220" alt="USDT (BSC)"> | <img src="docs/images/donate-btc.png" width="220" alt="Bitcoin (BTC)"> |
| **Mạng BSC (BEP20)**<br>`0x1b1817cc4f6eb49adb051c25d0f82e77f66c8514` | **Mạng BTC**<br>`14enMJBiXgk7jLc187qXB5qucBBSfsYuVG` |

