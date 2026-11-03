# Zimbra Backup (`zimbra-backup` v0.3.3)

Công cụ đóng gói `.rpm` và `.deb` hợp nhất dành cho máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** trên **Ubuntu 18.04, 20.04, 22.04 LTS** và **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**, trang bị **Menu tương tác TUI tiếng Anh rút gọn (100% Pure 7-bit ASCII — không bao giờ lỗi font `□` trên mọi SSH / VM Console)** cùng hệ thống **CLI tự động hóa** đầy đủ.

> **Tài liệu hướng dẫn sử dụng đầy đủ (từng màn hình Menu TUI & từng lệnh CLI kèm ví dụ chi tiết)**: Xem file [`HUONG_DAN_SU_DUNG.md`](HUONG_DAN_SU_DUNG.md).

---

## Tính năng chính

1. **Menu TUI tiếng Anh tinh gọn, hiển thị chuẩn trên mọi Terminal**:
   - **Vào thẳng Main Menu ngay lần chạy đầu tiên**: Tự động khởi tạo cấu hình chuẩn trong nền với thư mục lưu trữ mặc định `/home/backup`, không hiển thị màn hình cài đặt chặn người dùng.
   - **Tạo Job nhanh 5 bước đầy đủ**: `Job ID` -> `Chế độ (Full / Incremental)` -> `Đường dẫn thư mục lưu trữ & Kiểm tra ổ mount riêng/NFS` -> `Lịch chạy (nhập gộp Giờ:Phút dạng HH:MM)` -> `Số bản lưu giữ (mặc định 7 bản Full hoặc 2 chuỗi Incremental ~ 2 tuần)`.
   - **Chỉnh sửa Job 1 chạm**: Menu đánh số `1..10` hiển thị trực tiếp giá trị hiện tại của từng trường — cần đổi giờ chạy, số bản lưu hay thư mục chỉ cần bấm đúng số thứ tự mục đó rồi bấm `s` để lưu.
   - Toàn bộ giao diện, CLI và log dùng bảng mã **7-bit ASCII thuần**, loại bỏ triệt để hiện tượng ô vuông `□` trên console VMware/Proxmox/PuTTY hoặc môi trường `LANG=C` của `cron`.
2. **Quản lý Đa Job & Đồng bộ Crontab tự động theo quyền `zimbra`**:
   - Tạo, xem, **chỉnh sửa (`edit` sau khi cấu hình)**, bật/tắt, xóa và kích hoạt chạy ngay nhiều Job độc lập (`full` hoặc `incremental`).
   - Tự động chuyển sang quyền thực thi `zimbra` (`runuser -u zimbra`) khi gọi từ `root` và tự động cập nhật khối `# BEGIN zimbra-backup ... # END zimbra-backup` trong `crontab` của user `zimbra` mà không chạm vào khối `# ZIMBRASTART..# ZIMBRAEND` của hệ thống Zimbra.
3. **Tùy chỉnh ngày tháng & lịch chạy linh hoạt**:
   - Lịch **Hằng ngày** (`HH:MM`), **Hằng tuần** (chọn các thứ `0-6` + `HH:MM`), **Theo ngày/tháng cụ thể** (chọn ngày `1-31`, tháng `*` hoặc `1-12` + `HH:MM`), biểu thức **Cron 5 trường tùy chỉnh**, hoặc tắt lịch tự động (`off`).
4. **Quản lý số bản lưu trữ (`KEEP_COUNT`) & Chuỗi Incremental (`zb-backup-v2`)**:
   - Cấu hình số bản Full giữ lại (cho Job `full`, mặc định `7`) hoặc số **chuỗi hoàn chỉnh** giữ lại (cho Job `incremental`, mặc định `2` chuỗi), kèm tùy chọn thời điểm xóa bản cũ **sau khi bản mới thành công (`after` — mặc định an toàn)** hoặc **trước khi chạy (`before` — tiết kiệm đĩa)**.
   - Chuỗi Incremental gom `000_backup-full-<DD-MM-YYYY_HHMMSS>` + `001_backup-incremental-<DD-MM-YYYY_HHMMSS>..NNN_backup-incremental-<DD-MM-YYYY_HHMMSS>` với mốc `checkpoint` lùi đệm 5 phút chống sót mail qua nửa đêm hoặc khi gián đoạn; tự mở chuỗi Full mới theo chu kỳ cấu hình (`max_incr`, hằng tuần, hoặc hằng tháng).
   - **Tách riêng 3 thư mục phân loại rõ ràng dưới thư mục gốc (`/home/backup`)**:
     - `full/<job_id>/backup-full-DD-MM-YYYY_HHMMSS`
     - `incremental/<job_id>/chain-DD-MM-YYYY_HHMMSS/000_backup-full-...` & `001_backup-incremental-...`
     - `account/backup-<email>-DD-MM-YYYY_HHMMSS` (sao lưu lẻ từng tài khoản)
5. **Sao lưu chuẩn xác 100% dữ liệu người dùng tiếng Việt UTF-8 & Chữ ký**:
   - Giải mã dòng gập LDIF chuẩn RFC 2849 + Base64 UTF-8, bảo toàn nguyên vẹn tên hiển thị tiếng Việt có dấu (`displayName`), mật khẩu băm (`userPassword`), hạn ngạch (`zimbraMailQuota`), Alias, thành viên Distribution List (`zmprov -l gdlm`), chữ ký HTML/text (`zmprov -l gsig`), quyền Admin và bộ lọc Sieve nhiều dòng.
   - Kiểm tra toàn vẹn từng bản sao lưu bằng `manifest` SHA-256 + `tar -tzf` (không xóa nhầm hộp thư mới tạo rỗng `<200 bytes`).
6. **Hiển thị thông tin bản Backup & Khôi phục (Restore) tách biệt rõ ràng**:
   - **Tách riêng 2 luồng trên Main Menu & CLI**:
     - **Restore from Backup Job (`--job <job_id>` hoặc mặc định)**: Chỉ quét đúng thư mục lưu trữ của các Job Backup đã cấu hình (`<target_dir>/full/<job_id>` và `<target_dir>/incremental/<job_id>`), không quét tràn lan các thư mục lạ ngoài Job.
     - **Restore from Custom Dir (`CUSTOM_RESTORE_DIR` / `--dir <path>`)**: Cấu hình riêng thư mục khôi phục khác (ổ NAS/USB gắn ngoài, bản sao lưu lẻ `account/`, hoặc thư mục `auto_full_backup.sh` cũ — tự động dò đệ quy từ bất kỳ đường dẫn nào người dùng nhập vào).
   - Xem chi tiết từng bản backup, tìm kiếm tài khoản và dung lượng hộp thư bên trong, kiểm tra lại mã băm SHA-256 (`verify`).
   - Chọn bản backup bất kỳ (tự động ghép và nạp tuần tự `Full gốc -> Incr #1 -> ... -> Incr đã chọn`), chọn khôi phục **Toàn bộ máy chủ**, **Theo Domain**, hoặc **Chọn 1 / nhiều User cụ thể**; hỗ trợ khôi phục sang **tài khoản đích khác** (`--target-user`), khôi phục vào **thư mục con riêng** (`/Restore_<timestamp>`), chọn riêng **Hộp thư** hoặc **Cấu hình LDAP**, và chạy thử **`--dry-run`**.

> **Lưu ý kỹ thuật về Incremental trên Zimbra OSE & Kiểm thử trước Production**:
> Trên Zimbra Open Source Edition, dữ liệu hộp thư Incremental được trích xuất qua REST API (`?fmt=tgz&query=after:<checkpoint_ms>`). Đây là cơ chế sao lưu bồi đắp các thư/mục mới hoặc sửa đổi kể từ checkpoint gần nhất — nó không ghi nhận sự kiện người dùng xóa hẳn email hoặc dọn thùng rác giữa hai lần chạy khi nạp chồng (`modify`/`skip`). Trước khi áp dụng chính sách tự động xóa bản cũ hoặc chạy khôi phục hàng loạt trên hệ thống thật, hãy kiểm thử gói RPM trên máy Lab Zimbra cùng phiên bản (`8.8.15` / `9` / `10`).

---

## Cài đặt / Nâng cấp trên máy chủ Zimbra

Hỗ trợ đầy đủ **Ubuntu 18.04, 20.04, 22.04 LTS** (gói `.deb`) và **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9** (gói `.rpm`).

- **Gói cài đặt sẵn mới nhất**: mục [GitHub Releases](https://github.com/0xAndyNew/Backup-Zimbra/releases) (bản `v0.3.3`)
  - Ubuntu / Debian: [zimbra-backup_0.3.3-1_all.deb](https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.3/zimbra-backup_0.3.3-1_all.deb) (SHA-256: `a88b9f374d27eba68bd1e30198c0df4979ba96e91d4dc5ed659bbcf377bc1278`)
  - RHEL / CentOS / Rocky / AlmaLinux: [zimbra-backup-0.3.3-1.noarch.rpm](https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.3/zimbra-backup-0.3.3-1.noarch.rpm) (SHA-256: `b3167c2c8870d7a1988dada71fa13ca3019686fb9758cf0e3402848f944ebbfd`)

Yêu cầu máy chủ đã cài sẵn Zimbra Collaboration (`user zimbra` tồn tại dưới `/opt/zimbra`).

---

### Cách 1: Trên Ubuntu 18.04 / 20.04 / 22.04 LTS

**Tải gói `.deb`:**

```bash
curl -fSL -o zimbra-backup_0.3.3-1_all.deb \
  https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.3/zimbra-backup_0.3.3-1_all.deb
```

**Cài đặt hoặc nâng cấp bằng `apt` (khuyến nghị, tự động nạp đủ gói phụ thuộc):**

```bash
sudo apt update && sudo apt install -y ./zimbra-backup_0.3.3-1_all.deb
```

*(Hoặc cài trực tiếp bằng `dpkg`: `sudo dpkg -i ./zimbra-backup_0.3.3-1_all.deb && sudo apt-get install -f -y`)*

**Gỡ cài đặt sạch hoàn toàn trên Ubuntu:**

```bash
sudo apt remove -y zimbra-backup
```

*(hoặc `sudo dpkg -r zimbra-backup`). Quá trình gỡ cài đặt tự động dọn sạch khối cron `zimbra-backup` và `/var/lib/zimbra-backup`, **cam kết không chạm tới dịch vụ Zimbra `/opt/zimbra` hay dữ liệu backup**.*

---

### Cách 2: Trên Rocky Linux / AlmaLinux / RHEL / CentOS 7, 8, 9

**Tải gói `.rpm`:**

```bash
curl -fSL -o zimbra-backup-0.3.3-1.noarch.rpm \
  https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.3/zimbra-backup-0.3.3-1.noarch.rpm
```

**Cài đặt trên Rocky Linux / AlmaLinux / RHEL / CentOS 8, 9:**

```bash
dnf install -y ./zimbra-backup-0.3.3-1.noarch.rpm
```

**Nâng cấp bản mới trên RHEL/CentOS 8, 9:**

```bash
dnf upgrade -y ./zimbra-backup-0.3.3-1.noarch.rpm
```

**Hoặc dùng lệnh `rpm` chuẩn (mọi bản RHEL/CentOS 7, 8, 9):**

```bash
rpm -Uvh ./zimbra-backup-0.3.3-1.noarch.rpm
```

**Trên CentOS / RHEL 7 (cài mới):**

```bash
yum install -y ./zimbra-backup-0.3.3-1.noarch.rpm
```

**Gỡ cài đặt trên CentOS / RHEL:**

```bash
dnf remove -y zimbra-backup
```

*(hoặc `rpm -e zimbra-backup` trên CentOS/RHEL 7).*

Sau khi cài đặt, mở giao diện Menu tương tác (bằng quyền `root` hoặc `su - zimbra`):

```bash
zimbra-backup
```

Lần chạy đầu tiên sẽ tự động đưa bạn vào thẳng **MAIN MENU**, sẵn sàng để tạo ngay Job sao lưu đầu tiên (cấu hình thư mục lưu trữ và tùy chọn mount riêng được tích hợp trực quan ngay tại Bước 3 khi tạo Job).

---

## Hướng dẫn nhanh các lệnh CLI

### 1. Khởi tạo cấu hình chung bằng CLI (triển khai tự động)

```bash
zimbra-backup init --backup-dir /home/backup --require-mount yes --disk-warn 85
```

### 2. Tạo, chỉnh sửa & quản lý Job Backup

Tạo Job Full hằng ngày lúc `01:30`, giữ lại `7` bản (xóa bản cũ sau khi bản mới hoàn tất):

```bash
zimbra-backup job add full-daily --name "Daily Full Backup" --type full --schedule daily --hour 1 --minute 30 --keep 7 --prune-timing after
```

Tạo Job Incremental chạy hằng ngày lúc `02:30`, tự mở chuỗi Full mới sau mỗi `6` bản Incremental, giữ `2` chuỗi hoàn chỉnh:

```bash
zimbra-backup job add incr-daily --name "Daily Incremental Chain" --type incremental --schedule daily --hour 2 --minute 30 --full-cycle max_incr --full-cycle-value 6 --keep 2
```

Chỉnh sửa (`edit`) lại ngày/tháng chạy, số lượng bản lưu hoặc thư mục của Job bất kỳ sau khi đã cấu hình:

```bash
zimbra-backup job edit full-daily --schedule monthly --dom 1,15 --month "*" --hour 3 --minute 0 --keep 4
```

Xem danh sách, bật/tắt lịch hoặc chạy ngay một Job:

```bash
zimbra-backup job list
```

```bash
zimbra-backup job show full-daily
```

```bash
zimbra-backup job run full-daily
```

Đồng bộ lại khối Crontab của user `zimbra` (hữu ích sau khi nâng cấp phiên bản Zimbra):

```bash
zimbra-backup cron sync
```

### 3. Xem danh sách, tra cứu User & kiểm tra toàn vẹn bản Backup

```bash
zimbra-backup backup list
```

```bash
zimbra-backup backup list --job full-daily
```

```bash
zimbra-backup backup inspect 1 --search nguyen
```

```bash
zimbra-backup backup verify 1
```

Quét thư mục backup gắn ngoài (khi dựng máy chủ DR mới chưa có cấu hình Job):

```bash
zimbra-backup backup list --dir /mnt/nas-zimbra-old
```

### 4. Khôi phục dữ liệu (Restore)

Xem trước kế hoạch khôi phục (`--dry-run`) cho 2 user từ bản backup số `1`:

```bash
zimbra-backup restore --from 1 --users "user1@example.com,user2@example.com" --mode skip --dry-run
```

Khôi phục hộp thư của nhân viên cũ sang thư mục riêng `/BanGiao_NhanSu` bên trong tài khoản người nhận (không ghi đè mật khẩu của người nhận):

```bash
zimbra-backup restore --from 1 --users "nhanvien_cu@example.com" --target-user "quanly@example.com" --only mailbox --mode subfolder --subfolder-name "BanGiao_NhanSu" --yes
```

Khôi phục toàn bộ máy chủ từ ổ đĩa gắn ngoài:

```bash
zimbra-backup restore --dir /mnt/nas-zimbra-old --from 1 --all --mode skip
```

---

## Kiểm thử & Đóng gói lại từ mã nguồn

Chạy bộ kiểm thử tự động đầu-cuối (không cần cài Zimbra thật hay quyền `root`):

```bash
bash tests/run_tests.sh
```

Đóng gói file `.deb` và `.rpm` bằng công cụ Python có sẵn trong repo (không cần root hay docker, chạy được trên cả Windows và Linux):

```bash
python packaging/build_deb.py
python packaging/build_rpm.py
```

Hoặc đóng gói bằng `nfpm`:

```bash
nfpm package --config nfpm.yaml --packager rpm
nfpm package --config nfpm.yaml --packager deb
```

Hoặc đóng gói bằng `rpmbuild` trên RHEL/CentOS/AlmaLinux/Rocky:

```bash
mkdir -p "$HOME/rpmbuild/SOURCES" zimbra-backup-0.3.3 && \
cp -r bin lib packaging README.md zimbra-backup-0.3.3/ && \
tar czf "$HOME/rpmbuild/SOURCES/zimbra-backup-0.3.3.tar.gz" zimbra-backup-0.3.3 && \
rpmbuild -ba zimbra-backup.spec
```
