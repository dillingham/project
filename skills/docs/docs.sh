#!/usr/bin/env bash
# docs.sh - lint and measure user-facing docs against the house style.
# Self-contained: bash wrapper, embedded python3, no project coupling.
# Point it elsewhere with DOCS_DIR=path/to/docs.
set -euo pipefail

if [ -n "${DOCS_DIR:-}" ]; then
  DOCS="$DOCS_DIR"
elif ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$ROOT/docs" ]; then
  DOCS="$ROOT/docs"
else
  DOCS="docs"
fi

usage() {
  cat <<'USAGE'
docs.sh - keep docs/ in the house voice.

  docs.sh                    lint every page, then the corpus profile
  docs.sh lint [file...]     violations as file:line: CODE  message
  docs.sh stats [file...]    the measured profile beside the targets
  docs.sh toc <file>         the table of contents the headings imply
  docs.sh rules              what each rule code means

Files default to every page under docs/, subfolders included, and may be paths
or bare names (routing).
Set DOCS_DIR to point at another project. Exit status is 1 when lint finds
anything other than advisories, so it works as a hook or a pre-commit step.
USAGE
}

cmd="${1:-all}"
case "$cmd" in
  -h|--help|help) usage; exit 0 ;;
  lint|stats|toc|rules) shift ;;
  all) ;;
  *) cmd=lint ;;
esac

# docs/ must never send a reader into project/, so the linter needs to know where it is
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/project"

files=()
if [ "$cmd" != "rules" ]; then
  if [ "$#" -eq 0 ]; then
    # every page, subfolders included - a page nested under docs/ is still a page
    while IFS= read -r -d '' page; do files+=("$page"); done \
      < <(find "$DOCS" -type f -name '*.md' -print0 2>/dev/null | sort -z)
    [ "${#files[@]}" -gt 0 ] || { echo "docs.sh: no pages in $DOCS" >&2; exit 2; }
  else
    for a in "$@"; do
      if   [ -f "$a" ];          then files+=("$a")
      elif [ -f "$DOCS/$a" ];    then files+=("$DOCS/$a")
      elif [ -f "$DOCS/$a.md" ]; then files+=("$DOCS/$a.md")
      else echo "docs.sh: no such page: $a" >&2; exit 2
      fi
    done
  fi
fi

PROJECT_DIR="$PROJECT_DIR" python3 - "$cmd" "${files[@]:-}" <<'PY'
import os, re, sys, statistics
from pathlib import Path

cmd, paths = sys.argv[1], [p for p in sys.argv[2:] if p]

RULES = """Structure
  D001  first ## is not Introduction
  D002  table of contents missing, or out of step with the headings
  D003  a #### heading is listed in the table of contents
  D004  Testing does not come before Events and the extension point
  D005  a code block opens a section with no sentence leading into it

Rhythm
  D010  code block not preceded by a colon-terminated sentence
  D011  code block longer than 20 lines
  D012  more than five paragraphs without a code block
  D013  code fence with no language
  D014  reference entry does not open "The `name` method ..."
  D015  example line wider than DOCS_EXAMPLE_WIDTH (default 62)
  D026  a section carrying more bullets than paragraphs (advisory)
  D027  implementation detail where a capability belongs (advisory)

Voice
  D020  contraction other than let's or we'll
  D021  "you can" where "you may" is the house form
  D022  warmth word outside the introduction
  D023  "we" or "let's" outside a walkthrough (advisory)
  D024  em-dash or en-dash
  D025  hard-wrapped paragraph

Links
  D040  link to a file that does not exist
  D041  link to a heading that does not exist
  D042  a link into project/, or a ticket named in prose

Machinery that belongs to a docs website, not to a repository
  D030  <a name="..."> anchor
  D031  {{version}} in a link
  D032  <div class="..."> or <style> block

A *.review.md report answers to links and formatting only: D001-D003, D012,
D015, D026 and D042 skip it."""

if cmd == "rules":
    print(RULES); sys.exit(0)

INTERNALS = r"\b(base class|under the hood|behind the scenes|internally|is not declared|are not declared|the framework calls|abstract class|parent class|inheritance)\b"
WARMTH = r"\b(convenient(ly)?|expressive|powerful|beautiful|blazing|wonderful|enjoyable|effortless|seamless)\b"
CONTRACTION = r"\b(don't|doesn't|didn't|can't|won't|isn't|aren't|wasn't|weren't|hasn't|haven't|couldn't|shouldn't|wouldn't|it's|that's|there's|you'll|you're|they're)\b"
ADVISORY = {"D023", "D026", "D027"}
# A *.review.md report is a maintainer's critique of a page, not a page: it
# answers to links and formatting, never to the page skeleton, the rhythm, or
# the rules about what a reader of docs/ may be sent to. It quotes errors at
# whatever width they came, and cites the ticket that owns the gap.
REVIEW_EXEMPT = {"D001", "D002", "D003", "D012", "D015", "D026", "D042"}
WIDTH = int(os.environ.get("DOCS_EXAMPLE_WIDTH", "62"))
PROJECT = os.path.realpath(os.environ.get("PROJECT_DIR", "project"))
TICKET = r"(?<![\w/.-])((?:spec|done|todo|idea|spike|issue|reject)-[a-z0-9_-]+\.md)"

def slug(h):
    h = h.replace("`", "").lower()
    h = re.sub(r"[^a-z0-9 \-]", "", h)
    return re.sub(r"\s+", "-", h.strip())

def parse(text):
    """Split a page into typed lines: (n, kind, raw). kind is code/fence/head/toc/quote/html/table/list/prose/blank."""
    out, incode = [], False
    for n, raw in enumerate(text.split("\n"), 1):
        s = raw.strip()
        if s.startswith("```"):
            out.append((n, "fence", raw)); incode = not incode; continue
        if incode:
            out.append((n, "code", raw)); continue
        if not s:                      k = "blank"
        elif s.startswith("#"):        k = "head"
        elif s.startswith(">"):        k = "quote"
        elif s.startswith("|"):        k = "table"
        elif re.match(r"^([-*+]|\d+\.)\s", s): k = "list"
        elif s.startswith("<"):        k = "html"
        else:                          k = "prose"
        out.append((n, k, raw))
    return out

def heading_ids(heads):
    """The id each heading gets, in order and never one already taken. A repeat is numbered -1, -2, stepping past any number a heading already holds, as GitHub does."""
    counts, ids = {}, []
    for _, _, t in heads:
        base = candidate = slug(t)
        while candidate in counts:
            counts[base] += 1
            candidate = f"{base}-{counts[base]}"
        counts[candidate] = 0
        ids.append(candidate)
    return ids

_lines_cache = {}
def get_lines(path):
    """parse(), memoized per resolved path - lint, stats and anchors all read the same pages."""
    key = str(Path(path).resolve())
    if key not in _lines_cache:
        _lines_cache[key] = parse(Path(path).read_text())
    return _lines_cache[key]

def anchors(path):
    """Every id a page offers a link."""
    return set(heading_ids(headings(get_lines(path))))

def headings(lines):
    return [(n, len(m.group(1)), m.group(2).strip())
            for n, k, raw in lines if k == "head"
            for m in [re.match(r"^(#+)\s+(.*)$", raw.strip())] if m]

def lint(path):
    lines = get_lines(path)
    heads = headings(lines)
    found = []
    def hit(n, code, msg): found.append((n, code, msg))

    # --- structure
    h2 = [(n, t) for n, lvl, t in heads if lvl == 2]
    if not h2:
        hit(1, "D001", "no ## sections at all")
    elif h2[0][1].startswith("Meet "):
        pass                                    # the front door is exempt
    elif h2[0][1] != "Introduction":
        hit(h2[0][0], "D001", f'first ## is "{h2[0][1]}", expected "Introduction"')

    toc = [(n, m.group(1), m.group(2)) for n, k, raw in lines if k == "list"
           for m in [re.match(r"^\s*[-*+]\s*\[(.+?)\]\(#(.+?)\)\s*$", raw)] if m
           and (not h2 or n < h2[0][0])]
    ids = heading_ids(heads)
    nav = [(n, lvl, t, i) for (n, lvl, t), i in zip(heads, ids) if lvl in (2, 3)]
    if not toc:
        if len(nav) > 1:
            hit(1, "D002", "no table of contents above the first section")
    else:
        want = [i for _, _, _, i in nav]
        have = [a for _, _, a in toc]
        for a in have:
            if a not in want:
                n = next(n for n, _, x in toc if x == a)
                hit(n, "D002", f'contents link "#{a}" matches no ## or ### heading')
        for n, lvl, t, i in nav:
            if i not in have:
                hit(n, "D002", f'"{t}" is missing from the contents')
        for (n, lvl, t), i in zip(heads, ids):
            if lvl >= 4 and i in have:
                hit(n, "D003", f'"{t}" is a #### and does not belong in the contents')
        if [a for a in have if a in want] != [w for w in want if w in have]:
            hit(toc[0][0], "D002", "contents are in a different order than the headings")

    tail = {}
    for n, lvl, t in heads:
        if lvl != 2: continue
        if t == "Testing": tail.setdefault("testing", n)
        elif t == "Events" or t.endswith("Events"): tail.setdefault("events", n)
        elif "Custom" in t: tail.setdefault("custom", n)
    if "testing" in tail:
        for k in ("events", "custom"):
            if k in tail and tail[k] < tail["testing"]:
                hit(tail["testing"], "D004", f"Testing comes after {k}; it leads the tail sections")

    # --- rhythm
    paras_since_code = 0
    depth = 0
    i = 0
    while i < len(lines):
        n, k, raw = lines[i]
        if k != "fence":
            if k == "prose":
                paras_since_code += 1
                if paras_since_code == 6:
                    hit(n, "D012", "six paragraphs without a code block; show it instead")
            i += 1
            continue
        depth += 1
        if depth % 2 == 0:          # a closing fence, already handled
            i += 1
            continue
        lang = raw.strip()[3:].strip()
        if not lang:
            hit(n, "D013", "code fence with no language")
        j = i + 1
        while j < len(lines) and lines[j][1] != "fence":
            j += 1
        length = j - i - 1
        if length > 20:
            hit(n, "D011", f"code block is {length} lines; past 20 it is doing two things")
        p = i - 1
        while p >= 0 and lines[p][1] == "blank":
            p -= 1
        if p >= 0:
            pk, praw = lines[p][1], lines[p][2].strip()
            if pk == "head":
                hit(n, "D005", "code opens the section with no sentence leading into it")
            elif pk in ("prose", "list", "quote") and not praw.endswith((":", ";")):
                hit(n, "D010", "the sentence above does not end in a colon")
        paras_since_code = 0
        depth += 1                  # consume the closing fence
        i = j + 1

    # --- reference entries: #### `name()` must be followed by "The `name` ..."
    for idx, (n, lvl, t) in enumerate(heads):
        if lvl < 4:
            continue
        m = re.fullmatch(r"`([A-Za-z0-9_:\\]+)\(\)`", t.strip())
        if not m:
            continue
        name = m.group(1).split("::")[-1]
        nxt = next((raw.strip() for ln, kk, raw in lines
                    if ln > n and kk not in ("blank",)), "")
        if not re.match(rf"^The `[^`]*\b{re.escape(name)}` (method|helper|function|rule|field)\b", nxt):
            hit(n, "D014", f'entry should open "The `{name}` method ..."')

    # --- bullets against paragraphs, per section
    bounds = [n for n, lvl, _ in heads if lvl == 2] + [10**9]
    for lo, hi in zip(bounds, bounds[1:]):
        b = sum(1 for n, k, _ in lines if lo < n < hi and k == "list")
        pr = sum(1 for n, k, _ in lines if lo < n < hi and k == "prose")
        if b > pr and b >= 4:
            hit(lo, "D026", f"{b} bullets against {pr} paragraphs; this voice explains in prose")

    # --- voice, machinery
    intro_lo = intro_hi = None
    for idx, (n, lvl, t) in enumerate(heads):
        if lvl == 2 and t == "Introduction":
            intro_lo = n
            intro_hi = next((m for m, l2, _ in heads[idx+1:] if l2 == 2), 10**9)
            break
    for n, k, raw in lines:
        if k in ("code", "fence"): continue
        bare = re.sub(r"`[^`]*`", "", raw)
        if re.search(CONTRACTION, bare, re.I):
            hit(n, "D020", f'contraction: "{re.search(CONTRACTION, bare, re.I).group(0)}"')
        if re.search(r"\byou can\b", bare, re.I):
            hit(n, "D021", '"you can" - the house form is "you may"')
        if k != "head" and re.search(WARMTH, bare, re.I):
            if intro_lo is None or not (intro_lo <= n < intro_hi):
                hit(n, "D022", f'"{re.search(WARMTH, bare, re.I).group(1)}" outside the introduction')
        if k == "prose" and re.search(INTERNALS, bare, re.I):
            hit(n, "D027", f'"{re.search(INTERNALS, bare, re.I).group(1)}" describes the implementation; name the capability instead')
        if re.search(r"\b(we|let's|we'll)\b", bare, re.I) and k == "prose":
            hit(n, "D023", "first person outside a walkthrough - judge whether this page is one")
        if "—" in raw or "–" in raw:
            hit(n, "D024", "em-dash or en-dash; use a spaced hyphen")
        if "<a name" in raw:
            hit(n, "D030", "anchor tag; headings generate their own slugs")
        if "{{version}}" in raw:
            hit(n, "D031", "{{version}} link; use a relative path")
        if re.search(r'<div class=|<style>', raw):
            hit(n, "D032", "website markup in a repository page")

    for idx in range(len(lines) - 1):
        n, k, raw = lines[idx]
        n2, k2, raw2 = lines[idx + 1]
        if k == "prose" and k2 == "prose":
            hit(n2, "D025", "hard-wrapped paragraph; one line per paragraph")

    # --- links, and the line between docs/ and project/
    here = Path(path).resolve()
    for n, k, raw in lines:
        if k in ("code", "fence"):
            if k == "code" and len(raw.rstrip()) > WIDTH:
                hit(n, "D015", f"example line is {len(raw.rstrip())} characters; break it to {WIDTH} or fewer")
            continue
        bare = re.sub(r"`[^`]*`", "", raw)
        for target in re.findall(r"\]\(([^)]+)\)", bare):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue
            page, _, frag = target.partition("#")
            base = here.parent / page
            dest = here if not page else next((c.resolve() for c in (base, Path(str(base) + ".md")) if c.exists()), None)
            if dest is None:
                hit(n, "D040", f"link to a file that does not exist: {target}")
                continue
            if str(dest).startswith(PROJECT + os.sep):
                hit(n, "D042", f"links into project/: {target}")
            if frag and dest.suffix == ".md" and frag not in anchors(dest):
                hit(n, "D041", f"no heading on {dest.name} for #{frag}")
        for ticket in sorted(set(re.findall(TICKET, bare))):
            hit(n, "D042", f"names {ticket}; docs never send a reader into project/")

    if str(path).endswith(".review.md"):
        found = [f for f in found if f[1] not in REVIEW_EXEMPT]
    return sorted(set(found))

def stats(paths):
    prose = code = 0
    blocks, runs, sents, paras = [], [], [], []
    may = can = notes = warns = 0
    h = {2: 0, 3: 0, 4: 0}
    for p in paths:
        lines = get_lines(p)
        run = 0; depth = 0; length = 0
        for n, k, raw in lines:
            if k == "fence":
                depth += 1
                if depth % 2 == 0:
                    blocks.append(length); length = 0
                else:
                    runs.append(run); run = 0
                continue
            if k == "code": code += 1; length += 1; continue
            if k == "blank": continue
            prose += 1
            if k == "head":
                m = re.match(r"^(#+)", raw.strip())
                if m and len(m.group(1)) in h: h[len(m.group(1))] += 1
            if k == "quote":
                if "[!NOTE]" in raw or "**Note**" in raw: notes += 1
                if "[!WARNING]" in raw or "**Warning**" in raw: warns += 1
            if k == "prose":
                run += 1
                b = re.sub(r"`[^`]*`", "", raw.strip())
                paras.append(len(b.split()))
                may += len(re.findall(r"\byou may\b", b, re.I))
                can += len(re.findall(r"\byou can\b", b, re.I))
                for s in re.split(r"(?<=[.!?]) ", b):
                    if len(s.split()) > 2: sents.append(len(s.split()))
    med = lambda xs: statistics.median(xs) if xs else 0
    rows = [
        ("prose lines : code lines", f"1 : {code/prose:.2f}" if prose else "-", "1 : 2"),
        ("code block length, median", f"{med(blocks):.0f}", "about 5, cap 20"),
        ("longest code block", f"{max(blocks) if blocks else 0}", "20"),
        ("paragraphs between blocks, median", f"{med(runs):.0f}", "about 3"),
        ("sentence length, median", f"{med(sents):.0f}", "about 17"),
        ("paragraph length, median", f"{med(paras):.0f}", "about 30"),
        ('"you may" : "you can"', f"{may} : {can}", "you may wins"),
        ("notes : warnings", f"{notes} : {warns}", "as few as earn it"),
        ("## / ### / ####", f"{h[2]} / {h[3]} / {h[4]}", "more ### than ##"),
    ]
    w = max(len(r[0]) for r in rows)
    print(f"{'':{w}}  {'this corpus':>14}   target")
    for name, got, want in rows:
        print(f"{name:{w}}  {got:>14}   {want}")

if cmd == "toc":
    heads = headings(parse(Path(paths[0]).read_text()))
    for (n, lvl, t), i in zip(heads, heading_ids(heads)):
        if lvl == 2: print(f"- [{t}](#{i})")
        elif lvl == 3: print(f"    - [{t}](#{i})")
    sys.exit(0)

if cmd in ("lint", "all"):
    hard = 0
    for p in paths:
        try:
            rel = str(Path(p).resolve().relative_to(Path.cwd()))
        except ValueError:
            rel = str(p)
        for n, code_, msg in lint(p):
            tag = " (advisory)" if code_ in ADVISORY else ""
            if code_ not in ADVISORY: hard += 1
            print(f"{rel}:{n}: {code_}  {msg}{tag}")
    if cmd == "all":
        print()
        stats(paths)
    sys.exit(1 if hard else 0)

if cmd == "stats":
    stats(paths)
PY
