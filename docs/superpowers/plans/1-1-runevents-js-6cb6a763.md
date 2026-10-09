# 1.1 runEvents.js: eventRow for the five journal events (card 6cb6a763) — design

Narrows `docs/superpowers/specs/2026-10-05-run-events-timeline-design.md` (S5, "parent"
below) to one subtask of story ca0c7263. The parent's Architecture section (lines 72-76)
names `core/domain/runEvents.js` with `eventRow`, `mergeRows`, `filterRows`, `rowGlyph` and
`durationText`; this card delivers `eventRow` and its helper `durationText` only.

## Scope

In scope:

- New `core/domain/runEvents.js`: `.pragma library`, `.import "runs.js" as Runs`, and the two
  public functions `eventRow(event, titles, utcOffsetMinutes)` and `durationText(seconds)`.
- New `tests/core/domain/tst_run_events.qml`, written first (TDD).

Out of scope (sibling or later cards own it):

- `mergeRows`, `filterRows` and `rowGlyph` (parent lines 73-74): later subtasks of this story.
- `core/backend/runs/runs-events.py`, `RunStore.qml` events state, `EventsPane.qml`,
  `RunDetailScreen.qml` wiring, the contract test for `am events` (parent lines 77-90, 170-179).
- Drawing: the glyph character, the `urgent` token and the `‼` for failures (parent lines
  121-122) are the UI's job; this card returns the `runGlyphs.js` state key only.
- `docs/architecture.md` and README text for `runEvents.js`: the milestone's docs card.
- Friendlier labels for am's synthetic ids (`integrate`, `bases`, `base-*`): they take the same
  short-id fallback as any other id here (`…ntegrate`); `runs.js`'s `_isSynthetic` and
  `_syntheticLabel` are private and are not reused or copied.
- Cost and token figures: they no longer exist in the journal (parent lines 33-35). Nothing in
  this file reads or emits them.

## Inherited constraints

- Layering (`docs/architecture.md:11`; parent lines 69-70, 115-117): `core/domain/*.js` holds
  only `.pragma library` and `.import "x.js" as X` of other `core/domain` files. `runEvents.js`
  imports `runs.js` and nothing else; never `ui/` (so not `ui/components/runGlyphs.js`), never
  QML/Qt. `tests/architecture/test_layers.py` enforces this.
- No duplicated helpers: glyph mapping goes through `Runs.glyphStateOf` (`core/domain/runs.js:681-690`)
  and the short id through `Runs.shortId({id: x})` (`runs.js:528-531`), not re-implemented.
- Pure and never throwing, like the rest of `core/domain` (`docs/architecture.md:180`). No
  `new Date()`, no local-time getters: nothing depends on the machine's time zone or clock
  (parent lines 75-76).
- Event shape (parent lines 51-55, verified in `tests/fixtures/am/events.json`):
  `{seq, gseq, ts, run_id, event, story, card, phase, attempt, payload}`; `ts` is UTC,
  e.g. `2026-10-08T14:38:07.920070Z`. Unknown events (including `control_requested`,
  `control_handled`, `lease_*`, `claim_conflict`) and unknown payload keys are ignored (parent
  lines 54, 61-62, 159).
- Statuses (parent lines 58-61): run `started|done|escalated|stopped|cancelled`; story and
  subtask `pending|started|done|stopped|escalated`; phase `started|done|failed`; attempt
  `started|ok|schema_invalid|gate_failed|harness_error`. `cancelled` and `canceled` are both
  accepted everywhere (parent lines 64-65).
- Row model (parent lines 109-120), exact key set below.
- Comments and docstrings state the contract only, no narrative (card). ES5 `var`, private
  helpers `_`-prefixed (style of `runs.js`).
- Test fixtures (`docs/architecture.md:255-268`): am input comes from `tests/fixtures/am/`
  through `tests/helpers/amFixtures.js`; a hand-written am event is used only for an edge case
  the fixture lacks and is marked with a `synthetic:` comment.

## Interface

```
eventRow(event, titles, utcOffsetMinutes) -> row | null
durationText(seconds) -> string
```

`row` is a new plain object with exactly these eleven keys:

| key | type | value |
|---|---|---|
| `seq` | number | `event.seq` when a finite number, else `0` |
| `time` | string | `"HH:MM:SS"` (see Time), else `""` |
| `level` | string | `run`, `story`, `subtask`, `phase` or `attempt`, from `event.event` (`run_upsert` → `run`, …, `attempt_upsert` → `attempt`) |
| `label` | string | see Label |
| `status` | string | `payload.status` as am wrote it when a string, else `""` (no spelling rewrite: `canceled` stays `canceled`) |
| `glyph` | string | `Runs.glyphStateOf(status)`: one of `running`, `parked`, `escalated`, `dead`, `cancelled`, `done`, or `""` |
| `duration` | string | attempt level: `durationText(payload.duration)`; every other level `""` |
| `detail` | string | phase level: `payload.detail` when a string, else `""`; every other level `""` |
| `card` | string | `event.card` when a string, else `""` (a story or run row has `""`) |
| `phase` | string | `event.phase` when a non-empty string, else `payload.name` for a phase event when a non-empty string, else `""` |
| `attempt` | number | attempt level: `event.attempt` when a finite number > 0, else `payload.n` when a finite number > 0, else `0`; every other level `0` |

`eventRow` returns `null` when `event` is not a non-array object, or `event.event` is not one
of the five `*_upsert` kinds (an inherited name such as `"constructor"` is not a kind). A
missing or non-object `payload` is read as `{}` (the row is still built). It never throws
for any `titles` or `utcOffsetMinutes`, and never mutates its arguments.

### Time

- `ts` must be a string beginning `YYYY-MM-DDTHH:MM:SS` (digits), followed by an optional
  fractional part and a `Z`; anything else gives `time: ""`.
- The UTC hour, minute and second are read from the string (fraction truncated, never
  rounded up), shifted by `utcOffsetMinutes`, and wrapped into one day (past midnight wraps to
  `00:…`, before midnight to `23:…`). Each field is zero-padded to two digits.
- `utcOffsetMinutes` that is not a finite number is `0`; a fractional one is rounded to the
  nearest minute.

### Label

The name of the node:

- story level: `titles[event.story]` when `titles` is a non-array object with that own key
  holding a non-empty string, else `Runs.shortId({id: event.story})` (`"…"` + last 8
  characters; `"…"` alone when `event.story` is not a string).
- subtask, phase, attempt levels: the same lookup with `event.card`.

Then:

- story, subtask: the name.
- phase: name + `" "` + `phase`, or the name alone when `phase` is `""`.
- attempt: name + `" "` + `phase` + `"."` + `attempt`; name + `" "` + `phase` when `attempt` is
  `0`; the name alone when `phase` is `""`.
- run: `"run "` + the word for `payload.status`: `started` → `started`, `done` → `done`,
  `stopped` → `paused`, `escalated` → `escalated`, `cancelled` and `canceled` → `cancelled`;
  any other non-empty status string is used as is; with no status string the label is `"run"`.

Titles lookups use own keys only (`Object.prototype.hasOwnProperty.call`), so a card id such as
`"constructor"` never picks an inherited value.

### Glyph

`glyph` is exactly `Runs.glyphStateOf(status)`, which already yields: `started` → running,
`stopped` → parked, `escalated` → escalated, `failed`/`gate_failed`/`schema_invalid`/
`harness_error` → dead, `cancelled`/`canceled` → cancelled, `done`/`ok` → done, anything else
(including `pending` and `""`) → `""`. No other mapping lives in `runEvents.js`.

### durationText(seconds)

- Not a finite number, or negative: `""` (so `null`, `undefined`, `"4.2"`, `NaN`, `Infinity`,
  `-1` are all `""`).
- Rounded to one decimal; below 60: that value with one decimal and `s`: `0.031…` → `"0.0s"`,
  `4.21` → `"4.2s"`, `59.94` → `"59.9s"`.
- Otherwise (including `59.96`, which rounds to `60.0`): whole seconds rounded,
  `M + "m " + SS + "s"` with seconds zero-padded to two digits and minutes unbounded:
  `60` → `"1m 00s"`, `192.4` → `"3m 12s"`, `422` → `"7m 02s"`, `4500` → `"75m 00s"`.

## Error paths

All return without throwing and without a qmltestrunner warning (`tests/run.sh` fails on
TypeError, ReferenceError and the like):

| input | result |
|---|---|
| `event` `null`, `undefined`, a string, a number, an array | `null` |
| `event.event` missing, `lease_acquired`, `control_requested`, `control_handled`, `claim_conflict`, `"bogus"`, `"constructor"` | `null` |
| `payload` missing, `null`, a string | row built from `{}`: status `""`, glyph `""`, duration `""`, detail `""` |
| unknown payload keys (`cost`, `tokens`, anything) | ignored; the row has exactly the eleven keys |
| `titles` `null`, `undefined`, an array, a string; a title that is `""` or not a string | short-id fallback |
| `ts` missing, not a string, `"yesterday"`, no `Z` | `time: ""`, rest of the row intact |
| `utcOffsetMinutes` missing, `NaN`, a string | treated as `0` |
| `seq` missing or not a number | `seq: 0` |
| attempt `duration` `null` (a started attempt) | `duration: ""` |

## Tests

All new tests are **QML domain tests** in `tests/core/domain/tst_run_events.qml`: the tier for
pure `core/domain/*.js` (`docs/architecture.md` "Tests"; parent Testing lines 165-169, which puts
`eventRow` there). Style of `tests/core/domain/tst_runs.qml`: header comment,
`import QtQuick`, `import QtTest`, `import "../../../core/domain/runEvents.js" as RE`,
`import "../../../core/domain/runs.js" as Runs` (only where a test cross-checks the glyph),
`import "../../helpers/amFixtures.js" as F`, `TestCase { name: "DomainRunEvents" }`. Real events
come from `F.load("events.json").data.events` (am 0.2.0 recording of a finished run, run
`20261008T143807Z-63060df3`): index 0 `lease_acquired`, 1 `run_upsert` started, 2 `story_upsert`
pending (story `ae1e3ba6…`), 3 `subtask_upsert` pending (card `7442d674…`), 18 `phase_upsert`
worktree started, 19 the same phase done, 21 `attempt_upsert` explore.1 started (duration
null), 22 the same attempt ok (duration 0.0314…). The fixture holds no failed phase, escalated,
stopped or cancelled run and no failing attempt, so those cases are fixture events copied and
edited (a fresh `F.load` copy), each marked `// synthetic:`.

The **architecture tier** (`tests/architecture/test_layers.py`, `test_icon_glyphs.py`) must
pass unchanged: it proves the import rule and that no glyph character lands in `core/domain`.
No backend, store, contract or UI tests belong to this card.

| test (QML domain tier) | pins |
|---|---|
| `test_run_started_from_fixture` | event 1, offset 0: `{seq:2, time:"14:38:07", level:"run", label:"run started", status:"started", glyph:"running", duration:"", detail:"", card:"", phase:"", attempt:0}`; key set is exactly the eleven keys. |
| `test_run_labels` | synthetic copies of event 1 with status `done`, `stopped`, `escalated`, `cancelled`, `canceled`: labels `run done`, `run paused`, `run escalated`, `run cancelled`, `run cancelled`; glyphs `done`, `parked`, `escalated`, `cancelled`, `cancelled`; `status` keeps `canceled` as written. Unknown status `"weird"` → `run weird`, glyph `""`; no status → `run`. |
| `test_story_row` | event 2 with `titles = {"ae1e3ba6-cc07-4e9d-aff7-db161c3be234": "Control domain"}` → level `story`, label `Control domain`, status `pending`, glyph `""`, card `""`; with `{}` → label `…1c3be234` (`"…"` + the story id's last 8 characters). |
| `test_subtask_row` | event 3 with a title for its card → that title; without → `Runs.shortId({id: card})`; card carried; status `pending`. A synthetic copy with status `escalated` → glyph `escalated`; `stopped` → `parked`. |
| `test_phase_rows` | events 18, 19 with titles → label `<title> worktree`, status `started`/`done`, glyph `running`/`done`, phase `worktree`, attempt 0, detail `""`, duration `""`. |
| `test_failed_phase_detail` | synthetic copy of event 19 with status `failed`, detail `"3 tests red"` → glyph `dead`, detail `3 tests red`; detail `null` → `""`. |
| `test_attempt_rows` | event 21 → label `<title> explore.1`, attempt 1, phase `explore`, glyph `running`, duration `""`; event 22 → glyph `done` (ok is done), duration `0.0s`. |
| `test_attempt_failures` | synthetic copies of event 22 with status `gate_failed`, `schema_invalid`, `harness_error` → glyph `dead`; duration `192.4` → `3m 12s`. |
| `test_attempt_number_fallback` | synthetic attempt with `event.attempt` null and `payload.n` 2 → attempt 2, label `… explore.2`; neither → attempt 0, label `<name> explore`. |
| `test_phase_name_fallback` | synthetic phase event with `event.phase` null and `payload.name` `"verify"` → phase `verify`; neither → label is the name alone. |
| `test_time_offsets` | event 1 (`14:38:07.920070Z`) with offsets 0, 120, -330, 600, -900 → `14:38:07`, `16:38:07`, `09:08:07`, `00:38:07`, `23:38:07`; a `ts` of `…T00:00:59.999999Z` at offset 0 → `00:00:59` (truncated); offset `NaN`/missing → as 0. |
| `test_bad_ts` | `ts` missing, `5`, `"yesterday"`, `"2026-10-08T14:38:07"` (no `Z`) → `time ""`, row otherwise built. |
| `test_duration_text` | `null`, `undefined`, `"4.2"`, `NaN`, `Infinity`, `-1` → `""`; `0.031444` → `0.0s`; `4.21` → `4.2s`; `59.94` → `59.9s`; `59.96` → `1m 00s`; `60` → `1m 00s`; `192.4` → `3m 12s`; `422` → `7m 02s`; `4500` → `75m 00s`. |
| `test_duration_only_on_attempts` | a synthetic phase event with `payload.duration: 5` → duration `""`; detail on a non-phase event (`subtask_upsert` with `payload.detail`) → detail `""`. |
| `test_unknown_events_ignored` | event 0 (`lease_acquired`), and synthetic `control_requested`, `control_handled`, `claim_conflict`, `"bogus"`, `"constructor"`, missing `event` → `null`. |
| `test_bad_inputs` | `eventRow(null)`, `undefined`, `"x"`, `5`, `[]` → `null`; payload `null`/`"x"` → row with status `""`; titles `null`/`[]`/`"x"`/title `""`/title `7` → short-id fallback; titles `{constructor: …}` lookup of card `"constructor"` own-key only; `seq` missing → 0. |
| `test_unknown_keys_and_no_cost` | synthetic copy of event 22 with `payload.cost`, `payload.tokens`, `payload.extra` → keys exactly the eleven; no `cost`/`tokens` key. |
| `test_does_not_mutate` | `JSON.stringify` of event and titles before and after `eventRow` are equal. |
| `test_glyph_is_runs_mapping` | for every status in the parent's status list plus `canceled` and `pending`, `row.glyph === Runs.glyphStateOf(status)` and is a key of the set `running, parked, escalated, dead, cancelled, done` or `""`. |

## Verification

- `bash tests/run.sh tst_run_events` while iterating (the filter still runs pytest).
- `bash tests/run.sh` green before the card is done: pytest including `tests/architecture`, then
  every QML test.

---

# runEvents.js `eventRow` and `durationText` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure domain module `core/domain/runEvents.js` with `durationText(seconds)` and `eventRow(event, titles, utcOffsetMinutes)`, turning one am journal event into one timeline row.

**Architecture:** One `.pragma library` file in `core/domain/` that imports only `runs.js` (for `Runs.glyphStateOf` and `Runs.shortId`). Private `_`-prefixed helpers do the time parsing, the title lookup and the label; the two public functions never throw and never mutate input. Tests are QML domain tests fed from `tests/fixtures/am/events.json` through `tests/helpers/amFixtures.js`.

**Tech Stack:** QML JavaScript (ES5 style, `var`), Qt 6 `qmltestrunner` via `tests/run.sh`, pytest architecture tests.

**Spec:** `docs/superpowers/specs/1-1-runevents-js-6cb6a763.md` (prepended above this plan).

## Global Constraints

- `core/domain/runEvents.js` contains only `.pragma library` and `.import "runs.js" as Runs` as imports; never `ui/`, never QML/Qt (`tests/architecture/test_layers.py`).
- Glyph state via `Runs.glyphStateOf(status)` only; short id via `Runs.shortId({id: x})` only. No copy of either, and no reuse of `runs.js`'s private `_isSynthetic`/`_syntheticLabel`/`_attemptNumber`.
- Pure and never throwing; no `new Date()`, no local-time getters, no clock.
- Row has exactly eleven keys: `seq, time, level, label, status, glyph, duration, detail, card, phase, attempt`.
- `status` is `payload.status` as written (`canceled` stays `canceled`); no cost or token keys anywhere.
- Comments state the contract only, no narrative. ES5 `var`; private helpers `_`-prefixed.
- Test events come from `F.load("events.json").data.events`; every hand-edited event carries a `// synthetic:` comment.
- `bash tests/run.sh` must be green (pytest incl. `tests/architecture`, then every QML test) before the card is done.

## Review Focus

1. A `ts` with no fractional part (`2026-10-08T14:38:07Z`) is valid and gives `14:38:07`; one ending `+00:00` or lowercase `z` gives `""` — pinned in Task 2 `test_time_offsets` / `test_bad_ts`.
2. A fractional or huge `utcOffsetMinutes` (`90.4`, `89.6`, `-0.4`, `1e9`, `Infinity`) rounds to the minute, still yields `HH:MM:SS`, and never throws — pinned in Task 2 `test_time_offsets`.
3. A non-string `payload.status` (`5`, `null`, an object) gives status `""`, glyph `""` and run label `"run"`, not `"run 5"` — pinned in Task 2 `test_run_labels`.
4. An `event.attempt` on a non-attempt event (a phase event with `attempt: 3`) gives `attempt: 0` and no `.3` in the label — pinned in Task 2 `test_attempt_number_fallback`.
5. Ids naming inherited properties (`"__proto__"`, `"toString"`, `"constructor"`) as event kinds or card ids never pick an inherited value; a non-string story id gives `"…"` — pinned in Task 2 `test_unknown_events_ignored` / `test_bad_inputs`.

---

### Task 1: `durationText`

**Files:**
- Create: `core/domain/runEvents.js`
- Test: `tests/core/domain/tst_run_events.qml` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks. `tests/helpers/amFixtures.js` exports `load(name)` returning a fresh parse of `tests/fixtures/am/<name>`.
- Produces: `durationText(seconds) -> string`; private helpers `_isFiniteNumber(v) -> boolean` and `_pad2(n) -> string` in `core/domain/runEvents.js`; test-file helpers `events()`, `titles()` and properties `keys`, `storyId`, `cardId` used by Task 2.

- [ ] **Step 1: Write the failing test**

Create `tests/core/domain/tst_run_events.qml`:

```qml
// tests/core/domain/tst_run_events.qml
import QtQuick
import QtTest
import "../../../core/domain/runEvents.js" as RE
import "../../../core/domain/runs.js" as Runs
import "../../helpers/amFixtures.js" as F

// eventRow's input comes from tests/fixtures/am/events.json (am 0.2.0, run
// 20261008T143807Z-63060df3) via events().
TestCase {
  name: "DomainRunEvents"

  readonly property string keys: "attempt,card,detail,duration,glyph,label,level,phase,seq,status,time"
  readonly property string storyId: "ae1e3ba6-cc07-4e9d-aff7-db161c3be234"
  readonly property string cardId: "7442d674-e0d4-4048-96ee-cd27b5ba34f8"

  // The fixture's journal events, a fresh copy on every call.
  function events() { return F.load("events.json").data.events }

  // Titles for the fixture's story and its first subtask.
  function titles() {
    var t = {}
    t[storyId] = "Control domain"
    t[cardId] = "runs.js control"
    return t
  }

  function test_duration_text() {
    var blanks = [null, undefined, "4.2", NaN, Infinity, -Infinity, -1]
    for (var i = 0; i < blanks.length; i++) compare(RE.durationText(blanks[i]), "", String(blanks[i]))
    compare(RE.durationText(0.031444113003090024), "0.0s")
    compare(RE.durationText(0), "0.0s")
    compare(RE.durationText(4.21), "4.2s")
    compare(RE.durationText(59.94), "59.9s")
    compare(RE.durationText(59.96), "1m 00s")
    compare(RE.durationText(60), "1m 00s")
    compare(RE.durationText(192.4), "3m 12s")
    compare(RE.durationText(422), "7m 02s")
    compare(RE.durationText(4500), "75m 00s")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash tests/run.sh tst_run_events`
Expected: pytest passes, then under `== tests/core/domain/tst_run_events.qml`:
`FAIL!  : qmltestrunner::tst_run_events::compile() Script file:///…/core/domain/runEvents.js unavailable` and `Totals: 0 passed, 1 failed`; exit status 1.

- [ ] **Step 3: Write minimal implementation**

Create `core/domain/runEvents.js`:

```js
.pragma library
.import "runs.js" as Runs

// Run events timeline: one row per am journal event (`am events`).
// Pure and never throwing; reads no clock and no time zone.

function _isFiniteNumber(v) { return typeof v === "number" && isFinite(v) }
function _pad2(n) { return (n < 10 ? "0" : "") + n }

// An attempt's duration in seconds as text: below 60 (after rounding to one
// decimal) "S.Ss", else "Mm SSs" of the whole seconds. "" when seconds is not a
// finite number or is negative.
function durationText(seconds) {
  if (!_isFiniteNumber(seconds) || seconds < 0) return ""
  var tenths = Math.round(seconds * 10)
  if (tenths < 600) return (tenths / 10).toFixed(1) + "s"
  var whole = Math.round(seconds)
  return Math.floor(whole / 60) + "m " + _pad2(whole % 60) + "s"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash tests/run.sh tst_run_events`
Expected: pytest all passed (including `tests/architecture/test_layers.py`, which now scans `runEvents.js`), then `Totals: 3 passed, 0 failed` (initTestCase, test_duration_text, cleanupTestCase); exit status 0.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runEvents.js tests/core/domain/tst_run_events.qml
git commit -m "feat(runEvents): durationText for attempt durations"
```

---

### Task 2: `eventRow`

**Files:**
- Modify: `core/domain/runEvents.js` (replace the whole file)
- Test: `tests/core/domain/tst_run_events.qml` (add test functions before the final `}` of the `TestCase`)

**Interfaces:**
- Consumes: from Task 1, `durationText(seconds) -> string`, `_isFiniteNumber`, `_pad2`; test helpers `events()`, `titles()`, `keys`, `storyId`, `cardId`. From `core/domain/runs.js`: `Runs.glyphStateOf(status) -> string` (one of `running, parked, escalated, dead, cancelled, done, ""`) and `Runs.shortId(run) -> string` (`"…"` + last 8 chars of `run.id`, `"…"` when not a string).
- Produces: `eventRow(event, titles, utcOffsetMinutes) -> {seq: number, time: string, level: string, label: string, status: string, glyph: string, duration: string, detail: string, card: string, phase: string, attempt: number} | null` — consumed by later cards' `mergeRows`/`filterRows` and `RunStore.qml`.

Fixture indices used below (`events()[i]`): 0 `lease_acquired`; 1 `run_upsert` started, seq 2, ts `2026-10-08T14:38:07.920070Z`; 2 `story_upsert` pending, story `ae1e3ba6-cc07-4e9d-aff7-db161c3be234`, seq 3; 3 `subtask_upsert` pending, card `7442d674-e0d4-4048-96ee-cd27b5ba34f8`; 18 `phase_upsert` worktree started; 19 same phase done; 21 `attempt_upsert` explore.1 started, duration null; 22 same attempt ok, duration `0.031444113003090024`.

- [ ] **Step 1: Write the failing tests**

Insert these functions into `tests/core/domain/tst_run_events.qml` after `test_duration_text` and before the closing `}` of the `TestCase`:

```qml
  function test_run_started_from_fixture() {
    var r = RE.eventRow(events()[1], {}, 0)
    compare(Object.keys(r).sort().join(","), keys)
    compare(r.seq, 2)
    compare(r.time, "14:38:07")
    compare(r.level, "run")
    compare(r.label, "run started")
    compare(r.status, "started")
    compare(r.glyph, "running")
    compare(r.duration, "")
    compare(r.detail, "")
    compare(r.card, "")
    compare(r.phase, "")
    compare(r.attempt, 0)
  }

  function test_run_labels() {
    var cases = [["done", "run done", "done"], ["stopped", "run paused", "parked"],
                 ["escalated", "run escalated", "escalated"], ["cancelled", "run cancelled", "cancelled"],
                 ["canceled", "run cancelled", "cancelled"], ["weird", "run weird", ""]]
    for (var i = 0; i < cases.length; i++) {
      // synthetic: the fixture's run_upsert with its status edited
      var e = events()[1]
      e.payload.status = cases[i][0]
      var r = RE.eventRow(e, {}, 0)
      compare(r.label, cases[i][1], cases[i][0])
      compare(r.glyph, cases[i][2], cases[i][0])
      compare(r.status, cases[i][0], cases[i][0])
    }
    // synthetic: the fixture's run_upsert without a status
    var bare = events()[1]
    delete bare.payload.status
    var b = RE.eventRow(bare, {}, 0)
    compare(b.label, "run")
    compare(b.status, "")
    compare(b.glyph, "")
    // synthetic: a status that is not a string
    var odd = [5, null, { s: "done" }]
    for (var j = 0; j < odd.length; j++) {
      var o = events()[1]
      o.payload.status = odd[j]
      var r2 = RE.eventRow(o, {}, 0)
      compare(r2.label, "run", String(odd[j]))
      compare(r2.status, "", String(odd[j]))
      compare(r2.glyph, "", String(odd[j]))
    }
  }

  function test_story_row() {
    var r = RE.eventRow(events()[2], titles(), 0)
    compare(r.level, "story")
    compare(r.label, "Control domain")
    compare(r.status, "pending")
    compare(r.glyph, "")
    compare(r.card, "")
    compare(r.seq, 3)
    compare(RE.eventRow(events()[2], {}, 0).label, "…1c3be234")
  }

  function test_subtask_row() {
    var r = RE.eventRow(events()[3], titles(), 0)
    compare(r.level, "subtask")
    compare(r.label, "runs.js control")
    compare(r.card, cardId)
    compare(r.status, "pending")
    compare(r.glyph, "")
    var bare = RE.eventRow(events()[3], {}, 0)
    compare(bare.label, Runs.shortId({ id: cardId }))
    compare(bare.label, "…b5ba34f8")
    // synthetic: the fixture's subtask_upsert with its status edited
    var e = events()[3]
    e.payload.status = "escalated"
    compare(RE.eventRow(e, titles(), 0).glyph, "escalated")
    e.payload.status = "stopped"
    compare(RE.eventRow(e, titles(), 0).glyph, "parked")
  }

  function test_phase_rows() {
    var started = RE.eventRow(events()[18], titles(), 0)
    var done = RE.eventRow(events()[19], titles(), 0)
    compare(started.level, "phase")
    compare(started.label, "runs.js control worktree")
    compare(done.label, "runs.js control worktree")
    compare(started.status, "started")
    compare(done.status, "done")
    compare(started.glyph, "running")
    compare(done.glyph, "done")
    compare(started.phase, "worktree")
    compare(started.attempt, 0)
    compare(started.detail, "")
    compare(started.duration, "")
    compare(started.card, cardId)
  }

  function test_failed_phase_detail() {
    // synthetic: the fixture's done worktree phase edited to failed with a detail
    var e = events()[19]
    e.payload.status = "failed"
    e.payload.detail = "3 tests red"
    var r = RE.eventRow(e, titles(), 0)
    compare(r.glyph, "dead")
    compare(r.detail, "3 tests red")
    e.payload.detail = null
    compare(RE.eventRow(e, titles(), 0).detail, "")
  }

  function test_attempt_rows() {
    var started = RE.eventRow(events()[21], titles(), 0)
    compare(started.level, "attempt")
    compare(started.label, "runs.js control explore.1")
    compare(started.attempt, 1)
    compare(started.phase, "explore")
    compare(started.glyph, "running")
    compare(started.duration, "")
    var ok = RE.eventRow(events()[22], titles(), 0)
    compare(ok.status, "ok")
    compare(ok.glyph, "done")
    compare(ok.duration, "0.0s")
  }

  function test_attempt_failures() {
    var failures = ["gate_failed", "schema_invalid", "harness_error"]
    for (var i = 0; i < failures.length; i++) {
      // synthetic: the fixture's ok attempt with its status edited
      var e = events()[22]
      e.payload.status = failures[i]
      compare(RE.eventRow(e, titles(), 0).glyph, "dead", failures[i])
    }
    // synthetic: a longer attempt
    var long = events()[22]
    long.payload.duration = 192.4
    compare(RE.eventRow(long, titles(), 0).duration, "3m 12s")
  }

  function test_attempt_number_fallback() {
    // synthetic: the attempt number only in the payload
    var e = events()[21]
    e.attempt = null
    e.payload.n = 2
    var r = RE.eventRow(e, titles(), 0)
    compare(r.attempt, 2)
    compare(r.label, "runs.js control explore.2")
    // synthetic: no attempt number at all
    delete e.payload.n
    var none = RE.eventRow(e, titles(), 0)
    compare(none.attempt, 0)
    compare(none.label, "runs.js control explore")
    // synthetic: an attempt number on a phase event is not an attempt
    var p = events()[18]
    p.attempt = 3
    var phase = RE.eventRow(p, titles(), 0)
    compare(phase.attempt, 0)
    compare(phase.label, "runs.js control worktree")
  }

  function test_phase_name_fallback() {
    // synthetic: the phase name only in the payload
    var e = events()[18]
    e.phase = null
    e.payload.name = "verify"
    var r = RE.eventRow(e, titles(), 0)
    compare(r.phase, "verify")
    compare(r.label, "runs.js control verify")
    // synthetic: no phase name at all
    delete e.payload.name
    var none = RE.eventRow(e, titles(), 0)
    compare(none.phase, "")
    compare(none.label, "runs.js control")
  }

  function test_time_offsets() {
    var cases = [[0, "14:38:07"], [120, "16:38:07"], [-330, "09:08:07"], [600, "00:38:07"],
                 [-900, "23:38:07"], [90.4, "16:08:07"], [89.6, "16:08:07"], [-0.4, "14:38:07"],
                 [NaN, "14:38:07"], [undefined, "14:38:07"], ["120", "14:38:07"], [Infinity, "14:38:07"]]
    for (var i = 0; i < cases.length; i++)
      compare(RE.eventRow(events()[1], {}, cases[i][0]).time, cases[i][1], String(cases[i][0]))
    compare(RE.eventRow(events()[1], {}).time, "14:38:07")
    verify(/^\d\d:\d\d:\d\d$/.test(RE.eventRow(events()[1], {}, 1e9).time))
    // synthetic: a ts one microsecond short of the next second
    var e = events()[1]
    e.ts = "2026-10-08T00:00:59.999999Z"
    compare(RE.eventRow(e, {}, 0).time, "00:00:59")
    // synthetic: a ts with no fraction
    e.ts = "2026-10-08T14:38:07Z"
    compare(RE.eventRow(e, {}, 0).time, "14:38:07")
  }

  function test_bad_ts() {
    var bad = [5, "yesterday", "2026-10-08T14:38:07", "2026-10-08T14:38:07+00:00", "2026-10-08T14:38:07z", null]
    for (var i = 0; i < bad.length; i++) {
      // synthetic: the fixture's run_upsert with its ts edited
      var e = events()[1]
      e.ts = bad[i]
      var r = RE.eventRow(e, {}, 0)
      compare(r.time, "", String(bad[i]))
      compare(r.label, "run started", String(bad[i]))
      compare(r.seq, 2, String(bad[i]))
    }
    // synthetic: no ts
    var none = events()[1]
    delete none.ts
    compare(RE.eventRow(none, {}, 0).time, "")
  }

  function test_duration_only_on_attempts() {
    // synthetic: a duration on a phase event
    var p = events()[18]
    p.payload.duration = 5
    compare(RE.eventRow(p, titles(), 0).duration, "")
    // synthetic: a detail on a subtask and on an attempt event
    var s = events()[3]
    s.payload.detail = "why"
    compare(RE.eventRow(s, titles(), 0).detail, "")
    var a = events()[22]
    a.payload.detail = "why"
    compare(RE.eventRow(a, titles(), 0).detail, "")
  }

  function test_unknown_events_ignored() {
    compare(RE.eventRow(events()[0], {}, 0), null)
    var names = ["control_requested", "control_handled", "claim_conflict", "lease_released", "bogus",
                 "constructor", "toString", "__proto__", "", 5, null]
    for (var i = 0; i < names.length; i++) {
      // synthetic: the fixture's run_upsert renamed
      var e = events()[1]
      e.event = names[i]
      compare(RE.eventRow(e, {}, 0), null, String(names[i]))
    }
    // synthetic: no event name
    var none = events()[1]
    delete none.event
    compare(RE.eventRow(none, {}, 0), null)
  }

  function test_bad_inputs() {
    var notEvents = [null, undefined, "x", 5, [], [events()[1]]]
    for (var i = 0; i < notEvents.length; i++) compare(RE.eventRow(notEvents[i], {}, 0), null, String(notEvents[i]))
    compare(RE.eventRow(), null)

    var payloads = [null, "x", 5, []]
    for (var j = 0; j < payloads.length; j++) {
      // synthetic: the fixture's ok attempt with its payload replaced
      var e = events()[22]
      e.payload = payloads[j]
      var r = RE.eventRow(e, titles(), 0)
      compare(Object.keys(r).sort().join(","), keys, String(payloads[j]))
      compare(r.status, "", String(payloads[j]))
      compare(r.glyph, "", String(payloads[j]))
      compare(r.duration, "", String(payloads[j]))
      compare(r.label, "runs.js control explore.1", String(payloads[j]))
    }
    // synthetic: no payload
    var bare = events()[22]
    delete bare.payload
    compare(RE.eventRow(bare, titles(), 0).status, "")

    var short = Runs.shortId({ id: cardId })
    var badTitles = [null, undefined, [], "x", 5]
    for (var k = 0; k < badTitles.length; k++)
      compare(RE.eventRow(events()[3], badTitles[k], 0).label, short, String(badTitles[k]))
    var t = {}
    t[cardId] = ""
    compare(RE.eventRow(events()[3], t, 0).label, short)
    t[cardId] = 7
    compare(RE.eventRow(events()[3], t, 0).label, short)
    t[cardId] = null
    compare(RE.eventRow(events()[3], t, 0).label, short)

    // synthetic: card ids that name inherited properties
    var ctor = events()[3]
    ctor.card = "constructor"
    compare(RE.eventRow(ctor, {}, 0).label, "…structor")
    compare(RE.eventRow(ctor, { constructor: "Ctor" }, 0).label, "Ctor")
    var proto = events()[3]
    proto.card = "__proto__"
    compare(RE.eventRow(proto, {}, 0).label, "…_proto__")
    // synthetic: a story id that is not a string
    var numeric = events()[2]
    numeric.story = 5
    compare(RE.eventRow(numeric, titles(), 0).label, "…")

    // synthetic: seq missing or not a number
    var noSeq = events()[1]
    delete noSeq.seq
    compare(RE.eventRow(noSeq, {}, 0).seq, 0)
    noSeq.seq = "2"
    compare(RE.eventRow(noSeq, {}, 0).seq, 0)
    noSeq.seq = NaN
    compare(RE.eventRow(noSeq, {}, 0).seq, 0)
  }

  function test_unknown_keys_and_no_cost() {
    // synthetic: the fixture's ok attempt with keys am no longer writes
    var e = events()[22]
    e.payload.cost = 0.12
    e.payload.tokens = 3400
    e.payload.extra = { any: "thing" }
    var r = RE.eventRow(e, titles(), 0)
    compare(Object.keys(r).sort().join(","), keys)
    compare(r.hasOwnProperty("cost"), false)
    compare(r.hasOwnProperty("tokens"), false)
  }

  function test_does_not_mutate() {
    var all = events()
    var t = titles()
    for (var i = 0; i < all.length; i++) {
      var before = JSON.stringify(all[i])
      var titlesBefore = JSON.stringify(t)
      RE.eventRow(all[i], t, 120)
      compare(JSON.stringify(all[i]), before, "event " + i)
      compare(JSON.stringify(t), titlesBefore, "titles after event " + i)
    }
  }

  function test_glyph_is_runs_mapping() {
    var allowed = ["running", "parked", "escalated", "dead", "cancelled", "done", ""]
    var statuses = ["started", "done", "escalated", "stopped", "cancelled", "canceled", "pending", "failed",
                    "ok", "schema_invalid", "gate_failed", "harness_error"]
    for (var i = 0; i < statuses.length; i++) {
      // synthetic: the fixture's ok attempt with its status edited
      var e = events()[22]
      e.payload.status = statuses[i]
      var glyph = RE.eventRow(e, titles(), 0).glyph
      compare(glyph, Runs.glyphStateOf(statuses[i]), statuses[i])
      verify(allowed.indexOf(glyph) !== -1, statuses[i])
    }
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash tests/run.sh tst_run_events`
Expected: `test_duration_text` passes; each new test fails with
`Uncaught exception: Property 'eventRow' of object [object Object] is not a function`; exit status 1.

- [ ] **Step 3: Write the implementation**

Replace the whole of `core/domain/runEvents.js` with:

```js
.pragma library
.import "runs.js" as Runs

// Run events timeline: one row per am journal event (`am events`).
//
// Input event, as am writes it:
//   { seq, gseq, ts, run_id, event, story, card, phase, attempt, payload }
// ts is UTC, "YYYY-MM-DDTHH:MM:SS[.ffffff]Z". Only run_upsert, story_upsert,
// subtask_upsert, phase_upsert and attempt_upsert give a row; every other event
// and every unknown payload key is ignored. Pure and never throwing; reads no
// clock and no time zone.

var _LEVELS = { run_upsert: "run", story_upsert: "story", subtask_upsert: "subtask",
                phase_upsert: "phase", attempt_upsert: "attempt" }

var _RUN_WORDS = { started: "started", done: "done", stopped: "paused", escalated: "escalated",
                   cancelled: "cancelled", canceled: "cancelled" }

var _TS_RE = /^\d{4}-\d{2}-\d{2}T(\d{2}):(\d{2}):(\d{2})(\.\d+)?Z$/

function _isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function _has(o, key) { return Object.prototype.hasOwnProperty.call(o, key) }
function _isFiniteNumber(v) { return typeof v === "number" && isFinite(v) }
function _stringOr(v) { return typeof v === "string" ? v : "" }
function _pad2(n) { return (n < 10 ? "0" : "") + n }

// "HH:MM:SS" of a UTC ts shifted by utcOffsetMinutes (0 when not a finite
// number, rounded to the minute) and wrapped into one day; the fraction is
// dropped. "" when ts is not "YYYY-MM-DDTHH:MM:SS[.f]Z".
function _timeOf(ts, utcOffsetMinutes) {
  var m = typeof ts === "string" ? _TS_RE.exec(ts) : null
  if (m === null) return ""
  var offset = _isFiniteNumber(utcOffsetMinutes) ? Math.round(utcOffsetMinutes) : 0
  var day = 86400
  var secs = Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + offset * 60
  secs = (secs % day + day) % day
  return _pad2(Math.floor(secs / 3600)) + ":" + _pad2(Math.floor(secs % 3600 / 60)) + ":" + _pad2(secs % 60)
}

// titles[id] when titles is an object with that own key holding a non-empty
// string, else Runs.shortId of the id.
function _nameOf(id, titles) {
  if (_isObject(titles) && typeof id === "string" && _has(titles, id) && _stringOr(titles[id]) !== "")
    return titles[id]
  return Runs.shortId({ id: id })
}

function _labelOf(level, event, titles, status, phase, attempt) {
  if (level === "run") {
    if (status === "") return "run"
    return "run " + (_has(_RUN_WORDS, status) ? _RUN_WORDS[status] : status)
  }
  var name = _nameOf(level === "story" ? event.story : event.card, titles)
  if (level === "story" || level === "subtask" || phase === "") return name
  if (level === "phase" || attempt === 0) return name + " " + phase
  return name + " " + phase + "." + attempt
}

// One timeline row for an am journal event, or null when event is not an
// object or not one of the five *_upsert kinds. Row:
//   { seq, time, level, label, status, glyph, duration, detail, card, phase, attempt }
// seq: event.seq, else 0. time: "HH:MM:SS" of ts at utcOffsetMinutes, else "".
// level: run | story | subtask | phase | attempt. label: the node's title from
// titles (story id or card id -> title), else its short id; a phase adds
// " <phase>", an attempt " <phase>.<n>"; a run is "run <status word>".
// status: payload.status as written, else "". glyph: Runs.glyphStateOf(status).
// duration: an attempt's durationText(payload.duration), else "". detail: a
// phase's payload.detail, else "". card: event.card, else "". phase:
// event.phase, else a phase event's payload.name, else "". attempt: an
// attempt's event.attempt, else payload.n, when above 0; else 0.
function eventRow(event, titles, utcOffsetMinutes) {
  if (!_isObject(event) || typeof event.event !== "string" || !_has(_LEVELS, event.event)) return null
  var level = _LEVELS[event.event]
  var payload = _isObject(event.payload) ? event.payload : {}
  var status = _stringOr(payload.status)
  var phase = _stringOr(event.phase)
  if (phase === "" && level === "phase") phase = _stringOr(payload.name)
  var attempt = 0
  if (level === "attempt") {
    if (_isFiniteNumber(event.attempt) && event.attempt > 0) attempt = event.attempt
    else if (_isFiniteNumber(payload.n) && payload.n > 0) attempt = payload.n
  }
  return {
    seq: _isFiniteNumber(event.seq) ? event.seq : 0,
    time: _timeOf(event.ts, utcOffsetMinutes),
    level: level,
    label: _labelOf(level, event, titles, status, phase, attempt),
    status: status,
    glyph: Runs.glyphStateOf(status),
    duration: level === "attempt" ? durationText(payload.duration) : "",
    detail: level === "phase" ? _stringOr(payload.detail) : "",
    card: _stringOr(event.card),
    phase: phase,
    attempt: attempt
  }
}

// An attempt's duration in seconds as text: below 60 (after rounding to one
// decimal) "S.Ss", else "Mm SSs" of the whole seconds. "" when seconds is not a
// finite number or is negative.
function durationText(seconds) {
  if (!_isFiniteNumber(seconds) || seconds < 0) return ""
  var tenths = Math.round(seconds * 10)
  if (tenths < 600) return (tenths / 10).toFixed(1) + "s"
  var whole = Math.round(seconds)
  return Math.floor(whole / 60) + "m " + _pad2(whole % 60) + "s"
}
```

Notes for the implementer:
- `_has(_LEVELS, …)` and `_has(_RUN_WORDS, …)` are what keep `"constructor"`, `"toString"` and `"__proto__"` from resolving to inherited values; do not replace them with `in` or a plain property read.
- `_nameOf` checks `typeof id === "string"` before `_has`, so a non-string story/card id goes straight to `Runs.shortId`, which yields `"…"`.
- `_timeOf` truncates the fraction because the regex captures only the integer `HH`, `MM`, `SS` digits; do not convert `ts` to a float or a `Date`. `durationText` is the opposite: it rounds (`Math.round`) to tenths and to whole seconds, so `59.96` gives `1m 00s`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash tests/run.sh tst_run_events`
Expected: pytest all passed, then `Totals: 21 passed, 0 failed, 0 skipped`; no `TypeError`/`ReferenceError` lines; exit status 0.

- [ ] **Step 5: Run the full suite**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest all passed (including `tests/architecture/test_layers.py` and `test_icon_glyphs.py`), every `== tests/...qml` block shows `0 failed`; exit status 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/runEvents.js tests/core/domain/tst_run_events.qml
git commit -m "feat(runEvents): eventRow turns an am journal event into a timeline row"
```
<!-- task-pipeline: validated -->
