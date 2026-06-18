#!/usr/bin/env bash
# Installer regression tests: --force replaces directories cleanly and an
# invalid existing config is preserved unless --force was explicitly requested.
set -uo pipefail
export PYTHONUTF8=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t rg-install)"
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo"
fail() { echo "FAIL: $1" >&2; exit 1; }

bash "$KIT/install.sh" "$TMP/repo" --tools codex >/dev/null || fail "initial install failed"
bash "$KIT/install.sh" "$TMP/repo" --tools codex --force >/dev/null || fail "forced reinstall failed"
[ ! -d "$TMP/repo/.review-gate/skills/clean-code-guard/clean-code-guard" ] || fail "--force nested clean-code-guard"
[ ! -d "$TMP/repo/.review-gate/skills/docs-guard/docs-guard" ] || fail "--force nested docs-guard"

printf '{broken json\n' > "$TMP/repo/.review-gate/gate.config.json"
if bash "$KIT/install.sh" "$TMP/repo" --tools codex >/dev/null 2>&1; then
  fail "installer silently replaced an invalid config"
fi
grep -qF '{broken json' "$TMP/repo/.review-gate/gate.config.json" || fail "invalid config was not preserved"

echo "PASS: review-gate installer test"
