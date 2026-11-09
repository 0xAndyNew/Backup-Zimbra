# Zimbra Backup & Restore (`zimbra-backup` v0.3.14)

[![Release](https://img.shields.io/github/v/release/0xAndyNew/Backup-Zimbra?color=brightgreen&label=Release)](https://github.com/0xAndyNew/Backup-Zimbra/releases)
[![CI](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml/badge.svg)](https://github.com/0xAndyNew/Backup-Zimbra/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zimbra OSE](https://img.shields.io/badge/Zimbra_OSE-8.8.15_%7C_9_%7C_10-orange.svg)](https://www.zimbra.com/)
[![OS Support](https://img.shields.io/badge/OS-Ubuntu_%7C_RHEL_%7C_CentOS_%7C_Rocky_%7C_Alma-blue.svg)]()
[![Packages](https://img.shields.io/badge/Packages-RPM_%7C_DEB-success.svg)]()
[![Bash](https://img.shields.io/badge/Bash-4.2%2B-lightgrey.svg)]()
[![Encoding](https://img.shields.io/badge/Encoding-100%25_Pure_7--bit_ASCII-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-230%2F230_Passing-brightgreen.svg)]()

> 🌐 **[English Documentation](README_EN.md)** | **[Tài liệu Tiếng Việt](README.md)** | **[Hướng dẫn sử dụng chi tiết từng bước](HUONG_DAN_SU_DUNG.md)**

Bộ công cụ đóng gói `.rpm` và `.deb` hợp nhất chuyên nghiệp dành cho máy chủ **Zimbra Collaboration Open Source Edition (8.8.15, 9, 10)** trên **Ubuntu 18.04, 20.04, 22.04 LTS** và **CentOS / RHEL / AlmaLinux / Rocky Linux 7, 8, 9**. Trang bị **Giao diện Menu tương tác TUI (100% Pure 7-bit ASCII — không bao giờ lỗi font `□` trên mọi SSH / VM Console)** cùng hệ thống **CLI tự động hóa** đầy đủ và cơ chế an toàn `--yes`.

---

## ⚡ Cài đặt nhanh trong 1 dòng lệnh (Quick Install)

### Trên RHEL / CentOS / Rocky Linux / AlmaLinux (7, 8, 9):
```bash
sudo dnf install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.14/zimbra-backup-0.3.14-1.noarch.rpm
# Hoặc trên CentOS 7:
# sudo yum install -y https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.14/zimbra-backup-0.3.14-1.noarch.rpm
```

### Trên Ubuntu 18.04 / 20.04 / 22.04 LTS (Debian):
```bash
curl -fSL -o /tmp/zb.deb https://github.com/0xAndyNew/Backup-Zimbra/releases/download/v0.3.14/zimbra-backup_0.3.14-1_all.deb && sudo apt update && sudo apt install -y /tmp/zb.deb && rm -f /tmp/zb.deb
```

Khởi động giao diện quản lý ngay:
```bash
zimbra-backup
```

---

## 🖥️ Giao diện tương tác TUI trực quan (Pure ASCII)

```text
============================================================
  ZIMBRA BACKUP & RESTORE MANAGER (v0.3.14) - mail.domain.com
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

| Tính năng cốt lõi | Script rời thông thường | Zimbra Network Edition ($$$) | `zimbra-backup` v0.3.14 |
|---|:---:|:---:|:---:|
| **Chi phí bản quyền** | Miễn phí | Rất đắt đỏ theo năm | **100% Miễn phí & Open Source (MIT)** |
| **Gói cài đặt chuẩn OS** | ❌ Không có (file rời) | Có | **✅ Đầy đủ gói RPM & DEB** |
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

## 🌟 Điểm nổi bật trong phiên bản v0.3.14

1. **Xuất Metadata LDAP Hàng Loạt Siêu Tốc Bằng `zmprov -l -f` (Batch JVM Execution)**:
   - Gom toàn bộ hàng chục/hàng trăm lệnh `ga <email>` vào một file kịch bản batch duy nhất thực thi trong đúng 1 tiến trình JVM, thay vì khởi chạy 140+ tiến trình Java tuần tự.
   - Sử dụng bộ parser `awk` bóc tách từng khối LDIF theo ranh giới `# name `, loại bỏ hoàn toàn 7 phút nghẽn CPU ở giai đoạn xuất thông tin tài khoản, hạ thời gian xuất xuống dưới 5 giây.

2. **Chuẩn Hóa Giao Thức SOAP 1.1 Envelope Cho `DelegateAuthRequest`**:
   - Chuyển đổi toàn bộ cấu trúc SOAP Envelope sang chuẩn XML SOAP 1.1 (`xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"` và `Content-Type: text/xml; charset=utf-8`) tương thích 100% với Zimbra Collaboration `SoapServlet`.
   - Khắc phục lỗi `DelegateAuthRequest` bị từ chối do xung đột SOAP 1.2, đảm bảo 100% tài khoản lấy được delegated user token trực tiếp từ cổng Admin 7071 trong ~10ms mà không bao giờ bị rơi về fallback `zmmailbox` JVM.

3. **Tiền Dò & Export Biến Cấu Hình Port / Host Cho Tiến Trình Con**:
   - Dò và xuất sẵn các biến `ZB_REST_PORT`, `ZB_ADMIN_PORT`, và `ZB_SERVER_HOST` ngay trước khi khởi chạy worker pool song song.
   - Ngăn chặn hoàn toàn việc 70+ subshell worker chạy lại các lệnh `zmprov` hay `zmhostname`, triệt tiêu hơn 350 tiến trình JVM dư thừa.

4. **Triệt Tiêu Hoàn Toàn Bão Tải CPU (Hạ từ 93% xuống <3%)**:
   - Rút ngắn toàn bộ thời gian sao lưu hệ thống 70 tài khoản từ 13.5 phút xuống dưới 30 giây (nhanh gấp 25 lần).
   - Tối ưu hóa toàn diện mức tiêu thụ tài nguyên phần cứng máy chủ mail production.

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.13

1. **Khắc phục Triệt để Lỗi Xuất Hộp Thư REST (Cơ chế `QP_AUTH` & Phục hồi Cookie Auth)**:
   - Sửa lỗi 100% tài khoản bị thất bại khi sao lưu (`[FAIL] (x/70) user@domain - mailbox export failed after 3 attempts`).
   - Xác định chính xác nguyên nhân gốc rễ trong Zimbra Collaboration OSE `UserServletContext.java`: khi URL query chứa `&auth=admin`, phương thức `cookieAuthAllowed()` kiểm tra thấy `"admin"` không chứa chuỗi `"co"` (`AUTH_COOKIE`), dẫn đến việc Zimbra từ chối toàn bộ xác thực cookie và trả về `HTTP 401 Must Authenticate`.
   - Loại bỏ hoàn toàn `&auth=admin`, phục hồi cơ chế xác thực mặc định của Zimbra (`AUTH_DEFAULT = "co,jwt,nsc,qp"`).

2. **Khử Bão Tiến trình Java JVM Bằng Streaming Native REST Qua SOAP `DelegateAuthRequest`**:
   - Gửi yêu cầu SOAP `DelegateAuthRequest` trực tiếp đến cổng Zimbra Admin (7071) để cấp phát Delegated Auth Token trong ~10ms cho từng tài khoản.
   - `curl` trực tiếp stream dữ liệu hộp thư từ Mailbox port (8443/443) kèm header `Cookie: ZM_AUTH_TOKEN=<user_tok>` với tốc độ dây (wire-speed), không qua bất kỳ tiến trình Java JVM nào.
   - Triệt tiêu hoàn toàn hiện tượng nghẽn và bão CPU khi sao lưu, hạ tải CPU máy chủ từ 85%+ xuống dưới 2% trên toàn bộ các tài khoản.

3. **Tuần Tự Hóa Throttling Khóa JVM (`.jvm_worker.lock`) Khi Cần Fallback**:
   - Thay thế cơ chế hashing phân rã đa slot bằng khóa độc quyền duy nhất `$ZB_RUN_DIR/.jvm_worker.lock`, cam kết tuyệt đối không bao giờ có quá 1 tiến trình JVM chạy cùng lúc giữa các worker song song.
   - Kết hợp độ ưu tiên thấp nhất `nice -n 19` và `ionice -c 2 -n 7` bảo vệ tối đa các dịch vụ trọng yếu (`mailboxd`, `slapd`, `postfix`).

4. **Bảo Toàn Tuyệt Đối 100% Toàn Vẹn Dữ Liệu**:
   - File nén `.tgz` được xuất nguyên bản, kiểm tra định dạng `tar -tzf`, `gzip -t` và đối soát mã băm SHA-256 qua `manifest`.

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.12

1. **Khắc phục Triệt để Tải CPU Cao & Tối ưu Kết nối REST Mailbox Trực tiếp**:
   - Dò cổng REST chuẩn xác: Nhắm đúng cổng phục vụ UserServlet (`zimbraMailSSLPort` 8443, proxy 443) thay vì cổng admin 7071 (vốn trả về 404 cho `/service/home/`).
   - Truyền đầy đủ header `Host: <hostname>`, cặp cookie kép (`ZM_ADMIN_AUTH_TOKEN` và `ZM_AUTH_TOKEN`) cùng tham số `auth=admin` vào kết nối `curl -K`.
   - Giúp 100% tiến trình sao lưu hộp thư chạy qua `curl` trực tiếp bằng C/libcurl siêu tốc, hoàn toàn không bị rơi vào cơ chế fallback CLI `zmmailbox` (chạy trên Java JVM gây bão CPU 130% - 140% per core).

2. **Cơ chế Điều phối Độ ưu tiên Tiến trình & I/O (`nice 19` & `ionice`)**:
   - Tự động hạ độ ưu tiên lập lịch CPU (`nice -n 19`) và I/O đĩa cứng (`ionice -c 2 -n 7`) cho toàn bộ tiến trình con của subshell backup và restore.
   - Cam kết tuyệt đối không bao giờ làm nghẽn hoặc chiếm dụng tài nguyên của các dịch vụ Zimbra trọng yếu đang phục vụ người dùng (`mailboxd`, `slapd`, `postfix`, `nginx`).

3. **Bảo toàn Tuyệt đối 100% Toàn vẹn Dữ liệu**:
   - Trích xuất trọn vẹn toàn bộ email, danh bạ, lịch, chữ ký, bộ lọc Sieve và cấu hình LDAP vào file `.tgz` chuẩn của Zimbra OSE.
   - Tiếp tục kiểm tra nghiêm ngặt tính toàn vẹn bằng `tar -tzf`, `gzip -t` và mã băm SHA-256 trong file `manifest`.

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.11

1. **Rút gọn Cấu trúc Đường dẫn Lưu trữ (Ngắn gọn, Trực quan & Tương thích Ngược 100%)**:
   - Loại bỏ các cấp thư mục trung gian `<job_id>` / `chain-*` và hậu tố giờ-phút-giây `_HHMMSS`:
     - **Backup Full**: Lưu trực tiếp tại `<target_dir>/full/full-DD-MM-YYYY` (ví dụ `/backup/full/full-22-10-2026`).
     - **Backup Incremental**: Lưu phẳng trực tiếp tại `<target_dir>/incremental/full-DD-MM-YYYY` (bản gốc đầu chuỗi) và `<target_dir>/incremental/001-incremental-DD-MM-YYYY`, `002-incremental-DD-MM-YYYY`... (tự động quản lý liên kết chuỗi qua `chain_id` trong `manifest`).
     - **Backup lẻ tài khoản**: `<target_dir>/account/backup-<email>-DD-MM-YYYY`.
   - Hỗ trợ đầy đủ việc đọc, kiểm tra mã băm SHA-256 và khôi phục từ các thư mục định dạng cũ.

2. **Tối ưu Dọn dẹp FTP / SFTP Từ xa & Bảo mật Ký tự Đặc biệt trong Mật khẩu**:
   - Sắp xếp chuẩn xác thứ tự thời gian thực (`DD-MM-YYYY` -> `YYYY-MM-DD`) khi dọn dẹp các bản `.tar` và `.manifest` cũ trên máy chủ FTP/SFTP qua ranh giới tháng/năm, đồng thời bóc tách an toàn tên file từ kết quả `ls -l` của SFTP.
   - Bổ sung cơ chế escape ký tự `\` và `"` trong thông tin đăng nhập FTP/SFTP khi tạo file cấu hình tạm `curl -K`.

3. **Giao diện Bản tin Thông báo Email & Telegram Chuẩn ASCII Card**:
   - Thiết kế lại bố cục thông báo dạng thẻ ASCII rõ ràng kèm thông tin chi tiết tiến trình, dung lượng và chân trang thời gian máy chủ.

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.10

1. **Khắc phục triệt để lỗi Incremental Backup trên tài khoản không có thư mới (HTTP 204 No Content)**:
   - Khi chạy sao lưu Incremental (`query=after:...`), các hộp thư không phát sinh thư mới trong khoảng thời gian checkpoint được Zimbra trả về mã `HTTP 204 No Content` (0 bytes payload).
   - Trước đây, lệnh fallback `zmmailbox getRestURL` bắt gặp 204 sẽ xuất mã lỗi `status=204` và exit code 2, khiến script hiểu lầm là lỗi xuất dữ liệu và kích hoạt retry 3 lần liên tục dẫn đến báo `[FAIL] (x/70) user@domain - mailbox export failed after 3 attempts`.
   - `zimbra-backup` v0.3.10 nhận diện chính xác `HTTP 204 / status=204` là một delta rỗng hoàn toàn hợp lệ (empty delta), ghi nhận `[OK] (empty)` ngay trong lần chạy đầu tiên và hoàn tất sao lưu 100% tài khoản.

2. **Triệt tiêu bão tiến trình Java JVM & Hạ tải CPU từ 86% xuống dưới 5%**:
   - Ưu tiên kết nối trực tiếp đến cổng quản trị Zimbra Admin (`zimbraAdminPort` 7071) thay vì proxy 8443, cho phép `curl` dùng trực tiếp `ZM_ADMIN_AUTH_TOKEN` mà không bị HTTP 401 Unauthorized từ Nginx proxy.
   - Khi curl hoàn tất trực tiếp qua REST API (C/libcurl), hệ thống không còn bị rơi vào fallback CLI `zmmailbox` (chạy trên Java JVM).
   - Ngăn chặn triệt để tình trạng 4 worker song song khởi chạy hàng trăm tiến trình Java JVM cùng lúc, giữ CPU máy chủ Zimbra luôn êm ái (<5%) trong suốt chu kỳ sao lưu định kỳ.

3. **Nâng cấp Hệ thống Thông báo Khôi phục Toàn diện (Phân biệt Rõ Single Account & Full/Batch Restore)**:
   - **Khôi phục tài khoản đơn (`resto đơn`)**: Báo cáo chi tiết và tường minh: email được khôi phục, tài khoản đích và thư mục con chuyển tiếp (nếu có dùng `--target-user` hoặc `--mode subfolder`), chính xác dung lượng dữ liệu đã nạp (`Restored`), trạng thái thành công/thất bại, thời gian thực thi và đường dẫn file log.
   - **Khôi phục hàng loạt / toàn server (`restore full`)**: Báo cáo tổng thể: tổng số lượng tài khoản xử lý, thống kê chi tiết số tài khoản thành công và số tài khoản thất bại (`X succeeded, Y failed`), danh sách cụ thể các tài khoản bị lỗi (nếu có), tổng dung lượng dữ liệu đã nạp xuyên suốt toàn bộ chuỗi snapshot, trạng thái và file log.

---

## 🌟 Điểm nổi bật trong phiên bản v0.3.9

1. **Khắc phục triệt để lỗi HTTP 401 khi Restore tài khoản Non-active (Closed, Locked, Suspended)**:
   - Zimbra `UserServlet` / `MailboxServlet` từ chối các kết nối REST (`/service/home/`) đến các tài khoản ở trạng thái `closed`, `maintenance`, `locked`, `suspended` với lỗi `HTTP 401 Unauthorized` (`account.ACCOUNT_INACTIVE`).
   - `zimbra-backup` v0.3.9 cải tiến cơ chế **Deferred Status**: giữ tài khoản ở trạng thái `active` trong suốt quá trình nạp LDAP và stream hộp thư REST, sau đó tự động hoàn trả chính xác về trạng thái ban đầu (`closed`, `locked`, v.v.) sau khi toàn bộ chuỗi khôi phục hoàn tất hoặc khi tiến trình bị hủy đột ngột.

2. **Tự động Fallback Sender Domain cho Email Alerts (Chống chặn Mail RFC 5321)**:
   - Khi `Server label (alerts)` được người dùng đặt là địa chỉ IP thô (ví dụ `1.55.212.58`), hệ thống tự động nhận diện và fallback trường domain trong `From:` header sang FQDN hợp lệ (`zmhostname` hoặc `hostname -f`).
   - Ngăn chặn tuyệt đối việc email thông báo bị Postfix hoặc Mail Gateway đối tác (FPT, Gmail, Microsoft 365) từ chối nhận (reject), đồng thời vẫn bảo lưu nhãn IP trong tiêu đề và nội dung để quản trị viên dễ dàng nhận diện máy chủ.

3. **Chẩn đoán Lỗi Telegram API Trực quan (Transparent Diagnostics)**:
   - Khi gửi thử hoặc gửi thông báo thất bại, lệnh `zimbra-backup notify test-telegram` trích xuất và hiển thị trực tiếp thông báo lỗi từ Telegram API (như `Bad Request: chat not found`, `Forbidden: bot is not a member of the supergroup chat`), giúp giải quyết sự cố phân quyền Bot chỉ trong vài giây.

4. **Tài liệu Hướng dẫn Toàn diện về File `.manifest` và Thông báo Đa kênh**:
   - Bổ sung tài liệu giải thích chi tiết cơ chế manifest siêu nhẹ (`.manifest`), phục vụ tra cứu danh mục tức thì mà không cần kéo file `.tar` hàng chục GB về máy.
   - Hướng dẫn step-by-step xử lý các lỗi thường gặp với Telegram Supergroup ID (`-100...`) và hàng đợi Postfix.

---

## 🌟 Kiến trúc cốt lõi từ phiên bản v0.3.8

1. **Cấu hình Lưu trữ Từ xa FTP / SFTP theo từng Job (Per-Job Remote Storage)**:
   - Chuyển hoàn toàn cấu hình FTP từ mức toàn cục vào từng Job riêng biệt: mỗi Job tự chọn có đẩy FTP hay không (`[y/N]`), cấu hình máy chủ FTP/SFTP, port, tài khoản, và thư mục đích riêng (`/<job_id>`).
   - Hỗ trợ mã hóa **FTPS (SSL/TLS)** cho FTP truyền thống và **SFTP qua giao thức SSH** với backend `curl` tích hợp sẵn, không phụ thuộc gói bên ngoài.
   - **Bảo mật tuyệt đối**: Mật khẩu truyền qua file cấu hình tạm `0600` với cờ `curl -K`, dọn sạch ngay sau khi chạy, hoàn toàn không lộ mật khẩu trên lệnh hay tiến trình `ps aux`.

2. **Quản lý Bản lưu FTP Độc lập (`FTP_KEEP_COUNT`) & Tự động Dọn dẹp File Cũ trên FTP**:
   - Số lượng bản archive lưu giữ trên FTP (`FTP_KEEP_COUNT`) được quản lý **hoàn toàn độc lập** với số bản lưu cục bộ (`KEEP_COUNT`).
   - Tự động quét và dọn dẹp các file `.tar` và `.manifest` cũ vượt quá hạn lưu trên FTP bằng lệnh chuẩn `DELE` (FTP) hoặc `rm` (SFTP).
   - **Bảo toàn 100% bản lưu cục bộ tại Local**: Bản lưu trên FTP đóng vai trò là bản nhân bản dự phòng ngoài site (offsite replica). Hệ thống tuyệt đối không xóa bản backup ở local sau khi upload, giữ nguyên vẹn số bản local theo đúng `KEEP_COUNT`.

3. **Cải tiến Giao diện TUI & CLI**:
   - **Tạo Job 6 bước đầy đủ**: Bổ sung Bước 6 để tùy chọn cấu hình Remote Storage FTP / SFTP ngay khi tạo Job.
   - **Chỉnh sửa Job 1 chạm (Mục 1..11)**: Mục 11 hỗ trợ bật/tắt và cập nhật toàn bộ thông số FTP của Job.
   - Dọn sạch Menu 6 (Global Settings) để tập trung cấu hình đường dẫn chung, ngưỡng cảnh báo đĩa và thông báo Email/Telegram.
   - Lệnh kiểm tra kết nối: `zimbra-backup notify test-ftp [job_id]`.

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

4. **Tách riêng 3 phân vùng lưu trữ rút gọn dưới thư mục gốc (`/home/backup`)**:
   - `full/full-DD-MM-YYYY/`
   - `incremental/full-DD-MM-YYYY/` & `incremental/001-incremental-DD-MM-YYYY/`
   - `account/backup-<email>-DD-MM-YYYY/` (sao lưu lẻ từng tài khoản)

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

Chạy bộ kiểm thử tự động đầu-cuối 229 bài test:
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
