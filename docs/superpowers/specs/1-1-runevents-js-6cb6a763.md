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
