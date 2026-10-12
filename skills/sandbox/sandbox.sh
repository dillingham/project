#!/usr/bin/env bash
# Prepares a cloud sandbox - a container whose egress goes through an
# allowlisting proxy - so a repository's own setup runs there unchanged:
# the PHP its CI uses, Composer installing over git, Node fetching through
# the proxy. Then sets up the checkout it is called from.
#
#   sandbox.sh              prepare the machine, then set up this checkout
#   sandbox.sh machine      prepare the machine only
#   sandbox.sh php-version  the PHP version this checkout wants
#   sandbox.sh dist-only    locked packages Composer can only fetch as a GitHub zip
#   sandbox.sh profile      write the shell profile block only
set -euo pipefail

cmd="${1:-all}"
case "$cmd" in all|machine|php-version|dist-only|profile) ;; *) echo "usage: sandbox.sh [machine|php-version|dist-only|profile]" >&2; exit 2 ;; esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repository - run this from the checkout to set up" >&2; exit 1; }
work="${TMPDIR:-/tmp}/project-sandbox"
mkdir -p "$work"
ca=""
for candidate in /root/.ccr/ca-bundle.crt "${SSL_CERT_FILE:-}"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then ca="$candidate"; break; fi
done
sudo=""
[ "$(id -u)" = 0 ] || sudo=sudo
say() { printf '==> %s\n' "$*" >&2; }
step() { local what="$1"; shift; "$@" || { echo "$what failed - finish it by hand in $root" >&2; exit 1; }; }

# CI's setup-php pin is what the repo is tested on, so it wins; otherwise the
# highest minimum any locked package demands.
php_version() {
  if [ -n "${SANDBOX_PHP:-}" ]; then echo "$SANDBOX_PHP"; return; fi
  local version=""
  if [ -d "$root/.github/workflows" ]; then
    version=$(grep -rhoE "php-version:[[:space:]]*['\"]?[0-9]+\.[0-9]+" "$root/.github/workflows" | grep -oE '[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
  fi
  if [ -z "$version" ] && [ -f "$root/composer.lock" ] && command -v composer >/dev/null; then
    version=$(cd "$root" && composer check-platform-reqs --lock 2>&1 | grep -oE 'requires php \(>= ?[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
  fi
  echo "${version:-8.4}"
}

# A package with no source in the lock, only a GitHub zipball (phpstan/phpstan
# is the usual one), cannot install over git: name, dist url, owner/repo, ref.
dist_only() {
  [ -f "$root/composer.lock" ] || return 0
  python3 -I - "$root/composer.lock" <<'PY'
import json, re, sys
lock = json.load(open(sys.argv[1]))
for package in lock.get('packages', []) + lock.get('packages-dev', []):
    if package.get('source'):
        continue
    dist = package.get('dist') or {}
    match = re.match(r'https://api\.github\.com/repos/([^/]+/[^/]+)/zipball/(\w+)$', dist.get('url', ''))
    if match:
        print(package['name'], dist['url'], match.group(1), match.group(2))
PY
}

# Every later shell - the repo's own setup, worktree.sh, a test run - needs
# these, so they go in the profile rather than this process alone.
profile() {
  local block="# >>> project:sandbox >>>"$'\n'
  [ "$(id -u)" != 0 ] || block+="export COMPOSER_ALLOW_SUPERUSER=1"$'\n'
  block+="export NODE_USE_ENV_PROXY=1"$'\n'
  [ -z "$ca" ] || block+="export NODE_EXTRA_CA_CERTS=$ca"$'\n'
  block+="# <<< project:sandbox <<<"
  local file
  for file in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    [ -f "$file" ] || [ "$file" = "$HOME/.bashrc" ] || continue
    touch "$file"
    python3 -I - "$file" "$block" <<'PY'
import re, sys
path, block = sys.argv[1], sys.argv[2]
text = open(path).read()
text = re.sub(r'\n?# >>> project:sandbox >>>.*?# <<< project:sandbox <<<\n?', '\n', text, flags=re.S)
open(path, 'w').write(text.rstrip('\n') + '\n\n' + block + '\n')
PY
  done
}

php_satisfied() {
  command -v php >/dev/null || return 1
  [ -f "$root/composer.lock" ] || return 0
  (cd "$root" && composer check-platform-reqs --lock >/dev/null 2>&1)
}

# The ondrej PPA is refused by the proxy; GitHub release assets are not, and
# shivammathur/php-builder is the build CI's setup-php installs.
install_php() {
  local version="$1" ubuntu
  ubuntu=$( . /etc/os-release 2>/dev/null && [ "${ID:-}" = ubuntu ] && echo "${VERSION_ID:-}" ) || true
  [ -n "$ubuntu" ] || { echo "PHP $version is needed but this is not Ubuntu - install it by hand" >&2; exit 1; }
  say "installing PHP $version from shivammathur/php-builder (ubuntu $ubuntu)"
  step "downloading PHP $version" curl -fsSL -o "$work/php.tar.zst" "https://github.com/shivammathur/php-builder/releases/download/$version/php_$version%2Bubuntu$ubuntu.tar.zst"
  if command -v zstd >/dev/null; then
    zstd -dqf "$work/php.tar.zst" -o "$work/php.tar"
  else
    python3 -c 'import zstandard' 2>/dev/null || pip install -q --break-system-packages zstandard >/dev/null 2>&1 || pip install -q zstandard >/dev/null 2>&1
    python3 -I -c 'import sys, zstandard; zstandard.ZstdDecompressor().copy_stream(open(sys.argv[1], "rb"), open(sys.argv[2], "wb"))' "$work/php.tar.zst" "$work/php.tar"
  fi
  $sudo tar -xf "$work/php.tar" -C / ./etc/php ./usr/lib/php ./usr/bin
  $sudo ln -sf "/usr/bin/php$version" /usr/local/bin/php
  hash -r
  # The build ships every extension. Disable the ones whose system library is
  # missing, which otherwise warn on every php call, and xdebug, which is slow.
  local confd="/etc/php/$version/cli/conf.d" ext ini
  for ini in "$confd"/*-xdebug.ini; do [ ! -e "$ini" ] || $sudo mv "$ini" "$ini.disabled"; done
  for ext in $(php -v 2>&1 | grep -oE "Unable to load dynamic library '[a-z0-9_]+" | sed "s/.*'//" | sort -u); do
    for ini in "$confd"/*-"$ext".ini; do [ ! -e "$ini" ] || $sudo mv "$ini" "$ini.disabled"; done
  done
  php -v | head -1 >&2
}

# GitHub's zip downloads are refused for repos not attached to the session,
# while anonymous git reads are served, so Composer installs from source. A
# dist-only package gets its zip built from git and placed where Composer
# looks before downloading: its cache, keyed by sha1 of the dist url.
composer_over_git() {
  composer config --global preferred-install source
  local cache name url repo ref key dest src
  cache=$(composer config --global cache-files-dir)
  while read -r name url repo ref; do
    key=$(printf %s "$url" | sha1sum | cut -d' ' -f1)
    dest="$cache/$name/$key.zip"
    [ ! -f "$dest" ] || continue
    say "building $name from git at ${ref:0:7}"
    src="$work/src-${name//\//-}"
    rm -rf "$src" && mkdir -p "$src" "$(dirname "$dest")"
    git -C "$src" init -q
    step "fetching $name" git -C "$src" fetch -q --depth 1 "https://github.com/$repo" "$ref"
    git -C "$src" archive --format=zip --prefix="${repo//\//-}-${ref:0:7}/" -o "$dest" FETCH_HEAD
  done < <(dist_only)
}

case "$cmd" in
  php-version) php_version; exit 0 ;;
  dist-only) dist_only; exit 0 ;;
  profile) profile; exit 0 ;;
esac

if [ -z "${HTTPS_PROXY:-${https_proxy:-}}" ]; then
  echo "no HTTPS_PROXY - not a proxied sandbox, nothing to do"
  exit 0
fi

say "shell profile: COMPOSER_ALLOW_SUPERUSER, NODE_USE_ENV_PROXY, NODE_EXTRA_CA_CERTS"
profile
[ "$(id -u)" != 0 ] || export COMPOSER_ALLOW_SUPERUSER=1
export NODE_USE_ENV_PROXY=1
[ -z "$ca" ] || export NODE_EXTRA_CA_CERTS="$ca"
# A shell that started before the profile changed - an agent session's own -
# never sees the block, so say what to prefix for the rest of it.
session_env="export NODE_USE_ENV_PROXY=1${ca:+ NODE_EXTRA_CA_CERTS=$ca}"
[ "$(id -u)" != 0 ] || session_env+=" COMPOSER_ALLOW_SUPERUSER=1"
trap 'echo "shells already running need: $session_env" >&2' EXIT

if [ -f "$root/composer.json" ]; then
  if php_satisfied; then
    say "PHP $(php -r 'echo PHP_VERSION;') satisfies the lock file"
  else
    install_php "$(php_version)"
  fi
  say "Composer: install from source, seed dist-only packages"
  composer_over_git
fi

[ "$cmd" = all ] || { echo "machine ready"; exit 0; }

# The same chain worktree.sh runs, made safe to repeat: this is a checkout
# that may already be half set up, not a fresh worktree.
cd "$root"
[ ! -f composer.json ] || step "composer install" composer install --no-interaction
[ ! -f .env.example ] || [ -f .env ] || step "copying .env.example to .env" cp .env.example .env
if [ -f artisan ]; then
  grep -qE '^APP_KEY=.+' .env 2>/dev/null || step "key:generate" php artisan key:generate --ansi
  seed=""
  if grep -qE '^DB_CONNECTION=sqlite' .env 2>/dev/null && [ ! -f database/database.sqlite ]; then
    touch database/database.sqlite
    seed=--seed
  fi
  step "migrate" php artisan migrate --force $seed
fi
if [ -f package.json ]; then
  pm=npm
  [ ! -f pnpm-lock.yaml ] || pm=pnpm
  [ ! -f yarn.lock ] || pm=yarn
  { [ ! -f bun.lockb ] && [ ! -f bun.lock ]; } || pm=bun
  step "$pm install" "$pm" install
  if grep -qE '"build"[[:space:]]*:' package.json; then step "$pm run build" "$pm" run build; fi
fi
echo "ready: $root"
