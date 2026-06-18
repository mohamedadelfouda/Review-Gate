#!/usr/bin/env bash
# Self-contained smoke test for review-gate (commit mode). Creates a throwaway
# repo, installs the gate, and asserts the block → attest → unblock flow through
# a REAL git commit. Every step is time-boxed and prints its stage, so a hang is
# diagnosable and can NEVER stall CI. Exits non-zero on any failure.
set -uo pipefail
export PYTHONUTF8=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t rg-smoke)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

STAGE="start"
stage() { STAGE="$1"; }
fail()  { echo "FAIL [$STAGE]: $1" >&2; exit 1; }
# run "$@" under a hard timeout if available so a hang can't stall CI
run()   { if command -v timeout >/dev/null 2>&1; then timeout 90 "$@"; else "$@"; fi; }

stage "init repo"
git init -q || fail "git init"
git config user.email t@example.com; git config user.name tester
git checkout -q -b main 2>/dev/null || true
echo hi > a.txt; git add a.txt; git commit -qm init || fail "initial commit"

stage "install gate"
run bash "$KIT/install.sh" "$TMP" --mode commit --tools claude >/dev/null || fail "install timed out or failed"

# trivial, always-pass verify so the test exercises the GATE, not a toolchain
cat > .review-gate/gate.config.json <<'EOF'
{"gateMode":"commit","verify":{"typecheck":{"cmd":"true","perFile":false,"enabled":true},"lint":{"enabled":false},"test":{"enabled":false}},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF

# stage EVERYTHING (the installed gate files + our change) so there are no
# untracked files — the gate refuses to attest while untracked files exist.
echo "change" >> a.txt
git add -A

stage "commit blocked before attest"
if git commit -m blocked >/dev/null 2>&1; then fail "commit was NOT blocked before attest"; fi
[ "$(git rev-list --count HEAD)" = "1" ] || fail "a blocked commit still landed"

stage "attest"
run bash .review-gate/review-gate.sh attest --ran review,clean-code,docs >/dev/null 2>&1 || fail "attest timed out or failed"

stage "commit allowed after attest"
git commit -m reviewed >/dev/null 2>&1 || fail "commit blocked AFTER a passing attest"
[ "$(git rev-list --count HEAD)" = "2" ] || fail "reviewed commit did not land"

stage "re-stage blocks again"
echo more >> a.txt; git add a.txt
if git commit -m stale >/dev/null 2>&1; then fail "stale-marker commit was NOT blocked"; fi

stage "marker untracked"
[ -z "$(git ls-files .review-gate/.gate)" ] || fail "the attestation marker got committed"

echo "PASS: review-gate smoke test (commit mode)"
