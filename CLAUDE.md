# review-gate — repo guide for AI agents

This repository **is** the review-gate tool, and it **dogfoods itself**: commits
are gated by its own `gate/review-gate.sh` (via `.githooks/`, commit mode).

## Before any `git commit`

Follow the gate (the hook will block you otherwise):

1. `git add -A` the change.
2. Review the staged diff using the review agents in [`agents/`](agents/) and the
   guard-skills in [`skills/`](skills/) — apply them as checklists over the
   changed files (`code-reviewer` + `security-reviewer` always; the others when
   relevant; `clean-code-guard` for shell/code, `test-guard` for `tests/`,
   `docs-guard` for markdown).
3. Fix findings, re-stage (`git add -A`).
4. Attest + verify:
   ```bash
   bash gate/review-gate.sh attest --ran review,clean-code,test,docs
   ```
   (drop the steps the diff doesn't touch — attest tells you what's required).
5. `git commit`.

Verify for this repo = `tests/verify.sh` (shell syntax) + `tests/smoke.sh`
(install → block → attest → unblock). Both must pass before a commit lands.

## Layout

- `gate/review-gate.sh` — the gate (precommit/prepush/check/attest).
- `githooks/` — the hook templates the **installer** ships to consumer repos
  (they call `.review-gate/review-gate.sh`). `.githooks/` — this repo's own
  active hooks (call the source `gate/` directly).
- `agents/`, `skills/` — review agents + vendored guard-skills (MIT, Ahmed Nagdy).
- `integrations/` — per-tool wiring (claude/codex/cursor/windsurf/ci).
- `install.sh` — installs the gate into another repo. `setup.sh` — per-clone hook activation.

Keep all `*.sh` and the hooks **LF** (`.gitattributes` enforces it) — a CRLF
shebang breaks them on macOS/Linux.
