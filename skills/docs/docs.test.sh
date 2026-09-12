#!/usr/bin/env bash
# Plant the defects the link and width rules exist for, in a throwaway repo,
# and check each is reported - and that what is fine stays silent. A rule that
# reports a list is green both when nothing is wrong and when it is not running.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docs.sh"
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/docs-test.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/docs" "$TEMP/project"
git -C "$TEMP" init -q

at=$(printf 'a%.0s' $(seq 62)); over=$(printf 'b%.0s' $(seq 63))
printf '# Spec\n' > "$TEMP/project/spec-thing.md"
printf '# Other\n\n## Introduction\n\n## Usage\n' > "$TEMP/docs/other.md"
cat > "$TEMP/docs/page.md" <<DOC
# Page

## Introduction

Fine: [usage](other.md#usage), [same page](#introduction), [site](https://example.com).

Broken: [gone](missing.md), [nope](other.md#nope), [spec](../project/spec-thing.md), and spec-thing.md by name.

Two lines of example follow:

\`\`\`php
$at
$over
\`\`\`
DOC
cp "$TEMP/docs/page.md" "$TEMP/docs/page.review.md"

out=$(cd "$TEMP" && bash "$SCRIPT" lint page.md page.review.md || true)
fail() { echo "FAIL: $1"; echo "$out"; exit 1; }
expect() { grep -Fq -- "$1" <<<"$out" || fail "missing: $1"; }
refuse() { ! grep -Fq -- "$1" <<<"$out" || fail "unexpected: $1"; }

expect 'docs/page.md:7: D040  link to a file that does not exist: missing.md'
expect 'docs/page.md:7: D041  no heading on other.md for #nope'
expect 'docs/page.md:7: D042  links into project/: ../project/spec-thing.md'
expect 'docs/page.md:7: D042  names spec-thing.md'
expect 'docs/page.md:13: D015  example line is 63 characters'
refuse 'docs/page.md:12:'
refuse 'docs/page.md:5:'
expect 'docs/page.review.md:7: D040'
refuse 'docs/page.review.md:7: D042'
refuse 'docs/page.review.md:13: D015'
echo 'PASS: links, anchors, the project/ boundary and example width, with review sidecars exempt from the last two'

printf '# Dup\n\n## Introduction\n\n## Usage\n\n## Usage\n\nSee [one](#usage), [two](#usage-1) and [three](#usage-2).\n' > "$TEMP/docs/dup.md"
out=$(cd "$TEMP" && bash "$SCRIPT" lint dup.md || true)
expect 'docs/dup.md:9: D041  no heading on dup.md for #usage-2'
refuse '#usage-1'
echo 'PASS: a repeated heading is reachable at its numbered anchor, and only that far'

# The whole page, not one message: a valid page with repeated headings has to
# lint clean, and the contents it implies have to be the ones it carries.
cat > "$TEMP/docs/repeated.md" <<'DOC'
# Repeated

- [Introduction](#introduction)
- [Usage](#usage)
    - [Options](#options)
- [Usage](#usage-1)
    - [Options](#options-1)

## Introduction

See [the first usage](#usage) and [the second](#usage-1).

## Usage

The first.

### Options

The first options.

## Usage

The second.

### Options

The second options.
DOC
out=$(cd "$TEMP" && bash "$SCRIPT" lint repeated.md 2>&1) || fail 'a valid page with repeated headings failed lint'
[ -z "$out" ] || fail 'a valid page with repeated headings reported findings'
toc=$(cd "$TEMP" && bash "$SCRIPT" toc repeated.md)
[ "$toc" = "$(sed -n '3,7p' "$TEMP/docs/repeated.md")" ] || { out="$toc"; fail 'toc did not reproduce the contents the page carries'; }
echo 'PASS: a valid page with repeated headings lints clean, and toc generates its contents exactly' 
