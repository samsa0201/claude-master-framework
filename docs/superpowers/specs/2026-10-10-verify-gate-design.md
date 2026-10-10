# Verify gate: kiểm tra khi worker báo xong

Ngày: 2026-10-10. Trạng thái: đã làm. Mô tả cách dùng nằm ở README ("Kiểm tra khi worker báo xong") và SKILL.md.

## Vấn đề
`team wait` trả `done` khi thấy file `.team/out/<id>.done`, nhưng đó chỉ là lời worker tự báo (opencode từng báo xong mà không làm gì). `timeout`/`dead` thì không nói worker đang kẹt ở đâu, và pane đóng là mất màn hình.

## Quyết định
| Chủ đề | Quyết định |
|---|---|
| Chạy khi nào | Tự động trong `team wait` ngay sau khi thấy `.done`; không thêm lệnh cho người dùng |
| Hợp đồng task | `--files` (phạm vi sửa) và `--done` (lệnh phải thoát 0), mặc định `test:` của file flex; ghi vào `.team/out/<id>.contract` lúc giao việc, không đọc lại flex lúc kiểm tra |
| "Worker đã đổi gì" | Ảnh chụp cây làm việc lúc giao việc (`.base`: hash nội dung file khác HEAD hoặc chưa track, không ghi vào repo) so với lúc xong; HEAD đổi thì thêm `git diff old new` |
| Kết quả | ok / warn / fail, dòng đầu của `wait` vẫn đúng `done|timeout|dead` để không vỡ cách đọc cũ |
| Lưu log | Màn hình pane lúc done/timeout/dead vào `.team/logs/<id>.md` (markdown, đọc được qua API docs) |
| Dashboard | Badge trên task và thẻ worker, mục Checks và Worker screen trong drawer, chip "failed checks" |

## Không làm (và vì sao)
- **Hạn chót theo hoạt động** ("output còn đổi thì chờ tiếp"): TUI của opencode có spinner/đồng hồ, màn hình đổi liên tục kể cả khi kẹt chờ upstream, nên tín hiệu này sẽ báo sống nhầm. Thay vào đó `timeout` in thời điểm đổi gần nhất và 15 dòng cuối để lead tự phán đoán.
- Ghi toàn bộ phiên bằng `pipe-pane`: output TUI là chuỗi điều khiển terminal, không đọc được. Chụp màn hình cuối thì đọc được.
- Cách ly worktree cho worker song song: để sau.

## Giới hạn đã biết
- Worker song song trong một worktree thấy file của nhau (đo trên cây dùng chung).
- Quá `TEAM_SNAP_MAX` (5000) file đã đổi/chưa track thì bỏ qua so sánh và báo WARN (thường là thiếu `.gitignore`).
- Lệnh `--done` chạy code của project với quyền người dùng (không cấp thêm quyền nào so với worker). Chưa thử với opencode thật, chỉ có runtime giả.
