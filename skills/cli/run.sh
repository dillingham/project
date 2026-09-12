#!/usr/bin/env bash
# The /project:cli entry point. A command failing inside a skill's !`...` line
# aborts the skill before its instructions reach the model, and project.sh
# exits non-zero on purpose - check with findings, a usage error. So run it,
# say how it ended, and always succeed.
bash "$(dirname "${BASH_SOURCE[0]}")/project.sh" "$@" 2>&1
status=$?
[ "$status" -eq 0 ] || echo "[exit $status]"
exit 0
