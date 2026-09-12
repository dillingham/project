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
  project.sh next            critical + high, open only, plus one to triage
  project.sh open            every open ticket, priority order
  project.sh all             everything, including done and reject
  project.sh groom           untriaged: unjudged, unblocked, not a bucket
  project.sh blocked         waiting on another ticket, and on what
  project.sh list            holding pens: grouped one-liners, promote items out
  project.sh unblocked       blocked on something that already shipped
  project.sh claimed         tickets with a live worktree of their own name
  project.sh board           counts by status and by priority
  project.sh <status>        one status: idea spike todo issue done reject spec
  project.sh spec <name>     everything filed against spec-<name>.md
  project.sh find <term>     search titles and bodies
  project.sh show <id>       print one file
  project.sh show <status>   print the newest file at that status
  project.sh log <id>        its commit trail: hash, date, subject (renames followed)
  project.sh changelog       what landed, newest first, linked to its ticket
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
  local statf gitf
  statf=$(mktemp); gitf=$(mktemp)
  trap 'rm -f "$statf" "$gitf"' RETURN
  stat -f '%N|%m|%B' "$DIR"/*.md 2>/dev/null > "$statf" \
    || stat -c '%n|%Y|%W' "$DIR"/*.md 2>/dev/null > "$statf"
  # commit epoch followed by the paths it touched; empty when nothing is tracked
  git -C "$DIR/.." log --format='@%at' --name-only -- project 2>/dev/null > "$gitf" || true

  awk -F'|' -v main="$MAIN" -v now="$NOW" -v stale="$STALE_DAYS" -v gitf="$gitf" -v dir="$DIR" -v statuses="$STATUSES" -v tzoff="$TZ_OFFSET" '
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
    BEGIN {
      OFS="\037"
      # every ticket that exists, and the reverse index of Blocked: lines
      while (("ls " dir | getline f) > 0) { sub(/\.md$/, "", f); exists[f] = 1 }
      close("ls " dir)
      while (("grep -H \"^Blocked: \" " dir "/*.md 2>/dev/null" | getline g) > 0) {
        split(g, gp, ":Blocked: ")
        n = split(gp[1], pp, "/"); who = pp[n]; sub(/\.md$/, "", who)
        on = gp[2]; sub(/ .*/, "", on); sub(/\.md$/, "", on)
        blocks[on] = blocks[on] + 1
      }
      close("grep -H \"^Blocked: \" " dir "/*.md 2>/dev/null")

      # a ticket with a live worktree of its own name is claimed - no header
      # to write or commit, git worktree list is already shared and instant.
      # related tickets sharing one branch join their ids with +, so a
      # branch claims every id it names, not just the whole string
      while (("git -C " dir "/.. worktree list --porcelain 2>/dev/null | grep \"^branch \"" | getline wl) > 0) {
        b = wl; sub(/^branch refs\/heads\//, "", b)
        if (b != main) {
          wn = split(b, wp, "+")
          for (wi = 1; wi <= wn; wi++) { claimed[wp[wi]] = 1 }
        }
      }
      close("git -C " dir "/.. worktree list --porcelain 2>/dev/null | grep \"^branch \"")

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
      if (st!="done" && st!="reject" && st!="spec" && pri!="groom" && blocked=="" && !(base in claimed) && idle>=stale && r>0) { r=r-1; bump=" STALE" }
      # a blocked or already-claimed ticket cannot be started, so neither
      # competes for attention
      if (blocked!="") r = 8
      if (base in claimed) r = 8
      flag = ""
      if (base in claimed) { flag = " CLAIMED" }
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

# Prepare every edit before touching the checkout. Git detects the rename when
# the caller stages it; leave the index alone, including any staged user work.
move_ticket() (
  local status="$1" id="${2%.md}" dry_run="${3:-}"
  local root src dst heading stage file candidate target index count=0 applied=0
  local renamed=0 committed=0 result last_newline spec
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
    usage; [ -z "$cmd" ] && [ -d "$DIR" ] && { echo; rows | open_only | awk -F'\037' '$1<=1' | emit; } || true ;;
  next)
    rows | open_only | awk -F'\037' '$1<=1 && $8 !~ /BLOCKED/ && $8 !~ /CLAIMED/' | emit
    # one untriaged item alongside the work: triage before you start
    rows | open_only | awk -F'\037' '$2=="groom" && $8 !~ /BLOCKED/ && $8 !~ /CLAIMED/' | head -1 | emit ;;
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
  new)
    s="${2:?usage: project.sh new <status> <name>}"; n="${3:?usage: project.sh new <status> <name>}"
    case " $STATUSES " in *" $s "*) ;; *) echo "status must be one of: $STATUSES" >&2; exit 1;; esac
    mkdir -p "$DIR"
    f="$DIR/$s-$n.md"; [ -e "$f" ] && { echo "$f exists" >&2; exit 1; }
    S=$(echo "$s" | tr '[:lower:]' '[:upper:]' | cut -c1)$(echo "$s" | cut -c2-)
    printf '# %s\n\nPriority: medium\n\n## %s\n\n' "$(echo "$n" | tr '-' ' ')" "$S" > "$f"
    echo "$f" ;;
  move|mv)
    [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo "usage: project.sh move <status> <filename> [--dry-run]" >&2; exit 1; }
    if [ "$cmd" = move ]; then move_ticket "$2" "$3" "${4:-}"
    else move_ticket "$3" "$2" "${4:-}"; fi ;;
  idea|spike|todo|issue|done|reject|list|spec-only)
    rows | awk -F'\037' -v K="${cmd%-only}" '$3==K' | newest | emit ;;
  *) usage >&2; exit 1 ;;
esac
