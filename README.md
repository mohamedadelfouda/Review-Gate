# review-gate

> A tool-agnostic **review + verify gate** for git repositories.
> It blocks a `git commit` (or `git push`) until a mandatory code review and a
> configured verify step have run for the exact change.
>
> Created by **Fouda** · MIT licensed · works with the terminal, **Claude Code**,
> **OpenAI Codex**, **Cursor**, **Windsurf**, and any tool that runs git.

**🇬🇧 [English](#english) · 🇪🇬 [العربية](#العربية)**

---

## English

### What it is

`review-gate` makes "review before it lands" non-optional. It installs a native
**git hook** that refuses to let a commit (or push) through until:

1. the change has been **reviewed** (by review agents + guard-skill checklists), and
2. a **verify** step (your typecheck + lint + test) has passed for that exact change.

Because the enforcement is a **git hook**, it works for *any* actor that runs
git — the terminal, a human, Claude Code, Codex, Cursor, Windsurf — not just one
AI tool. Each AI tool additionally gets a small instruction file so it runs the
review *proactively*.

It is an **honesty gate, not a sandbox.** It makes the *accidental* skip
("the agent forgot to review") impossible. A determined caller can still bypass
it (`git commit --no-verify`, or by editing the config). For un-bypassable
enforcement, pair it with a CI check.

### How it works

Two commands inside `.review-gate/review-gate.sh`:

- **`attest --ran <steps>`** — you run this *after* reviewing. It computes which
  review/guard steps the diff **requires** (from the changed files) and refuses to
  record approval unless your `--ran` covers them. Then it runs the configured
  **verify** and writes a marker bound to the exact change.
- the **git hook** (`pre-commit` / `pre-push`) — runs automatically and **blocks**
  the action unless a fresh, passing marker matches the current change.

Any change to what you're committing invalidates the marker, so the gate always
re-runs on the latest content.

### Two modes

Set per-repo in `.review-gate/gate.config.json` → `"gateMode"`:

| Mode | Fires on | Marker binds to | Use for |
|------|----------|-----------------|---------|
| `commit` | `git commit` | the **staged tree** | local-only repos that never push |
| `push` | `git push` | the **HEAD commit** | repos that push to a remote / open PRs |

> The git hook enforces **`git push`** for every actor (terminal / human / any
> tool). `gh pr create` is additionally blocked by the **Claude** integration
> only — for guaranteed PR-level enforcement, add the CI check (below).

### Install

```bash
# clone the kit somewhere, then point it at your repo:
bash install.sh /path/to/your-repo --mode commit          # local-only project
bash install.sh /path/to/your-repo --mode push            # push/PR-based project
bash install.sh /path/to/your-repo --tools claude,cursor  # narrow the AI tools (default: all)
```

The installer adds `.review-gate/` (gate + agents + guard-skills + config),
installs the git hooks (`.githooks/` + `core.hooksPath`), wires each selected AI
tool, and git-ignores the machine-local marker. Then:

1. Edit `.review-gate/gate.config.json` so the verify commands match your stack.
2. Commit the review-gate files (the **first** commit is gated too — review + attest it).
3. Each person who clones the repo runs **once**: `git config core.hooksPath .githooks`.

### Tool coverage

| Actor | How it's enforced | How it's told to review |
|-------|-------------------|--------------------------|
| Terminal / human / any tool | `pre-commit` / `pre-push` git hook | — (you follow `GATE.md`) |
| Claude Code | git hook + PreToolUse hook | `CLAUDE.md` + `.claude/agents` + `.claude/skills` (parallel subagents) |
| OpenAI Codex (& others) | git hook | `AGENTS.md` |
| Cursor | git hook | `.cursor/rules/review-gate.mdc` |
| Windsurf | git hook | `.windsurfrules` |

Tools that can't spawn subagents apply the agents/guard-skills as **checklists**
in a single pass — the enforcement is identical; only the review depth varies.

### Configure verify (any language)

`.review-gate/gate.config.json` declares three commands. Omitting `verify`
defaults to the Node trio (`tsc` + `eslint` + `vitest`).

```json
{
  "gateMode": "commit",
  "verify": {
    "typecheck": { "cmd": "python -m mypy .",    "perFile": false, "enabled": true },
    "lint":      { "cmd": "python -m ruff check", "perFile": true,  "enabled": true },
    "test":      { "cmd": "python -m pytest -q",  "perFile": false, "enabled": true }
  },
  "lintableExtensions": ["py"],
  "codeExtensions": ["py"]
}
```

- `perFile: true` appends the changed files (matching `lintableExtensions`) as args.
- `perFile: false` runs the command once for the whole project.
- `enabled: false` skips that step (no failure). A project with no tests/linter
  still gets the **review** enforcement.

Ready-made examples: [`gate/examples/`](gate/examples/) (python, go, minimal).

### The honesty-gate caveat (read this)

- The **verify** (typecheck/lint/test) is genuinely run and enforced.
- The **review acknowledgment** (`--ran review`) is trusted — the gate can't force
  the thinking to happen, only make the *accidental* skip impossible.
- The git hook can be bypassed with `--no-verify`. That's by design (escape hatch).
- For **hard** enforcement that nobody can bypass, add a CI job that re-runs verify
  on the pull request — ready-made template:
  [`integrations/ci/github-actions.yml`](integrations/ci/github-actions.yml).

### Requirements

`bash`, `git`, and Python 3 on `PATH` as `python3` or `python` (used for JSON +
safe arg parsing). On Windows, run via Git Bash.

### Credits & license

- **review-gate** — created by **Fouda**, MIT licensed (see [`LICENSE`](LICENSE)).
- **Guard skills** (`clean-code-guard`, `test-guard`, `docs-guard`) — by
  **Ahmed Nagdy** ([@amElnagdy](https://github.com/amElnagdy/guard-skills)), MIT,
  vendored unmodified with their license preserved (see [`NOTICE`](NOTICE)).

---

## العربية

### إيه هي

`review-gate` بتخلّي "المراجعة قبل ما الكود يعدّي" حاجة **إجبارية**. بتركّب **git
hook** بيرفض يعدّي أي `commit` (أو `push`) لحد ما:

1. التغيير يتـ **راجع** (بمراجعين + checklists بتاعة guard-skills)، و
2. خطوة **verify** (الـ typecheck + lint + test بتوعك) تنجح على نفس التغيير بالظبط.

عشان الفرض **git hook**، بيشتغل لأي حاجة بتشغّل git — التيرمنال، إنسان، Claude
Code، Codex، Cursor، Windsurf — مش أداة واحدة بس. وكل أداة AI بتاخد كمان ملف
تعليمات صغير عشان تعمل المراجعة من نفسها.

دي **بوابة على الذمة، مش صندوق مغلق.** بتخلّي النسيان (إن الـ agent ينسى يراجع)
**مستحيل**. أي حد مصمم يعدّيها يقدر (`git commit --no-verify` أو يعدّل الإعداد).
للفرض اللي ماينفعش يتعدّى، ضيف معاها CI check.

### بتشتغل إزاي

أمرين جوّه `.review-gate/review-gate.sh`:

- **`attest --ran <steps>`** — بتشغّلها **بعد** المراجعة. بتحسب الـ steps المطلوبة
  للتغيير (من الملفات المتغيّرة) وبترفض تسجّل الموافقة إلا لو الـ `--ran` بتاعك
  مغطّيها. وبعدين بتشغّل الـ **verify** وبتكتب marker مربوط بالتغيير بالظبط.
- الـ **git hook** (`pre-commit` / `pre-push`) — بيشتغل أوتوماتيك و**يبلوك** الإجراء
  إلا لو فيه marker جديد وناجح بيطابق التغيير الحالي.

أي تعديل في اللي بتعمله commit بيلغي الـ marker، فالبوابة دايمًا بتعيد على آخر محتوى.

### الوضعين

بيتحدد لكل ريبو في `.review-gate/gate.config.json` → `"gateMode"`:

| الوضع | بيشتغل عند | الـ marker مربوط بـ | يُستخدم لـ |
|------|------------|---------------------|-----------|
| `commit` | `git commit` | **الشجرة المجهّزة (staged)** | مشاريع محلية مش بتعمل push |
| `push` | `git push` | **HEAD commit** | مشاريع بتعمل push / PRs |

> الـ git hook بيفرض **`git push`** لأي مُنفِّذ (تيرمنال / إنسان / أي أداة). أما
> `gh pr create` فبيتمنع من تكامل **Claude** بس — لفرض مضمون على مستوى الـ PR ضيف
> الـ CI check (تحت).

### التثبيت

```bash
bash install.sh /path/to/your-repo --mode commit          # مشروع محلي بحت
bash install.sh /path/to/your-repo --mode push            # مشروع بيعمل push/PR
bash install.sh /path/to/your-repo --tools claude,cursor  # تحديد أدوات AI (الافتراضي: الكل)
```

الـ installer بيضيف `.review-gate/` (البوابة + الأجنتس + الـ guard-skills +
الإعداد)، بيركّب الـ git hooks، بيوصّل كل أداة مختارة، وبيعمل gitignore للـ marker.
بعد كده:

1. عدّل `.review-gate/gate.config.json` بحيث أوامر الـ verify تطابق مشروعك.
2. اعمل commit لملفات review-gate (أول commit بيتفرض عليه برضه — راجعه واعمله attest).
3. أي حد بيعمل clone للريبو يشغّل **مرة واحدة**: `git config core.hooksPath .githooks`.

### تغطية الأدوات

| المُنفِّذ | الفرض إزاي | بيتقال يراجع إزاي |
|----------|-----------|-------------------|
| تيرمنال / إنسان / أي أداة | `pre-commit` / `pre-push` git hook | — (تمشي على `GATE.md`) |
| Claude Code | git hook + PreToolUse hook | `CLAUDE.md` + `.claude/agents` + `.claude/skills` (subagents بالتوازي) |
| OpenAI Codex (وغيره) | git hook | `AGENTS.md` |
| Cursor | git hook | `.cursor/rules/review-gate.mdc` |
| Windsurf | git hook | `.windsurfrules` |

الأدوات اللي مابتعملش subagents بتطبّق الأجنتس/الـ guard-skills كـ **checklists** في
مرور واحد — الفرض واحد، بس عمق المراجعة بيختلف.

### ظبط الـ verify (أي لغة)

`.review-gate/gate.config.json` بيحدّد 3 أوامر. لو شِلت `verify` بيرجع لافتراضي Node
(`tsc` + `eslint` + `vitest`). (شوف المثال الإنجليزي فوق.)

- `perFile: true` بيضيف الملفات المتغيّرة كـ args.
- `perFile: false` بيشغّل الأمر مرة واحدة على المشروع كله.
- `enabled: false` بيسكِّب الخطوة (من غير فشل). مشروع من غير tests/linter لسه بياخد
  فرض **المراجعة**.

أمثلة جاهزة: [`gate/examples/`](gate/examples/) (python / go / minimal).

### تنبيه "بوابة الذمة" (اقراه)

- الـ **verify** (typecheck/lint/test) بيتشغّل فعلًا ومفروض.
- **إقرار المراجعة** (`--ran review`) على الذمة — البوابة ماتقدرش تجبر التفكير يحصل،
  بس تخلّي النسيان مستحيل.
- الـ git hook بيتعدّى بـ `--no-verify` (ده مخرج مقصود).
- للفرض **الصلب** اللي محدش يقدر يعدّيه، ضيف CI job يعيد الـ verify على الـ PR —
  قالب جاهز: [`integrations/ci/github-actions.yml`](integrations/ci/github-actions.yml).

### المتطلبات

`bash` و`git` وPython 3 على الـ `PATH` كـ `python3` أو `python`. على ويندوز شغّلها عبر Git Bash.

### الحقوق والترخيص

- **review-gate** — من تنفيذ **Fouda**، ترخيص MIT (شوف [`LICENSE`](LICENSE)).
- **الـ Guard skills** (`clean-code-guard`، `test-guard`، `docs-guard`) — من عمل
  **Ahmed Nagdy** ([@amElnagdy](https://github.com/amElnagdy/guard-skills))، ترخيص
  MIT، متضمّنة من غير تعديل مع الحفاظ على ترخيصها (شوف [`NOTICE`](NOTICE)).
