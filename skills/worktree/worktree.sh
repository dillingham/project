#!/usr/bin/env bash
# worktree.sh - start work on a ticket: a fresh git worktree off the default
# branch, set up for whatever the repo is built with (composer, .env, artisan,
# npm/pnpm/yarn/bun), so the path it prints is runnable, not just checked out.
# Usage: worktree.sh <id> [--take]
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repository" >&2; exit 1; }
# every repo's worktrees share one folder; ~/Worktrees is what Herd parks
WORKTREES="${PROJECT_WORKTREES:-$HOME/Worktrees}"

n="${1:?usage: worktree.sh <id> [--take]}"
take=""; [ "${2:-}" = "--take" ] && take=1

# the branch every worktree starts from: origin's HEAD when there is a remote,
# else main, else master
base=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true); base=${base#origin/}
if [ -z "$base" ]; then
  for b in main master; do
    git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$b" && { base=$b; break; }
  done
fi
[ -n "$base" ] || { echo "cannot tell the default branch - no origin/HEAD, main or master" >&2; exit 1; }

mainpath=$(git -C "$REPO_ROOT" worktree list --porcelain | awk -v b="refs/heads/$base" '/^worktree /{p=substr($0,10)} $0=="branch " b {print p; exit}')
[ -n "$mainpath" ] || { echo "no worktree has $base checked out" >&2; exit 1; }

# the worktrees folder is shared by every repo, so the folder carries the repo
# name - the branch does not need to, since refs are already scoped per repo
reponame=$(basename "$mainpath")

# Refuse a bad name before anything is created, not halfway through setup.
# The branch keeps the id verbatim, `+` joins included - the board splits
# claims on it. The folder doubles as a hostname under Herd, where `+` is not
# a legal character and a label caps at 63, so a joined id names its folder
# after its FIRST id: the folder only has to be unique and typable.
git check-ref-format --branch "$n" >/dev/null 2>&1 || { echo "not a usable branch name: $n" >&2; exit 1; }
folder=$(printf '%s-%s' "$reponame" "${n%%+*}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | tr -s '-')
folder=${folder%-}
[ "${#folder}" -le 63 ] || { echo "folder name $folder is ${#folder} characters; a hostname label caps at 63 - pick a shorter id" >&2; exit 1; }

# stash is one stack shared by the whole repo, not per-worktree, so a
# concurrent `git stash` anywhere else can move what "top of stack" means
# between our push and our pop. Apply by the sha the push handed us
# (content-addressed, survives being buried) and drop only the matching
# entry - never a blind pop, which would risk taking someone else's stash.
unstash() { git -C "$1" stash apply "$2" \
  && git -C "$1" stash drop "$(git -C "$1" stash list --format='%H %gd' | awk -v s="$2" '$1==s{print $2; exit}')"; }

# abort() undoes the stash (if we took one) before leaving, so a failed
# later step never strands the default branch's own changes on the stash stack
stashed=""
abort() { echo "$1" >&2; [ -n "$stashed" ] && unstash "$mainpath" "$stashed"; exit 1; }

git -C "$mainpath" show-ref --verify --quiet "refs/heads/$n" \
  && abort "branch $n already exists, aborting - resume there or pick a different id"
dest="$WORKTREES/$folder"
[ -e "$dest" ] && abort "$dest already exists, aborting"

dirty=$(git -C "$mainpath" status --porcelain)
if [ -n "$dirty" ]; then
  if [ -n "$take" ]; then
    git -C "$mainpath" stash push -u -m "relocating to $n" >&2 || abort "stash failed, aborting"
    stashed=$(git -C "$mainpath" rev-parse refs/stash)
  else
    echo "$base is not clean, aborting:" >&2
    echo "$dirty" >&2
    echo "pass --take to relocate these changes into the new worktree instead of aborting" >&2
    exit 1
  fi
fi

if git -C "$mainpath" remote get-url origin >/dev/null 2>&1; then
  git -C "$mainpath" fetch origin "$base" || abort "fetch origin $base failed, aborting"
  git -C "$mainpath" merge --ff-only "origin/$base" \
    || abort "$base has diverged from origin/$base, aborting - resolve manually"
fi

mkdir -p "$WORKTREES"
git -C "$mainpath" worktree add "$dest" -b "$n" "$base" || abort "worktree add failed, aborting"

# Herd serves every folder directly under a parked path as <folder>.test, so
# there is no server to start. Without Herd there is no URL to promise.
url=""
command -v herd >/dev/null 2>&1 && url="http://$folder.test"

# past this point the worktree is real and staying - the git state is
# already committed to, so nothing below unwinds it. abort() (which would
# re-touch the stash) is never called again from here down.
conflict=""
if [ -n "$stashed" ]; then
  if unstash "$dest" "$stashed"; then
    stashed=""
  else
    conflict=1
    echo "stash pop conflicted - resolve inside $dest (git stash list still has it)" >&2
  fi
fi

# each step names its own failure instead of one generic message
step() { local what="$1"; shift; "$@" || { echo "$what failed - finish setup manually inside $dest" >&2; exit 1; }; }

# everything gitignored that `git worktree add` could not bring along, for
# whichever of these the repo actually uses. --force/--no-interaction
# everywhere so nothing stalls on a prompt that only resolves by accident
# because an agent's shell is not a tty (a real terminal would hang on it).
setup() (
  cd "$dest"
  # Herd (or other tooling) sources the original checkout's .env into
  # ad-hoc shells, so composer/artisan/npm here can inherit its APP_KEY,
  # APP_URL, DB_* etc. as real env vars - and env vars win over the new
  # worktree's own .env (PHP dotenv never overwrites an already-set var).
  # Unset every key .env.example declares so this worktree's .env is what
  # actually takes effect.
  if [ -f .env.example ]; then
    for envkey in $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env.example | cut -d= -f1); do
      unset "$envkey"
    done
  fi
  [ ! -f composer.json ] || step "composer install" composer install --no-interaction
  [ ! -f .env.example ] || [ -f .env ] || step "copying .env.example to .env" cp .env.example .env
  if [ -f artisan ]; then
    # APP_URL from .env.example is a placeholder - point it at the domain
    # Herd is actually serving this worktree on, the one printed below
    [ -z "$url" ] || step "writing APP_URL into .env" \
      php -r "file_put_contents('.env', preg_replace('/^APP_URL=.*/m', 'APP_URL=$url', file_get_contents('.env')));"
    step "key:generate" php artisan key:generate --ansi
    # the sqlite file is gitignored, so a fresh worktree never has one - touch
    # it rather than lean on migrate's interactive-only auto-create prompt
    if grep -qE '^DB_CONNECTION=sqlite' .env 2>/dev/null; then touch database/database.sqlite; fi
    step "migrate --seed" php artisan migrate --seed --force
  fi
  if [ -f package.json ]; then
    pm=npm
    [ ! -f pnpm-lock.yaml ] || pm=pnpm
    [ ! -f yarn.lock ] || pm=yarn
    { [ ! -f bun.lockb ] && [ ! -f bun.lock ]; } || pm=bun
    step "$pm install" "$pm" install
    if grep -qE '"build"[[:space:]]*:' package.json; then step "$pm run build" "$pm" run build; fi
  fi
)

setup_failed=""
if [ -n "$conflict" ]; then
  echo "skipping automated setup because of the stash conflict above - resolve it, then finish setup by hand inside $dest" >&2
  setup_failed=1
else
  setup || setup_failed=1
fi

# always print the path - the worktree exists whether or not setup finished,
# and a caller with only an abort message has no way to find it
echo "$dest"
[ -z "$url" ] || echo "$url"
[ -n "$setup_failed" ] && exit 1
exit 0
