#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# review-gate installer — set up the review gate in a target repo.
#
# Usage:
#   bash install.sh /path/to/repo [--mode push|commit] [--tools all|claude,codex,cursor,windsurf] [--force]
#
#   --mode   commit (default for local-only repos) | push
#   --tools  which AI-tool integrations to wire (default: all). The git hook
#            enforcement is ALWAYS installed regardless — it covers the terminal
#            and any tool that runs git.
#   --force  overwrite agents/skills/config/cursor-rule if they already exist.
#
# Installs:
#   .review-gate/        review-gate.sh, gate.config.json, GATE.md, agents/, skills/
#   .githooks/           pre-commit + pre-push  (+ git config core.hooksPath .githooks)
#   per tool:  CLAUDE.md + .claude/{agents,skills,settings.json}  (claude)
#              AGENTS.md                                          (codex & others)
#              .cursor/rules/review-gate.mdc                      (cursor)
#              .windsurfrules                                     (windsurf)
#   .gitignore  += .review-gate/.gate/
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Python 3 as $REVIEW_GATE_PYTHON (override) → python3 → python.
py() { if [ -n "${REVIEW_GATE_PYTHON:-}" ]; then "$REVIEW_GATE_PYTHON" "$@"; elif command -v python3 >/dev/null 2>&1; then python3 "$@"; elif command -v python >/dev/null 2>&1; then python "$@"; else return 127; fi; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""; GATE_MODE="commit"; TOOLS="all"; FORCE=0
MODE_SET=0; TOOLS_SET=0; FORCE_INTERACTIVE=0; ASSUME_YES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)        GATE_MODE="${2:-commit}"; MODE_SET=1; shift 2 ;;
    --mode=*)      GATE_MODE="${1#--mode=}"; MODE_SET=1; shift ;;
    --tools)       TOOLS="${2:-all}"; TOOLS_SET=1; shift 2 ;;
    --tools=*)     TOOLS="${1#--tools=}"; TOOLS_SET=1; shift ;;
    --force)       FORCE=1; shift ;;
    --interactive) FORCE_INTERACTIVE=1; shift ;;   # prompt even when stdin isn't a TTY
    --yes|-y)      ASSUME_YES=1; shift ;;           # never prompt; take detected/defaults
    -*)            echo "unknown option: $1" >&2; exit 2 ;;
    *)             [ -z "$TARGET" ] && TARGET="$1"; shift ;;
  esac
done

{ [ "$MODE_SET" -eq 0 ] || [ "$GATE_MODE" = push ] || [ "$GATE_MODE" = commit ]; } || { echo "❌ --mode must be push|commit" >&2; exit 2; }
[ -n "$TARGET" ] || { echo "usage: bash install.sh /path/to/repo [--mode push|commit] [--tools all|claude,codex,cursor,windsurf] [--interactive|--yes] [--force]" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "❌ target not found: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "❌ $TARGET is not a git repo. Run 'git init' first." >&2; exit 1; }
[ -n "${REVIEW_GATE_PYTHON:-}" ] || command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || { echo "❌ Python 3 (REVIEW_GATE_PYTHON, python3, or python) is required to install review-gate." >&2; exit 1; }

# ── Auto-detect, and (only with a human at a TTY) ask to confirm ────────────
detect_tools() {  # comma list of AI tools present in the repo, else "all"
  local d=""
  [ -d "$TARGET/.cursor" ] && d="$d cursor"
  { [ -f "$TARGET/CLAUDE.md" ] || [ -d "$TARGET/.claude" ]; } && d="$d claude"
  [ -f "$TARGET/AGENTS.md" ] && d="$d codex"
  [ -f "$TARGET/.windsurfrules" ] && d="$d windsurf"
  d="$(echo "$d" | xargs | tr ' ' ',')"
  [ -n "$d" ] && echo "$d" || echo "all"
}
detect_mode() { [ -n "$(git -C "$TARGET" remote 2>/dev/null)" ] && echo push || echo commit; }
detect_preset() {  # verify preset NAME that best fits the project's stack
  if [ -f "$TARGET/package.json" ]; then echo node
  elif [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/setup.py" ] || ls "$TARGET"/*.py >/dev/null 2>&1; then echo python
  elif [ -f "$TARGET/go.mod" ]; then echo go
  else echo node; fi   # unknown → node default; edit after
}
preset_path() {  # preset name → example config path
  case "$1" in
    python)  echo "$SCRIPT_DIR/gate/examples/python.gate.config.json" ;;
    go)      echo "$SCRIPT_DIR/gate/examples/go.gate.config.json" ;;
    minimal) echo "$SCRIPT_DIR/gate/examples/minimal.gate.config.json" ;;
    *)       echo "$SCRIPT_DIR/gate/gate.config.example.json" ;;   # node
  esac
}

ASK=0
{ [ -t 0 ] && [ -t 1 ]; } && ASK=1            # a real terminal with a human
[ "$FORCE_INTERACTIVE" -eq 1 ] && ASK=1
[ "$ASSUME_YES" -eq 1 ] && ASK=0              # --yes wins: never prompt (CI / scripted)

if [ "$MODE_SET" -eq 0 ]; then
  SUGGEST_MODE="$(detect_mode)"
  if [ "$ASK" -eq 1 ]; then
    printf 'Gate on local "commit" or on "push"? [%s]: ' "$SUGGEST_MODE" >&2
    read -r ans 2>/dev/null || ans=""; GATE_MODE="${ans:-$SUGGEST_MODE}"
  else GATE_MODE="$SUGGEST_MODE"; fi
fi
[ "$GATE_MODE" = push ] || [ "$GATE_MODE" = commit ] || { echo "❌ mode must be push|commit (got '$GATE_MODE')" >&2; exit 2; }

if [ "$TOOLS_SET" -eq 0 ]; then
  DETECTED_TOOLS="$(detect_tools)"
  if [ "$ASK" -eq 1 ]; then
    printf 'AI tools to wire (comma list, or "all") [%s]: ' "$DETECTED_TOOLS" >&2
    read -r ans 2>/dev/null || ans=""; TOOLS="${ans:-$DETECTED_TOOLS}"
  else TOOLS="$DETECTED_TOOLS"; fi
fi

PRESET="$(detect_preset)"
if [ "$ASK" -eq 1 ]; then
  printf 'Verify preset — node / python / go / minimal? [%s]: ' "$PRESET" >&2
  read -r ans 2>/dev/null || ans=""; PRESET="${ans:-$PRESET}"
fi
CONFIG_EXAMPLE="$(preset_path "$PRESET")"

want_tool() { case ",$TOOLS," in *",all,"*) return 0 ;; *",$1,"*) return 0 ;; *) return 1 ;; esac; }

copy_if() {  # src dst — copy unless dst exists (unless --force); rm -rf before
             # overwriting a dir so cp -r doesn't nest a copy inside the old one.
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then echo "  ~ kept $(basename "$dst")"; return; fi
  [ -e "$dst" ] && rm -rf "$dst"
  cp -r "$src" "$dst"; echo "  ✓ $(basename "$dst")"
}

# Upsert a marked block (<!-- review-gate:begin/end -->) into a text file.
upsert_block() {
  TARGET_F="$1" SNIPPET_F="$2" py - <<'PY'
import os, re, sys
try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass
tf, sf = os.environ["TARGET_F"], os.environ["SNIPPET_F"]
block = open(sf, encoding="utf-8").read().strip("\n")
b, e = "<!-- review-gate:begin -->", "<!-- review-gate:end -->"
try: cur = open(tf, encoding="utf-8").read()
except FileNotFoundError: cur = ""
if b in cur and e in cur:
    new = re.sub(re.escape(b) + r".*?" + re.escape(e), block.replace("\\", "\\\\"), cur, flags=re.S)
    act = "updated"
else:
    sep = "" if cur == "" else ("\n" if cur.endswith("\n") else "\n\n")
    new = cur + sep + block + "\n"; act = "added"
open(tf, "w", encoding="utf-8").write(new)
print(f"  - {os.path.basename(tf)} {act}")
PY
}

CG="$TARGET/.review-gate"
echo "▶ Installing review-gate [$GATE_MODE mode, tools: $TOOLS] into $TARGET"

# ── 1. .review-gate/ core ───────────────────────────────────────────────────
mkdir -p "$CG/agents" "$CG/skills" "$CG/.gate"
cp "$SCRIPT_DIR/gate/review-gate.sh" "$CG/review-gate.sh"; chmod +x "$CG/review-gate.sh"
cp "$SCRIPT_DIR/setup.sh" "$CG/setup.sh"; chmod +x "$CG/setup.sh"
echo "  ✓ .review-gate/review-gate.sh + setup.sh"

# Config: created if absent; an INVALID existing config is PRESERVED and the
# install aborts unless --force replaces it. gateMode then synced to --mode.
CFG="$CG/gate.config.json"
if [ -f "$CFG" ] && [ "$FORCE" -ne 1 ]; then
  if CFG_PATH="$CFG" py -c 'import json,os; json.load(open(os.environ["CFG_PATH"]))' >/dev/null 2>&1; then
    echo "  ~ kept existing gate.config.json"
  else
    echo "  ✗ $CFG exists but is INVALID JSON — left untouched. Fix it, or re-run with --force to replace it." >&2
    exit 1
  fi
else
  cp "$CONFIG_EXAMPLE" "$CFG"
  echo "  ✓ gate.config.json (verify preset: $(basename "$CONFIG_EXAMPLE") — edit it to match your project)"
fi
CG_CFG="$CFG" GATE_MODE="$GATE_MODE" py - <<'PY'
import json, os, sys
try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass
p, mode = os.environ["CG_CFG"], os.environ["GATE_MODE"]
cfg = json.load(open(p))   # valid here (validated or freshly copied above)
if cfg.get("gateMode") != mode:
    cfg["gateMode"] = mode
    open(p, "w").write(json.dumps(cfg, indent=2) + "\n")
    print(f"  - gate.config.json gateMode = '{mode}'")
else:
    print(f"  - gate.config.json gateMode already '{mode}'")
PY

for a in "$SCRIPT_DIR"/agents/*.md; do copy_if "$a" "$CG/agents/$(basename "$a")"; done
for s in "$SCRIPT_DIR"/skills/*/; do copy_if "$s" "$CG/skills/$(basename "$s")"; done

if [ "$GATE_MODE" = commit ]; then cp "$SCRIPT_DIR/templates/GATE.commit.md" "$CG/GATE.md"; else cp "$SCRIPT_DIR/templates/GATE.push.md" "$CG/GATE.md"; fi
echo "  ✓ .review-gate/GATE.md ($GATE_MODE protocol)"

# ── 2. git hooks (universal enforcement) ────────────────────────────────────
mkdir -p "$TARGET/.githooks"
install_hook() {  # src dst — never clobber a foreign hook: back it up + warn first
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! grep -q "review-gate" "$dst" 2>/dev/null; then
    cp "$dst" "$dst.pre-review-gate.bak"
    echo "  ⚠ existing $(basename "$dst") wasn't review-gate's — backed it up to $(basename "$dst").pre-review-gate.bak (it will no longer run; re-add its logic if you need it)"
  fi
  cp "$src" "$dst"; chmod +x "$dst"
}
install_hook "$SCRIPT_DIR/githooks/pre-commit" "$TARGET/.githooks/pre-commit"
install_hook "$SCRIPT_DIR/githooks/pre-push"   "$TARGET/.githooks/pre-push"
echo "  ✓ .githooks/pre-commit + pre-push"

CUR_HP="$(git -C "$TARGET" config --local --get core.hooksPath 2>/dev/null || true)"
if [ -z "$CUR_HP" ] || [ "$CUR_HP" = ".githooks" ]; then
  git -C "$TARGET" config core.hooksPath .githooks
  echo "  ✓ git config core.hooksPath = .githooks"
else
  echo "  ⚠ ENFORCEMENT NOT INSTALLED — core.hooksPath is already '$CUR_HP' (husky/other);"
  echo "    review-gate did NOT override it. Until you wire it in, commits/pushes are NOT gated."
  echo "    Add these two lines yourself:"
  echo "      → $CUR_HP/pre-commit :  ROOT=\"\$(git rev-parse --show-toplevel)\"; exec bash \"\$ROOT/.review-gate/review-gate.sh\" precommit"
  echo "      → $CUR_HP/pre-push   :  ROOT=\"\$(git rev-parse --show-toplevel)\"; exec bash \"\$ROOT/.review-gate/review-gate.sh\" prepush"
fi

# ── 3. per-tool integrations ────────────────────────────────────────────────
if want_tool claude; then
  echo "  claude:"
  mkdir -p "$TARGET/.claude/agents" "$TARGET/.claude/skills"
  for a in "$CG"/agents/*.md; do copy_if "$a" "$TARGET/.claude/agents/$(basename "$a")"; done
  for s in "$CG"/skills/*/; do copy_if "$s" "$TARGET/.claude/skills/$(basename "$s")"; done
  upsert_block "$TARGET/CLAUDE.md" "$SCRIPT_DIR/integrations/claude/CLAUDE.snippet.md"
  CLAUDE_SETTINGS="$TARGET/.claude/settings.json" GATE_MODE="$GATE_MODE" py - <<'PY'
import json, os, sys
try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass
path, mode = os.environ["CLAUDE_SETTINGS"], os.environ["GATE_MODE"]
try: data = json.load(open(path))
except FileNotFoundError: data = {}
except json.JSONDecodeError as e:
    sys.stderr.write(f"  ! {path} invalid JSON ({e}); skipping hook wiring.\n"); raise SystemExit(0)
pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
blk = next((b for b in pre if b.get("matcher") == "Bash"), None)
if blk is None: blk = {"matcher": "Bash", "hooks": []}; pre.append(blk)
bh = blk.setdefault("hooks", [])
cmd = "bash .review-gate/review-gate.sh check"
conds = ["Bash(git commit*)"] if mode == "commit" else ["Bash(git push*)", "Bash(gh pr create*)"]
existing = [h for h in bh if "review-gate.sh" in (h.get("command") or "")]
if {h.get("if") for h in existing} == set(conds):
    print("  - .claude/settings.json hook already correct for this mode")
else:
    # Rebuild from scratch so a mode change (commit<->push) updates the condition
    # instead of leaving a stale one behind.
    bh[:] = [h for h in bh if "review-gate.sh" not in (h.get("command") or "")]
    for c in conds: bh.append({"type":"command","command":cmd,"if":c,"timeout":30,"statusMessage":"Review Gate"})
    open(path, "w").write(json.dumps(data, indent=2) + "\n")
    print(f"  - .claude/settings.json PreToolUse hook set for {mode} mode ({', '.join(conds)})")
PY
fi

if want_tool codex; then
  echo "  codex:"
  upsert_block "$TARGET/AGENTS.md" "$SCRIPT_DIR/integrations/codex/AGENTS.md"
fi

if want_tool cursor; then
  echo "  cursor:"
  mkdir -p "$TARGET/.cursor/rules"
  copy_if "$SCRIPT_DIR/integrations/cursor/review-gate.mdc" "$TARGET/.cursor/rules/review-gate.mdc"
fi

if want_tool windsurf; then
  echo "  windsurf:"
  upsert_block "$TARGET/.windsurfrules" "$SCRIPT_DIR/integrations/windsurf/windsurfrules.snippet"
fi

# ── 4a. .gitattributes — keep the installed shell scripts/hooks LF on every OS ─
GA="$TARGET/.gitattributes"
if [ -f "$GA" ] && grep -qF '.review-gate/review-gate.sh text eol=lf' "$GA" 2>/dev/null; then
  echo "  ✓ .gitattributes already pins LF for the gate scripts"
else
  printf '\n# review-gate: shell scripts/hooks must stay LF (a CRLF shebang breaks them on macOS/Linux)\n.githooks/pre-commit text eol=lf\n.githooks/pre-push text eol=lf\n.review-gate/review-gate.sh text eol=lf\n' >> "$GA"
  echo "  ✓ .gitattributes += LF pins for the gate scripts"
fi

# ── 4b. .gitignore the marker ────────────────────────────────────────────────
GI="$TARGET/.gitignore"
if [ -f "$GI" ] && grep -qE '^\.review-gate/\.gate/?$' "$GI" 2>/dev/null; then
  echo "  ✓ .gitignore already ignores .review-gate/.gate/"
else
  printf '\n# review-gate attestation marker (machine-local)\n.review-gate/.gate/\n' >> "$GI"
  echo "  ✓ .gitignore += .review-gate/.gate/"
fi

echo
echo "✅ review-gate installed [$GATE_MODE mode] in $TARGET"
echo "   Next:"
echo "   1) Edit .review-gate/gate.config.json so verify (typecheck/lint/test) matches this project"
echo "      (examples in $SCRIPT_DIR/gate/examples/). Keep gateMode = \"$GATE_MODE\"."
echo "   2) Commit the review-gate files. (The FIRST commit is gated too — run the review + attest for it.)"
echo "   3) Anyone who clones this repo runs once:  bash .review-gate/setup.sh"
echo "      (or: git config core.hooksPath .githooks — git hooks are per-clone.)"
echo "   • Optional un-bypassable enforcement: copy $SCRIPT_DIR/integrations/ci/github-actions.yml"
echo "     to .github/workflows/review-gate.yml (re-runs verify on every PR)."
echo "   4) If using Claude Code: restart it (or open /hooks) so the PreToolUse hook loads."
