# TÀI LIỆU HƯỚNG DẪN SỬ DỤNG CHI TIẾT `zimbra-backup` (v0.3.0)

Tài liệu này hướng dẫn **đầy đủ từng bước, từng màn hình Menu TUI và từng câu lệnh CLI kèm ví dụ thực tế** cho bộ công cụ sao lưu & khôi phục hợp nhất **`zimbra-backup` v0.3.0** trên máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** chạy **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**.

---

## MỤC LỤC

1. [Tổng quan dữ liệu sao lưu & Cấu trúc thư mục](#1-tổng-quan-dữ-liệu-sao-lưu--cấu-trúc-thư-mục)
2. [Cài đặt, Nâng cấp & Thiết lập lần đầu (Quick Initial Setup)](#2-cài-đặt-nâng-cấp--thiết-lập-lần-đầu-quick-initial-setup)
3. [Hướng dẫn chi tiết Giao diện Menu TUI (`zimbra-backup`)](#3-hướng-dẫn-chi-tiết-giao-diện-menu-tui-zimbra-backup)
   - [Menu 1: Jobs & Crontab Schedule (Quản lý Job & Lịch tự động)](#31-menu-1--jobs--crontab-schedule-quản-lý-job--lịch-tự-động)
   - [Menu 2: Run Backup Now (Chạy sao lưu thủ công ngay lập tức)](#32-menu-2--run-backup-now-chạy-sao-lưu-thủ-công-ngay-lập-tức)
   - [Menu 3: Restore from Backup Job (Khôi phục từ Job đã cấu hình)](#33-menu-3--restore-from-backup-job-khôi-phục-từ-job-đã-cấu-hình)
   - [Menu 4: Restore from Custom Dir (Khôi phục từ thư mục ngoài / bản cũ)](#34-menu-4--restore-from-custom-dir-khôi-phục-từ-thư-mục-ngoài--bản-cũ)
   - [Menu 5: Backup Catalog & Verify (Tra cứu User, Kiểm tra SHA-256 & Dọn rác)](#35-menu-5--backup-catalog--verify-tra-cứu-user-kiểm-tra-sha-256--dọn-rác)
   - [Menu 6: Global Settings & Alerts (Cấu hình chung & Cảnh báo Telegram/Email)](#36-menu-6--global-settings--alerts-cấu-hình-chung--cảnh-báo-telegramemail)
   - [Menu 7: View Logs (Xem nhật ký thực thi)](#37-menu-7--view-logs-xem-nhật-ký-thực-thi)
4. [Cẩm nang toàn bộ lệnh CLI (`zimbra-backup <lệnh>`) & Ví dụ từng lệnh](#4-cẩm-nang-toàn-bộ-lệnh-cli-zimbra-backup-lệnh--ví-dụ-từng-lệnh)
   - [4.1. Lệnh `init` — Khởi tạo & sửa cấu hình hệ thống](#41-lệnh-init--khởi-tạo--sửa-cấu-hình-hệ-thống)
   - [4.2. Lệnh `job` — Tạo, sửa, bật/tắt, xóa và chạy Job](#42-lệnh-job--tạo-sửa-bậttắt-xóa-và-chạy-job)
   - [4.3. Lệnh `cron` — Xem & đồng bộ lại Crontab Zimbra](#43-lệnh-cron--xem--đồng-bộ-lại-crontab-zimbra)
   - [4.4. Lệnh `backup` — Xem danh sách, tìm User, kiểm tra SHA-256 & sao lưu lẻ](#44-lệnh-backup--xem-danh-sách-tìm-user-kiểm-tra-sha-256--sao-lưu-lẻ)
   - [4.5. Lệnh `restore` — Khôi phục dữ liệu chuyên sâu bằng dòng lệnh](#45-lệnh-restore--khôi-phục-dữ-liệu-chuyên-sâu-bằng-dòng-lệnh)
   - [4.6. Lệnh `status` & `logs` — Kiểm tra trạng thái tổng thể & xem Log](#46-lệnh-status--logs--kiểm-tra-trạng-thái-tổng-thể--xem-log)
5. [Các kịch bản thực chiến hay gặp nhất (Step-by-Step)](#5-các-kịch-bản-thực-chiến-hay-gặp-nhất-step-by-step)
6. [Lưu ý kỹ thuật quan trọng & Xử lý sự cố thường gặp](#6-lưu-ý-kỹ-thuật-quan-trọng--xử-lý-sự-cố-thường-gặp)

---

## 1. Tổng quan dữ liệu sao lưu & Cấu trúc thư mục

### 1.1. Công cụ sao lưu và khôi phục những thành phần nào?

Mỗi bản sao lưu (`Full` hoặc `Incremental`) tự động thu thập **2 nhóm dữ liệu đầy đủ**:

1. **Cấu hình LDAP & Metadata tài khoản**:
   - Danh sách **Domains** (`domains/domains.txt`).
   - Danh sách **Tài khoản đang hoạt động** (`accounts/active_accounts.txt` — tự động loại bỏ các tài khoản hệ thống `spam.*`, `ham.*`, `virus-quarantine.*`, `galsync.*`).
   - **Mật khẩu gốc dạng mã băm (`userPassword` SSHA/SHA512)** trong `passwords/<email>.shadow`: Khi khôi phục sang máy mới, người dùng **đăng nhập lại bằng mật khẩu cũ ngay lập tức**, không cần đặt lại mật khẩu.
   - **Tên hiển thị tiếng Việt UTF-8 (`displayName`)** và hạn ngạch dung lượng (`zimbraMailQuota`) — giải mã chuẩn LDIF RFC 2849 + Base64, không bị lỗi font hay mất chữ có dấu.
   - **Mail Aliases** (bí danh email) trong `aliases/<email>.txt`.
   - **Distribution Lists (Nhóm mail)** và danh sách thành viên chi tiết trong `dl/` và `distribution_lists/`.
   - **Chữ ký email (`Signatures`)** cả dạng HTML và văn bản thuần trong `signatures/`.
   - **Bộ lọc thư (`Sieve Filters`)** nhiều dòng trong `filters/`.
   - **Quyền Quản trị viên (`Admins`)** trong `admins/admins.txt`.
2. **Dữ liệu Hộp thư (`.tgz` qua HTTPS REST API nội bộ)**:
   - Toàn bộ **Email** (Inbox, Sent, Drafts, Trash, các thư mục con người dùng tự tạo).
   - **Danh bạ (Contacts)**, **Lịch làm việc (Calendar)**, **Công việc (Tasks)**, **Cặp tài liệu (Briefcase)**.
   - Bảng mã kiểm tra toàn vẹn **`manifest` (`SHA-256`)** cho từng file `.tgz` để phát hiện ngay nếu ổ cứng lưu trữ bị lỗi bit (bit-rot) hoặc copy thiếu dung lượng.

---

### 1.2. Cấu trúc thư mục trên máy chủ

Khi cài gói RPM, hệ thống phân tách rõ **thư mục cấu hình/trạng thái** và **thư mục chứa dữ liệu Backup**:

```text
/usr/bin/zimbra-backup                  # Lệnh chạy chính (gõ ở bất kỳ đâu)
/usr/libexec/zimbra-backup/*.sh         # Các module thư viện của công cụ
/etc/logrotate.d/zimbra-backup          # Tự động nén & xoay vòng log hằng tuần

/var/lib/zimbra-backup/                 # Thư mục trạng thái nội bộ (quyền 0700 zimbra:zimbra)
  ├── settings.conf                     # Cấu hình chung (thư mục mặc định, cảnh báo Telegram/Email...)
  ├── operation.lock                    # Khóa flock chống 2 tiến trình backup/restore đè lên nhau
  ├── jobs/                             # Cấu hình từng Job (<job_id>.conf)
  ├── logs/                             # Nhật ký chi tiết từng lần chạy backup/restore
  └── run/                              # Chứa file token tạm 0600 khi đang chạy (tự xóa khi xong)

/home/backup/                           # Thư mục lưu dữ liệu mặc định (DEFAULT_BACKUP_DIR)
  ├── full/                             # [1] Tách riêng toàn bộ các Job Backup FULL
  │     └── <job_id_full>/              # Ví dụ: /home/backup/full/daily-full/
  │           ├── backup-full-01-11-2026_013000/
  │           └── backup-full-02-11-2026_013000/
  ├── incremental/                      # [2] Tách riêng toàn bộ các Job Backup INCREMENTAL
  │     └── <job_id_incr>/              # Ví dụ: /home/backup/incremental/daily-incr/
  │           └── chain-01-11-2026_020000/
  │                 ├── 000_backup-full-01-11-2026_020000/        # Bản Full gốc đầu chuỗi
  │                 ├── 001_backup-incremental-02-11-2026_020000/ # Bản Incremental ngày 1
  │                 └── 002_backup-incremental-03-11-2026_020000/ # Bản Incremental ngày 2
  └── account/                          # [3] Tách riêng các bản Backup lẻ theo Email (Account)
        ├── backup-giamdoc@hdll.vn-02-11-2026_101500/             # Sao lưu 1 email lẻ
        └── backup-giamdoc@hdll.vn+1more-02-11-2026_103000/       # Sao lưu gộp nhiều email
```

> **Quy tắc đặt tên thư mục rõ ràng (`ngay-thang-nam`)**:
> - Tầng 1 tự động phân loại thành 3 thư mục riêng biệt: **`full/`**, **`incremental/`**, **`account/`**.
> - Tên thư mục bản sao lưu luôn ghi rõ loại sao lưu hoặc địa chỉ email kèm dấu thời gian **`DD-MM-YYYY_HHMMSS`** theo giờ máy chủ để quản trị viên nhìn qua `ls` biết ngay nội dung và ngày tháng.
> - Chính sách tự động xóa bản cũ (`KEEP_COUNT`) sắp xếp theo `timestamp` chuẩn trong `manifest` (không sắp xếp chữ cái đơn thuần), đảm bảo luôn giữ đúng bản mới nhất kể cả khi bước qua tháng mới hoặc năm mới.

> **Lưu ý về phân quyền**: Mọi tiến trình của `zimbra-backup` đều tự động hạ quyền từ `root` sang user `zimbra` để làm việc an toàn với LDAP và hộp thư Zimbra. Vì vậy, bất kỳ thư mục nào dùng để lưu hoặc đọc bản backup (như `/home/backup`, `/backup`, `/mnt/nas`) đều cần cấp quyền đọc/ghi cho user `zimbra`.

---

## 2. Cài đặt, Nâng cấp & Thiết lập lần đầu (Quick Initial Setup)

### Bước 1: Chuẩn bị thư mục lưu trữ và phân quyền cho `zimbra`

Ví dụ bạn muốn lưu backup mặc định tại `/home/backup`:

```bash
mkdir -p /home/backup
```

```bash
chown -R zimbra:zimbra /home/backup
```

```bash
chmod 700 /home/backup
```

*(Nếu bạn có sẵn thư mục backup cũ ở `/backup` muốn đọc để khôi phục, cấp quyền đọc cho `zimbra`: `chown -R zimbra:zimbra /backup` hoặc `chmod -R a+rX /backup`).*

### Bước 2: Cài đặt hoặc nâng cấp gói RPM

Trên **Rocky Linux / AlmaLinux / RHEL / CentOS 8, 9** (cài mới):

```bash
dnf install -y ./zimbra-backup-0.3.0-1.noarch.rpm
```

Trên **CentOS / RHEL 7** (cài mới):

```bash
yum install -y ./zimbra-backup-0.3.0-1.noarch.rpm
```

Nếu máy chủ **đã cài phiên bản cũ (`0.1.0`, `0.2.0`...)**, nâng cấp trực tiếp lên bản mới (tự động giữ nguyên toàn bộ Job, lịch Cron và cấu hình hiện có trong `/var/lib/zimbra-backup`):

```bash
dnf upgrade -y ./zimbra-backup-0.3.0-1.noarch.rpm
```

Hoặc dùng `rpm` chuẩn trên mọi phiên bản CentOS / RHEL / AlmaLinux / Rocky 7, 8, 9:

```bash
rpm -Uvh ./zimbra-backup-0.3.0-1.noarch.rpm
```

*(Trường hợp muốn cài đè lại đúng cùng số phiên bản đang cài thì thêm cờ `--force`: `rpm -Uvh --force ./zimbra-backup-0.3.0-1.noarch.rpm`).*

Kiểm tra cài đặt thành công:

```bash
zimbra-backup --version
```

### Gỡ cài đặt hoàn toàn chỉ với 1 lệnh (Không ảnh hưởng Server & Hệ thống Email)

Khi cần gỡ bỏ công cụ `zimbra-backup`, bạn chỉ cần chạy **1 lệnh duy nhất** bằng quyền `root`:

```bash
dnf remove -y zimbra-backup
```

Hoặc trên mọi phiên bản CentOS / RHEL / AlmaLinux / Rocky 7, 8, 9:

```bash
rpm -e zimbra-backup
```

**Cơ chế tự động dọn sạch & cam kết an toàn tuyệt đối cho Zimbra:**
- Nếu tại thời điểm gõ lệnh đang có tiến trình Backup hoặc Restore chạy dở (`operation.lock` đang giữ khóa), gói RPM sẽ **tự động chặn gỡ cài đặt** để không làm gián đoạn phiên làm việc với Zimbra.
- Tự động gỡ riêng khối `# BEGIN zimbra-backup ... # END zimbra-backup` khỏi `crontab` của user `zimbra` sau khi đối chiếu đảm bảo **100% các dòng cron hệ thống của Zimbra (`# ZIMBRASTART .. # ZIMBRAEND`, `/opt/zimbra/...`) còn nguyên vẹn**.
- Tự động dọn sạch toàn bộ file thực thi, cấu hình Job, Settings, Log và file `.rpmsave` trong `/var/lib/zimbra-backup` (không báo lỗi `Directory not empty`, không để lại file rác).
- **Tuyệt đối không khởi động lại hay tác động bất kỳ dịch vụ nào của Zimbra** (`zmcontrol`, `postfix`, `mailboxd`, `ldap`...), **không chạm vào `/opt/zimbra`**, và **không xóa dữ liệu các bản backup đã sao lưu** trên ổ đĩa (`/home/backup`, `/backup`, NAS...).
- Khi chạy nâng cấp `rpm -Uvh --force` hoặc `dnf upgrade`, gói tự động nhận biết cờ nâng cấp nên **giữ nguyên toàn bộ Job và lịch Cron hiện có**.

### Bước 3: Chạy Thiết lập lần đầu (`QUICK INITIAL SETUP`)

Đứng ở tài khoản `root` (hoặc `su - zimbra`), gõ lệnh:

```bash
zimbra-backup
```

Trong lần mở đầu tiên (khi chưa có `/var/lib/zimbra-backup/settings.conf`), màn hình **QUICK INITIAL SETUP** tự động xuất hiện:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.0) - mail.corp.vn
  >> QUICK INITIAL SETUP
============================================================
Welcome! Configure your default backup storage in 2 quick steps.

1. Default backup directory [/home/backup]:
   (Tip: Choose 'yes' for external disk/NFS/SAN, or 'no' for a normal local folder)
2. Require dedicated mounted disk/NFS? [y/N]:
   Directory '/home/backup' does not exist. Create it now? [Y/n]:
Configure advanced settings (disk thresholds / Telegram / Email alerts) now? [y/N]:
Create your first scheduled backup job now? [Y/n]:
```

**Giải thích từng câu hỏi:**

1. **`1. Default backup directory [/home/backup]`**:
   - Bấm **Enter** để dùng mặc định `/home/backup`, hoặc gõ đường dẫn khác (ví dụ `/mnt/backup-nas`).
2. **`2. Require dedicated mounted disk/NFS?`**:
   - Chọn **`n` (`no`)** nếu `/home/backup` là thư mục nằm ngay trên ổ đĩa của máy chủ.
   - Chọn **`y` (`yes`)** nếu đó là ổ cứng gắn ngoài / NFS / SAN / iSCSI mount riêng — khi đó nếu ổ mạng bị rớt mount, công cụ sẽ **dừng ngay và báo động**, tuyệt đối không ghi nhầm làm tràn phân vùng `/` của hệ điều hành!
3. **`Configure advanced settings ... now? [y/N]`**:
   - Bấm **Enter (`no`)** để hoàn tất nhanh (có thể cấu hình Telegram/Email sau ở **Menu 6**), hoặc gõ `y` nếu muốn nhập luôn Bot Token Telegram.
4. **`Create your first scheduled backup job now? [Y/n]`**:
   - Bấm **Enter (`yes`)** để chuyển thẳng sang màn hình tạo lịch Backup tự động đầu tiên.

---

## 3. Hướng dẫn chi tiết Giao diện Menu TUI (`zimbra-backup`)

Mỗi khi gõ `zimbra-backup`, màn hình **MAIN MENU** gồm 7 công cụ chính hiển thị như sau:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.0) - mail
  >> MAIN MENU
============================================================
  Job Storage : /home/backup (mount: no) | Jobs: 2 | Custom Restore: (not set)
------------------------------------------------------------
  1) Jobs & Crontab Schedule   (Create, Edit, Enable/Disable, Delete)
  2) Run Backup Now            (Run Job, Force Full, Single Account)
  3) Restore from Backup Job   (Select Configured Job -> Snapshot)
  4) Restore from Custom Dir   (Configure / Scan Other Directory)
  5) Backup Catalog & Verify   (Job Snapshots, Search Users, SHA-256)
  6) Global Settings & Alerts  (Storage Paths, Disk Limits, Telegram)
  7) View Logs
  0) Exit
============================================================
Select [0-7]:
```

Dưới đây là cách sử dụng chi tiết từng mục từ `1` đến `7`.

---

### 3.1. Menu `1` — `Jobs & Crontab Schedule` (Quản lý Job & Lịch tự động)

Khi bấm `1` từ Main Menu, bạn sẽ thấy bảng tổng hợp các Job đang có và 6 thao tác:

```text
  1) Create new backup job (Quick 5-step wizard)
  2) Edit existing job (change schedule, retention, path, scope...)
  3) View full job details
  4) Enable / Disable job cron schedule
  5) Delete job configuration
  6) View & re-sync Zimbra crontab
  0) Back to main menu
```

#### A. Mục `1 -> 1`: Tạo Job sao lưu mới (`Create new backup job` — 5 bước)

- **Bước 1 — `1. Job ID`**: Đặt mã định danh viết liền không dấu (gồm chữ, số, `-`, `_`, tối đa 48 ký tự), ví dụ: `daily-full`, `backup-1`, `incr-main`.
- **Bước 2 — `2. Select Backup Mode`**:
  - `1) full`: Mỗi lần tới giờ sẽ sao lưu **Full độc lập 100%** ra thư mục `backup-full-DD-MM-YYYY_HHMMSS` (đơn giản nhất, mỗi bản tự chứa đầy đủ mọi thứ, mặc định giữ `7` bản, `2` luồng song song).
  - `2) incremental`: Sao lưu theo **Chuỗi thông minh** (lần đầu tiên chạy `000_backup-full-DD-MM-YYYY_HHMMSS`, các ngày tiếp theo chỉ tải phần thư mới/thay đổi `001_backup-incremental-..` đến `006_backup-incremental-..`, hết chu kỳ tự tạo chuỗi Full mới; mặc định giữ `2` chuỗi hoàn chỉnh ~ 2 tuần, `4` luồng song song — tiết kiệm 70–85% dung lượng ổ cứng và thời gian chạy hằng đêm).
- **Bước 3 — `3. Backup Storage Directory` (Cấu hình đường dẫn lưu trữ Backup)**:
  - Nhập đường dẫn thư mục gốc nơi lưu bản sao lưu của Job này (mặc định gợi ý theo `DEFAULT_BACKUP_DIR` như `[/home/backup]`, bạn có thể bấm **Enter** để dùng mặc định hoặc nhập đường dẫn riêng như `/backup`, `/mnt/nas-zimbra`...).
  - Công cụ tự động tách nhánh theo loại sao lưu và in ngay đường dẫn đích cụ thể trên màn hình:
    - Job `full` -> `<đường_dẫn>/full/<Job_ID>`
    - Job `incremental` -> `<đường_dẫn>/incremental/<Job_ID>`
  - Nếu thư mục chưa tồn tại, công cụ hỏi tạo luôn tại chỗ (`Create it now? [Y/n]`) và kiểm tra quyền ghi của user `zimbra` (nếu thiếu quyền sẽ hiển thị sẵn lệnh `mkdir -p ... && chown zimbra:zimbra ...` để bạn phân quyền trước khi chạy).
- **Bước 4 — `4. Configure Schedule` (Chọn lịch chạy tự động)**:
  - `1) Daily`: Chạy mỗi ngày vào giờ `HH:MM` (hệ 24h, ví dụ nhập `01:30` hoặc `2` tương đương `02:00`).
  - `2) Weekly`: Chạy theo thứ trong tuần (`0`=Chủ Nhật, `1`=Thứ Hai .. `6`=Thứ Bảy; có thể nhập dãy như `1-5` cho Thứ 2 đến Thứ 6, hoặc `0,3` cho Chủ Nhật & Thứ Tư) + giờ `HH:MM`.
  - `3) Monthly`: Chạy theo ngày trong tháng (`1-31`, ví dụ `1` hoặc `1,15` cho mùng 1 & ngày 15) + tháng (`*` là mọi tháng, hoặc `1,4,7,10` cho đầu mỗi quý) + giờ `HH:MM`.
  - `4) Custom`: Nhập trực tiếp biểu thức Cron 5 trường chuẩn (ví dụ `0 */6 * * *` để chạy mỗi 6 tiếng).
  - `5) Manual`: Không đặt lịch tự động (chỉ chạy khi quản trị viên bấm chạy bằng tay).
- **Bước 5 — `5. Retention Policy` (Số bản lưu giữ trên đĩa)**:
  - Với Job `full`: Nhập số bản Full muốn giữ lại (ví dụ `7` bản). Bản thứ 8 trở đi sẽ tự động bị xóa gọn gàng.
  - Với Job `incremental`: Nhập số **chuỗi hoàn chỉnh (`COMPLETE CHAINS`)** muốn giữ (ví dụ `2` chuỗi = giữ nguyên 2 tuần gần nhất; công cụ không bao giờ xóa lẻ mất bản `000_backup-full` khi các bản `backup-incremental` phụ thuộc vào nó còn giữ).
- **Câu hỏi cuối — `Customize advanced options ...? [y/N]`**:
  - Bấm **Enter (`no`)** để lưu ngay và đồng bộ vào `crontab` của user `zimbra`.
  - Chọn **`y`** nếu bạn muốn lọc riêng theo Domain/User, chỉnh chu kỳ mở chuỗi Full mới, số luồng song song, hoặc thời điểm xóa bản cũ.

> **Ví dụ thực tế 1 (Tạo Job Incremental lưu vào `/backup`, chạy 02:00 sáng hằng ngày, giữ 2 tuần)**:
> 1. Vào `Main Menu` -> bấm `1` -> bấm `1`.
> 2. `1. Job ID`: gõ `daily-incr` -> Enter.
> 3. `2. Select Backup Mode`: gõ `2` (incremental) -> Enter.
> 4. `3. Backup Storage Directory`: gõ `/backup` -> Enter (hệ thống báo `-> Snapshots for job 'daily-incr' will be saved in: /backup/incremental/daily-incr`).
> 5. `4. Configure Schedule`: gõ `1` (Daily) -> tại `Run time HH:MM (24h)` gõ `02:00` -> Enter.
> 6. `5. Retention Policy`: bấm Enter để giữ mặc định `2` chuỗi hoàn chỉnh (1 Full + 6 Incr mỗi chuỗi).
> 7. `Customize advanced options?`: bấm Enter (`no`). Hệ thống tự ghi `/var/lib/zimbra-backup/jobs/daily-incr.conf` và nạp vào `crontab -l -u zimbra`.

#### B. Mục `1 -> 2`: Chỉnh sửa Job đã có (`Edit existing job`)

Màn hình sửa Job cho phép sửa **bất kỳ thông số đơn lẻ nào** chỉ bằng 1 phím số `1..10`, sau đó bấm `s` để lưu và cập nhật lại Crontab:

| Phím | Tên trường | Ý nghĩa & Giá trị có thể chọn |
|---|---|---|
| `1` | `Backup Mode` | Chuyển đổi giữa `full` và `incremental`. |
| `2` | `Schedule (Cron)` | Đổi giờ chạy `HH:MM`, đổi ngày trong tuần/tháng hoặc biểu thức cron. |
| `3` | `Retention Keep` | Số bản Full (hoặc số chuỗi Incremental) giữ lại trước khi tự dọn bản cũ (`1..365`). |
| `4` | `Full Chain Cycle` | *(Dành cho Incremental)* Khi nào tự mở chuỗi `000_full` mới: `1) max_incr` (sau N bản Incr, mặc định `6`), `2) weekly` (vào một thứ cố định, ví dụ `0`=Chủ Nhật), `3) monthly` (vào ngày cố định `1..28`). |
| `5` | `Target Directory` | Đặt thư mục lưu riêng cho Job này (ví dụ `/mnt/nas2`), hoặc gõ `default` để dùng chung `DEFAULT_BACKUP_DIR` (`/home/backup`). |
| `6` | `Backup Scope` | Phạm vi sao lưu: `1) All active accounts` (toàn máy chủ), `2) Specific domain(s)` (ví dụ `hdll.vn,sub.hdll.vn`), `3) Specific account(s)` (ví dụ `sep@hdll.vn,ketoan@hdll.vn`). |
| `7` | `Prune Timing` | Thời điểm xóa bản cũ quá hạn: `1) after` (Mặc định an toàn — tạo xong bản mới thành công rồi mới xóa bản cũ), `2) before` (Xóa bản cũ nhất trước khi chạy — chỉ dùng khi ổ cứng quá chật không đủ chỗ chứa đồng thời bản mới + bản cũ). |
| `8` | `Parallel Workers` | Số luồng tải hộp thư song song (`1..16`). Máy 4–8 CPU nên để `2..4` luồng để không gây nghẽn Zimbra mailboxd giờ cao điểm. |
| `9` | `Job Description` | Ghi chú mô tả cho Job. |
| `10` | `Schedule Enabled` | `yes` (bật chạy tự động theo lịch) hoặc `no` (tạm tắt lịch). |
| `s` | `Save & Sync Crontab` | Lưu mọi thay đổi và đồng bộ ngay vào `crontab` của `zimbra`. |

#### C. Các mục `1 -> 3, 4, 5, 6`

- **`3) View full job details`**: Hiển thị toàn bộ cấu hình chi tiết của 1 Job (bao gồm đường dẫn lưu trữ thực tế `/home/backup/full/<job_id>` hoặc `/home/backup/incremental/<job_id>` và dòng cron chính xác).
- **`4) Enable / Disable job cron schedule`**: Bật/tắt nhanh lịch chạy tự động của 1 Job (ví dụ tạm tắt đêm nay để bảo trì ổ cứng).
- **`5) Delete job configuration`**: Xóa file cấu hình Job và gỡ lịch khỏi Crontab. **An toàn tuyệt đối**: Các bản dữ liệu backup cũ đã tạo trên ổ cứng **vẫn được giữ nguyên**, không bị xóa theo!
- **`6) View & re-sync Zimbra crontab`**: Hiển thị khối `# BEGIN zimbra-backup ... # END zimbra-backup` trong `crontab` của user `zimbra` và đồng bộ lại. Rất hữu ích sau khi bạn chạy script nâng cấp phiên bản Zimbra (vì bộ cài Zimbra đôi khi ghi lại crontab mặc định).

---

### 3.2. Menu `2` — `Run Backup Now` (Chạy sao lưu thủ công ngay lập tức)

Khi bấm `2` từ Main Menu, có 3 chế độ chạy ngay:

```text
  1) Run a configured Job now
  2) Force a new Full chain for an Incremental Job (--force-full)
  3) Ad-hoc Full backup for specific email account(s)
  0) Back to main menu
```

1. **`1) Run a configured Job now`**:
   - Chọn 1 Job đã cấu hình để chạy ngay lập tức (không cần đợi tới giờ ban đêm).
   - Nếu Job đó là `incremental` và chưa có bản Full gốc nào, lần chạy đầu tiên sẽ tự động tạo bản `000_backup-full-DD-MM-YYYY_HHMMSS`; các lần chạy tiếp theo sẽ tạo `001_backup-incremental-DD-MM-YYYY_HHMMSS`, `002_backup-incremental-...`.
2. **`2) Force a new Full chain for an Incremental Job (--force-full)`**:
   - Dùng cho Job `incremental` khi bạn vừa thay đổi lớn trên hệ thống (ví dụ vừa thêm hàng loạt tài khoản, dọn dẹp hộp thư lớn) và muốn **ngắt chuỗi cũ, mở ngay một chuỗi `chain-DD-MM-YYYY_HHMMSS/000_backup-full-...` mới tinh** ngay lúc này.
3. **`3) Ad-hoc Full backup for specific email account(s)`**:
   - Sao lưu nhanh **1 hoặc vài tài khoản lẻ** mà không cần tạo Job định kỳ (rất tiện trước khi xóa tài khoản nhân viên nghỉ việc hoặc trước khi thao tác nhạy cảm trên hộp thư VIP).
   - **Ví dụ thực tế**:
     - Chọn `2` -> chọn `3`.
     - `Account email(s) (comma-separated)`: gõ `giamdoc@hdll.vn` -> Enter.
     - `Base backup directory (saved under <dir>/account) [/home/backup]`: bấm Enter.
     - Hệ thống tự động lưu vào nhánh riêng `/home/backup/account/backup-giamdoc@hdll.vn-02-11-2026_101500/` (xuất đầy đủ cả cấu hình LDAP + mật khẩu + chữ ký + hộp thư `.tgz`). Nếu nhập nhiều email cùng lúc (ví dụ `giamdoc@hdll.vn,ketoan@hdll.vn`), thư mục sẽ mang tên `backup-giamdoc@hdll.vn+1more-02-11-2026_101500/`.
     - Khi cần khôi phục lại bản sao lưu lẻ này, vào **Menu 4 (`Restore from Custom Dir`)** và nhập `/home/backup/account` (hoặc `/home/backup`).

---

### 3.3. Menu `3` — `Restore from Backup Job` (Khôi phục từ Job đã cấu hình)

Menu `3` dùng để khôi phục từ các bản sao lưu do chính các Job của `zimbra-backup` tạo ra. Nó **chỉ quét đúng thư mục của các Job đã cấu hình** (`<target_dir>/full/<job_id>` và `<target_dir>/incremental/<job_id>`), giúp danh sách gọn gàng, chính xác, không lẫn các thư mục ngoài hay thư mục `account/`.

#### Quy trình 4 bước khôi phục chuẩn trên Menu `3` (và Menu `4`)

Sau khi chọn Job cần khôi phục (ví dụ `1` cho Job cụ thể hoặc `a` để xem gộp tất cả các Job), màn hình hiển thị bảng **Catalog** sắp xếp từ **mới nhất (`NO. 1`) đến cũ nhất**:

```text
NO.  JOB             TYPE         CREATED (UTC)         USERS  SIZE        BACKUP ID / PATH
--------------------------------------------------------------------------------------------------------------------
[1]  daily-incr      incr(#2)     2026-11-03T19:00:08Z  70     120.40 MiB  incremental/daily-incr/chain-01-11-2026_020000/002_backup-incremental-03-11-2026_020008
[2]  daily-incr      incr(#1)     2026-11-02T19:00:05Z  70     85.15 MiB   incremental/daily-incr/chain-01-11-2026_020000/001_backup-incremental-02-11-2026_020005
[3]  daily-incr      full         2026-11-01T19:00:10Z  70     54.58 GiB   incremental/daily-incr/chain-01-11-2026_020000/000_backup-full-01-11-2026_020010
```

> **Cơ chế tự động ghép chuỗi Incremental**: Bạn không cần tự nạp bản Full rồi nạp từng bản Incremental thủ công! Nếu bạn chọn khôi phục mốc thời gian **`[1]` (`002_backup-incremental-...`)**, công cụ sẽ tự động kiểm tra SHA-256 của cả chuỗi, khôi phục cấu hình LDAP mới nhất ở mốc `002`, sau đó tự động nạp hộp thư tuần tự theo đúng thứ tự: **`000_backup-full` -> `001_backup-incremental` -> `002_backup-incremental`**.

Tiếp theo bạn đi qua **4 bước (`Step 1` -> `Step 4`)**:

##### `Step 1` — Chọn điểm thời gian cần khôi phục (`Select backup number [NO.]`)
- Nhập số thứ tự ở cột `NO.` (ví dụ gõ `1` để lấy bản mới nhất). Nhập `0` nếu muốn hủy.

##### `Step 2` — Chọn phạm vi khôi phục (`Restore Scope`)
```text
Step 2 - Restore Scope:
  1) Full server (all domains, accounts, DLs, aliases, signatures, mailboxes)
  2) By domain(s)
  3) Specific user account(s) (search & select 1 or more users)
```
- Chọn **`1` (`Full server`)**: Khôi phục **toàn bộ máy chủ** — tự động tạo lại tất cả Domains, tất cả Accounts, Distribution Lists (nhóm mail), Aliases, chữ ký, bộ lọc, quyền Admin và toàn bộ hộp thư.
- Chọn **`2` (`By domain(s)`)**: Khôi phục toàn bộ tài khoản và nhóm mail thuộc 1 hoặc nhiều tên miền (ví dụ gõ `hdll.vn` hoặc `hdll.vn,chi-nhanh.vn`).
- Chọn **`3` (`Specific user account(s)`)**: Khôi phục **1 hoặc một vài tài khoản cụ thể**:
  1. `Filter accounts by keyword/domain (press Enter to list all)`: Gõ từ khóa (ví dụ `hieu` hoặc `ketoan`) để lọc nhanh, hoặc bấm **Enter** để liệt kê toàn bộ danh sách kèm dung lượng hộp thư từng người.
  2. `Enter number(s) (e.g. 1,3,5) or email(s)`: Có thể chọn 1 người (ví dụ `12`), chọn nhiều người cùng lúc cách nhau bằng dấu phẩy (ví dụ `2,5,18`), hoặc gõ thẳng địa chỉ email.
  3. **Câu hỏi chuyển hướng khi chỉ chọn 1 tài khoản**:
     `Restore into a DIFFERENT destination email account? [y/N]:`
     - **Bấm Enter (`no` — Mặc định khuyên dùng)**: Khôi phục thẳng về **đúng tài khoản gốc đó** (tự động tạo lại tài khoản nếu trên server đã bị xóa).
     - **Chỉ gõ `y` (`yes`)** khi bạn muốn lấy dữ liệu của người A (ví dụ `nhanvien_cu@hdll.vn`) đổ sang hộp thư của **người B khác** (ví dụ `quanly@hdll.vn`).

##### `Step 3` — Chọn thành phần dữ liệu & Chế độ xử lý trùng lặp (`Components & Conflict Handling`)
```text
Step 3 - Components & Conflict Handling:
  1) Both LDAP account settings + Mailbox data (default)
  2) Mailbox data only (.tgz emails, contacts, calendar)
  3) LDAP settings only (password hash, quota, aliases, signatures, filters)
```
- **`1) Both LDAP account settings + Mailbox data`** *(Mặc định)*: Khôi phục **trọn vẹn 100% tài khoản** (cả mật khẩu gốc, tên hiển thị tiếng Việt, quota, alias, chữ ký, bộ lọc mail lẫn toàn bộ email/danh bạ/lịch).
- **`2) Mailbox data only`**: Chỉ nạp lại email/danh bạ/lịch (giữ nguyên mật khẩu, quota và cấu hình tài khoản hiện tại). **Rất quan trọng khi khôi phục sang tài khoản người khác (`--target-user`)** để không ghi đè mật khẩu của người nhận!
- **`3) LDAP settings only`**: Chỉ khôi phục mật khẩu, quota, alias, chữ ký, bộ lọc mail trong vài giây mà không nạp lại hàng chục GB hộp thư.

Nếu có khôi phục hộp thư (`1` hoặc `2`), công cụ hỏi tiếp **Chế độ xử lý khi email đã tồn tại (`Mailbox Conflict Mode`)**:

| Tùy chọn | Tên chế độ | Hành vi thực tế đối với hộp thư đang hoạt động | Khi nào nên chọn? |
|---|---|---|---|
| **`1`** | **`skip`** *(Mặc định)* | **Giữ nguyên 100%** mọi email đang có trên server; chỉ nạp bổ sung những email/thư mục bị thiếu (đã lỡ xóa). | Khi user lỡ tay xóa mất mail cũ nhưng vẫn cần giữ nguyên các mail mới vừa nhận hôm nay, hoặc khi dựng server mới. |
| **`2`** | **`subfolder`** | Không đụng vào `Inbox` hay `Sent` hiện tại; toàn bộ dữ liệu bản backup được đưa gọn vào một thư mục riêng (ví dụ `/Restore_20261102_1430`). | Khi muốn đối chiếu, tìm lại một vài thư cũ hoặc bàn giao hộp thư nhân viên cũ sang hộp thư quản lý. |
| **`3`** | **`modify`** | Giữ các thư mới đang có; nếu thư trùng ID với bản backup thì cập nhật lại trạng thái/nội dung theo bản backup, đồng thời thêm thư còn thiếu. | Khi thư mục/trạng thái mail bị xáo trộn cần đồng bộ lại theo bản sao lưu mà không muốn xóa mail mới phát sinh. |
| **`4`** | **`reset`** | **XÓA SẠCH toàn bộ hộp thư hiện tại** của tài khoản đích rồi nạp nguyên trạng bản backup vào thay thế (mọi email mới nhận sau thời điểm backup sẽ bị xóa). | Chỉ dùng khi hộp thư bị hỏng nặng/nhiễm rác hàng loạt và bạn muốn quay ngược 100% hộp thư về đúng thời điểm sao lưu. |

##### `Step 4` — Chạy thử kiểm tra trước (`Dry-Run`) & Thực thi
- `Step 4 - Preview with Dry-Run first (no changes made)? [y/N]:`
  - Nếu chọn `y`, công cụ sẽ kiểm tra file, liệt kê chính xác chuỗi các bước sẽ chạy, số lượng tài khoản, chế độ nạp mà **không ghi bất kỳ thay đổi nào vào Zimbra**. Sau khi xem xong bản nháp, công cụ hỏi `Proceed with LIVE restore now? [y/N]:` — gõ `y` để bắt đầu chạy thật!
  - Nếu bấm **Enter (`no`)** ở câu hỏi Dry-Run, quá trình khôi phục thật sẽ bắt đầu ngay.

---

### 3.4. Menu `4` — `Restore from Custom Dir` (Khôi phục từ thư mục ngoài / bản cũ)

Menu `4` được thiết kế tách biệt hoàn toàn với các Job định kỳ để bạn khôi phục từ:
- Thư mục chứa bản backup của các script cũ (`auto_full_backup.sh` như `/backup` hoặc `/backup/full/20261031_174042`).
- Ổ cứng USB / NAS / NFS gắn từ máy chủ Zimbra cũ sang máy chủ mới dựng chưa tạo Job nào.
- Bản sao lưu lẻ từng tài khoản (`Account` trong `/home/backup/account/backup-<email>-DD-MM-YYYY_HHMMSS`).

Giao diện Menu `4`:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.0) - mail
  >> RESTORE FROM CUSTOM DIRECTORY
============================================================
  Configured Custom Restore Dir : (not set)
  (Separate from Backup Jobs - supports external NAS/USB, ad-hoc & legacy dirs)
------------------------------------------------------------
  1) Configure Custom Restore Dir & start restore
  2) Restore from a one-time directory path (do not overwrite config)
  3) Set / Change configured Custom Restore Dir
  0) Back to main menu
```

**Ý nghĩa từng dòng lựa chọn:**

1. **`1) Configure Custom Restore Dir & start restore`** *(khi đã lưu đường dẫn thì hiển thị `1) Restore from configured Custom Restore Dir (...)`)*:
   - Dùng khi bạn có một thư mục chứa bản backup cố định hay dùng lại nhiều lần (ví dụ `/backup` hoặc `/mnt/nas-restore`).
   - Lần đầu bấm `1`, bạn nhập đường dẫn (ví dụ `/backup`) -> công cụ **lưu đường dẫn này vào cấu hình** và quét ngay danh sách bản backup để bắt đầu 4 bước khôi phục. Từ lần sau trở đi, vào Menu `4` bấm `1` là vào thẳng danh sách bản backup mà không cần gõ lại đường dẫn!
2. **`2) Restore from a one-time directory path (do not overwrite config)`**:
   - Dùng để quét và khôi phục **tạm thời 1 lần duy nhất** từ một đường dẫn bất kỳ (ví dụ ổ cứng cắm tạm `/mnt/usb_khachhang`) mà **không làm thay đổi** cấu hình thư mục cố định ở dòng 1.
3. **`3) Set / Change configured Custom Restore Dir`**:
   - Chỉ dùng để đổi sang đường dẫn mặc định khác, hoặc gõ `none` (hoặc `-`) để xóa đường dẫn đã lưu về trạng thái `(not set)`.

> **Khả năng dò tự động nhiều tầng theo bất kỳ đường dẫn nào bạn cung cấp (không cố định tên thư mục)**:
> Công cụ không ép cứng tên `/backup` hay `/full`, mà **quét đệ quy thông minh (tối đa 5 tầng thư mục con)** bắt đầu từ **chính đường dẫn bất kỳ mà bạn nhập vào** để tìm mọi thư mục có dấu hiệu bản sao lưu hợp lệ (`manifest` hoặc `accounts/active_accounts.txt` + `mailboxes/`) và dừng ngay không quét sâu vào bên trong `mailboxes/`. Ví dụ:
> - Bạn nhập `/backup` -> Tự tìm thấy `/backup/full/20261031_174042`!
> - Bạn nhập `/data/zimbra_cu` -> Tự tìm thấy `/data/zimbra_cu/server_hcm/thang_10/ban_truoc_upgrade`!
> - Bạn nhập `/mnt/nas_khachhang` -> Tự tìm thấy mọi bản Full, chuỗi Incremental, bản lẻ `adhoc_*` hoặc bản `legacy` nằm bất kỳ đâu bên dưới `/mnt/nas_khachhang`!
> - Bạn nhập trực tiếp `/backup/full/20261031_174042` -> Nhận diện trực tiếp ngay lập tức!

---

### 3.5. Menu `5` — `Backup Catalog & Verify` (Tra cứu User, Kiểm tra SHA-256 & Dọn rác)

Khi bấm `5` từ Main Menu, công cụ hiển thị ngay dung lượng ổ cứng (`df -h`) kèm bảng danh sách toàn bộ bản sao lưu của các Job và 4 tiện ích kiểm tra:

```text
  1) Inspect snapshot details & search accounts inside backup
  2) Verify SHA-256 checksums of a backup / chain
  3) Switch catalog view to a Custom Directory
  4) Clean leftover '.pending.*' staging directories
  0) Back to main menu
```

1. **`1) Inspect snapshot details & search accounts inside backup`**:
   - Nhập số thứ tự bản backup `[NO.]` (ví dụ `1`), sau đó nhập từ khóa email cần tìm (ví dụ `nguyen`, hoặc bấm **Enter** để xem tất cả).
   - Công cụ in ra: thông tin Manifest (thời gian tạo, dung lượng, số lượng domain/user) và danh sách từng tài khoản khớp từ khóa kèm kích thước file `.tgz` của người đó (giúp bạn biết chắc chắn tài khoản cần tìm có nằm trong bản backup ngày hôm đó hay không và nặng bao nhiêu MB/GB trước khi khôi phục).
2. **`2) Verify SHA-256 checksums of a backup / chain`**:
   - Nhập số thứ tự `[NO.]` cần kiểm tra (ví dụ `1`).
   - Công cụ tính toán lại mã băm `SHA-256` từng file `.tgz` trên ổ cứng và đối chiếu với `manifest` gốc lúc sao lưu. Nếu là bản Incremental, nó kiểm tra xuyên suốt từ `000_full` đến bản Incremental đó. Nếu báo `Verification PASSED`, bản sao lưu đảm bảo nguyên vẹn 100% từng byte!
3. **`3) Switch catalog view to a Custom Directory`**:
   - Chuyển màn hình Catalog sang soi một thư mục ngoài (ví dụ `/backup` hoặc `/mnt/nas`) để tra cứu tài khoản hoặc verify checksum các bản backup nằm ngoài Job. Bấm `3` lần nữa để quay về xem kho Job mặc định.
4. **`4) Clean leftover '.pending.*' staging directories`**:
   - Khi đang sao lưu dở dang, `zimbra-backup` luôn ghi vào thư mục ẩn tạm `.pending.<timestamp>` rồi mới đổi tên nguyên tử sang tên thật khi hoàn tất 100%. Nếu máy chủ bị cúp điện đột ngột giữa đêm làm sót lại thư mục `.pending.*`, bấm `4` để dọn sạch dung lượng đĩa (chỉ chạy được khi không có tiến trình backup nào đang hoạt động).

---

### 3.6. Menu `6` — `Global Settings & Alerts` (Cấu hình chung & Cảnh báo Telegram/Email)

Khi bấm `6` từ Main Menu:

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.0) - mail
  >> GLOBAL SETTINGS & ALERTS
============================================================
  1) Default job backup dir   : /home/backup
  2) Custom restore directory : (not set)
  3) Require mountpoint       : no
  4) Disk warning / Min free  : 85% / 1024 MB
  5) Server label (alerts)    : (auto: mail.hdll.vn)
  6) Telegram Bot alerts      : no
  7) Email failure alerts     : no
  8) Send test Telegram alert
  0) Back to main menu
```

- **Mục `1` (`Default job backup dir`)**: Đổi thư mục lưu trữ mặc định cho các Job (mặc định là `/home/backup`).
- **Mục `2` (`Custom restore directory`)**: Đặt hoặc xóa (`none`) đường dẫn mặc định cho Menu 4.
- **Mục `3` (`Require mountpoint`)**: Bật `yes` nếu dùng ổ NAS/NFS/SAN gắn ngoài để chống ghi nhầm vào ổ OS khi mất kết nối mạng lưu trữ.
- **Mục `4` (`Disk warning / Min free`)**:
  - `Disk usage warning threshold (%)` *(mặc định `85%`)*: Khi ổ đĩa vượt quá 85%, công cụ vẫn chạy nhưng sẽ gửi cảnh báo dung lượng cao.
  - `Minimum free disk space (MB)` *(mặc định `1024` MB = 1 GB)*: Nếu dung lượng trống còn dưới mức này, công cụ từ chối chạy để tránh làm treo máy chủ vì đầy đĩa 100%.
- **Mục `5` (`Server label`)**: Đặt tên gợi nhớ cho máy chủ xuất hiện trên tin nhắn Telegram/Email (ví dụ `Mail-HCM-Primary`; để trống sẽ tự lấy `zmhostname`).
- **Mục `6` (`Telegram Bot alerts`) & Mục `8` (`Send test Telegram alert`)**:
  - Cho phép gửi thông báo kết quả (Thành công `[OK]`, Cảnh báo `[WARN]`, Thất bại `[ERROR]`) kèm thời gian chạy và dung lượng về nhóm Telegram trực hệ thống:
    1. Tạo Bot qua `@BotFather` trên Telegram để lấy **Bot Token** (dạng `123456789:AAH...`).
    2. Thêm Bot vào nhóm nhận cảnh báo và lấy **Chat ID** (thường bắt đầu bằng dấu trừ `-100...` cho Supergroup). Nếu nhóm bật chế độ chia chủ đề (Topics), nhập thêm **Topic Thread ID**, nếu không thì để trống bấm Enter.
    3. Lưu ý bảo mật: Bot Token không bao giờ bị lộ trên `ps aux` vì công cụ truyền qua file cấu hình tạm quyền `0600` trong `/var/lib/zimbra-backup/run/`.
    4. Sau khi bật ở mục `6`, bấm ngay **mục `8` (`Send test Telegram alert`)** để nhận tin nhắn thử nghiệm trên điện thoại!
- **Mục `7` (`Email failure alerts`)**: Gửi email cảnh báo qua `sendmail` của Zimbra tới địa chỉ quản trị khi sao lưu gặp lỗi.

---

### 3.7. Menu `7` — `View Logs` (Xem nhật ký thực thi)

- Liệt kê 15 file log gần nhất trong `/var/lib/zimbra-backup/logs/` (sắp xếp mới nhất ở số `1`).
- Nhập số thứ tự file log (ví dụ `1`) để đọc ngay 100 dòng cuối cùng ngay trên giao diện TUI mà không cần thoát ra gõ lệnh Linux.
- Hệ thống đã cài sẵn cấu hình `/etc/logrotate.d/zimbra-backup` tự động nén `.gz` và giữ lịch sử log 12 tuần gọn gàng.

---

## 4. Cẩm nang toàn bộ lệnh CLI (`zimbra-backup <lệnh>`) & Ví dụ từng lệnh

Toàn bộ tính năng trên Menu TUI đều có lệnh CLI tương ứng để bạn viết script tự động hóa, chạy qua Ansible/SSH, hoặc thao tác nhanh chỉ bằng 1 dòng lệnh. Bạn có thể gõ dưới quyền `root` hoặc `zimbra` (nếu gõ từ `root`, công cụ tự động chuyển sang `zimbra`).

Xem nhanh trợ giúp bất cứ lúc nào:

```bash
zimbra-backup --help
```

---

### 4.1. Lệnh `init` — Khởi tạo & sửa cấu hình hệ thống

**Cú pháp đầy đủ:**

```text
zimbra-backup init [--backup-dir <path>] [--restore-dir <path|none>]
                   [--require-mount <yes|no>] [--create-dir]
                   [--disk-warn <1-99>] [--disk-min-mb <MB>]
                   [--host-label <ten_server>]
                   [--telegram-enabled <yes|no>] [--telegram-token <token>]
                   [--telegram-chat <chat_id>] [--telegram-thread <thread_id>]
                   [--email-enabled <yes|no>] [--email-to <email>]
```

**Ví dụ 1 — Khởi tạo nhanh thư mục lưu trữ nội bộ `/home/backup` (tự tạo thư mục nếu chưa có):**

```bash
zimbra-backup init --backup-dir /home/backup --require-mount no --create-dir
```

**Ví dụ 2 — Khởi tạo cho ổ lưu trữ NFS `/mnt/zimbra_nas` (bắt buộc kiểm tra mount) kèm cảnh báo ổ đĩa 80% và tối thiểu 5 GB trống:**

```bash
zimbra-backup init --backup-dir /mnt/zimbra_nas --require-mount yes --disk-warn 80 --disk-min-mb 5120
```

**Ví dụ 3 — Cấu hình sẵn thư mục khôi phục ngoài `/backup` và bật cảnh báo Telegram + Email:**

```bash
zimbra-backup init \
  --restore-dir /backup \
  --host-label "Zimbra-HDLL-Prod" \
  --telegram-enabled yes \
  --telegram-token "7123456789:AAExampleBotTokenString12345" \
  --telegram-chat "-1001987654321" \
  --email-enabled yes \
  --email-to "it-admin@hdll.vn"
```

**Ví dụ 4 — Xóa cấu hình thư mục Restore riêng về mặc định trống:**

```bash
zimbra-backup init --restore-dir none
```

---

### 4.2. Lệnh `job` — Tạo, sửa, bật/tắt, xóa và chạy Job

**Các lệnh con của `job`:**

| Lệnh con | Chức năng |
|---|---|
| `zimbra-backup job list` | Hiển thị bảng danh sách toàn bộ các Job, loại sao lưu, lịch chạy và số bản giữ lại. |
| `zimbra-backup job show <job_id>` | Xem chi tiết toàn bộ 15 tham số cấu hình và đường dẫn thực tế của 1 Job. |
| `zimbra-backup job add <job_id> [options]` | Tạo Job mới và tự động đăng ký vào Crontab của `zimbra`. |
| `zimbra-backup job edit <job_id> [options]` | Chỉnh sửa 1 hoặc nhiều thông số của Job đã có và đồng bộ lại Crontab. |
| `zimbra-backup job enable <job_id>` | Bật lại lịch chạy tự động cho Job đang tạm tắt. |
| `zimbra-backup job disable <job_id>` | Tạm tắt lịch chạy tự động (giữ nguyên cấu hình Job). |
| `zimbra-backup job delete <job_id> [--yes]` | Xóa cấu hình Job và gỡ khỏi Crontab (giữ nguyên dữ liệu backup trên đĩa). |
| `zimbra-backup job run <job_id> [--force-full]` | Chạy ngay lập tức một Job (thêm `--force-full` nếu muốn ép mở chuỗi Full mới). |

**Bảng tham số cho `job add` và `job edit`:**

| Tham số | Giá trị hợp lệ | Mặc định | Giải thích |
|---|---|---|---|
| `--name "<mô tả>"` | Chuỗi ASCII | `Scheduled backup <id>` | Tên mô tả hiển thị của Job. |
| `--type` | `full` \| `incremental` | `full` | Chế độ Full độc lập hoặc chuỗi Incremental. |
| `--target-dir` | Đường dẫn hoặc `default` | `default` | Thư mục lưu riêng của Job (`default` kế thừa `DEFAULT_BACKUP_DIR`). |
| `--require-mount` | `inherit` \| `yes` \| `no` | `inherit` | Ghi đè chế độ kiểm tra mount riêng cho Job này. |
| `--scope` | `all` \| `domains` \| `accounts` | `all` | Phạm vi sao lưu: toàn máy chủ, theo domain, hoặc danh sách email. |
| `--scope-values` | Danh sách phân cách dấu phẩy | *(trống)* | Ví dụ `hdll.vn,sub.hdll.vn` hoặc `a@hdll.vn,b@hdll.vn`. |
| `--schedule` | `daily` \| `weekly` \| `monthly` \| `custom` \| `off` | `daily` | Kiểu lập lịch Crontab. |
| `--hour` / `--minute` | `0..23` / `0..59` | `2` / `0` | Giờ và phút chạy (hỗ trợ cả dãy cron như `1,13`). |
| `--dow` | `0..7` (hoặc `1-5`, `0,3`) | `*` | Thứ trong tuần khi `--schedule weekly` (`0` hoặc `7` là Chủ Nhật). |
| `--dom` / `--month` | `1..31` / `1..12` hoặc `*` | `*` / `*` | Ngày và tháng chạy khi `--schedule monthly`. |
| `--cron-expr` | Chuỗi Cron 5 trường | `"0 2 * * *"` | Tự động chuyển `--schedule` sang `custom`. |
| `--full-cycle` | `max_incr` \| `weekly` \| `monthly` | `max_incr` | Quy tắc tự mở chuỗi Full mới cho Job Incremental. |
| `--full-cycle-value` | Số nguyên | `6` | Số bản Incr tối đa (`1..60`), hoặc thứ (`0..6`), hoặc ngày (`1..28`). |
| `--keep` | `1..365` | `7` (Full) / `2` (Incr) | Số bản Full hoặc số chuỗi hoàn chỉnh giữ lại. |
| `--prune-timing` | `after` \| `before` | `after` | Xóa bản cũ sau khi bản mới xong (`after`) hay trước khi chạy (`before`). |
| `--parallel` | `1..16` | `2` (Full) / `4` (Incr) | Số luồng trích xuất hộp thư song song. |
| `--enabled` | `yes` \| `no` | `yes` | Bật/tắt lịch tự động ngay lúc tạo/sửa. |

**Ví dụ 1 — Tạo Job Full hằng ngày lúc `01:30` sáng, giữ 7 bản gần nhất:**

```bash
zimbra-backup job add full-daily \
  --name "Daily Full Server Backup" \
  --type full \
  --schedule daily --hour 1 --minute 30 \
  --keep 7 --prune-timing after --parallel 2
```

**Ví dụ 2 — Tạo Job Incremental chạy `02:00` hằng ngày, cứ Chủ Nhật (`dow=0`) mở chuỗi Full mới, giữ 2 chuỗi (~2 tuần):**

```bash
zimbra-backup job add incr-weekly-chain \
  --name "Weekly Full + Daily Incremental" \
  --type incremental \
  --schedule daily --hour 2 --minute 0 \
  --full-cycle weekly --full-cycle-value 0 \
  --keep 2 --parallel 4
```

**Ví dụ 3 — Tạo Job Full định kỳ mùng 1 và ngày 15 hằng tháng lúc `03:00` lưu sang ổ lưu trữ dài hạn `/mnt/archive`:**

```bash
zimbra-backup job add archive-bimonthly \
  --name "Archive 1st and 15th" \
  --type full \
  --target-dir /mnt/archive \
  --schedule monthly --dom 1,15 --month "*" --hour 3 --minute 0 \
  --keep 6
```

**Ví dụ 4 — Tạo Job chỉ sao lưu riêng 1 tên miền `hdll.vn` mỗi 12 tiếng bằng biểu thức Cron tùy chỉnh:**

```bash
zimbra-backup job add domain-hdll \
  --type incremental \
  --scope domains --scope-values "hdll.vn" \
  --cron-expr "0 1,13 * * *" \
  --full-cycle max_incr --full-cycle-value 13 \
  --keep 2
```

**Ví dụ 5 — Sửa giờ chạy của Job `full-daily` sang `00:45` và tăng lên 4 luồng:**

```bash
zimbra-backup job edit full-daily --hour 0 --minute 45 --parallel 4
```

**Ví dụ 6 — Chạy ngay một Job bằng tay, hoặc ép mở chuỗi Full mới cho Job Incremental:**

```bash
zimbra-backup job run full-daily
```

```bash
zimbra-backup job run incr-weekly-chain --force-full
```

**Ví dụ 7 — Tạm tắt, bật lại, hoặc xóa cấu hình Job:**

```bash
zimbra-backup job disable full-daily
```

```bash
zimbra-backup job enable full-daily
```

```bash
zimbra-backup job delete archive-bimonthly --yes
```

---

### 4.3. Lệnh `cron` — Xem & đồng bộ lại Crontab Zimbra

**Ví dụ 1 — Xem các dòng lịch chạy tự động đang được `zimbra-backup` quản lý trong `crontab` của `zimbra`:**

```bash
zimbra-backup cron show
```

**Ví dụ 2 — Đồng bộ lại Crontab từ các file Job trong `/var/lib/zimbra-backup/jobs/*.conf` (dùng sau khi nâng cấp Zimbra):**

```bash
zimbra-backup cron sync
```

---

### 4.4. Lệnh `backup` — Xem danh sách, tìm User, kiểm tra SHA-256 & sao lưu lẻ

**Ví dụ 1 — Liệt kê tất cả các bản backup thuộc các Job đã cấu hình trên máy:**

```bash
zimbra-backup backup list
```

**Ví dụ 2 — Chỉ liệt kê các bản backup của riêng 1 Job `full-daily`:**

```bash
zimbra-backup backup list --job full-daily
```

**Ví dụ 3 — Quét danh sách các bản backup nằm ở thư mục ngoài (ví dụ `/backup` chứa `/backup/full/20261031_174042` hoặc ổ NAS `/mnt/nas`):**

```bash
zimbra-backup backup list --dir /backup
```

**Ví dụ 4 — Xem thông tin chi tiết bản backup số `1` và tìm các email có chứa chữ `nguyen`:**

```bash
zimbra-backup backup inspect 1 --search nguyen
```

*(Nếu soi bản backup ở thư mục ngoài `/backup`, thêm `--dir /backup`)*:

```bash
zimbra-backup backup inspect 1 --dir /backup --search hdll.vn
```

**Ví dụ 5 — Kiểm tra toàn vẹn mã băm `SHA-256` của bản backup số `1` (nếu là bản Incremental, tự động kiểm tra toàn bộ chuỗi từ `000_full` tới bản đó):**

```bash
zimbra-backup backup verify 1
```

**Ví dụ 6 — Sao lưu Full tức thời (Ad-hoc) cho 2 tài khoản cụ thể trước khi bảo trì/xóa user:**

```bash
zimbra-backup backup user "giamdoc@hdll.vn,ketoan@hdll.vn"
```

*(Hoặc chỉ định lưu vào một thư mục riêng `/mnt/usb_vip`)*:

```bash
zimbra-backup backup user "giamdoc@hdll.vn" --dir /mnt/usb_vip
```

**Ví dụ 7 — Dọn dẹp các thư mục tạm `.pending.*` bị bỏ dở do sập nguồn:**

```bash
zimbra-backup backup clean-pending
```

---

### 4.5. Lệnh `restore` — Khôi phục dữ liệu chuyên sâu bằng dòng lệnh

**Cú pháp đầy đủ:**

```text
zimbra-backup restore
  --from <NO. | backup_id | đường_dẫn_snapshot>
  [--job <job_id> | --dir <thư_mục_ngoài>]
  (--all | --domain <d1,d2> | --users <email1,email2>)
  [--target-user <email_đích_khác>]
  [--only <all|mailbox|ldap>]
  [--mode <skip|subfolder|modify|reset>]
  [--subfolder-name <tên_thư_mục_con>]
  [--dry-run]
  [--yes]
```

**Giải thích các tham số quan trọng:**
- `--from`: Chọn bản backup theo số thứ tự `NO.` trong lệnh `backup list` (ví dụ `1` là bản mới nhất), hoặc mã `backup_id`, hoặc đường dẫn tuyệt đối tới thư mục snapshot.
- `--job <job_id>`: Giới hạn tìm kiếm trong 1 Job cụ thể.
- `--dir <path>`: Khôi phục từ thư mục ngoài Job (ví dụ `--dir /backup` hoặc `--dir /home/backup/account`).
- **Bộ 3 phạm vi (chọn 1 trong 3)**:
  - `--all`: Khôi phục toàn bộ máy chủ (Domains + Accounts + DLs + Aliases + Signatures + Filters + Admins + Mailboxes).
  - `--domain <d1,d2>`: Khôi phục toàn bộ các tài khoản và nhóm mail thuộc tên miền chỉ định.
  - `--users <u1,u2>`: Khôi phục 1 hoặc nhiều tài khoản chỉ định.
- `--target-user <dest_email>`: *(Chỉ dùng khi `--users` truyền đúng 1 email)* Đổ dữ liệu của tài khoản nguồn sang hộp thư của một tài khoản đích khác.
- `--only`: `all` (cả LDAP + Mailbox — mặc định), `mailbox` (chỉ hộp thư `.tgz`), hoặc `ldap` (chỉ mật khẩu, quota, alias, chữ ký, bộ lọc).
- `--mode`: `skip` (mặc định an toàn — chỉ thêm mail còn thiếu), `subfolder` (nạp vào thư mục con riêng), `modify` (cập nhật mục trùng + thêm mục thiếu), `reset` (xóa trắng hộp thư hiện tại rồi nạp lại từ bản sao lưu).
- `--dry-run`: Chạy mô phỏng kiểm tra trước, không thay đổi dữ liệu thật.
- `--yes`: Bỏ qua câu hỏi xác nhận `[y/N]` (dùng khi viết script hoặc khi đã kiểm tra kỹ — đặc biệt cần thiết nếu chạy không tương tác với `--all` hoặc `--mode reset`).

**6 Ví dụ lệnh `restore` thực tế thường dùng nhất:**

**Ví dụ 1 — Chạy thử (`--dry-run`) kiểm tra kế hoạch khôi phục toàn bộ server từ thư mục `/backup`:**

```bash
zimbra-backup restore --dir /backup --from 1 --all --mode skip --dry-run
```

**Ví dụ 2 — Khôi phục toàn bộ máy chủ Zimbra mới dựng (Disaster Recovery) từ thư mục `/backup`:**

```bash
zimbra-backup restore --dir /backup --from 1 --all --only all --mode skip --yes
```

**Ví dụ 3 — Khôi phục bổ sung các email bị xóa nhầm cho 2 nhân viên từ Job `daily-incr` (bản mới nhất số `1`, giữ nguyên mail mới đang có):**

```bash
zimbra-backup restore --job daily-incr --from 1 --users "user1@hdll.vn,user2@hdll.vn" --mode skip --yes
```

**Ví dụ 4 — Khôi phục hộp thư của 1 user vào thư mục riêng `/KhoiPhuc_Thang10` để user tự kiểm tra và lọc lại thư cần lấy:**

```bash
zimbra-backup restore --from 1 --users "ketoan@hdll.vn" --only mailbox --mode subfolder --subfolder-name "KhoiPhuc_Thang10" --yes
```

**Ví dụ 5 — Bàn giao toàn bộ email của nhân viên đã nghỉ việc (`nv_nghiviec@hdll.vn`) vào thư mục `/BanGiao_NV_Cu` bên trong hộp thư của Trưởng phòng (`truongphong@hdll.vn`), giữ nguyên mật khẩu của Trưởng phòng:**

```bash
zimbra-backup restore \
  --from 1 \
  --users "nv_nghiviec@hdll.vn" \
  --target-user "truongphong@hdll.vn" \
  --only mailbox \
  --mode subfolder \
  --subfolder-name "BanGiao_NV_Cu" \
  --yes
```

**Ví dụ 6 — Chỉ khôi phục lại Mật khẩu gốc, Chữ ký và Bộ lọc mail (`--only ldap`) cho 1 tài khoản mà không tốn thời gian nạp lại hộp thư:**

```bash
zimbra-backup restore --from 1 --users "giamdoc@hdll.vn" --only ldap --yes
```

---

### 4.6. Lệnh `status` & `logs` — Kiểm tra trạng thái tổng thể & xem Log

**Xem toàn cảnh trạng thái hệ thống, danh sách Job và danh sách các bản Backup hiện có:**

```bash
zimbra-backup status
```

**Xem 80 dòng cuối của file log mới nhất:**

```bash
zimbra-backup logs
```

**Xem 200 dòng cuối của file log mới nhất:**

```bash
zimbra-backup logs latest 200
```

**Liệt kê tất cả các file log đang lưu trong `/var/lib/zimbra-backup/logs/`:**

```bash
zimbra-backup logs list
```

**Xem nội dung của một file log cụ thể theo tên:**

```bash
zimbra-backup logs job_full-daily_20261102_013000.log 150
```

---

## 5. Các kịch bản thực chiến hay gặp nhất (Step-by-Step)

### Kịch bản 1: Khôi phục từ thư mục `/backup` cũ (do `auto_full_backup.sh` tạo ra) lên Server mới

Giả sử trên máy chủ bạn đang có thư mục `/backup/full/20261031_174042` chứa 70 tài khoản (54.58 GiB):

1. Mở giao diện quản lý:
   ```bash
   zimbra-backup
   ```
2. Bấm phím **`4`** (`Restore from Custom Dir`).
3. Bấm phím **`1`** (`Configure Custom Restore Dir & start restore`) -> Nhập đường dẫn **`/backup`** -> Bấm **Enter**.
   - Công cụ tự động dò thấy `/backup/full/20261031_174042` (`legacy-full`, `70 USERS`, `54.58 GiB`) ở dòng `NO. 1`.
4. **`Step 1`**: Gõ **`1`** -> Enter.
5. **`Step 2`**:
   - Muốn khôi phục cả 70 tài khoản lên máy chủ mới: Gõ **`1`** (`Full server`) -> Enter.
   - Hoặc chỉ muốn khôi phục thử 1 tài khoản trước: Gõ **`3`** (`Specific user account(s)`) -> Gõ tên cần tìm -> Nhập số thứ tự tài khoản -> Tại câu hỏi `Restore into a DIFFERENT destination email account? [y/N]:` bấm **Enter (`no`)**.
6. **`Step 3`**:
   - Chọn thành phần: Bấm **Enter (`1` — Both LDAP account settings + Mailbox data)**.
   - Chọn chế độ xung đột: Bấm **Enter (`1` — `skip`)**.
7. **`Step 4`**:
   - Gõ **`y`** để xem bản xem trước `Dry-Run`, kiểm tra đúng số lượng user rồi gõ **`y`** ở câu `Proceed with LIVE restore now?` để bắt đầu nạp dữ liệu.

---

### Kịch bản 2: Thiết lập chiến lược Backup chuẩn Production cho doanh nghiệp (50–500 Users)

Chiến lược tối ưu dung lượng đĩa và độ an toàn cao nhất là kết hợp **1 Job Incremental hằng đêm** + **1 Job Full lưu trữ đầu tháng**:

1. Khởi tạo thư mục lưu trữ và cảnh báo Telegram:
   ```bash
   zimbra-backup init --backup-dir /home/backup --require-mount no --create-dir --disk-warn 85 --disk-min-mb 5120
   ```
2. Tạo Job số 1 — Sao lưu Incremental mỗi đêm lúc `01:30`, tự mở chuỗi Full mới vào mỗi Chủ Nhật (`dow=0`), giữ `2` chuỗi (~14 ngày khôi phục theo từng ngày):
   ```bash
   zimbra-backup job add prod-daily-incr \
     --name "Nightly Incremental Chain (14 days)" \
     --type incremental \
     --schedule daily --hour 1 --minute 30 \
     --full-cycle weekly --full-cycle-value 0 \
     --keep 2 --prune-timing after --parallel 4
   ```
3. Tạo Job số 2 — Sao lưu Full độc lập vào `03:30` sáng ngày mùng `1` hằng tháng, giữ `3` tháng gần nhất:
   ```bash
   zimbra-backup job add prod-monthly-full \
     --name "Monthly Standalone Full (3 months)" \
     --type full \
     --schedule monthly --dom 1 --month "*" --hour 3 --minute 30 \
     --keep 3 --prune-timing after --parallel 2
   ```
4. Kiểm tra lại lịch Crontab đã được nạp tự động:
   ```bash
   zimbra-backup cron show
   ```

---

## 6. Lưu ý kỹ thuật quan trọng & Xử lý sự cố thường gặp

### 6.1. Đặc thù của bản Incremental trên Zimbra Open Source Edition (OSE)
- Trên Zimbra OSE, công cụ trích xuất dữ liệu Incremental qua HTTPS REST API nội bộ với truy vấn `?fmt=tgz&query=after:<checkpoint_ms>` (có lùi đệm an toàn **5 phút / 300 giây** để không bao giờ bị lọt các email đang nhận dở lúc giao thời hoặc nửa đêm).
- Đây là cơ chế **sao lưu bồi đắp các thư/mục mới hoặc thay đổi**: nếu hôm qua user có 1.000 thư, hôm nay user tự tay xóa hẳn 50 thư rác rồi tối nay chạy Incremental, thì khi khôi phục cả chuỗi, 50 thư đã xóa kia vẫn có mặt trong bước `000_full` nên sẽ được khôi phục lại cùng 950 thư còn lại (không tự động xóa đi 50 thư đó). Khi bắt đầu chu kỳ `000_full` mới của tuần kế tiếp, hộp thư sẽ lại gọn đúng 950 thư thực tế.
- Khi bạn chọn chế độ `--mode reset` trên một bản Incremental, công cụ đã có cơ chế bảo vệ thông minh: bước 1 (`000_full`) chạy `resolve=reset` để làm sạch hộp thư, còn các bước `001_incr..NNN_incr` tiếp theo tự động chuyển sang `resolve=modify` để bồi đắp lên bản Full chứ không xóa trắng dữ liệu của bước trước.

### 6.2. Báo lỗi `Another zimbra-backup operation is already running (lock: /var/lib/zimbra-backup/operation.lock)`
- **Nguyên nhân**: Để bảo vệ toàn vẹn dữ liệu và không làm quá tải Zimbra, tại một thời điểm chỉ cho phép **1 tiến trình backup hoặc restore duy nhất** giữ khóa `flock`. Nếu đang có Job ban đêm chạy chưa xong mà bạn bấm chạy thêm Job khác (hoặc chạy Restore), tiến trình thứ 2 sẽ dừng lại an toàn.
- **Cách kiểm tra**: Chạy `ps aux | grep zimbra-backup` để xem tiến trình đang chạy và theo dõi tiến độ qua `zimbra-backup logs latest 50`. Ngay khi tiến trình đó kết thúc (kể cả bị tắt đột ngột), nhân Linux sẽ tự động nhả khóa `flock`.

### 6.3. Báo lỗi `Directory '...' is not writable by user 'zimbra'` hoặc không thấy thư mục ngoài
- **Nguyên nhân**: Bạn tạo thư mục `/backup` hoặc gắn ổ cứng bằng tài khoản `root` với quyền `0700 root:root`, khiến user `zimbra` không thể đi vào đọc/ghi.
- **Cách xử lý**: Cấp quyền sở hữu cho user `zimbra`:
  ```bash
  chown -R zimbra:zimbra /home/backup
  ```
  Hoặc với thư mục chỉ dùng để đọc bản backup cũ (`/backup`):
  ```bash
  chown -R zimbra:zimbra /backup
  ```

### 6.4. Sau khi nâng cấp phiên bản Zimbra (ví dụ từ 8.8.15 lên 10) lịch tự động không chạy?
- Bộ cài đặt nâng cấp của Zimbra đôi khi tạo lại file crontab mới cho user `zimbra`. Bạn chỉ cần gõ duy nhất 1 lệnh sau để nạp lại toàn bộ lịch chạy từ cấu hình đã lưu mà không phải tạo lại Job:
  ```bash
  zimbra-backup cron sync
  ```
