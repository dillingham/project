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

## Claims follow the name, not the filename

A worktree's branch is named for its ticket when it opens, and the ticket keeps moving after that - a spike becomes a todo mid-work. Matching the whole id dropped the claim at the first rename, and let a second worktree open on the renamed ticket. The name after the status word is the part a status change never touches, which is the same reason status is the first word.

Rejected: renaming the branch along with the ticket. The branch is the checkout a live session is standing in, and the rename would have to happen from whichever checkout ran the move.

Each branch carries its own copy of `project/` while claims are shared across all of them, so a claimed ticket is moved only on its claiming branch. Moved on the default branch as well, the two renames collide when the branch merges, and the collision surfaces long after anyone remembers why.

Checking for a claim and creating the worktree are one step, under a lock in the repository's common git dir, which every worktree shares. Without it, two starts launched together both find no claim and both create one. The lock is let go as soon as the worktree exists, so a second start waits seconds, not through the first one's dependency install.

The lock is an `flock` the kernel holds for the process, not a file whose existence is the lock. Rejected: a pid file or symlink with stale-lock takeover. Two waiters can read the same dead owner; one removes it and takes a fresh lock, and the other, acting on what it read, removes that live lock too. A check before the delete narrows the gap without closing it. A kernel lock dies with its holder, so there is nothing stale to judge.

Every child that inherits the lock holds it until it exits, so which children get it is a choice. `git worktree add` keeps it: a start killed mid-creation leaves the add running, and a lock released with the shell let a second start claim the same ticket while the orphan finished. Every other git runs without it, since a fetch can leave maintenance or a credential daemon running long after it returns, holding the lock with nothing to claim.

## next never answers with nothing when there is work

`next` leads with critical and high, because that is what to work on. With none free, it offers the best judged rank that is, instead of printing nothing: an empty answer reads to an agent as an empty board, and the agent stops or invents work. A note on stderr says which case the rows are, leaving stdout one record per line.

`groom` stays out of that fallback. The one-to-triage pick already surfaces it, and offering an untriaged ticket as work would price it by omission.

## Checkpoints append; there is no current-state block

Rejected: a rewritten "current state" section at the top of each ticket. It would be the one part of the file that is rewritten, so the approach that failed last session gets overwritten by the one being tried now - the history the next session most needs. A dated checkpoint appended to the current section gives the same answer, since the newest one is the current state, and keeps what was tried, the way spike answers are recorded as each group lands.

Rejected: a goal line in the checkpoint. The `## Todo` owns the goal, and a second copy drifts.

Each checkpoint is complete, carrying forward whatever failed or is open and still applies, because `resume` shows only the newest and a partial one hides the rest. `resume` reads only the section for the ticket's current status: a spike's checkpoint says what to do while it is a spike, and once it is a todo that instruction is history, however recent.

## done lands with the merge

`move done` runs on the ticket's own branch, so the rename merges with the code. Moved on the default branch after the merge, there is a window where the code is in and the board says todo; moved before, `done-` claims a landing that may never happen. Neither needed a new status.

An aside filed mid-ticket lands the same way, from the worktree. A live trial filed one on the default branch while the ticket's `## Done`, on its branch, linked it: each side then linked a file only the other had, `check` failed on both, and the untracked file left the default branch too dirty for the next worktree start. Filing where the work is costs the aside its visibility on the default branch until the merge, which is the same wait every other change on that branch has.

`move` appends a heading and nothing under it, so finishing depended on the agent remembering to write the `## Done`. `check` now fails a ticket whose CURRENT section is empty. Earlier sections are exempt, empty or not: they are history, and history is never rewritten to satisfy a lint.

## Agents commit on ticket branches

The first live trial ran five sessions and none committed: every checkpoint and change lived only in a worktree's working tree, outside history and gone with the worktree. An unstaged diff works as a review surface for one agent in one checkout. With a worktree per ticket, the branch is the review surface - `git diff <default>...<branch>` is the whole change, and its log is the steps.

So implementation commits when the work reaches a coherent change, a settled decision, or substantial unfinished progress. The default branch still moves only by the user's merge, which is where review happens. Review-only work commits nothing, in any checkout: what an agent may do follows the task, not the directory.

The ticket's name does not lead the subject - see Branches and commit subjects drop the status word, below - but it still has to survive every status change and the eventual deletion of the branch itself, so it lives in a `Branch:` trailer instead, which `git log --grep` finds the same way.

The commit names its paths, `git commit -- <paths>`. Staging outside those paths is preserved; inside them git takes the working-tree file whole, so a file both of them changed cannot be among them - it is left out and named. Leaving it out can break the snapshot when committed files depend on it, so those stay out with it, and the handoff says whether verification covered the commit or the working tree. Rejected: staging the agent's hunks out of a shared file. `git add -p` is interactive, and after a restart the agent cannot tell its hunks from the user's; a wrong guess commits the user's change under the agent's message.

Rejected: a commit at every stop or every handoff. Most pauses are conversational, and a commit per pause buries the steps worth reading; the checkpoint rides along with the next commit that means something.

## Branches and commit subjects drop the status word

A branch named `todo-slugify` starts accurate and stops being accurate the moment the ticket becomes `done-slugify`, which is most of its life. The fix is not to rename the branch (rejected already, above, for the checkout-ownership reason) - it is to never put the status word on the branch to begin with. `$W todo-slugify` now opens a branch named `slugify`.

That changes which direction the id-to-branch match is allowed to run. Deriving a stable name FROM a ticket id is safe: the id always has the form `{status}-{name}`, so stripping the first segment is unambiguous. Deriving one by stripping a status word back OUT of a bare branch name is not: a ticket can legitimately have a stable name that itself starts with a reserved status word, like `spec-reactive-fields` (see the naming table in `SKILL.md`), and a branch simply named `spec-reactive-fields` would mis-parse as status `spec`, name `reactive-fields`. So claim matching only ever runs forward - a requested id's stable parts are computed once and compared to each live branch's `+`-joined parts as opaque strings, never the reverse.

That does cost a transition: a worktree opened before this change carries an old branch like `todo-x`, and the new exact-match check does not recognize it as claiming `x`. It is a one-time, self-resolving gap - every worktree still open at the moment this shipped, until it finishes or is recreated - not a standing ambiguity, which is the trade worth making over the alternative above.

The same staleness argument applied to the commit subject, which used to lead with the ticket's stable name (`slugify: ...`). The subject is now a plain, capitalized sentence describing the change - `Map ß, ø and æ explicitly` - and the ticket's name moved to a trailing `Branch: slugify` line, the same shape as `Co-Authored-By:`. A trailer outlives the branch's own deletion the same way the commit itself does, so `git log --grep` or `git log --format='%(trailers:key=Branch,valueonly)'` still finds the ticket's whole history, and it names exactly what a GitHub search for the closed PR needs: `gh pr list --search "head:slugify" --state all` finds a merged or closed PR by its former head branch even after that branch is gone, because GitHub keeps the branch name on the PR record itself, not on the live ref.
