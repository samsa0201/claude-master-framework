# studio
Claude session as entry point (product lead), coding-agent workers (opencode by default) running custom models in tmux panes, products in `projects/`.
Setup: `./install.sh` (installs opencode/goose under `.runtime/`), put `NINEROUTER_API_KEY=...` in `.env` (gitignored, chmod 600) and load it in your shell (fish: `~/.config/fish/conf.d/studio.fish`, bash: `set -a; . ~/dev/studio/.env; set +a` in `~/.bashrc`), then `claude` in this dir.
Commands: `team new|attach|assign|wait|ls|close|display|ui` (see bin/team). Tests: `tests/team_test.sh`, `tests/runtime-accept.sh <runtime> <model>`.

## Dashboard web (`team ui`)
Chỉ đọc: worker và task trực tiếp, docs của project (markdown), diff chưa commit + lịch sử commit, terminal của worker; light/dark. Server `ui/serve.py` (stdlib) chỉ nghe `127.0.0.1` và chỉ nhận GET; giao diện Vite + Vue 3 + TypeScript chạy bằng Bun trong `ui/web/`, build ra `ui/dist/` (gitignored).
- Build (không commit build output): `team ui` tự lo. `ui/build.sh` cài bun đúng phiên bản ghim trong `ui/web/package.json` (`packageManager`) vào `.runtime/bun` bằng npm (giống opencode, không phụ thuộc bun của máy), rồi `bun install --frozen-lockfile && bun run build` ra `ui/dist/`. Chỉ build lại khi nội dung `ui/web/` đổi (so hash lưu ở `ui/dist/.stamp`, không dựa mtime nên `git pull`/checkout không làm build sai). Cần node/npm và mạng ở lần đầu; npm lỗi thì dùng bun trên PATH; build lỗi mà đã có bản cũ thì vẫn phục vụ bản cũ. `install.sh` gọi cùng script. Đổi bản bun: sửa `packageManager`, chạy `team ui` để cài, rồi cập nhật `ui/web/bun.lock` bằng chính bun đó (bun cũ không đọc được lockfile của bun mới).
- Chạy: `team ui [port]` (mặc định 7777), rồi `ssh -L 7777:localhost:7777 <host>` và mở http://localhost:7777. Header `Host` ngoài localhost bị chặn (chống DNS rebinding); thêm host bằng `TEAM_UI_HOSTS=a.example,b.example` (vd. khi dùng `tailscale serve`).
- Bảo vệ: chỉ đọc `.md` trong `docs/` và `.team/{roles,tasks,out}` (không symlink/`..`), git chạy không shell và bỏ `fsmonitor`/ext-diff/textconv, file chưa track kiểu `.env`/`*.pem`/`*.key` không hiện trong diff. Nội dung do worker viết nên markdown tắt HTML thô, có CSP.
- Dev: chạy `team ui`, rồi `cd ui/web && bun run dev` (Vite proxy `/api` sang 7777). Test: `python3 -m unittest tests/ui_api_test.py`, `cd ui/web && bun test`. Dữ liệu mẫu để xem thử (tmux riêng, thư mục tạm): `tests/ui_demo.sh [port]`.
- Thiết kế: [docs/superpowers/specs/2026-10-09-web-ui-redesign.md](docs/superpowers/specs/2026-10-09-web-ui-redesign.md). Giao diện Pip-Boy cũ còn trong git history (commit `0dfce01`).

## Worker runtime: vì sao chọn opencode (POC 2026-10-09)
Worker dùng model tùy chỉnh (qwen3.8-flash, kCode qua 9router) chạy trong một coding agent CLI. Đã POC 4 agent × 2 model × 3 task (T1 thêm hàm + test, T2 sửa UI, T3 kỷ luật: không sửa file khóa, ghi `.team/out/*.md` + `.done`). Kết quả chấm bằng script, không tin lời agent tự báo. Chi tiết và lệnh tái hiện: [docs/poc/agents-poc.md](docs/poc/agents-poc.md).

| Agent | qwen3.8-flash | kCode | Quyền | Tmux tương tác |
|---|---|---|---|---|
| **opencode** | ✅ T1–T3 (2 lượt, 28–62s) | ✅ | allow/deny theo tool | ✅ không hộp thoại, nhận `send-keys` |
| goose | ✅ T1–T3 (2 lượt) | ✅ | chế độ tự duyệt, chống lặp tool | chưa thử |
| pi | ✅ T1–T3 (2 lượt) | ✅ chịu chậm tốt nhất | **không có** | chưa thử |
| codex | ❌ T3 trượt 3/3 | ⚠️ T3 thiếu `.done` | sandbox + approval | chưa thử |

**Chọn opencode làm mặc định** vì: đạt mọi task với cả hai model; có hệ thống quyền thật (MVP chưa có sandbox nên đây là lớp bảo vệ còn lại); đã chứng minh chạy tương tác trong tmux pane không bị hộp thoại chặn; hỗ trợ MCP (QA điều khiển browser). **goose làm dự phòng** (đạt hết, có chống lặp; chạy một task mỗi tiến trình, không giữ ngữ cảnh). **Không dùng pi** cho tới khi có sandbox (không có quyền). **Không dùng codex** qua 9router: model kết thúc lượt mà không gọi tool ("Applying now…") và `codex exec` coi là xong; bản 0.147 cũng bỏ `wire_api="chat"`.

Lưu ý rút ra:
- kCode chậm/chập chờn ở hạ tầng (502/503, có lúc chờ 100–200s), không phải lỗi agent: timeout cho task UI ≥ 10 phút.
- tmux server không có `NINEROUTER_API_KEY` → `team` phải đưa biến vào pane.
- Chạy headless (`opencode run`, `pi -p`) cần `</dev/null`, nếu không sẽ treo.
- Từng thấy opencode trả "DONE" mà không làm gì: lead luôn tự kiểm diff/test, không tin báo cáo worker.
- Bench chỉ có 3 task nhỏ; chưa có task Android hay task nhiều file.

Trạng thái: đã triển khai (adapter `agents/runtime/opencode.sh`, dự phòng `goose.sh`). Kết quả `tests/runtime-accept.sh` (opencode): qwen3.8-flash 4/4 PASS với grader chặt (commit 4421bc8); kCode 4/4 PASS (commit e5af3ef, grader lỏng hơn, ~14 phút).
Cô lập: worker opencode/goose dùng thư mục XDG config/data riêng của studio (`runtime-home/`, `.runtime/`), không đụng `~/.config` của người dùng.
Chromium của QA chạy với `--no-sandbox` (AppArmor trên máy này chặn sandbox của nó).

- noVNC/x11vnc không có mật khẩu và chỉ lắng nghe trên localhost: ổn trên máy một người dùng.
- goose: `base_url` của provider cố định là localhost:20128 (NINEROUTER_URL không áp dụng cho goose).

## Port theo project (cô lập mức 1)

Mỗi project có một dải 20 port cố định (mặc định từ 20000, đổi bằng `TEAM_PORT_BASE`/`TEAM_PORT_SPAN`/`TEAM_PORT_MAX`), ghi ở `projects/.ports` (flock, không trùng khi `team new` song song) và `projects/<tên>/.team/ports.env`: `PORT_WEB`, `PORT_API`, `PORT_DB`, `PORT_CACHE`, `PORT_AUX1`, `PORT_AUX2`, `COMPOSE_PROJECT_NAME`. File này được đưa vào env của mọi pane worker và liệt kê trong task file kèm quy tắc "chỉ dùng các port này, strict mode".
- `team ports <tên>`: bảng port + trạng thái, kèm dòng `ssh -L ...` để chạy trên Mac.
- `team ports <tên> kill` / `team close <tên>`: dừng process còn nghe trên dải port của project, chỉ khi cwd của nó nằm trong thư mục project.
- Đây là quy ước mềm (worker vẫn có thể bind port khác). Mức 2 (bubblewrap) và mức 3 (network namespace) sẽ ép thật; hợp đồng "port lấy từ env" giữ nguyên.
- `bin/portscan.py` đọc `/proc` nên không cần `ss`/`lsof`.
