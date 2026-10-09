#!/usr/bin/env python3
"""team ui: serves ui/index.html + /state (JSON built from projects/*/.team and tmux panes). Stdlib only."""
import json, os, re, subprocess, sys, glob
from urllib.parse import parse_qs, urlparse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROOT = os.environ.get("STUDIO_ROOT") or os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
HTML = os.path.join(ROOT, "ui", "index.html")


def live_panes():  # {task id: pane tag} for workers whose pane is still open
    try:
        out = subprocess.run(["tmux", "list-panes", "-a", "-F", "#{@tid} #{@team}"],
                             capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return {}
    return {l.split()[0]: l.split()[1] for l in out.splitlines() if len(l.split()) == 2}


def team_panes():  # {tag: pane id} for every tmux pane tagged @team (the only panes we ever touch)
    try:
        out = subprocess.run(["tmux", "list-panes", "-a", "-F", "#{pane_id} #{@team}"],
                             capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return {}
    return {l.split()[1]: l.split()[0] for l in out.splitlines() if len(l.split()) == 2}


def term(tag, lines=80):
    pane = team_panes().get(tag)
    if not pane:
        return {"tag": tag, "text": None}
    out = subprocess.run(["tmux", "capture-pane", "-p", "-J", "-t", pane, "-S", f"-{lines}"],
                         capture_output=True, text=True, timeout=2).stdout
    return {"tag": tag, "text": out.rstrip()}


def title_of(path):
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("You are acting as"):
                return line[:140]
    except OSError:
        pass
    return ""


def state():
    live, tasks = live_panes(), {}
    for proj_dir in glob.glob(os.path.join(ROOT, "projects", "*", ".team")):
        proj = os.path.basename(os.path.dirname(proj_dir))
        for f in glob.glob(os.path.join(proj_dir, "tasks", "*.md")) + glob.glob(os.path.join(proj_dir, "out", "*.md")):
            tid = os.path.basename(f)[:-3]
            t = tasks.setdefault(tid, {"id": tid, "proj": proj, "title": "", "summary": "", "start": os.path.getmtime(f)})
            t["start"] = min(t["start"], os.path.getmtime(f))
            if "/tasks/" in f:
                t["title"] = title_of(f)
                m = re.search(r"\(role: ([a-z0-9-]+)\)", open(f, encoding="utf-8", errors="replace").readline())
                if m:
                    t["role"] = m.group(1)
                m = re.search(r"\(worker: ([a-z0-9-]+)\)", open(f, encoding="utf-8", errors="replace").readline())
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
        # desk = worker pane (web-dev-2, ...), so parallel --new workers of one role don't share a desk
        t.setdefault("seat", t["worker"][len(t["proj"]) + 1:] if t["worker"] else t["role"])
        t["status"] = "done" if t["end"] else ("working" if t["worker"] else "stale")
    return {"tasks": sorted(tasks.values(), key=lambda t: t["start"]), "live": sorted(set(live.values())), "panes": sorted(team_panes())}


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/state"):
            body, ctype = json.dumps(state()).encode(), "application/json"
        elif self.path.startswith("/term"):
            tag = parse_qs(urlparse(self.path).query).get("tag", [""])[0]
            body, ctype = json.dumps(term(tag)).encode(), "application/json"
        elif self.path in ("/vaultboy.gif", "/helm.png"):   # fixed whitelist, no path traversal
            body, ctype = open(os.path.join(ROOT, "ui", self.path[1:]), "rb").read(), "image/" + self.path.rsplit(".", 1)[1]
        else:
            body, ctype = open(HTML, "rb").read(), "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7777
    print(f"studio office → http://localhost:{port}")
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
