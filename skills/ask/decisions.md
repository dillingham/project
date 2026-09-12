# Decisions

Why the board is shaped the way it is, and which obvious alternatives were tried and rejected.

**Read this before changing how the board works.** The plugin README explains how it works and SKILL.md is the operating manual; neither says why. Every rejected idea below is genuinely plausible - each one sounds like a clear improvement until you know what it costs - and a plausible bad idea comes back every few months until the reasoning against it is written down.

Written the day the board was built, from the arguments that produced it.

## Status lives in the filename, not in the file

Rejected: a `Status:` header, or a folder per status.

A filename and a field would eventually disagree, and nothing would tell you which was lying. Keeping it in the name leaves one place for it to be wrong. It also makes a state change a `git mv`, so the change is a commit and `git log --follow` becomes the ticket's history for free - which a header edit would not give you.

Folders were the other option and cost more than they give: a ticket in `blocked/` is invisible to an `ls` of `todo/`, and moving between them is the same rename with an extra level to type.

The system began as `project/tickets/` beside `project/specs/` and `project/history/`. Flattening to one folder removed the question of which folder a thing belongs in, which turned out to be the question people actually got stuck on.

## groom is an honest absence

`Priority: groom` means nobody has judged this. It sorts BELOW `low`, because an unknown is not a claim, and it is never promoted by staleness, because an untriaged ticket going stale needs triage rather than attention.

The system started with 44 priorities stamped by status - every `todo-` got `high`, every `idea-` got `low` - which looked like judgment and was not. `groom` is what those should have been.

**Rejected: automating it.** A background agent grooming on every call has LESS context than a human, not more. It would open a ticket cold and guess, then write a plausible reason underneath, which converts an honest absence of judgment into synthetic confidence. That is the 44 defaults again, harder to spot because they have prose attached.

**Accepted instead: automate the research, not the judgment.** Whether the thing still exists, which tickets share its subject, whether a `done-` already covers it - all verifiable, all worth precomputing. The priority stays `groom` until someone with standing decides.

The hook that works is `mv <id> done`: discrete, deliberate, already a command with output, and context is at its peak. "Finish work on a spec" was tried and discarded - too vague to fire, and at the moment attention is lowest.

## Two things that look untriaged and are not

The first `groom` queue had six entries and every one was mis-modelled. Naming them correctly emptied it.

**Blocked.** `Blocked: issue-fields-injection.md - same mechanism, one line each once it lands`. The reason matters as much as the id, because "cannot start until that is decided" and "will be fixed by the same change" call for different responses. A blocked ticket drops out of `next`, since offering work nobody can start is noise, and out of `groom`, because its priority is deferred rather than unknown.

**Lists.** `list-minor.md` holds two dozen one-liners. A file like that does not have *a* priority and should never be asked for one, so it carries no `Priority:` and appears in no queue. Promote an item out when someone picks it up; that is when it earns a priority.

## What goes in the filename, and what goes in the header

The rule that decides it: **a KIND goes in the name, a SUBJECT goes in the header.**

- `list-` is a prefix because "holding pen" is a kind of file, binary, and it changes how the file is treated.
- `Spec: spec-blocks.md` is a header because a subject has many values, is orthogonal to status, and a ticket can touch two.

`idea-{spec}-{name}` was proposed and rejected on that basis: it would push the subject right in an `ls`, force a meaningless `general-` fallback on everything fitting no spec, and could not express a ticket touching two.

## Blocks is derived, never stored

`Blocked:` is the only stored direction. The board counts backwards and shows `BLOCKS:5` on the blocker's own row, which is usually the real argument for its priority.

Storing both directions is the same fact written twice, and two copies of a fact drift. The one that stays is the one carrying the reason.

## UNBLOCKED? is a question

When a blocker ships or vanishes, its dependents flag `UNBLOCKED?` and `project.sh unblocked` lists them. **Nothing is edited.**

"The blocker shipped" does not reliably mean "this is startable". It might have shipped partially, or in a way that changed what the dependent needs. Noticing is bookkeeping and the tool does it; deciding is judgment and it does not.

## Tab-separated, not CSV

Rejected: CSV.

Measured 2026-08-23: 40 of the board's 89 rows carried a comma, and no file in `project/` carried a tab. The separator CSV would use is the character that is everywhere in the data; the one in use is the character that is nowhere.

The cost is not just quoting. A quoted field with doubled inner quotes needs a real parser - quote state, escapes, embedded newlines - where a tab needs a split. `Spec: spec-blocks.md, spec-fields.md` is the case that makes it plain: it is legitimately comma-separated INSIDE one field, so CSV would quote it and the reader would then split it again on the same character it just un-escaped. Tabs also land in roughly aligned columns in a terminal, which is most of why a human can scan the output at all.

This is why `rows()` builds its records on `\037` and only converts to tabs in `emit()`: a separator must not appear in the data, and the presentation edge is the one place that can be guaranteed. It strips any tab out of the title and spec on the way through, so the invariant holds rather than being hoped for.

## The changelog is written, not generated

`project/changelog.md` overlaps `project.sh done` on purpose, and the overlap is the whole argument for it.

**Rejected: generating it.** Every field a generated changelog could use already exists - the `done-` title, the date the file was first seen under `done-`, the `Spec:` line - so `project.sh done` IS that changelog, and a file rebuilt from it would be the same fact stored twice. What generation cannot produce is the collapse: the binder, the resolution ladder, the scoping tickets and the bug sweep are four `done-` files and one change to anyone reading later. Deciding they are one line is judgment, which is the same reason `groom` is not automated.

**Rejected: a root `CHANGELOG.md` in Keep a Changelog format.** That serves people consuming a release, and nothing is released. Added/Changed/Fixed buckets would also fight the entries this board actually produces, most of which are settled decisions rather than user-visible behaviour.

**Rejected: one line per ticket.** It is mechanical and it is honest, and it makes the file exactly as long as `ls project/done-*`, which is the thing nobody reads. The value is being shorter than the board, not being a second view of it.

The append hook is `mv <id> done`, for the reason the grooming hook is: discrete, already a command with output, and context at its peak.

## Reporting

Run the command that proves a claim in the same breath as making it. This is in `SKILL.md` because it was learned the hard way in the session that built the board: a count stated from memory was wrong, a `40d` row was an artifact of a test that had not been cleaned up, and a batch of `FAIL`s were a broken test harness rather than broken code. All three were caught by the human, not the machine.

If you change state to demonstrate something, undo it and confirm the undo. A demonstration left in place becomes a false record.

## Moves repair references

`project.sh move <status> <filename>` owns the rename and reference updates as one deterministic shell command. Keeping a reference to `todo-something.md` after its target becomes `done-something.md` preserves a broken link, not history. Earlier sections and changelog entries keep their reasoning while their references follow the target. Git records the original spellings.

Replacement follows exact filenames throughout repository text, including bare mentions and code examples. An example naming the actual ticket follows the rename; a different illustrative filename does not match. This avoids asking an agent to classify each mention, and covers references a Markdown-only link parser would miss. Git ignores keep dependencies and generated files outside the operation.

The command prepares its edits before writing, rejects collisions, offers `--dry-run`, and restores files on a write failure. It leaves staging to the caller so an unrelated staged change is not disturbed. `mv <id> <status>` remains an alias for existing callers.
