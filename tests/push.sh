#!/usr/bin/env bash
# Push-mode integration test: the attestation must bind to the ref actually
# pushed, not merely to the checked-out HEAD — pushing a different (unattested)
# branch must be blocked. Every git push here is internal to a temp repo.
set -uo pipefail
export PYTHONUTF8=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t rg-push)"
trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/remote.git"; WORK="$TMP/work"

git init -q --bare "$REMOTE"
git init -q "$WORK"
git -C "$WORK" config user.email t@example.com
git -C "$WORK" config user.name tester
git -C "$WORK" checkout -q -b main
echo main > "$WORK/a.txt"; git -C "$WORK" add a.txt; git -C "$WORK" commit -qm main
git -C "$WORK" checkout -q -b other
echo other > "$WORK/a.txt"; git -C "$WORK" commit -qam other
git -C "$WORK" checkout -q main
git -C "$WORK" remote add origin "$REMOTE"

bash "$KIT/install.sh" "$WORK" --mode push --tools codex >/dev/null
cat > "$WORK/.review-gate/gate.config.json" <<'EOF'
{"gateMode":"push","verify":{"typecheck":{"cmd":"true","perFile":false,"enabled":true},"lint":{"enabled":false},"test":{"enabled":false}},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF

fail() { echo "FAIL: $1" >&2; exit 1; }
cd "$WORK" || exit 1

# Commit the review-gate setup so the tree is clean (the gate requires no
# unstaged/untracked files in push mode), then attest the resulting HEAD.
git add -A && git commit -qm "add review-gate" || fail "could not commit setup"
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs >/dev/null 2>&1 || fail "attest did not pass"

# Pushing 'other' (a commit that is NOT the attested HEAD) must be blocked.
if git push origin other >/dev/null 2>&1; then
  fail "an unattested non-HEAD ref was pushed"
fi
git --git-dir="$REMOTE" rev-parse --verify refs/heads/other >/dev/null 2>&1 && fail "blocked ref landed remotely"

# Pushing the attested HEAD ('main') must succeed.
git push origin main >/dev/null 2>&1 || fail "the attested HEAD ref was blocked"
[ "$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" = "$(git rev-parse main)" ] || fail "attested ref did not land"

echo "PASS: review-gate push test (actual pushed refs are enforced)"
