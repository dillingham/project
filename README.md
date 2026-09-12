# project

A Claude Code plugin for running a project out of markdown: a board in `project/`, a git worktree per ticket, user docs in one house voice, and a QA hunt that pins every bug it finds with a failing test.

## Install

```
/plugin marketplace add dillingham/project
/plugin install project@dillingham
```

Updates arrive with `/plugin marketplace update dillingham`.

| Skill | Does |
| --- | --- |
| `/project:chat <question>` | answers anything about the work - what's next, what's open, file this, close that, let's spike X |
| `/project:cli [command]` | runs the board script and prints its raw output; no arguments prints the menu |
| `/project:worktree <id>` | starts work on a ticket in a fresh, fully set up git worktree |
| `/project:docs [spec or page]` | writes, revises or lints the pages in `docs/` |
| `/project:qa <feature>` | hunts a feature in a real browser for bugs the other suites cannot see |

Claude also reaches for each one on its own when the conversation calls for it - filing an aside you drop mid-task, or starting a worktree when you say "let's start on X".

## The board

Every piece of work is one markdown file in `project/`, named `{status}-{name}.md`:

```
project/
  issue-fields-injection.md
  todo-next-up.md
  done-resolution-ladder.md
  spec-binding.md
```

The **status is the first word**. So `ls project/` is the board, and changing a ticket's status is renaming its file.

### Dropping something in mid-session

This is the part that earns the system.

Say something in passing while an agent is working - "that reminds me, selects can't reach an API" - and it writes a file and keeps going:

```
filed issue-select-api-source.md
```

No stopping to decide where it belongs, no approval, no derail. The rule in the skill is *filing is never an interruption*. Same when the agent finds something itself that isn't the job in front of it.

That only works because deciding is cheap, which is what the ticket types are for.

### The ticket types

| Prefix | Means | Usually becomes |
| --- | --- | --- |
| `idea-` | a raw thought, unexamined | `spike-`, or `reject-` |
| `spike-` | a question to investigate, no committed outcome | `todo-`, or `reject-` |
| `todo-` | decided, described well enough to start | `done-` |
| `issue-` | a real gap, documented, deliberately not being worked now | `todo-` when scheduled |
| `done-` | shipped, with the reasoning that got it there | stays |
| `reject-` | considered and not taken, or superseded | stays |

Two more that are not work items:

- `spec-` is a feature definition. `spec-binding.md`, `spec-fields-select.md`.
- `list-` is a holding pen of one-liners, like `list-minor.md`. Too small for their own files; promote one out when someone picks it up.

`issue-` does the heavy lifting. It is the parking lot: real, written down, and consciously not today's job. Without it every finding is either a derail or a loss.

### Asking about it

```
/project:chat what's next?
/project:chat what's open?
/project:chat anything about scoping?
```

Behind it is `project.sh`, which reads the folder and answers in one pass. `/project:cli` runs it directly:

```
$ /project:cli next
high  issue  issue-fields-injection  2026-08-23 15:52  0d BLOCKS:5  fields() cannot take parameters  spec-blocks.md, spec-fields.md
high  issue  issue-submit-entry-point  2026-08-23 15:52  0d  submit() and the Form entry point are unbuilt  spec-forms.md
```

The point is that an agent runs one command instead of grepping and reading twenty files. It is tab-separated on purpose - cheap to read, nothing to parse.

### Moving a ticket

```
/project:cli move spike idea-select-api.md
```

This appends a `## Spike` section, renames the file, and updates references to its old filename throughout repository text files. **It preserves the reasoning above, repairing references even in older sections.** A ticket accumulates its own history:

```markdown
# Selects cannot reach an API

## Idea
Wondered whether options could come from somewhere other than a relation.

## Spike
Checked: a third source branch is cheap. Auth is not - an API source needs
credentials the block does not have.

## Done
Shipped as `Options`, resolved from the container so it can take dependencies.
```

The wrong guess in `## Idea` is worth keeping. It is why the `## Done` looks the way it does.

### What landed

`project/changelog.md` is the readable half of the board. One line per landed change, newest first, each linking the `done-` ticket that carries the reasoning:

```markdown
## 2026-08-23

- Route binding left the `#[Bind]` attribute for a binder, nested bindings scope by default - [done-binder.md](done-binder.md), [done-scoped-bindings-by-default.md](done-scoped-bindings-by-default.md)
```

It is not a second copy of the `done-` files. Those are the complete record and one per ticket; a changelog line is one per CHANGE, so a batch of related tickets collapses into a single entry with several links. `move done <filename>` prompts for the line at the moment you have just written the `## Done`, which is when the one-sentence version is cheapest.

### Priority, and `groom`

Every ticket carries one line:

```
Priority: groom | low | medium | high | critical
```

Judged by impact, never effort. `critical` is flat out wrong or hits every user; `low` is an edge case worth fixing.

**`groom` means nobody has judged it yet.** It sorts below `low`, because an unknown is not a claim, and `/project:cli groom` is the queue. It exists so you can file something without pricing it in the moment - which is the whole reason filing stays cheap.

### Blocked items

Some tickets cannot start yet. They say so, and why:

```
Blocked: issue-fields-injection.md - same mechanism, one line each once it lands
```

A blocked ticket disappears from `next`, because offering work nobody can start is noise. It is not `groom` either - its priority is deferred, not unknown.

You only write the blocked direction. The board counts backwards and shows `BLOCKS:5` on the blocker itself, which is usually the real argument for its priority.

When a blocker ships, its dependents flag `UNBLOCKED?` and `/project:cli unblocked` lists them. Nothing is edited - the flag is a prompt to look, because "the blocker shipped" does not always mean "this can start".

### Automatic grooming

The queue drains by itself in two places, both tool-driven so nobody has to remember:

- **`next`** surfaces one `groom` item alongside the real work. Triage before you start, which can change what you pick.
- **`move done <filename>`** shows the untriaged tickets sharing that spec. You just finished the work, so you have the context they need, and it costs a glance.

What is deliberately *not* automated is the priority itself. An agent assigning one cold has less context than you do, and a guess with a confident reason underneath is worse than an honest `groom`.

### Claiming

A ticket is claimed by the worktree `/project:worktree` opens for it - its branch is named after the ticket, and `git worktree list` is shared by every checkout, so there is no header to write. A claimed ticket shows `CLAIMED` and drops out of `next` until the worktree is removed.

## Settings

| Variable | Default | For |
| --- | --- | --- |
| `PROJECT_STALE_DAYS` | `30` | days idle before a ticket sorts up one priority |
| `PROJECT_WORKTREES` | `~/Worktrees` | where `/project:worktree` puts worktrees |
| `DOCS_DIR` | `docs/` | where `/project:docs` looks for pages |

## Changing it

[skills/chat/SKILL.md](skills/chat/SKILL.md) is the operating manual an agent reads. [skills/chat/decisions.md](skills/chat/decisions.md) is why each of these is shaped the way it is, and which obvious alternatives were tried and rejected - read that one before changing how any of this works. `bash skills/cli/project.test.sh` exercises the move command in throwaway repositories.
