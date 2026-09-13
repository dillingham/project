#!/usr/bin/env bash
# Plant each kind of source in a throwaway repo and check every candidate is
# listed with the board files already citing it - and that fenced examples,
# ticked boxes, ignored files and near-miss citations stay out.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backfill.sh"
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/backfill-test.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT
git -C "$TEMP" init -q
mkdir -p "$TEMP/project" "$TEMP/notes/sub" "$TEMP/notes/.trash" "$TEMP/src/Reminders" "$TEMP/vendor" "$TEMP/bin"
T=$'\t'

printf '# Auth\n\nPriority: groom\n\n## Todo\n\nBackfilled from `notes/auth.md` and gh#12. Also notes/fences.md.\n' > "$TEMP/project/todo-auth.md"
printf '# Other\n\nPriority: groom\n\n## Idea\n\nSee `xnotes/sub/billing.md`, `notes/sub/billing.md.bak`, gh#1200, https://github.com/other/dep/issues/7 and https://github.com/a/b/issues/8.\n' > "$TEMP/project/idea-other.md"
cat > "$TEMP/notes/fences.md" <<'MD'
````markdown
```php
// TODO: example inside
```
````
TODO: real one after
MD
cat > "$TEMP/notes/auth.md" <<'MD'
# Auth notes

- [ ] rotate refresh tokens
- [x] login form
TODO: decide session length

```text
TODO in fence
- [ ] fenced example
```
MD
printf 'Billing stuff\n- [ ] invoices\n' > "$TEMP/notes/sub/billing.md"
printf '# Trashed\n- [ ] hidden\n' > "$TEMP/notes/.trash/old.md"
cat > "$TEMP/src/Reminders/EmailReminder.php" <<'PHP'
<?php
final class EmailReminder
{
    // TODO(brian): retry when the mailer is down
    /* FIXME handle timezones */
}
PHP
printf '<?php\n// queues an email_reminder later\n$todo = 1;\n' > "$TEMP/src/Other.php"
printf '<?php\n// TODO: unrelated\n' > "$TEMP/src/Unrelated.php"
printf '<?php\n// TODO: EmailReminder vendored\n' > "$TEMP/vendor/EmailReminderLib.php"
printf 'vendor/\n' > "$TEMP/.gitignore"

run() { out=$(cd "$TEMP" && bash "$SCRIPT" "$@" 2>"$TEMP/err") && code=0 || code=$?; }
fail() { echo "FAIL: $1"; echo "$out"; cat "$TEMP/err"; exit 1; }
expect() { grep -Fxq -- "$1" <<<"$out" || fail "missing: $1"; }
refuse() { ! grep -Fq -- "$1" <<<"$out" || fail "unexpected: $1"; }

run md notes
[ "$code" -eq 0 ] || fail "md exited $code"
expect "notes/auth.md${T}doc${T}Auth notes${T}todo-auth.md"
expect "notes/auth.md:3${T}open${T}rotate refresh tokens${T}todo-auth.md"
expect "notes/auth.md:5${T}marker${T}decide session length${T}todo-auth.md"
expect "notes/sub/billing.md${T}doc${T}billing${T}-"
expect "notes/sub/billing.md:2${T}open${T}invoices${T}-"
refuse 'login form'
refuse 'in fence'
refuse 'fenced example'
refuse 'hidden'
echo 'PASS: notes list documents, open boxes and markers, skipping ticked boxes, fences and hidden folders'

expect "notes/fences.md${T}doc${T}fences${T}todo-auth.md"
expect "notes/fences.md:6${T}marker${T}real one after${T}todo-auth.md"
refuse 'example inside'
echo 'PASS: a shorter fence inside a longer one stays inside it, and a citation may end a sentence'

run code EmailReminder
[ "$code" -eq 0 ] || fail "code subject exited $code"
expect "src/Reminders/EmailReminder.php${T}file${T}final class EmailReminder${T}-"
expect "src/Reminders/EmailReminder.php:4${T}marker${T}retry when the mailer is down${T}-"
expect "src/Reminders/EmailReminder.php:5${T}marker${T}handle timezones${T}-"
expect "src/Other.php${T}file${T}// queues an email_reminder later${T}-"
refuse 'Unrelated'
refuse 'vendor'
refuse 'project/'
refuse "src/Other.php:3"
echo 'PASS: a subject finds every spelling of itself, and ignored files and the board stay out'

run code src/Reminders
expect "src/Reminders/EmailReminder.php${T}file${T}final class EmailReminder${T}-"
expect "src/Reminders/EmailReminder.php:4${T}marker${T}retry when the mailer is down${T}-"
refuse 'Other.php'
echo 'PASS: a path scopes to what is under it'

run code NoSuchThing
[ "$code" -eq 0 ] && [ -z "$out" ] && grep -q 'nothing names NoSuchThing' "$TEMP/err" || fail 'an unknown subject should print nothing and say so'
echo 'PASS: an unknown subject is empty, and says so'

cat > "$TEMP/bin/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TEMP/gh-args"
[ -z "\${GH_FAIL:-}" ] || { echo 'HTTP 401' >&2; exit 1; }
printf '%s' '[{"number":12,"title":"Login\\tbroken","labels":[{"name":"bug"}],"url":"https://github.com/a/b/issues/12"},{"number":120,"title":"Dark mode","labels":[],"url":"https://github.com/a/b/issues/120"},{"number":7,"title":"Seven","labels":[],"url":"https://github.com/a/b/issues/7"},{"number":8,"title":"Eight","labels":[],"url":"https://github.com/a/b/issues/8"}]'
SH
chmod +x "$TEMP/bin/gh"
PATH="$TEMP/bin:$PATH" run gh label:bug
[ "$code" -eq 0 ] || fail "gh exited $code"
expect "gh#12${T}issue${T}Login broken [bug]${T}todo-auth.md"
expect "gh#120${T}issue${T}Dark mode${T}-"
grep -Fq -- '--search label:bug' "$TEMP/gh-args" || fail 'the search was not passed to gh'
grep -Fq -- '--state open' "$TEMP/gh-args" || fail 'gh was not limited to open issues'
expect "gh#7${T}issue${T}Seven${T}-"
expect "gh#8${T}issue${T}Eight${T}idea-other.md"
echo 'PASS: issues are listed with their labels, gh#12 is not gh#120, and another repository'"'"'s issue 7 is not this one'

GH_FAIL=1 PATH="$TEMP/bin:$PATH" run gh
[ "$code" -eq 2 ] || fail "a failed gh call exited $code, not 2"
run md missing
[ "$code" -eq 2 ] || fail "a missing folder exited $code, not 2"
run code
[ "$code" -eq 2 ] || fail "code with no argument exited $code, not 2"
run nope
[ "$code" -eq 2 ] || fail "an unknown source exited $code, not 2"
echo 'PASS: a failed gh call, a missing folder and bad arguments exit 2'

# last, because an unreadable file anywhere in the repo fails every code run too
mkdir -p "$TEMP/locked"
printf '# Secret\n- [ ] hidden work\n' > "$TEMP/locked/secret.md"
chmod 000 "$TEMP/locked/secret.md"
if [ -r "$TEMP/locked/secret.md" ]; then
  echo 'SKIP: running as a user who can read a mode-000 file'
else
  run md locked
  [ "$code" -eq 2 ] && grep -q 'cannot read locked/secret.md' "$TEMP/err" || fail "an unreadable note exited $code without naming it"
  echo 'PASS: an unreadable source fails with its path, instead of vanishing'
fi
