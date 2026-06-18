# Changelog

## v0.2.0 — unified hardening

Merges two independent review passes (an external review of v0.1 and a parallel
hardened fork) plus a gap both missed, into one version. All changes are covered
by the integration suite (`tests/run.sh`: commit + push + install) which the
repo's own gate runs on every commit.

### Correctness

- **Pushed refs are validated, not just HEAD.** The `pre-push` hook now checks
  every ref update on stdin: attesting HEAD no longer unlocks pushing a different
  (unattested) branch. Deletions are ignored. (`tests/push.sh`)
- **Missing `gate.config.json` fails closed.** Previously a gated repo whose
  config was deleted would silently no-op and let the commit/push through. Now
  every entrypoint (hooks, Claude `check`, `attest`, `ci-verify`) fails closed
  with a clear message.
- **`perFile` verify commands preserve quoting.** A configured command containing
  quotes (e.g. `python -c "..."`) is now run through a real shell with the changed
  files appended as safe positional args, instead of word-splitting.
- **Untracked (non-ignored) files block attest.** They are visible to verify but
  are not committed/pushed, so they would let verify pass on content that doesn't
  land. (Complements the existing unstaged-tracked-files guard.)
- **Invalid `gateMode` value fails closed.** A typo like `"commmit"` now resolves
  to `invalid` (was silently `push`), so a commit-mode repo can't be downgraded
  by a misspelling.
- **First push diffs against the empty tree.** On a repo's first push, local
  `main`/`master` is HEAD itself and is no longer used as its own review base.

### Robustness / portability

- **Python 3 is discovered as `python3` or `python`**, or pinned via
  `REVIEW_GATE_PYTHON` (an explicit interpreter path) for odd environments. Hooks
  fail closed if none is present.
- **The push-mode `git fetch` is time-boxed** (when GNU `timeout` is available) so
  an unreachable remote can't hang attest.
- **The installer preserves an invalid existing `gate.config.json`** and aborts
  (instead of clobbering it) unless `--force` is given. (`tests/install.sh`)
- **`install.sh --force` replaces directories** instead of nesting a copy inside.
- **Re-installing with a different `--mode`** updates the Claude `PreToolUse`
  condition instead of leaving a stale one.
- **Verify logs use `mktemp`** instead of fixed `/tmp` paths.
- **The CI companion shares the gate's verify** via a `ci-verify` subcommand that
  **honors `perFile`** (perFile commands run on the PR's changed files, others
  whole-project) so CI matches local attest instead of diverging; `tests/ci.sh`
  locks it. The repo's own workflow runs the **source** `gate/review-gate.sh
  ci-verify` (it dogfoods from source — there is no installed `.review-gate/`
  copy in the tool's own repo). CI enforces the VERIFY step, not that a human/
  agent actually reviewed.

### Setup

- **Interactive setup.** The installer auto-detects the project (AI tools from
  `.cursor/`/`CLAUDE.md`/`AGENTS.md`/`.windsurfrules`; stack from `package.json`/
  `pyproject.toml`/`go.mod`) and, with a terminal, **asks** the user to confirm
  mode / tools / verify preset. `--yes` skips prompts; CI / non-TTY never prompts
  (can't hang). **AI agents ask the user in their language** and propose the
  verify commands from the project — see `SETUP.md`.
- **Mandatory once installed** (the advisory/on-demand option was dropped). The
  user-facing block messages no longer advertise `--no-verify`.

### Notes

- It remains an **honesty gate**: a LOCAL git hook can always be skipped with
  `--no-verify` (git runs no hook at all then) — no local hook can prevent that.
  For truly un-skippable enforcement make the CI companion a **required** status
  check (see `SETUP.md`); it runs server-side regardless of `--no-verify`.
- **Self-hosted:** review-gate gates its own commits. Its `test` verify runs
  `tests/run.sh`, which installs the gate into throwaway repos and exercises the
  full block → attest → commit/push flow — so every commit tests the gate, with
  the gate.
