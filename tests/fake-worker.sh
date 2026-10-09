#!/usr/bin/env bash
# Fake worker for tests: handles "Read .team/tasks/<id>.md ..." messages (argv, then stdin lines).
# Writes env + assembled role prompt to .team/out/<id>.md, then <id>.done.
# Task text FAKE_DIE: exit without .done (crash). FAKE_HANG: never finish this task.
do_msg() {
  local id t
  id=$(sed -n 's|.*\.team/tasks/\([^ ]*\)\.md.*|\1|p' <<<"$1"); [ -n "$id" ] || return 0
  t=.team/tasks/$id.md
  grep -q FAKE_DIE "$t" && exit 3
  grep -q FAKE_HANG "$t" && return 0
  { echo "role=$FAKE_ROLE model=$FAKE_MODEL browser=$FAKE_BROWSER"; cat ".team/role-$FAKE_ROLE.md"; } > ".team/out/$id.md"
  touch ".team/out/$id.done"
}
do_msg "$1"
while IFS= read -r line; do do_msg "$line"; done
