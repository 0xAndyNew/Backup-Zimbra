# Legacy Scripts (Các script gốc ban đầu)

Thư mục này lưu trữ 3 script sao lưu và khôi phục rời ban đầu để phục vụ việc đối chiếu lịch sử:

1. `auto_full_backup.sh`: Script sao lưu toàn bộ (Full) đời đầu.
2. `auto_incr_backup.sh`: Script sao lưu gia tăng (Incremental) đời đầu.
3. `restore_email.sh`: Script khôi phục hộp thư đời đầu.

> **Lưu ý**: Toàn bộ chức năng của 3 script này đã được hợp nhất, tối ưu hiệu năng và chuẩn hóa toàn diện vào gói công cụ **`zimbra-backup`** (xem tại thư mục `bin/` và `lib/`). Không khuyến nghị chạy trực tiếp 3 script rời này trong môi trường Production vì chưa có các cơ chế an toàn `--yes`, xử lý đa luồng worker pool, bảo toàn thuộc tính tiếng Việt UTF-8 và quản lý chuỗi Incremental chuẩn hóa.
