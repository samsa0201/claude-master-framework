#!/usr/bin/env python3
"""Tests for ui/serve.py (the `team ui` API). No model, no real tmux server, temp dirs only.
Run: python3 -m unittest tests/ui_api_test.py   (or tests/ui_api_test.py)"""
import http.client, json, os, shutil, subprocess, sys, tempfile, threading, unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ui"))
import serve  # noqa: E402

GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"]


def sh(cwd, *args):
    subprocess.run([*GIT, *args], cwd=cwd, check=True, capture_output=True)


def write(path, text="", mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as f:
        f.write(text)


class UiApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = os.path.realpath(tempfile.mkdtemp())
        cls.patches = [
            mock.patch.dict(os.environ, {"TMUX_TMPDIR": cls.tmp}),   # private tmux socket dir: never the user's server
            mock.patch.object(serve, "PROJ", os.path.join(cls.tmp, "projects")),
            mock.patch.object(serve, "DIST", os.path.join(cls.tmp, "dist")),
        ]
        for p in cls.patches:
            p.start()
        os.environ.pop("TMUX", None)
        sh(cls.tmp, "init", "-q")   # projects/ lives inside a repo, like in studio: git must not walk up into it
        P = serve.PROJ
        # demo: committed README, then edited; plus untracked files of every kind
        d = os.path.join(P, "demo")
        os.makedirs(d)
        sh(d, "init", "-q")
        write(f"{d}/.git/info/exclude", ".team/\n", "a")   # like `team new`
        write(f"{d}/README.md", "one\n")
        sh(d, "add", "."), sh(d, "commit", "-q", "-m", "first commit")
        write(f"{d}/README.md", "one\ntwo\n")
        write(f"{d}/new.txt", "hello new\n")
        write(f"{d}/.env", "SECRET=hunter2\n")
        write(f"{d}/bin.dat", b"\0\1\2", "wb")
        write(f"{d}/big.txt", "x" * (serve.MAX_UNTRACKED_FILE + 1))
        os.symlink("/etc/hostname", f"{d}/link")
        write(f"{d}/docs/prd.md", "# PRD\n")
        write(f"{d}/docs/big.md", "y" * (serve.MAX_DOC + 10))
        write(f"{d}/docs/notes.txt", "not markdown")
        write(f"{cls.tmp}/outside.md", "OUTSIDE-SECRET")
        os.symlink(f"{cls.tmp}/outside.md", f"{d}/docs/leak.md")
        write(f"{d}/.team/auth.json", '{"token": "x"}')
        write(f"{d}/.team/roles/dev.md", "role notes")
        write(f"{d}/.team/tasks/demo-dev-120000.md", "# Task demo-dev-120000 (role: dev) (worker: dev)\nYou are acting as: dev.\nBuild the thing\n")
        write(f"{d}/.team/out/demo-dev-120000.md", "all built\n")
        write(f"{d}/.team/out/demo-dev-120000.done")
        write(f"{d}/.team/tasks/demo-qa-130000.md", "# Task demo-qa-130000 (role: qa) (worker: qa-2)\nYou are acting as: qa.\nVerify it\n")
        # fresh: git repo with no commit yet (right after `team new`)
        write(f"{P}/fresh/a.txt", "fresh file\n"), os.makedirs(f"{P}/fresh/.team"), sh(f"{P}/fresh", "init", "-q")
        # norepo: no .git of its own
        os.makedirs(f"{P}/norepo/.team"), write(f"{P}/norepo/docs/idea.md", "idea")
        os.makedirs(f"{P}/.display")
        # dist: a built SPA
        write(f"{serve.DIST}/index.html", "<!doctype html><title>app</title>")
        write(f"{serve.DIST}/assets/app-1a2b.js", "console.log(1)")
        write(f"{cls.tmp}/secret.txt", "TOP-SECRET")
        cls.srv = serve.make_server(0)
        cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown(), cls.srv.server_close()
        for p in cls.patches:
            p.stop()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def req(self, path, host=None, method="GET"):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        c.request(method, path, headers={"Host": host} if host else {})
        r = c.getresponse()
        body = r.read()
        c.close()
        return r.status, r, body

    def get(self, path, **kw):
        status, r, body = self.req(path, **kw)
        return status, (json.loads(body) if r.getheader("Content-Type", "").startswith("application/json") else body)

    # ── state ──
    def test_state_shape(self):
        status, s = self.get("/api/state")
        self.assertEqual(status, 200)
        self.assertEqual(s["projects"], ["demo", "fresh", "norepo"])
        by = {t["id"]: t for t in s["tasks"]}
        done, stale = by["demo-dev-120000"], by["demo-qa-130000"]
        self.assertEqual((done["status"], done["role"], done["seat"], done["proj"]), ("done", "dev", "dev", "demo"))
        self.assertEqual(done["title"], "Build the thing")
        self.assertEqual(done["summary"], "all built")
        self.assertEqual((stale["status"], stale["seat"]), ("stale", "qa-2"))   # no pane, no .done
        self.assertEqual((s["live"], s["panes"]), ([], []))

    def test_term_unknown_pane(self):
        self.assertEqual(self.get("/api/term?tag=nope")[1], {"tag": "nope", "text": None})

    # ── docs ──
    def test_files_listing_whitelist(self):
        paths = {f["path"] for f in self.get("/api/projects/demo/files")[1]["files"]}
        self.assertEqual(paths, {"docs/prd.md", "docs/big.md", ".team/roles/dev.md",
                                 ".team/tasks/demo-dev-120000.md", ".team/tasks/demo-qa-130000.md", ".team/out/demo-dev-120000.md"})

    def test_read_doc(self):
        status, d = self.get("/api/projects/demo/file?path=docs/prd.md")
        self.assertEqual((status, d["text"], d["truncated"]), (200, "# PRD\n", False))
        self.assertEqual(self.get("/api/projects/demo/file?path=.team/out/demo-dev-120000.md")[1]["text"], "all built\n")

    def test_read_doc_truncates(self):
        d = self.get("/api/projects/demo/file?path=docs/big.md")[1]
        self.assertTrue(d["truncated"])
        self.assertEqual(len(d["text"]), serve.MAX_DOC)

    def test_read_doc_rejects(self):
        for path, want in [
            ("docs/notes.txt", 400), (".team/auth.json", 400), ("", 400), ("docs/prd.md%00.png", 400), ("docs/%00.md", 400),
            ("../../outside.md", 404), ("docs/../../../outside.md", 404), (f"{self.tmp}/outside.md", 404),
            ("docs/leak.md", 404),             # symlink out of docs/
            ("README.md", 404),                # a .md in the repo that is not in a whitelisted dir
            ("docs/missing.md", 404),
        ]:
            with self.subTest(path=path):
                self.assertEqual(self.get("/api/projects/demo/file?path=" + path)[0], want)

    def test_project_name_validation(self):
        for name in ["..", "..%2f..%2fetc", "%2e%2e", ".display", "nope", "demo%2f..%2fdemo", "de%20mo"]:
            with self.subTest(name=name):
                self.assertEqual(self.get(f"/api/projects/{name}/files")[0], 404)

    # ── git ──
    def test_diff_tracked_and_untracked(self):
        status, d = self.get("/api/projects/demo/diff")
        self.assertEqual(status, 200)
        self.assertIn("+two", d["diff"])
        self.assertIn("+++ b/new.txt", d["diff"])
        self.assertIn("+hello new", d["diff"])
        self.assertEqual(d["branch"], "main")
        self.assertTrue(d["head"])
        self.assertFalse(d["truncated"])
        self.assertLessEqual({(".env", "sensitive name"), ("bin.dat", "binary"), ("big.txt", "too large"), ("link", "symlink"),
                              ("docs/leak.md", "symlink")}, {(s["path"], s["reason"]) for s in d["skipped"]})
        self.assertNotIn(".team/auth.json", d["untracked"])   # .team/ is excluded, as in a real project
        self.assertNotIn("hunter2", d["diff"])
        self.assertNotIn("hostname", d["diff"])

    def test_diff_without_commits(self):
        d = self.get("/api/projects/fresh/diff")[1]
        self.assertIsNone(d["head"])
        self.assertIn("+fresh file", d["diff"])

    def test_diff_requires_own_repo(self):   # norepo sits inside the temp studio repo; must not diff that one
        self.assertEqual(self.get("/api/projects/norepo/diff")[0], 404)
        self.assertEqual(self.get("/api/projects/norepo/log")[0], 404)

    def test_diff_truncates(self):
        with mock.patch.object(serve, "MAX_GIT", 60):
            d = self.get("/api/projects/demo/diff")[1]
        self.assertTrue(d["truncated"])

    def test_log_and_commit(self):
        commits = self.get("/api/projects/demo/log")[1]["commits"]
        self.assertEqual([c["subject"] for c in commits], ["first commit"])
        self.assertEqual(self.get("/api/projects/fresh/log")[1], {"commits": []})
        c = self.get(f"/api/projects/demo/commit?sha={commits[0]['sha']}")[1]
        self.assertEqual((c["subject"], c["author"]), ("first commit", "t"))
        self.assertIn("+one", c["diff"])
        self.assertEqual(self.get(f"/api/projects/demo/commit?sha={commits[0]['short']}")[1]["sha"], commits[0]["sha"])

    def test_commit_rejects(self):
        for sha, want in [("", 400), ("HEAD", 400), ("-p", 400), ("zzzzzzz", 400), ("abc", 400), ("0" * 40, 404), ("deadbeef", 404)]:
            with self.subTest(sha=sha):
                self.assertEqual(self.get("/api/projects/demo/commit?sha=" + sha)[0], want)

    # ── static ──
    def test_static_and_spa_fallback(self):
        status, r, body = self.req("/")
        self.assertEqual((status, r.getheader("Content-Type")), (200, "text/html; charset=utf-8"))
        self.assertIn(b"<title>app</title>", body)
        self.assertEqual(self.req("/projects/demo/docs")[2], body)   # client-side route → index.html
        status, r, body = self.req("/assets/app-1a2b.js")
        self.assertEqual((status, body), (200, b"console.log(1)"))
        self.assertTrue(r.getheader("Content-Type").startswith("text/javascript"))
        self.assertIn("immutable", r.getheader("Cache-Control"))
        self.assertEqual(self.req("/assets/missing.js")[0], 404)
        self.assertEqual(self.req("/favicon.ico")[0], 404)

    def test_static_traversal(self):
        for path in ["/..%2fsecret.txt", "/%2e%2e/secret.txt", "/assets/..%2f..%2fsecret.txt", "/..%2f..%2foutside.md", "//etc/hostname"]:
            with self.subTest(path=path):
                body = self.req(path)[2]
                self.assertNotIn(b"SECRET", body.upper())   # a 404 or the index page, never the file outside dist/

    def test_unbuilt_ui(self):
        with mock.patch.object(serve, "DIST", os.path.join(self.tmp, "nodist")):
            status, _, body = self.req("/")
        self.assertEqual(status, 503)
        self.assertIn(b"bun run build", body)

    # ── protocol ──
    def test_host_header(self):
        for host, want in [("localhost:7777", 200), ("127.0.0.1", 200), ("[::1]:80", 200), ("evil.example", 403),
                           ("localhost.evil.example", 403), ("127.0.0.1.evil.example:7777", 403)]:
            with self.subTest(host=host):
                self.assertEqual(self.req("/api/state", host=host)[0], want)
        with mock.patch.object(serve, "HOSTS", serve.HOSTS | {"box.ts.net"}):
            self.assertEqual(self.req("/api/state", host="box.ts.net")[0], 200)

    def test_get_only(self):
        for method in ["POST", "PUT", "DELETE"]:
            with self.subTest(method=method):
                self.assertEqual(self.req("/api/state", method=method)[0], 501)

    def test_headers_and_errors(self):
        _, r, _ = self.req("/api/state")
        self.assertEqual(r.getheader("X-Content-Type-Options"), "nosniff")
        self.assertIn("default-src 'self'", r.getheader("Content-Security-Policy"))
        self.assertEqual(self.get("/api/nope"), (404, {"error": "no such endpoint"}))
        self.assertEqual(self.get("/api/projects/demo/zzz")[0], 404)


if __name__ == "__main__":
    unittest.main()
