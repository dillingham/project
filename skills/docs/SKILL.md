---
name: docs
description: "Use when writing, revising or reviewing user-facing documentation - the pages in docs/ that teach someone how to use this project. Invoked as `/project:docs <spec>` to write or revise the page a spec describes, `/project:docs <page>` to revise an existing page, or `/project:docs` alone to lint every page and report drift. Runs a five-step procedure: locate the target and its siblings, verify every claim against the code, draft, lint with the bundled docs.sh, and report contradictions rather than silently fixing them. Also covers the page skeleton, what goes first, the paragraph-then-code rhythm, voice, and when a note or warning earns its place. Not for design specs, agent rules, or code comments."
---

# Writing docs

These rules describe one house voice: second person, example-led, and ordered around the reader's task rather than around the shape of the thing being documented. They are what makes that voice work, not what it happens to look like.

Docs are for someone building something with this project. They arrive with a task and leave the moment it is solved. Design rationale, alternatives considered, and the history of a decision belong wherever this project keeps its specs, never here.

## When invoked directly

```
/project:docs spec-<feature>.md  write or revise the page that spec describes
/project:docs <page>             revise an existing page
/project:docs                    lint every page and report drift
```

Work the five steps in order. Each names the condition that stops you.

| | Step | Stop if |
| --- | --- | --- |
| 1 | **Locate** the target page and its siblings | the argument covers several pages' worth: ask which |
| 2 | **Verify** every claim against the code | the code contradicts a published page: report it, do not fix it |
| 3 | **Draft** by the craft rules below | - |
| 4 | **Lint** with `docs.sh` | a page you drafted still has findings |
| 5 | **Report** what you found and what you decided | - |

### 1. Locate

Resolve the argument to one target page. A spec names the feature; the page is the one already covering that feature, or a new page beside its siblings if none does.

Then read a sibling page in the same directory, all the way through. It carries house facts this skill cannot know: the namespace, the recurring cast of example models, which types and methods actually exist, and how pages here write links and admonitions.

**Where this skill and the repository disagree, the repository wins.** This skill governs shape, order, and voice. The repository governs everything local: syntax, the cast of example models, which directories hold sketches rather than shipped code, and how a spec connects to the tests that pin it. Match what is already there for link form, admonition markup, and heading capitalisation, and do not convert an existing convention because this file shows a different one.

### 2. Verify

**Every claim needs evidence, and tests are the best of it, because they run.** A spec records what was decided, not always what shipped; a published page records what was true when it was written. Neither is evidence. Demo resources and sample apps are not either - they routinely call methods that were renamed or never built.

Where a project writes its test names as claims rather than `test_it_works`, read those first. They state outright what the source only implies, so they are both faster and more precise than reading implementation: a name like `the filter is serialized, never applied` settles in one line what a missing call site takes a grep to prove.

**The test name is the claim, the fixture is the proof, and neither is the example.** Check your example against a fixture, then write it fresh in the project's own cast. A fixture carries whatever made its assertion cheap, and every one of those teaches the reader something false when pasted into a page: a disabled default, a fixed sort order, a hook stubbed to return nothing, a spy, an anonymous class, a name chosen to describe the behaviour under test.

**Absence is evidence too.** A behaviour no test asserts is unbuilt or untested, and that is usually the exact sentence you were about to get wrong. Verify in the source whatever the tests do not reach, and name in your report which sections rest on behaviour nothing tests - those are the ones a reader should trust least.

The two invocations part company here, and only here. `/project:docs` alone, or `/project:docs <page>`, is a **review**: you report and change nothing. `/project:docs <spec>` **produces a page**, so a false claim has to be dealt with rather than merely noted. In both cases you report, and in neither do you decide which side was wrong.

**Report contradictions, never correct them.** When a page claims something the code does not do, leave that page exactly as written and say so in your reply: the file and line, what it claims, what the code actually does, and where you looked. The page may be aspirational, or the code may be the bug. Deciding which is not yours to do, and a silent correction hides the choice from the person who has to make it.

**In a revision, a false claim is omitted, not repeated and not fixed.** Preserving every fact means every fact; a claim the code contradicts is not one. Do not carry the passage forward, and do not write the corrected version either, because choosing the replacement is the same decision you were told not to make. Leave it out, and let the report say what is missing and why. This is the one case where a revision legitimately comes back shorter.

### 3. Draft

Everything from "Writing from a spec" down is the craft. A revision preserves every fact the page already carries: restructure, resplit, and rewrite prose freely, but do not quietly drop a capability because it was awkward to place.

### 4. Lint

`${CLAUDE_SKILL_DIR}/docs.sh` must exit 0 on any page you wrote or revised before you report. A review changes nothing, so the gate does not apply to it: run the linter, carry the findings into your report, and leave the pages as they are. It also profiles the page against the shape targets:

```shell
docs.sh lint <page>    # one page, by path or bare name
docs.sh toc <page>     # the contents its headings imply
docs.sh rules          # what each code means
```

Set `DOCS_DIR` when the pages are not in `docs/`. Advisory findings do not fail the run, but read them: they are the rules a machine can only guess at.

### 5. Report

Say what you changed and why, in a few lines. Then, separately and always: every contradiction from step 2, cited to the file and line that settles it; every place the spec and a published page disagreed on a name or signature; and anything you deliberately left out. Say plainly when you found no contradictions, since silence and an unverified page look identical from here. A clean report that hides an unresolved question is worse than a messy one.

## Writing from a spec

Documentation is usually written from a design spec, and a spec is not a draft of a page. It argues toward a decision, so it contains rejected alternatives, internal class names, machinery the reader never calls, and questions still open. Almost all of it is cut.

- Document the decision, not the argument. An approach the spec explored and abandoned must not appear as if it shipped.
- Document what the reader writes, not what the package implements. A method the framework calls on their behalf is plumbing; name it only if they override it.
- Leave open questions out. If the spec has not decided, the page cannot say.
- Trust the sibling pages over the spec for anything user-facing. A spec's examples are sketches and often name types that were never built.
- When the spec and a published page disagree on a name or a signature, say so in your reply rather than resolving it silently. Picking one is a decision the reader will live with.

## The shape of a page

Every page is the same object:

```
# Title

- [Introduction](#introduction)
- [Second Section](#second-section)
    - [A Variation Of It](#a-variation-of-it)

## Introduction

<prose>
```

A feature page always opens with `## Introduction`. Never skip it, never rename it, and never put anything above it but the title and the table of contents. The table of contents lists `##` and `###` headings only.

The three heading levels mean three different things, and confusing them is the most common structural failure:

| Level | Means | Example |
| --- | --- | --- |
| `##` | a thing you do | `## Defining Features`, `## Sending Mail` |
| `###` | a variation of that thing | `### Class Based Features`, `### Queueing Mail` |
| `####` | one method, option, or nuance | `#### Available Options`, `#### Dependency Injection` |

`####` headings stay out of the table of contents. They are the grain inside a section, not navigation.

Order sections by how likely each is to be the last one the reader needs. They arrive with a task and leave the moment it is solved, so the common case comes before the complete case, and the default comes before the escape hatch. Name a section after the verb it performs.

## What goes first

**Why before what.** The introduction opens on the reader's problem in the reader's language, and only then names the mechanism. It never opens on a definition. One that does this well:

> Some of the data retrieval or processing tasks performed by your application could be CPU intensive or take several seconds to complete. When this is the case, it is common to cache the retrieved data for a time so it can be retrieved quickly on subsequent requests for the same data.

The whole first sentence is the reader's situation. The feature is not mentioned until the reader wants it to exist.

**The default before the escape hatch.** Show the thing working with nothing configured, then show what may be changed. The two-argument form comes before the third argument, which comes before the specialized method that wraps it.

**The common case before the complete case.** Frequency of use sets length, not surface area. The method a reader calls daily earns four paragraphs and its own example; the three exhaustive variants share one.

**Prerequisites at the moment of need.** Do not front-load a wall of requirements. State each one in the section that needs it, immediately before the code that would fail without it.

**Nothing is held back for later.** If a caveat applies to the code you just showed, it goes under that code, not in a later section. This bans deferring an explanation, not pointing forward: naming the section that handles the harder case is useful, and a sentence doing that is ordinary prose.

## Sections stand alone

Readers arrive in the middle. A search result, a link from another page, a jump from the table of contents - whatever section they land on has to work without the one above it.

**Show the setup the example depends on.** If the code only behaves that way because a route declares a parameter, a field carries a particular name, or something upstream resolved a value first, that thing goes in the example. Writing that a value "is already resolved" without showing what resolved it teaches the reader nothing they can reproduce. The example is the whole claim, so an example missing its context is a claim you have not made.

**Explain the capability, not the mechanism that permits it.** A sentence like "the parent declares no such method, so an override may add its own parameters" describes the type hierarchy. What the reader needs is that they may type-hint whatever the method should receive. Internal structure is the reason a feature can exist; it is not the feature, and the reader cannot call it. Whenever a sentence explains the implementation, ask what capability it is evidence of, and write that instead.

**Never gesture at what you do not show.** A trailing "unless you need to narrow it further" names a capability and then withholds it. Either demonstrate it in the block below or leave it out entirely. An option mentioned without an example is a question planted in the reader's head that the page never answers.

## The unit

The page is built from one repeating unit: **one or two short paragraphs, ending in a colon, then a small code block.**

The colon is close to absolute. Write the sentence so the code block is its object.

**Paragraphs, not bullets.** This is the rule most often broken by accident. A good documentation page runs to a handful of prose bullets across its whole length, and its bodies are paragraphs and code blocks almost exclusively. A bullet list is what you reach for when you have not decided what the relationship between the items is. Decide, and write the sentence. Bullets earn their place for a genuine enumeration with no connective tissue: accepted values, required extensions, a list of drivers.

Two numbers are worth holding while you draft. A code block runs about 5 lines, and past 20 it is doing two things and should be two blocks with a sentence between them. Three paragraphs between code blocks is normal, and five with no code means you are explaining rather than showing. The rest of the proportions are `docs.sh`'s job, not yours.

Inside the code:

- `// ...` marks an elided body. Use it rather than inventing filler.
- A trailing comment shows the result: `// [[1, 2, 3, 4], [5, 6, 7]]`. Never write "this returns" in prose when the comment can carry it.
- Examples use a small recurring cast of realistic nouns, preferring whichever cast the sibling pages already use. Never `Foo`, `Bar`, or `MyThing`.
- Every fence gets a language.

## Voice

Second person, always. The reader is `you`. `we` and `let's` appear only in a walkthrough that builds one thing with the reader across several sections.

`you may` is available to you, `you should` is advised, and `you must` is reserved for what breaks otherwise. Prefer `you may` over `you can`. Avoid contractions: `do not`, `does not`, `cannot`.

**Warmth belongs in the introduction.** Sell the idea once at the top, then get out of the way. `convenient`, `expressive`, `powerful`, `simple`, `enjoyable` are introduction words. A body paragraph that calls a method convenient is padding.

**Never apologize for the reader's freedom.** The recurring move is to grant permission and move on: "Of course, you are free to...", "you are not limited to...", "If you would like...". It never scolds, and never implies the reader is doing it wrong.

## Phrasebook

The house transitions, when you want one:

| Opener | For |
| --- | --- |
| `If you would like to...` | an optional capability |
| `Sometimes you may need to...` | a case that is real but not the default |
| `By default, ...` | behavior, before the override |
| `To accomplish this, ...` | the method that satisfies the need just named |
| `Alternatively, you may...` | a genuinely equal second route |

## Catalogue pages

Some pages are a catalogue rather than a narrative: every field type, every available method. They take a different and rigid shape. Read `reference-pages.md` beside this file before writing one.

## Notes and warnings

**Most sections have none, and a page with none is perfectly normal.** Reach for one only when the sentence genuinely does not belong in the flow. Two admonitions exist and they are not interchangeable.

`> [!NOTE]` is a pointer or a bonus. It sends the reader somewhere else, or tells them something pleasant they did not ask for.

`> [!WARNING]` is a constraint that will cost the reader time. A prerequisite, an incompatibility, a reserved name, a default that is dangerous, a thing that silently does not work. Skipping it means a bug.

The test that settles most cases: **if removing it would change what the reader does, it is not an admonition, it is a paragraph.** Advice on which of two tools to reach for is the body of the page, however tempting the box looks. A note the reader cannot afford to skip is a paragraph wearing a costume.

The corollary is that a page with a real footgun in it should spend a warning on that footgun rather than leaving it in flat prose.

There is no third admonition: do not invent tip, info, or caution. Take the markup itself from the sibling pages, which may write `> **Note**` rather than `> [!NOTE]`.

## Mechanical rules

- Backtick every identifier: class names, methods (`save()`), config keys, file paths, commands, option names.
- Shell blocks include the whole command the reader pastes, prefix and all.
- Cross-link on first mention of another page's concept, writing the link exactly the way the sibling pages write theirs. A well-linked page carries around ten of these. A page that links out twice is holding the reader in one place rather than pointing them onward.
- Do not hard-wrap. One line per paragraph, one line per bullet, wrapping left to the reader.
- Strip website machinery from anything you adapt from a published docs site: `<a name>` anchors, `{{version}}` in links, `content-list` divs, `{.collection-method}` heading attributes.
- Tables are fine in moderation. Where the alternative is six parallel paragraphs, a table is usually clearer, as long as it compares like against like.
- No em-dashes or en-dashes. A spaced hyphen takes the parenthetical break.

## The review the linter cannot do

1. Does the introduction name the reader's problem before it names the mechanism?
2. Does every section work for a reader who landed on it directly, with no memory of the section above?
3. Does any sentence explain the implementation where it should name the capability?
4. Is every option the prose mentions actually demonstrated?
5. Would removing any admonition change what the reader does? If so it is a paragraph, not a box.
6. Does any paragraph explain something the code below it already shows?
