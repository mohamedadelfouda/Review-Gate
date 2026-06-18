#!/usr/bin/env bash
# Self-contained smoke test for review-gate (commit mode). Creates a throwaway
# repo, installs the gate, and asserts the block → attest → unblock flow through
# a REAL git commit. Exits non-zero on any failure. Safe to run in CI.
set -uo pipefail
export PYTHONUTF8=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t rg-smoke)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

git init -q
git config user.email t@example.com
git config user.name tester
git checkout -q -b main 2>/dev/null || true
echo hi > a.txt; git add a.txt; git commit -qm init

bash "$KIT/install.sh" "$TMP" --mode commit --tools claude >/dev/null

# trivial, always-pass verify so the test exercises the GATE, not a toolchain
cat > .review-gate/gate.config.json <<'EOF'
{"gateMode":"commit","verify":{"typecheck":{"cmd":"true","perFile":false,"enabled":true},"lint":{"enabled":false},"test":{"enabled":false}},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "change" >> a.txt; git add a.txt

# 1) a commit must be BLOCKED before attest
if git commit -m blocked >/dev/null 2>&1; then fail "commit was NOT blocked before attest"; fi
[ "$(git rev-list --count HEAD)" = "1" ] || fail "a blocked commit still landed"

# 2) attest, then the commit must PASS
bash .review-gate/review-gate.sh attest --ran review,clean-code >/dev/null 2>&1 || fail "attest did not pass"
git commit -m reviewed >/dev/null 2>&1 || fail "commit blocked AFTER a passing attest"
[ "$(git rev-list --count HEAD)" = "2" ] || fail "reviewed commit did not land"

# 3) re-staging different content must BLOCK again (stale marker)
echo more >> a.txt; git add a.txt
if git commit -m stale >/dev/null 2>&1; then fail "stale-marker commit was NOT blocked"; fi

# 4) the marker must NOT be tracked
[ -z "$(git ls-files .review-gate/.gate)" ] || fail "the attestation marker got committed"

echo "PASS: review-gate smoke test (commit mode)"
