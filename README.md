# project

A Claude Code plugin that gives your agent the tools to automate project management and follow consistent Git and GitHub standards. The agent can maintain a Markdown board, set up worktrees, resume work across sessions, make meaningful commits, write docs, hunt bugs and prepare pull requests with linked context and test evidence. Specs, tickets and decisions stay in your repository; you control what gets merged.

## Skills

Speak naturally: "what's next?", "let's start on slugify", "remember this for later", or "carry on where we left off". The agent selects relevant skills as the conversation develops and offers to open a PR when the work is ready for review. You can also invoke them directly:

| Skill | What the agent does |
| --- | --- |
| [/project:chat](skills/chat/SKILL.md) | Plans work, captures ideas and issues, tracks priorities and dependencies, investigates decisions, and resumes tickets. |
| [/project:worktree](skills/worktree/SKILL.md) | Creates a ticket branch in its own worktree and sets up dependencies and the app environment. |
| [/project:docs](skills/docs/SKILL.md) | Writes or reviews user documentation against the code and checks its house style. |
| [/project:qa](skills/qa/SKILL.md) | Hunts bugs in a real browser and pins confirmed failures with reproducing tests. |
| [/project:pr](skills/pr/SKILL.md) | Uses the current context to prepare or revise a PR, link related work, and validate the description. |
| [/project:backfill](skills/backfill/SKILL.md) | Brings work from notes, GitHub issues or a part of the code onto the board as specs, tickets and lists, ready to triage. |
| [/project:cli](skills/cli/SKILL.md) | Runs board commands directly and returns their raw output. With no arguments, shows the menu. |
| [/project:contribute](skills/contribute/SKILL.md) | Changes this plugin in a source checkout, tests the changes, and prepares them for review. |

## Git and GitHub standards

- **One worktree per ticket.** A worktree claims its ticket so other sessions can see it is taken. The claim follows status changes, and ticket updates merge with the code.
- **Meaningful commits.** Commit a coherent change, a settled decision or substantial progress worth preserving. Capitalize the subject and leave the ticket out of it, such as `Map Latin characters explicitly`, and carry the ticket's stable name in a trailing `Branch: slugify` line instead - it outlives the branch itself, findable with `git log --grep` even after the branch is deleted. Explain useful reasoning in the body. User edits in shared files, and changes that depend on them, stay uncommitted for review.
- **PRs with context and evidence.** `/project:pr` uses the current conversation and branch. Descriptions open with an overview, followed by `### Changes`, `### Related` and `### Testing`. Related work links specs, tickets and PRs; testing names commands, results and what was verified. A validator checks structure and style; the agent checks the claims against the work.
- **Visible handoffs.** The agent reports the branch, latest commit, verification results, anything uncommitted, and a review command such as `git diff main...slugify`. It distinguishes tests of the committed snapshot from tests of the working tree. PR publication follows your request; commits on the default branch and merges require your instruction.

Your instructions and repository conventions take precedence over the plugin's defaults.

## The board

The board is a flat `project/` folder. Each file is named `{status}-{name}.md`, so a directory listing shows the state of the work:

```text
project/
  idea-api-source.md
  todo-slugify.md
  issue-feed-dates.md
  done-route-binding.md
  spec-slugs.md
```

| Prefix | Meaning |
| --- | --- |
| `idea-` | A thought to consider. |
| `spike-` | A question to investigate before choosing an approach. |
| `todo-` | Decided work, described well enough to start. |
| `issue-` | A known gap parked for later. |
| `done-` | Completed work and the reasoning behind it. |
| `reject-` | A considered approach that was declined or superseded. |
| `spec-` | A feature definition, separate from its work items. |
| `list-` | Small ideas or deferrals that do not yet need individual tickets. |

**Capture without derailing.** An aside becomes a ticket in the active checkout, and the agent continues its original task. Priorities reflect impact: `low`, `medium`, `high` or `critical`. `groom` means the item has not been judged yet.

**Choose available work.** `next` ranks work, excludes claimed or blocked tickets, and surfaces one item to triage. Dependency counts highlight blockers; `UNBLOCKED?` flags dependents worth revisiting when their blocker lands.

**Resume with the reasoning intact.** Moving a ticket renames it, repairs references and appends a status section. Dated checkpoints preserve progress, failed approaches, open questions, the next action and a verification command. `resume` brings that context into a fresh session. The changelog links completed tickets into an account of what landed.

```text
/project:cli next
/project:cli resume todo-slugify
/project:cli move todo spike-api-source.md
/project:cli check
```

See the [board guide](skills/chat/SKILL.md) for the full workflow.

## Install

```text
/plugin marketplace add dillingham/project
/plugin install project@dillingham
```

Updates arrive with `/plugin marketplace update dillingham`.

Worktrees live in `~/Worktrees` by default. Allow that folder once using its absolute path in `permissions.additionalDirectories` in `~/.claude/settings.json`, or grant access for a session with `claude --add-dir ~/Worktrees`.

## Checks and settings

`ci.sh` checks the board and documentation for broken references and other consistency or style problems. Pin a released tag in CI:

```sh
curl -fsSL https://raw.githubusercontent.com/dillingham/project/v0.5.0/ci.sh | bash -s v0.5.0
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `PROJECT_STALE_DAYS` | `30` | Days idle before a judged, available ticket moves up one priority level. |
| `PROJECT_WORKTREES` | `~/Worktrees` | Where ticket worktrees are created. |
| `PROJECT_LOCK_WAIT` | `60` | Seconds a worktree start waits for another start to finish. |
| `DOCS_DIR` | `docs/` | Where documentation is read and checked. |
| `DOCS_EXAMPLE_WIDTH` | `62` | Maximum line width for documentation examples. |

For the reasoning behind the workflow, read [decisions.md](skills/chat/decisions.md). To change the plugin, follow the [contribution guide](skills/contribute/SKILL.md).
