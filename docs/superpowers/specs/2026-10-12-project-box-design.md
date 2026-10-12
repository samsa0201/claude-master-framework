# Project box: cô lập worker bằng Docker + Tailscale — design

Ngày: 2026-10-12. Trạng thái: chờ người dùng review.
Bối cảnh và các ứng viên đã loại: [docs/isolation-tech.md](../../isolation-tech.md).

## Target (đã chốt với người dùng)
| # | Target | Hệ quả |
|---|---|---|
| T1 | Chỉ tin Claude lead; worker (harness + custom model) là không tin cậy | Ranh giới do kernel ép, không dựa vào prompt. Worker không thấy gì ngoài project, không có docker socket, không root, không cap |
| T2 | Mỗi project/feature có mạng riêng | App trong box dùng port chuẩn (5173, 3000, …) không va chạm; bỏ hẳn việc cấp và quản lý port |
| T3 | Truy cập dễ từ Mac qua Tailscale | Mỗi feature một tên trên tailnet, không `ssh -L` từng port; có HTTPS thật khi cần secure context |

## Không làm (bản này)
- Docker/compose bên trong box (không project nào dùng; socket docker = root).
- Lọc DNS; giấu `.env` khỏi worker (xem Giới hạn).
- Nhiều display cho QA song song (vẫn một Xvfb chung như hiện tại).
- Di trú tự động project cũ.

## Bằng chứng (spike 2026-10-11/12 trên máy thật: Ubuntu 26.04, kernel 7.0, Docker 29.7, user trong group `docker`, sudo cần mật khẩu)
| Kiểm tra | Kết quả |
|---|---|
| bwrap | `/usr/bin/bwrap` chạy được (profile AppArmor `bwrap-userns-restrict`), bản linuxbrew thì không. Loại vì không cho nhiều worker dùng chung một netns của project khi userns bị AppArmor chặn |
| Hai box cùng :5173 | Không va chạm, kể cả khi host cũng dùng 5173; box này không với sang box kia |
| opencode trong box | Chạy task thật qua 9router (`172.25.0.1:20128`, 9router nghe `0.0.0.0`); file ghi ra thuộc uid 1000; không thấy `/home/samsa`, `~/.ssh` |
| Tailscale sidecar (`tailscale/tailscale:v1.102.3`, userspace, chung netns) | `http://spike-feat:5173` và `https://spike-feat.tail5ede80.ts.net` (cert thật) mở được từ Mac. Chrome trên Mac phải đổi Secure DNS provider để phân giải MagicDNS |
| Firewall iptables lọc uid 1000 do helper `NET_ADMIN` cài | 9router và npm registry: đi được. `example.com`, host `:22`/`:7777`, Mac qua tailnet, LAN: bị chặn. Gỡ luật từ container chung netns không cap (kể cả root): `Permission denied` |
| opencode sau firewall | Task xong (khoảng 46s); tcpdump chỉ thấy kết nối tới 9router. Lần chạy đầu có 6 gói bị chặn không rõ đích, không lặp lại, không làm hỏng task |

## 1. Kiến trúc và vòng đời
- Một project = một box: container `studio-<proj>` trên network `studio-<proj>`, sidecar `studio-<proj>-ts`, home volume `studio-<proj>-home`.
- Box được tạo **lazy** ở `team assign` hoặc `team run` đầu tiên. Tiến trình giữ chỗ: `sleep infinity` với `--init`.
- Box chạy `--user 1000:1000 --cap-drop ALL --security-opt no-new-privileges`. Trong box không có process root nào; root trong netns không bị firewall lọc, nên chỉ sidecar (container riêng) chạy root.
- Worker = pane tmux chạy `docker exec -it -u 1000 -w <proj dir> studio-<proj> <rt_cmd>`. Các worker cùng project dùng chung box, nên chung `localhost`: QA gọi thẳng dev server.
- `team close <proj>`: kill pane, `docker rm -f` box và sidecar, xoá network và home volume. `team close <proj> <role>`: chỉ kill pane, box giữ nguyên.
- **Fail-closed:** không có docker, image không build được, box hoặc firewall không dựng được thì `team assign`/`team run` dừng với lỗi rõ ràng, không bao giờ chạy worker trần. Firewall lỗi thì xoá box vừa tạo.
- `TEAM_SANDBOX=none`: chạy trần như trước. Chỉ dùng khi đặt rõ ràng (test framework, debug); không có port block.
- Lead (Claude) chạy trên host, đọc/sửa file project trực tiếp như hiện nay.

## 2. Image, mount, `.env`, phân vai
**Image `studio-box`:** `box/Dockerfile`, gồm `ubuntu:26.04` + `git curl ca-certificates python3 ripgrep iptables` + thư viện runtime cho Chromium. Tag theo hash nội dung Dockerfile, tự build khi đổi (như `ui/build.sh`). `iptables` có trong image cho helper; worker không có cap nên không dùng được.

**Mount** (đường dẫn bên trong giống hệt host; `$HOME` là volume riêng của box, các mount bên dưới đè lên nó):
| Đường dẫn | Quyền |
|---|---|
| `projects/<proj>` | rw |
| git common dir của repo gốc (chỉ project `attach`, đọc từ file `.git` của worktree) | rw |
| `$HOME` = volume `studio-<proj>-home` (cache npm/bun, dữ liệu opencode qua `XDG_DATA_HOME`, `.gitconfig` sinh ra) | rw |
| `$ROOT/.runtime/{opencode,goose}`, `$ROOT/runtime-home` | ro |
| thư mục bản node đang dùng (`dirname $(dirname $(readlink -f $(command -v node)))`), `~/.bun/bin/bun` | ro |
| `~/.cache/ms-playwright` | ro |
| `/tmp/.X11-unix/X99` (socket display QA) | rw |

Không mount: phần còn lại của `$HOME` (`~/.ssh`, `~/.gitconfig`, `~/.docker/config.json`, `~/.claude`, phần còn lại của `~/.bun` gồm 9router), `/home/linuxbrew`, project khác, repo studio, docker socket.

`.gitconfig` trong box chỉ có `user.name`, `user.email` (chép từ `git config --global`), không có credential: worker commit được, không push được.

Dữ liệu opencode chuyển từ `$ROOT/.runtime/data` (dùng chung) sang home của từng box (đã kiểm tra: không thành phần nào khác đọc thư mục cũ).

**`.env`:** `team attach` copy các file `.env*` đang bị gitignore trong checkout main (bỏ `node_modules`, `.garden`, `.worktrees`) sang worktree, giữ đường dẫn tương đối, in danh sách file. Lead review tên key và cảnh báo khi thấy dấu hiệu secret prod. Worker đọc được `.env`; lớp bảo vệ là egress (phần 3).

**Phân vai:**
- Lead: setup (copy `.env`, cài deps, dịch vụ phụ) và chạy app bằng `team run`; bật app trước khi giao task cho QA.
- Worker: sửa code, chạy test/lint, đọc `.team/logs/`. Không tự bật server lâu dài. Cần restart, đổi cấu hình hoặc mở thêm domain thì ghi yêu cầu vào kết quả task.

## 3. Mạng
**Firewall:** sau khi tạo box (và mỗi lần `team assign`, `team run`, `team egress`), một helper ngắn hạn `docker run --rm --network container:studio-<proj> --cap-add NET_ADMIN studio-box` xoá và cài lại chuỗi luật riêng (`STUDIO`) trong netns của box. Luật chỉ áp dụng cho `-m owner --uid-owner 1000` (worker và app do lead chạy):
1. ACCEPT: `-o lo`; `ESTABLISHED,RELATED`; DNS (udp/tcp 53).
2. ACCEPT: 9router (gateway của network box, port lấy từ `NINEROUTER_URL`).
3. ACCEPT tcp 443/80 tới IP phân giải lúc cài luật của danh sách mặc định: `registry.npmjs.org`, `registry.yarnpkg.com`, `pypi.org`, `files.pythonhosted.org`. Không có github.
4. ACCEPT theo `projects/<proj>/.team/egress` (lead quản lý; mỗi dòng `host[:port]`, port mặc định 443).
5. Còn lại: REJECT, có bộ đếm. Từ đó chặn host, tailnet `100.64.0.0/10`, LAN và internet.

**Truy cập (T3):** sidecar `tailscale/tailscale:v1.102.3`, `--network container:studio-<proj>`, `TS_USERSPACE=true`, `TS_HOSTNAME=<proj>`, `TS_AUTHKEY` đọc từ `~/.config/studio/ts-authkey` (auth key reusable + ephemeral, chmod 600). Key chỉ nằm trong env của sidecar; box khác PID namespace nên worker không đọc được. Không có file key thì in cảnh báo và chạy box không có sidecar.
- `http://<proj>:<port>`: mọi port trong box.
- `team https <proj> <port>` → `tailscale serve --bg <port>` → `https://<proj>.<tailnet>.ts.net`.
- Dự phòng không có Tailscale: `ssh -L <port>:<ip box>:<port> <host>`.

## 4. Thay đổi trên `team`
Code box nằm ở `bin/box.sh` (source từ `bin/team`): `box_image`, `box_up`, `box_fw`, `box_ts`, `box_exec`, `box_down`.

| Lệnh | Thay đổi |
|---|---|
| `new`, `attach` | Bỏ cấp port. `attach` copy `.env*` (phần 2) |
| `assign` | `box_up` (lazy) + `box_fw` → pane chạy qua `box_exec`. Mục Ports trong task file đổi thành: mạng riêng, port mặc định của framework, bind `0.0.0.0`, không tự bật server lâu dài, log app ở `.team/logs/` |
| `run <proj> <tên> "<cmd>"` (mới) | `docker exec -d -u 1000` trong box, `setsid`, ghi pgid vào `.team/run/<tên>.pid`, log `.team/logs/<tên>.log`. `team run <proj>`: liệt kê cái đang chạy |
| `stop <proj> <tên>` (mới) | Kill process group |
| `egress <proj>` (mới) | Cài lại luật, in số gói bị REJECT |
| `https <proj> <port>` (mới) | `tailscale serve` trong sidecar |
| `url <proj>` (thay `ports`) | URL tailnet, IP box, dòng `ssh -L` dự phòng |
| `close <proj>` | `box_down`; bỏ `ports_kill` |
| `display` | Như cũ (Xvfb trên host) |

Xoá: `ports_init`, `ports_kill`, `slot_of`, `slot_free`, `listen`, `projects/.ports`, `ports.env`, `bin/portscan.py`.

Adapter `agents/runtime/*.sh`: `rt_env` bỏ `XDG_DATA_HOME=$ROOT/.runtime/data` khi chạy trong box; `NINEROUTER_URL` trỏ gateway của box. Biến env đi vào bằng `docker exec -e`.

## Test
- `tests/team_test.sh`: chạy với `TEAM_SANDBOX=none` + runtime `fake` (không cần docker). Bỏ test port; thêm test task file mới, copy `.env` khi `attach`, và fail-closed (`TEAM_DOCKER=false` → `assign` lỗi, không tạo pane).
- `tests/box_test.sh` (mới, cần docker; dùng tiền tố tên riêng và tự dọn): hai box cùng :5173; box không với sang nhau; uid 1000 tới 9router và registry, bị chặn host/tailnet/LAN/`example.com`; gỡ luật bị từ chối; không thấy `~/.ssh`; `run`/`stop`; `close` dọn sạch container, network, volume; không có key Tailscale thì có cảnh báo.
- Nghiệm thu tay: một task opencode thật, một task goose thật, một lần QA browser qua noVNC, mở `https://<proj>.<tailnet>.ts.net` từ Mac.

## Chuyển đổi
Pane worker kiểu cũ: `team close` trước. Lần `assign` tiếp theo tự tạo box và xoá `ports.env` cũ. Ba worktree magisk: lead copy `.env` bằng tay một lần.

## Docs
README (bỏ phần port; thêm box, egress, Tailscale, Chrome Secure DNS), `skills/studio/SKILL.md` (lệnh mới, lead lo setup/run, bỏ quy tắc port), `agents/*.md` (bỏ hướng dẫn port), `docs/isolation-tech.md` (đánh dấu đã chọn).

## Giới hạn đã biết
- Đích được phép cũng là kênh rò rỉ (ví dụ registry cho phép publish package); vì vậy danh sách mặc định nhỏ nhất có thể và không có github.
- DNS chưa lọc: truy vấn đi qua resolver của host, rò được dữ liệu nhỏ qua tên miền.
- IP của domain được cài lúc nạp luật; CDN đổi IP thì hỏng tới lần nạp lại kế tiếp.
- Worker đọc được `.env` và mã nguồn; chỉ dùng secret dev/staging trong box. Để sau: app chạy uid riêng để worker không `cat` được `.env` (gói gọn trong `team run`).
- Socket X99 chung: worker QA có thể chụp hoặc gõ vào display ảo đó (chỉ chứa browser QA).
- 6 gói bị chặn không rõ đích ở lần chạy opencode đầu tiên; `team egress` in bộ đếm để phát hiện.
