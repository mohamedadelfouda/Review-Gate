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

# a foreign .githooks/pre-commit AND pre-push must NOT be clobbered without --force
git init -q "$TMP/hook-repo"
git -C "$TMP/hook-repo" config user.email a@b.c; git -C "$TMP/hook-repo" config user.name tester
mkdir -p "$TMP/hook-repo/.githooks"
printf '#!/bin/sh\necho custom-commit\n' > "$TMP/hook-repo/.githooks/pre-commit"
printf '#!/bin/sh\necho custom-push\n'   > "$TMP/hook-repo/.githooks/pre-push"
chmod +x "$TMP/hook-repo/.githooks/pre-commit" "$TMP/hook-repo/.githooks/pre-push"
git -C "$TMP/hook-repo" config core.hooksPath .githooks
bash "$KIT/install.sh" "$TMP/hook-repo" --mode commit --tools codex --yes >/dev/null
grep -q custom-commit "$TMP/hook-repo/.githooks/pre-commit" || fail "installer overwrote a foreign pre-commit without --force"
grep -q custom-push   "$TMP/hook-repo/.githooks/pre-push"   || fail "installer overwrote a foreign pre-push without --force"
bash "$KIT/install.sh" "$TMP/hook-repo" --mode commit --tools codex --yes --force >/dev/null
grep -q review-gate "$TMP/hook-repo/.githooks/pre-commit" || fail "--force did not replace the foreign pre-commit"
grep -q review-gate "$TMP/hook-repo/.githooks/pre-push"   || fail "--force did not replace the foreign pre-push"

# a CUSTOM hook that merely CALLS review-gate (no managed sentinel) must survive reinstall
git init -q "$TMP/embed-repo"
git -C "$TMP/embed-repo" config user.email a@b.c; git -C "$TMP/embed-repo" config user.name tester
bash "$KIT/install.sh" "$TMP/embed-repo" --mode commit --tools codex --yes >/dev/null
printf '#!/bin/sh\necho my-wrapper\nROOT="$(git rev-parse --show-toplevel)"; bash "$ROOT/.review-gate/review-gate.sh" precommit || exit $?\n' > "$TMP/embed-repo/.githooks/pre-commit"
bash "$KIT/install.sh" "$TMP/embed-repo" --mode commit --tools codex --yes >/dev/null
grep -q my-wrapper "$TMP/embed-repo/.githooks/pre-commit" || fail "reinstall clobbered a custom hook that merely embeds review-gate"

echo "PASS: review-gate installer test"
