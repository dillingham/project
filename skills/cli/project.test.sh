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

fixture
cat > "$FIXTURE/project/todo-example.md" <<'DOC'
# A ticket

Spec: spec-real.md

## Todo

Fine: [real](spec-real.md), [heading](spec-real.md#the-heading), [here](#a-ticket), [site](https://example.com).
Broken: [gone](spec-gone.md), [nope](spec-real.md#nope), and spec-real.md bare. `spec-real.md` in code is fine.
DOC
printf '# Real\n\n## The Heading\n' > "$FIXTURE/project/spec-real.md"
mkdir -p "$FIXTURE/src" "$FIXTURE/tests"
printf '// see project/spec-real.md and project/spec-missing.md\n' > "$FIXTURE/src/app.php"
printf '// a fixture: project/planted.md\n' > "$FIXTURE/tests/fixture.php"
git -C "$FIXTURE" add -A
if run check; then echo 'FAIL: check passed a broken board' >&2; exit 1; fi
contains "$TEMP/output" 'project/todo-example.md:8: P001  link to a file that does not exist: spec-gone.md'
contains "$TEMP/output" 'project/todo-example.md:8: P002  no heading on spec-real.md for #nope'
contains "$TEMP/output" 'project/todo-example.md:8: P003  bare spec-real.md in prose'
contains "$TEMP/output" 'src/app.php:1: P004  cites project/spec-missing.md'
[ "$(wc -l < "$TEMP/output" | tr -d ' ')" = 4 ] || { echo 'FAIL: check reported something fine' >&2; cat "$TEMP/output" >&2; exit 1; }
ok 'check reports broken links, missing anchors, bare ticket names and stale code citations, and nothing that is fine'

fixture
run check
ok 'check passes a clean board'

fixture
rm "$FIXTURE/project/todo-example.md"
if run check; then echo 'FAIL: check passed an empty board' >&2; exit 1; fi
ok 'an empty board fails the check rather than passing unread'

fixture
printf '# Blocker\n\nPriority: high\n' > "$FIXTURE/project/todo-blocker.md"
printf '# Waits\n\nPriority: high\nBlocked: todo-blocker.md - needs it first\n' > "$FIXTURE/project/todo-waits.md"
printf '# Taken\n\nPriority: high\n' > "$FIXTURE/project/todo-taken.md"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm board
git -C "$FIXTURE" worktree add -q "$TEMP/worktree $passed" -b taken
run blocked
contains "$TEMP/output" 'BLOCKED'
if grep -q 'UNBLOCKED' "$TEMP/output"; then echo 'FAIL: a live blocker read as lifted' >&2; cat "$TEMP/output" >&2; exit 1; fi
run next
contains "$TEMP/output" 'todo-blocker'
if grep -q 'todo-taken' "$TEMP/output"; then echo 'FAIL: next offered a claimed ticket' >&2; cat "$TEMP/output" >&2; exit 1; fi
ok 'claims and blockers read correctly from a repository path with spaces'

fixture
for i in $(seq 1500); do printf '# Groom %s\n\nPriority: groom\n' "$i" > "$FIXTURE/project/idea-groom-$i.md"; done
run next || { echo "FAIL: next exited non-zero on a large grooming queue" >&2; exit 1; }
[ "$(grep -c 'groom' "$TEMP/output")" = 1 ] || { echo 'FAIL: next should offer exactly one ticket to triage' >&2; exit 1; }
ok 'next offers one ticket to triage and exits cleanly however long the queue'

fixture
run new idea untriaged-thing
contains "$FIXTURE/project/idea-untriaged-thing.md" 'Priority: groom'
run groom
contains "$TEMP/output" 'idea-untriaged-thing'
ok 'a new ticket is untriaged until someone judges it'

fixture
printf '# Page\n\n## Usage\n\n## Usage\n' > "$FIXTURE/project/spec-dup.md"
printf '# A ticket\n\nPriority: low\n\n## Todo\n\n[one](spec-dup.md#usage) [two](spec-dup.md#usage-1) [three](spec-dup.md#usage-2)\n' > "$FIXTURE/project/todo-example.md"
if run check; then echo 'FAIL: check passed a link to a third Usage' >&2; exit 1; fi
contains "$TEMP/output" 'no heading on spec-dup.md for #usage-2'
[ "$(wc -l < "$TEMP/output" | tr -d ' ')" = 1 ] || { echo 'FAIL: check rejected a valid duplicate-heading anchor' >&2; cat "$TEMP/output" >&2; exit 1; }
ok 'a repeated heading is reachable at its numbered anchor'

fixture
printf '# Page\n\n## Usage\n\n## Usage-1\n\n## Usage\n' > "$FIXTURE/project/spec-dup.md"
printf '# A ticket\n\nPriority: low\n\n## Todo\n\n[a](spec-dup.md#usage) [b](spec-dup.md#usage-1) [c](spec-dup.md#usage-2) [d](spec-dup.md#usage-3)\n' > "$FIXTURE/project/todo-example.md"
if run check; then echo 'FAIL: check passed a link to a heading that is not there' >&2; exit 1; fi
contains "$TEMP/output" 'no heading on spec-dup.md for #usage-3'
[ "$(wc -l < "$TEMP/output" | tr -d ' ')" = 1 ] || { echo 'FAIL: a heading id was handed out twice' >&2; cat "$TEMP/output" >&2; exit 1; }
ok 'a numbered heading id is never handed out twice'

fixture
printf '# Middling\n\nPriority: medium\n\n## Todo\n\nx\n' > "$FIXTURE/project/todo-middling.md"
printf '# Minor\n\nPriority: low\n\n## Todo\n\nx\n' > "$FIXTURE/project/todo-minor.md"
run next
contains "$TEMP/output" 'no critical or high work is free'
contains "$TEMP/output" 'todo-middling'
contains "$TEMP/output" 'todo-example'
if grep -q 'todo-minor' "$TEMP/output"; then echo 'FAIL: next offered a lower rank beside the best one' >&2; cat "$TEMP/output" >&2; exit 1; fi
ok 'with nothing urgent, next offers the best available rank and says so'

fixture
printf '# Renamed\n\nPriority: high\n\n## Spike\n\nx\n\n## Todo\n\nx\n' > "$FIXTURE/project/todo-renamed.md"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm board
git -C "$FIXTURE" worktree add -q "$TEMP/worktree $passed" -b renamed
run open
grep -q 'todo-renamed.*CLAIMED' "$TEMP/output" || { echo 'FAIL: the claim did not follow the rename' >&2; cat "$TEMP/output" >&2; exit 1; }
run next
contains "$TEMP/output" 'nothing judged is free to start: 1 claimed, 0 blocked'
if grep -q 'todo-renamed' "$TEMP/output"; then echo 'FAIL: next offered a claimed ticket' >&2; exit 1; fi
cp "$FIXTURE/project/todo-renamed.md" "$TEMP/before"
if run move done todo-renamed; then echo 'FAIL: moved a ticket claimed by another branch' >&2; exit 1; fi
cmp "$TEMP/before" "$FIXTURE/project/todo-renamed.md"
contains "$TEMP/output" 'claimed by renamed'
(cd "$TEMP/worktree $passed" && bash "$SCRIPT" move done todo-renamed > /dev/null) || { echo 'FAIL: the claiming branch could not move its ticket' >&2; exit 1; }
ok 'a claim follows its ticket through a status change, and only its branch may move it'

fixture
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm board
WT="$TEMP/worktree $passed"
git -C "$FIXTURE" worktree add -q "$WT" -b example
printf '\n### Checkpoint 2026-09-01\n\nNext: the old plan.\n\n### Checkpoint 2026-09-12\n\nFailed: the first approach.\nNext: the second approach.\n' >> "$WT/project/todo-example.md"
git -C "$WT" -c user.name=Test -c user.email=test@example.test commit -qam checkpoint
echo wip > "$WT/wip.txt"
run resume todo-example
contains "$TEMP/output" "$(printf 'path\t%s' "$(git -C "$WT" rev-parse --show-toplevel)")"
contains "$TEMP/output" '1 since'
contains "$TEMP/output" '...example'
contains "$TEMP/output" '?? wip.txt'
contains "$TEMP/output" 'Next: the second approach.'
if grep -q 'the old plan' "$TEMP/output"; then echo 'FAIL: resume showed a superseded checkpoint' >&2; exit 1; fi
(cd "$WT" && bash "$SCRIPT" resume) > "$TEMP/output" 2>&1
contains "$TEMP/output" 'Next: the second approach.'
if run resume todo-missing; then echo 'FAIL: resumed a ticket nothing claims' >&2; exit 1; fi
ok 'resume reads the newest checkpoint from the branch copy, beside the worktree and its state'

fixture
cat > "$FIXTURE/project/todo-example.md" <<'DOC'
# Cache

Priority: high

## Spike

### Checkpoint 2026-09-01

Next: ask the user to choose a cache lifetime.

## Todo

Approved: cache per request, decided 2026-09-05.
DOC
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm board
WT="$TEMP/worktree $passed"
git -C "$FIXTURE" worktree add -q "$WT" -b example
run resume todo-example
contains "$TEMP/output" 'none under ## Todo'
contains "$TEMP/output" 'Approved: cache per request'
if grep -q 'ask the user' "$TEMP/output"; then echo 'FAIL: resume offered a spike checkpoint on a todo' >&2; cat "$TEMP/output" >&2; exit 1; fi
printf '\n### Checkpoint 2026-09-12\n\nNext: wire it in.\n' >> "$WT/project/todo-example.md"
run resume todo-example
contains "$TEMP/output" 'Next: wire it in.'
if grep -q 'ask the user' "$TEMP/output"; then echo 'FAIL: resume offered a spike checkpoint on a todo' >&2; exit 1; fi
ok 'resume reads only the current section, and shows that section when it has no checkpoint'

fixture
printf '# Shipped\n\nPriority: low\n\n## Todo\n\n## Done\n\n' > "$FIXTURE/project/done-shipped.md"
printf '# Written\n\nPriority: low\n\n## Todo\n\n## Done\n\n```text\nexample\n```\n' > "$FIXTURE/project/done-written.md"
if run check; then echo 'FAIL: check passed a ## Done nobody wrote' >&2; exit 1; fi
contains "$TEMP/output" 'project/done-shipped.md:7: P005  nothing written under ## Done'
[ "$(wc -l < "$TEMP/output" | tr -d ' ')" = 1 ] || { echo 'FAIL: check held history or a fenced example against the ticket' >&2; cat "$TEMP/output" >&2; exit 1; }
ok 'check flags a current section nobody wrote, and leaves earlier sections alone'

fixture
printf 'hello\n' > "$FIXTURE/a.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qF - <<'MSG'
Ship the widget

Branch: widget
MSG
run trail todo-widget
contains "$TEMP/output" 'Ship the widget'
# no remote is ever added to a fixture repo, so the pr lookup is always
# unavailable here - for a reason that depends on whether this machine
# happens to have gh installed, which the assertion does not care about
contains "$TEMP/output" 'unavailable'
run trail spike-widget
contains "$TEMP/output" 'Ship the widget'
run trail todo-missing-entirely
contains "$TEMP/output" 'no commits carry Branch: missing-entirely'
ok 'trail finds a commit by its Branch trailer under any status prefix, without touching project/, and reports plainly when a pr lookup cannot run'

fixture
printf '# Widget\n\nPriority: high\n' > "$FIXTURE/project/todo-widget.md"
printf '# Todo Widget\n\nPriority: high\n' > "$FIXTURE/project/todo-todo-widget.md"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm board
# git worktree list --porcelain sorts by PATH, not by creation order, so the
# colliding branch's folder is named to sort FIRST - a whole-string fallback
# would then match it before ever reaching the correct one; a fix that only
# works because the correct branch happened to sort first would pass either way
git -C "$FIXTURE" worktree add -q "$TEMP/aaa-collides $passed" -b todo-widget
git -C "$FIXTURE" worktree add -q "$TEMP/zzz-correct $passed" -b widget
run resume todo-widget
contains "$TEMP/output" "$(printf 'path\t%s' "$(git -C "$TEMP/zzz-correct $passed" rev-parse --show-toplevel)")"
if grep -q "aaa-collides $passed" "$TEMP/output"; then echo 'FAIL: resume matched the wrong tickets branch' >&2; cat "$TEMP/output" >&2; exit 1; fi
ok 'resume matches a ticket id to its own branch, not to another ticket whose raw id equals it'

fixture
printf 'hello\n' > "$FIXTURE/a.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qm init
git -C "$FIXTURE" remote add origin https://example.com/fake/repo.git
mkdir -p "$TEMP/bin $passed"
cat > "$TEMP/bin $passed/gh" <<'SH'
#!/usr/bin/env bash
echo '[{"number":1,"title":"Exact match","url":"https://example.com/pr/1","headRefName":"slugify"},{"number":2,"title":"False positive","url":"https://example.com/pr/2","headRefName":"slugify-followup"}]'
SH
chmod +x "$TEMP/bin $passed/gh"
PATH="$TEMP/bin $passed:$PATH" run trail todo-slugify
contains "$TEMP/output" 'Exact match'
if grep -q 'False positive' "$TEMP/output"; then echo 'FAIL: trail attributed an unrelated pr from a loose head match' >&2; cat "$TEMP/output" >&2; exit 1; fi
ok 'trail filters the gh search results by the exact head, not GitHubs loose head: match'

fixture
printf 'hello\n' > "$FIXTURE/a.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qF - <<'MSG'
Ship a and b together

Branch: a+b
MSG
run trail todo-a
contains "$TEMP/output" 'Ship a and b together'
run trail todo-b
contains "$TEMP/output" 'Ship a and b together'
run trail todo-c
contains "$TEMP/output" 'no commits carry Branch: c'
ok 'trail finds a joined branchs commit from either single ticket id, and not from an unrelated one'

fixture
printf 'hello\n' > "$FIXTURE/a.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qF - <<'MSG'
Ship it

Branch: gone-ticket
MSG
rm -rf "$FIXTURE/project"
run trail todo-gone-ticket
contains "$TEMP/output" 'Ship it'
ok 'trail works even after project/ itself is gone'

fixture
printf 'hello\n' > "$FIXTURE/a.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qF - <<'MSG'
Ship alpha and beta together

Branch: alpha+beta
MSG
git -C "$FIXTURE" remote add origin https://example.com/fake/repo.git
mkdir -p "$TEMP/bin $passed"
cat > "$TEMP/bin $passed/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in
  *" api "*"/pulls"*) echo "42	Ship alpha and beta together	https://example.com/pr/42" ;;
  *" pr "*" list "*) echo "[]" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$TEMP/bin $passed/gh"
# querying by beta, the SECOND part of the joined branch - a head:beta
# search would never find alpha+beta, since head: is a prefix search
PATH="$TEMP/bin $passed:$PATH" run trail todo-beta
contains "$TEMP/output" 'Ship alpha and beta together'
ok 'trail finds a joined branchs pr by the commit it found, regardless of which of its tickets was queried'

fixture
printf 'hello\n' > "$FIXTURE/a.txt"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" -c user.name=Test -c user.email=test@example.test commit -qF - <<'MSG'
Ship a and b separately

Branch: a
Branch: b
MSG
run trail todo-a
contains "$TEMP/output" 'Ship a and b separately'
run trail todo-b
contains "$TEMP/output" 'Ship a and b separately'
ok 'trail finds a commit carrying two separate Branch trailer lines, for either ticket'

printf '%s scenarios passed.\n' "$passed"
