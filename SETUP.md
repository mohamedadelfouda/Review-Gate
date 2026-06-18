# Setting up review-gate

review-gate asks a few questions at install time instead of guessing. It works
the same whether a human runs it or an AI agent does — only the *asking* surface
differs.

## Humans — terminal wizard

Run the installer. With a real terminal it auto-detects and **asks you to
confirm**:

```bash
bash install.sh /path/to/repo
```

It asks:
- **Mode** — gate on local **`commit`** or on **`push`**? (suggested from whether
  the repo has a git remote — remote → `push`, local-only → `commit`).
- **Tools** — which AI-tool integrations to wire? (detected from `.cursor/`,
  `CLAUDE.md`, `AGENTS.md`, `.windsurfrules`; `all` if none found).
- **Verify preset** — node / python / go, detected from `package.json` /
  `pyproject.toml` / `go.mod` and written into `.review-gate/gate.config.json`
  for you to fine-tune.

Skip the questions with explicit flags, or `--yes` to take the detected values:

```bash
bash install.sh /path/to/repo --mode commit --tools claude --yes
```

In CI / non-interactive shells it never prompts — it uses the flags or the
detected defaults, so it can't hang.

## AI agents (Claude / Codex / Cursor / …)

When a user asks you to set up review-gate, **do NOT silently pick defaults — ask
them first, in their own language, using your normal question UI**:

1. **Mode** — "Gate every local commit, or only on push?" (suggest `push` if the
   repo has a git remote, else `commit`).
2. **Tools** — confirm which AI tools to wire (detect from `.cursor/`,
   `CLAUDE.md`, `AGENTS.md`, `.windsurfrules`; default to what's present).
3. **Verify** — inspect the project and **propose** the typecheck / lint / test
   commands (Node → `tsc` / `eslint` / `vitest`; Python → `mypy` / `ruff` /
   `pytest`; Go → `go vet` / `golangci-lint` / `go test`), then confirm.

Then run the installer non-interactively with their answers and write the
confirmed verify commands into `.review-gate/gate.config.json`:

```bash
bash install.sh . --mode <commit|push> --tools <list> --yes
```

The gate's own messages are English — **relay them to the user in their
language.**

## Enforcement — and the one honest limit

Once installed, the gate is **mandatory**: every commit (commit mode) or push
(push mode) is blocked until the review + verify ran for that exact change.

But git lets anyone skip a **local** hook with `--no-verify`, and **no local hook
can prevent that** — it's how git works. So the local gate is a strong, honest
deterrent, not an unbreakable lock.

To make it **truly un-skippable** for whatever reaches the shared repo, add the
CI companion and make it a **required** check:

1. Copy [`integrations/ci/github-actions.yml`](integrations/ci/github-actions.yml)
   to `.github/workflows/review-gate.yml` (it runs `review-gate.sh ci-verify`).
2. On GitHub: **Settings → Branches → Branch protection → Require status checks**
   → select the review-gate check.

CI runs on the server regardless of any local `--no-verify`, so a bypassed local
commit still fails the pull request.
