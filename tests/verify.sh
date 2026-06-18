#!/usr/bin/env bash
# review-gate self-verify: syntax-check every shell script + git hook in the repo.
# Used as this repo's own gate.config.json "typecheck" command (dogfooding).
set -uo pipefail
fail=0
while IFS= read -r f; do
  bash -n "$f" || { echo "✗ syntax error: $f" >&2; fail=1; }
done < <(find . -path ./.git -prune -o -type f \( -name '*.sh' -o -name 'pre-commit' -o -name 'pre-push' \) -print)
if [ "$fail" -eq 0 ]; then echo "✓ shell syntax OK"; else exit 1; fi
