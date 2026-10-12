#!/usr/bin/env bash
# sandbox.sh in throwaway repositories: which PHP it picks, which locked
# packages it builds from git, the profile block it writes once, and that it
# leaves a machine with no proxy alone.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sandbox.sh"
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/sandbox-test.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT
passed=0

repo() {
  passed=$((passed+1))
  R="$TEMP/repo $passed"
  mkdir -p "$R"
  git -C "$R" init -q -b main
}
run() { (cd "$R" && HOME="$TEMP/home $passed" TMPDIR="$TEMP" bash "$SCRIPT" "$@") > "$TEMP/output" 2>&1; }
fail() { echo "FAIL: $1" >&2; cat "$TEMP/output" >&2; exit 1; }
ok() { printf 'PASS: %s\n' "$1"; }

repo
mkdir -p "$R/.github/workflows"
printf "steps:\n  - with:\n      php-version: '8.3'\n" > "$R/.github/workflows/lint.yml"
printf "steps:\n  - with:\n      php-version: \"8.5\"\n" > "$R/.github/workflows/tests.yml"
run php-version || fail 'php-version exited non-zero'
[ "$(cat "$TEMP/output")" = 8.5 ] || fail 'the highest CI pin was not picked'
ok 'the PHP version is the highest php-version pinned in CI'

repo
mkdir -p "$R/.github/workflows"
printf "      php-version: '8.5'\n" > "$R/.github/workflows/tests.yml"
(cd "$R" && SANDBOX_PHP=8.4 bash "$SCRIPT" php-version) > "$TEMP/output" 2>&1 || fail 'php-version exited non-zero'
[ "$(cat "$TEMP/output")" = 8.4 ] || fail 'SANDBOX_PHP did not override the CI pin'
ok 'SANDBOX_PHP overrides the CI pin'

repo
cat > "$R/composer.lock" <<'JSON'
{
  "packages": [
    {"name": "laravel/framework", "source": {"type": "git", "url": "https://github.com/laravel/framework.git"}, "dist": {"type": "zip", "url": "https://api.github.com/repos/laravel/framework/zipball/aaa111"}}
  ],
  "packages-dev": [
    {"name": "phpstan/phpstan", "source": null, "dist": {"type": "zip", "url": "https://api.github.com/repos/phpstan/phpstan/zipball/e285254e60f33c21902efef4a926ca0987c06804"}},
    {"name": "acme/private", "dist": {"type": "zip", "url": "https://repo.acme.test/dist/private.zip"}}
  ]
}
JSON
run dist-only || fail 'dist-only exited non-zero'
[ "$(cat "$TEMP/output")" = 'phpstan/phpstan https://api.github.com/repos/phpstan/phpstan/zipball/e285254e60f33c21902efef4a926ca0987c06804 phpstan/phpstan e285254e60f33c21902efef4a926ca0987c06804' ] || fail 'dist-only did not list exactly the GitHub-only package'
ok 'only a package with no source and a GitHub zipball is built from git'

repo
mkdir -p "$TEMP/home $passed"
echo 'export KEEP=1' > "$TEMP/home $passed/.bashrc"
run profile || fail 'profile exited non-zero'
run profile || fail 'profile exited non-zero the second time'
[ "$(grep -c '>>> project:sandbox >>>' "$TEMP/home $passed/.bashrc")" = 1 ] || fail 'a second run did not replace the block'
grep -q '^export NODE_USE_ENV_PROXY=1$' "$TEMP/home $passed/.bashrc" || fail 'NODE_USE_ENV_PROXY is missing'
grep -q '^export KEEP=1$' "$TEMP/home $passed/.bashrc" || fail 'the existing profile was not kept'
[ ! -e "$TEMP/home $passed/.zshrc" ] || fail 'a profile the user does not have was created'
ok 'the profile block is written once, beside what was there'

repo
mkdir -p "$TEMP/home $passed"
(cd "$R" && env -u HTTPS_PROXY -u https_proxy HOME="$TEMP/home $passed" bash "$SCRIPT") > "$TEMP/output" 2>&1 || fail 'no proxy exited non-zero'
grep -q 'nothing to do' "$TEMP/output" || fail 'no proxy did not say so'
[ -z "$(ls -A "$TEMP/home $passed")" ] || fail 'no proxy still wrote to the home folder'
ok 'a machine with no proxy is left alone'

mkdir -p "$TEMP/not a repo"
(cd "$TEMP/not a repo" && bash "$SCRIPT" php-version) > "$TEMP/output" 2>&1 && fail 'outside a repository did not fail'
grep -q 'not inside a git repository' "$TEMP/output" || fail 'outside a repository did not say why'
ok 'outside a repository it refuses and says why'

repo
run nonsense && fail 'an unknown command did not fail'
grep -q usage "$TEMP/output" || fail 'an unknown command did not print usage'
ok 'an unknown command prints usage'

echo "sandbox: all passed"
