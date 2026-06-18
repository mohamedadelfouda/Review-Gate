#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

bash tests/smoke.sh || exit 1
bash tests/empty-verify.sh || exit 1
bash tests/push.sh || exit 1
bash tests/install.sh || exit 1
bash tests/ci.sh || exit 1

echo "PASS: all review-gate integration tests"
