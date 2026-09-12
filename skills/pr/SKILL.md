---
name: pr
description: "Draft, revise or lint a pull request title and body from the complete branch change, with an overview, Changes, Related and Testing in the project style. Use when preparing a PR, improving its description or offering to open one when implementation is ready for review."
---

# Pull requests

Make the change reviewable for someone who has not read the conversation. Start with the concrete problem and resulting behavior, then explain the changes, their related work and the evidence.

`/project:pr` with no arguments uses the current context. Infer the active task and worktree, intended base branch, existing PR and related work from the conversation and repository. Do not require a subcommand, ticket name or branch the context already supplies. Inspect first and ask only when a material ambiguity remains. An explicit request to review or lint is read-only. Invoking the skill after accepting an offer to open or update the PR uses that existing authorization; do not ask again.

For a lint-only request, run the validator on the existing body and report its findings; no drafting or publication is needed.

## Read the change

Read the repository's contribution instructions, PR template and recent titles for its conventions. Identify the target branch and the ticket's stable name, without its status prefix or `.md`. Keep that name in the title using the repository's style: `slugify: transliterate accented input` or `feat(slugify): transliterate accented input`. Do not invent a ticket for work that has none.

Inspect the complete diff from the target branch's merge base to the proposed head, the commits, and the working-tree status. Read the changed code and the relevant specs, ticket sections and deferrals. Use the full change when rewriting a description, including changes made in earlier sessions. Describe what the committed branch includes; identify excluded local work separately, including dependent changes left out with a shared file. Old descriptions and commit messages are leads, not proof of what the branch now does.

Record the tested revision and actual command output. Tests run with uncommitted changes prove that working tree, not a different committed head. Run the relevant checks when authorized and practical; otherwise name the missing verification and why it was not run. Do not convert a previous session's claim into a fresh test result.

## Write the body

Use an unheaded overview of one or two short paragraphs, followed by these exact headings in this order. This example illustrates the shape; replace every claim and link with evidence from the actual change:

```markdown
Accented input now produces readable ASCII slugs. Explicit mappings cover letters that Unicode normalization leaves unchanged.

### Changes

- Apply explicit mappings for `ß`, `ø` and `æ` alongside normalization.
- Preserve the existing separator and empty-input behavior.

### Related

- Specs: [Transliteration](https://github.com/acme/app/blob/7c9f3d2/project/spec-slugs.md).
- Tickets: [Slugify](https://github.com/acme/app/blob/7c9f3d2/project/done-slugify.md).
- Related PRs: None identified.

### Testing

- `python3 -m unittest tests.test_slugify` - passed: 10 tests at the proposed head.
```

Changes are meaningful `- ` bullets about behavior and decisions, not a file inventory or a session diary. Keep the overview in prose. Use plain, concrete language and no em or en dashes in prose. Do not leave template instructions, `TODO`, `TBD` or `FIXME` fillers. Put literal examples in inline code or fenced blocks.

Related has one row each for `Specs:`, `Tickets:` and `Related PRs:`. Use descriptive inline Markdown links, or `None identified.` for a category searched with no relevant match. Inspect references in the ticket, spec, commits and existing PR. Use available read access to find related PRs; if it is unavailable, say `None identified. PR lookup unavailable: <specific reason>.` without implying a complete search. Link repository files using forge URLs pinned to the proposed head's commit SHA so they resolve from the PR and survive branch deletion or later status renames. Check local paths and inspect related PRs where access permits; never invent a link.

Testing uses one bullet per actual command: ``- `command` - passed: result and tested revision.`` A failed command uses `failed:` and explains the remaining failure. Work not run uses `- Not run: <specific reason>.` Mixed passed, failed and not-run entries are allowed. State any working-tree differences that limit what the results prove. Do not say all tests passed when only a subset ran.

## Validate and deliver

Write the exact proposed body to a local file, then run:

```bash
bash "${CLAUDE_SKILL_DIR}/pr.sh" lint /path/to/pr-body.md
```

The validator checks structure and a small set of style rules. It does not establish that a claim is true, a linked resource exists or testing proves the change. Review those against the evidence yourself. `pr.sh rules` lists the enforced format. If the repository requires additional fields, preserve them within the appropriate section; an explicit user or repository requirement that conflicts with this shape takes precedence, and any resulting lint exception must be named.

When meaningful implementation is ready for review and the conversation makes opening a PR a useful next step, prepare the validated title and body and proactively offer to open it. Do this at that review point, not at every pause or checkpoint. Drafting and linting otherwise produce a local title and body. Create or update a remote PR only when the user's request authorizes it; finishing a ticket alone does not. If creation or updating was already requested, proceed without asking again. When authorized, use the forge's structured body argument or a CLI `--body-file` with the validated file. A PR needs its branch on the forge, so authorization to open one covers pushing that branch and nothing else - never the default branch, never a tag. Do not stage, commit, push or merge merely to prepare the description, and preserve the user's review and staging rules.

Return the title, body-file path and validation result, or the PR link when publication was requested and succeeded. Identify any missing evidence that affects review.
