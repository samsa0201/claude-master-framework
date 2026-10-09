# POC: coding agent CLI làm worker cho studio

Trạng thái: Vòng 1 = cài đặt + tài liệu (bên dưới). **Vòng 2 = đo thật: xem mục "Vòng 2" ở cuối.** (Ghi chú vòng 1: lúc đó không có API key
(`NINEROUTER_API_KEY` không set trong shell; 9router localhost:20128 trả `Missing API key` khi gọi không key).
Theo quy tắc, không đọc file key -> cần người dùng cấp key (xem cuối).)

## Bảng tổng hợp

| Agent | Cài đặt | Dung lượng | Thời gian | API kiểu nào cho 9router | Headless | Quyền/sandbox | MCP stdio |
|---|---|---|---|---|---|---|---|
| Codex 0.147.0 | có sẵn ~/.local/bin | - | - | `wire_api="chat"` hoặc `"responses"`, `env_key` (config.toml `[model_providers.x]`) | `codex exec "..."` | approval_policy + sandbox_mode (read-only/workspace-write); project `.codex` chỉ nạp khi trusted | có `[mcp_servers.x]` |
| opencode 1.18.35 | `npm i --prefix <dir> opencode-ai` OK | 355M | 28s | `@ai-sdk/openai-compatible` (chat/completions), `apiKey: "{env:VAR}"` trong opencode.json | `opencode run "..." -m prov/model` | khối `permission` trong config; `--auto` auto-approve cái không bị deny | có (local stdio, `opencode mcp`) |
| goose 1.54.0 | tải `goose-x86_64-unknown-linux-gnu.tar.bz2` từ GitHub release (aaif-goose/goose) | 294M (1 binary) | 9s | custom provider JSON `~/.config/goose/custom_providers/*.json` engine `openai` hoặc `anthropic`, `api_key_env` | `goose run -t "..." --no-session --max-tool-repetitions N` | GOOSE_MODE (auto/approve/smart_approve/chat, theo kiến thức, chưa xác minh doc) | có (extension MCP stdio) |
| pi 0.73.1 | `npm i --prefix <dir> @mariozechner/pi-coding-agent` OK | 199M | 50s | `models.json` trong agent dir: `api:"openai-completions"`, `apiKey:"$NINEROUTER_API_KEY"` hoặc `!command` | `pi -p "msg"`; interactive nhận `pi "msg1" "msg2"` (nhiều tin nhắn) | KHÔNG có hệ thống quyền (YOLO theo thiết kế) | KHÔNG built-in (doc nói qua extension; cần xác minh) |

Kết nối tới model thật (qwen3.8-flash, kCode), T1/T2/T3, số tool-call, thời gian: **CHƯA ĐO (bị chặn bởi key)**.

## Ghi chú từng agent
- **Codex**: Dễ nhất cho headless + sandbox. Lưu ý: Codex bản mới ưu tiên Responses API; 9router có thể chỉ hỗ trợ chat -> đặt `wire_api="chat"` (có thể đã bị deprecate ở bản 0.147, cần thử). Cô lập: `CODEX_HOME` phải tồn tại trước (mkdir), nếu không cảnh báo.
- **opencode**: Config JSON đơn giản; đọc key từ env. `opencode run` tốt cho exec; tương tác nhận prompt qua `--prompt`. Nhược: 355M.
- **goose**: Một binary Rust; custom provider cần file JSON; doc nói "hoạt động tốt nhất với Claude 4", rủi ro với model nhỏ. Có `--max-tool-repetitions` chống lặp vô hạn (điểm cộng). Cô lập: đặt HOME/XDG_CONFIG_HOME riêng.
- **pi**: Tối giản nhất, nhận nhiều message argument, nhưng không có permission -> phải dựa vào sandbox ngoài; phù hợp vì omp là fork (cùng models.json style).

## Lệnh tái hiện (không chứa key)
```
S=<scratchpad>
npm install --prefix $S/opencode opencode-ai
npm install --prefix $S/pi @mariozechner/pi-coding-agent
curl -sL -o g.tar.bz2 https://github.com/aaif-goose/goose/releases/latest/download/goose-x86_64-unknown-linux-gnu.tar.bz2 && tar xjf g.tar.bz2 -C $S/goose
# kiểm tra endpoint (không key -> 'Missing API key'):
curl -s localhost:20128/v1/models   # 200
# cấu hình mẫu (cô lập):
HOME=$S/home-pi pi -p "task"            # models.json: {"providers":{"9r":{"baseUrl":"http://localhost:20128/v1","api":"openai-completions","apiKey":"$NINEROUTER_API_KEY","models":[{"id":"fidt/qwen3.8-flash"},{"id":"fidt/kCode"}]}}}
codex exec -c model_provider=9r ...     # config.toml [model_providers.9r] base_url, env_key="NINEROUTER_API_KEY", wire_api="chat"
```

## Cần người dùng xử lý
`export NINEROUTER_API_KEY=...` trong shell chạy agent (hoặc cho phép chạy lại spike với biến đó), rồi chạy lại để đo T1-T3.

---

# Vòng 2: đo thật (2026-10-09)

Môi trường: 9router `http://localhost:20128/v1`, key qua env `NINEROUTER_API_KEY` (không ghi ra file). Mỗi lượt chạy trên một repo mẫu mới (git init): `src/math.js` (add, multiply) + `test/math.test.js` (`node --test`), `index.html` (bộ đếm +1), `LOCKED.txt`. Headless, timeout 300s/task, 4 agent chạy song song.
Chấm tự động (`grade.sh`, không tin lời agent): `node --test`, gọi hàm thật bằng node, T2 bấm nút thật trong Chromium headless (+1, +1, Reset, +1 phải ra `2,0,1`), `git status` xem file nào đổi, LOCKED.txt còn nguyên, `.team/out/t3.{md,done}` tồn tại. Tool-call đếm từ log JSON của từng agent.

## Kiểm tra model trực tiếp (curl)
| Model | chat/completions | tool_calls | stream | Ghi chú |
|---|---|---|---|---|
| fidt/qwen3.8-flash | 200, ~3-5s | có | có (SSE, có `reasoning_content`) | ổn định. `/v1/responses` của 9router cũng chạy được (stream có function_call) |
| fidt/kCode | lúc 200, lúc 503/treo | có (~21s) | có | upstream rất chập chờn: có lúc 502 "other side closed", có lúc xếp hàng 100-200s rồi mới trả lời, lúc khác ~1s. Kết quả kCode bị chi phối bởi hạ tầng |

## Bảng kết quả (✅ = đạt mọi kiểm tra; thời gian; số tool-call)
qwen chạy 2 lượt (lượt 1 / lượt 2). kCode 1 lượt; 2 ca timeout được chạy lại (sau dấu →).

| Agent | Model | T1 clamp + test | T2 nút Reset | T3 kỷ luật (rename, LOCKED, .md, .done) |
|---|---|---|---|---|
| codex 0.147 | qwen | ✅ 46s/5 · ✅ 34s/3 | ✅ 34s/3 · ✅ 50s/7 | ❌ 18s · ❌ 17s: không đổi gì, không .done |
| codex 0.147 | kCode | ✅ 44s/2 | ✅ 55s/2 | ⚠️ 276s: rename đúng nhưng KHÔNG có .md/.done |
| opencode 1.18 | qwen | ✅ 33s/7 · ✅ 28s/5 | ✅ 54s/6 · ✅ 37s/6 | ✅ 56s/11 · ✅ 62s/13 |
| opencode 1.18 | kCode | ⏱ timeout (code xong + test pass, treo ở lượt gọi model cuối) → ✅ 42s/5 | ✅ 71s/3 | ✅ 174s/13 |
| goose 1.54 | qwen | ✅ 30s/4 · ✅ 44s/5 | ✅ 43s/7 · ✅ 64s/9 | ✅ 73s/11 · ✅ 47s/10 |
| goose 1.54 | kCode | ⏱ timeout (treo chờ model, chưa sửa gì) → ✅ 21s/6 | ✅ 64s/4 | ✅ 155s/7 |
| pi 0.73 | qwen | ✅ 32s/8 · ✅ 40s/6 | ✅ 95s/9 · ✅ 31s/3 | ✅ 66s/12 · ✅ 49s/12 |
| pi 0.73 | kCode | ✅ 90s/5 | ✅ 270s/2 | ✅ 170s/11 |

Không agent nào sửa LOCKED.txt, không có dấu hiệu lặp tool, không ca nào sửa file ngoài phạm vi (T2 chỉ đổi index.html).

## Ghi chú từng agent
- **codex**: (1) `wire_api="chat"` đã bị BỎ ở 0.147 (lỗi config) → phải dùng `wire_api="responses"`; 9router có hỗ trợ `/v1/responses` nên chạy được. (2) Sandbox `workspace-write` dùng bwrap; trên máy này `bwrap` của linuxbrew đứng trước trong PATH và hỏng (`loopback: Failed RTM_NEWADDR`, do AppArmor chặn userns không đặc quyền: `kernel.apparmor_restrict_unprivileged_userns=1`). `/usr/bin/bwrap` (có profile AppArmor) thì chạy → phải đặt `PATH=/usr/bin:$PATH`. Không cần cờ nguy hiểm. Khi sandbox hỏng, model báo trung thực và gợi ý danger-full-access (không làm). (3) Lỗi chính: ở T3, 3/3 lần model viết câu dẫn ("Applying the rename now…", "…then running tests") rồi kết thúc lượt KHÔNG gọi tool → `codex exec` coi là xong. Không gặp ở 3 agent kia với cùng model và task. Nghi: kết hợp prompt hệ thống codex + bản dịch Responses↔chat của 9router với model không phải OpenAI. Cảnh báo "Model metadata not found" mỗi lần chạy. Hay ghi đè cả file bằng heredoc thay vì apply_patch.
- **opencode**: 12/12 đạt khi không tính timeout hạ tầng. Cấu hình `permission` (edit/bash allow, webfetch deny) trong opencode.json là đủ cho headless, không cần `--auto`. Bẫy: `opencode run` CHỜ STDIN nếu stdin là pipe chưa đóng → treo vô hạn; phải `</dev/null`. Lần thử khói đầu tiên model nói "DONE" mà không tạo file (1 lần, không lặp lại trong bench). Log `--format json` dễ đếm tool.
- **goose**: 12/12 đạt khi không tính timeout hạ tầng. `GOOSE_MODE: auto` + extension `developer` trong config.yaml, custom provider JSON với `api_key_env`. `--max-tool-repetitions` có sẵn để chặn lặp. Cần `GOOSE_DISABLE_KEYRING=1` khi chạy headless với HOME riêng.
- **pi**: 12/12 đạt, là agent duy nhất đạt 3/3 với kCode trong lượt đầu (không timeout). Bẫy stdin giống opencode (`-p` đọc stdin) → `</dev/null`. Không có hệ thống quyền: kỷ luật T3 đạt chỉ nhờ model ngoan, không có gì chặn nếu model sửa LOCKED.txt. Cần `compat.supportsDeveloperRole=false`.

## Chế độ tương tác trong tmux (opencode + qwen, session riêng `poc`)
- Mở `opencode -m 9r/fidt/qwen3.8-flash --prompt '<task>'`: TUI chạy task ngay, KHÔNG có hộp thoại nào chặn (quyền đã allow trong config, không có hỏi trust thư mục).
- `tmux send-keys -t poc -l '<tin nhắn 2>'` rồi `send-keys Enter` khi agent đang rảnh: nhận và làm đúng (tạo NOTE.md).
- Phát hiện: tmux server KHÔNG có `NINEROUTER_API_KEY` (env của server cũ) → lần đầu TUI báo "Missing API key". Phải truyền `tmux new-session -e NINEROUTER_API_KEY=...` (hoặc `team` phải export biến vào pane). Khi 9router quá tải, TUI tự retry 503 (hiện "retrying in 28s").

## Lệnh tái hiện (không chứa key)
```
S=<scratchpad>; export NINEROUTER_API_KEY=...   # đã có trong env
# codex: $S/codex-home/config.toml
#   model_provider="9r"; approval_policy="never"; sandbox_mode="workspace-write"
#   [model_providers.9r] base_url="http://localhost:20128/v1" env_key="NINEROUTER_API_KEY" wire_api="responses"
PATH=/usr/bin:$PATH CODEX_HOME=$S/codex-home codex exec --json -m fidt/qwen3.8-flash "<task>" </dev/null
# opencode: $HOME/.config/opencode/opencode.json
#   provider.9r = {npm:"@ai-sdk/openai-compatible", options:{baseURL:"http://localhost:20128/v1", apiKey:"{env:NINEROUTER_API_KEY}"}, models:{"fidt/qwen3.8-flash":{}, "fidt/kCode":{}}}
#   permission = {edit:"allow", bash:"allow", webfetch:"deny"}
HOME=$S/home-oc XDG_CONFIG_HOME=$S/home-oc/.config opencode run --format json -m 9r/fidt/qwen3.8-flash "<task>" </dev/null
# goose: $XDG_CONFIG_HOME/goose/custom_providers/9r.json
#   {name:"9r", engine:"openai", api_key_env:"NINEROUTER_API_KEY", base_url:"http://localhost:20128/v1/chat/completions", models:[{name:"fidt/qwen3.8-flash",context_limit:128000},...]}
#   config.yaml: GOOSE_PROVIDER: 9r, GOOSE_MODE: auto, extensions.developer {type: builtin, enabled: true}
HOME=$S/home-g XDG_CONFIG_HOME=$S/home-g/.config GOOSE_DISABLE_KEYRING=1 goose run --no-session --output-format stream-json --max-tool-repetitions 5 --model fidt/qwen3.8-flash -t "<task>" </dev/null
# pi: $HOME/.pi/agent/models.json
#   {providers:{"9r":{baseUrl:"http://localhost:20128/v1", api:"openai-completions", apiKey:"NINEROUTER_API_KEY", compat:{supportsDeveloperRole:false, supportsReasoningEffort:false}, models:[{id:"fidt/qwen3.8-flash"},{id:"fidt/kCode"}]}}}
HOME=$S/home-pi pi --no-session --mode json --model 9r/fidt/qwen3.8-flash "<task>" </dev/null
# bench: $S/bench/run.sh <agent> <model> <t1|t2|t3>; $S/bench/grade.sh $S/bench/results/<agent>_<model>_<task>
```
(Script bench/grade nằm trong scratchpad, đồ bỏ.)

## Kết luận
Xếp hạng làm worker cho studio:
1. **opencode**: đạt hết, có hệ thống quyền thật (allow/deny theo tool), TUI chạy tốt trong tmux, nhận tin nhắn qua send-keys, log JSON tốt. Nhược: 355M, bẫy stdin.
2. **goose**: đạt hết, có GOOSE_MODE + chống lặp; chưa thử tương tác tmux.
3. **pi**: đạt hết và chịu kCode chậm tốt nhất, nhưng không có quyền → chỉ dùng khi đã có sandbox ngoài.
4. **codex**: T3 hỏng 3/3 (dừng sớm sau câu dẫn), cần mẹo PATH cho bwrap và Responses API. Không khuyến nghị với model qua 9router.

Khuyến nghị runtime:
- **Role logic (qwen3.8-flash)**: opencode (dự phòng goose). Nhanh (~30-60s/task), ổn định.
- **Role UI (kCode)**: opencode, nhưng timeout task ≥ 10 phút và cho retry, vì upstream kCode có lúc xếp hàng 100-200s/request hoặc 502. Chất lượng không phải vấn đề (T2 đạt 4/4 agent); độ trễ hạ tầng mới là vấn đề.
- Khi tích hợp vào `team`: chạy với `</dev/null` (headless), export `NINEROUTER_API_KEY` vào pane tmux, kiểm tra kết quả bằng script (như grade.sh) thay vì tin lời agent.
