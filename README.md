# studio
Claude session as entry point, omp workers in tmux windows, products in `projects/`.
Setup: `./install.sh`, `export NINEROUTER_API_KEY=...` (also into tmux: `tmux set-environment -g NINEROUTER_API_KEY ...`), run `omp` once to finish onboarding, then `claude` in this dir.
Commands: `team new|assign|wait|ls|close` (see bin/team).

## Worker runtime: vì sao chọn opencode (POC 2026-10-09)
Worker dùng model tùy chỉnh (qwen3.8-flash, kCode qua 9router) chạy trong một coding agent CLI. Đã POC 4 agent × 2 model × 3 task (T1 thêm hàm + test, T2 sửa UI, T3 kỷ luật: không sửa file khóa, ghi `.team/out/*.md` + `.done`). Kết quả chấm bằng script, không tin lời agent tự báo. Chi tiết và lệnh tái hiện: [docs/poc/agents-poc.md](docs/poc/agents-poc.md).

| Agent | qwen3.8-flash | kCode | Quyền | Tmux tương tác |
|---|---|---|---|---|
| **opencode** | ✅ T1–T3 (2 lượt, 28–62s) | ✅ | allow/deny theo tool | ✅ không hộp thoại, nhận `send-keys` |
| goose | ✅ T1–T3 (2 lượt) | ✅ | chế độ tự duyệt, chống lặp tool | chưa thử |
| pi | ✅ T1–T3 (2 lượt) | ✅ chịu chậm tốt nhất | **không có** | chưa thử |
| codex | ❌ T3 trượt 3/3 | ⚠️ T3 thiếu `.done` | sandbox + approval | chưa thử |

**Chọn opencode làm mặc định** vì: đạt mọi task với cả hai model; có hệ thống quyền thật (MVP chưa có sandbox nên đây là lớp bảo vệ còn lại); đã chứng minh chạy tương tác trong tmux pane không bị hộp thoại chặn; hỗ trợ MCP (QA điều khiển browser). **goose làm dự phòng** (đạt hết, có chống lặp). **Không dùng pi** cho tới khi có sandbox (không có quyền). **Không dùng codex** qua 9router: model kết thúc lượt mà không gọi tool ("Applying now…") và `codex exec` coi là xong; bản 0.147 cũng bỏ `wire_api="chat"`.

Lưu ý rút ra:
- kCode chậm/chập chờn ở hạ tầng (502/503, có lúc chờ 100–200s), không phải lỗi agent: timeout cho task UI ≥ 10 phút.
- tmux server không có `NINEROUTER_API_KEY` → `team` phải đưa biến vào pane.
- Chạy headless (`opencode run`, `pi -p`) cần `</dev/null`, nếu không sẽ treo.
- Từng thấy opencode trả "DONE" mà không làm gì: lead luôn tự kiểm diff/test, không tin báo cáo worker.
- Bench chỉ có 3 task nhỏ; chưa có task Android hay task nhiều file.

Trạng thái: đã chọn, **chưa triển khai** — `bin/team` vẫn đang chạy worker theo cách cũ cho tới khi spec + plan được duyệt.
