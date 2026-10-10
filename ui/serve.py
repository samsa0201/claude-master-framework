#!/usr/bin/env python3
"""team ui: read-only JSON API over projects/*/.team, tmux panes and git, plus the built SPA from ui/dist. Stdlib only.
Project files are written by worker models and the browser is the only caller, so: GET only, URL input is validated,
git runs hardened, and the Host header must be local (DNS rebinding could otherwise read diffs from any web page)."""
import glob, json, mimetypes, os, re, subprocess, sys
from urllib.parse import parse_qs, unquote, urlparse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROOT = os.environ.get("STUDIO_ROOT") or os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
PROJ = os.environ.get("TEAM_PROJECTS") or os.path.join(ROOT, "projects")   # same override as bin/team
DIST = os.path.join(ROOT, "ui", "dist")
HOSTS = {"localhost", "127.0.0.1", "::1"} | {h for h in os.environ.get("TEAM_UI_HOSTS", "").split(",") if h}

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")   # a project dir name; never contains a slash or starts with a dot
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
DOC_DIRS = ("docs", ".team/roles", ".team/tasks", ".team/out", ".team/logs")   # the only places a .md can be read from
MAX_DOC = 512 * 1024        # bytes of one document
MAX_GIT = 1024 * 1024       # bytes of one git response
MAX_UNTRACKED = 50          # untracked files shown as "new file" diffs
MAX_UNTRACKED_FILE = 100 * 1024
MAX_FILES = 500
GIT_TIMEOUT = 5
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"   # repos without a commit yet diff against this
SENSITIVE = re.compile(r"(^\.env|\.pem$|\.key$|^id_(rsa|ed25519)|^auth\.json$)")

mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("text/javascript", ".mjs")


class ApiError(Exception):
    def __init__(self, status, msg):
        super().__init__(msg)
        self.status, self.msg = status, msg


# ── tmux ──
def tmux(fmt):
    try:
        return subprocess.run(["tmux", "list-panes", "-a", "-F", fmt], capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return ""


def live_panes():  # {task id: pane tag} for workers whose pane is still open
    return {l.split()[0]: l.split()[1] for l in tmux("#{@tid} #{@team}").splitlines() if len(l.split()) == 2}


def team_panes():  # {tag: pane id} for every tmux pane tagged @team (the only panes we ever touch)
    return {l.split()[1]: l.split()[0] for l in tmux("#{pane_id} #{@team}").splitlines() if len(l.split()) == 2}


def term(tag, lines=80):
    pane = team_panes().get(tag)
    if not pane:
        return {"tag": tag, "text": None}
    try:
        out = subprocess.run(["tmux", "capture-pane", "-p", "-J", "-t", pane, "-S", f"-{lines}"],
                             capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return {"tag": tag, "text": None}
    return {"tag": tag, "text": out.rstrip()}


# ── tasks ──
def read_verify(path):  # .team/out/<id>.verify written by `team wait`: "<ok|warn|fail>\t<summary>" then detail lines
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            raw = f.read(4096)
    except OSError:
        return None
    head, _, details = raw.partition("\n")
    status, _, summary = head.partition("\t")
    return {"status": status, "summary": summary, "details": details.strip()} if status in ("ok", "warn", "fail") else None


def title_of(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and not line.startswith("You are acting as"):
                    return line[:140]
    except OSError:
        pass
    return ""


def state():
    live, tasks = live_panes(), {}
    team_dirs = glob.glob(os.path.join(glob.escape(PROJ), "*", ".team"))
    for proj_dir in team_dirs:
        proj = os.path.basename(os.path.dirname(proj_dir))
        for f in glob.glob(os.path.join(glob.escape(proj_dir), "tasks", "*.md")) + glob.glob(os.path.join(glob.escape(proj_dir), "out", "*.md")):
            tid = os.path.basename(f)[:-3]
            t = tasks.setdefault(tid, {"id": tid, "proj": proj, "title": "", "summary": "", "start": os.path.getmtime(f)})
            t["start"] = min(t["start"], os.path.getmtime(f))
            if os.sep + "tasks" + os.sep in f:
                t["title"] = title_of(f)
                with open(f, encoding="utf-8", errors="replace") as fh:
                    head = fh.readline()
                m = re.search(r"\(role: ([a-z0-9-]+)\)", head)
                if m:
                    t["role"] = m.group(1)
                m = re.search(r"\(worker: ([a-z0-9-]+)\)", head)
                if m:
                    t["seat"] = m.group(1)
            else:
                t["summary"] = title_of(f)
            done = os.path.join(proj_dir, "out", tid + ".done")
            t["end"] = os.path.getmtime(done) if os.path.exists(done) else None
    for t in tasks.values():
        if "role" not in t:  # no task file left: id = <proj>-<role>-HHMMSS, proj may contain dashes
            rest = t["id"][len(t["proj"]) + 1:] if t["id"].startswith(t["proj"] + "-") else t["id"].rsplit("-", 2)[-2]
            t["role"] = rest.rsplit("-", 1)[0] if "-" in rest else rest
        t["worker"] = live.get(t["id"])
        # desk = worker pane (web-dev-2, ...), so parallel --new workers of one role don't share a seat
        t.setdefault("seat", t["worker"][len(t["proj"]) + 1:] if t["worker"] else t["role"])
        t["status"] = "done" if t["end"] else ("working" if t["worker"] else "stale")
        team_dir = os.path.join(PROJ, t["proj"], ".team")
        t["verify"] = read_verify(os.path.join(team_dir, "out", t["id"] + ".verify"))
        t["log"] = os.path.exists(os.path.join(team_dir, "logs", t["id"] + ".md"))   # saved screen of the worker pane
    projects = sorted(os.path.basename(os.path.dirname(d)) for d in team_dirs)
    return {"tasks": sorted(tasks.values(), key=lambda t: t["start"]), "live": sorted(set(live.values())),
            "panes": sorted(team_panes()), "projects": projects}


# ── project files ──
def project_dir(name):
    if not NAME_RE.match(name or "") or not os.path.isdir(os.path.join(PROJ, name)):
        raise ApiError(404, "no such project")
    return os.path.join(PROJ, name)


def doc_roots(pd):  # [(group, real dir)]
    real = os.path.realpath(pd)
    return [(d, os.path.realpath(os.path.join(real, d))) for d in DOC_DIRS]


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def within(path, root):
    return path.startswith(root + os.sep)


def list_docs(pd):
    real, out = os.path.realpath(pd), []
    for group, root in doc_roots(pd):
        for dp, dns, fns in os.walk(root):   # followlinks=False
            dns[:] = [d for d in dns if not d.startswith(".")]
            if dp[len(root):].count(os.sep) >= 3:
                dns[:] = []
            for fn in fns:
                full = os.path.join(dp, fn)
                if not fn.endswith(".md") or not within(os.path.realpath(full), root) or not os.path.isfile(full):
                    continue
                st = os.stat(full)
                out.append({"path": os.path.relpath(full, real), "group": group, "name": fn, "size": st.st_size, "mtime": st.st_mtime})
                if len(out) >= MAX_FILES:
                    return out
    return out


def read_doc(pd, rel):
    if not rel or "\0" in rel or not rel.endswith(".md"):
        raise ApiError(400, "path must be a .md file")
    full = os.path.realpath(os.path.join(os.path.realpath(pd), rel))
    if not any(within(full, root) for _, root in doc_roots(pd)) or not os.path.isfile(full):
        raise ApiError(404, "no such document")
    with open(full, "rb") as f:
        raw = f.read(MAX_DOC + 1)
    return {"path": rel, "text": raw[:MAX_DOC].decode("utf-8", "replace"), "truncated": len(raw) > MAX_DOC, "mtime": os.path.getmtime(full)}


# ── git ──
def git(pd, *args, ok=(0,)):  # → (text, truncated). Hardened: no repo-configured fsmonitor, pager, prompts or index locks.
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0")
    try:
        r = subprocess.run(["git", "-C", pd, "-c", "core.fsmonitor=false", "-c", "core.quotepath=off", "--no-pager", *args],
                           capture_output=True, timeout=GIT_TIMEOUT, env=env)
    except subprocess.TimeoutExpired:
        raise ApiError(504, "git timed out")
    except OSError:
        raise ApiError(500, "git not available")
    if r.returncode not in ok:
        raise ApiError(500, "git failed: " + r.stderr.decode("utf-8", "replace").strip()[:200])
    return r.stdout[:MAX_GIT].decode("utf-8", "replace"), len(r.stdout) > MAX_GIT


def repo_dir(name):
    pd = project_dir(name)
    if not os.path.exists(os.path.join(pd, ".git")):   # without this git would walk up into the studio repo itself
        raise ApiError(404, "project is not a git repo")
    return pd


def head_of(pd):
    out, _ = git(pd, "rev-parse", "--verify", "-q", "HEAD", ok=(0, 1))
    return out.strip() or None


DIFF_FLAGS = ("--no-ext-diff", "--no-textconv", "--no-color")


def diff(name):  # uncommitted work: tracked changes vs HEAD + untracked files shown as new-file diffs
    pd = repo_dir(name)
    head = head_of(pd)
    text, truncated = git(pd, "diff", *DIFF_FLAGS, head or EMPTY_TREE)
    names, _ = git(pd, "ls-files", "--others", "--exclude-standard", "-z")
    untracked = [n for n in names.split("\0") if n]
    skipped, parts, size = [], [text], len(text)
    for n in untracked[:MAX_UNTRACKED]:
        full = os.path.join(pd, n)
        try:
            st = os.lstat(full)
            reason = ("symlink" if os.path.islink(full) else "sensitive name" if SENSITIVE.search(os.path.basename(n))
                      else "too large" if st.st_size > MAX_UNTRACKED_FILE else None)
            if not reason:
                with open(full, "rb") as f:
                    reason = "binary" if b"\0" in f.read(8000) else None
        except OSError:
            reason = "unreadable"
        if reason:
            skipped.append({"path": n, "reason": reason})
            continue
        if size >= MAX_GIT:
            truncated = True
            break
        part, _ = git(pd, "diff", "--no-index", *DIFF_FLAGS, "--", "/dev/null", n, ok=(0, 1))
        parts.append(part)
        size += len(part)
    if len(untracked) > MAX_UNTRACKED:
        truncated = True
    branch, _ = git(pd, "symbolic-ref", "--short", "-q", "HEAD", ok=(0, 1))
    return {"diff": "".join(parts), "untracked": untracked, "skipped": skipped, "truncated": truncated,
            "head": head, "branch": branch.strip() or None}


def log(name):
    pd = repo_dir(name)
    if not head_of(pd):
        return {"commits": []}
    out, _ = git(pd, "log", "-n", "30", "--format=%H%x1f%an%x1f%at%x1f%s")
    commits = []
    for line in out.splitlines():
        sha, author, at, subject = (line.split("\x1f") + ["", "", "", ""])[:4]
        commits.append({"sha": sha, "short": sha[:7], "author": author, "time": int(at or 0), "subject": subject})
    return {"commits": commits}


def commit(name, sha):
    pd = repo_dir(name)
    if not SHA_RE.match(sha or ""):
        raise ApiError(400, "bad sha")
    out, _ = git(pd, "rev-parse", "--verify", "-q", sha + "^{commit}", ok=(0, 1))
    if not out.strip():
        raise ApiError(404, "no such commit")
    meta, _ = git(pd, "log", "-1", "--format=%H%x1f%an%x1f%at%x1f%s%x1f%b", sha)
    full, author, at, subject, body = (meta.rstrip("\n").split("\x1f", 4) + ["", "", "", "", ""])[:5]
    text, truncated = git(pd, "show", "--format=", "--patch", *DIFF_FLAGS, sha)
    return {"sha": full, "author": author, "time": int(at or 0), "subject": subject, "body": body.strip(),
            "diff": text, "truncated": truncated}


# ── http ──
def api(path, q):
    one = lambda k: q.get(k, [""])[0]
    if path == "/api/state":
        return state()
    if path == "/api/term":
        return term(one("tag"))
    m = re.fullmatch(r"/api/projects/([^/]+)/(files|file|diff|log|commit)", path)
    if not m:
        raise ApiError(404, "no such endpoint")
    name, what = unquote(m.group(1)), m.group(2)
    if what == "files":
        return {"files": list_docs(project_dir(name))}
    if what == "file":
        return read_doc(project_dir(name), one("path"))
    if what == "commit":
        return commit(name, one("sha"))
    return diff(name) if what == "diff" else log(name)


def host_ok(host):
    try:
        return (urlparse("//" + (host or "")).hostname or "") in HOSTS
    except ValueError:
        return False


class H(BaseHTTPRequestHandler):
    def send(self, status, body, ctype, cache="no-store"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status, obj):
        self.send(status, json.dumps(obj).encode(), "application/json")

    def do_GET(self):
        u = urlparse(self.path)
        try:
            if not host_ok(self.headers.get("Host")):
                raise ApiError(403, "forbidden host (set TEAM_UI_HOSTS to allow more)")
            if u.path.startswith("/api/"):
                return self.send_json(200, api(u.path, parse_qs(u.query)))
            self.static(unquote(u.path))
        except ApiError as e:
            self.send_json(e.status, {"error": e.msg})
        except Exception as e:   # a broken project must not kill the server or leak a traceback
            self.send_json(500, {"error": type(e).__name__})

    def static(self, path):
        real = os.path.realpath(DIST)
        full = os.path.realpath(os.path.join(real, path.lstrip("/")))
        if os.path.isfile(full) and within(full, real):
            ctype = mimetypes.guess_type(full)[0] or "application/octet-stream"
            if ctype.startswith("text/"):
                ctype += "; charset=utf-8"
            # vite hashes everything in /assets, so those files never change under the same name
            cache = "public, max-age=31536000, immutable" if path.startswith("/assets/") else "no-store"
            return self.send(200, read_bytes(full), ctype, cache)
        index = os.path.join(real, "index.html")
        if "." in path.rsplit("/", 1)[-1] or path.startswith("/assets/"):   # a missing file, not an SPA route
            return self.send(404, b"not found", "text/plain; charset=utf-8")
        if not os.path.isfile(index):
            return self.send(503, b"ui not built: cd ui/web && bun install && bun run build", "text/plain; charset=utf-8")
        self.send(200, read_bytes(index), "text/html; charset=utf-8")

    def log_message(self, *a):
        pass


def make_server(port=7777):
    return ThreadingHTTPServer(("127.0.0.1", port), H)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7777
    print(f"studio dashboard → http://localhost:{port}")
    make_server(port).serve_forever()
