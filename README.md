# studio
Claude session as entry point (product lead), coding-agent workers (opencode by default) running custom models in tmux panes, products in `projects/`.
Setup: `./install.sh` (installs opencode/goose under `.runtime/`), put `NINEROUTER_API_KEY=...` in `.env` (gitignored, chmod 600) and load it in your shell (fish: `~/.config/fish/conf.d/studio.fish`, bash: `set -a; . ~/dev/studio/.env; set +a` in `~/.bashrc`), then `claude` in this dir.
Commands: `team new|attach|assign|wait|ls|close|run|stop|exec|egress|url|https|display|ui` (see bin/team). Tests: `tests/team_test.sh`, `tests/box_test.sh` (Docker), `tests/runtime-accept.sh <runtime> <model>`.

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

**Chọn opencode làm mặc định** vì: đạt mọi task với cả hai model; có hệ thống quyền thật (lớp bảo vệ trong box); đã chứng minh chạy tương tác trong tmux pane không bị hộp thoại chặn; hỗ trợ MCP (QA điều khiển browser). **goose làm dự phòng** (đạt hết, có chống lặp; chạy một task mỗi tiến trình, không giữ ngữ cảnh). **Không dùng pi** cho tới khi có sandbox (không có quyền). **Không dùng codex** qua 9router: model kết thúc lượt mà không gọi tool ("Applying now…") và `codex exec` coi là xong; bản 0.147 cũng bỏ `wire_api="chat"`.

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

## Box theo project (cô lập)
Worker và app chạy trong một container Docker riêng cho mỗi project (`studio-<tên>`), lead (Claude) ở trên host. Thiết kế + kết quả spike: [docs/superpowers/specs/2026-10-12-project-box-design.md](docs/superpowers/specs/2026-10-12-project-box-design.md).
- **Mạng riêng:** port mặc định (5173, 3000...) không va chạm giữa các project; không còn dải port.
- **Filesystem allowlist:** chỉ thấy project (rw), repo gốc của worktree (rw, nhưng `config` và `hooks` chỉ đọc vì chúng chạy code trên host), tool (ro: opencode, goose, node, bun, Chromium), display QA (cả thư mục `/tmp/.X11-unix` được mount rw vì Xvfb khởi động lại sẽ tạo lại socket). `.team/` chỉ đọc trong box (host đọc `roles/`, `tasks/`, `role-*.md`: lead vẫn viết flex `roles/<role>.md` từ host như cũ), trừ `.team/out`, `.team/logs`, `.team/run` (rw). Không thấy `~/.ssh`, `~/.claude`, project khác, docker socket. Home riêng ở `/box/home` (volume, xoá khi `team close`). Box của worktree chỉ thấy git dir của repo gốc dạng khung xương (objects/refs/logs rw; config, hooks, HEAD, info, packed-refs, config.worktree, commondir/gitdir ro) nên checkout chính của người dùng không bị chiếm quyền; dashboard chạy git với `GIT_DIR`/`GIT_COMMON_DIR` tin cậy, không đệ quy submodule, không hook.
- **Egress:** chỉ uid của worker/app bị lọc; được ra 9router (qua forwarder `localhost:20128` trong box; `NINEROUTER_URL` phải trỏ tới localhost trên host, box tới nó qua gateway), registry npm/yarn/pypi và `projects/.box/<tên>.egress` (lead sửa, `team egress <tên>` nạp lại + in số gói bị chặn). Còn lại (host, tailnet, LAN, internet) bị chặn. Không có github mặc định.
- **Lead chạy app:** `team run <tên> web "bun run dev"` (log `.team/logs/web.log`), `team stop <tên> web`, `team exec <tên> "bun test"` (cài deps, chạy test: không bao giờ chạy code project trên host). `team run` kiểm tra app còn sống sau ~0,3s, không thì báo "failed to start" (lệnh chạy một lần thì dùng `team exec`). Lead cũng xem diff/log bằng `team exec <tên> "git diff"` / `"git log"`, không chạy git trần trong `projects/<tên>` trên host.
- **Truy cập từ Mac:** sidecar Tailscale mỗi project (key ephemeral ở `~/.config/studio/ts-authkey`, chmod 600): `http://<tên>:<port>`; `team https <tên> <port>` → `https://<tên>.<tailnet>.ts.net` (secure context cho PWA/OAuth). `team url <tên>` in các URL và dòng `ssh -L` dự phòng. Chrome phải tắt hoặc đổi Secure DNS thì mới phân giải được MagicDNS.
- `team attach` copy các file `.env*` bị gitignore từ checkout chính. Chỉ dùng secret dev/staging: worker đọc được chúng, egress chặn đường gửi ra ngoài.
- Fail-closed: không dựng được box hoặc firewall thì `team` dừng. `TEAM_SANDBOX=none` chạy trần (chỉ để debug/test framework).
- **Chạy thật (2026-10-13, magisk-glass: 27 commit, 6 worker song song + lead):** `team exec` cho test/build/git, `team run` + URL tailnet cho dev server, Browser MCP (Chrome của user) cho rà UI đều chạy ổn. Những chỗ phải xử lý tay:
  - **Vite chặn host:** dev server trong box được mở bằng tên box (`http://<tên>:5173`) nên Vite trả 403 và app có thể coi host lạ là trang preview. Project phải tự khai báo host (magisk: `VITE_DEV_HOSTS=<tên>,<tên>-1` trong `.env`). Biến `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS` chỉ nhận một host.
  - **`team close <tên>` thiếu role sẽ xoá cả box** (cùng lệnh với đóng một worker). Box tạo lại thì `team run` lại app.
  - **Box tạo lại bị đổi tên tailnet thành `<tên>-1`** vì node cũ còn trong tailnet; `tailscale set --hostname` không lấy lại được tên. Phải xoá node cũ trong admin hoặc đổi tên tay. Hệ quả: URL đổi, phiên đăng nhập và OAuth redirect gắn với tên cũ hỏng theo (IAM chỉ nhận redirect URI đã đăng ký).
  - **Worker cần bị giám sát:** worker có thể hết context (~120K) trước khi commit, hoặc thoát mà không ghi `.done` (lúc đó `team wait` báo timeout/dead). Lead tự review diff, chạy test và commit thay.
  - **Commit trong box** cần `git -c user.name=… -c user.email=…`; cảnh báo `packed-refs.lock: Permission denied` là vô hại (packed-refs chỉ đọc).
  - **Trong box không có `bunx`**, dùng `bun x`.
  - **`team run` có thể báo "failed to start" nhầm** cho process thực ra đã chạy (gặp với một HTTP listener Python); kiểm tra lại bằng curl.
  - **Mẹo rà UI:** snapshot của Browser MCP trên trang nặng (canvas) tốn ~25K token. Rẻ hơn là gắn tạm một script đo vào trang dev, cho nó tự đi một vòng qua các màn và POST kết quả về một listener chạy bằng `team run` trong box (trình duyệt tới qua tailnet), rồi đọc bằng `team exec`.
- Giới hạn: DNS chưa lọc; đích được phép cũng là kênh rò rỉ; IP của domain được chốt lúc nạp luật. Allowlist theo IP nên CDN của registry (Cloudflare/Fastly) dùng chung IP: worker quyết tâm có thể tới site khác cùng CDN (nâng cấp: proxy kiểm SNI). DNS qua resolver của Docker có thể tunnel lượng nhỏ dữ liệu. Display X dùng chung của QA hiển thị cho mọi box. Box worktree có thể di chuyển ref của repo gốc (vd. `refs/heads/main`). `.gitattributes` vẫn chọn được driver định nghĩa trong git config toàn cục của người dùng (vd. git-lfs). Đừng chạy git trần trong `projects/<project box>` trên host.
