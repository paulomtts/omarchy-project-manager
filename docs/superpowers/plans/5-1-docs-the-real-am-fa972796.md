# 5.1 Docs: the real am shapes, the fixtures and the schema footer — design

Card `fa972796`, subtask of story `0bd845c8`. Parent design:
`docs/superpowers/specs/2026-10-05-align-run-model-design.md` (below: "parent"),
work item 5 "Docs, written from the implementation" (parent l.331).

## Goal

`docs/architecture.md` and `tests/helpers/README.md` describe what the code on
this branch does after milestone "Align the run model with real am" (cards
1.x-4.5): the normalized run shape, the logs argv with the project root, the
watch hello and `amSchema`/`amVersion`, the footer, both cancel spellings, the
committed am fixtures, the rule for using them, and the fixture contract test
with its live check. Docs only: no code, test or fixture changes.

## Inherited constraints

- Docs state only what the code does; no narrative, no card or milestone
  references in new text (card description; parent l.331 "written from the
  implementation").
- The normalized shape's existing keys keep their meaning; `rows` stay per
  attempt (parent l.306-309, decision 3 l.155-159).
- Synthetic stories `integrate` and `bases` stay in `tree.stories`, never in
  `tree.subtasks`; resolver rows under a synthetic story whose subtask id is a
  real card id are dropped, `base-*` rows kept (parent decision 2, l.148-154).
- Fixture rule, loading and contract wording come from parent l.257-284.
- Both spellings and schemas from parent l.286-304.
- `docs/architecture.md` layering and `tests/architecture` (duplicate
  components, icon glyph rules) must keep passing; prose edits cannot affect
  them (`tests/architecture/test_layers.py`, `test_icon_glyphs.py` read no
  docs).

## Source of truth (read before writing; cite nothing else)

| fact | code |
|---|---|
| normalized shape, scalar precedence, synthetic stories, rows renamed, resolver rows dropped | `core/domain/runs.js:4-37` (doc comment), `:38-140` |
| `runState` / `glyphStateOf`: `canceled` = `cancelled`; `ok` → done; `gate_failed`, `schema_invalid`, `harness_error` → dead | `runs.js:146-158`, `:541-552` |
| escalation fallback names a failure only | `runs.js:337-345` |
| `TERMINAL` holds `cancelled` and `canceled` | `core/backend/runs/runs-snapshot.py:1-20`, `:34` |
| hello schema 1 or 2 accepted, forwarded once as `{"hello":{"schema":N,"am":"<version>"}}` (`""` when not a string); other schema → `SchemaMismatch`; backlog dropped | `core/backend/runs/runs-watch.py:1-27` |
| logs argv: project root first, `--repo-dir` | `core/backend/runs/runs-logs.py:1-10`, `:44-48`; `core/stores/RunStore.qml:386-395` |
| `amSchema` (int, 0 unknown) / `amVersion` (string, `""` unknown): set from hello, schema an integer ≥ 1 else 0, am a string else `""`; reset when a watch starts, stops or exits | `RunStore.qml:31-32`, `:215-275` |
| footer: `am` + ` <version>` when `amSchema > 0` and version non-empty, + ` · schema N` when `amSchema > 0`, + ` · watching`/` · not watching`; `lastError` when `amStatus` is `error`; flash text wins | `ui/screens/RunsScreen.qml:145-156` |
| fixtures: 9 files | `tests/fixtures/am/` |
| QML loader | `tests/helpers/amFixtures.js`, `tests/helpers/tst_am_fixtures.qml` |
| `QML_XHR_ALLOW_FILE_READ=1` | `tests/run.sh:28` |
| fixture contract + live check | `tests/contract/test_am_fixtures.py:1-14`, `:52-66`, `:293-345` |
| `test_am_shapes.py`: hand-written schema-1 journals; hello schema accepted as 1 or 2 | `tests/contract/test_am_shapes.py:1-8`, `:159` |

If any line above disagrees with what the implementer reads in the file, the
file wins and the doc says what the file says.

## Required edits (observable result: the text of two files)

### `docs/architecture.md`

1. **RunStore paragraph (l.83-91).** Add one sentence: `amSchema` (journal
   schema from the current watch's hello; `0` = unknown) and `amVersion` (am's
   version from it; `""` = unknown), set from the watch's
   `{"hello": {"schema": N, "am": V}}` line (an integer of 1 or more, else 0; a
   string, else `""`), back to unknown when a watch starts, stops or exits.
2. **Run detail logs paragraph (l.94).** Say `logsRunner` runs `runs-logs.py`
   with the project root first, then run, card, phase and attempt.
3. **RunsScreen paragraph (l.169).** Replace the hardcoded `am · schema 1 ·
   watching` with the real rule: `am <version> · schema N · watching` (or `not
   watching`) while a hello is known; without one `am · watching` / `am · not
   watching`; the version is shown only with a known schema. Keep the existing
   `lastError` / hidden-when wording.
4. **runs.js paragraph (l.184).** Add the normalized shape after
   `normalizeRun`: scalars (`id, repo_dir, started_at, base_branch,
   branch_prefix, workflow` prefer the `am runs` row; `status, milestone_id`
   prefer the `am status` run); `lease`, `requests`; `tree.stories` every story
   in am's order including the synthetic `integrate` and `bases`, each with
   `subtasks` as card-id strings; `tree.subtasks` the subtasks of real stories
   only, flattened in am's order, each with `story_id`; `rows` one per am row
   (per attempt; a phase without attempts has one row with `attempt` null) as
   `{story_id, card_id, phase, attempt, status}` renamed from am's `story,
   subtask, phase, attempt, state`, with an Integrate resolver's rows (synthetic
   story, real card id) dropped; copies, never am's objects. In the State part,
   say `runState` and `glyphStateOf` read both `cancelled` and `canceled` as
   `cancelled`, and `glyphStateOf` maps attempt outcomes (`ok` → done;
   `gate_failed`, `schema_invalid`, `harness_error` → dead). If
   `escalationReason` is described, say it first reads a failed phase's detail
   (else `escalated at <phase>`), and that when no phase of the tree failed its
   fallback names the phase of the last failing row (`failed, escalated,
   gate_failed, schema_invalid, harness_error`) as `escalated at <phase>`, else
   `escalated` (`runs.js:343-367`).
5. **Backend paragraph (l.199).** `runs-snapshot.py`: terminal includes both
   `cancelled` and `canceled`. `runs-watch.py`: replace "checks that the hello
   line's schema is 1" with: accepts a hello of schema 1 or 2 (anything else is
   `SchemaMismatch`) and forwards the first one as `{"hello": {"schema": N,
   "am": "<version>"}}`. Also add this line to the list of things it prints.
   Keep the `runs-logs.py` argv (already correct).
6. **Tests section (l.221-234).** Add:
   - `tests/fixtures/am/`: real captured am payloads (`runs.json`, five
     `status-*.json`, `watch-events.json`, `watch-hello.json`,
     `logs-attempt.json`); keys starting with `_` are annotations readers
     ignore.
   - The rule: tests of code that reads am output (`normalizeRun`, `logTail`,
     the `runs-*` helpers, `run-control.py`, `RunStore`'s snapshot, logs and
     watch handling) build their input from these fixtures; a hand-written am
     payload only for a synthetic edge case, marked with a `synthetic:`
     comment; tests of code that takes a normalized run may build it by hand;
     edits to a fixture inside a test are made on a fresh copy. Python reads
     them with `json.load`, QML with `tests/helpers/amFixtures.js` (see
     `tests/helpers/README.md`).
   - `test_am_fixtures.py`: pins each level's exact key set, the status
     vocabularies and the absence of a top-level `subtasks` in status data;
     its live check runs `am runs` and `am status <newest>` in the main
     checkout (the parent of git's common dir) read-only with only
     `--repo-dir`, expects the same key sets with `story_id` allowed as the one
     extra key on a runs row and on the status run, and is skipped when `am` or
     `git` is absent or the checkout has no runs.
   - Fix the `test_am_shapes.py` bullet if it claims the hello must be schema
     1 (the test accepts 1 or 2; its journals are hand-written schema 1).

Wording follows the file's style: dense single-paragraph bullets, backticked
identifiers, no headings added inside existing sections.

### `tests/helpers/README.md`

Already documents `amFixtures.js` (`load(name)`, fresh parse, `Error` naming
the file, `QML_XHR_ALLOW_FILE_READ=1` set by `tests/run.sh`, import line).
Check each claim against `amFixtures.js` and `tst_am_fixtures.qml`; correct only
what disagrees. Add one sentence pointing to the rule in
`docs/architecture.md`'s Tests section (which tests must load fixtures).
Nothing else.

## Error paths

None at runtime: no code changes. The failure modes are documentary:
- a stale claim survives (the `schema is 1` sentence, `am · schema 1`);
- a new claim contradicts the code (e.g. saying synthetic subtasks appear in
  `tree.subtasks`, or the version shows without a schema).
Both are caught by the review greps below, not by the suite.

## Tests

No automated test is added: the card's deliverable is prose, and a test that
greps documentation for phrases would pin wording, not behavior (rejected:
brittle and outside the repo's test tiers; `tests/architecture` reads no docs).
TDD for this card reduces to:

| check | tier | why |
|---|---|---|
| `bash tests/run.sh` green before and after | full suite (pytest incl. `tests/architecture` and `tests/contract`, then every `tst_*.qml`) | card's stated verification; proves nothing outside the two docs changed behaviour |
| `grep -n "schema is 1\|am · schema 1" docs/architecture.md` prints nothing | manual review step | the two known stale claims are gone |
| `grep -n "amSchema\|amVersion\|story_id\|tests/fixtures/am\|test_am_fixtures\|canceled" docs/architecture.md` hits the RunStore, runs.js, backend and Tests paragraphs | manual review step | every required edit landed |
| `git diff --stat main...HEAD` after the change lists only `docs/architecture.md`, `tests/helpers/README.md` (plus spec/plan) | manual review step | scope held |
| each new sentence traced to a row of the Source-of-truth table | reviewer read | "state only what the code does" |

## Out of scope

- Any code, test or fixture change, including `test_am_shapes.py`'s own
  docstring.
- Docs for the open questions (parent l.333-343): progress counting vs am's,
  Integrate escalation reasons, resolver attempts in Run detail,
  `--from-now`.
- Other docs (README.md, other specs/plans) and sibling stories' docs
  (e.g. the runs-monitor docs card `task-5-4`).
- Restructuring `docs/architecture.md` beyond the paragraphs named above.

---

# 5.1 Docs: the real am shapes, the fixtures and the schema footer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/architecture.md` and `tests/helpers/README.md` say what the code on this branch does about the normalized run shape, the logs argv, the watch hello / `amSchema` / `amVersion`, the Runs footer, both cancel spellings, the committed am fixtures and the fixture contract test.

**Architecture:** Prose-only edits to two Markdown files. Each task replaces exact sentences (found with `Edit`'s exact-string match, never by line number, because earlier tasks shift lines). "RED" for a docs task is a grep that shows the stale claim present / the new claim absent; "GREEN" is the same grep after the edit; the full suite runs at the end of every task to prove nothing else changed.

**Tech Stack:** Markdown; verification with `grep`, `git diff`, `bash tests/run.sh` (pytest, then every `tst_*.qml` through qmltestrunner).

**Spec:** `docs/superpowers/specs/5-1-docs-the-real-am-fa972796.md` (prepended above). Parent: `docs/superpowers/specs/2026-10-05-align-run-model-design.md`.

## Global Constraints

- Docs only: no code, test or fixture change (not even `test_am_shapes.py`'s docstring).
- Docs state only what the code does; no narrative, no card or milestone references (no `S2 4.1`-style tags, no card ids) in new text.
- Wording follows the file's style: dense single-paragraph bullets, backticked identifiers, no headings added inside existing sections.
- `docs/architecture.md` is not restructured beyond the paragraphs named in the spec.
- If the code disagrees with this plan's wording, the code wins: re-read the cited lines and write what they say.
- Scope check: the branch is stacked on earlier cards, so `git diff --stat main...HEAD` lists the whole milestone. Compare against this card's starting commit instead: `git diff --stat ed8be4f` must list only `docs/architecture.md`, `tests/helpers/README.md` and the spec/plan files.

## Review Focus

1. **Footer without a version** — a hello whose `am` is not a string gives `am · schema N · watching`; the doc must not claim the version always shows with the schema (Task 1 states this case explicitly; checked by the Task 1 grep for `schema N · …`).
2. **Synthetic stories** — `integrate` / `bases` appear in `tree.stories` but never in `tree.subtasks`; a doc that lists them under `tree.subtasks` would mislead a reader writing a `runTree` change (Task 2 wording plus its reviewer-read step against `runs.js:27-32`).
3. **`attempt` null** — `rows[].attempt` is `null` whenever am's value is not a finite number, not only "for a phase without attempts"; the doc says the code's rule (Task 2).
4. **Terminal set in the snapshot** — `stopped` is terminal for `runs-snapshot.py` though `runState` calls it parked; the doc lists the snapshot's five terminal statuses verbatim from `TERMINAL` (Task 2).
5. **Fixture underscore keys** — `amFixtures.js` keeps `_`-keys (its test `test_underscore_keys_are_kept`); the doc says readers *ignore* them, not that the loader strips them (Task 3 README check).

---

### Task 1: RunStore hello, logs argv and the Runs footer in `docs/architecture.md`

**Files:**
- Modify: `docs/architecture.md` — RunStore bullet (~l.83-91), Run detail logs line (~l.94), RunsScreen paragraph (~l.169)
- Read (source of truth): `core/stores/RunStore.qml:31-32`, `:211-275`, `:386-395`; `ui/screens/RunsScreen.qml:145-156`

**Interfaces:**
- Consumes: nothing.
- Produces: the doc's names `amSchema`, `amVersion`, the hello line `{"hello": {"schema": N, "am": V}}` — Task 2's backend sentence uses the same hello spelling.

- [ ] **Step 1: Baseline — the suite is green before any edit**

Run: `bash tests/run.sh 2>&1 | tail -20`
Expected: pytest summary with no failures, and every QML `Totals:` line with `0 failed`. If anything fails before you edit, stop and report it — it is not this card's doing.

- [ ] **Step 2: RED — show the stale footer claim and the missing names**

Run:
```bash
grep -n "am · schema 1" docs/architecture.md
grep -c "amSchema\|amVersion" docs/architecture.md
grep -n "runs-logs.py\` with the project root first" docs/architecture.md
```
Expected: the first prints one line (the RunsScreen paragraph); the second prints `0`; the third prints nothing.

- [ ] **Step 3: Add the hello sentence to the RunStore bullet**

Use `Edit` on `docs/architecture.md`.

old_string:
```
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`).
```
new_string:
```
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`). `amSchema` (the journal schema from the
  current watch's hello; `0` = unknown) and `amVersion` (am's version from it;
  `""` = unknown) are set from the watch's `{"hello": {"schema": N, "am": V}}`
  line -- `N` when it is an integer of 1 or more, else `0`; `V` when it is a
  string, else `""` -- and go back to unknown when a watch starts, stops or
  exits.
```

- [ ] **Step 4: Say the logs argv in the Run detail line**

Use `Edit` on `docs/architecture.md`.

old_string:
```
  Run detail's output pane is a second `HelperRunner`, `logsRunner` (`runs-logs.py`, guarded by the project like the snapshot):
```
new_string:
```
  Run detail's output pane is a second `HelperRunner`, `logsRunner` (`runs-logs.py` with the project root first, then the run, card, phase and attempt; guarded by the project like the snapshot):
```

- [ ] **Step 5: Replace the hardcoded footer with the real rule**

Use `Edit` on `docs/architecture.md`.

old_string:
```
Below it the footer reads `am · schema 1 · watching` (or `not watching`), shows `lastError` instead when `amStatus` is `error`, and is hidden when am is missing or the schema banner shows.
```
new_string:
```
Below it the footer reads `am <version> · schema N · watching` (or `not watching`) while the watch's hello is known (`amVersion`, `amSchema`; `am · schema N · …` when the hello named no version), and `am · watching` / `am · not watching` without one -- the version shows only with a known schema; it shows `lastError` instead when `amStatus` is `error`, and is hidden when am is missing or the schema banner shows.
```

- [ ] **Step 6: GREEN — the stale claim is gone and the new names landed**

Run:
```bash
grep -n "am · schema 1" docs/architecture.md
grep -n "amSchema\|amVersion" docs/architecture.md
grep -n "runs-logs.py\` with the project root first" docs/architecture.md
grep -n "am · schema N · …" docs/architecture.md
```
Expected: the first prints nothing; the second hits the RunStore bullet and the RunsScreen paragraph; the third and fourth print one line each.

- [ ] **Step 7: Reviewer read against the code**

Open `ui/screens/RunsScreen.qml:149-156` and confirm: flash text wins; `lastError` only when `amStatus === "error"` and `lastError !== ""`; version only when `amSchema > 0 && amVersion !== ""`; ` · schema N` when `amSchema > 0`. Open `core/stores/RunStore.qml:213-275` and confirm `forgetHello()` is called from `stopWatch`, `startWatch` and `watchExited`. If any sentence written above disagrees, fix the sentence.

- [ ] **Step 8: Full suite still green**

Run: `bash tests/run.sh 2>&1 | tail -20`
Expected: same result as Step 1 (no failures).

- [ ] **Step 9: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): RunStore's amSchema/amVersion, the logs argv and the Runs footer rule"
```

---

### Task 2: The normalized run shape, run states and the run backend in `docs/architecture.md`

**Files:**
- Modify: `docs/architecture.md` — the `runs.js` domain-helpers paragraph (~l.184), the `core/backend/runs/` paragraph (~l.199)
- Read (source of truth): `core/domain/runs.js:4-140` (doc comment and `normalizeRun`), `:146-158` (`runState`), `:337-367` (`_FAILURE_STATUSES`, `escalationReason`), `:541-552` (`glyphStateOf`); `core/backend/runs/runs-snapshot.py:1-34`; `core/backend/runs/runs-watch.py:1-27`

**Interfaces:**
- Consumes: Task 1's hello spelling `{"hello": {"schema": N, "am": ...}}`.
- Produces: nothing later tasks rely on.

- [ ] **Step 1: RED — show the stale watch claim and the missing shape**

Run:
```bash
grep -n "schema is 1" docs/architecture.md
grep -c "story_id\|canceled\`" docs/architecture.md
grep -n "tree.subtasks" docs/architecture.md
```
Expected: the first prints one line (the backend paragraph); the second prints `0`; the third prints nothing.

- [ ] **Step 2: Add the normalized shape after `normalizeRun`**

Use `Edit` on `docs/architecture.md`.

old_string:
```
Normalizing: `normalizeRun` (an `am runs` row plus its `am status` data). State:
```
new_string:
```
Normalizing: `normalizeRun` (an `am runs` row plus its `am status` data) returns copies, never am's objects: the scalars `id`, `repo_dir`, `started_at`, `base_branch`, `branch_prefix` and `workflow` prefer the `am runs` row, `status` and `milestone_id` the `am status` run; `lease` (`pid`, `host`, `heartbeat_at`, `accepting`, `live`; null when am gave none) and `requests` (`{command, requested_at, handled_at}`, in the order made); `tree.stories`, every story in am's order including the synthetic `integrate` and `bases`, each with `subtasks` as card-id strings; `tree.subtasks`, the subtasks of the real stories only, flattened in am's order, each with `story_id`; and `rows`, one per am row in am's order (am lists one per attempt; `attempt` is null when am's is not a number, as for a phase without attempts) as `{story_id, card_id, phase, attempt, status}` renamed from am's `story`, `subtask`, `phase`, `attempt` and `state`, with an Integrate resolver's rows (a synthetic story with a real card id) dropped. State:
```

- [ ] **Step 3: Both cancel spellings in `runState`**

Use `Edit` on `docs/architecture.md`.

old_string:
```
parked = `stopped`, plus escalated, cancelled and done; anything else is `unknown`)
```
new_string:
```
parked = `stopped`, plus escalated, cancelled (`cancelled` or `canceled`) and done; anything else is `unknown`)
```

- [ ] **Step 4: `glyphStateOf`'s spellings and attempt outcomes**

Use `Edit` on `docs/architecture.md`.

old_string:
```
`glyphStateOf` (an am story, subtask, phase, attempt or row status as a `runGlyphs.js` key).
```
new_string:
```
`glyphStateOf` (an am story, subtask, phase, attempt or row status as a `runGlyphs.js` key: `cancelled` and `canceled` are both cancelled, the attempt outcome `ok` is done, and `gate_failed`, `schema_invalid` and `harness_error` are dead).
```

- [ ] **Step 5: `escalationReason`'s order**

Use `Edit` on `docs/architecture.md`.

old_string:
```
`attention` (escalated or dead: "Needs attention") and `escalationReason`.
```
new_string:
```
`attention` (escalated or dead: "Needs attention") and `escalationReason` (the first failed phase's detail, else its last attempt's detail, else `escalated at <phase>`; with no failed phase, `escalated at <phase>` of the last row whose status is `failed`, `escalated`, `gate_failed`, `schema_invalid` or `harness_error`, else `escalated`).
```

- [ ] **Step 6: The snapshot's terminal set**

Use `Edit` on `docs/architecture.md`.

old_string:
```
then `am status <id> --repo-dir R` for every non-terminal run and the latest 10 terminal ones, and prints
```
new_string:
```
then `am status <id> --repo-dir R` for every non-terminal run and the latest 10 terminal ones (terminal: `done`, `escalated`, `stopped`, `cancelled` or `canceled`), and prints
```

- [ ] **Step 7: The watch's hello**

Use `Edit` on `docs/architecture.md`.

old_string:
```
it runs `am watch --all --follow`, checks that the hello line's schema is 1, drops
```
new_string:
```
it runs `am watch --all --follow`, accepts a hello line of journal schema 1 or 2 (anything else is `SchemaMismatch`) and prints the first one as `{"hello": {"schema": N, "am": "<version>"}}` (`""` when am's version is not a string), drops
```

- [ ] **Step 8: GREEN — the stale claim is gone and every edit landed**

Run:
```bash
grep -n "schema is 1\|am · schema 1" docs/architecture.md
grep -n "tree.subtasks\|story_id" docs/architecture.md
grep -n "canceled\`" docs/architecture.md
grep -n "\"hello\": {\"schema\": N" docs/architecture.md
```
Expected: the first prints nothing; the second hits the `runs.js` paragraph; the third hits the `runs.js` paragraph (both `runState` and `glyphStateOf`) and the backend paragraph; the fourth hits the RunStore bullet (Task 1) and the backend paragraph.

- [ ] **Step 9: Reviewer read against the code**

Check each new clause against its line: scalar precedence `runs.js:127-134`; lease fields and null `:69-79`; requests `:81-87`; stories/subtasks with the synthetic check `:89-109` (synthetic stories go into `stories` with their ids but their subtasks are never pushed to `subtasks`); rows rename, `attempt` null rule and resolver drop `:111-124`; `runState` `:153`; `glyphStateOf` `:541-552`; `escalationReason` `:337-367`; `TERMINAL` `runs-snapshot.py:34`; hello `runs-watch.py:7-20`. Fix any sentence that disagrees.

- [ ] **Step 10: Full suite still green**

Run: `bash tests/run.sh 2>&1 | tail -20`
Expected: no failures, as in Task 1 Step 1.

- [ ] **Step 11: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): the normalized run shape, both cancel spellings and the schema 1-or-2 hello"
```

---

### Task 3: The am fixtures, their rule and the fixture contract test (`docs/architecture.md` Tests, `tests/helpers/README.md`)

**Files:**
- Modify: `docs/architecture.md` — `## Tests` section (~l.221-234)
- Modify: `tests/helpers/README.md` — the `amFixtures.js` paragraph (l.12-18)
- Read (source of truth): `tests/fixtures/am/` (9 files), `tests/helpers/amFixtures.js`, `tests/helpers/tst_am_fixtures.qml`, `tests/run.sh:28`, `tests/contract/test_am_fixtures.py:1-14`, `:52-66`, `:293-345`, `tests/contract/test_am_shapes.py:1-8`, `:159`

**Interfaces:**
- Consumes: nothing.
- Produces: the anchor "`docs/architecture.md`'s Tests section" that the README sentence points to.

- [ ] **Step 1: RED — the fixtures and their test are undocumented**

Run:
```bash
grep -c "tests/fixtures/am\|test_am_fixtures" docs/architecture.md
grep -n "docs/architecture.md" tests/helpers/README.md
ls tests/fixtures/am/
```
Expected: `0`; nothing; the nine files `logs-attempt.json runs.json status-done-integrate.json status-done.json status-escalated-integrate.json status-escalated.json status-started.json watch-events.json watch-hello.json`. If the listing differs, write the doc from the listing.

- [ ] **Step 2: Fix the `test_am_shapes.py` sentence and add the fixture contract test**

Use `Edit` on `docs/architecture.md`.

old_string:
```
  `test_am_shapes.py` does the same for the installed `am`: hand-written schema 1
  journals under a throwaway `XDG_DATA_HOME`, pinning the `am runs`, `am status`
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses;
  skipped when `am` is absent.
```
new_string:
```
  `test_am_shapes.py` does the same for the installed `am`: hand-written schema 1
  journals under a throwaway `XDG_DATA_HOME`, pinning the `am runs`, `am status`
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses,
  with the `--follow` hello's schema accepted as 1 or 2; skipped when `am` is
  absent. `test_am_fixtures.py` pins the committed captures in
  `tests/fixtures/am/`: each level's exact key set, the run and attempt status
  vocabularies, and no top-level `subtasks` in `am status` data. Its live check
  runs `am runs` and `am status <newest>` in the main checkout (the parent of
  git's common dir), read-only with only `--repo-dir`, and expects the same key
  sets, with `story_id` allowed as the one extra key on a runs row and on the
  status run; it is skipped when `am` or `git` is absent or the checkout has no
  runs.
- `tests/fixtures/am/` holds real captured am payloads: `runs.json`, five
  `status-*.json`, `watch-events.json`, `watch-hello.json` and
  `logs-attempt.json`; keys starting with `_` are annotations readers ignore.
  Tests of code that reads am output (`normalizeRun`, `logTail`, the `runs-*`
  helpers, `run-control.py`, `RunStore`'s snapshot, logs and watch handling)
  build their input from these fixtures; a hand-written am payload is used only
  for a synthetic edge case and is marked with a `synthetic:` comment. Tests of
  code that takes a normalized run may build it by hand. A test that edits a
  fixture edits a fresh copy. Python reads them with `json.load`, QML with
  `tests/helpers/amFixtures.js` (see `tests/helpers/README.md`).
```

- [ ] **Step 3: Check each README claim against the loader**

Compare `tests/helpers/README.md:12-18` with `tests/helpers/amFixtures.js` and `tests/helpers/tst_am_fixtures.qml`:
- `.pragma library` with `load(name)` — `amFixtures.js:1`, `:6`.
- fresh parse on every call — `JSON.parse` per call, `test_two_loads_are_distinct`.
- throws an `Error` naming `<name>` on unreadable/unparseable — `amFixtures.js:17`.
- `XMLHttpRequest` needs `QML_XHR_ALLOW_FILE_READ=1`, set by `tests/run.sh` — `run.sh:28`.
- import line `import "../helpers/amFixtures.js" as F` from `tests/<dir>/` — resolves to `tests/helpers/amFixtures.js`.

All five agree as of this plan; correct only a claim that disagrees when you read it. Do not add anything about `_` keys being stripped: the loader keeps them (`test_underscore_keys_are_kept`).

- [ ] **Step 4: Point the README to the rule**

Use `Edit` on `tests/helpers/README.md`.

old_string:
```
`tests/run.sh` sets it. From a test under `tests/<dir>/`:
```
new_string:
```
`tests/run.sh` sets it. Which tests must build their am input from these
fixtures is the rule in `docs/architecture.md`'s Tests section. From a test
under `tests/<dir>/`:
```

- [ ] **Step 5: GREEN — every required edit landed and the scope held**

Run:
```bash
grep -n "schema is 1\|am · schema 1" docs/architecture.md
grep -n "amSchema\|amVersion\|story_id\|tests/fixtures/am\|test_am_fixtures\|canceled" docs/architecture.md
grep -n "docs/architecture.md" tests/helpers/README.md
git diff --stat ed8be4f
```
Expected: the first prints nothing; the second hits the RunStore bullet, the RunsScreen paragraph, the `runs.js` paragraph, the backend paragraph and the Tests section; the third prints one line; the fourth lists only `docs/architecture.md`, `tests/helpers/README.md` (plus the spec and plan under `docs/superpowers/`, if committed).

- [ ] **Step 6: Reviewer read against the tests**

Confirm against `tests/contract/test_am_fixtures.py:1-14` (contract and live-check wording), `:63-66` (`LIVE_EXTRA` is `story_id` on the runs row and status run only), `:298-311` (skips: no `am`, no main checkout, `am runs` failing, no runs) and `test_am_shapes.py:159` (`hello["schema"] in (1, 2)`). Fix any sentence that disagrees.

- [ ] **Step 7: Full suite still green**

Run: `bash tests/run.sh 2>&1 | tail -20`
Expected: no failures, as in Task 1 Step 1.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md tests/helpers/README.md
git commit -m "docs: the committed am fixtures, the rule for using them and the fixture contract test"
```
<!-- task-pipeline: validated -->
