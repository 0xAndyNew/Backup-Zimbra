# Zimbra Backup — bản thử nghiệm 0.1.0

> **Đã tạo `zimbra-backup-0.1.0-1.noarch.rpm` trên Windows bằng nFPM; chưa cài hoặc kiểm thử trên Zimbra 10. Không cài lên production.** Đây là bản thử nghiệm một phần. Các script gốc vẫn được giữ nguyên để tham khảo, không được đưa vào RPM.

## Phạm vi hiện có

- Cài RPM không hỏi cấu hình. Chạy `zimbra-backup` với quyền `zimbra` hoặc root để vào menu.
- Full độc lập: thiết lập/sửa job (đường dẫn mount, giữ N bản, lịch hằng ngày hoặc hằng tuần), chạy tay hoặc qua cron. Theo lựa chọn của người dùng, xóa bản Full cũ nhất **trước** khi tạo bản mới nếu đã đủ N. Nếu bản mới thất bại, sẽ còn ít hơn N bản. Các bản lỗi nằm trong thư mục `.pending.*` và không tính vào N; phải kiểm tra thủ công.
- Backup Full một account chỉ định (lưu riêng) và một Full nền ban đầu cho luồng incremental tương lai (lưu riêng); không tự xóa hai loại này.
- Kiểm tra đường dẫn đã mount, manifest của bản full, checksum mailbox, thông tin kho, log và thông báo Telegram tùy chọn.

## Chưa hỗ trợ — không sử dụng để khôi phục trên production

- **Incremental hằng ngày chưa triển khai**; menu không cho bật. Script gốc lọc `date:>=` không đáp ứng yêu cầu backup/restore toàn bộ trạng thái (thư bị xóa/di chuyển, flags, metadata).
- **Restore bị vô hiệu hóa** cho đến khi có thử nghiệm Zimbra 10 phù hợp. Không thể cam kết metadata do REST tgz xuất là bản sao đầy đủ của Zimbra.
- `bash -n zimbra-backup` đã qua; RPM được kiểm tra cấu trúc metadata, quyền thư mục và hash script bên trong. Chưa có thử nghiệm mock Zimbra hoặc cài/restore trên Linux. **Không xác nhận RPM cài/chạy được trên mọi bản Zimbra 10.** SHA-256 bản thử: `66c1dcc054f5007cf2f9c1df1228b5a01abf7797cfd63d0ecdc928f6c8fe3aa1`.

## Thử trên máy Linux khác

Chỉ cài trên **máy thử nghiệm**, không dùng dữ liệu Zimbra production. RPM cần user `zimbra` đã tồn tại trước khi cài vì nó sở hữu `/var/lib/zimbra-backup`. Sau khi chuyển RPM sang máy thử, xem thông tin và cài bằng trình quản lý gói của hệ điều hành, rồi kiểm tra menu và đường dẫn mount. Không đặt lịch hoặc chạy Full trong kho có dữ liệu quan trọng trước khi kiểm tra hành vi xóa trước backup.

## Build lại trên Linux có rpm-build

Bản RPM đính kèm được build bằng nFPM theo `nfpm.yaml`; có thể build lại bằng nFPM, hoặc tạo tarball nguồn để build spec trên Linux. Ví dụ trong thư mục chứa `zimbra-backup` và `zimbra-backup.spec`:

```bash
mkdir -p "$HOME/rpmbuild/SOURCES" zimbra-backup-0.1.0
cp zimbra-backup zimbra-backup-0.1.0/
tar czf "$HOME/rpmbuild/SOURCES/zimbra-backup-0.1.0.tar.gz" zimbra-backup-0.1.0
rpmbuild -ba zimbra-backup.spec
```

Gói được tạo (nếu build thành công) ở `$HOME/rpmbuild/RPMS/noarch/`. Cần máy có user `zimbra`, dịch vụ Zimbra đã cài và `cronie`, `flock`, `mountpoint`, `sha256sum`, `tar`, `zmmailbox`, `zmprov`. Chỉ dùng một bản thử nghiệm, kiểm tra `bash -n zimbra-backup` và thử nghiệm trên Zimbra sandbox trước khi cài.

**Lưu ý:** Script hiện dùng `runuser` chuyển sang user `zimbra`, ghi state ở `/var/lib/zimbra-backup` (mặc định) và yêu cầu `STORE_ROOT` là mountpoint trực tiếp (mặc định `/mnt/backup`). Không đổi đường dẫn kho đã có dữ liệu nếu chưa di chuyển và xác minh lại tất cả các bản backup. Token Telegram được lưu trong `/var/lib/zimbra-backup/settings` với quyền `0600` của user zimbra. Cron tạo entry riêng cho job Full, không đụng cron khác.

## Cần xác minh để hoàn thiện

Cung cấp kết quả `zmcontrol -v`, bản Network Edition hoặc Open Source, OS (`cat /etc/os-release`) và môi trường kiểm thử. Sau đó chọn cơ chế snapshot/delta của Zimbra 10 có thể khôi phục thư mới, thư xóa/di chuyển, flags và metadata, xây kiểm thử full + nhiều incremental + restore; chỉ khi đạt yêu cầu mới bật lịch incremental và restore, rồi phát hành RPM.
