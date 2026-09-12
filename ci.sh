#!/usr/bin/env bash
# ci.sh - run every check this plugin ships against the repo in the working
# directory: `project.sh check` when there is a project/, `docs.sh lint` when
# there is a docs/. Exits 1 when either finds anything.
#
# Locally, from a checkout of the plugin:
#   bash path/to/project/ci.sh
# In CI, pinned to a tag so a plugin release never turns a build red by itself:
#   curl -fsSL https://raw.githubusercontent.com/dillingham/project/v0.2.1/ci.sh | bash -s v0.2.1
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd)"
if [ ! -f "$here/skills/cli/project.sh" ]; then
  ref="${1:?piped in, so pass the tag it came from: curl ... | bash -s <tag>}"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/project-ci.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" https://github.com/dillingham/project "$tmp"
  here="$tmp"
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
status=0

if [ -d "$root/project" ]; then
  echo "== project.sh check"
  bash "$here/skills/cli/project.sh" check || status=1
fi
if [ -d "$root/docs" ]; then
  echo "== docs.sh lint"
  bash "$here/skills/docs/docs.sh" lint || status=1
fi

exit "$status"
