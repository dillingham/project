---
name: backfill
description: "Use when work that belongs on the board lives somewhere else - a folder of markdown notes, GitHub issues, or a part of the codebase with no spec and TODO comments scattered through it. Invoked as `/project:backfill <folder>`, `/project:backfill gh [search]` or `/project:backfill <Subject or path>`, such as `/project:backfill EmailReminder`. The bundled backfill.sh lists what the source holds and which board files already cite it; subagents read the source and return proposals; one pass dedupes them against the board and writes specs, tickets and lists, every ticket at Priority: groom. Ends with counts of what was filed, merged, dropped and left open. Also for re-running an import to pick up what is new since the last one."
argument-hint: "<notes folder> | gh [search] | <Subject or path>"
---

# Backfill

Work that predates the board lives in notes, issue trackers and TODO comments. Backfill brings it onto the board in the board's own shape, so `next`, `find` and `spec` can see it. A script collects and the agent decides, the split [decisions.md](../chat/decisions.md) makes for grooming: what a source holds and what the board already cites is research; what each item becomes is judgement.

Operating the board is [chat](../chat/SKILL.md), and everything it says about statuses, headers, appending and writing holds here. This file adds only what an import needs.

## When invoked

```
B="${CLAUDE_SKILL_DIR}/backfill.sh"
P="${CLAUDE_SKILL_DIR}/../cli/project.sh"
```

| Argument | Source | Collect with |
| --- | --- | --- |
| a folder of markdown notes | documents, open checkboxes, TODO markers | `$B md <dir>` |
| `gh`, or `gh <search>` such as `gh label:bug` | open GitHub issues | `$B gh [search]` |
| a path, or a subject such as `EmailReminder` | the files under that path, or every file naming the subject in any spelling, and their TODO markers | `$B code <path or subject>` |

A folder of code rather than notes is the `code` source. When the argument is missing, or could be either, ask.

Output is tab-separated, one candidate per line:

```
ref  kind  title  board
```

`kind` is `doc`, `open` (an unchecked checkbox) or `marker` (TODO, FIXME, HACK, XXX) from notes, `issue` from GitHub, and `file` or `marker` from code. `board` lists the `project/` files that already cite the row's source, or `-`. On a rerun that column is where to start: read those files before proposing anything, but a cited source does not mean every item in it is covered.

**The rows are an index, not the content.** A `doc`, `file` or `issue` row means read the whole thing: a decision, an open question or a plan sits in prose no pattern finds, and a ticked box can claim work the code does not have.

## 1. Read the board first

Run `$P all` and `ls project/spec-*`, then `$P find` and `$P spec` for the subject when there is one. Every proposal needs to know what already exists, or the import files a second copy of work the board already carries.

## 2. Swarm the reading, not the writing

When there are more rows than one agent can read carefully, split them into chunks - by folder, by issue range, by directory - and send one subagent per chunk, all in one message. Give each the board listing from step 1, its rows, and the filing rules below.

**Subagents return proposals and write nothing.** Two agents writing at once file the same work under two names, and neither can see the other's file to notice. Each proposal says:

```
file: todo-token-refresh.md (new)  |  extends: spec-auth.md
status: todo - decided in the notes; `grep -r TokenRefresher src/` finds nothing
spec: spec-auth.md
from: notes/auth.md, notes/sessions.md
body:
<the markdown to write or append>
dropped:
- notes/auth.md:12 switch sessions to JWT - shipped, src/Auth/JwtGuard.php
```

Every row a subagent was given ends up under a `from:` or a `dropped:`, so nothing falls between chunks unaccounted for.

## 3. Merge, then write

One agent - you, not a subagent - merges the proposals:

- Collapse proposals for the same work, from two notes or two issues, into one file citing both sources.
- Check each against the board with `$P find <its key term>`. A match is appended to, never duplicated and never rewritten.
- Create each new file with `$P new <status> <name>`, so the header is the board's own, then write its title and body. `new` writes `Priority: groom` on every file; delete it from a `spec-` or a `list-`, which carry none.
- Extend an existing ticket by appending under its current section. A `spec-` that already owns the subject is governed by the repo, per chat's Where things belong: file tickets against it with `Spec:`, and report what it is missing rather than rewriting it.

Then run `$P check`, and fix whatever it reports in files you wrote.

## Filing rules

**Every ticket is `Priority: groom`.** An import is the case `groom` exists for. Never guess a priority from a source's tone. When the source carries its own signal - a `p1` label, "urgent" in a note - quote it in the body so the triage session has it, and leave the header at `groom`. Promise nothing about what `next` will pick. Say a dependency in prose rather than as `Blocked:`, which drops a ticket out of `groom` - the queue an import is feeding - and let triage decide whether it blocks.

**Ask what is true, per chat's Choosing the prefix.** A decided change with nothing left to settle is a `todo-`, a known gap an `issue-`, an open question a `spike-`, and a thought an `idea-`. A TODO comment is usually an `issue-` or an `idea-`: it records a gap someone noticed and chose not to fix. It is a `todo-` only when the comment or the code around it says what to do.

**Verify before filing.** A note or an issue can be months older than the code. Before filing an open commitment, look for it in the code. Shipped work goes under `dropped:` with the file that proves it, or becomes a `done-` when its reasoning is worth keeping. A superseded plan becomes a `reject-` on the same test, and is dropped otherwise.

**Thin items share a file.** One-liners - most checkboxes, most TODO markers - are bullets in a `list-<subject>.md`, per chat's Small things group, not a file each.

**Cite the source in the body**, in backticks, spelled as the `ref` column printed it but without the line number: ``Backfilled from `notes/auth.md`.``, ``Backfilled from gh#142, https://github.com/acme/app/issues/142.``, ``Backfilled from `src/Reminders/EmailReminder.php`, `EmailReminder::send()`.`` A rerun's `board` column finds that spelling, and `$P find gh#142` answers whether an issue was imported. Backticks keep a path out of the link check, so deleting the old notes later breaks nothing. Name the symbol rather than the line, which rots.

**Keep the reasoning.** Notes are often the only place a decision's why was written down. Carry it into the file's first section, where it outlives the notes.

### By source

- **Notes** mix design, work and reference. Design becomes or joins a `spec-`; work becomes tickets whose `Spec:` points at it; reference someone using the project needs is a `todo-document-*`, since `docs/` is [docs](../docs/SKILL.md)'s job.
- **GitHub** is usually one issue to one file. Read each with `gh issue view <n> --comments` before proposing, because a title alone often misleads. Backfill reads GitHub and never writes to it: no comments, labels or closing.
- **Code** gets a `spec-<subject>.md` when no spec owns the subject: a `Description:`, what the feature is for, its entry points and the tests that pin it by name, and links to the tickets for what is unfinished. State intent and name the classes, per chat's Writing so it does not drift; a line-by-line account of the code is stale on the next commit. A subject with no boundary - "everything missing from the app" - is not a source: ask for the path or the feature.

## 4. Report

Counts, each from a command, not from memory:

- rows collected, from the collector's output
- files created and extended, from `git status --short project/`, by status
- rows merged into another file, dropped as shipped or not work, and still unresolved - naming the unresolved ones

Then point at `$P groom` as the next session. Everything this run filed is waiting there, and triage is its own task.

Backfill leaves the source alone: it never deletes the notes or writes to GitHub, and it commits by chat's rules, never on the default branch. The user reviews the diff and decides what to keep.
