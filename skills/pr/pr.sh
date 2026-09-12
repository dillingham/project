#!/usr/bin/env bash
# Deterministic PR-body shape and style checks; no repository or network access.
set -euo pipefail

usage() {
  cat <<'USAGE'
pr.sh lint <body-file>   validate a PR body; silent on success
pr.sh rules              show the required shape and style
Exit 1 means lint findings; exit 2 means invalid arguments or unreadable input.
USAGE
}

case "${1:-help}" in
  help|-h|--help) usage; exit 0 ;;
  rules) [ "$#" -eq 1 ] || { usage >&2; exit 2; } ;;
  lint) [ "$#" -eq 2 ] || { usage >&2; exit 2; } ;;
  *) usage >&2; exit 2 ;;
esac
command -v python3 >/dev/null || { echo 'pr.sh: python3 is required' >&2; exit 2; }

python3 - "$@" <<'PY'
import re
import sys
from pathlib import Path

RULES = """PR001  unheaded overview of one or two prose paragraphs required
PR002  exactly ### Changes, ### Related, ### Testing, once each in that order
PR003  each section must contain text outside fenced examples
PR004  section headings must have a blank line before and after
PR005  Changes and Testing use '- ' bullets; continuations are indented
PR006  Related has Specs, Tickets, Related PRs rows with inline Markdown links
       or 'None identified.'; link destinations must be nonempty and balanced
PR007  Testing: `command` - passed: result / failed: result, or Not run: reason
PR008  no TODO, TBD, FIXME, template fillers or em/en dashes in prose
PR009  close code fences; fenced examples do not count as body structure
Only Markdown shape and style are checked, not facts, link existence or results."""

if sys.argv[1] == 'rules':
    print(RULES)
    sys.exit(0)

path = sys.argv[2]
try:
    lines = Path(path).read_text(encoding='utf-8').splitlines()
except (OSError, UnicodeError) as exc:
    print(f'pr.sh: {exc}', file=sys.stderr)
    sys.exit(2)

findings = []
def report(n, code, message):
    findings.append((n, code, message))

# Preserve physical line numbers while keeping example Markdown out of parsing.
visible = []
fence = None
for n, raw in enumerate(lines, 1):
    if fence:
        if re.fullmatch(r' {0,3}' + re.escape(fence[0]) +
                        '{' + str(fence[1]) + r',}\s*', raw):
            fence = None
        continue
    opening = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', raw)
    if opening:
        marker = opening.group(1)
        fence = (marker[0], len(marker), n)
        continue
    visible.append((n, raw))
if fence:
    report(fence[2], 'PR009', 'unclosed code fence')

expected = ['Changes', 'Related', 'Testing']
heads = [(n, raw) for n, raw in visible if re.match(r'^\s*#{1,6}(?:\s|$)', raw)]
if [raw for _, raw in heads] != ['### ' + name for name in expected]:
    report(heads[0][0] if heads else 1, 'PR002',
           'use exactly ### Changes, ### Related, ### Testing, once each in that order')
for n, _ in heads:
    if n == 1 or lines[n - 2].strip() or n == len(lines) or lines[n].strip():
        report(n, 'PR004', 'put a blank line before and after the heading')

first = heads[0][0] if heads else len(lines) + 1
overview = [(n, raw) for n, raw in visible if n < first]
paragraphs = re.split(r'\n\s*\n', '\n'.join(raw for _, raw in overview).strip())
if (not any(raw.strip() for _, raw in overview) or len(paragraphs) > 2 or
        any(re.match(r'^\s*(?:[-*+]\s|\d+[.)]\s|[>|]|#{1,6}\s)', raw)
            for _, raw in overview if raw.strip())):
    report(1, 'PR001', 'start with one or two unheaded prose paragraphs')

sections = {}
for index, (n, raw) in enumerate(heads):
    end = heads[index + 1][0] if index + 1 < len(heads) else len(lines) + 1
    if raw in ['### ' + name for name in expected]:
        rows = [(line, text) for line, text in visible if n < line < end and text.strip()]
        sections[raw[4:]] = rows
        if not rows:
            report(n, 'PR003', 'section needs content outside fenced examples')

def bullets(rows, section):
    result = []
    for n, raw in rows:
        if raw.startswith('- ') and raw[2:].strip():
            result.append([n, raw[2:].strip()])
        elif raw.startswith('  ') and result:
            result[-1][1] += ' ' + raw.strip()
        else:
            report(n, 'PR005', f'{section} requires nonempty - bullets, with indented continuations')
    return result

bullets(sections.get('Changes', []), 'Changes')

def links_valid(text):
    """Accept simple inline links, including balanced parentheses in destinations.

    Titles and reference links are deliberately outside this small house format.
    Text between links may explain the relationship, but bare URLs/brackets fail.
    """
    found = False
    rest = ''
    i = 0
    while i < len(text):
        if text[i] != '[':
            rest += text[i]
            i += 1
            continue
        label_end = text.find('](', i + 1)
        if label_end < 0 or not text[i + 1:label_end].strip() or '[' in text[i + 1:label_end]:
            return False
        start = label_end + 2
        depth = 1
        j = start
        while j < len(text) and depth:
            if text[j] == '\\' and j + 1 < len(text):
                j += 2
                continue
            if text[j] == '(':
                depth += 1
            elif text[j] == ')':
                depth -= 1
            j += 1
        if depth:
            return False
        destination = text[start:j - 1]
        if destination.startswith('<') and destination.endswith('>'):
            destination = destination[1:-1]
        if not destination or re.search(r'\s|[<>]', destination):
            return False
        found = True
        i = j
    return found and not re.search(r'[\[\]]|https?://', rest)

related = bullets(sections.get('Related', []), 'Related')
labels = ['Specs', 'Tickets', 'Related PRs']
seen = []
for n, text in related:
    match = re.fullmatch(r'(Specs|Tickets|Related PRs):\s+(.+)', text)
    if not match:
        report(n, 'PR006', 'use Specs:, Tickets: or Related PRs: with links or None identified.')
        continue
    label, value = match.groups()
    seen.append(label)
    none = re.fullmatch(r'None identified\.(?: PR lookup unavailable: \S.*)?', value)
    if not none and not links_valid(value):
        report(n, 'PR006', 'use inline [label](destination) links or None identified.')
if 'Related' in sections and seen != labels:
    report(next((n for n, raw in heads if raw == '### Related'), 1), 'PR006',
           'include Specs, Tickets and Related PRs once each in that order')

for n, text in bullets(sections.get('Testing', []), 'Testing'):
    if not (re.fullmatch(r'`[^`\n]+` - (?:passed|failed): \S.*', text, re.I) or
            re.fullmatch(r'Not run: \S.*', text, re.I)):
        report(n, 'PR007', 'use `command` - passed: result / failed: result, or Not run: reason')

for n, raw in visible:
    # Literal identifiers and inline examples can contain these words and dashes.
    prose = re.sub(r'(`+).*?\1', '', raw)
    if re.search(r'[\u2013\u2014]|(?<![\w/-])(?:TODO|TBD|FIXME)(?![\w/-])|'
                 r'<(?:insert|describe|summary|reason|link|ticket|spec|testing)\b[^>]*>|'
                 r'\[(?:insert|describe|summary|reason|link|ticket|spec|testing)\](?!\()', prose, re.I):
        report(n, 'PR008', 'replace template fillers and use a spaced hyphen instead of em/en dashes')

for n, code, message in sorted(set(findings)):
    print(f'{path}:{n}: {code}  {message}')
sys.exit(1 if findings else 0)
PY
