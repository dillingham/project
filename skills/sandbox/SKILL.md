---
name: sandbox
description: "Use at the start of work in a cloud sandbox - a Claude Code web or remote session, or any container whose egress goes through an allowlisting proxy (HTTPS_PROXY is set) - before running a repo's setup or tests. Installs the PHP the repo's CI pins, makes Composer install over git past the proxy, gives Node the proxy for build-time fetches, then sets up the checkout. Also when composer install fails with 'Could not authenticate against github.com', the lock needs a newer PHP than the machine has, or a build fails with ENOTFOUND on a font or CDN host."
---

# Sandbox

A cloud sandbox is an Ubuntu container whose egress goes through a proxy that allows some hosts and refuses the rest. A repo's ordinary setup fails there in a handful of predictable ways, none of which is the repo's fault. `sandbox.sh` fixes the machine so that setup runs unchanged, then runs it for the checkout it is called from.

## Running it

From anywhere inside the checkout, with a generous timeout (the first run downloads PHP and clones every Composer package):

```
S="${CLAUDE_SKILL_DIR}/sandbox.sh"
$S
```

`$S machine` prepares the machine and stops, for when the repo's own setup command should run instead. It is safe to repeat: each step checks before it acts, and with no `HTTPS_PROXY` it does nothing at all.

Then prove it with one small test file, not the whole suite.

## What it fixes

| Symptom | Cause | What the script does |
| --- | --- | --- |
| the lock needs `php >= 8.4` and the machine has 8.3 | the base image is old, and the PPA is refused by the proxy | installs the PHP CI pins (`php-version:` in `.github/workflows`, else the lock's highest minimum, `SANDBOX_PHP` to override) from `shivammathur/php-builder` release assets, the build CI's `setup-php` uses |
| every `php` call warns `Unable to load dynamic library` | that build ships every extension, and some need system libraries the image lacks | disables each extension that fails to load, plus xdebug |
| `composer install` fails with `Could not authenticate against github.com` | GitHub's zip downloads are refused for repos not attached to the session; anonymous git reads are not | sets `preferred-install` to `source` globally, so every later install clones over git |
| the same error on `phpstan/phpstan` | it has no source in the lock, only a zip | fetches its locked commit over git, zips it, and places it in Composer's cache under the key Composer looks for |
| a build fails with `ENOTFOUND` on a font or CDN host | Node's built-in `fetch()` ignores `HTTPS_PROXY` | exports `NODE_USE_ENV_PROXY=1` and the proxy's CA bundle |

npm installs need nothing: the package registries bypass the proxy.

## The current session keeps its old shell

The script writes `COMPOSER_ALLOW_SUPERUSER`, `NODE_USE_ENV_PROXY` and `NODE_EXTRA_CA_CERTS` into the shell profile, but an agent session's shell was captured when the session started and never re-reads it. The script ends by printing the export line those shells need. For the rest of the session, start any Node command that fetches - a build, SSR, a browser test, a `worktree.sh` run - with that line.

Everything else it changes takes effect at once: PHP on the path, Composer's global config and cache.

## Other traps in the same sandbox

- `gh` GraphQL is refused, so `gh pr list` fails. Use REST: `gh api 'repos/OWNER/REPO/pulls?state=all'`.
- The checkout is shallow with a single-branch refspec, so `git checkout --track origin/X` says "not a branch". Add the refspec first: `git config --add remote.origin.fetch '+refs/heads/X:refs/remotes/origin/X'`, then `git fetch --depth=200 origin X`.
- Pushing needs the Claude GitHub App on the repo. Check before promising a push: `gh api repos/OWNER/REPO --jq .permissions`, or `git push --dry-run`.
- Never disable TLS verification or unset `HTTPS_PROXY` to get past a refusal. `/root/.ccr/README.md` and `curl -sS "$HTTPS_PROXY/__agentproxy/status"` say which host was refused and why.
