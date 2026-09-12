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

# --take never puts the changes on the stash stack. That stack is shared by
# every worktree of the repo, and git drops an entry only by its position,
# which another worktree's push can change between reading it and dropping
# it. So it builds the commit `git stash -u` would - index, worktree and
# untracked files - without storing it, and holds it under a ref of its own,
# so a crash leaves the changes findable and gc leaves them alone. `git stash
# apply --index` takes that commit like any stash, staged and unstaged apart.
carry=""
held="refs/take/$folder"
take_changes() {
  local head work index tree untracked scratch
  head=$(git -C "$mainpath" rev-parse HEAD)
  work=$(git -C "$mainpath" stash create "relocating to $n") || return 1
  if [ -z "$work" ]; then
    # untracked files only: the index and the worktree are both HEAD's
    index=$(git -C "$mainpath" commit-tree "$head^{tree}" -p "$head" -m "index on $base") || return 1
    work=$(git -C "$mainpath" commit-tree "$head^{tree}" -p "$head" -p "$index" -m "relocating to $n") || return 1
  fi
  if [ -n "$(git -C "$mainpath" ls-files --others --exclude-standard)" ]; then
    scratch=$(mktemp); rm -f "$scratch"
    tree=$(git -C "$mainpath" ls-files -z --others --exclude-standard \
      | GIT_INDEX_FILE="$scratch" git -C "$mainpath" update-index --add -z --stdin \
      && GIT_INDEX_FILE="$scratch" git -C "$mainpath" write-tree) || { rm -f "$scratch"; return 1; }
    rm -f "$scratch"
    untracked=$(git -C "$mainpath" commit-tree "$tree" -m "untracked files on $base") || return 1
    work=$(git -C "$mainpath" commit-tree "$work^{tree}" -p "$head" -p "$work^2" -p "$untracked" -m "relocating to $n") || return 1
  fi
  git -C "$mainpath" update-ref "$held" "$work" || return 1
  carry=$work
  git -C "$mainpath" reset -q --hard && git -C "$mainpath" clean -fdq
}

# Until the worktree exists, ANY exit - an abort below, or a command failing
# under set -e - puts the changes back on the default branch.
restore() {
  [ -n "$carry" ] || return 0
  if git -C "$mainpath" stash apply --index "$carry" > /dev/null; then
    git -C "$mainpath" update-ref -d "$held"
  else
    echo "could not put the changes back - they are kept as $held: git stash apply --index $held" >&2
  fi
  carry=""
}
trap restore EXIT
abort() { echo "$1" >&2; exit 1; }

# Two starts at once would both pass the claim check below before either had
# created its worktree, so check-and-create run under a lock on a file in the
# repository's common git dir, which every worktree shares. It is an flock on
# this shell's fd 9, taken through python3 because macOS has no flock(1): the
# kernel drops it once no process holds that fd, however they died, so
# there is never a stale lock to judge and take over. The file itself stays.
# It is let go the moment the worktree exists, before the slow setup.
command -v python3 >/dev/null || abort "python3 is needed to lock the worktree start, aborting"
lock="$(cd "$REPO_ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd)/project-worktree.lock"
exec 9>>"$lock"
# A child inherits fd 9 and holds the lock for as long as it lives. The one
# git that creates a claim keeps it: killed mid-creation, this shell leaves
# `worktree add` running, and the lock has to outlast it. fsmonitor is off for
# the add, so no daemon its checkout starts can inherit the lock. Every other
# git runs without it - a fetch can leave maintenance or a credential daemon
# behind long after it returns, and none of those can claim anything.
git() {
  case " $* " in
    *" worktree add "*) command git -c core.fsmonitor=false "$@" ;;
    *) command git "$@" 9>&- ;;
  esac
}
python3 -c '
import fcntl, sys, time
end = time.time() + float(sys.argv[1])
while True:
    try:
        fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except BlockingIOError:
        if time.time() >= end:
            sys.exit(1)
        time.sleep(0.2)
' "${PROJECT_LOCK_WAIT:-60}" || abort "another worktree start has held $lock for ${PROJECT_LOCK_WAIT:-60}s, aborting"

# One live worktree per ticket. The board matches a claim on the name after
# the status word, across + joins, so todo-a+todo-b is refused while any
# worktree holds todo-a - or holds spike-a, opened before it became a todo.
claims=$(git -C "$mainpath" worktree list --porcelain | awk -v base="$base" -v want="$n" -v statuses="idea spike todo issue done reject spec list" '
  function slug(id,   s) {
    s = id; sub(/-.*/, "", s)
    if (id !~ /-/ || index(" " statuses " ", " " s " ") == 0) return ""
    sub(/^[^-]*-/, "", id); return id
  }
  BEGIN { k = split(want, mine, "+"); for (i = 1; i <= k; i++) { s = slug(mine[i]); if (s != "") ours[s] = mine[i] } }
  /^worktree / { p = substr($0, 10) }
  /^branch refs\/heads\// {
    b = substr($0, 19); if (b == base) next
    k = split(b, part, "+")
    for (i = 1; i <= k; i++) { s = slug(part[i]); if (s in ours) print ours[s] " is already claimed by " b " at " p }
  }')
[ -z "$claims" ] || abort "$claims - resume it there (project.sh resume ${n%%+*}), or remove that worktree first"

git -C "$mainpath" show-ref --verify --quiet "refs/heads/$n" \
  && abort "branch $n already exists, aborting - resume there or pick a different id"
dest="$WORKTREES/$folder"
[ -e "$dest" ] && abort "$dest already exists, aborting"

dirty=$(git -C "$mainpath" status --porcelain)
if [ -n "$dirty" ]; then
  if [ -n "$take" ]; then
    git -C "$mainpath" show-ref --verify --quiet "$held" \
      && abort "$held already holds changes from an earlier --take - git stash apply --index $held, then git update-ref -d $held"
    take_changes || abort "could not set the changes aside, aborting"
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

mkdir -p "$WORKTREES" || abort "cannot create $WORKTREES, aborting"
git -C "$mainpath" worktree add "$dest" -b "$n" "$base" || abort "worktree add failed, aborting"
trap - EXIT
# the claim is live now, so the next start waiting on the lock will see it
exec 9>&-

# Herd serves every folder directly under a parked path as <folder>.test, so
# there is no server to start. Without Herd there is no URL to promise.
url=""
command -v herd >/dev/null 2>&1 && url="http://$folder.test"

# past this point the worktree is real and staying - the git state is
# already committed to, so nothing below unwinds it, and abort() is never
# called again from here down.
conflict=""
if [ -n "$carry" ]; then
  if git -C "$dest" stash apply --index "$carry" >&2; then
    git -C "$mainpath" update-ref -d "$held"
  else
    conflict=1
    echo "applying the changes conflicted - resolve inside $dest (they are also kept as $held)" >&2
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
  echo "skipping automated setup because of the conflict above - resolve it, then finish setup by hand inside $dest" >&2
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
