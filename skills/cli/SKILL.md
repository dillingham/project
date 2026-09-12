---
name: cli
description: "Run the project board script directly: `/project:cli <command> [args]`, such as `next`, `open`, `board`, `find <term>`, `show <id>`, `new <status> <name>` or `move <status> <filename>`. With no arguments it prints the full command menu, then what to pick up. Raw output, no interpretation - a question in plain words is /project:chat."
argument-hint: "[next | open | board | find <term> | show <id|status> | new <status> <name> | move <status> <file> ...]"
disable-model-invocation: true
---

!`bash "${CLAUDE_SKILL_DIR}/project.sh" $ARGUMENTS 2>&1; echo "[exit $?]"`

Relay the output above to the user exactly as printed, in a code block, and add nothing - no summary, no recommendation, no follow-up question. This is the raw CLI; `/project:chat` is the one that interprets. When the exit line is not `[exit 0]`, show the output and stop.
