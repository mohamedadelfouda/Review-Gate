# review-gate

> **Review before code lands.**
>
> `review-gate` is a tool-agnostic **review + verify gate** for Git repositories.
> It blocks `git commit` or `git push` until the change has been reviewed and your
> configured verify command has passed for the **exact change** being committed or pushed.

- **Status:** `v0.2.0` — Public Beta
- **Created by:** Fouda
- **License:** MIT
- **Telemetry:** None by default — it never sends your code, diffs, file names, or repo metadata anywhere.
- **Works with:** terminal, humans, Claude Code, OpenAI Codex, Cursor, Windsurf, and any tool that runs Git.

**🇬🇧 [English](#english) · 🇪🇬 [العربية](#العربية)**

### Quick links
[60-second flow](#60-second-flow) · [Quick install](#quick-install) ·
[Two modes](#two-modes) · [Configure verify](#configure-verify) ·
[CI companion](#ci-companion) · [Fail-closed](#fail-closed-behavior) ·
[Privacy](#privacy) · [Limitations](#limitations)

---

## English

### Why this exists

AI coding tools are fast. Sometimes too fast. A coding agent can edit files, run a
quick check, and commit or push before a proper review happened. `review-gate` adds
a simple rule at the Git boundary:

> No commit or push until review was acknowledged and verify passed for the exact change.

It is especially useful for AI-assisted workflows where Claude Code, Codex, Cursor,
Windsurf, or another tool may be changing code quickly.

### 60-second flow

```bash
git add -A
git commit -m "change"
# 🔒 blocked: no fresh review-gate attestation for this change

bash .review-gate/review-gate.sh attest --ran review,clean-code
git commit -m "change"
# ✅ allowed
```

If you change the code after attesting, the marker goes stale and the next commit is
blocked again — approval is bound to the exact change, not to "I ran it once".

### What it does

`review-gate` installs native Git hooks that block either `git commit` (**commit
mode**) or `git push` (**push mode**). Before the action is allowed, you run:

```bash
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
```

The gate then:

1. computes which review/guard steps are required from the changed files,
2. checks that your `--ran` steps cover them,
3. runs the configured verify steps: typecheck, lint, and test,
4. writes a local marker tied to the exact staged tree or HEAD commit,
5. lets the Git hook pass only while that marker still matches.

### Important: honesty gate, not a sandbox

`review-gate` is an **honesty gate**, not a security sandbox. It prevents accidental
skips — "the agent forgot to review", "I committed before running tests", "the staged
code changed after review", "I attested one branch but pushed another".

It does **not** stop a determined person from bypassing local Git hooks (git's own
`--no-verify` skips hooks entirely — no local hook can prevent that). For hard,
non-bypassable enforcement, pair it with CI: make the included GitHub Actions
companion (`integrations/ci/github-actions.yml`) a **required** status check.

### Two modes

Set the mode in `.review-gate/gate.config.json` via `"gateMode": "commit"` or
`"gateMode": "push"`.

| Mode     | Blocks       | Marker binds to          | Best for                                                        |
| -------- | ------------ | ------------------------ | --------------------------------------------------------------- |
| `commit` | `git commit` | staged tree              | local-first projects, solo work, repos that do not always push  |
| `push`   | `git push`   | HEAD commit / pushed ref | team repos, PR workflows, remote-backed projects                |

#### Commit mode

The gate binds to the **staged tree**. Recommended flow:

```bash
git add -A
# review the staged diff
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
git commit -m "your message"
```

It blocks attestation if there are unstaged tracked changes or non-ignored untracked
files, because those are visible to verify but may not be part of the commit.

#### Push mode

The gate binds to the **commit being pushed**. Recommended flow:

```bash
# review the branch diff
git commit -m "your message"
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
git push
```

The pre-push hook validates the actual refs Git is pushing, not only the currently
checked-out `HEAD`. Attesting one branch does not unlock pushing a different branch.

`gh pr create` is not a universal Git hook event. The Claude integration additionally
blocks `gh pr create`, but for guaranteed PR-level enforcement add the CI companion.

> In push mode, attest does a best-effort, time-boxed `git fetch` to resolve the
> review base against your remote — it still works offline (it falls back to your
> local base).

### Quick install

Clone or download this repo, then run the installer against your target repo:

```bash
bash install.sh /path/to/your-repo
```

**It asks, instead of guessing.** Run in a terminal with no flags and the installer
auto-detects your project, then **asks you to confirm**:

- **mode** — `commit` or `push` (suggested from whether the repo has a Git remote),
- **tools** — which AI integrations to wire (detected from `.cursor/`, `CLAUDE.md`,
  `AGENTS.md`, `.windsurfrules`; falls back to all if none are found),
- **verify preset** — node / python / go / minimal (detected from `package.json` /
  `pyproject.toml` / `go.mod`).

Skip the questions with explicit flags, or `--yes` to take the detected values (CI /
scripted runs never prompt, so they can't hang):

```bash
bash install.sh /path/to/your-repo --mode push --tools claude,cursor
bash install.sh /path/to/your-repo --yes
```

Supported tool values: `claude,codex,cursor,windsurf`.

When an **AI agent** (Claude / Codex / Cursor / …) installs review-gate, it asks you
those same choices **in your own language** and proposes verify commands from your
project — see **[`SETUP.md`](SETUP.md)**.

### What the installer adds

```text
.review-gate/
  review-gate.sh
  gate.config.json
  GATE.md
  agents/
  skills/
  setup.sh
.githooks/
  pre-commit
  pre-push
```

It also: sets `core.hooksPath` to `.githooks` (only when safe), installs the AI-tool
instruction files, adds `.review-gate/.gate/` to `.gitignore`, and pins shell
scripts/hooks to LF via `.gitattributes`.

**Your existing hooks are safe.** If your repo already uses Husky or another hook
manager, review-gate leaves your `core.hooksPath` untouched and prints the commands
to wire itself in manually. And if a non-review-gate `.githooks/pre-commit` /
`pre-push` already exists, the installer **leaves it in place** and prints how to
wire review-gate into it (use `--force` to replace it) — it never silently
overwrites your hooks.

### After install

1. Edit `.review-gate/gate.config.json` and set the verify commands for your stack.
2. Commit the review-gate files. The first commit is gated too, so run review + attest before committing.
3. Every person who clones the repo runs once: `bash .review-gate/setup.sh`
   (it sets `core.hooksPath`, refusing to override an existing one). Git hooks are
   local per clone, so this is required for every clone.

### Configure verify

`review-gate` can run any commands you want. The installer pre-fills a preset based
on your detected stack; edit it freely. Example for Python:

```json
{
  "gateMode": "commit",
  "verify": {
    "typecheck": { "cmd": "python -m mypy .",      "perFile": false, "enabled": true },
    "lint":      { "cmd": "python -m ruff check",  "perFile": true,  "enabled": true },
    "test":      { "cmd": "python -m pytest -q",   "perFile": false, "enabled": true }
  },
  "lintableExtensions": ["py"],
  "codeExtensions": ["py"]
}
```

`perFile: true` appends the changed files as safe positional arguments, e.g.
`python -m ruff check changed_1.py changed_2.py`. `perFile: false` runs the command
once for the whole project.

If the whole `verify` block is omitted, review-gate uses Node defaults
(`tsc --noEmit`, `eslint --max-warnings 0`, `vitest related --run`). If a `verify`
block exists but one step is omitted, that step is **disabled** instead of silently
falling back to Node. Ready-made examples: `gate/examples/{python,go,minimal}.gate.config.json`.

### Review steps

`--ran` always includes `review`. Extra guard steps are required by changed files:

| Step         | Required when           |
| ------------ | ----------------------- |
| `clean-code` | production code changed |
| `test`       | test files changed      |
| `docs`       | docs / markdown changed |

```bash
bash .review-gate/review-gate.sh attest --ran review,clean-code        # code only
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs   # code + docs
```

If a required step is missing, `attest` refuses to write the marker.

### Tool coverage

| Actor                  | Enforcement                | Review guidance                                 |
| ---------------------- | -------------------------- | ----------------------------------------------- |
| Terminal / human       | Git hook                   | `GATE.md`                                       |
| Any tool that runs Git | Git hook                   | `GATE.md`                                       |
| Claude Code            | Git hook + PreToolUse hook | `CLAUDE.md`, `.claude/agents`, `.claude/skills` |
| OpenAI Codex           | Git hook                   | `AGENTS.md`                                     |
| Cursor                 | Git hook                   | `.cursor/rules/review-gate.mdc`                 |
| Windsurf               | Git hook                   | `.windsurfrules`                                |

The Git hook is the actual enforcement. AI integrations are extra instructions that
make tools review proactively before they commit or push. Tools that cannot spawn
subagents can still apply the agents and guard-skills as checklists in one pass.

### Fail-closed behavior

`review-gate` fails closed for configuration mistakes. It blocks when:
`.review-gate/gate.config.json` is missing, is invalid JSON, or has an invalid
`gateMode`; the marker is missing, corrupt, or for another mode; the staged tree
changed after attest (commit mode); HEAD or the pushed ref changed after attest
(push mode); untracked non-ignored files or unstaged tracked changes are present at
attest; or verify fails. Ignored files do not block attest.

### CI companion

Local hooks are useful but bypassable. For stronger enforcement, add the CI workflow
(`integrations/ci/github-actions.yml`) and require it. It runs
`bash .review-gate/review-gate.sh ci-verify`, which re-runs the **same** configured
verify as local attest (it honors `perFile` — perFile commands run on the PR's
changed files, others whole-project). CI cannot prove a review was thoughtful, but it
enforces the real verify step on every pull request — regardless of any local
`--no-verify`.

> **Still honesty-based, not a hard lock.** The CI check runs the gate + config from
> the PR's own content, so a PR author can weaken `gate.config.json` or the gate
> itself and turn the check green. For a true lock, protect `.review-gate/**` with
> required review (e.g. CODEOWNERS), or run the gate + config from your base branch.

### Requirements

- `bash`, `git`, and Python 3 as `python3` or `python`. If your environment has a
  wrapped or missing `python3`, pin one explicitly:

  ```bash
  REVIEW_GATE_PYTHON=/usr/bin/python3 bash .review-gate/review-gate.sh attest --ran review,clean-code
  ```

- On Windows, use Git Bash.
- Shell scripts and hooks are pinned to LF. If no Python 3 is found, the gate fails
  closed. GNU `timeout` is used when available; the gate degrades gracefully without
  it (e.g. stock macOS).

### Privacy

`review-gate` does not collect telemetry. It does not send your code, file names,
diffs, commands, or repository metadata anywhere. Everything runs locally; the only
network access is your own `git fetch` (push mode, best-effort) to resolve a review
base against **your** remote.

### Tests

```bash
bash tests/run.sh        # the full integration suite
bash tests/verify.sh     # shell syntax
bash tests/smoke.sh      # commit-mode block → attest → unblock
bash tests/push.sh       # push-mode ref enforcement
bash tests/install.sh    # installer --force + invalid-config + foreign-hook safety
bash tests/ci.sh         # ci-verify pass/fail + perFile
```

### Limitations

It does **not** replace human judgment or CI, prevent a determined local bypass,
guarantee the review was thoughtful, sandbox AI tools, or secure secrets. It **does**
make accidental review skips hard, force verify to run, bind approval to the exact
change, invalidate approval when the change changes, and give AI-assisted workflows a
safer default.

### Credits

- `review-gate` — created by **Fouda**, MIT licensed.
- Guard skills (`clean-code-guard`, `test-guard`, `docs-guard`) are by
  **Ahmed Nagdy** ([@amElnagdy](https://github.com/amElnagdy/guard-skills)), MIT
  licensed, vendored with their license preserved. See `NOTICE`.

---

## العربية

### ليه الأداة دي موجودة؟

أدوات الـ AI coding بقت سريعة جدًا، ساعات أسرع من اللازم — ممكن الـ agent يعدّل ملفات،
يشغّل check بسيط، ويعمل commit أو push قبل ما يحصل review حقيقي. `review-gate` بتحط قاعدة
بسيطة عند باب Git:

> مفيش commit أو push يعدّي غير لما يحصل review ويتشغّل verify على نفس التغيير بالظبط.

### تجربة في ٦٠ ثانية

```bash
git add -A
git commit -m "change"
# 🔒 اتبلوك: مفيش attest جديد للتغيير ده

bash .review-gate/review-gate.sh attest --ran review,clean-code
git commit -m "change"
# ✅ عدّى
```

لو غيّرت الكود بعد الـ attest، الـ marker يبقى قديم والـ commit اللي بعده يتبلوك تاني —
الموافقة مربوطة بنفس التغيير، مش بـ"أنا شغّلته مرة".

### بتعمل إيه؟

`review-gate` بتركّب Git hooks تمنع `git commit` (في **commit mode**) أو `git push` (في
**push mode**). قبل ما العملية تعدّي، تشغّل:

```bash
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
```

وبعدها: (1) تحسب خطوات المراجعة المطلوبة حسب الملفات المتغيرة، (2) تتأكد إن `--ran`
يغطّيها، (3) تشغّل verify (typecheck/lint/test)، (4) تكتب marker محلي مربوط بنفس التغيير،
(5) تسمح للعملية بس لو التغيير لسه مطابق للـ marker.

### مهم: بوابة ذمة، مش sandbox

`review-gate` هي **honesty gate**، مش security sandbox. بتمنع النسيان والأخطاء العادية
(الـ agent نسي يراجع / commit قبل tests / غيّرت staged بعد review / attest لفرع ودفعت فرع).
لكنها **لا** تمنع شخص مصمم يتخطّى الـ hooks المحلية — `--no-verify` بيتخطّى الـ hooks
بالكامل ومفيش hook محلي يمنع ده. للفرض الصلب، خلّي الـ CI companion **required check**.

### الوضعين

الوضع في `.review-gate/gate.config.json` عبر `"gateMode": "commit"` أو `"push"`.

| الوضع    | بيمنع        | الـ marker مربوط بـ      | مناسب لـ                                     |
| -------- | ------------ | ------------------------ | -------------------------------------------- |
| `commit` | `git commit` | staged tree              | شغل محلي / solo / repos مش دايمًا بتعمل push |
| `push`   | `git push`   | HEAD commit / pushed ref | فرق / PRs / شغل على remote                   |

**commit mode** — مربوط بالـ staged tree:

```bash
git add -A
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
git commit -m "your message"
```

بيمنع الـ attest لو فيه unstaged tracked changes أو untracked files مش ignored.

**push mode** — مربوط بالـ commit اللي هيتدفع:

```bash
git commit -m "your message"
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
git push
```

الـ pre-push hook بيتحقق من الـ refs اللي Git بيدفعها فعلًا، مش بس HEAD. (`gh pr create`
مش Git hook عام؛ تكامل Claude بيمنعه، بس للفرض المضمون على مستوى PR استخدم CI.) في push
mode الـ attest بيعمل `git fetch` best-effort بـ timeout عشان يحسب الـ base على الـ remote
بتاعك — وبيشتغل offline برضه (بيرجع للـ base المحلي).

### التثبيت السريع

```bash
bash install.sh /path/to/your-repo
```

**بتسأل، مش بتخمّن.** من غير flags في تيرمنال، بتكتشف مشروعك وبعدين **بتسألك تأكّد**:

- **الوضع** — `commit` ولا `push` (اقتراح من وجود remote)،
- **الأدوات** — اكتشاف من `.cursor/`/`CLAUDE.md`/`AGENTS.md`/`.windsurfrules` ("الكل" لو مفيش)،
- **verify preset** — node / python / go / minimal (اكتشاف من ملفات المشروع).

تتخطّى بالـ flags، أو `--yes` تاخد المكتشف (CI مابيسألش، فمايعلّقش):

```bash
bash install.sh /path/to/your-repo --mode push --tools claude,cursor
bash install.sh /path/to/your-repo --yes
```

القيم المدعومة: `claude,codex,cursor,windsurf`. ولو **أجنت AI** بيركّبها، بيسألك نفس
الاختيارات **بلغتك** ويقترح أوامر الـ verify من مشروعك — شوف **[`SETUP.md`](SETUP.md)**.

### الـ installer بيضيف إيه؟

```text
.review-gate/  (review-gate.sh, gate.config.json, GATE.md, agents/, skills/, setup.sh)
.githooks/     (pre-commit, pre-push)
```

وكمان: يضبط `core.hooksPath` على `.githooks` (لو آمن)، يركّب ملفات تعليمات الـ AI، يضيف
`.review-gate/.gate/` للـ `.gitignore`، ويثبّت الـ scripts/hooks على LF.

**الـ hooks بتاعتك آمنة.** لو الريبو بيستخدم Husky أو hook manager تاني، review-gate
**مش بتلمس** `core.hooksPath` بتاعك وبتطبعلك أوامر الربط اليدوي. ولو فيه
`.githooks/pre-commit`/`pre-push` مش بتاع review-gate، الـ installer **بيسيبه زي ما هو**
وبيطبعلك إزاي تربط review-gate فيه (استخدم `--force` للاستبدال) — عمره ما بيدوس على الـ
hooks بتاعتك بصمت.

### بعد التثبيت

1. عدّل `.review-gate/gate.config.json` وظبط أوامر الـ verify حسب مشروعك.
2. اعمل commit لملفات review-gate. أول commit نفسه gated — اعمل review + attest قبله.
3. أي حد بيعمل clone يشغّل مرة واحدة: `bash .review-gate/setup.sh` (الـ git hooks محلية لكل clone).

### ظبط verify

الـ installer بيملّأ preset حسب الـ stack المكتشف، وانت تعدّله. مثال Python:

```json
{
  "gateMode": "commit",
  "verify": {
    "typecheck": { "cmd": "python -m mypy .",      "perFile": false, "enabled": true },
    "lint":      { "cmd": "python -m ruff check",  "perFile": true,  "enabled": true },
    "test":      { "cmd": "python -m pytest -q",   "perFile": false, "enabled": true }
  },
  "lintableExtensions": ["py"],
  "codeExtensions": ["py"]
}
```

`perFile: true` بتضيف الملفات المتغيرة كـ arguments آمنة (مثلًا
`python -m ruff check changed_1.py changed_2.py`). `perFile: false` تشغّل الأمر مرة واحدة
على المشروع كله. لو شلت `verify` بالكامل تستخدم Node defaults؛ لو خطوة ناقصة تبقى
**disabled** مش بترجع لـ Node. أمثلة: `gate/examples/{python,go,minimal}.gate.config.json`.

### خطوات المراجعة

`--ran` لازم يحتوي `review`. وفيه guard steps إضافية حسب الملفات: `clean-code` (production
code)، `test` (test files)، `docs` (docs/markdown).

```bash
bash .review-gate/review-gate.sh attest --ran review,clean-code,docs
```

لو خطوة مطلوبة ناقصة، `attest` بيرفض يكتب الـ marker.

### Fail-closed

الأداة بتقفل لو: `gate.config.json` مش موجود / JSON بايظ / `gateMode` غلط؛ الـ marker مش
موجود / corrupt / لوضع مختلف؛ الـ staged tree اتغيرت بعد attest (commit)؛ HEAD أو الـ
pushed ref اتغير بعد attest (push)؛ فيه untracked مش ignored أو unstaged tracked وقت
attest؛ أو verify فشل. الملفات الـ ignored لا تمنع attest.

### CI

ضيف الـ workflow (`integrations/ci/github-actions.yml`) وخلّيه required. بيشغّل
`bash .review-gate/review-gate.sh ci-verify` اللي بيعيد **نفس** الـ verify المحلي (بيحترم
`perFile`). الـ CI مش هيثبت إن المراجعة الفكرية حصلت، لكنه يفرض الـ verify على كل PR —
مهما حصل `--no-verify` محلي.

> **برضه honesty مش قفل صلب.** الـ CI بيشغّل البوابة + الإعداد من محتوى الـ PR نفسه، فصاحب
> الـ PR يقدر يضعّف `gate.config.json` أو البوابة ويخلّي الـ check أخضر. لقفل حقيقي، احمِ
> `.review-gate/**` بمراجعة إلزامية (CODEOWNERS)، أو شغّل البوابة + الإعداد من الـ base branch.

### المتطلبات

- `bash` و`git` وPython 3 كـ `python3` أو `python`. لو بيئتك فيها python غريب، حدّد واحد:
  `REVIEW_GATE_PYTHON=/usr/bin/python3 bash .review-gate/review-gate.sh attest --ran review,clean-code`
- على Windows استخدم Git Bash. الـ scripts/hooks مثبتة على LF. لو مفيش Python، الأداة تفشل
  مقفولة. GNU `timeout` بيستخدم لو موجود، ولو مفيش الأداة تكمل عادي (macOS الافتراضي).

### الخصوصية

`review-gate` **لا تجمع** أي telemetry. مابتبعتش الكود ولا أسماء الملفات ولا الـ diffs ولا
الأوامر ولا أي metadata لأي مكان. كله بيشتغل محليًا؛ الوصول الوحيد للنت هو `git fetch`
بتاعك (في push mode، best-effort) عشان يحسب base على الـ remote **بتاعك**.

### الاختبارات

```bash
bash tests/run.sh    # الـ suite الكامل
bash tests/{verify,smoke,push,install,ci}.sh   # كل واحد لوحده
```

### الحدود

**لا** تستبدل حكم المبرمج ولا CI، ولا تمنع تخطّي محلي مصمم، ولا تضمن إن المراجعة كانت
بعمق، ولا تعمل sandbox للـ AI، ولا تحمي secrets. **لكنها** تصعّب نسيان الـ review، تجبر الـ
verify يشتغل، تربط الموافقة بنفس التغيير، تلغيها لو التغيير اتغير، وتدّي workflows الـ AI
default أأمن.

### الحقوق

- `review-gate` — من تنفيذ **Fouda**، ترخيص MIT.
- الـ guard skills (`clean-code-guard`, `test-guard`, `docs-guard`) من عمل **Ahmed Nagdy**
  ([@amElnagdy](https://github.com/amElnagdy/guard-skills))، ترخيص MIT، مضافة مع الحفاظ على
  الترخيص. راجع `NOTICE`.
