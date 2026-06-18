#!/usr/bin/env bash
# Regression test: an EMPTY verify block ("verify": {}) must NOT fall back to
# Node defaults. Because {} is falsy in Python, the old code treated a present
# but empty block as "absent" and re-enabled tsc/eslint/vitest. With "verify"
# present (even {}), every omitted step must be DISABLED. README documents this.
# Self-contained + time-boxed like smoke.sh, so a hang can never stall CI.
set -uo pipefail
export PYTHONUTF8=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t rg-emptyverify)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

STAGE="start"
stage() { STAGE="$1"; }
fail()  { echo "FAIL [$STAGE]: $1" >&2; exit 1; }
run()   { if command -v timeout >/dev/null 2>&1; then timeout 90 "$@"; else "$@"; fi; }

stage "init repo"
git init -q || fail "git init"
git config user.email t@example.com; git config user.name tester
git checkout -q -b main 2>/dev/null || true
echo hi > a.txt; git add a.txt; git commit -qm init || fail "initial commit"

stage "install gate"
run bash "$KIT/install.sh" "$TMP" --mode commit --tools claude >/dev/null || fail "install timed out or failed"

# An EMPTY verify block. No step is configured: all three must be DISABLED, and
# NONE of the Node default commands (tsc/eslint/vitest) may run.
cat > .review-gate/gate.config.json <<'EOF'
{"gateMode":"commit","verify":{},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF

echo "change" >> a.txt
git add -A

stage "attest with empty verify"
OUT="$(run bash .review-gate/review-gate.sh attest --ran review,clean-code,docs 2>&1)" \
  || fail "attest failed (empty verify should disable every step, not run Node defaults):
$OUT"

stage "no Node defaults ran"
case "$OUT" in
  *tsc*|*eslint*|*vitest*) fail "a Node default command leaked into verify with empty 'verify: {}':
$OUT" ;;
esac

stage "every step disabled"
echo "$OUT" | grep -q "typecheck: disabled" || fail "typecheck not disabled:
$OUT"
echo "$OUT" | grep -q "lint: disabled"      || fail "lint not disabled:
$OUT"
echo "$OUT" | grep -q "test: disabled"      || fail "test not disabled:
$OUT"

stage "commit allowed after attest"
git commit -m reviewed >/dev/null 2>&1 || fail "commit blocked AFTER a passing attest"
[ "$(git rev-list --count HEAD)" = "2" ] || fail "reviewed commit did not land"

echo "PASS: review-gate empty-verify regression test"
