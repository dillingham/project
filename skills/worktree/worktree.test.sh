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

printf '%s scenarios passed.\n' "$passed"
