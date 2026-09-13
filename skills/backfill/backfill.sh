#!/usr/bin/env bash
# backfill.sh - list what a source holds, for /project:backfill to file.
# Output is tab-separated: ref, kind, title, board. It collects and never
# writes: what each row becomes on the board is the skill's judgement.
set -euo pipefail

# the board belongs to the repo you are standing in, not to wherever this script is installed
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GH_LIMIT=1000

usage() {
  cat <<'USAGE'
backfill.sh md <dir>              every markdown file under <dir>, its open checkboxes and TODO markers
backfill.sh gh [search]           open GitHub issues, optionally narrowed by a search (label:bug)
backfill.sh code <path|subject>   files under a path, or files naming a subject, and their TODO markers

Columns: ref  kind  title  board
kind is doc, open or marker (notes), issue (GitHub), file or marker (code).
board lists the project/ files already citing the row's source, or -. Read
them before filing anything; a cited source is not proof every item is covered.
An existing path wins over a subject of the same name.
Exit 2 means invalid arguments, an unreadable source or a failed gh call.
USAGE
}

case "${1:-help}" in
  help|-h|--help) usage; exit 0 ;;
  md|code) [ "$#" -eq 2 ] || { usage >&2; exit 2; } ;;
  gh) ;;
  *) usage >&2; exit 2 ;;
esac
command -v python3 >/dev/null || { echo 'backfill.sh: python3 is required' >&2; exit 2; }

# read -d '' rather than $(cat <<...): bash 3.2 misparses a heredoc inside $() once it holds a lone paren
read -r -d '' COLLECT <<'PY' || true
import json, re, subprocess, sys
from pathlib import Path

mode, root, arg, limit = sys.argv[1], Path(sys.argv[2]).resolve(), sys.argv[3], int(sys.argv[4])
MARKER = re.compile(r'(?<![\w-])(?:TODO|FIXME|HACK|XXX)(?![\w-])(?:\([^)]*\))?[\s:]*(.*)')
CHECKBOX = re.compile(r'^\s*[-*+]\s+\[ \]\s+(.*)')
FENCE = re.compile(r'^\s*(```|~~~)')
CLOSER = re.compile(r'\s*(\*/|-->|--}}|#}|%>|\?>)\s*$')
DECL = re.compile(r'^\s*(?:(?:export|public|private|protected|abstract|final|static|async|pub|default)\s+)*'
                  r'(?:class|interface|trait|enum|function|def|func|fn|module|struct|type)\s+\w')

def die(message):
    print(f'backfill.sh: {message}', file=sys.stderr)
    sys.exit(2)

board = {}
if (root / 'project').is_dir():
    for f in sorted((root / 'project').glob('*.md')):
        board[f.name] = f.read_text(encoding='utf-8', errors='replace')

def cites(pattern):
    rx = re.compile(pattern)
    return ','.join(name for name, text in board.items() if rx.search(text)) or '-'

def path_cites(rel):
    # whole path only: notes/a.md must not match xnotes/a.md or notes/a.md.bak
    return cites(r'(?<![\w./-])' + re.escape(rel) + r'(?![\w/-])')

def rel(p):
    p = Path(p).resolve()
    try:
        return p.relative_to(root).as_posix()
    except ValueError:
        return str(p)

def text_of(p):
    try:
        data = p.read_bytes()
    except OSError:
        return None
    if b'\0' in data[:8192] or len(data) > 2_000_000:
        return None
    return data.decode('utf-8', errors='replace')

def emit(ref, kind, title, cited):
    # tabs and newlines are the separators, so none survive into a field
    title = re.sub(r'\s+', ' ', title).strip()[:160] or '-'
    print('\t'.join((ref, kind, title, cited)))

def marker(line):
    m = MARKER.search(line)
    return CLOSER.sub('', m.group(1)) if m else None

def hidden(p, base):
    return any(part.startswith('.') or part == 'node_modules' for part in p.relative_to(base).parts[:-1])

if mode == 'md':
    src = Path(arg).resolve()
    if not src.is_dir():
        die(f'not a directory: {arg}')
    files = sorted(p for p in src.rglob('*')
                   if p.is_file() and p.suffix.lower() in ('.md', '.markdown') and not hidden(p, src))
    if not files:
        print(f'backfill.sh: no markdown under {arg}', file=sys.stderr)
    for p in files:
        text = text_of(p)
        if text is None:
            continue
        r, cited = rel(p), path_cites(rel(p))
        heading = next((l[2:] for l in text.splitlines() if l.startswith('# ')), p.stem)
        emit(r, 'doc', heading, cited)
        fenced = False
        for n, line in enumerate(text.splitlines(), 1):
            if FENCE.match(line):
                fenced = not fenced
                continue
            if fenced:
                continue
            box = CHECKBOX.match(line)
            if box:
                emit(f'{r}:{n}', 'open', box.group(1), cited)
            elif (m := marker(line)) is not None:
                emit(f'{r}:{n}', 'marker', m, cited)

elif mode == 'code':
    listed = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                            capture_output=True)
    if listed.returncode == 0:
        candidates = [root / n for n in listed.stdout.decode('utf-8', 'replace').split('\0') if n]
    else:
        candidates = [p for p in root.rglob('*') if p.is_file() and not hidden(p, root)]
    # the board is the destination, never a source
    candidates = sorted(p for p in candidates if p.is_file() and not rel(p).startswith('project/'))

    target = Path(arg).resolve()
    if target.exists():
        scope = [p for p in candidates if p.resolve() == target or target in p.resolve().parents]
        subject = None
        if not scope:
            print(f'backfill.sh: no files under {arg}', file=sys.stderr)
    else:
        # EmailReminder also finds email_reminder, email-reminders and "email reminder"
        spaced = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1 \2', re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', arg))
        words = [w for w in re.split(r'[^A-Za-z0-9]+', spaced) if w]
        if not words:
            die(f'nothing to search for in {arg!r}')
        subject = re.compile(r'[-_ ]?'.join(map(re.escape, words)), re.IGNORECASE)
        scope = candidates

    found = 0
    for p in scope:
        text = text_of(p)
        if text is None:
            continue
        lines = text.splitlines()
        r = rel(p)
        if subject:
            named = next((l for l in lines if subject.search(l)), None)
            if named is None and not subject.search(r):
                continue
            title = named or next((l for l in lines if DECL.match(l)), '-')
        else:
            title = next((l for l in lines if DECL.match(l)), '-')
        found += 1
        cited = path_cites(r)
        emit(r, 'file', title, cited)
        for n, line in enumerate(lines, 1):
            m = marker(line)
            if m is not None:
                emit(f'{r}:{n}', 'marker', m, cited)
    if subject and not found:
        print(f'backfill.sh: nothing names {arg}', file=sys.stderr)

elif mode == 'gh':
    try:
        issues = json.load(sys.stdin)
    except ValueError as exc:
        die(f'gh returned something other than JSON: {exc}')
    for i in issues:
        n = i['number']
        labels = ', '.join(l['name'] for l in i.get('labels') or [])
        title = i['title'] + (f' [{labels}]' if labels else '')
        emit(f'gh#{n}', 'issue', title, cites(rf'(?<![\w#])gh#{n}(?!\d)|/issues/{n}(?!\d)'))
    if len(issues) >= limit:
        print(f'backfill.sh: stopped at {limit} issues; narrow it with a search', file=sys.stderr)
PY

mode=$1; shift
if [ "$mode" = gh ]; then
  command -v gh >/dev/null 2>&1 || { echo 'backfill.sh: gh is not installed' >&2; exit 2; }
  args=(issue list --state open --limit "$GH_LIMIT" --json number,title,labels,url)
  [ "$#" -eq 0 ] || args+=(--search "$*")
  # gh reads the repo from the checkout it runs in
  json=$(cd "$ROOT" && gh "${args[@]}") || { echo 'backfill.sh: gh issue list failed' >&2; exit 2; }
  printf '%s' "$json" | python3 -c "$COLLECT" gh "$ROOT" "" "$GH_LIMIT"
else
  python3 -c "$COLLECT" "$mode" "$ROOT" "$1" "$GH_LIMIT"
fi
