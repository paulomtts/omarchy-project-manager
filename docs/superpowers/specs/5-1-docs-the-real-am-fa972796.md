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
