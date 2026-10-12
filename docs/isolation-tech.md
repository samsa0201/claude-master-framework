# Cô lập project: vấn đề, công nghệ ứng viên, kế hoạch POC

Trạng thái: **đã chọn Docker box mỗi project + firewall iptables trong netns + Tailscale sidecar** (2026-10-12), sau spike trên máy thật. Thiết kế và kết quả spike: [specs/2026-10-12-project-box-design.md](superpowers/specs/2026-10-12-project-box-design.md). Phần dưới giữ làm bối cảnh research; các lệnh POC ở mục 5 là bản nháp ban đầu.

Quy trình đã thống nhất cho từng phần: **plan → POC → chọn → triển khai**; chỉ triển khai sau khi người dùng duyệt.

## 1. Vấn đề (đã chốt)

Scope cô lập là **project**. Hiện chỉ cô lập code (mỗi project một repo/worktree), và chỉ theo quy ước.

| # | Vấn đề | Hậu quả |
|---|---|---|
| P1 | Port: mọi project dùng chung network của host | Hai project cùng chạy 5173/3000 thì va chạm; Vite tự nhảy port nên QA có thể test nhầm app; worker không biết port của mình |
| P2 | Process: dev server/DB còn sống sau khi worker chết | Giữ port, tốn tài nguyên, va chạm lần sau |
| P3 | Filesystem: worker chạy cùng user, không bị chặn | Đọc được `~/.ssh`, ghi được project khác. Quyền của opencode chỉ là allowlist agent tự tuân thủ (README: "MVP chưa có sandbox") |
| P4 | Truy cập từ Mac: mỗi port phải `ssh -L` tay | Port đổi thì gõ lại, nhiều project thì lệnh dài |
| P5 | Secure context cho PWA | `http://<host>:port` không phải secure context (service worker, push, camera không chạy); `ssh -L` thì vẫn là `localhost` nên chạy được |
| P6 | Dịch vụ phụ (Postgres, redis, compose) | Trùng tên container, port, data dir giữa các project |

## 2. Hợp đồng chung (giữ nguyên ở mọi mức)

Port đến từ env (`PORT_*`, `COMPOSE_PROJECT_NAME`), worker không hardcode. Bên dưới có thể nâng từ quy ước mềm lên cô lập thật mà không phải sửa prompt hay flex file. Cấu hình dự kiến: `sandbox: none | bwrap | srt | sysbox | ...` và `access: ssh | tailscale | serve`.

**Nguyên tắc fail-closed:** nếu cấu hình yêu cầu sandbox mà không dựng được thì dừng và báo lỗi, không lặng lẽ hạ xuống chạy không sandbox (học từ các dự án thử backend lần lượt `firecracker → gvisor → bwrap → namespace` rồi báo lỗi thay vì chạy trần).

## 3. Công nghệ ứng viên

| Công nghệ | P1 | P2 | P3 | P4/P5 | P6 | Chi phí / rủi ro |
|---|---|---|---|---|---|---|
| **A. Port block theo project** (đã làm, mềm) | quy ước | kill theo cwd | – | in sẵn `ssh -L` | `COMPOSE_PROJECT_NAME` | Thấp, không cần root |
| **B. bubblewrap (bwrap)** | – | pid ns | ép thật | – | – | Cần user namespace; Ubuntu ≥ 24.04 cần xử lý AppArmor |
| **B'. Anthropic sandbox-runtime (srt)** | ? | pid ns | ép thật + deny-list | – | – | Beta; bwrap + seccomp + proxy lọc domain; **gỡ hẳn netns** nên chưa rõ dev server có listen/truy cập được không |
| **B''. Landlock** | – | – | ép thật (LSM) | – | – | Không cần root, không cần user namespace; không có pid/net ns |
| **C. netns riêng (`unshare --net` + `pasta`)** | ép thật | có | – | cần publish port | một phần | Không cần root nếu dùng `pasta` |
| **C'. Podman rootless (pasta mặc định từ Podman 5)** | ép thật | có | có (mount) | cần publish | có | Không cần root; hạn chế: container↔container qua IP host, port < 1024 |
| **D. Sysbox** (container/project) | ép thật | có | có | cần publish | compose chạy được bên trong | Cần root + Docker; bảo trì mong manh (xem 4.1) |
| **D'. Incus** (system container) | ép thật | có | có | cần publish | Docker chạy được bên trong | Cần cài Incus; chưa đánh giá kỹ |
| **E. Tailscale `host:port`** | – | – | – | không cần `ssh -L`; HTTP thường (P5 vẫn lỗi) | – | App phải bind đúng địa chỉ |
| **F. `tailscale serve`** | – | – | – | HTTPS thật (giải quyết P5) | – | Cần MagicDNS + HTTPS cert; 1 tên/node |
| **G. Tailscale Services** (beta từ 10/2025) | – | – | – | tên MagicDNS riêng mỗi service | – | Chưa xác minh gói/điều kiện/trạng thái |
| **H. gVisor / Firecracker (microVM)** | ép thật | có | có | – | có | Nặng (khởi động, RAM); Firecracker cần KVM; nhiều khả năng quá mức cần thiết |

## 4. Kết quả research

### 4.1 Sysbox: còn hoạt động nhưng mong manh
- Danh sách release có v0.7.1 là bản mới nhất; repo cập nhật 4/3/2026.
- Issue mở: Sysbox 0.7.0 **không chạy trên Ubuntu 26.04** (mở 27/4/2026); nhiều issue về Kubernetes/containerd 2.x.
- Có issue "State of the project" hỏi về việc bảo trì; Sysbox-EE đã bị archived tháng 8/2025.
- Kết luận: chỉ dùng nếu distro/kernel của máy nằm trong vùng bản hiện tại chạy tốt. Không coi là nền tảng chính.

### 4.2 Anthropic sandbox-runtime (srt)
- Mã nguồn mở Apache-2.0, beta research preview, cài từ npm `@anthropic-ai/sandbox-runtime`. Linux: **bwrap + seccomp BPF + proxy HTTP/SOCKS5 lọc domain**. Cấu hình JSON: `filesystem.{denyRead,allowRead,allowWrite,denyWrite}`, `network.{allowedDomains,deniedDomains}`; mặc định chặn ghi vào `.git/hooks/`, `.bashrc`, `.mcp.json`...
- Chạy: `srt --settings ./srt-settings.json <command>`.
- Yêu cầu: bubblewrap ≥ 0.4.0 (khuyến nghị ≥ 0.5.0), `socat`, `ripgrep`, user namespace không đặc quyền.
- **Network namespace bị gỡ hẳn**, mọi traffic đi qua proxy bằng Unix socket (bind-mount vào sandbox). Docs không nói rõ process trong sandbox có `listen` rồi được truy cập từ ngoài không → **câu hỏi POC số một** (ảnh hưởng dev server + browser QA).
- Seccomp chặn tạo Unix socket (`allowAllUnixSockets` để tắt); `allowUnixSockets` theo path bị bỏ qua trên Linux.
- Giới hạn khác: glob hẹp ở `allowWrite`; file mount rỗng có thể sót lại nếu process bị SIGKILL.

### 4.3 AppArmor + bwrap (Ubuntu 24.04+)
- `kernel.apparmor_restrict_unprivileged_userns` mặc định bật, bwrap lỗi kiểu `setting up uid map: Permission denied` / `loopback: Failed RTM_NEWADDR`.
- Cách ưu tiên: nạp **profile AppArmor cấp `userns` cho đúng binary bwrap** (gói `apparmor-profiles` có profile mẫu; profile theo đường dẫn chỉ khớp khi bwrap ở vị trí cố định). Cách cuối cùng: `sysctl kernel.apparmor_restrict_unprivileged_userns=0` (Canonical khuyên tránh vì mở lại bề mặt khai thác kernel).
- README của repo ghi "AppArmor trên máy này chặn sandbox của Chromium": rất có thể cùng cơ chế (chưa kiểm chứng).

### 4.4 Hệ sinh thái sandbox cho coding agent
- Landlock là backend mặc định của Codex CLI trên Linux; bwrap là backend của srt và Flatpak; gVisor và Firecracker dùng cho sandbox được host (E2B, Modal...).
- Tuyển tập để duyệt thêm: gist "List of coding agent sandboxes 2026-05", `awesome-ai-coding-sandboxes` (xếp hạng theo isolation/egress/secrets), `awesome-AI-sandbox`.
- Mặc định của sandbox tích hợp trong các agent thường lỏng (đọc được gần hết máy, kế thừa env): cần cấu hình deny-list rõ ràng.

### 4.5 pasta / passt (Mức 3 không cần root)
- Backend mạng mặc định của Podman rootless từ 5.0; chuyển tiếp port không cần root, hỗ trợ IPv4/IPv6.
- Hạn chế: kết nối container↔container qua IP của host không chạy nếu không cấu hình thêm; port < 1024 cần sysctl `net.ipv4.ip_unprivileged_port_start`; chuyển tiếp giữ IP nguồn qua `rootless_port_forwarder = "pasta"` còn thử nghiệm.

### 4.6 Incus
- System container giống VM, chạy Docker bên trong được, "unprivileged by design" theo docs. Chưa so sánh trực tiếp được với Sysbox và chưa rõ chi tiết rootless.

### 4.7 Tailscale (chưa xác minh đầy đủ)
- `tailscale serve`: một tên MagicDNS cho mỗi node + chứng chỉ TLS tự động; muốn nhiều project phải khác port hoặc path trên cùng host. MagicDNS và HTTPS cert phải bật (mặc định bật cho tailnet mới).
- **Tailscale Services** (beta, 10/2025): mỗi service có tên MagicDNS và IP ảo riêng, ví dụ `svc:webapp` ánh xạ về endpoint cục bộ → có thể có hostname riêng mỗi project mà không cần sidecar mỗi project. Trang chính bị lỗi tải khi research, nên **trạng thái beta, gói áp dụng và cách phối hợp với `tailscale serve` chưa được xác minh**.
- Nếu chạy trong container/netns riêng: có thể gắn sidecar tailscale mỗi project để có hostname riêng và dùng port chuẩn (đổi lại mỗi project là một thiết bị tailnet, cần auth key).

## 5. Kế hoạch POC (chưa chạy)

Các lệnh dưới đây **chưa được chạy thử** (viết từ docs, có thể cần chỉnh). Chạy trên **máy Linux thật** (container cloud của phiên làm việc có kernel/AppArmor khác nên không đại diện). Các bước 1–2 chỉ đọc hoặc chạy trong thư mục tạm.

**POC-0: điều kiện máy** (chỉ đọc)
```bash
uname -r; cat /etc/os-release | head -3
command -v bwrap && bwrap --version
command -v socat rg podman docker incus pasta passt
unshare -Ur true && echo "userns OK" || echo "userns BLOCKED"
sysctl kernel.apparmor_restrict_unprivileged_userns 2>/dev/null
sudo -n true 2>&1 | head -1
tailscale version; tailscale status --self 2>/dev/null | head -2
```

**POC-1: bwrap thuần.** Mục tiêu: ghi được trong một thư mục project, **không ghi được ra ngoài**, không thấy `~/.ssh`, `--unshare-pid` hoạt động.
```bash
mkdir -p /tmp/poc-proj && cd /tmp/poc-proj
bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /home --bind "$PWD" "$PWD" \
      --unshare-pid --die-with-parent \
      bash -c 'echo ok > poc.txt && ls ~/.ssh 2>&1 | head -1; touch /etc/x 2>&1 | head -1; ps aux | wc -l'
```
Đạt nếu: `poc.txt` được tạo; `~/.ssh` không thấy; ghi `/etc/x` bị từ chối; `ps` chỉ thấy vài process.

**POC-2: srt.** Câu hỏi quyết định: dev server trong sandbox có `listen` và truy cập được từ ngoài / từ một process khác trong cùng sandbox không?
```bash
npm i -g @anthropic-ai/sandbox-runtime   # hoặc npx
cat > /tmp/srt.json <<'J'
{"network":{"allowedDomains":["localhost"]},
 "filesystem":{"denyRead":["~/.ssh"],"allowWrite":["."]}}
J
srt --settings /tmp/srt.json 'python3 -m http.server 20999 & sleep 1; curl -sI localhost:20999 | head -1'
curl -sI localhost:20999 | head -1   # chạy ngoài sandbox: có tới được không?
```

**POC-3: pasta + netns.** Mục tiêu: netns riêng, forward một port ra host không cần root.
```bash
pasta --config-net -t 20998:8080 -- python3 -m http.server 8080 &
sleep 1; curl -sI localhost:20998 | head -1
```

**POC-4: opencode trong sandbox.** Chạy một task nhỏ qua `team assign` với lệnh worker bọc trong sandbox đã chọn từ POC-1/2; kiểm tra worker hoàn thành, ra được 9router (`$NINEROUTER_URL`), ghi `.team/out/<id>.md`.

**POC-5: Chromium QA trong/ngoài sandbox.** Xem Playwright MCP vẫn lên được Xvfb chung và tới được app.

**POC-6: Tailscale.** `tailscale serve --https=443 localhost:<PORT_WEB>` rồi mở `https://<máy>.<tailnet>.ts.net` từ Mac; đọc docs Tailscale Services hiện hành và thử nếu tailnet cho phép.

**POC-7 (chỉ khi POC-0 có Docker + root + distro phù hợp): Sysbox / Incus.**

### Tiêu chí đạt (tổng)
Worker ghi được trong project của nó, không ghi được ra ngoài, không đọc được `~/.ssh`, hoàn thành task qua 9router, dev server của project truy cập được từ browser QA, và dừng sandbox thì không còn process con giữ port.

## 6. Câu hỏi còn mở
1. Máy Linux: OS/kernel, `sudo`, Docker/Podman, AppArmor ra sao (kết quả POC-0).
2. App của người dùng: có `docker compose` (DB, redis) không; có PWA/API cần secure context không; có OAuth callback `localhost:port` không.
3. Tailnet: đã bật MagicDNS + HTTPS cert chưa; cấp được auth key cho sidecar không.
4. Số project chạy song song thường là bao nhiêu (từ 3 trở lên thì cô lập network thật đáng làm sớm).

## Nguồn
- Sysbox: [State of the project #979](https://github.com/nestybox/sysbox/issues/979), [releases](https://github.com/nestybox/sysbox/releases), [issues](https://github.com/nestybox/sysbox/issues), [Sysbox-EE (archived)](https://github.com/docker-archive/nestybox.sysbox-ee)
- srt: [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
- Tổng hợp sandbox: [coding agent sandboxes 2026-05](https://gist.github.com/wincent/2752d8d97727577050c043e4ff9e386e), [awesome-ai-coding-sandboxes](https://github.com/fhiltscher/awesome-ai-coding-sandboxes), [awesome-AI-sandbox](https://github.com/webcoyote/awesome-AI-sandbox), [How to Choose an AI Agent Sandbox (2026)](https://cosmonic.com/ai-sandbox/choosing-an-agent-sandbox/)
- AppArmor + bwrap: [Understanding AppArmor User Namespace Restriction](https://discourse.ubuntu.com/t/understanding-apparmor-user-namespace-restriction/58007), [Ubuntu 24.04 and Bubblewrap](https://etbe.coker.com.au/2024/04/24/ubuntu-24-04-bubblewrap/)
- pasta/Podman: [podman-rootless(7)](https://www.mankier.com/7/podman-rootless), [rootless port forwarding](https://oneuptime.com/blog/post/2026-03-17-configure-port-forwarding-rootless-podman/markdown)
- Incus: [containers and VMs](https://linuxcontainers.org/incus/docs/main/explanation/containers_and_vms)
- Tailscale: [share a local dev server](https://tailscale.com/docs/use-cases/application-testing/share-local-dev-server-with-team), [Services beta](https://tailscale.com/blog/services-beta)
