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

printf '# Auth\n\nPriority: groom\n\n## Todo\n\nBackfilled from `notes/auth.md` and gh#12.\n' > "$TEMP/project/todo-auth.md"
printf '# Other\n\nPriority: groom\n\n## Idea\n\nSee `xnotes/sub/billing.md` and gh#1200.\n' > "$TEMP/project/idea-other.md"
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
refuse 'fence'
refuse 'hidden'
echo 'PASS: notes list documents, open boxes and markers, skipping ticked boxes, fences and hidden folders'

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
printf '%s' '[{"number":12,"title":"Login\\tbroken","labels":[{"name":"bug"}],"url":"https://github.com/a/b/issues/12"},{"number":120,"title":"Dark mode","labels":[],"url":"https://github.com/a/b/issues/120"}]'
SH
chmod +x "$TEMP/bin/gh"
PATH="$TEMP/bin:$PATH" run gh label:bug
[ "$code" -eq 0 ] || fail "gh exited $code"
expect "gh#12${T}issue${T}Login broken [bug]${T}todo-auth.md"
expect "gh#120${T}issue${T}Dark mode${T}-"
grep -Fq -- '--search label:bug' "$TEMP/gh-args" || fail 'the search was not passed to gh'
grep -Fq -- '--state open' "$TEMP/gh-args" || fail 'gh was not limited to open issues'
echo 'PASS: issues are listed with their labels, and gh#12 is not gh#120'

GH_FAIL=1 PATH="$TEMP/bin:$PATH" run gh
[ "$code" -eq 2 ] || fail "a failed gh call exited $code, not 2"
run md missing
[ "$code" -eq 2 ] || fail "a missing folder exited $code, not 2"
run code
[ "$code" -eq 2 ] || fail "code with no argument exited $code, not 2"
run nope
[ "$code" -eq 2 ] || fail "an unknown source exited $code, not 2"
echo 'PASS: a failed gh call, a missing folder and bad arguments exit 2'
