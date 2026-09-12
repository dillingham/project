#!/usr/bin/env bash
# worktree.sh in throwaway repositories: what it creates, what it refuses,
# and that a refusal never loses the work it was asked to carry.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/worktree.sh"
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/worktree-test.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT
passed=0

repo() {
  passed=$((passed+1))
  R="$TEMP/repo $passed"
  mkdir -p "$R"
  git -C "$R" init -q -b main
  echo original > "$R/a.txt"
  git -C "$R" add -A
  git -C "$R" -c user.name=Test -c user.email=test@example.test commit -qm init
}
run() { (cd "$R" && PROJECT_WORKTREES="$1" bash "$SCRIPT" "${@:2}") > "$TEMP/output" 2>&1; }
fail() { echo "FAIL: $1" >&2; cat "$TEMP/output" >&2; exit 1; }
ok() { printf 'PASS: %s\n' "$1"; }
# another process holding the start lock on $1, as $holder, until killed
hold() {
  python3 -c 'import fcntl, sys, time; f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(60)' "$1" "$TEMP/held" &
  holder=$!
  until [ -e "$TEMP/held" ]; do sleep 0.1; done
  rm -f "$TEMP/held"
}

repo
run "$TEMP/worktrees $passed" 'todo-a+todo-b' || fail 'a joined id did not open a worktree'
[ -d "$TEMP/worktrees $passed/repo-$passed-todo-a" ] || fail 'the folder is not named after the first id'
git -C "$R" show-ref --verify --quiet 'refs/heads/todo-a+todo-b' || fail 'the branch lost the joined id'
ok 'a joined id keeps its branch name and names its folder after the first id'

repo
echo edited > "$R/a.txt"
run "$TEMP/worktrees $passed" todo-x && fail 'a dirty default branch did not abort'
[ "$(cat "$R/a.txt")" = edited ] || fail 'the refusal touched the dirty work'
ok 'a dirty default branch is refused without --take and left as it was'

repo
echo edited > "$R/a.txt"
touch "$TEMP/a file"
run "$TEMP/a file/worktrees" todo-x --take && fail 'an uncreatable worktrees folder did not abort'
[ "$(cat "$R/a.txt")" = edited ] || fail 'the stashed work was not restored to the default branch'
[ -z "$(git -C "$R" stash list)" ] || fail 'the stash was left behind'
ok 'a --take that fails after stashing puts the work back and leaves no stash'

repo
echo staged > "$R/a.txt"
git -C "$R" add a.txt
echo unstaged > "$R/a.txt"
echo untracked > "$R/new.txt"
touch "$TEMP/a file $passed"
run "$TEMP/a file $passed/worktrees" todo-x --take && fail 'an uncreatable worktrees folder did not abort'
[ "$(git -C "$R" show :a.txt)" = staged ] || fail 'the staged version was lost from the index'
[ "$(cat "$R/a.txt")" = unstaged ] || fail 'the unstaged version was lost'
[ "$(cat "$R/new.txt")" = untracked ] || fail 'the untracked file was lost'
[ -z "$(git -C "$R" stash list)" ] || fail 'the stash was left behind'
[ -z "$(git -C "$R" for-each-ref refs/take)" ] || fail 'the ref holding the changes was left behind'
ok 'a failed --take puts staged, unstaged and untracked changes back exactly as they were'

repo
echo staged > "$R/a.txt"
git -C "$R" add a.txt
echo unstaged > "$R/a.txt"
echo untracked > "$R/new.txt"
run "$TEMP/worktrees $passed" todo-x --take || fail '--take did not open a worktree'
D="$TEMP/worktrees $passed/repo-$passed-todo-x"
[ "$(git -C "$D" show :a.txt)" = staged ] || fail 'the staged version did not arrive staged'
[ "$(cat "$D/a.txt")" = unstaged ] || fail 'the unstaged version did not arrive'
[ "$(cat "$D/new.txt")" = untracked ] || fail 'the untracked file did not arrive'
[ -z "$(git -C "$R" status --porcelain)" ] || fail 'the default branch was not left clean'
ok '--take moves staged, unstaged and untracked changes exactly as they were'

repo
git -C "$R" worktree add -q "$TEMP/other $passed" -b other
echo mine > "$R/a.txt"
echo untracked > "$R/new.txt"
REAL_GIT=$(command -v git)
mkdir -p "$TEMP/bin $passed"
# git as usual, except that it logs every command reading or writing the
# stash stack, and at each step of the move another worktree pushes a stash
cat > "$TEMP/bin $passed/git" <<SH
#!/usr/bin/env bash
"$REAL_GIT" "\$@"; status=\$?
case " \$* " in
  *" stash create "*|*" stash apply "*) ;;
  *" stash "*) echo "\$*" >> "$TEMP/stack $passed" ;;
esac
case " \$* " in *" stash create "*|*" worktree add "*|*" stash apply "*)
  echo "competitor \$\$" > "$TEMP/other $passed/a.txt"
  "$REAL_GIT" -C "$TEMP/other $passed" stash push -q -m competitor ;;
esac
exit \$status
SH
chmod +x "$TEMP/bin $passed/git"
(cd "$R" && PATH="$TEMP/bin $passed:$PATH" PROJECT_WORKTREES="$TEMP/worktrees $passed" bash "$SCRIPT" todo-x --take) > "$TEMP/output" 2>&1 \
  || fail '--take failed while another worktree pushed stashes'
[ ! -e "$TEMP/stack $passed" ] || fail "--take read or wrote the shared stash stack: $(cat "$TEMP/stack $passed")"
D="$TEMP/worktrees $passed/repo-$passed-todo-x"
[ "$(cat "$D/a.txt")" = mine ] && [ "$(cat "$D/new.txt")" = untracked ] || fail 'the worktree did not get the changes, untracked file included'
[ "$(git -C "$R" stash list | wc -l | tr -d ' ')" = 3 ] && [ "$(git -C "$R" stash list --format=%gs | sort -u)" = 'On other: competitor' ] \
  || fail "the other worktree's stashes did not all survive: $(git -C "$R" stash list)"
[ -z "$(git -C "$R" status --porcelain)" ] || fail 'the default branch was not left clean'
[ -z "$(git -C "$R" for-each-ref refs/take)" ] || fail 'the ref holding the changes was left behind'
ok '--take never touches the shared stash stack, so stashes other worktrees push mid-move all survive'

repo
P="$(cd "$(dirname "$SCRIPT")/../cli" && pwd)/project.sh"
(cd "$R" && bash "$P" new todo ship-it > /dev/null) || fail 'new did not file the ticket'
git -C "$R" add -A
git -C "$R" -c user.name=Test -c user.email=test@example.test commit -qm 'file todo-ship-it'
(cd "$R" && bash "$P" next 2>/dev/null) | grep -q todo-ship-it || fail 'next does not offer the new ticket'
run "$TEMP/worktrees $passed" todo-ship-it || fail 'the ticket did not get a worktree'
D="$TEMP/worktrees $passed/repo-$passed-todo-ship-it"
(cd "$R" && bash "$P" claimed) | grep -q "^todo-ship-it" || fail 'the worktree does not claim its ticket'
if (cd "$R" && bash "$P" next 2>/dev/null) | grep -q todo-ship-it; then fail 'next still offers a claimed ticket'; fi
(cd "$D" && bash "$P" move done todo-ship-it > /dev/null) || fail 'the ticket did not move to done inside its worktree'
[ -f "$D/project/done-ship-it.md" ] && [ -f "$R/project/todo-ship-it.md" ] || fail 'the move reached beyond its worktree'
(cd "$D" && bash "$P" check > "$TEMP/output") && fail 'check passed a ## Done nobody wrote'
printf 'Shipped; `true` proves it.\n' >> "$D/project/done-ship-it.md"
(cd "$D" && bash "$P" check > "$TEMP/output") || fail 'the board is not clean after the move'
ok 'a ticket goes from filed, to offered, to claimed by its worktree, to done inside it'

repo
git -C "$R" worktree add -q "$TEMP/held $passed" -b todo-a
run "$TEMP/worktrees $passed" 'todo-a+todo-b' && fail 'a joined id opened over a claimed ticket'
grep -q 'todo-a is already claimed by todo-a' "$TEMP/output" || fail 'the refusal did not name the claim'
git -C "$R" show-ref --verify --quiet 'refs/heads/todo-a+todo-b' && fail 'the refusal left a branch behind'
git -C "$R" worktree add -q "$TEMP/spike $passed" -b spike-c
run "$TEMP/worktrees $passed" todo-c && fail 'a ticket opened while its earlier status held a worktree'
grep -q 'todo-c is already claimed by spike-c' "$TEMP/output" || fail 'the refusal did not name the earlier status'
ok 'a claimed ticket, joined or under an earlier status, is refused before anything is created'

repo
REAL_GIT=$(command -v git)
mkdir -p "$TEMP/bin $passed"
# git as usual, but slow to list worktrees, so two starts launched together
# both reach the claim check before either has created anything
cat > "$TEMP/bin $passed/git" <<SH
#!/usr/bin/env bash
case " \$* " in *" worktree list "*) sleep 1 ;; esac
exec "$REAL_GIT" "\$@"
SH
chmod +x "$TEMP/bin $passed/git"
start() { (cd "$R" && PATH="$TEMP/bin $passed:$PATH" PROJECT_WORKTREES="$TEMP/worktrees $passed" bash "$SCRIPT" "$1") > "$TEMP/output $2" 2>&1; }
# a start killed while holding the lock, so both starts below find its
# leftovers - the arrangement where stale-lock takeover let two in at once
hold "$R/.git/project-worktree.lock"
{ kill -9 "$holder"; wait "$holder"; } 2>/dev/null || true
start todo-a one & first=$!
start 'todo-b+todo-a' two & second=$!
wait "$first" && a=0 || a=1
wait "$second" && b=0 || b=1
[ $((a + b)) = 1 ] || { cat "$TEMP/output one" "$TEMP/output two" >&2; fail 'two simultaneous starts did not come out as exactly one claim'; }
ok 'two starts at once on the same ticket make exactly one worktree, after a killed start too'

repo
hold "$R/.git/project-worktree.lock"
(cd "$R" && PROJECT_LOCK_WAIT=1 PROJECT_WORKTREES="$TEMP/worktrees $passed" bash "$SCRIPT" todo-x) > "$TEMP/output" 2>&1 && fail 'a start went ahead while another held the lock'
grep -q 'has held' "$TEMP/output" || fail 'the refusal did not name the lock'
git -C "$R" show-ref --verify --quiet refs/heads/todo-x && fail 'a start blocked on the lock still made a branch'
{ kill -9 "$holder"; wait "$holder"; } 2>/dev/null || true
run "$TEMP/worktrees $passed" todo-x || fail 'a killed holder still blocked the next start'
ok 'a start waits on a held lock, and a killed holder blocks nothing'

repo
REAL_GIT=$(command -v git)
mkdir -p "$TEMP/bin $passed"
# git as usual, except that worktree add reports its parent and its own pid,
# then waits to be let go - so the start can be killed mid-creation
cat > "$TEMP/bin $passed/git" <<SH
#!/usr/bin/env bash
case " \$* " in *" worktree add "*)
  echo "\$PPID \$\$" > "$TEMP/adding $passed"
  until [ -e "$TEMP/release $passed" ]; do sleep 0.1; done ;;
esac
exec "$REAL_GIT" "\$@"
SH
chmod +x "$TEMP/bin $passed/git"
(cd "$R" && PATH="$TEMP/bin $passed:$PATH" PROJECT_WORKTREES="$TEMP/worktrees $passed" bash "$SCRIPT" todo-a) > "$TEMP/output first" 2>&1 &
first=$!
until [ -s "$TEMP/adding $passed" ]; do sleep 0.1; done
read -r parent child < "$TEMP/adding $passed"
kill -9 "$parent"; wait "$first" 2>/dev/null || true
(cd "$R" && PROJECT_LOCK_WAIT=1 PROJECT_WORKTREES="$TEMP/worktrees $passed" bash "$SCRIPT" 'todo-b+todo-a') > "$TEMP/output" 2>&1 \
  && fail 'a start went ahead while a killed start was still creating its worktree'
touch "$TEMP/release $passed"
while kill -0 "$child" 2>/dev/null; do sleep 0.1; done
git -C "$R" show-ref --verify --quiet refs/heads/todo-a || fail 'the orphaned creation did not finish'
run "$TEMP/worktrees $passed" 'todo-b+todo-a' && fail 'a joined id opened over the orphan'"'"'s claim'
grep -q 'todo-a is already claimed by todo-a' "$TEMP/output" || fail 'the refusal did not name the claim'
ok 'a start killed mid-creation holds the lock until its worktree add finishes'

printf '%s scenarios passed.\n' "$passed"
