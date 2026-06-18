#!/usr/bin/env bash
# ci-verify integration test: the installed `.review-gate/review-gate.sh ci-verify`
# runs the configured verify and exits non-zero on failure. Guards against the
# "CI workflow references a path that doesn't exist / verify diverges" class of bug.
set -uo pipefail
export PYTHONUTF8=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t rg-ci)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q; git config user.email t@example.com; git config user.name tester
git checkout -q -b main 2>/dev/null || true
echo hi > a.txt; git add a.txt; git commit -qm init

bash "$KIT/install.sh" "$TMP" --mode commit --tools claude --yes >/dev/null

fail() { echo "FAIL: $1" >&2; exit 1; }

# the installer must have placed a runnable gate at the path the CI template uses
[ -f .review-gate/review-gate.sh ] || fail ".review-gate/review-gate.sh missing after install"

# passing verify
cat > .review-gate/gate.config.json <<'EOF'
{"gateMode":"commit","verify":{"typecheck":{"cmd":"true","perFile":false,"enabled":true},"lint":{"enabled":false},"test":{"enabled":false}},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF
bash .review-gate/review-gate.sh ci-verify >/dev/null 2>&1 || fail "ci-verify failed on a passing config"

# failing verify
cat > .review-gate/gate.config.json <<'EOF'
{"gateMode":"commit","verify":{"typecheck":{"cmd":"false","perFile":false,"enabled":true},"lint":{"enabled":false},"test":{"enabled":false}},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF
if bash .review-gate/review-gate.sh ci-verify >/dev/null 2>&1; then fail "ci-verify passed on a FAILING config"; fi

# perFile + multi-commit: with NO base branch, ci-verify must check ALL tracked
# files (empty-tree fallback), not just the tip commit — else a BAD file added in an
# EARLIER commit slips through. (--no-verify is test scaffolding to build history
# without going through the gate.) The lint fails if any checked file contains BAD.
printf 'BAD\n' > flag.txt;  git add flag.txt;  git commit -qm flag  --no-verify
printf 'ok\n'  > later.txt; git add later.txt; git commit -qm later --no-verify
cat > .review-gate/gate.config.json <<'EOF'
{"gateMode":"commit","verify":{"typecheck":{"enabled":false},"lint":{"cmd":"! grep -q BAD","perFile":true,"enabled":true},"test":{"enabled":false}},"lintableExtensions":["txt"],"codeExtensions":["txt"]}
EOF
if bash .review-gate/review-gate.sh ci-verify >/dev/null 2>&1; then
  fail "ci-verify missed an earlier commit's file (no base must check ALL files, not just the tip)"
fi

echo "PASS: review-gate ci-verify test"
