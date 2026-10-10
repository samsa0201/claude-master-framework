# studio
Claude session as entry point (product lead), coding-agent workers (opencode by default) running custom models in tmux panes, products in `projects/`.
Setup: `./install.sh` (installs opencode/goose under `.runtime/`), put `NINEROUTER_API_KEY=...` in `.env` (gitignored, chmod 600) and load it in your shell (fish: `~/.config/fish/conf.d/studio.fish`, bash: `set -a; . ~/dev/studio/.env; set +a` in `~/.bashrc`), then `claude` in this dir.
Commands: `team new|attach|assign|wait|ls|close|display|ui` (see bin/team). Tests: `tests/team_test.sh`, `tests/runtime-accept.sh <runtime> <model>`.

## Kiểm tra khi worker báo xong
`done` chỉ là lời worker tự báo (xem "Lưu ý rút ra" bên dưới), nên `team wait` tự kiểm tra thay lead, không cần thêm lệnh nào:
- `team assign ... --files src/,README.md --done "bun test"`: `--files` là các đường dẫn worker được sửa, `--done` là lệnh một dòng phải thoát 0 (mặc định lấy `test:` trong frontmatter của file flex `.team/roles/<role>.md`). Cả hai được ghi vào file task cho worker đọc.
- Lúc giao việc, `team` chụp trạng thái cây làm việc (chỉ băm nội dung file đã đổi/chưa track, không ghi gì vào repo) vào `.team/out/<id>.base`. Khi thấy `.done`, `team wait` so với ảnh chụp đó (kể cả khi worker tự commit), kiểm tra có file kết quả, file nào ngoài `--files`, chạy lệnh `--done` (timeout 300s, đổi bằng `TEAM_VERIFY_TIMEOUT`, không có `NINEROUTER_API_KEY` trong môi trường lệnh này).
- Đầu ra: dòng đầu vẫn đúng `done`, kế đó `verify: OK|WARN|FAIL — ...` cùng chi tiết (cũng lưu ở `.team/out/<id>.verify`). FAIL: file ngoài phạm vi, lệnh `--done` lỗi, thiếu file kết quả. WARN: task `dev*` không đổi file nào hoặc không có lệnh test. Chạy `wait` lần hai chỉ in lại kết quả cũ.
- `timeout`/`dead`: kèm 15 dòng cuối của pane, thời điểm output đổi gần nhất, và lưu cả màn hình vào `.team/logs/<id>.md`. `timeout` chỉ là hạn chót, không giết worker. Chưa dùng "output còn đổi thì chờ tiếp" vì TUI có spinner luôn đổi màn hình dù worker kẹt.
- Dashboard hiện badge Checks passed/warning/failed, tóm tắt "failed checks" ở đầu project, và trong drawer của task có chi tiết kiểm tra cùng màn hình đã lưu.
- Giới hạn: đo trên worktree dùng chung, nên worker chạy song song trong một project thấy file của nhau (cho mỗi worker `--files` riêng). Lệnh `--done` chạy code của project với quyền của bạn, giống worker. Chỉ thử bằng runtime giả trong `tests/team_test.sh`, chưa thử với opencode thật.

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
