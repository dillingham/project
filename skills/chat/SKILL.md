---
name: chat
description: "Use for any question about what to work on next, what is open, what is stale, or what belongs to a feature - and for filing, finding or moving work in project/ - capturing an idea or aside the user drops mid-task, recording a finding you are not fixing now, promoting a spike into committed work, closing something as done, rejecting it, picking up work an earlier session left in a worktree, or answering what is open. Every file in project/ is {status}-{name}.md and the status is the first word, so changing status is a rename. Files ACCRETE sections (## Idea, ## Spike, ## Todo, ## Done) rather than being rewritten. Also covers where a thing belongs: project/spec-* for design, project/ for work, docs/ for user-facing. Invoked as /project:chat with a question, it runs the bundled project.sh and answers directly. The board ranks by priority and bumps anything idle past 30 days."
---

# project/

**Before proposing a change to how the board works, read decisions.md beside this file.** Most obvious improvements have already been tried and rejected for reasons that are not obvious - auto-grooming, storing the blocked relationship in both directions, putting the spec in the filename, a background agent that triages. Each sounds like a clear win until you know what it costs. Operating the board needs only this file; the plugin README introduces it; changing it needs decisions.md.

## When invoked directly

`/project:chat <question>` means: **run the script, read the answer, reply.** Do not open files first, and do not ask which command to run.

```
P="${CLAUDE_SKILL_DIR}/../cli/project.sh"
```

It reads the board of whichever repo the session is in. `/project:cli` runs the same script for a user who wants its raw output rather than an answer.

Running it with no arguments prints its own menu followed by what to pick up, so that is the safe first call if you are unsure.

| They asked | Run | Then |
| --- | --- | --- |
| "what's next", "what should I work on", nothing at all | `$P next` | Name the top one or two, say what each is and what it blocks, offer to start. A note that no critical or high work is free means the rows are the best available, not urgent - say so. A note that nothing judged is free means every open ticket is claimed, blocked or untriaged - say which, never "nothing to do". |
| "pick up X", "where was I", "carry on", a fresh session on work already started | `$P resume <id>`, or `$P resume` inside its worktree | `cd` to the path it prints, run its `Verify:` to confirm what you inherited, then continue from `Next:`. See Checkpoints below. |
| "yes" (to that offer), "let's start on X", "spin up a worktree for X" | invoke the **worktree** skill (`/project:worktree <id>`) | Starting is never anything less than this - see Worktrees below. Report the path it printed, or the abort reason verbatim, then work there. Always invoke the skill itself, never just describe what it would do. |
| "what spike should we work on", "any open ideas" | `$P spike` / `$P idea` | Same, scoped to that status. |
| "what's open", "how much is left" | `$P board` then `$P open` | Lead with the counts, then the list. |
| "what's happening with binding" | `$P spec binding` | Group by status in the reply: what shipped, what is open. |
| "is there anything about X" | `$P find X` | No rows means no match. Say so; do not guess. |
| "add/remember/file X" | `$P new <status> <name>` | Write the body, then one line confirming. |
| "that's done", "close it" | `$P move done <filename>`, on the ticket's own branch | Reconcile first and fill in the `## Done` it appends - see Finishing below. |
| "what shipped", "what landed this week", "what changed" | `cat project/changelog.md` | Answer from the top of it. The links go to the ticket carrying the reasoning. |
| "latest todo", "what was added last", "what's new" | `$P show todo` (or whichever status they named) | One command: it prints the id it picked, then that whole file. Answer from it - do not list first. |
| "let's spike X", "spike out X", "design X" | `$P spec X` then `$P find X` | Do not answer in prose. Run the spike session below. |
| "is the board healthy", "any broken links", before committing edits to `project/` | `$P check` | No output means clean. Otherwise each line is `file:line: CODE`; fix what you wrote, and report the rest rather than fixing it unasked. |

Output is tab-separated, one record per line:

```
priority  status  id  created  idle  title  spec
```

`created` is when the file was first seen under its CURRENT status, so moving a ticket restamps it - which is what makes "the latest todo" mean the one that most recently became a todo. `idle` is days since it was last touched, and an `idle` ending in `STALE` means the ticket is idle past the threshold and has been sorted up one priority level. Say so when you surface one - a high-priority ticket going stale is usually stale for a reason worth naming.

The two orderings answer different questions, and neither command needs sorting by hand. `next`, `open`, `groom` and `board` rank by priority, because those ask what to work on. Every listing - one status, `all`, `find`, `spec` - comes back newest first, because those ask what landed.

`show` takes either form: `show todo-next-up` prints that file, and `show todo` prints the newest todo, preceded by the id it resolved to. A bare status and an id can never be confused, because an id always carries a hyphen after its status word. Reach for the status form whenever the question is about the most recent thing rather than about a ticket you can already name - it is one command where listing and then opening is two.

Answer with judgement, not a dump. Three rows and a recommendation beats twenty rows.

One flat folder. Every file is `{status}-{name}.md`, and **the status is the first word**. Changing status is a rename, so `ls project/` is the board and `git log --follow` is the trail.

| Prefix | Means | Usually becomes |
| --- | --- | --- |
| `idea-` | a raw thought, unexamined | `spike-`, or `reject-` |
| `spike-` | an investigation or open question, no committed outcome | `todo-`, or `reject-` |
| `todo-` | committed work, described well enough to start | `done-` |
| `issue-` | a real gap, documented deliberately, NOT being addressed now | `todo-` when scheduled |
| `done-` | shipped, with the reasoning that got it there | stays |
| `reject-` | considered and not taken, or superseded and no longer true | stays |
| `spec-` | a major feature definition, not a work item | stays |
| `list-` | a holding pen of one-liners, not one ticket | items get promoted out |

### The header

Every file carries the same header block under its `# Title`, and every line in it is optional except where noted:

```
Description: one line saying what this is
Priority: groom | low | medium | high | critical   (tickets - required)
Spec: spec-blocks.md                              (tickets - when it belongs to one)
Blocked: issue-fields-injection.md - and WHY      (when it cannot start yet)
```

`Description:` is where the board reads its summary from, falling back to the `# Title` when absent. On a `spec-` file it is REQUIRED, because the title there is one word and one word tells an agent nothing. On a ticket it is optional: most ticket titles are already a full sentence, and a `Description:` that restates the title is worse than no line at all. Add one when the title is short or when the title alone would mislead.

Sub-topics group by name rather than by folder: `spec-fields-select.md`, `spec-forms-validation.md`, `spec-blocks-indexes.md`. So `ls project/spec-fields-*` is everything about fields, and the parent sorts directly above its children.

## Worktrees

Starting work on a ticket is never just editing files in place - it is always the **worktree** skill first, then `cd` into the path it prints, before touching anything else. There is no lighter-weight "start" - every ask is a worktree, and it is a skill invocation, not a bash command you run inline. See [worktree](../worktree/SKILL.md) for what it does, what it always sets up (dependencies, env, keys, migrations, the frontend build - whichever the repo uses), and `--take` for moving dirty main work into its own branch; this file only says when to reach for it.

**Claiming needs nothing extra - the worktree itself is the claim.** The branch it creates drops `<id>`'s status word - `slugify` for `todo-slugify` (no repo prefix either, since branches already live in this repo's own ref space) - so the name stays accurate no matter how many times the ticket's status changes under it. `git worktree list` is shared across every worktree of the same repo, visible instantly with no commit and no header line to write or drift. `next`, `open` and `groom` all check it: a live worktree claims the ticket whose current stable name its branch names exactly, so a `spike-` that becomes a `todo-` mid-work stays claimed, unchanged, by the branch opened for the spike. A claimed ticket shows `CLAIMED` and drops out of `next` and out of the one-to-triage groom pick, the same way a `Blocked:` ticket does, until `git worktree remove` clears it. `$P claimed` lists what is live right now. The worktree skill refuses a ticket that is already claimed, joined ids included, and names the worktree holding it - resume there instead.

Claims are shared by every worktree of the repo, but each branch carries its own copy of `project/`. So a claimed ticket changes status on its own branch, and the change reaches the default branch when that branch merges. `move` refuses a claimed ticket anywhere else: move it on its branch, or remove the worktree first when the work is abandoned.

## Checkpoints, and resuming

A worktree says where the work lives and the ticket says what it is for. Neither says where it stands, so a session that stops with a ticket unfinished appends a checkpoint inside the ticket's current section, in the worktree's copy of the ticket, where it travels with the branch:

```markdown
### Checkpoint 2026-09-12

Done: Options resolves from the container; `SelectTest` covers relation and closure sources.
Failed: resolving in the constructor - the container is not booted yet. Do not retry it.
Open: whether an API source caches per request or per block.
Next: the API source, from `Select::resolveOptions()`.
Verify: `php artisan test --filter=Select`
```

Write one whenever you stop mid-ticket, hand it to another session, or abandon an approach the next session would otherwise try again. **Each checkpoint is a complete handoff**, because `resume` shows only the newest: carry forward every failed approach and open question that still applies, and drop only what is resolved. A checkpoint with just `Done:` and `Next:` hides an earlier `Failed:` that still holds from the one session that needed it. The goal is not restated: the section above owns it. Checkpoints append like everything else - the newest is the current state and the ones above it are what was tried, which is exactly what a rewritten status block would have erased.

`$P resume <id>` reads it back: the worktree's path and branch, the commits it carries past the default branch, what is uncommitted, and the newest checkpoint in the ticket's current section, read from the branch's copy, which the default branch has not seen. With no checkpoint in that section, it prints the section instead. A status change leaves earlier checkpoints behind as history, so the new section states whatever in them still holds. Inside the worktree, `$P resume` alone resumes the branch you are on. A fresh session asked to pick something up runs it before anything else, `cd`s to the path, runs `Verify:`, and continues from `Next:` - it does not redo what the checkpoint says is done.

**Commit when the work reaches something worth keeping** - a coherent change, a settled decision, or substantial unfinished progress. A checkpoint on disk survives a restart, but it is outside history until committed and it goes wherever the worktree goes. A pause or a handoff alone does not call for a commit: checkpoint wording and routine bookkeeping ride along with the next meaningful one. Unfinished progress, once committed, has its checkpoint say what is incomplete or failing.

- **Capitalize the subject and leave the ticket out of it** - `Map ß, ø and æ explicitly`, in the repo's own commit style: plain, or `feat: ...` under Conventional Commits, where a scope names a code area, never the ticket. Carry the ticket's stable name - the part after the status, `slugify` for `todo-slugify.md` - in a trailing `Branch: slugify` line instead, its own line after a blank line, the same shape as `Co-Authored-By:`. It survives every status change and outlives the branch itself once that is deleted, so `git log --grep` or `git log --format='%(trailers:key=Branch,valueonly)'` finds the ticket's whole history, and it is what `gh pr list --search "head:slugify" --state all` and a local, offline lookup agree on. The subject says what changed; add a body when the reasoning, a rejected approach or a tradeoff would help the next agent.
- **Never add a Co-Authored-By, Generated-by or other AI-attribution trailer.** The commit is the user's, made on their instruction; a tool used to write it is not a coauthor, the way a compiler is not credited on the binary it produces.
- **Commit only what is the task's.** A worktree is shared with the user. Stage the task's paths with `git add -A -- <paths>`, which takes new files and a `move`'s rename, then `git commit -- <paths>` with the same paths. Staging outside those paths is preserved; inside them git takes the whole working-tree file, which is why a file that also carries the user's changes stays out entirely and is named in the handoff - telling their hunks from yours is a guess, and a wrong guess puts their change in your commit.
- **Keep the commit coherent.** Leaving a file out can leave a snapshot that does not build, even though the working tree passed. When the change needs an excluded file, the parts that depend on it stay uncommitted too, named in the handoff. Say whether verification ran against the committed snapshot or the working tree.
- **Never commit on the default branch, and never merge,** unless asked. The default branch moves by the user's merge, which is where the work is reviewed.
- **Review is not implementation.** Reviewing a branch, in whatever checkout, edits, stages and commits nothing unless the user asks for fixes.

Each handoff names the branch, its latest commit, the verification run and its result, anything still uncommitted, and the command that reviews the whole change: `git diff <default>...<branch>`. When the user's or the repo's own rules say otherwise about committing, those rules win.

## Finishing

Moving a ticket to `done-` claims the work landed, so reconcile before making the claim:

- **What was promised.** Each thing the `## Todo` committed to either shipped or was deferred, and the `## Done` says which.
- **The proof.** Run the newest checkpoint's `Verify:`, or the cheapest command that proves the change, now. The `## Done` names it and says it passed. A result from earlier in the session is a memory, not evidence.
- **What was left.** Everything deferred is filed - its own ticket, or a line in a `list-` - and linked from the `## Done`. "Not done" with no link is invisible the day the ticket closes.
- **Where it lands.** Run `move done` on the ticket's own branch, as part of the work, so the rename reaches the default branch in the same merge as the code. The default branch then shows `done-` exactly when the change is there, and never for a branch that was abandoned.

`move done` prints this list, and `$P check` flags a ticket whose current section is still empty (`P005`), so a `## Done` nobody wrote does not pass.

When the conversation reaches a coherent implementation ready for review, use [pr](../pr/SKILL.md) to prepare and validate its title and description, then offer to open the pull request. Make the offer when the work becomes ready, rather than at every pause. If the user already asked for a PR, follow that request without asking again.

Merging is the user's call. Once the branch has merged, the worktree's job is over: offer `git worktree remove <path>` and `git branch -d <branch>`, both of which refuse when something would be lost. A worktree left standing still claims its ticket and still shows in `$P claimed`.

## Spiking a subject

`/project:chat lets spike forms` is not a board query. It means: **read everything the repo already knows about that subject, work out what is genuinely undecided, and ask - one decision at a time, with selectable options.** The output is a `spike-` file that accretes answers as they are given.

Do not open with prose. Do not present a survey and ask what they think. Ask.

### Gather first, and read for real

Run `$P spec <subject>` and `$P find <subject>`, then read every `spec-` file that owns any part of it and every list that mentions it, and check the code for what actually exists. A question about something already settled wastes the session's most expensive resource, which is the user's attention.

Filter what you gathered down to what is genuinely open. A question earns its place when it is contradicted across two specs, listed under a "Left loose", or referenced by a spec and owned by none. Everything else is background.

### Open with what is settled

Before the first question, list what is already decided and will not be reopened, each with the file that carries it. This is what stops a spike relitigating ground the specs already argued, and it is also a check on your own reading - if you cannot name where a thing was settled, it was not.

### Ask with AskUserQuestion, in groups of up to four

Order the questions so the ones nothing else can be answered without come first. Then:

- **Every option carries a recommendation and a receipt.** Mark one `(Recommended)` and put it first. Say why in terms of what the repo already does - a rule it matches, a trap it avoids, prior art in the codebase.
- **Every option carries a `preview`** with real code, real envelope JSON, or the real route lines. An option the user cannot picture is an option they cannot judge, and the preview is what makes "the add notes option" usable - they reply against something concrete.
- **Name the cost of every option, including the recommended one.** An option with no downside listed reads as a sales pitch and gets picked for the wrong reason.
- **Never offer an option you would refuse to build.** Three real choices beat four where one is filler.

Then follow what they actually say. A user who selects nothing and writes a note has given you the more useful answer - read the note, and either ask again with better options or take the decision they described. A note that describes a shape you did not offer is the common case and it is the point of the workflow.

### Record after every group, not at the end

Append the answers to the `spike-` file as each group lands, under a `### Answered <date> - <group>` heading inside `## Spike`. A session that records only at the end loses everything if it is interrupted, and the user cannot see progress accumulating.

Record the REASONING, not just the choice. Six months later the choice is in the code and the reasoning is nowhere else.

### Watch for the question that dissolves

The best outcome of a spike is not an answer, it is a question that stops existing. When the user's instinct removes a mechanism, check what else went with it and say so plainly - three questions dissolving is a better result than three questions answered, and it needs recording as loudly.

The inverse matters as much. If the user makes a case that beats your recommendation, say that it beat it and reverse cleanly. Do not defend a recommendation because you made it.

### Close by filing, not by summarising

A spike ends with files, not a wall of text.

- Anything deferred goes in a `list-` holding pen, named for the subject, with the reasoning for each deferral. "We decided not to" is invisible six months later unless it is written where someone will trip over it.
- Anything that needs its own investigation becomes its own `spike-`, linked from the parent.
- Anything the session made FALSE in a published spec gets logged as a correction to make. A spec asserting something the session overturned is worse than a gap.
- Then a short summary in chat. Short. The files are the record; the reply is a pointer to them.

## Filing is never an interruption

When the user drops an aside mid-task, or you find something real that is not the job in front of you: **write the file and keep going.** Do not derail to fix it. Do not drop it because you are busy. Say one line - "filed `issue-x.md`" - and continue. Never stop for approval on a file that only records a thought.

**File it in the checkout you are working in.** Inside a worktree, that is the worktree: the file reaches the default branch in the same merge as the work, a link to it from the ticket resolves on both sides, and the default branch stays clean. Filed on the default branch mid-ticket, it breaks all three - each side links a file only the other has, so `check` fails on both until the merge, and the stray file makes the next worktree start refuse.

## Never rewrite. Append.

A file accretes its own history. Each status adds a section; earlier sections stay exactly as written, wrong guesses included, because the wrong guess is why the next section exists.

```markdown
# Selects cannot reach an API

Priority: medium

## Idea

Wondered whether options could come from somewhere other than a relation.

## Spike

Checked: Select::resolveOptions() dispatches on the source type, so a third
branch is cheap. What is NOT cheap is auth - an API source needs credentials
the block does not have.

## Todo

Add an Options class resolved from the container, so it can take dependencies.

## Done

Shipped as `Options`. The container resolution is what makes credentials work.
Rejected along the way: a closure source, because it cannot be type-hinted.
```

When you move a file, **append the new section, rename the file, and preserve the reasoning above.** A `## Done` that contradicts the `## Idea` above it is the system working. References are the exception: a reference to the old filename must follow the rename, including in earlier sections and changelog entries.

Use `project.sh move <status> <filename>`. The filename may include or omit `.md`; `project.sh mv <id> <status>` remains a compatibility alias. Add `--dry-run` to either spelling to see the rename, affected files, and diffs without changing the checkout.

The script performs the reference repair itself, without an agent search-and-replace pass. It updates exact filenames throughout tracked and untracked text files, honoring Git ignores. This includes Markdown targets and filename labels, bare prose, metadata, code examples, and historical entries. A code example naming the real ticket follows it too; a different illustrative filename stays unchanged. Bare ids in `Blocked:` headers and `/project/<id>` links also follow the rename. Fragments and descriptive link labels stay intact.

The command rejects missing sources, existing destinations, and moves to the same status before editing. It prepares the changes first and restores the original files if a write fails. It leaves the Git index alone; stage the rename and reference changes together when committing. Run `bash "${CLAUDE_SKILL_DIR}/../cli/project.test.sh"` after changing the move command.

## Priority

Judge by IMPACT, never by effort. A one-line fix to something flat out wrong is `critical`; a month of work that nobody is waiting on is `low`.

| Priority | Reasoning | Looks like |
| --- | --- | --- |
| `critical` | flat out wrong, or it affects 100% of users | wrong output, a silent leak, a crash on the common path, or the thing every other ticket is blocked on |
| `high` | wrong or missing on a path most users take, and the workaround costs something real | a defect with an awkward workaround, a gap that forces boilerplate into every app, or a ticket several others wait on |
| `medium` | real, on a path plenty of users reach, and there is a workaround that costs little | a defect in a narrower shape, a missing convenience, a documented gap people can route around |
| `low` | an edge case, small impact, good to fix | doc drift, a missing example, a rough error message, an unpinned decision nobody has hit |
| `groom` | nobody has judged it yet | anything filed in a hurry, or created by a bulk import |

**`groom` is the honest default when you do not know.** It is not "medium-ish" - it means untriaged, and it sorts below `low` because an unknown is not a claim. Two rules follow: never guess a priority to look decisive, and never let a `groom` ticket be promoted by staleness, because an untriaged ticket going stale means it needs triage, not attention.

`project.sh groom` is the queue. Working through it is its own task, done deliberately and not in the middle of something else - which is the point: filing something as `groom` lets you capture it now and decide later, instead of inventing a priority in the moment.

Two calibrations that keep the scale honest.

**Silence raises it a level.** A loud failure finds itself: someone hits it, sees an exception, files it. A silent one returns a plausible wrong answer for months. The same defect deserves a higher priority when nothing about it is visible.

**Blocking raises it too.** A ticket that several others cannot start without is worth more than its own contents. Say so in the file, and name what it blocks.

Priority is orthogonal to status - an `idea-` can be `critical` if it is the right idea, and a `todo-` can be `low`. Set it when you file, revise it whenever the answer changes, and say so if you change someone else's. When you assign anything other than `groom`, write the reason on the line below, so the next reader can disagree with the reasoning rather than just the number.

## Blocked, and buckets

Two things routinely look like an untriaged ticket and are not. Marking them is what keeps `project.sh groom` meaning "nobody has judged this".

**`Blocked:` names what it waits on, and why.** The reason matters as much as the id, because "cannot start until that is decided" and "will be fixed by the same change" call for different responses:

```
Blocked: issue-fields-injection.md - same mechanism, one line each once it lands
```

A blocked ticket drops out of `next`, since offering work nobody can start is noise. Its priority is not unknown, it is deferred, so it is not `groom` either.

Only `Blocked:` is stored. **`BLOCKS:n` is derived** - the board counts who points at a ticket and shows its leverage on that ticket's own row, which is usually the real argument for its priority. Never write a `Blocks:` line: two directions of the same fact drift.

The board also flags **`UNBLOCKED?`** when a blocker has shipped or vanished. That is a ticket sitting idle for no reason, and nothing else would surface it. `project.sh unblocked` is that list.

**A holding pen is `list-`, not a ticket.** `list-minor.md` holds two dozen one-liners; a file like that does not have *a* priority and should never be asked for one, so it carries no `Priority:` at all and never appears in `next`, `open` or `groom`. Promote an item out to its own ticket when someone picks it up - that is when it earns a priority.

It is a prefix rather than a header for the same reason `spec-` is: status is the first word, and "this is a holding pen" is a KIND of file, not a subject. `Spec:` stays a header because a subject has many values and is orthogonal to everything else; a kind is neither.

## Choosing the prefix

Ask what is TRUE, not what you hope.

- The user thought out loud, no decision attached? `idea-`
- A question has to be answered before anyone can act? `spike-`
- Decided, and someone could start from what is written? `todo-`
- A genuine defect or gap that is deliberately not being fixed now? `issue-`
- Considered and not taken, or overtaken by events? `reject-`

An `issue-` is not a weak `todo-`. It is the parking lot: real, documented, consciously not this session's job.

## Small things group

An item too thin for its own file joins a grouped `idea-` file - `list-minor.md`, `list-reconcile.md` - as one bullet. Promote it out to its own file when someone picks it up. Do not create a two-line file per one-liner; that is noise, not a board.

## Writing one

- Name the file for the SUBJECT, not the symptom: `issue-fields-injection.md`, not `issue-fields-broken.md`. Kebab-case, three to six words after the prefix.
- Only lifecycle headings are `##`. Everything inside a section is `###` or deeper.
- Never write a `Status:` line. The filename is the status, and two sources disagree eventually.
- **Always write a `.md` reference in PROSE as a markdown link**, never bare. Header values (`Spec:`) and anything inside backticks or a code fence stay bare - they are metadata and examples, not references to follow.
-  In prose, write `[done-resolution-ladder.md](done-resolution-ladder.md)` rather than the bare name. Bare mentions are invisible to a link check, so they rot silently through every rename - and a linked reference is clickable, which is most of why anyone follows it.
- Link siblings by bare filename, since everything lives in one folder. A file never links to itself; say "above" or "below" instead.
- Record reasoning, not just conclusions. A file nobody can argue with later gets relitigated.

## The changelog

`project/changelog.md` is what LANDED, newest first, under the date it landed. A line says what changed in one sentence and links the `done-` ticket that says why - it never restates the reasoning, because the ticket owns that.

**Append when work reaches `done-`.** `move done <filename>` says so in its output, which is the moment to do it: you have just written the `## Done`, so the one-line version is already in your head.

Three rules keep it from becoming a second board.

- **One line per landed CHANGE, not per ticket.** A batch of related tickets collapses to one line carrying several links - the binder, the ladder and the scoping tickets are one entry, because they are one change to anyone reading later.
- **Not everything earns a line.** A change nobody outside the session would notice does not get one. `project.sh done` is the complete record of tickets; the changelog is the readable one.
- **Preserve past entries, repairing references when their targets move.** An entry says what was true on that date. When something is superseded, the new entry says so and the old reasoning stays, exactly as a ticket's `## Idea` survives its `## Done`.

It carries no `Priority:` and never appears in a queue - the board ignores any file whose first word is not a status, which is also why a map like `index.md` is invisible to it.

## Where things belong

| It is | Put it in |
| --- | --- |
| a major feature definition | `project/spec-*.md` |
| anything actionable, at any stage | `project/{status}-*.md` |
| what someone using the project needs to know | `docs/` |

`project/spec-*` and `docs/` differ in AUDIENCE, not rigour: a spec may name private methods, cite framework internals and argue with itself; `docs/` says what to do and nothing about why.

When the repo keeps a `project/index.md`, it is the entry point and the concept-to-file map, and a genuinely new concept earns a `spec-` file plus a row there.

**Writing or auditing a `spec-` file is not this skill's job.** Whatever the repo says about its specs - usually `project/index.md` or its CLAUDE.md - governs them: the authority ordering, the house voice, the design check to run before inventing something. Read it before editing a spec, and do not restate it here - one copy is what keeps it true.

## Reporting what you find

Run the command that proves a claim in the same breath as making it. Counts, statuses, "this is fixed", "these are the open ones" - all of it is one command away, and stating it from memory is how a board stops being trusted.

- Do not report a number you have not just produced.
- Do not describe a test as passing without the run in front of you.
- If you demonstrate something by editing state - backdating a file, adding a fixture - undo it and confirm the undo. A demonstration left in place becomes a false record.
- Correct a wrong figure plainly and move on. The correction matters, the apology does not.

## Writing so it does not drift

- **Link, never restate.** If another file owns a rule, point at it in one line. A second copy is a lie the moment either is edited, and you will not know which one the reader trusted.
- **Never write a position or a count.** `Block.php:414` rots on the next insert above it; "learn these five" rots when a sixth arrives; "the three families" rots when something fits none of them. Name the method, the heading or the class - names move with the thing they name.
- **Do not describe what the code does today.** Behaviour changes and prose does not. Name the class, its docblock, or the test that pins it, and let the reader read the live thing. Describe intent instead, which is what a spec is for and what does not go stale.
- **Write every file reference as a markdown link.** A bare `fields.md` is invisible to the rename check, unclickable, and can silently resolve to a different real file elsewhere in the repo.
- **State the rule, not the edit that produced it.** "X is Y" survives. "X is no longer Z, because we moved it" is a change log - it is wrong the moment it is superseded, and it means nothing to a reader who never saw Z.
- **No relative time.** "currently", "recently", "for now", "still", "soon". Write the absolute date or write nothing.
- **Confirm a file exists before citing it.** A reference written from memory points at what you remember, which is often what was deleted last week.

## Naming the work

A `todo-` may name the KIND of work after the status, when that is the useful thing to scan for:

```
todo-document-partial-reload.md     write the documentation
todo-spec-reactive-fields.md        write or finish the spec
todo-fix-morph-eager-loading.md     change the code
todo-test-docs-coverage.md          add the coverage
```

`ls project/todo-document-*` is then every documentation gap. Use it when the verb matters more than the subject, and skip it when the subject already says everything.

**Documentation counts as work.** A shipped feature nobody can find is not finished, and a doc describing behaviour the code no longer has is worse than no doc. When you notice either, file a `todo-document-*` rather than fixing it inline in the middle of something else.

## Formatting

When the repo has its own Markdown rules (a CLAUDE.md section, a `.claude/rules/` file), they win. Otherwise:

- Do not hard-wrap. A paragraph is one line, a bullet is one line, a heading is one line.
- Blank lines separate paragraphs, lists, headings and code fences, and are the only intentional vertical breaks.
- No em-dashes or en-dashes. A spaced hyphen (` - `) takes a parenthetical break, a plain hyphen a range (`2-4`).
- Leave code fences, tables and ASCII diagrams alone: their line breaks are meaningful.
