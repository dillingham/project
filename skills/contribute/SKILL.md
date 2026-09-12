---
name: contribute
description: "Use when the user asks to change the project plugin itself - how the board works, what a /project:* skill says, or what project.sh, worktree.sh, docs.sh or ci.sh does - and when a /project:* skill got something wrong and the fix belongs in the plugin rather than in this repo. Covers where the source lives (never the installed cache), whether a change belongs in the plugin or in the repo you are standing in, the mechanics that break a plugin skill silently, how to test a change live before it ships, the version bump, and the hand-off: committed in a checkout, never pushed, tagged or opened as a PR until the user says so."
argument-hint: "<the change>"
---

# Contributing to the plugin

The plugin is the [dillingham/project](https://github.com/dillingham/project) repository. Every `/project:*` skill, and every script behind one, is a file in it.

## Never edit the installed copy

The installed plugin lives under `~/.claude/plugins/cache/`, and that is not a checkout. It is overwritten on the next update and carries no history, so a change made there disappears without a trace. Work in a git checkout of the repository.

Ask the user where their checkout is. When they have none, clone `https://github.com/dillingham/project` - or their fork of it - to a folder they name, and work on a branch named for the change.

## Decide where the change belongs

The plugin serves every repo that installs it, so it carries rules, never facts about one repo.

| The change is | It belongs in |
| --- | --- |
| a rule every repo should follow, a script's behaviour, a skill's procedure | the plugin |
| a fact about one repo - its test commands, paths, demo URL, the name of its suites | that repo's CLAUDE.md, or its `project/` spec for the subject |

A skill that needs a repo fact says where to look for it, and each repo keeps its own answer. When one request is both, split it: the rule goes to the plugin, the fact stays in the repo.

Before changing how the board works - statuses, headers, priorities, what `next` or `move` do - read `skills/chat/decisions.md`. Most obvious improvements were tried and rejected there for reasons that are not obvious.

## Mechanics that break a skill silently

Each of these failed without an error while the plugin was being built.

- **Scripts find the repo from the working directory** (`git rev-parse --show-toplevel`), never from their own location. Installed, a script lives in the plugin cache, nowhere near the repo it is meant to read.
- **A skill reaches its bundled files through `${CLAUDE_SKILL_DIR}`**, and a sibling skill's through `${CLAUDE_SKILL_DIR}/../<skill>/`. A path relative to the repo, like `.claude/skills/...`, resolves to nothing.
- **A `` !`command` `` line runs before the model sees the skill, and a permission check can reject it with no visible error.** Keep it to one command, and declare what it runs in `allowed-tools`. `/project:cli` returned nothing at all until both were true.
- **Every skill is invoked with the plugin's prefix.** The `name` in the frontmatter is only the part after the colon, and `/project:<name>` is what the user types.
- **Markdown is not hard-wrapped and carries no em-dashes or en-dashes.** A spaced hyphen takes the break.

## Test it before handing it over

Run everything the repository already checks:

```
bash skills/cli/project.test.sh
bash skills/docs/docs.test.sh
bash skills/pr/pr.test.sh
claude plugin validate .
```

A change to a script's behaviour gets a scenario in that script's test file, in the style already there: plant the defect in a throwaway repository, then assert it is reported and that what is fine stays silent.

Then drive the changed skill for real. `--plugin-dir` loads the checkout in place of the installed plugin for one session, so run it from a scratch repository rather than one whose files a skill might change:

```
claude --plugin-dir <checkout> -p "/project:cli next"
```

A headless session cannot approve a permission prompt, so pass `--allowedTools` for anything the skill would normally ask for. When a run prints nothing, add `--output-format stream-json --verbose`: the rejection that the plain output swallows is in the stream.

Report what you ran and what came back. A test described as passing without its output in front of the user is a claim.

## Version it

Bump `version` in `.claude-plugin/plugin.json`: the last number for a fix, the middle one for a new command, rule or skill. An installed plugin only updates when the version changes, so a change shipped without a bump never reaches anyone.

## Hand it over

Commit in the checkout, then report the branch, the commit, and what you tested. **Do not push, tag, or open a pull request until the user says so.** Anything that leaves the machine is theirs to send.

When they do say so:

- **The owner** pushes, then tags `v<version>` and pushes the tag. `ci.sh` is pinned by tag in other repos' CI, so a tag is what makes a release usable there.
- **Anyone else** pushes to their fork and opens a pull request with `gh pr create -R dillingham/project`.

Once it is released, `claude plugin marketplace update dillingham` and then `claude plugin update project@dillingham` bring it in, and the session has to restart to load it.
