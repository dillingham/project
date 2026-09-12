---
name: worktree
description: "Use to START work on a ticket, idea, or any ask that means editing code - never edit in place on the default branch. Triggers: /project:ask has just decided what to work on, 'yes' to being offered a ticket, 'let's start on X', 'spin up a worktree for X', or 'this should have been a branch' / 'move my changes off main'. Runs the bundled worktree.sh: creates a fresh git worktree off the default branch at ~/Worktrees/<repo>-<id>, then sets it up for whatever the repo uses - composer install, .env, key:generate, migrate --seed, npm/pnpm/yarn/bun install and build - before returning, so the path it prints is genuinely ready to work in. Invoke this every single time work starts, even mid-conversation - do not just describe it in prose and move on."
argument-hint: "<id> [--take]"
---

# worktree

Starting work is never just editing files in place. It is always this skill first, then `cd` into the path it prints, before touching anything else. There is no lighter-weight "start" - every ask is a worktree.

## Running it

Run it from anywhere inside the repo:

```
W="${CLAUDE_SKILL_DIR}/worktree.sh"
$W <id>
```

`<id>` is a ticket id from `project/` (`todo-calendar`, not `calendar`) or, for `--take` below, just a name you pick. Report the path it printed, or the abort reason verbatim, then work there.

**Run it. Do not narrate it.** Deciding a ticket and then describing what a worktree would do, without actually invoking this skill, is the failure this file exists to prevent - if the conversation reaches "let's start on X", the very next tool call is this script, not a sentence about it.

## What it does

`$W <id>` opens a fresh worktree for `<id>` at `~/Worktrees/<reponame>-<id>`, branched off the default branch - `origin/HEAD` when there is a remote, else `main`, else `master`. The folder carries the repo's name because every repo's worktrees share one folder; set `PROJECT_WORKTREES` to use a different one.

It refuses rather than guesses: the default branch must be clean (`git status --porcelain` empty) or it aborts and prints exactly what is dirty, the default branch is fast-forwarded from origin first when a remote exists and left alone when there is none, and it aborts rather than reuses if the branch or the destination folder already exists. A name git will not take as a branch, or one whose folder would pass 63 characters, is refused before anything is created.

There is nothing to check out separately - `git worktree add` already checks the branch out inside the new folder the moment it creates it. The only remaining step is moving the session itself there: run `cd <the path it printed>` and stay there for the rest of the session. This is the one place `cd` is correct despite the usual advice to prefer absolute paths and stay put - the session's whole purpose from here on IS that worktree, exactly as if it had started there.

When [Herd](https://herd.laravel.com) is installed it also prints `http://<folder>.test`, since Herd serves every folder directly under a parked path - no server to start, no port to pick. That only holds if the worktrees folder is parked (`herd park` inside it, once). `https` needs `herd secure <folder>` first; it is not run automatically, since plain `http` already works with no setup.

## Setup always runs, every time

`git worktree add` only brings across what git tracks. Everything gitignored - dependencies, `.env`, the sqlite file, the build - has to be created fresh, and the script does that before it returns, for whichever of these the repo actually has:

| When the repo has | It runs |
| --- | --- |
| `composer.json` | `composer install --no-interaction` |
| `.env.example` | a fresh `.env` copy |
| `artisan` | `APP_URL` pointed at the worktree's own domain, `key:generate`, the sqlite file touched when `DB_CONNECTION=sqlite`, `migrate --seed --force` |
| `package.json` | install with whichever manager its lockfile names, then `run build` when it has a build script |

`--force`/`--no-interaction` run through the whole chain on purpose - nothing in it should ever be able to stall on a prompt, in an agent shell or a real terminal.

Before any of that runs, the script also unsets every key `.env.example` declares. Herd (and other tooling) sources the original checkout's `.env` into ad-hoc shells, which means `composer`/`artisan`/`npm` here can inherit its `APP_KEY`, `APP_URL`, `DB_*` etc. as real environment variables - and an env var always wins over the new worktree's own `.env` file (PHP dotenv never overwrites an already-set var). Left alone, `key:generate` fails outright with "APP_KEY is already present in the environment", or the build inherits the wrong `APP_URL`, depending on whether that particular shell happened to have the original `.env` exported.

If any step fails, the script says exactly which one - not one generic "setup failed" - and still prints the worktree's path first, because the worktree itself already exists and is worth having even when setup did not finish. Finish the failed step by hand inside that path; everything before it already succeeded and does not need repeating.

A stash-pop conflict (see `--take` below) skips the automated setup entirely rather than running installs and migrations over files that may still carry conflict markers - resolve the conflict first, then run the setup steps by hand.

## Claiming needs nothing extra

The worktree itself is the claim - see [ask](../ask/SKILL.md) for how `CLAIMED` and `project.sh claimed` read that back from `git worktree list`. This skill only creates the worktree; it does not touch the board.

## Moving dirty work off the default branch

"move my current changes on main into their own worktree", "this should have been a branch" means `$W <id> --take`: it stashes whatever is dirty, runs the same guarded sequence as a plain call, then applies the stash inside the new worktree - the default branch ends clean, the worktree carries the work. `<id>` here is just a name: ask for one, or use whatever was already given - never infer it from the diff or the ticket files.

## Joining tickets on one branch

Two tickets that belong on the same branch - one names the other as `Blocked:`, or the work is genuinely one change - are not a reason to force a single id. Join both with `+`: `$W todo-a+todo-b`. The branch keeps the whole name, and the board's claim check splits on `+`, so both ids show `CLAIMED` and both drop out of `next`. The folder, and so the hostname, is named after the first id alone, because `+` is not a legal hostname character.
