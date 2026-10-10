# Task contract + verification, sourced by bin/team.
# A worker's ".done" is only its own claim. These turn it into facts the lead can act on:
#   at assign   write_contract: .team/out/<id>.contract (role, allowed files, done command) and <id>.base (working-tree snapshot)
#   on done     verify_task:    compare the tree with the snapshot, run the done command, write .team/out/<id>.verify
#   on stuck    screen_log:     keep what the pane showed as .team/logs/<id>.md (the pane may be closed later)
# Everything here only reads the project (git runs read-only; the done command is the one thing that executes project code).

SNAP_MAX=${TEAM_SNAP_MAX:-5000}   # more changed+untracked files than this: skip the comparison (a missing .gitignore, not a task)
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904

plural() { [ "$1" = 1 ] || echo s; }   # always exits 0: safe inside $(...) under set -e
rgit() { GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false "$@"; }   # read-only: never take index.lock, which a worker running "git add" in the same tree could trip over
cget() { awk -F'\t' -v k="$2" '$1==k {print substr($0, length(k)+2); exit}' "$1" 2>/dev/null || true; }   # <file> <key>

snap() {   # <dir>: "HEAD<TAB>sha", then "<content hash|deleted|other><TAB><path>" for each file that differs from HEAD (staged or not) or is untracked and not ignored
  local d=$1 f base tmp; tmp=$(mktemp -d); : > "$tmp/here"
  base=$(rgit -C "$d" rev-parse -q --verify HEAD 2>/dev/null || true)
  printf 'HEAD\t%s\n' "${base:-none}"
  { rgit -C "$d" diff --name-only --no-renames -z "${base:-$EMPTY_TREE}"; rgit -C "$d" ls-files -z -o --exclude-standard; } | tr '\0' '\n' | sort -u > "$tmp/all"
  if [ "$(wc -l < "$tmp/all")" -gt "$SNAP_MAX" ]; then printf 'TOOMANY\t%s\n' "$(wc -l < "$tmp/all")"; rm -rf "$tmp"; return 0; fi
  while IFS= read -r f; do
    if [ -f "$d/$f" ]; then echo "$f" >> "$tmp/here"
    elif [ -e "$d/$f" ] || [ -L "$d/$f" ]; then printf 'other\t%s\n' "$f"
    else printf 'deleted\t%s\n' "$f"; fi
  done < "$tmp/all"
  if [ -s "$tmp/here" ]; then rgit -C "$d" hash-object --stdin-paths < "$tmp/here" | paste - "$tmp/here"; fi   # hashes only: nothing is written to the repo
  rm -rf "$tmp"
}

changed_since() {   # <dir> <snapshot file>: paths whose state differs from the snapshot; "?TOOMANY" if either side was too big; "@@HEAD<TAB>old<TAB>new" if HEAD moved
  { cat "$2"; echo '@@NOW'; snap "$1"; } | awk -F'\t' '
    /^@@NOW$/ { now = 1; next }
    $1 == "TOOMANY" { print "?TOOMANY"; bad = 1; exit }
    $1 == "HEAD" { if (now) h1 = $2; else h0 = $2; next }
    now { n[$2] = $1; next }
    { b[$2] = $1 }
    END { if (bad) exit
          for (p in b) if (!(p in n) || n[p] != b[p]) print p
          for (p in n) if (!(p in b)) print p
          if (h0 != h1) print "@@HEAD\t" h0 "\t" h1 }' | sort -u
}

write_contract() {   # <proj dir> <id> <role> <files, comma separated> <done command>
  local o="$1/.team/out"
  printf 'role\t%s\nfiles\t%s\ndone\t%s\n' "$3" "$4" "$5" > "$o/$2.contract"
  if [ -e "$1/.git" ]; then snap "$1" > "$o/$2.base"; fi   # no .git of its own: git would walk up into the studio repo
}

pane_tail() {   # <pane> <n>: last n non-empty lines of what the pane shows, plain text
  { tmux capture-pane -p -J -t "$1" -S -200 2>/dev/null || true; } | sed -e 's/[[:space:]]*$//' | { grep -v '^$' || true; } | tail -n "$2"
}

screen_log() {   # <pane> <proj dir> <id> <why>: save the pane's screen as markdown in .team/logs/<id>.md
  mkdir -p "$2/.team/logs"
  { printf '# Worker screen of %s (%s, %s)\n\n~~~~~~text\n' "$3" "$4" "$(date '+%F %T')"
    { tmux capture-pane -p -J -t "$1" -S -300 2>/dev/null || true; } | sed -e 's/[[:space:]]*$//' | cat -s
    printf '~~~~~~\n'; } > "$2/.team/logs/$3.md"
}

verify_task() {   # <proj dir> <id>: writes .team/out/<id>.verify and prints "verify: ..." (first file line "<ok|warn|fail><TAB><summary>", rest = details)
  local d=$1 id=$2 o="$1/.team/out" role files cmd g p n old new isdev= toomany= st=ok rc=0 tout= why= more=
  local -a scope=() chg=() outof=() fails=() warns=() oks=() det=()
  role=$(cget "$o/$id.contract" role); files=$(cget "$o/$id.contract" files); cmd=$(cget "$o/$id.contract" done)
  case $role in dev|dev-*) isdev=1 ;; esac

  if [ -s "$o/$id.md" ]; then oks+=("result written"); else fails+=("no result file (.team/out/$id.md is missing or empty)"); fi

  if [ -f "$o/$id.base" ]; then
    mapfile -t chg < <(changed_since "$d" "$o/$id.base")
    local -a keep=()
    for p in "${chg[@]}"; do
      case $p in
        '?TOOMANY') toomany=1 ;;
        @@HEAD*) IFS=$'\t' read -r _ old new <<<"$p"   # the worker committed: those files changed too
                 [ "$old" = none ] && old=$EMPTY_TREE
                 while IFS= read -r g; do [ -n "$g" ] && keep+=("$g"); done < <(rgit -C "$d" diff --name-only --no-renames "$old" "$new" 2>/dev/null || true) ;;
        *) keep+=("$p") ;;
      esac
    done
    mapfile -t chg < <(printf '%s\n' "${keep[@]}" | sed '/^$/d' | sort -u)
    n=${#chg[@]}
    if [ -n "$toomany" ]; then warns+=("could not compare files: too many untracked files (add a .gitignore)")
    else
      if [ "$n" -gt 0 ]; then oks+=("$n file$(plural "$n") changed"); fi
      if [ -n "$files" ]; then
        IFS=, read -ra scope <<<"$files"
        for p in "${chg[@]}"; do
          local ok=
          for g in "${scope[@]}"; do
            g="${g#"${g%%[![:space:]]*}"}"; g="${g%"${g##*[![:space:]]}"}"; g=${g%/}; [ -n "$g" ] || continue
            case $p in $g|$g/*) ok=1; break ;; esac
          done
          [ -n "$ok" ] || outof+=("$p")
        done
        if [ ${#outof[@]} -gt 0 ]; then fails+=("${#outof[@]} file$(plural ${#outof[@]}) outside the allowed scope"); fi
      fi
      if [ -n "$isdev" ] && [ "$n" = 0 ]; then warns+=("no files changed"); fi
    fi
  fi

  if [ -n "$cmd" ]; then
    local t0=$SECONDS
    if tout=$(cd "$d" && env -u NINEROUTER_API_KEY timeout "${TEAM_VERIFY_TIMEOUT:-300}" bash -c "$cmd" 2>&1 </dev/null); then
      oks+=("done command passed ($((SECONDS - t0))s)")
    else
      rc=$?; why=; if [ "$rc" = 124 ]; then why=", timed out"; fi
      fails+=("done command failed (exit $rc$why)")
    fi
  elif [ -n "$isdev" ]; then warns+=("no test command (pass --done or set test: in .team/roles/$role.md)"); fi

  if [ ${#fails[@]} -gt 0 ]; then st=fail; elif [ ${#warns[@]} -gt 0 ]; then st=warn; fi
  local -a parts=("${fails[@]}" "${warns[@]}" "${oks[@]}"); local sum=
  for p in "${parts[@]}"; do sum+="${sum:+ · }$p"; done

  if [ ${#chg[@]} -gt 0 ] && [ "$st" != ok ]; then
    if [ ${#chg[@]} -gt 8 ]; then more=" (+$((${#chg[@]} - 8)) more)"; fi
    det+=("changed: $(printf '%s\n' "${chg[@]:0:8}" | paste -sd, - | sed 's/,/, /g')$more")
  fi
  if [ ${#outof[@]} -gt 0 ]; then det+=("outside scope ($files): $(printf '%s\n' "${outof[@]:0:8}" | paste -sd, - | sed 's/,/, /g')"); fi
  if [ "$rc" != 0 ] && [ -n "$tout" ]; then
    det+=("done command output (last lines):"); while IFS= read -r p; do det+=("    ${p:0:200}"); done < <(printf '%s\n' "$tout" | tail -n 8)
  fi

  { printf '%s\t%s\n' "$st" "$sum"; [ ${#det[@]} -eq 0 ] || printf '%s\n' "${det[@]}"; } > "$o/$id.verify"
  show_verify "$o/$id.verify"
}

show_verify() {   # <verify file>
  local st; st=$(head -1 "$1" | cut -f1)
  printf 'verify: %s — %s\n' "$(tr '[:lower:]' '[:upper:]' <<<"$st")" "$(head -1 "$1" | cut -f2-)"
  tail -n +2 "$1" | sed 's/^/  /'
}
