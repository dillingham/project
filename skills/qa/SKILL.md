---
name: qa
description: "Use when asked to QA, tirekick, kick the tires, stress, poke at, or hunt for bugs in a feature - and whenever a feature is built enough to look at but nobody has driven it live. A HUNT, not a test suite: work out what the repo's cheaper suites structurally cannot see, imagine the arrangements that would break it, drive them in a real browser, and pin whatever breaks with a FAILING test before anything is fixed. The red test is the deliverable. Carries the ladder that sends a claim down the stack - finding a bug in a browser does not make it a browser bug, and one a server or component test can prove gets that test however it was found."
argument-hint: "<feature or scenario>"
---

# QA

A browser test is the most expensive test in a repo. It earns its place only by catching what nothing cheaper could.

That is the entire discipline. Everything below serves it.

## Map the repo's suites first

This skill names suites by what they can see, not by tool. Before hunting, find out what each one is called here: the repo's CLAUDE.md, its testing spec if it keeps one (`project/spec-testing.md` is the usual home), the test scripts in `composer.json` or `package.json`, and the test directories. You need three answers - which suite owns what the server decides, which owns what one component draws, and where browser proofs live and how they run. When the repo has no browser suite at all, say so in the report and ask before adding one, since that is a new dependency.

| Suite | Sees | Cannot see |
| --- | --- | --- |
| server (Pest, PHPUnit, pytest, request specs) | one request, one response: routing, auth, validation, what was written | what a browser does with the response; two pages' worth of UI in one DOM |
| component (Vitest, Jest, Testing Library) | one component built from one set of props, in jsdom | real focus, real layout, native form semantics, a server round trip, two components together |
| static (PHPStan, tsc) | shapes | behaviour |

The gap is one word long: **assembly**. Everything else in the stack proves a part in isolation. The browser is the only place the parts are put together and a person touches them.

## Send it down the stack, and mean it

**Finding a bug in a browser does not make it a browser bug.** Discovery is free-form - drive whatever you like, however you like, that is the whole point of the hunt. Proof is not free-form: it belongs to the cheapest suite that can carry the claim, which is usually not the browser. Those are two separate decisions, and collapsing them is how a browser suite fills up with tests that had no business being in it.

Before writing a browser test, try to kill it. Work down the list and stop at the first suite that can hold the claim:

1. **Can a server test assert it?** Nearly anything about what the SERVER decided - the response's shape, a rule, a gate, a redirect, what a request was allowed to write, what a header changed. Hit the route and assert the literal.
2. **Can a component test assert it?** Anything about what ONE set of props becomes - what renders, what a blank value shows, what a handler does to local state. Build the props, render, look at the output.
3. **Only if both genuinely cannot**, and you can say why in terms of what the suite structurally cannot reach, write the browser test.

"It is easier to assert in a browser" is not a reason. Neither is "the page was already open".

### Claims that look browser-only and are not

| The claim | Where it actually belongs |
| --- | --- |
| the form only shows VAT for a UK order | server - the condition ships in the response, so assert the condition rather than the rendering |
| an invalid email is rejected | server - POST it |
| live validation checks only the field it was asked about | server - send the request the client would send |
| a denied field never reaches the page | server - it is absent from the response |
| the error message renders under its input | component - one render carrying errors |
| a null money cell shows an em dash | component - render the cell |
| every component ships a test hook | component - glob the sources, render the tree |

The pattern: if the claim is about what the server DECIDED, or about what ONE component draws, it is not a browser claim - however you happened to find it.

### The line, on one example

These two sound like the same test and are not, and the difference is the whole section:

- *"Live validation checks only the named field"* - the SERVER's behaviour for one request. A server test, in milliseconds, no browser.
- *"Blurring that input sends a validation request for that field, and typing in the other form's input does not"* - the CLIENT's own dispatch, in a real focus model, with two forms present. Nothing but a browser can see it.

Ask which one you are actually claiming. Most of the time it is the first.

## Where browser-only bugs actually live

Six seams. Generate scenarios from these rather than enumerating a matrix - the point is to reach arrangements that are hard to reach, not to cover every combination.

1. **Coexistence.** Two components on one page. Nothing else in the stack ever renders two - a server test ships one response, a component test renders one component. Every per-component identity becomes a page-wide identity here: DOM `id`, `label[for]`, form state keys, error bags, registry entries. Ask what two components are each certain they own alone.
2. **The same rule implemented twice.** A condition evaluated on the server and again in the client; validation run live and again on submit. Two implementations of one rule agree until they do not, and only a live page feeds both the same input at the same moment.
3. **The round trip that redraws the page.** Submit, redirect, re-render. Ask what survives it: form state, errors, scroll, focus, the neighbouring component's everything. A validation failure is not an endpoint, it is a full page re-render the user is standing in the middle of.
4. **Native browser semantics.** `label[for]` resolution, focus order, what `<form>` nesting does to inputs, checkbox serialization, date inputs, the browser silently resolving a duplicate `id` to the first match. jsdom approximates these; the browser decides them.
5. **The second time.** The same interaction twice, or two interleaved. State that accumulates, listeners that stack, a control that behaves differently once something else has been touched.
6. **The viewer's context.** Timezone, locale, dark mode, a narrow viewport. Component suites usually pin a timezone so they agree between a laptop and CI, which means the real zone is exercised nowhere but a live page.

## Start where the repo already admits a gap

Do not start from imagination. A repo that keeps a board writes its blind spots down, and they are the highest-yield leads in it.

- **"Left loose"** or open-question sections in `spec-*.md` files.
- **Deferrals in `done-*` tickets** - the closing section naming what shipped without being proven.
- **`list-*` holding pens**, and any `issue-` ticket.

One grep covers the first, when the repo uses that heading:

```
grep -rn '^## Left loose' -A 20 project/
```

The richer vein has no fixed heading and has to be read: the closing sections of recent `done-*` tickets, where whoever shipped it named what went out unproven. `bash "${CLAUDE_SKILL_DIR}/../cli/project.sh" done` lists them newest first.

Grep for the repo's own words for a gap, and check what they mean first - a word like `deferred` can be a framework feature far more often than a deferral, and bury the signal. A test file whose docblock records surviving mutants or known holes is worth reading whole.

## How far to go

**An open-ended ask stops at the first confirmed bug.** "QA forms" is not a request to find everything; it is a request to find something real and prove it. Once a finding survives "Verify the finding is real" below, pin it, file it, write the log and report. A second bug in the same session competes for attention with the first and delays the fix for both.

Confirmed means it survived that verification - a lead you disproved does not end the hunt, it is the hunt working.

**A feature that already has a section in the log is a continue.** Start at its ⬜ lines - somebody reasoned those out and chose not to reach them, which makes them better leads than anything you would invent cold. Generate fresh scenarios only once they are exhausted, or when one of them is clearly no longer the interesting question.

A scoped ask is different again: "QA two forms on one page" names the scenario, so drive that one to a conclusion and report it clean if it is clean. A hunt that finds nothing is a result, not a failure, and the clean list is the deliverable.

## The loop

**Read the log → read what is proven → drive it live → verify the finding is real → pin it red → file it → log it.**

Then stop, and report. The fix is not part of the hunt.

### 1. Read what is already proven

**Start with `project/qa.md`, the hunt log.** If this feature has been hunted before, its section says what was already driven, what came back clean, and what the last hunt did not reach - which is both your exclusion list and, on a "continue", your starting point. Re-driving a scenario somebody already cleared is the main way this work gets wasted. When the file does not exist, this hunt creates it (step 6).

Then read the owning spec, and the server and component tests for the feature. Skim test NAMES and docblocks, not bodies - a feature can have thirty test files and you want the shape of what is covered, not its detail. Write that list down: it is the exclusion list, and skipping this step is how a session spends an hour re-proving validation that has held for months.

### 2. Drive it live

Drive the running app - the dev URL the repo's CLAUDE.md names, or the one `/project:worktree` printed. Use the chrome-devtools MCP tools, or Claude in Chrome. Explore freely, cheaply and without committing anything - most scenarios die here, which is the point.

A login wall is the repo's problem to have solved already: look for a local auto-login or a seeded user in its CLAUDE.md or `.env.example` before logging in by hand, and note in the report when there is neither.

One exception to driving by hand, worth doing first because it is nearly free: a scratch browser test sweeping the feature's routes for console errors, when the browser suite offers one (Pest's `visit([...])->assertNoSmoke()`, for one). Delete it afterwards - it is a smoke check, not a proof. It finds broken pages, not interesting bugs, so treat a clean sweep as the starting line rather than a result.

**Do not trust the generic assertions to do the hunting.** An automated accessibility scan pointed at a page whose duplicate `id` and doubled `label[for]` were the actual bug reported neither - it returned two unrelated findings from the app shell. Generic assertions find generic problems; the imagined scenario is what finds the bug.

### 3. Verify the finding is real before you write a line

Two ways to be confidently wrong, both cheap to avoid.

**Synthetic events lie.** React's `onBlur` is `focusout`; dispatching `new FocusEvent('blur')` fires nothing, and "the second form never validates" is exactly the wrong conclusion that produces. Setting `.value` directly is invisible to React too. Reproduce with real interaction - the MCP `click`/`fill` tools, or real focus movement - before believing any negative result. A thing that does not happen is the easiest observation to fake.

**Isolate before blaming the scenario.** Reproduce the same behaviour in the simplest arrangement that could show it - one form instead of two, one row instead of a page. If it reproduces there, it is not the scenario's bug and the interesting finding is somewhere else. This is what separates "two forms break validation" from "my probe was wrong".

### 4. Pin it red

A finding is not a finding until a test fails on it. Run it, and hand over the red output, **before** proposing or applying any fix.

Which suite that test lives in is decided by the ladder above, not by where you were standing when you found it. A bug found by driving a page still gets a server test if a server test can prove it - that is the common case, and the browser test is the exception you have to justify. The rules below apply to a browser test, once you have earned one.

- **Assert the CORRECT behaviour**, so the test is red now and green on the fix. Never assert the buggy behaviour to "document" it - that test inverts the moment someone fixes the bug.
- **Assert the scenario the test assumes, not just the outcome.** A test about the second form's label must first prove there are two forms; otherwise a page that renders one form passes for the wrong reason.
- **Name the user-visible consequence**, not the mechanism: `clicking the second form label focuses the second form control` beats `ids are unique`. Where a test asserts a page-wide invariant rather than an experience, name the invariant precisely and let a sibling test carry the consequence.
- **The interaction must be real.** The driver's own click is a trusted browser click; `label.click()` inside an injected script proves something adjacent. The rule from step 3 does not relax once you are writing the test - if the claim is about what happens when a person clicks, script cannot make it.
- **Make the failure carry the answer.** Prefer a named assertion when one says the claim exactly, and when reaching for a script assertion, return the offending value rather than a boolean - `[] vs ['name']` names the collision, `true vs false` sends the reader back to the page.
- **Select by what a thing IS**, in the order test hook (`data-test`, `data-testid`) → stable semantic selector → script. Never by a utility class, and never positionally unless the position IS the claim.
- One claim per test.

For Pest's browser plugin, the selectors, assertions and traps are in [references/browser-api.md](references/browser-api.md).

### 5. File it

The bug goes on the board through `/project:ask` as an `issue-` (or `todo-` if it is being scheduled).

**The ticket carries the failing test: its path, and its actual output pasted verbatim.** Run it, copy what it printed, do not paraphrase it. That output is the most compressed statement of the bug anyone will ever write - `expected '/teams', got '/people'` says in one line what a paragraph of prose says badly - and it is what lets a reader who will never run the test understand the defect. A ticket that only names a path asks them to go and get it, which they will not.

Fixing is a separate decision the user makes with the red test in front of them. When the repo leads behaviour changes with a spec, say that the fix belongs there rather than in a patch.

**The ticket carries the survival question forward.** Whoever lands the fix reads the ticket, not this skill, so the question has to be waiting for them there. Give the ticket a `### After the fix` section naming the proof and asking it outright:

```markdown
### After the fix

Decide whether `<path to the proof>` survives, and record which in `## Done`. Default is to keep it - it does not run in the fast loop. Demote a claim the fix made assertable in a server or component test; retire one whose mechanism is gone; anything kept gets renamed from the bug to the invariant.
```

Write your own read of it while the bug is fresh - which assertions you expect to demote and which look permanent. That is the most useful thing you know at filing time and the thing nobody can reconstruct later.

### 6. Log the hunt

Append to the feature's section in `project/qa.md`, whether or not you found anything. One line per scenario, phrased as the claim being made.

**A section is a standing checklist, not a journal.** It is the feature's name and then the lines - no date, no preamble saying what this session drove, nothing recording which hunt added what. A later hunt adds lines to the same section rather than opening its own, so a section always reads as the current state of what is known about that feature rather than a pile of visits to it.

```markdown
## Tables

- ✅ sorting a column keeps the current filter in the URL
- ❌ a paginated table returns to page 1 after a filter changes - [ticket](issue-....md)
- ⬜ two tables on one page, whose page params would share a key
```

Group by marker - ✅, then ❌, then ⬜ - rather than appending in the order you drove them. When you drive a ⬜, it becomes the ✅ or ❌ line; it does not stay alongside it.

**A ❌ requires a failing test.** Something you watched break in a browser but never pinned is not a ❌ - it has no proof, so nobody can confirm it, and nothing will tell anyone when it is fixed. Pin it and file it, or leave the line out until you do.

**The ✅ lines are the point.** Most of a hunt comes back clean, and that is the expensive half to reproduce - a bug gets a ticket, but the ground covered has nowhere else to live, and without it the next session re-drives all of it.

Anything absent from the list has not been driven, so there is nothing to write about what you missed. Add a ⬜ only for a scenario you specifically identified and chose not to reach - on a "continue" those are where the next session starts.

**One sentence, and high level.** A line reads like a test name, not a report - if it runs past the width of the lines already there, it is carrying detail that belongs somewhere else. Label the link `[ticket]` rather than repeating the filename.

Nest a single bullet only when the line cannot be reproduced without it - the route, or the two values that differ. Never nest deeper than one, and treat needing it at all as a sign the line is trying to say two things.

A new log opens with a title, a `Description:` line, and the legend, then one `##` per feature:

```markdown
# QA

Description: What each browser hunt has driven, one line per scenario - so the next hunt resumes rather than restarts.

- ✅ driven, held
- ❌ driven, broke, and pinned by a failing test - links its ticket
- ⬜ named as worth driving, not yet driven
```

The board ignores it, since its name starts with no status.

## Writing the proof

**Explore on the dev app. Prove on your own scenario.** Never assert structure against demo or seeded pages - they are a playground somebody reshuffles, and a test pinned to one breaks on an experiment rather than on a regression.

### The test is self-contained

**A proof declares its own scenario, in its own file, and shares nothing.** The routes, the components, the records and the assertions are readable top to bottom without opening anything else.

This is a deliberate exception to the shared-fixture habit, and the reason is what these tests are FOR. A proof is read by someone trying to understand a bug they have not seen. A shared fixture makes them open a second file to find out what was even on the page, and worse, it can be edited by an unrelated test until the scenario no longer means what the name says. The duplication is the point: this file is a self-contained reproduction, and it should still reproduce in a year when every fixture around it has moved.

Whether routes can go in the test depends on the driver. One that boots the app in-process - Pest's browser plugin does - sees routes registered in the test's setup and rows from its factories. One that drives a separately running server cannot, so the scenario needs a real route kept in a file only proofs load.

**Namespace the file and then name its classes plainly.** `PersonForm`, not `QaPersonForm` - the directory already says what these are, and a prefix repeating it is noise in the one file that most needs to read easily. The namespace is what stops two proofs colliding on a name.

Strip the scenario to the minimum that still shows the bug. A realistic form buries the collision in twelve fields; two forms carrying one field each puts it on the first screen.

### Write it to onboard someone who has never seen the bug

That reader is the only audience this file has. Everything in it should move them toward understanding what breaks, and anything that does not is in their way.

- **Make the fixtures concrete.** "A page with two forms: one adds a person, one adds a team, and both have a box labelled Name" is a scenario anyone can picture. `MemberForm` and `Board` are shapes with no referent.
- **Say it in plain language.** The docblock explains the bug the way you would say it aloud, not the way the codebase says it. Reach for a term of art only when a plain word would be wrong.
- **Never explain the tooling.** No comment about what a selector resolves to, why a script assertion returns an array rather than a boolean, or why the click is real. That is all in this skill, it is the same in every proof, and in the file it stands between the reader and the bug.
- **Never narrate the code.** A docblock above a class whose next four lines say exactly what it says is a line the reader must check against the code and then discard. This is the most common way a proof gets padded, because a docblock per class feels like diligence.
- **Comment the bug, or say nothing.** The only comment that earns its place tells the reader something about the failure they could not get from the code.
- **Name the test as the sentence that is false.** `clicking the team form label puts the caret in the team form` failing with `expected '/teams', got '/people'` - a stranger can read those two lines and understand the whole defect.

### One proof, one file - browser assertions and cheap ones together

**A proof holds every assertion about its bug, whatever suite each one belongs to.** The ladder decides how a claim is asserted; it never decides which file it lives in. A proof scattered across two directories is a proof nobody can read.

So a file mixes freely where the runner allows it: a plain request assertion establishing the scenario on the wire, beside the browser assertion for the part only a browser can see. In Pest a test becomes a browser test by calling `visit(` directly in its own closure, so the plain assertions beside it run at normal speed - see [references/browser-api.md](references/browser-api.md) for the trap in that.

### When a thing cannot be selected

When the components already draw test hooks, a missing hook is a gap to note, not something to work around.

What is left is the case a hook cannot answer: **you can see two of a kind and cannot tell WHICH one is which.** Do not invent a scheme to separate them. That is a finding, and usually the finding - an element with no scoped identity is the shape of an id collision. File it, keep the awkward selector in the red test, and say so **in the ticket** - not in the proof, which stays free of commentary about its own tooling. That an assertion had to reach for an endpoint or a position to name one of two identical things IS the finding, and it is invisible once the selector reads as ordinary.

## After the fix

Going green is a decision rather than an ending, and it belongs to whoever lands the fix - which is why step 5 puts the question in the ticket rather than answering it here. The default is to keep the proof: the browser suite is a corpus of bugs that were hard to find and easy to reintroduce, and it stays out of the fast loop, so keeping one costs nothing on every save. Two narrow exits: **demote** a claim the fix made assertable in a server or component test, because that test runs on every save rather than at merge; **retire** one whose mechanism the fix removed entirely. Anything kept is renamed from the bug to the invariant. When the repo's testing spec says otherwise, it wins.

## Running them

Use the command the repo gives its browser suite, one test at a time while writing it, and headed when you need to watch it happen. A browser suite belongs out of the fast gate - run last, once everything cheaper is green - and when this repo's is not, say so in the report rather than moving it.

## Reporting

The red test is the deliverable, so lead with it: what breaks, what a user sees, and the command that shows it failing. Then the mechanism, then the file and line. A finding reported without a failing test is a claim; the whole point of this skill is to hand over proof instead.

Say plainly what you drove and found clean, too. "Error bags are isolated, state survives the round trip, conditionals scope per form" is the larger half of a hunt and it is what makes the one red test believable.
