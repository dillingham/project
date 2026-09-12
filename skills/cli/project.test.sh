#!/usr/bin/env bash
# Exercise the real command in disposable Git repositories, never the live board.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/project.sh"
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/project-test.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT
passed=0

fixture() {
  passed=$((passed+1))
  FIXTURE="$TEMP/case $passed"
  mkdir -p "$FIXTURE/project" "$FIXTURE/docs/nested pages"
  git -C "$FIXTURE" init -q
  printf '# A ticket\n\nPriority: groom\n\n## Todo\n\nOriginal reasoning.\n' > "$FIXTURE/project/todo-example.md"
}

# the script finds the board from the working directory, as it does when installed as a plugin
run() { (cd "$FIXTURE" && bash "$SCRIPT" "$@") > "$TEMP/output" 2>&1; }
contains() { grep -Fq -- "$2" "$1" || { echo "FAIL: missing $2 in $1" >&2; exit 1; }; }
reject() {
  cp "$FIXTURE/project/todo-example.md" "$TEMP/before"
  if run "$@"; then echo "FAIL: accepted $*" >&2; exit 1; fi
  cmp "$TEMP/before" "$FIXTURE/project/todo-example.md"
}
ok() { printf 'PASS: %s\n' "$1"; }

fixture
cat > "$FIXTURE/docs/nested pages/references.md" <<'DOC'
[todo-example.md](../../project/todo-example.md#todo)
[Reasoning](../../project/todo-example.md)
Bare todo-example.md. Backticked `todo-example.md`.
```text
project/todo-example.md
```
[Live page](/project/todo-example#todo)
Keep todo-example-other.md and prefix-todo-example.md and todo-example.mdx.
Keep todo-example.md.backup and /project/todo-example-other.
DOC
printf 'Blocked: todo-example.md - needs the decision\n' > "$FIXTURE/project/issue-dependent.md"
printf 'Blocked: todo-example - same decision\n' > "$FIXTURE/project/issue-bare-dependent.md"
printf 'History: [todo-example.md](todo-example.md#todo)\n' > "$FIXTURE/project/changelog.md"
printf '// See project/todo-example.md' > "$FIXTURE/source.txt"
printf 'todo-example.md\000binary' > "$FIXTURE/binary.bin"
printf 'ignored/\n' > "$FIXTURE/.gitignore"
mkdir "$FIXTURE/ignored"
printf 'todo-example.md\n' > "$FIXTURE/ignored/reference.md"
git -C "$FIXTURE" add project docs source.txt .gitignore binary.bin
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm fixture
printf 'Untracked todo-example.md\n' > "$FIXTURE/untracked.md"
git -C "$FIXTURE" ls-files --stage > "$TEMP/index-before"
run move done todo-example.md
[ ! -e "$FIXTURE/project/todo-example.md" ]
contains "$FIXTURE/project/done-example.md" 'Original reasoning.'
contains "$FIXTURE/project/done-example.md" '## Done'
contains "$FIXTURE/docs/nested pages/references.md" '[done-example.md](../../project/done-example.md#todo)'
contains "$FIXTURE/docs/nested pages/references.md" '[Reasoning](../../project/done-example.md)'
contains "$FIXTURE/docs/nested pages/references.md" 'Bare done-example.md. Backticked `done-example.md`.'
contains "$FIXTURE/docs/nested pages/references.md" 'project/done-example.md'
contains "$FIXTURE/docs/nested pages/references.md" '[Live page](/project/done-example#todo)'
contains "$FIXTURE/docs/nested pages/references.md" 'Keep todo-example-other.md and prefix-todo-example.md and todo-example.mdx.'
contains "$FIXTURE/docs/nested pages/references.md" 'Keep todo-example.md.backup and /project/todo-example-other.'
contains "$FIXTURE/project/issue-dependent.md" 'Blocked: done-example.md - needs the decision'
contains "$FIXTURE/project/issue-bare-dependent.md" 'Blocked: done-example - same decision'
contains "$FIXTURE/project/changelog.md" 'History: [done-example.md](done-example.md#todo)'
contains "$FIXTURE/untracked.md" 'Untracked done-example.md'
printf '// See project/done-example.md' > "$TEMP/expected"
cmp "$TEMP/expected" "$FIXTURE/source.txt"
printf 'todo-example.md\000binary' > "$TEMP/expected"
cmp "$TEMP/expected" "$FIXTURE/binary.bin"
contains "$FIXTURE/ignored/reference.md" 'todo-example.md'
git -C "$FIXTURE" ls-files --stage > "$TEMP/index-after"
cmp "$TEMP/index-before" "$TEMP/index-after"
contains "$TEMP/output" 'unblocks: issue-dependent.md'
ok 'tracked and untracked references, old history, exact names, fragments, binary/ignore boundaries, unchanged index'

fixture
printf 'todo-example.md\n' > "$FIXTURE/project/changelog.md"
cp -R "$FIXTURE" "$TEMP/dry-before"
chmod a-w "$FIXTURE/project/todo-example.md" "$FIXTURE/project/changelog.md"
run move done todo-example --dry-run
diff -r "$TEMP/dry-before" "$FIXTURE"
contains "$TEMP/output" '(dry run)'
contains "$TEMP/output" '+done-example.md'
ok 'dry run shows the reference diff without changing files or requiring write access'

fixture
run mv todo-example.md done
contains "$FIXTURE/project/done-example.md" '## Done'
ok 'legacy mv accepts the extension and succeeds without dependents'

fixture
run mv todo-example spike
contains "$FIXTURE/project/spike-example.md" '## Spike'
ok 'legacy mv accepts an id'

fixture
printf '# Existing history\n' > "$FIXTURE/project/done-example.md"
cp "$FIXTURE/project/done-example.md" "$TEMP/destination-before"
reject move done todo-example
cmp "$TEMP/destination-before" "$FIXTURE/project/done-example.md"
ok 'collision preserves both tickets'

fixture
reject move todo todo-example
reject move unknown todo-example
reject move 'done reject' todo-example
reject move done ../todo-example
reject move done todo-example --unknown
reject move done todo-example --dry-run extra
reject move done todo-missing
ok 'same status, invalid input, and missing source change nothing'

fixture
ln -s "$FIXTURE/missing" "$FIXTURE/project/done-example.md"
reject move done todo-example
[ -L "$FIXTURE/project/done-example.md" ]
ok 'dangling destination symlink is a collision'

fixture
printf 'No final newline' > "$FIXTURE/project/todo-example.md"
run move done todo-example
printf 'No final newline\n\n## Done\n\n' > "$TEMP/expected"
cmp "$TEMP/expected" "$FIXTURE/project/done-example.md"
ok 'section appends correctly to a ticket without a final newline'

fixture
printf 'todo-example.md\n' > "$FIXTURE/reference.md"
cp -R "$FIXTURE/project" "$TEMP/rollback-before"
mkdir "$FIXTURE/bin"
REAL_CAT=$(command -v cat)
cat > "$FIXTURE/bin/cat" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" = */1.after ]] && [ ! -e "$PROJECT_TEST_FAILURE" ]; then
  touch "$PROJECT_TEST_FAILURE"
  printf 'partial write'
  exit 1
fi
exec "$PROJECT_TEST_CAT" "$@"
SH
chmod +x "$FIXTURE/bin/cat"
if PATH="$FIXTURE/bin:$PATH" PROJECT_TEST_CAT="$REAL_CAT" PROJECT_TEST_FAILURE="$TEMP/failed" run move done todo-example; then
  echo 'FAIL: write failure reported success' >&2; exit 1
fi
diff -r "$TEMP/rollback-before" "$FIXTURE/project"
contains "$FIXTURE/reference.md" 'todo-example.md'
ok 'write failure restores the original ticket and references'

printf '%s scenarios passed.\n' "$passed"
