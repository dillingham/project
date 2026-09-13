#!/usr/bin/env bash
# project.sh - read and move the board in project/
# Output is tab-separated: priority, status, id, created, idle, title, spec
set -euo pipefail

# the board belongs to the repo you are standing in, not to wherever this script is installed
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIR="$ROOT/project"
# a worktree on the default branch is not a claim; origin's HEAD names it, else main, else master
MAIN=$(git -C "$ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true); MAIN=${MAIN#origin/}
if [ -z "$MAIN" ]; then
  MAIN=main
  git -C "$ROOT" show-ref --verify --quiet refs/heads/main 2>/dev/null \
    || ! git -C "$ROOT" show-ref --verify --quiet refs/heads/master 2>/dev/null || MAIN=master
fi
STATUSES="idea spike todo issue done reject spec list"
STALE_DAYS=${PROJECT_STALE_DAYS:-30}
NOW=$(date +%s)
SEP=$(printf '\037')
# awk here has no strftime, and a date(1) per ticket is a fork per ticket -
# see idea-board-git-walk-at-scale.md. Pass the offset in and do the maths once.
TZ_OFFSET=$(date +%z)
TZ_OFFSET=$(( ${TZ_OFFSET:0:1}1 * (10#${TZ_OFFSET:1:2} * 3600 + 10#${TZ_OFFSET:3:2} * 60) ))

usage() {
  cat <<'USAGE'
project.sh - the board in project/. Every file is {status}-{name}.md.

  project.sh                 this menu, then what to pick up
  project.sh next            critical + high, else the best available, plus one to triage
  project.sh open            every open ticket, priority order
  project.sh all             everything, including done and reject
  project.sh groom           untriaged: unjudged, unblocked, not a bucket
  project.sh blocked         waiting on another ticket, and on what
  project.sh list            holding pens: grouped one-liners, promote items out
  project.sh unblocked       blocked on something that already shipped
  project.sh claimed         live worktrees, by the branch that claims its tickets
  project.sh resume [id]     where a claimed ticket stands: worktree, commits, newest checkpoint
  project.sh board           counts by status and by priority
  project.sh <status>        one status: idea spike todo issue done reject spec
  project.sh spec <name>     everything filed against spec-<name>.md
  project.sh find <term>     search titles and bodies
  project.sh show <id>       print one file
  project.sh show <status>   print the newest file at that status
  project.sh log <id>        its commit trail: hash, date, subject (renames followed)
  project.sh trail <id>      commits carrying Branch: <stable name>, and any PR for that head
  project.sh changelog       what landed, newest first, linked to its ticket
  project.sh check           broken links, anchors and bare ticket names in project/,
                             a ticket's current section left empty, and code citing
                             a project/ or docs/ file that is gone
  project.sh new <status> <name>   scaffold with the header
  project.sh move <status> <filename> [--dry-run]   rename and update references
  project.sh mv <id> <status> [--dry-run]          compatibility alias

Starting work on a ticket is the worktree skill, not this script:
  /project:worktree <id> [--take]

Columns: priority  status  id  created  idle  title  spec
created is when the file was first seen under its CURRENT status, so a status
change restamps it. An idle column ending in STALE means the ticket sorted up
one priority level. next, open, groom and board rank by priority; every listing
(one status, all, find, spec) is newest first.
USAGE
}

# one stat + one git + one awk, rather than two forks per file
rows() {
  local statf gitf lsf blockf branchf
  statf=$(mktemp); gitf=$(mktemp); lsf=$(mktemp); blockf=$(mktemp); branchf=$(mktemp)
  trap 'rm -f "$statf" "$gitf" "$lsf" "$blockf" "$branchf"' RETURN
  stat -f '%N|%m|%B' "$DIR"/*.md 2>/dev/null > "$statf" \
    || stat -c '%n|%Y|%W' "$DIR"/*.md 2>/dev/null > "$statf"
  # commit epoch followed by the paths it touched; empty when nothing is tracked
  git -C "$DIR/.." log --format='@%at' --name-only -- project 2>/dev/null > "$gitf" || true
  # gathered here, quoted, rather than as shell commands inside awk, where a
  # path with a space in it splits into two arguments
  ls "$DIR" > "$lsf" 2>/dev/null || true
  grep -H "^Blocked: " "$DIR"/*.md > "$blockf" 2>/dev/null || true
  git -C "$DIR/.." worktree list --porcelain 2>/dev/null | grep "^branch " > "$branchf" || true

  awk -F'|' -v main="$MAIN" -v now="$NOW" -v stale="$STALE_DAYS" -v gitf="$gitf" -v lsf="$lsf" -v blockf="$blockf" -v branchf="$branchf" -v statuses="$STATUSES" -v tzoff="$TZ_OFFSET" '
    # civil-from-days, because this awk has no strftime
    function stamp(t,   z, era, doe, yoe, y, doy, mp, d, m, secs) {
      t = t + tzoff
      secs = t % 86400
      z = int(t / 86400) + 719468
      era = int(z / 146097)
      doe = z - era * 146097
      yoe = int((doe - int(doe/1460) + int(doe/36524) - int(doe/146096)) / 365)
      y = yoe + era * 400
      doy = doe - (365*yoe + int(yoe/4) - int(yoe/100))
      mp = int((5*doy + 2) / 153)
      d = doy - int((153*mp + 2) / 5) + 1
      m = mp + (mp < 10 ? 3 : -9)
      if (m <= 2) { y++ }
      return sprintf("%04d-%02d-%02d %02d:%02d", y, m, d, int(secs/3600), int((secs%3600)/60))
    }
    function rank(p) { return p=="critical"?0 : p=="high"?1 : p=="medium"?2 : p=="low"?3 : p=="groom"?4 : 5 }
    # the name after the status word, which a status change leaves alone;
    # empty for anything that does not lead with a status
    function slug(id,   s) {
      s = id; sub(/-.*/, "", s)
      if (id !~ /-/ || index(" " statuses " ", " " s " ") == 0) return ""
      sub(/^[^-]*-/, "", id); return id
    }
    BEGIN {
      OFS="\037"
      # every ticket that exists, and the reverse index of Blocked: lines
      while ((getline f < lsf) > 0) { sub(/\.md$/, "", f); exists[f] = 1 }
      while ((getline g < blockf) > 0) {
        split(g, gp, ":Blocked: ")
        n = split(gp[1], pp, "/"); who = pp[n]; sub(/\.md$/, "", who)
        on = gp[2]; sub(/ .*/, "", on); sub(/\.md$/, "", on)
        blocks[on] = blocks[on] + 1
      }

      # a ticket with a live worktree of its own name is claimed - no header
      # to write or commit, git worktree list is already shared and instant.
      # related tickets sharing one branch join their ids with +, so a
      # branch claims every id it names, not just the whole string. A live
      # the branch is itself the ticket stable name (its status word was
      # dropped when the worktree opened), so it is matched here verbatim,
      # never re-parsed - which is also why a spike that becomes a todo
      # mid-work stays claimed by the branch opened for the spike
      while ((getline wl < branchf) > 0) {
        b = wl; sub(/^branch refs\/heads\//, "", b)
        if (b != main) {
          wn = split(b, wp, "+")
          for (wi = 1; wi <= wn; wi++) { if (wp[wi] != "") claimed[wp[wi]] = 1 }
        }
      }

      while ((getline l < gitf) > 0) {
        if (l ~ /^@/) { t = substr(l,2)+0; continue }
        if (l == "") continue
        n = split(l, pp, "/"); b = pp[n]
        if (!(b in last)) last[b] = t      # log is newest-first
        first[b] = t                        # keeps overwriting down to the oldest
      }
    }
    {
      path=$1; mt=$2+0; bt=$3+0
      n=split(path, pp, "/"); base=pp[n]; sub(/\.md$/, "", base)
      st = base; sub(/-.*/, "", st)
      # the status is the first word, so a file that does not start with one is
      # not board work - a map like index.md is not a ticket
      if (index(" " statuses " ", " " st " ") == 0) next
      claim = (slug(base) in claimed)

      pri=""; spec=""; title=""; desc=""; blocked=""
      while ((getline l < path) > 0) {
        if (title=="" && substr(l,1,2)=="# ")       title = substr(l,3)
        else if (substr(l,1,10)=="Priority: ")      pri   = substr(l,11)
        else if (substr(l,1,6)=="Spec: ")           spec  = substr(l,7)
        else if (substr(l,1,13)=="Description: ")   desc  = substr(l,14)
        else if (substr(l,1,9)=="Blocked: ")         blocked = substr(l,10)

        if (title!="" && pri!="" && spec!="" && desc!="" && blocked!="") break
      }
      # Description is the uniform header on every file; the H1 is the short name.
      # Show the description when there is one - on a spec the H1 is one word.
      if (desc!="") title = desc
      # the output separator must never appear in the data. Nothing in project/
      # carries a tab today, and a stray one would silently split a column.
      gsub(/\t/, " ", title); gsub(/\t/, " ", spec)
      close(path)
      if (pri=="") pri="none"

      f = (base".md" in first) ? first[base".md"] : (bt>0 ? bt : mt)
      m = (base".md" in last)  ? last[base".md"]  : mt
      created = stamp(f); idle = int((now-m)/86400)

      r = rank(pri); bump=""
      # groom is untriaged, so staleness cannot promote it - triage it first
      # a claimed ticket also skips the bump: idle here just means the file
      # itself is untouched, which is normal while the real work happens on
      # the worktree branch instead
      if (st!="done" && st!="reject" && st!="spec" && pri!="groom" && blocked=="" && !claim && idle>=stale && r>0) { r=r-1; bump=" STALE" }
      # a blocked or already-claimed ticket cannot be started, so neither
      # competes for attention
      if (blocked!="") r = 8
      if (claim) r = 8
      flag = ""
      if (claim) { flag = " CLAIMED" }
      if (blocked != "") {
        on = blocked; sub(/ .*/, "", on); sub(/\.md$/, "", on)
        # a block whose blocker already shipped is stale, and nobody notices
        # the blocker shipped, or the ticket it names no longer exists
        lifted = (on ~ /^(done|reject)-/) || !(on in exists)
        flag = flag (lifted ? " UNBLOCKED?" : " BLOCKED")
      }
      if (base in blocks) { flag = flag " BLOCKS:" blocks[base] }
      print r, pri, st, base, title, spec, created, idle"d" bump flag
    }
  ' "$statf" | sort -t"$(printf '\037')" -k1,1n -k8,8r
}

emit() { awk -F'\037' -v OFS='\t' '{ print $2, $3, $4, $7, $8, $5, $6 }'; }
# a listing answers "what landed lately", so it re-sorts on created, newest
# first. next/open/groom/board keep the priority rank rows() sorted on.
newest() { sort -t"$SEP" -k7,7r; }
open_only() { awk -F'\037' '$3!="done" && $3!="reject" && $3!="spec" && $3!="list"'; }

# the stable part of an id - what a status change never touches, and what a
# commit's Branch: trailer carries - so trail can key code to a ticket even
# once its file is gone from the working tree
stable_name() {
  case "$1" in
    idea-*|spike-*|todo-*|issue-*|done-*|reject-*|spec-*|list-*) echo "${1#*-}" ;;
    *) echo "$1" ;;
  esac
}

# The live worktree claiming a ticket, as branch<TAB>path, matched the way
# rows() matches: on the name after the status word, across + joins. awk reads
# to the end rather than exiting, which under pipefail would SIGPIPE git.
claimer() {
  { git -C "$ROOT" worktree list --porcelain 2>/dev/null || true; } | awk -v main="$MAIN" -v want="$1" -v statuses="$STATUSES" '
    function slug(id,   s) {
      s = id; sub(/-.*/, "", s)
      if (id !~ /-/ || index(" " statuses " ", " " s " ") == 0) return ""
      sub(/^[^-]*-/, "", id); return id
    }
    BEGIN { w = slug(want) }
    /^worktree / { p = substr($0, 10) }
    /^branch refs\/heads\// && !found {
      b = substr($0, 19); if (b == main) next
      hit = (b == want)
      n = split(b, part, "+")
      for (i = 1; i <= n; i++) if (w != "" && part[i] == w) hit = 1
      if (hit) { print b "\t" p; found = 1 }
    }'
}

# What to pick up. Critical and high lead; with none free, the best judged
# rank that is, so an empty answer means nothing can be started rather than
# nothing is urgent. Then one untriaged item. The note saying which case this
# is goes to stderr, keeping stdout one record per line.
next_up() {
  local open free pick
  open=$(rows | open_only)
  free=$(printf '%s\n' "$open" | awk -F'\037' 'NF && $8 !~ /BLOCKED/ && $8 !~ /CLAIMED/')
  pick=$(printf '%s\n' "$free" | awk -F'\037' 'NF && $1<=1')
  if [ -z "$pick" ]; then
    # sorted on rank already, so the first judged row holds the best rank
    pick=$(printf '%s\n' "$free" | awk -F'\037' 'NF && $1<=3 { if (top == "") top = $1; if ($1 == top) print }')
    if [ -n "$pick" ]; then
      echo "no critical or high work is free - the best available:" >&2
    else
      printf '%s\n' "$open" | awk -F'\037' 'NF && $8 ~ /CLAIMED/ {c++} NF && $8 ~ /BLOCKED/ {b++}
        END { printf "nothing judged is free to start: %d claimed, %d blocked\n", c, b }' >&2
    fi
  fi
  [ -z "$pick" ] || printf '%s\n' "$pick" | emit
  # one untriaged item alongside the work: triage before you start. The
  # filter reads to the end rather than head -1 closing the pipe, which
  # under pipefail turns a long queue into a SIGPIPE exit
  printf '%s\n' "$free" | awk -F'\037' 'NF && $2=="groom" && !n++' | emit
}

# Prepare every edit before touching the checkout. Git detects the rename when
# the caller stages it; leave the index alone, including any staged user work.
move_ticket() (
  local status="$1" id="${2%.md}" dry_run="${3:-}"
  local root src dst heading stage file candidate target index count=0 applied=0
  local renamed=0 committed=0 result last_newline spec claim
  local -a files=()
  root="$(cd "$DIR/.." && pwd)"
  case "$status" in idea|spike|todo|issue|done|reject|spec|list) ;; *) echo "invalid status: $status" >&2; exit 1;; esac
  [[ "$id" =~ ^(idea|spike|todo|issue|done|reject|spec|list)-[a-z0-9]+(-[a-z0-9]+)*$ ]] \
    || { echo "expected a ticket filename or id: $2" >&2; exit 1; }
  [ -z "$dry_run" ] || [ "$dry_run" = --dry-run ] \
    || { echo "unknown option: $dry_run" >&2; exit 1; }
  src="$DIR/$id.md"
  dst="$DIR/$status-${id#*-}.md"
  [ -f "$src" ] && [ ! -L "$src" ] || { echo "no regular ticket: $src" >&2; exit 1; }
  [ "$src" != "$dst" ] || { echo "already $status: $id.md" >&2; exit 1; }
  [ ! -e "$dst" ] && [ ! -L "$dst" ] || { echo "destination exists: $dst" >&2; exit 1; }
  # every branch carries its own copy of project/, so a claimed ticket changes
  # status on its claiming branch and reaches the default branch with the
  # merge. Moved anywhere else, the two renames collide when it lands.
  claim=$(claimer "$id")
  if [ -n "$claim" ] && [ "${claim%%$'\t'*}" != "$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" ]; then
    echo "$id.md is claimed by ${claim%%$'\t'*} at ${claim#*$'\t'} - move it there, or remove that worktree first" >&2; exit 1
  fi
  heading=$(printf '%s' "$status" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
  stage=$(mktemp -d "${TMPDIR:-/tmp}/project-move.XXXXXX")
  trap '
    result=$?
    if [ "$committed" -eq 0 ] && [ "$renamed" -eq 1 ]; then
      for ((index=0; index<applied; index++)); do
        target="${files[index]}"
        [ "$target" != "$src" ] || target="$dst"
        cat "$stage/$index.before" > "$target" || result=1
      done
      mv -n "$dst" "$src" || result=1
      echo "move failed; restored the ticket and references" >&2
    fi
    rm -rf "$stage"
    exit "$result"
  ' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Include tracked and untracked text, recursively, honoring Git ignores.
  # A filename is a reference even inside backticks, code, or old prose.
  git -C "$root" grep -Ilz --untracked --exclude-standard -F "$id" > "$stage/candidates" \
    || { result=$?; [ "$result" -eq 1 ] || exit "$result"; }
  printf '%s\0' "project/$id.md" >> "$stage/candidates"
  while IFS= read -r -d '' candidate; do
    file="$root/$candidate"
    [ "$file" != "$src" ] || [ ! -e "$stage/source-seen" ] || continue
    [ "$file" != "$src" ] || touch "$stage/source-seen"
    [ ! -L "$file" ] || { echo "cannot update symlink: $candidate" >&2; exit 1; }
    cp -p "$file" "$stage/$count.before"
    last_newline=$(tail -c 1 "$file" | wc -l | tr -d ' ')
    awk -v old="$id" -v new="${dst##*/}" -v terminated="$last_newline" '
      function replace(text, needle, replacement,   start, at, before, after, rest, out) {
        start=1; out=""
        while ((at=index(substr(text,start),needle)) > 0) {
          at+=start-1
          before=at>1 ? substr(text,at-1,1) : ""
          after=substr(text,at+length(needle),1)
          rest=substr(text,at+length(needle)+1,1)
          out=out substr(text,start,at-start)
          if (before !~ /[[:alnum:]_.-]/ && after !~ /[[:alnum:]_-]/ && !(after=="." && rest ~ /[[:alnum:]_-]/)) {
            out=out replacement
          } else { out=out needle }
          start=at+length(needle)
        }
        return out substr(text,start)
      }
      {
        line=replace($0,old ".md",new)
        new_id=new; sub(/\.md$/,"",new_id)
        if (line ~ /^Blocked: /) {
          prefix="Blocked: " old
          if (substr(line,1,length(prefix))==prefix && (length(line)==length(prefix) || substr(line,length(prefix)+1,1) ~ /[[:space:]]/)) {
            line="Blocked: " new_id substr(line,length(prefix)+1)
          }
        }
        line=replace(line,"/project/" old,"/project/" new_id)
        if (NR>1) printf "\n"
        printf "%s",line
      }
      END { if (terminated) printf "\n" }
    ' "$file" > "$stage/$count.after"
    if [ "$file" = "$src" ]; then
      [ "$last_newline" -eq 1 ] || printf '\n' >> "$stage/$count.after"
      printf '\n## %s\n\n' "$heading" >> "$stage/$count.after"
    elif cmp -s "$stage/$count.before" "$stage/$count.after"; then
      continue
    fi
    [ "$dry_run" = --dry-run ] || [ -w "$file" ] || { echo "not writable: $candidate" >&2; exit 1; }
    files[count]="$file"
    count=$((count+1))
  done < "$stage/candidates"

  printf '%s -> %s%s\n' "${src##*/}" "${dst##*/}" "${dry_run:+ (dry run)}"
  for ((index=0; index<count; index++)); do
    printf '  update: %s\n' "${files[index]#"$root/"}"
  done
  if [ "$dry_run" = --dry-run ]; then
    for ((index=0; index<count; index++)); do
      diff -u -L "${files[index]#"$root/"}" -L "${files[index]#"$root/"} (after)" \
        "$stage/$index.before" "$stage/$index.after" || [ "$?" -eq 1 ]
    done
    exit 0
  fi

  mv -n "$src" "$dst"
  [ ! -e "$src" ] || { echo "destination appeared; move aborted" >&2; exit 1; }
  renamed=1
  for ((index=0; index<count; index++)); do
    target="${files[index]}"
    [ "$target" != "$src" ] || target="$dst"
    applied=$((index+1))
    cat "$stage/$index.after" > "$target"
  done
  committed=1
  printf 'Moved; ## %s appended. Fill in the new section.\n' "$heading"
  if [ "$status" = done ]; then
    # finishing is reconciling, not remembering - see Finishing in chat's SKILL.md
    echo '  promised: each thing the ## Todo committed to, shipped or deferred - say which'
    echo '  proof: the command that proves it, run now, and that it passed'
    echo '  left: a link to wherever each deferred thing was filed'
    echo '  changelog: add a line to project/changelog.md if this changed something a reader would notice'
    spec=$(awk -F': ' '/^Spec: /{print $2; exit}' "$dst")
    if [ -n "$spec" ]; then
      (rows | open_only | awk -F'\037' -v S="$spec" '$2=="groom" && $6==S && $8 !~ /BLOCKED/' | emit) || true
    fi
    awk -v filename="${dst##*/}" -v id="${dst##*/}" '
      BEGIN {sub(/\.md$/,"",id)}
      /^Blocked: / && ($2==filename || $2==id) {name=FILENAME; sub(/.*\//,"",name); print "  unblocks: " name}
    ' "$DIR"/*.md
  fi
)

cmd="${1:-}"
case "$cmd" in
  ''|help|-h|--help|new) ;;
  *) [ -d "$DIR" ] || { echo "no project/ folder in $ROOT - start one with: project.sh new <status> <name>" >&2; exit 1; } ;;
esac
case "$cmd" in
  ''|help|-h|--help)
    usage; [ -z "$cmd" ] && [ -d "$DIR" ] && { echo; next_up 2>&1; } || true ;;
  next) next_up ;;
  groom) rows | open_only | awk -F'\037' '$2=="groom" && $8 !~ /BLOCKED/ && $8 !~ /CLAIMED/' | emit ;;
  blocked)
    # the reason lives in the header, and the reason is the point
    rows | open_only | awk -F'\037' '$8 ~ /BLOCKED|UNBLOCKED/' | while IFS="$SEP" read -r _ p st b t sp age idle; do
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$st" "$b" "$idle" "$t" \
        "$(awk -F': ' '/^Blocked: /{print $2; exit}' "$DIR/$b.md")"
    done ;;
  unblocked) rows | open_only | awk -F'\037' '$8 ~ /UNBLOCKED/' | emit ;;
  claimed)
    # a live worktree of the ticket's own name, no header to read
    git -C "$DIR/.." worktree list --porcelain \
      | awk -v main="$MAIN" '/^worktree /{p=substr($0,10)} /^branch refs\/heads\//{b=$0; sub(/^branch refs\/heads\//,"",b); if (b!=main) print b"\t"p}' ;;
  resume)
    # Where a claimed ticket stands, read from its worktree: the branch's copy
    # of the ticket carries checkpoints the default branch has not seen yet.
    n="${2:-}"
    if [ -z "$n" ]; then
      n=$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
      [ -n "$n" ] && [ "$n" != "$MAIN" ] || { echo "usage: project.sh resume <id> - or run it inside the ticket's worktree" >&2; exit 1; }
    fi
    claim=$(claimer "${n%.md}")
    [ -n "$claim" ] || { echo "no live worktree claims $n - start one with /project:worktree $n" >&2; exit 1; }
    branch=${claim%%$'\t'*}; path=${claim#*$'\t'}
    printf 'branch\t%s\npath\t%s\n' "$branch" "$path"
    # the whole change as one diff, which is what a review reads
    printf 'review\tgit diff %s...%s\n' "$MAIN" "$branch"
    printf 'commits\t%s since %s\n' "$(git -C "$path" rev-list --count "$MAIN..HEAD" 2>/dev/null || echo '?')" "$MAIN"
    git -C "$path" log --format='  %h %s' "$MAIN..HEAD" 2>/dev/null || true
    dirty=$(git -C "$path" status --short)
    if [ -n "$dirty" ]; then printf 'uncommitted\n%s\n' "$(printf '%s\n' "$dirty" | sed 's/^/  /')"; else printf 'uncommitted\tnone\n'; fi
    for part in $(printf '%s' "$branch" | tr '+' ' '); do
      # the branch names its ticket's stable part directly now; try it
      # against every status and take whichever file actually exists
      ticket=$(for s in $STATUSES; do if [ -f "$path/project/$s-$part.md" ]; then echo "$s-$part.md"; break; fi; done)
      [ -n "$ticket" ] || { printf 'ticket\t%s is not on this branch\n' "$part"; continue; }
      printf 'ticket\t%s\n' "$path/project/$ticket"
      # Only the section for the status the ticket holds now: a spike's
      # checkpoint is history once the ticket is a todo. The newest checkpoint
      # there is the current state; with none, the section itself is.
      title="## $(printf '%s' "${ticket%%-*}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
      awk -v title="$title" '
        /^[[:space:]]*```/ { fenced = !fenced }
        !fenced && /^## / { insec = ($0 == title); oncp = 0; if (insec) { sec = ""; cp = "" } }
        insec { sec = sec $0 "\n" }
        insec && !fenced && /^### Checkpoint/ { cp = ""; oncp = 1 }
        oncp && !fenced && /^##?#? / && !/^### Checkpoint/ { oncp = 0 }
        oncp { cp = cp $0 "\n" }
        END {
          if (cp != "") printf "\n%s", cp
          else if (sec != "") printf "checkpoint\tnone under %s - the section itself:\n\n%s", title, sec
          else printf "checkpoint\tno %s section - read the ticket\n", title
        }' "$path/project/$ticket"
    done ;;
  open)  rows | open_only | emit ;;
  all)   rows | newest | emit ;;
  board)
    for s in $STATUSES; do printf 'status\t%s\t%s\n' "$s" "$(ls "$DIR"/$s-*.md 2>/dev/null | wc -l | tr -d ' ')"; done
    rows | open_only | awk -F'\037' '$2!="groom" || $8 !~ /BLOCKED/ {c[$2]++} END{split("critical high medium low groom",o," "); for(i=1;i<=5;i++) printf "priority\t%s\t%d\n", o[i], c[o[i]]+0}' ;;
  spec)
    q="${2:?usage: project.sh spec <name>}"
    ids=$( { grep -l "Spec: .*spec-$q\.md" "$DIR"/*.md 2>/dev/null || true; } | sed 's|.*/||;s|\.md$||' | tr '\n' ' ')
    rows | awk -F'\037' -v L=" $ids" 'index(L, " "$4" ")>0' | newest | emit ;;
  find)
    q="${2:?usage: project.sh find <term>}"
    ids=$( { grep -il -- "$q" "$DIR"/*.md 2>/dev/null || true; } | sed 's|.*/||;s|\.md$||' | tr '\n' ' ')
    [ -n "${ids// /}" ] && rows | awk -F'\037' -v L=" $ids" 'index(L, " "$4" ")>0' | newest | emit || true ;;
  show)
    n="${2:?usage: project.sh show <id|status>}"
    # a bare status means the newest ticket at that status. An id always carries
    # a hyphen after its status word, so the two forms cannot collide.
    case " $STATUSES " in *" $n "*)
      n=$(rows | awk -F'\037' -v K="$n" '$3==K' | newest | awk -F'\037' 'NR==1{r=$4} END{print r}')
      [ -n "$n" ] || { echo "no ${2} tickets" >&2; exit 1; }
      # you did not name the file, so say which one this is
      echo "$n" ;;
    esac
    cat "$DIR/$n.md" ;;
  changelog) cat "$DIR/changelog.md" ;;
  log)
    # the commit trail for one ticket. --follow so renames (status changes) survive.
    n="${2:?usage: project.sh log <id>}"
    [ -e "$DIR/$n.md" ] || { echo "no $n" >&2; exit 1; }
    out=$(git -C "$DIR/.." log --follow --format='%h%x09%ad%x09%s' --date=short -- "project/$n.md" 2>/dev/null || true)
    [ -n "$out" ] && echo "$out" || echo "uncommitted" ;;
  trail)
    # code committed under the ticket's stable name, found by its Branch:
    # trailer rather than by the ticket file - this reaches a commit that
    # never touched project/, and survives the file being long since gone
    n="${2:?usage: project.sh trail <id>}"
    stable=$(stable_name "$n")
    pattern="^Branch: ${stable}"'$'
    out=$(git -C "$ROOT" log --all --format='%h%x09%ad%x09%s' --date=short --grep="$pattern" 2>/dev/null || true)
    if [ -n "$out" ]; then echo "$out"; else echo "no commits carry Branch: $stable"; fi
    if ! command -v gh >/dev/null 2>&1; then
      echo "pr	unavailable: gh is not installed"
    elif ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
      echo "pr	unavailable: no origin remote"
    else
      ghout=$(gh pr list --search "head:$stable" --state all --json number,title,url 2>&1) \
        || { echo "pr	unavailable: $ghout"; ghout=""; }
      if [ -n "$ghout" ]; then
        rows=$(printf '%s' "$ghout" | python3 -c '
import json, sys
for p in json.load(sys.stdin):
    print("pr\t%s\t%s\t%s" % (p["number"], p["title"], p["url"]))
' 2>/dev/null || true)
        if [ -n "$rows" ]; then printf '%s\n' "$rows"; else echo "pr	none found for head:$stable"; fi
      fi
    fi ;;
  new)
    s="${2:?usage: project.sh new <status> <name>}"; n="${3:?usage: project.sh new <status> <name>}"
    case " $STATUSES " in *" $s "*) ;; *) echo "status must be one of: $STATUSES" >&2; exit 1;; esac
    mkdir -p "$DIR"
    f="$DIR/$s-$n.md"; [ -e "$f" ] && { echo "$f exists" >&2; exit 1; }
    S=$(echo "$s" | tr '[:lower:]' '[:upper:]' | cut -c1)$(echo "$s" | cut -c2-)
    # untriaged until someone with standing judges it - see groom in chat's SKILL.md
    printf '# %s\n\nPriority: groom\n\n## %s\n\n' "$(echo "$n" | tr '-' ' ')" "$S" > "$f"
    echo "$f" ;;
  move|mv)
    [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo "usage: project.sh move <status> <filename> [--dry-run]" >&2; exit 1; }
    if [ "$cmd" = move ]; then move_ticket "$2" "$3" "${4:-}"
    else move_ticket "$3" "$2" "${4:-}"; fi ;;
  idea|spike|todo|issue|done|reject|list|spec-only)
    rows | awk -F'\037' -v K="${cmd%-only}" '$3==K' | newest | emit ;;
  check)
    # Ported from the Pest suite that guarded the board through its renames:
    # every rule reports a list, and an empty board is itself a failure, so a
    # glob that stops matching cannot pass in silence.
    python3 - "$ROOT" <<'PY2'
import re, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
TICKET = r"(?<![\w/.-])((?:spec|done|todo|idea|spike|issue|reject)-[a-z0-9_-]+\.md)"
HEADER = re.compile(r"^(Description|Priority|Spec|Blocked|Bucket): ")
found = []

def prose(text):
    """Line numbers kept; fenced blocks and inline code dropped - an example is not a reference."""
    fenced = False
    for n, line in enumerate(text.split("\n"), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            yield n, re.sub(r"`[^`]*`", "", line)

def anchors(text):
    """GitHub's heading slugs, approximated the way the Pest check did. A repeat is numbered -1, -2, stepping past any number a heading already holds, as GitHub does."""
    counts = {}
    for h in re.findall(r"^#{1,6} (.+)$", text, re.M):
        base = candidate = re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", re.sub(r"<[^>]+>", "", h).lower())).strip("-")
        while candidate in counts:
            counts[base] += 1
            candidate = f"{base}-{counts[base]}"
        counts[candidate] = 0
    return set(counts)

def empty_section(text, title):
    """Line of the last `## <title>` outside a fence when nothing is written under it, else None."""
    lines, fenced, marks = text.split("\n"), False, []
    for n, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("## "):
            marks.append((n, line[3:].strip()))
    for i in range(len(marks) - 1, -1, -1):
        n, heading = marks[i]
        if heading == title:
            end = marks[i + 1][0] if i + 1 < len(marks) else len(lines)
            return None if any(l.strip() for l in lines[n + 1:end]) else n + 1
    return None

def resolve(src, page):
    base = src.parent / page
    return next((c.resolve() for c in (base, Path(str(base) + ".md")) if c.exists()), None)

files = sorted((root / "project").glob("*.md"))
if not files:
    print("project/: no markdown files, so nothing was checked")
    sys.exit(1)

for f in files:
    name = str(f.relative_to(root))
    # move appends the heading and nothing else, so an empty section for the
    # status a ticket holds now is one nobody wrote. Earlier sections are
    # history, left as written, so only the current one is held to this.
    status = f.name.split("-", 1)[0]
    if status in ("idea", "spike", "todo", "issue", "done", "reject"):
        at = empty_section(f.read_text(), status.capitalize())
        if at:
            found.append(f"{name}:{at}: P005  nothing written under ## {status.capitalize()}")
    for n, line in prose(f.read_text()):
        for target in re.findall(r"\]\(([^)]+)\)", line):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue
            page, _, frag = target.partition("#")
            dest = resolve(f, page) if page else f
            if dest is None:
                found.append(f"{name}:{n}: P001  link to a file that does not exist: {target}")
            elif frag and dest.suffix == ".md" and frag not in anchors(dest.read_text()):
                found.append(f"{name}:{n}: P002  no heading on {dest.name} for #{frag}")
        if HEADER.match(line):
            continue
        for ticket in sorted(set(re.findall(TICKET, re.sub(r"\[[^\]]*\]\([^)]*\)", "", line)))):
            if ticket != f.name:
                found.append(f"{name}:{n}: P003  bare {ticket} in prose; write it as a link")

# Code citing a spec or a page by path. Test folders are skipped: fixtures
# plant paths that are meant not to exist.
tracked = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, text=True).stdout
for path in filter(None, tracked.split("\0")):
    if path.endswith(".md") or re.search(r"(^|/)tests?/", path):
        continue
    try:
        text = (root / path).read_text()
    except (UnicodeDecodeError, OSError):
        continue
    for n, line in enumerate(text.split("\n"), 1):
        for cite in sorted(set(re.findall(r"(?<![\w/.-])((?:project|docs)/[A-Za-z0-9_./-]+\.md)", line))):
            if not (root / cite).exists():
                found.append(f"{path}:{n}: P004  cites {cite}, which does not exist")

print("\n".join(found)) if found else None
sys.exit(1 if found else 0)
PY2
    ;;
  *) usage >&2; exit 1 ;;
esac
