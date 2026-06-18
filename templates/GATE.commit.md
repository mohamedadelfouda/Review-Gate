# Review Gate — Pre-Commit Protocol (MANDATORY)

This repo enforces review at **`git commit`** time (`gateMode: commit`). Before
committing ANY work, always run this gate in order — even if the user only says
"commit". The pre-commit git hook BLOCKS the commit until it's done.

1. **Stage** the work: `git add -A` (the gate binds to the *staged* content, so
   what you review must be what you stage).
2. **Review the staged diff** (`git diff --cached`) across the relevant
   dimensions — in parallel if your tool supports subagents — using the agents in
   `.review-gate/agents/` and the guard-skills in `.review-gate/skills/`:
   - `code-reviewer` — always
   - `security-reviewer` — always
   - `performance-reviewer` — when non-trivial logic / hot paths / queries change
   - `database-reviewer` — when SQL / migrations / queries change
   - `accessibility-reviewer` — when UI changes
   - `i18n-reviewer` — when user-facing text / locale formatting changes
   - `refactor-cleaner` — when the change risks dead code / duplication
   - guard-skills: `clean-code-guard` (production code), `test-guard` (tests),
     `docs-guard` (docs/markdown)

   If your tool can't spawn subagents, apply these files as **checklists** in a
   single pass over the diff.
3. **Self-review + fix** every real finding. Then **re-stage**: `git add -A`.
4. **Attest**:
   ```bash
   bash .review-gate/review-gate.sh attest --ran <steps>
   ```
   `<steps>` = `review` + whichever guard-skills the diff needed (`clean-code`
   for production code, `test` for test files, `docs` for markdown). `attest`
   computes the required set from the staged files and REFUSES the marker unless
   `--ran` covers it, then runs the configured verify (typecheck + lint + test).
5. **`git commit`** — allowed only while the staged tree still matches the marker.
   Do NOT `git add` new content after attest (it invalidates the marker). Avoid
   `git commit -a/-am` with unstaged changes (the gate blocks it).

**Enforcement:** the `pre-commit` git hook (fires for any tool/terminal) + an
optional Claude Code PreToolUse hook. It's an **honesty gate**, not a sandbox —
the escape hatch is `git commit --no-verify`; don't use it to skip the review.

> Verify commands are configured in `.review-gate/gate.config.json`
> (`gateMode` must stay `"commit"`).
