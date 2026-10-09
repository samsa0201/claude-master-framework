# Worker runtime + roles + QA browser — design

Ngày: 2026-10-09. Trạng thái: chờ người dùng review.
Bằng chứng: [docs/poc/agents-poc.md](../../poc/agents-poc.md), tóm tắt trong README.

## Mục tiêu
- Worker (model tùy chỉnh rẻ: qwen3.8-flash, kCode qua 9router) cho kết quả ổn định hơn omp.
- Người dùng chỉ nói chuyện với Claude (lead). Worker hoạt động như sub-agent: nhận task, làm, ghi kết quả; lead review diff/test trước khi đi tiếp (giống `superpowers:subagent-driven-development`).
- Người dùng xem được worker làm việc (pane tmux) và xem QA thao tác website (browser trên màn hình ảo).

## Không làm ở MVP
- Sandbox cấp OS (Docker/OpenShell). Chỉ có: git worktree riêng + hệ thống quyền của agent.
- Nhiều QA song song / nhiều màn hình ảo; stream CDP tự viết vào `team ui`.
- Tự động giao lại khi lỗi, health-check định kỳ, đo chi phí token.
- Runtime pi (không có hệ thống quyền) và codex (trượt T3 qua 9router).

## Quyết định đã chốt
| Chủ đề | Quyết định |
|---|---|
| Runtime mặc định | **opencode**; **goose** làm adapter dự phòng |
| Mô hình chạy | Pane tmux tương tác (giữ ngữ cảnh, người dùng xem trực tiếp) |
| Model | qwen3.8-flash (logic), kCode (UI); cả hai qua 9router OpenAI-compatible |
| Role | `pm`, `ux`, `dev`, `qa`, `qc`, `docs` |
| Prompt role | base (`agents/<role>.md`) + flex do lead viết theo project |
| QA browser | Playwright MCP có giao diện trên `DISPLAY=:99`, xem qua noVNC `localhost:6080`, tuần tự |

## 1. Kiến trúc
```
User ──chat──▶ Claude (lead, pane chính)
                 │ team assign <proj> <role[-suffix]> "<task>" [--runtime R] [--model M] [--new]
                 ▼
        bin/team ── adapter agents/runtime/<R>.sh ──▶ pane tmux @team=<proj>-<role>
                 │                                       (opencode/goose + model, cwd = projects/<proj>)
                 └── .team/tasks/<id>.md  ◀── worker đọc     .team/out/<id>.md + <id>.done ──▶ team wait
```
Phần dùng chung giữ nguyên từ `bin/team` hiện tại: `new`, `attach` (worktree), file task, `.done`, `wait`, `ls`, `close`, `ui`, header pane. Chỉ thay đoạn khởi động worker (hiện là `omp`/`ccp`) bằng lời gọi adapter.

## 2. Adapter runtime
Mỗi runtime là một file `agents/runtime/<R>.sh` được `bin/team` `source`, định nghĩa:
- `rt_start` — in ra lệnh shell để mở pane, task đầu tiên đi vào argument (tránh race lúc khởi động). Nhận `$MODEL`, `$MSG`, `$ROLE_PROMPT` (đường dẫn file prompt đã ghép).
- `rt_env` — in các cặp `KEY=VAL` cần cho pane: thư mục config riêng của runtime, và `NINEROUTER_API_KEY` được truyền từ env của lời gọi `team` (tmux server không có biến này — phát hiện từ POC). Không bao giờ ghi giá trị key ra file.
- Tin nhắn tiếp theo vào pane đang sống: dùng chung `tmux send-keys -l` + `Enter` như hiện nay (opencode đã chứng minh nhận được).

Config của runtime nằm trong studio, cô lập khỏi config của người dùng:
- `runtime-home/opencode/` (`XDG_CONFIG_HOME`): provider 9router (`@ai-sdk/openai-compatible`, `apiKey: "{env:NINEROUTER_API_KEY}"`), model qwen3.8-flash + kCode, `permission` (edit/bash allow, webfetch deny, cùng các pattern deny cho bash nguy hiểm nếu opencode hỗ trợ — xem Rủi ro), MCP Playwright cho QA.
- `runtime-home/goose/`: custom provider JSON với `api_key_env`, `GOOSE_MODE: auto`, extension `developer`, `GOOSE_DISABLE_KEYRING=1`, `--max-tool-repetitions 5`.
- Thư mục `runtime-home/` commit được (không chứa key).

Prompt role được nạp: opencode/goose không có cờ `--append-system-prompt` như omp → adapter đặt prompt đã ghép vào đầu tin nhắn đầu tiên ("Read `.team/role-<role>.md` then `.team/tasks/<id>.md` and do it exactly."). Cùng cơ chế "đọc file" như hiện nay, không phụ thuộc tính năng riêng của runtime.

Chấp nhận một runtime cho một role khi: (1) mở pane không có hộp thoại nào; (2) qua `tests/runtime-accept.sh` (T1–T3) với model của role; (3) nhận được tin nhắn thứ hai qua `send-keys`.

## 3. Role: base + flex
- Base `agents/<role>.md`: frontmatter `runtime`, `model`, `browser` (`none|qa|self`), `timeout`; thân = trách nhiệm, đầu ra, tiêu chí xong, quy tắc chung (tiếng Việt, YAGNI, chỉ làm trong project, không commit secret).
- Flex `projects/<proj>/.team/roles/<role-name>.md`: do lead viết khi bắt đầu project/attach — stack, lệnh build/test, quy ước, file quan trọng, chuyên môn (BE/FE/mobile). Frontmatter của flex được phép ghi đè `runtime`/`model`/`browser`/`timeout`.
- Tên role có hậu tố: `dev-fe` → base là file agents khớp tiền tố dài nhất (`agents/dev.md`), flex là `.team/roles/dev-fe.md`. Không có file khớp → `agents/_base.md` như hiện nay. Mỗi tên role là một pane riêng.
- Thứ tự ưu tiên giá trị: cờ dòng lệnh > flex > base.
- `team assign` ghép base + flex thành `.team/role-<role-name>.md` (như hiện nay ghép base).

| Role | Việc | model mặc định | browser |
|---|---|---|---|
| `pm` | idea → `docs/prd.md` | qwen3.8-flash | none |
| `ux` | flow, màn hình, mockup | kCode | none |
| `dev` | viết code theo TDD (test đỏ → code → xanh), chỉ sửa đúng phạm vi task, chạy test trước khi báo xong | qwen3.8-flash (flex `dev-fe` đặt kCode) | none (`self` khi flex/task bật) |
| `qa` | kiểm tra chức năng: chạy app, thao tác browser, ca biên; bằng chứng trace/video/ảnh | qwen3.8-flash | qa |
| `qc` | đọc diff so với spec + quy ước, chạy lint/test, báo vấn đề theo mức độ; **không sửa code** | qwen3.8-flash | none |
| `docs` | README, hướng dẫn chạy, tài liệu API, CHANGELOG từ code thật; **không sửa code** | qwen3.8-flash | none |

`web-dev`, `android-dev` bị thay bằng `dev` + flex. Timeout mặc định: qwen 15 phút, kCode 30 phút (kCode có lúc chờ 100–200s/request).

## 4. QA với browser
- Runtime của role có `browser != none` phải hỗ trợ MCP; opencode cấu hình Playwright MCP (`@playwright/mcp`) chạy có giao diện, `DISPLAY=:99`, lưu trace + video vào `.team/out/<id>/`, dùng Chromium của Playwright đã có trong `~/.cache/ms-playwright`.
- `team assign` với role có browser: nếu chưa chạy thì bật `Xvfb :99` + `x11vnc -localhost -rfbport 5999` + `websockify 127.0.0.1:6080` (noVNC từ `/usr/share/novnc`), in `http://localhost:6080/vnc.html`. Mọi cổng chỉ nghe 127.0.0.1; người dùng xem qua `ssh -L 6080:localhost:6080`.
- Một màn hình → chỉ một worker có browser chạy cùng lúc; `team assign` từ chối (báo lỗi rõ) nếu đã có worker browser đang chạy chưa `.done`.
- `team display stop` dọn Xvfb/x11vnc/websockify. `team close` không tắt màn hình.
- Đăng nhập: dùng `storageState` theo quy trình SSH trong SKILL.md, truyền cho Playwright MCP; QA không thấy token.
- Báo cáo QA (`.team/out/<id>.md`): từng bước, pass/fail, đường dẫn ảnh/trace. Lead đọc, nghi ngờ thì mở trace hoặc tự kiểm bằng browser MCP của mình.

## 5. Xử lý lỗi
| Tình huống | Phát hiện | Xử lý |
|---|---|---|
| Thiếu key / endpoint chết | `team assign` preflight: `NINEROUTER_API_KEY` có set, `GET /v1/models` trả 200 | báo lỗi, không mở pane |
| Worker kẹt/lặp | `team wait` hết timeout của role/model | trả `timeout`; lead `capture-pane` rồi nhắc / đóng giao lại / đổi runtime-model |
| Pane chết chưa `.done` | `team wait` thấy pane có `@tid` biến mất | trả `dead` ngay |
| Báo xong nhưng sai | lead review diff + tự chạy test (đã có trong flow) | giao lại kèm nhận xét |
| Màn hình ảo bận | `team assign` role browser | từ chối, báo worker đang giữ |

## 6. Kiểm thử
- `tests/team_test.sh` + runtime giả `agents/runtime/fake.sh` (không gọi model; ghi `.md` + `.done`): assign → wait → close, `--new`, tên role hậu tố chọn đúng base/flex, thứ tự ưu tiên runtime/model, pane chết → `dead`, preflight thiếu key, khóa màn hình ảo. Chạy trong một tmux session riêng, không đụng pane người dùng.
- `tests/runtime-accept.sh <runtime> <model>`: viết lại sạch bench T1–T3 của POC (repo mẫu, timeout, chấm bằng script). Chạy khi thêm runtime/model.

## 7. Di chuyển từ hiện trạng
- Hoàn tác thay đổi chưa commit dùng `ccp` trong `bin/team`, `SKILL.md`, `agents/*.md` (thay bằng thiết kế này).
- Cập nhật `SKILL.md` (role mới, `--runtime`, flex, QA browser, timeout), `README.md` (setup opencode thay omp), `install.sh` (cài opencode/goose vào chỗ cố định, không seed `~/.omp`).
- omp, `models.example.yml` giữ tới khi adapter opencode chạy ổn, sau đó xóa.

## Rủi ro
- Bench POC chỉ 3 task nhỏ; chưa có task Android hay nhiều file. Lead vẫn review mọi diff.
- `permission` của opencode với bash allow không chặn được lệnh phá hoại; cần xác minh opencode có hỗ trợ deny theo pattern (vd `git push*`, `rm -rf /*`) và quyền thư mục ngoài project hay không. Nếu không, chấp nhận rủi ro như MVP đã chốt (không sandbox).
- kCode chập chờn ở hạ tầng: timeout dài, task UI chậm.
- opencode từng báo "DONE" mà không làm gì (1 lần): đã che bởi review của lead và QC.

## Quá trình brainstorm (2026-10-09)
Bối cảnh: chất lượng đầu ra của worker omp không như mong muốn. Thử thay omp bằng Claude Code qua `ccp` (profile gateway): worker chạy được nhưng bị hộp thoại trust + thông báo billing của auto-mode chặn, gateway không stream nên rất chậm (task tạo 1 file ~4 phút), connector claude.ai bị tắt khi có `ANTHROPIC_API_KEY`. → Quyết định không vá tiếp mà brainstorm lại lớp worker.

| # | Câu hỏi | Lựa chọn | Lý do / phương án bị loại |
|---|---|---|---|
| 1 | Tiêu chí chọn agent | An toàn quan trọng nhất; worker như sub-agent của Claude (người dùng chỉ nói chuyện với Claude); rồi tương thích model tùy chỉnh; rồi chất lượng với model yếu | — |
| 2 | Ứng viên POC | Codex CLI, opencode, goose, pi | Bỏ Claude Code headless (vấn đề gateway ở trên), bỏ omp (lý do ban đầu) |
| 3 | An toàn = chặn gì | Đọc secret, ghi ngoài project, hành động khó hoàn tác | Mạng ra ngoài không bắt buộc |
| 4 | Sandbox ở đâu | Cân nhắc Docker thuần, sandbox riêng từng agent, NVIDIA OpenShell (Landlock + seccomp + proxy deny, policy YAML; chạy K3s trong Docker) | bwrap không chạy được trên máy (AppArmor chặn userns), Docker dùng được |
| 5 | Sandbox có thừa không | **MVP không sandbox** | Sub-agent của Claude cũng không có sandbox; sandbox gây khó (toolchain, mạng, quyền file, debug, xem trực tiếp). Ghi nhận: worktree không chặn được đọc secret — chấp nhận ở MVP |
| 6 | Mô hình chạy worker | **Pane tmux tương tác** | Bỏ headless-mỗi-task (dù tránh được hộp thoại) và lai; muốn xem trực tiếp + giữ ngữ cảnh |
| 7 | Model cho POC | qwen3.8-flash, kCode | Bỏ deepseek-v4.1-flash: chậm và lặp; giả thuyết (chưa kiểm chứng): token suy luận dài + gateway không stream, lớp dịch API làm rơi tool call |
| 8 | Bộ task POC | T1 hàm + test, T2 sửa UI, T3 kỷ luật (.done, không sửa file khóa) | Chấm bằng script, không tin lời agent |
| 9 | Worker dùng browser để làm gì | Cả ba: QA kiểm UI, dev tự xem UI, lead tự kiểm — thành cờ `browser` theo role | Yêu cầu chính: **người dùng nhìn thấy QA thao tác website** |
| 10 | Cách xem browser từ Mac | **A: Xvfb + x11vnc + noVNC, port-forward `localhost:6080`** (đã thử, người dùng thấy ổn) | B (tự stream CDP vào `team ui`, xem nhiều QA một trang) để sau khi cần song song; video/trace chỉ làm bằng chứng |
| 11 | QA tuần tự hay song song | Tuần tự (một màn hình ảo) | Song song → phương án B |
| 12 | Kiến trúc lớp worker | **Adapter mỏng mỗi runtime** | Bỏ "cứng một agent" (khóa chặt) và "proxy dịch API trước mọi agent" (nhiều việc, có thể chính là nguồn lỗi lặp) |
| 13 | Runtime mặc định | **opencode, goose dự phòng** — theo kết quả POC vòng 2 (xem README) | pi không có quyền; codex trượt T3 qua 9router |
| 14 | Bộ role | `pm`, `ux`, `dev`, `qa`, `qc`, `docs` | `dev` chung (TDD); BE/FE/mobile do lead thêm qua flex. Tách QA (chức năng, browser) và QC (chất lượng code, không sửa code) |
| 15 | Prompt role | base cố định + flex do lead viết khi bắt đầu project; tên role có hậu tố (`dev-fe`) | Cho phép nhiều dev chuyên môn khác nhau trong cùng project |

POC: vòng 1 (cài đặt + tài liệu) bị chặn vì shell chưa có `NINEROUTER_API_KEY`; người dùng set key, vòng 2 đo thật 4 agent × 2 model × 3 task. Chi tiết trong [docs/poc/agents-poc.md](../../poc/agents-poc.md).
