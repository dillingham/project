---
name: cli
description: "Run the project board script directly: `/project:cli <command> [args]`, such as `next`, `open`, `board`, `find <term>`, `show <id>`, `new <status> <name>` or `move <status> <filename>`. With no arguments it prints the full command menu, then what to pick up. Raw output, no interpretation - a question in plain words is /project:chat."
argument-hint: "[next | open | board | find <term> | show <id|status> | new <status> <name> | move <status> <file> ...]"
disable-model-invocation: true
allowed-tools: Bash(bash:*)
---

!`bash "${CLAUDE_SKILL_DIR}/run.sh" $ARGUMENTS`

Relay the output above to the user exactly as printed, in a code block, and add nothing - no summary, no recommendation, no follow-up question. This is the raw CLI; `/project:chat` is the one that interprets. An `[exit N]` last line means the command failed or, for `check`, found problems: show the output and stop.
