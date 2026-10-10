# Web UI (`team ui`) — làm lại

Ngày: 2026-10-09. Trạng thái: đã làm xong (slice 1-4). Kiểm bằng `tests/ui_api_test.py`, `bun test`, `tests/team_test.sh` và Playwright trên dữ liệu mẫu `tests/ui_demo.sh`.

## Mục tiêu
Thay màn hình Pip-Boy (văn phòng pixel, CRT, roi cursor) bằng dashboard hiện đại, gọn, đọc được khi làm việc lâu. Vẫn **chỉ xem** (không ghi gì), nhưng thêm: đọc tài liệu dự án và xem diff của worktree.

## Quyết định đã chốt (từ người dùng)
| Chủ đề | Quyết định |
|---|---|
| Hướng thiết kế | Dashboard hiện đại kiểu Linear/Vercel, light + dark |
| Chức năng | Chỉ xem: trạng thái worker/task, feed, terminal tmux + **xem docs** + **xem diff** |
| Stack | **Vite + Vue 3 (`<script setup>`) + TypeScript, chạy bằng Bun** |

Do lead chọn (đổi được): CSS thuần với design token (không Tailwind), `markdown-it` để render md (tắt HTML thô nên an toàn), parser diff tự viết (~60 dòng, không thêm dependency), font hệ thống (không gọi Google Fonts, chạy offline).

## Không làm
- Assign/close worker, đổi model từ UI; ghi hoặc sửa file; đăng nhập (server vẫn chỉ nghe `127.0.0.1`).
- Terminal đầy đủ (xterm.js, nhập phím). Giữ polling `tmux capture-pane` như cũ.
- Giữ lại theme Pip-Boy, roi cursor, Vault Boy, `helm.png`. Vẫn còn trong git history (commit `0dfce01`); nói nếu muốn giữ làm theme phụ.

## Giao diện
```
┌ sidebar ─────┬ header: <project> · 3 active · 5/8 done · 1 stale ── [light/dark] ┐
│ ● magisk     ├ tabs: Overview │ Docs │ Changes │ Terminal                         │
│ ○ todo-app   │                                                                   │
│              │  Overview: lưới thẻ worker (dev-fe, qa, ...) + timeline task      │
│ 5 units      │  Docs:     cây file docs/ .team/roles/ .team/out/ → render md     │
│ online       │  Changes:  Uncommitted | Commits → diff từng file (unified)       │
│              │  Terminal: chọn pane @team, output cập nhật mỗi 1s                │
└──────────────┴───────────────────────────────────────────────────────────────────┘
```
- **Thẻ worker**: tên seat, badge trạng thái (working / idle / stale / done — có chữ + icon, không chỉ màu), task hiện tại, thời gian chạy. Bấm vào → tab Terminal của worker đó.
- **Timeline**: assigned → done theo thời gian, bấm một task để mở drawer: nội dung task (`.team/tasks/<id>.md`) và báo cáo (`.team/out/<id>.md`).
- Responsive: dưới 860px sidebar thành dropdown. Tôn trọng `prefers-reduced-motion` và `prefers-color-scheme`; nút đổi theme nhớ trong `localStorage` (bọc try/catch).
- Polling: `/api/state` mỗi 2s, terminal mỗi 1s chỉ khi tab Terminal đang mở; dừng khi tab trình duyệt ẩn. Mất kết nối → banner "link down", tự nối lại.

## API (`ui/serve.py`, stdlib, chỉ GET)
| Route | Trả về |
|---|---|
| `GET /api/state` | như `/state` hiện tại (tasks, live, panes) + `projects` (mọi project có `.team/`, kể cả chưa có task) |
| `GET /api/term?tag=` | như `/term` hiện tại |
| `GET /api/projects/<p>/files` | danh sách `.md` trong `docs/`, `.team/roles/`, `.team/tasks/`, `.team/out/` |
| `GET /api/projects/<p>/file?path=` | nội dung một file `.md` ở trên |
| `GET /api/projects/<p>/diff` | `git diff HEAD` (uncommitted) + file chưa track hiện như diff "new file" (tối đa 50 file, mỗi file ≤ 100 KB; bỏ qua binary, symlink, `.env*`/`*.pem`/`*.key`/`auth.json`, kèm lý do trong `skipped`) |
| `GET /api/projects/<p>/log` / `.../commit?sha=` | 30 commit gần nhất / `git show` một commit |
| `GET /*` | file tĩnh trong `ui/dist/`, không có thì trả `index.html` (SPA) |

Bảo vệ (đầu vào do worker model rẻ tạo ra nên coi là không tin cậy):
- `<p>` khớp `^[A-Za-z0-9][A-Za-z0-9._-]*$` (không chứa `/`, không bắt đầu bằng dấu chấm; `team new` không giới hạn tên nên không ép chữ thường) và là thư mục thật dưới `projects/`; `sha` khớp `^[0-9a-f]{7,40}$`.
- `path`: chỉ `.md`, `realpath` phải nằm trong 4 thư mục whitelist (chặn `../` và symlink), tối đa 512 KB.
- Git chạy bằng `subprocess` dạng list (không shell), kèm `-c core.fsmonitor=false --no-ext-diff --no-textconv --no-color`, `GIT_OPTIONAL_LOCKS=0`, timeout 5s, output cắt ở 1 MB và báo "truncated". Chỉ chạy khi project có `.git` riêng (không thì git sẽ đi ngược lên repo studio). Repo chưa có commit thì diff với empty tree.
- Header `Host` phải là `localhost`/`127.0.0.1`/`::1` (chặn DNS rebinding đọc diff từ trang web khác); thêm host khác (vd. `tailscale serve`) qua `TEAM_UI_HOSTS=a,b`. Mọi response có CSP `default-src 'self'` và `nosniff`.
- File tĩnh: `realpath` phải nằm trong `ui/dist/`. Bỏ whitelist ảnh cũ.
- `projects/` dùng `TEAM_PROJECTS` như `bin/team` (để test được bằng thư mục tạm).

## Cấu trúc & build
```
ui/serve.py            # server (sửa)
ui/web/                # nguồn: package.json, bun.lock, vite.config.ts, index.html, src/
  src/{App.vue,api.ts,diff.ts,format.ts,components/*.vue}
ui/dist/               # output build, gitignored
```
- Build: `cd ui/web && bun install --frozen-lockfile && bun run build`. `install.sh` chạy bước này nếu có `bun` (không thì in hướng dẫn cài).
- `team ui`: tự build khi thiếu `ui/dist/` hoặc khi nguồn trong `ui/web/` mới hơn bản build; build lỗi mà đã có bản cũ thì phục vụ bản cũ, chưa có bản nào thì dừng và in lệnh build (không phục vụ trang trống). `bun.lock` tạo bằng bun 1.3.x để bun cũ vẫn đọc được.
- Dev: `bun run dev` (Vite, proxy `/api` → `127.0.0.1:7777`, cần `team ui` chạy song song).
- Xóa: `ui/index.html`, `ui/helm.png`, `ui/vaultboy.gif`. Sửa mô tả "cute live office view" ở `bin/team`, `skills/studio/SKILL.md`, `README.md`; thêm `ui/dist/` và `ui/web/node_modules/` vào `.gitignore`.

## Các slice (làm lần lượt, mỗi slice tự kiểm trước khi qua slice sau)
1. **API + test**: sửa `serve.py` theo bảng trên; `tests/ui_api_test.py` (stdlib `unittest`, thư mục tạm + repo git giả): shape của state, chặn path traversal/symlink/không phải `.md`, tên project sai → 404, diff/log/commit trên repo thật, cắt output, SPA fallback, file tĩnh ngoài `dist/` bị từ chối.
2. **Scaffold Vue + Overview**: Vite/Vue/TS, token + light/dark, sidebar, header, thẻ worker, timeline, drawer task, polling + banner mất kết nối.
3. **Terminal, Docs, Changes**: tab terminal; cây docs + render markdown; diff viewer (parser `diff.ts` có `bun test`).
4. **Hoàn thiện**: responsive, a11y (focus, aria, bàn phím), empty/error state, dọn file cũ, cập nhật docs, `install.sh`, `.gitignore`.

## Tiêu chí xong
- `python3 -m unittest tests/ui_api_test.py`, `bun test`, `bun run build` và `tests/team_test.sh` đều xanh.
- Chạy `team ui` với dữ liệu mẫu (project giả có tasks/out/docs/repo git + pane tmux giả); Playwright Chromium chụp ảnh các tab ở desktop (1280px), mobile (390px), light và dark; không có lỗi console.
- Chuỗi thử bảo mật thủ công: `/api/projects/..%2f..%2fetc/file`, `path=../../.env`, symlink ra ngoài đều bị từ chối.

## Cách thực hiện
Lead tự code trong session này (môi trường cloud không có 9router/worker pane). Nếu bạn muốn chạy bằng worker `dev-fe` (kCode) thì mỗi slice ở trên đã đủ nhỏ để giao.
