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
(cd "$R" && bash "$P" next) | grep -q todo-ship-it || fail 'next does not offer the new ticket'
run "$TEMP/worktrees $passed" todo-ship-it || fail 'the ticket did not get a worktree'
D="$TEMP/worktrees $passed/repo-$passed-todo-ship-it"
(cd "$R" && bash "$P" claimed) | grep -q "^todo-ship-it" || fail 'the worktree does not claim its ticket'
if (cd "$R" && bash "$P" next) | grep -q todo-ship-it; then fail 'next still offers a claimed ticket'; fi
(cd "$D" && bash "$P" move done todo-ship-it > /dev/null) || fail 'the ticket did not move to done inside its worktree'
[ -f "$D/project/done-ship-it.md" ] && [ -f "$R/project/todo-ship-it.md" ] || fail 'the move reached beyond its worktree'
(cd "$D" && bash "$P" check > "$TEMP/output") || fail 'the board is not clean after the move'
ok 'a ticket goes from filed, to offered, to claimed by its worktree, to done inside it'

printf '%s scenarios passed.\n' "$passed"
