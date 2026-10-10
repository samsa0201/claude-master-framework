import { expect, test } from 'bun:test'
import { parseDiff, totals } from './diff'

const MODIFIED = `diff --git a/src/api.ts b/src/api.ts
index 111..222 100644
--- a/src/api.ts
+++ b/src/api.ts
@@ -1,4 +1,5 @@
 one
-two
+TWO
+two-b
 three
@@ -20,2 +21,2 @@ function x() {
 ctx
-old
+new
`

test('modified file: statuses, counts, line numbers across hunks', () => {
  const [f] = parseDiff(MODIFIED)
  expect(f).toMatchObject({ path: 'src/api.ts', oldPath: null, status: 'modified', adds: 3, dels: 2, lineCount: 8 })
  expect(f!.hunks).toHaveLength(2)
  expect(f!.hunks[0]!.lines.map((l) => [l.kind, l.oldNo, l.newNo])).toEqual([
    ['ctx', 1, 1], ['del', 2, null], ['add', null, 2], ['add', null, 3], ['ctx', 3, 4],
  ])
  expect(f!.hunks[1]!.header).toContain('function x()')
  expect(f!.hunks[1]!.lines[0]).toMatchObject({ kind: 'ctx', oldNo: 20, newNo: 21 })
})

test('added, deleted, renamed and binary files', () => {
  const text = `diff --git a/new.txt b/new.txt
new file mode 100644
index 0000000..e69de29
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+a
+b
diff --git a/gone.txt b/gone.txt
deleted file mode 100644
--- a/gone.txt
+++ /dev/null
@@ -1 +0,0 @@
-bye
diff --git a/old name.md b/new name.md
similarity index 90%
rename from old name.md
rename to new name.md
--- a/old name.md
+++ b/new name.md
@@ -1 +1 @@
-x
+y
diff --git a/logo.png b/logo.png
new file mode 100644
Binary files /dev/null and b/logo.png differ
`
  const fs = parseDiff(text)
  expect(fs.map((f) => [f.path, f.status])).toEqual([
    ['new.txt', 'added'], ['gone.txt', 'deleted'], ['new name.md', 'renamed'], ['logo.png', 'binary'],
  ])
  expect(fs[2]!.oldPath).toBe('old name.md')
  expect(fs[0]).toMatchObject({ adds: 2, dels: 0 })
  expect(fs[1]).toMatchObject({ adds: 0, dels: 1 })
  // a binary file shows as binary even when it is new
  expect(parseDiff('diff --git a/x.bin b/x.bin\nBinary files a/x.bin and b/x.bin differ\n')[0]).toMatchObject({ status: 'binary', hunks: [] })
  expect(totals(fs)).toEqual({ files: 4, adds: 3, dels: 2 })
})

test('path comes from +++ when the name has spaces', () => {
  const [f] = parseDiff('diff --git a/my file.txt b/my file.txt\n--- a/my file.txt\n+++ b/my file.txt\n@@ -1 +1 @@\n-a\n+b\n')
  expect(f!.path).toBe('my file.txt')
})

test('"No newline" marker is a meta line, not a change', () => {
  const [f] = parseDiff('diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-x\n\\ No newline at end of file\n+y\n\\ No newline at end of file\n')
  expect(f).toMatchObject({ adds: 1, dels: 1 })
  expect(f!.hunks[0]!.lines.map((l) => l.kind)).toEqual(['del', 'meta', 'add', 'meta'])
})

test('lines starting with ---/+++ inside a hunk are content, not headers', () => {
  const [f] = parseDiff('diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1,2 +1,2 @@\n--- not a header\n+++ also content\n')
  expect(f).toMatchObject({ path: 'a', adds: 1, dels: 1 })
})

test('empty or non-diff input yields no files; git show metadata before the first diff is ignored', () => {
  expect(parseDiff('')).toEqual([])
  expect(parseDiff('commit abc\nAuthor: x\n\n    message\n')).toEqual([])
  expect(parseDiff('commit abc\n\ndiff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-1\n+2\n')).toHaveLength(1)
})
