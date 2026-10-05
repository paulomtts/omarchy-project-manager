# 3.1 RunStore: dispatch state machine (card 66a6b6c0)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-dispatch-design.md` (S3,
"the parent" below): "Dispatch levels" (lines 30-41), "Flow" bullets (lines
71-85), "Architecture" bullets 4-5 (lines 108-117), "Safety" (lines 123-134),
"Errors" (lines 136-145) and "Testing" bullet 2 (lines 152-153). Parent story
3d877d1f ("Dispatch store"). Everything this card builds on is already on this
branch: `Runs.dispatchPlan` / `Runs.dispatchDefaults` (card 5eb7ec0c),
`Runs.validateDispatch` / `Runs.previewSummary` (45cc9067),
`dispatch-preview.py` (a19ca446), `start-run.py` (299ec9c0) and the dispatch
keys of `viewer-state.py get-run-settings` / `set-run-settings` (fdb5feb1).

This card is the store half only. The dialog, the entry points, the toast and
the navigation to Run detail are sibling cards 4.1 (dfc0ac87) and 4.2
(46141e11); they read and call what this card exposes.

## Starting point

- `core/stores/RunStore.qml` (1028 lines) has no dispatch code. Its conventions
  (all must be followed): scope id `store`; helpers run through `HelperRunner`
  (`core/stores/HelperRunner.qml`: one script, latest run wins, `run(args)`
  spawns `python3 <script> <args...>`, `cancel()`, `finished(stdout, exitCode,
  launchedGuard)` fires only for the newest launch whose launch guard still
  equals `guard`); test handles are `readonly property alias`es (lines 98-112);
  timers carry an `objectName`, `interval`, `repeat: false` and `onTriggered`
  (`debounceTimer`, line ~879); one JSON line is read with
  `store.parseEnvelope(text)` (line ~406: last non-blank line parsed as an
  object, else `null`); per-request runners come from a `Component` and are
  kept in a list (`controlC` / `controlRunners`, lines ~975-1000).
- `projectSwitched()` (lines 253-286) resets everything of the old project and
  reads `viewer-state.py get-run-settings ROOT` on `settingsLoadRunner`.
  `applyRunSettings` (line ~813) reads only `notifyOnEscalation` from that
  reply and returns early once `notifyTouched`.
- `stopLive()` (lines 154-163) runs when the panel closes.
- `core/domain/runs.js` (lines 778-960):
  - `dispatchPlan(card, cardMap)` → `{command, flags, level, offered, reason,
    suggest}`; `card === "board"` gives `{command: "board", flags: ["--board"],
    level: "board", offered: true}`; a milestone gives `flags: ["--milestone",
    ID]`, a subtask `command: "card"`, `flags: ["--card", ID]`; a story or a
    finished card gives `offered: false` with `reason`.
  - `dispatchDefaults({defaultBranch, settings}, card, cardMap)` →
    `{allowNoVerification: false, base, parallelism, prefix, verify}`.
  - `validateDispatch(form)` → `{ok, errors: [{field, message}]}` (prefix,
    verify, parallelism, in that order; `base` is never checked).
  - `previewSummary(dryRunData)` → `{board, integrate, summary}`.
- `core/backend/runs/dispatch-preview.py ROOT (milestone ID | board)
  [--base-branch B] [--branch-prefix P] [--max-concurrent N] [--verify CMD]...
  [--allow-no-verification]` prints am's envelope as one line;
  `dispatch-preview.py --defaults ROOT` prints `{"ok": true, "data":
  {"default_branch": B, "source": S}}` or an error envelope. Exit 0 except Usage.
- `core/backend/runs/start-run.py ROOT (milestone ID | card ID | board)` with the
  same options prints one line: `{"ok": true, pid, log, started_at, run_id: ID |
  null, message}` or `{"ok": false, error: {type, message}, log?, pid?,
  started_at?, exit_code?, log_tail?}`. It may take up to ~20 s (it polls `am
  runs`), and the `am run` it spawns survives the helper being stopped.
- `viewer-state.py get-run-settings ROOT` prints one **bare** object with every
  key: `verify`, `allowNoVerification`, `notifyOnEscalation`, `prefixHistory`
  (≤ 20 non-blank strings, newest first), `parallelism` (whole ≥ 1, default 4),
  `confirmDispatch` (default true). `set-run-settings ROOT JSON` takes any
  subset, refuses any invalid key, and prints `{"ok": true}` or an error
  envelope.

## Scope

In scope:

- `core/stores/RunStore.qml`: the dispatch state, the form, the debounced
  preview, the default-branch lookup, `dispatchStart()`, the project-switch
  guard, the `dispatchStarted` signal, persisting the used values, and keeping
  the whole `get-run-settings` reply as `runSettings`.
- `tests/core/stores/tst_run_store.qml`: new tests appended. No existing test is
  edited.
- `docs/architecture.md`: the `RunStore.qml` paragraph (line 95 block) gains
  one paragraph describing dispatch; the "Refresh model" line (165) names the
  dispatch debounce among the timers that run only while something is pending.

### Out of scope

- `ui/components/DispatchDialog.qml`, the cost warning, the "Confirm
  dispatches" extra click, Start's disabled look and the inline refusal: card
  4.1 (dfc0ac87). `confirmDispatch` is only read (it is in `runSettings`); no
  setter is added here.
- The Dispatch button, key `d`, the Runs toolbar entry, offering a story's
  milestone, the "Started — waiting for the run to appear" toast and pushing Run
  detail on `dispatchStarted`: card 4.2 (46141e11). The subtask's "card, story,
  blocked_by" display is UI too; the store's part of the explicit confirm is
  that Start is a separate call.
- `App.qml` and `Navigator` wiring (App already composes `app.runs`, line 106).
- Any change to `runs.js`, `HelperRunner.qml`, or a backend helper, and any
  pytest.
- Disabling Dispatch while am is missing (parent line 140): the UI reads the
  existing `amStatus`.
- Linking a `ClaimedError` to the other run (parent line 129): the store keeps
  the type and the verbatim message; making a link of it is UI.

## Decisions

- **D1. The caller hands the store the target.** The store only knows the
  project root, and must not import a sibling store (`docs/architecture.md`
  layering). `openDispatch(card, cardMap)` takes the brd card as
  `Board.indexTree()` leaves it (or the string `"board"`) and the `{id: card}`
  map, exactly what `Runs.dispatchPlan` / `Runs.dispatchDefaults` take. The
  target cannot be changed afterwards except by opening again.
- **D2. The form starts from `dispatchDefaults` with this project's stored
  settings.** The store keeps the last `get-run-settings` reply for the current
  project as `runSettings` (the parsed object, `{}` until a reply or when it is
  unreadable). `applyRunSettings` sets it on every reply for the current project,
  before (and independently of) its `notifyTouched` early return. A dispatch
  opened before that reply lands starts from `{}` (no verify, parallelism 4).
- **D3. Base comes from one `--defaults` lookup per opening.** Opening launches
  `dispatch-preview.py --defaults ROOT`; until it replies no preview is launched
  and the state is `previewing`. When it replies with a non-blank
  `data.default_branch` and the user has not set `base` since the opening, `base`
  becomes that branch (trimmed). Any other reply leaves `base` as it is (`""`
  unless the user typed one); a blank base is never sent, so am uses its own
  default and the preview shows the result (parent lines 75-77).
- **D4. A subtask has no preview.** am's `--dry-run` covers milestone and board
  only (parent line 35). For level `subtask`, the point where milestone and board
  launch a preview instead validates the form: valid → `ready`, else `refused`.
  The explicit confirm (parent line 125-126) is the dialog's Start click
  (card 4.2).
- **D5. The form is checked before a preview.** `Runs.validateDispatch` runs
  first; an invalid form goes to `refused` with its errors and launches nothing.
- **D6. One runner per Start, guard `""`, tied to the project it was made in.**
  `start-run.py` takes up to 20 s and must not be stopped by a preview, by a
  project switch, or by a Start in another project. Each Start creates its own
  `HelperRunner` from a `Component` (like `controlC`), with `guard: ""` and a
  `madeFor` project. After a successful start the same runner then writes the
  settings (`viewer-state.py set-run-settings`) for `madeFor`, and goes when that
  write replies (after a failed start it goes at once). A reply that is not `here` (its `madeFor` is not the current project, or the
  dispatch it started was reset by a project switch) changes nothing in the store's dispatch state,
  emits nothing and refreshes nothing; its settings write for `madeFor` still
  happens (parent line 145: "recorded against that project").
- **D7. Used values are saved only after a successful start**, as one
  `set-run-settings` write: `verify` (the non-blank commands sent), `allowNoVerification`,
  `prefixHistory` (the prefix sent, then the previous history without it, at
  most 20) and `parallelism`. The JSON is built when Start is pressed, from that
  project's `runSettings` at that moment, so a later project switch cannot mix
  projects. `confirmDispatch` and `notifyOnEscalation` are never written here.
  This write never uses `settingsSaveRunner`, so the notify switch's
  bookkeeping is untouched.
- **D8. A change while `starting` is refused**, and so is `closeDispatch()`:
  the launch takes at most ~20 s, and its outcome must land in a dialog that
  still shows the values it was started with.
- **D9. Closing the panel closes the dispatch** (like `closeDispatch()`) unless
  a start is in flight, which then lands normally. This keeps the refresh rule
  "no timers while idle" (`docs/architecture.md` line 165).

## Behaviour

### New public surface on `RunStore`

| member | type | meaning |
|---|---|---|
| `dispatchState` | string | `idle`, `previewing`, `ready`, `refused`, `starting`, `started`, `failed` |
| `dispatchTarget` | `var` | the `Runs.dispatchPlan` result for the opened target, `null` while idle |
| `dispatchForm` | `var` | `{base, prefix, verify, parallelism, allowNoVerification}`, `null` while idle; replaced, never changed in place |
| `dispatchPreview` | `var` | `Runs.previewSummary(data)` of the latest successful preview, else `null` |
| `dispatchError` | string | the sentence for `refused` / `failed`, else `""` |
| `dispatchErrorType` | string | am's or the helper's `error.type`; `"Form"` for a form refusal; `"Target"` for a target `dispatchPlan` does not offer; `""` when unknown or none |
| `dispatchErrors` | `var` | `validateDispatch` errors for a form refusal, else `[]` |
| `dispatchSuggest` | `var` | `dispatchPlan`'s `suggest` for a refused target (a story's milestone), else `null` |
| `dispatchRunId` | string | the started run's id, `""` when none (yet) |
| `dispatchMessage` | string | `start-run.py`'s `message` after a start (`"started, run not visible yet"` or `""`) |
| `dispatchLog` / `dispatchLogTail` | string | from a failed start's reply, `""` when absent |
| `dispatchExitCode` | `var` | a failed start's `exit_code` when it is a number, else `null` |
| `runSettings` | `var` | the current project's last `get-run-settings` object (D2) |
| `signal dispatchStarted(var runId)` | signal | after a successful start for the current project: the run id string, or `null` when not visible yet |
| `openDispatch(card, cardMap)` | function → bool | opens the dispatch for a target |
| `setDispatchField(name, value)` | function → bool | changes one form field |
| `dispatchStart()` | function → bool | starts the run; only from `ready` |
| `closeDispatch()` | function → bool | back to `idle` |
| `dispatchDefaultsRunner` | readonly alias | the `--defaults` HelperRunner (guard `store.project`) |
| `dispatchPreviewRunner` | readonly alias | the preview HelperRunner (guard `store.project`) |
| `dispatchDebounceTimer` | readonly alias | `objectName: "dispatchDebounceTimer"`, `interval: 400`, `repeat: false` |
| `dispatchStartRunners` | readonly alias | in-flight start runners, oldest first, each with `madeFor` and the HelperRunner API |

`idle` resets every field above except `runSettings` to its "none" value.

### openDispatch(card, cardMap)

1. No project → returns `false`, nothing changes.
2. State `starting` → returns `false`, nothing changes.
3. Any pending debounce stops; the preview and defaults runners are cancelled;
   every dispatch field is reset as for `idle`.
4. `plan = Runs.dispatchPlan(card, cardMap)`; `dispatchTarget = plan`.
   `plan.offered` false → state `refused`, `dispatchError = plan.reason`,
   `dispatchErrorType = "Target"`, `dispatchSuggest = plan.suggest`, nothing
   launched; returns `false`.
5. `dispatchForm = Runs.dispatchDefaults({defaultBranch: "", settings:
   runSettings}, card, cardMap)` (only its five keys); state `previewing`;
   launches `python3 <backendDir>runs/dispatch-preview.py --defaults ROOT`;
   returns `true`.

### Defaults reply

Dropped by the runner when the project changed. Otherwise: base set per D3.
Then the form is **checked** (below), immediately, with no debounce.

### setDispatchField(name, value)

- `name` must be one of `base`, `prefix`, `verify`, `parallelism`,
  `allowNoVerification`, and the state one of `previewing`, `ready`,
  `refused`, `failed` with a non-null `dispatchForm` (a refused target has
  none). Otherwise returns `false`, nothing changes.
- `dispatchForm` is replaced by a copy with that field set to `value` as given
  (`verify` copied as a fresh array). The store converts nothing: the UI gives
  `parallelism` as a number.
- Setting `base` marks it user-set for D3.
- State → `previewing`; `dispatchPreview`, `dispatchError`, `dispatchErrorType`,
  `dispatchErrors`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode` are
  cleared; the preview runner is cancelled (an in-flight preview's reply is
  dropped); `dispatchDebounceTimer` restarts. Returns `true`.
- Each call restarts the 400 ms timer, so a burst of changes costs one check
  (parent line 71).

### Checking the form (the debounce firing, or the defaults reply)

- While the defaults lookup is still in flight, a debounce firing does nothing;
  the defaults reply does the check.
- `Runs.validateDispatch(dispatchForm)` not ok → `refused`,
  `dispatchErrors = errors`, `dispatchError = errors[0].message`,
  `dispatchErrorType = "Form"`. Nothing launched.
- Level `subtask` → `ready` (D4).
- Milestone or board → state stays `previewing` and the preview runner runs:

```
python3 <backendDir>runs/dispatch-preview.py ROOT <target> [--base-branch B]
        --branch-prefix P --max-concurrent N [--verify CMD]... [--allow-no-verification]
```

  `<target>` is `milestone ID` or `board`. `B` is `base` trimmed, the pair left
  out when that is `""`. `P` is `prefix` trimmed. `N` is `String(parallelism)`.
  One `--verify CMD` pair per command that is a non-blank string, verbatim, in
  order. `--allow-no-verification` exactly when `allowNoVerification === true`.
  The start argv below uses the same options, built by the same function.

### Preview reply (latest wins)

Applied only when it is the newest launch, the project has not changed, and no
form change came after its launch (each change cancels the runner).

- `{"ok": true, "data": D}` → `ready`, `dispatchPreview = Runs.previewSummary(D)`.
- `{"ok": false, "error": {"type": T, "message": M}}` with `M` a non-blank
  string → `refused`, `dispatchError = M` verbatim (parent line 73-74),
  `dispatchErrorType = T` when a string, else `""`.
- Anything else (no line, not JSON, no message) → `refused`, `dispatchError =
  "The preview could not be read"`, `dispatchErrorType = ""`.

### dispatchStart()

- Only from `ready` (parent line 72, 125); anything else returns `false` and
  launches nothing.
- Builds a start runner (D6) with `madeFor = project`, state → `starting`,
  launches:

```
python3 <backendDir>runs/start-run.py ROOT <target> <the same options as the preview>
```

  `<target>` is `milestone ID`, `card ID` or `board`. Returns `true`.
- The settings JSON for D7 is built now and kept on the runner, key order
  exactly `verify`, `allowNoVerification`, `prefixHistory`, `parallelism`:
  `prefixHistory` is the trimmed prefix followed by `runSettings.prefixHistory`'s
  string entries that are non-blank and differ from it, cut to 20.

### Start reply

Let `here` be `madeFor === store.project` **and** this runner is the one that
put the store into `starting` (the store keeps that runner as the current start
runner while the state is `starting`; `projectSwitched()` and `idle` forget it).
Project A → B → A while A's start is in flight therefore leaves the first reply
not `here`: it must not overwrite a dialog the user has since opened in A.

- `{"ok": true, run_id, message}`:
  - `here`: state `started`, `dispatchRunId` = `run_id` when a non-empty string
    else `""`, `dispatchMessage` = `message` when a string else `""`;
    `runSettings` takes the four saved values; `store.refresh()`; then
    `dispatchStarted(runId)` with the id string, or `null` when
    `dispatchRunId` is `""`.
  - always: the same runner runs `python3 <backendDir>projects/viewer-state.py
    set-run-settings <madeFor> <JSON>`.
- `{"ok": false, error, ...}`: when `here`, state `failed`, `dispatchError` =
  `error.message` when a non-blank string else `"The launch could not be
  read"`, `dispatchErrorType` = `error.type` when a string else `""`,
  `dispatchLog` / `dispatchLogTail` from `log` / `log_tail` when strings,
  `dispatchExitCode` = `exit_code` when a number. Nothing saved; no signal.
- No readable envelope: as `ok: false` with `"The launch could not be read"`.
- Not `here`: nothing in the dispatch state changes, no signal, no refresh.

### Settings write reply

When `here` and the reply is not `{"ok": true}`: `flash("Dispatch settings could
not be saved")`. Otherwise nothing. The runner then goes.

### closeDispatch()

From `starting` returns `false` (D8). Otherwise: stops the debounce, cancels the
preview and defaults runners, state `idle` with every field reset; returns
`true`.

### Project switch and panel close

- `projectSwitched()` resets the dispatch exactly as `closeDispatch()` does,
  **even from `starting`**, and sets `runSettings = {}`. In-flight start
  runners are left alone (D6).
- `stopLive()` calls `closeDispatch()` (D9); from `starting` that refuses and
  the start lands normally.

## Errors

| case | behaviour |
|---|---|
| no project | `openDispatch` → `false` |
| target not offered (story, finished card, no card) | `refused`, `dispatchErrorType "Target"`, `dispatchSuggest` for a story |
| form invalid | `refused`, `dispatchErrorType "Form"`, `dispatchErrors`, nothing launched |
| `--defaults` fails (no git, detached HEAD) | base stays as it is, check proceeds |
| preview refusal | `refused`, message verbatim |
| preview unreadable | `refused`, `The preview could not be read` |
| start refusal / early exit / spawn failure | `failed` with message, log, log tail, exit code |
| start unreadable | `failed`, `The launch could not be read` |
| run not visible in 20 s | `started`, `dispatchRunId ""`, `dispatchStarted(null)` |
| project switched mid-start | old project's settings still written; new project's dispatch untouched; no signal |
| settings write fails | flash `Dispatch settings could not be saved` (current project only) |

## Tests

All in `tests/core/stores/tst_run_store.qml` (QML store tier: the store is a
QML `Scope` whose behaviour is only observable through its properties, its
signal and the stub `Process` argv, which is what this file already drives with
`makeWithProject` / `reply(proc, text, code)` / firing timers by
`triggered()`). Test data: a milestone card `{id: "m1", title: "M3 Document
runs", status: "todo", parentId: "", depth: 0}`, a story `s1` (depth 1, parent
`m1`), a subtask `t1` (depth 2, parent `s1`) and their `cardMap`. Process helpers
must reply to the settings-load runner first where `runSettings` matters.

1. `test_dispatch_starts_idle` — fresh store: state `idle`, form/target/preview
   `null`, `dispatchStart()` → `false`, `closeDispatch()` → `true`.
2. `test_open_without_project_is_refused` — `openDispatch` → `false`, no
   defaults launch.
3. `test_open_milestone_goes_previewing_and_asks_defaults` — exact argv
   `["python3", "/plugin/core/backend/runs/dispatch-preview.py", "--defaults",
   root]`; state `previewing`; form from stored settings (`verify`,
   `parallelism` from a prior get-run-settings reply), prefix `m3`.
4. `test_open_story_is_refused_with_its_milestone` — `refused`, type `Target`,
   message `A story is dispatched through its milestone`, `dispatchSuggest.id
   === "m1"`, nothing launched.
5. `test_open_done_card_is_refused` — `The card is done`.
6. `test_defaults_reply_sets_base_and_launches_preview` — exact preview argv
   with `--base-branch main --branch-prefix m3 --max-concurrent 4 --verify "uv
   run pytest"` in that order; no debounce needed.
7. `test_defaults_reply_keeps_a_user_set_base`.
8. `test_defaults_failure_sends_no_base` — no `--base-branch` pair.
9. `test_debounce_waits_for_defaults` — a change before the defaults reply, the
   timer fires: nothing launched; the defaults reply launches one preview.
10. `test_preview_ok_goes_ready_with_summary` — `previewing → ready`,
    `dispatchPreview.summary` from a recorded milestone payload.
11. `test_preview_refusal_goes_refused_verbatim` — `ClaimedError` message and
    type kept.
12. `test_preview_unreadable_goes_refused`.
13. `test_board_preview_argv` — `openDispatch("board", map)`, target `board`.
14. `test_invalid_form_is_refused_without_launch` — empty prefix: `refused`,
    type `Form`, `dispatchErrors[0].field === "prefix"`, no preview process.
15. `test_allow_no_verification_flag` — `verify []`, opt-out true → valid, argv
    ends with `--allow-no-verification`; blank verify entries are not sent.
16. `test_change_restarts_400ms_debounce_and_one_preview_per_burst` —
    `interval === 400`, three changes → one launch when the timer fires, with
    the last values; state `previewing` after each change.
17. `test_latest_preview_wins` — preview 1 in flight, a change, preview 2
    launched; reply to 1 is dropped (state stays `previewing`), reply to 2 sets
    `ready`.
18. `test_change_after_ready_drops_preview_and_goes_previewing`.
19. `test_set_unknown_field_or_while_idle_is_refused`.
20. `test_subtask_goes_ready_without_preview` — after the defaults reply:
    `ready`, no preview process, and `dispatchStart` argv uses `card t1`.
21. `test_start_refused_unless_ready` — from `previewing`, `refused`, `idle`:
    `false`, no start runner.
22. `test_start_argv_and_starting` — exact `start-run.py` argv for the
    milestone; state `starting`; `dispatchStartRunners.length === 1`.
23. `test_change_and_close_refused_while_starting`.
24. `test_start_ok_with_run_id_emits_and_saves` — state `started`,
    `dispatchRunId`, `dispatchStarted` once with `"r-1"`, a snapshot refresh is
    launched, then the same runner's exact argv `["python3",
    "/plugin/core/backend/projects/viewer-state.py", "set-run-settings", root,
    '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3","old"],"parallelism":4}']`;
    `runSettings` updated; the runner is gone after the `{"ok":true}` reply.
25. `test_start_ok_without_run_id_emits_null` — `dispatchStarted(null)`,
    `dispatchMessage "started, run not visible yet"`.
26. `test_prefix_history_dedups_and_caps_at_20`.
27. `test_start_failure_goes_failed_with_log` — early-exit reply: message,
    type, log, log tail, exit code; no signal; no settings write.
28. `test_start_unreadable_goes_failed`.
29. `test_failed_then_change_previews_again`.
30. `test_settings_write_failure_flashes`.
31. `test_project_switch_resets_dispatch_and_drops_old_preview` — a preview
    reply for A after the switch to B changes nothing; `runSettings` is `{}`.
32. `test_start_result_belongs_to_its_project` — start in A, switch to B, A's
    ok reply: B's state `idle`, no `dispatchStarted`, but the settings write
    names A's root.
32b. `test_start_reply_after_switching_away_and_back_is_not_here` — start in A,
    switch to B and back to A (state `idle`), open a new dispatch to `previewing`,
    then the first start's ok reply: state stays `previewing`, no
    `dispatchStarted`, settings still written for A.
33. `test_start_in_other_project_does_not_stop_the_first` — start in A, switch,
    start in B: both runners in `dispatchStartRunners`, A's process still
    running.
34. `test_panel_close_closes_dispatch_but_not_a_start` — `active` false from
    `ready` → `idle` and the timer stopped; from `starting` → stays and lands.
35. `test_run_settings_kept_even_after_notify_touched` — `runSettings` set from
    the reply although `notifyTouched`; `notifyOnEscalation` unchanged.

`tests/architecture` (test_layers.py, test_icon_glyphs.py) must keep passing
unchanged: the store gains no import. Verification: `bash tests/run.sh` green.

---

# 3.1 RunStore dispatch state machine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `RunStore` the dispatch state machine — open a target, edit a debounced form, preview it with `dispatch-preview.py`, start it with `start-run.py`, and save the used values — so the dialog (card 4.1) and the entry points (card 4.2) only read properties and call functions.

**Architecture:** Everything lives in `core/stores/RunStore.qml` beside the existing run controls: two project-guarded `HelperRunner`s (the `--defaults` lookup and the preview), one 400 ms one-shot `Timer`, a private `QtObject` (`dispatchBook`) for bookkeeping, and one `HelperRunner` per Start made from a `Component` with `guard: ""` and `madeFor` (the `controlC` pattern). The pure decisions (`dispatchPlan`, `dispatchDefaults`, `validateDispatch`, `previewSummary`) already exist in `core/domain/runs.js` and are only called.

**Tech Stack:** QML (Qt 6, Quickshell `Scope`/`Process` stubs in `tests/stubs`), QtTest via `qmltestrunner`, plain JS.

**Spec:** `docs/superpowers/specs/3-1-runstore-dispatch-66a6b6c0.md` (reproduced above this line).

## Global Constraints

- `core/stores/RunStore.qml` keeps exactly its imports: `QtQml`, `Quickshell`, `Quickshell.Io`, `"../domain/runs.js" as Runs`. No new import (`tests/architecture/test_layers.py` must pass unchanged).
- Not touched: `core/domain/runs.js`, `core/stores/HelperRunner.qml`, any backend helper, `App.qml`, any UI file, any pytest. No existing test in `tests/core/stores/tst_run_store.qml` is edited; new tests are appended before the file's final `}`.
- Store conventions: scope id `store`; test handles are `readonly property alias`; timers carry `objectName`, `interval`, `repeat: false`, `onTriggered`; one JSON line is read with `store.parseEnvelope(text)`; per-request runners come from a `Component` and live in a list.
- `dispatchDebounceTimer`: `objectName: "dispatchDebounceTimer"`, `interval: 400`, `repeat: false`.
- Sentences, verbatim: `The preview could not be read`, `The launch could not be read`, `Dispatch settings could not be saved`.
- Settings write JSON key order exactly `verify`, `allowNoVerification`, `prefixHistory`, `parallelism`; `prefixHistory` at most 20; `confirmDispatch` and `notifyOnEscalation` are never written by dispatch; dispatch never uses `settingsSaveRunner`.
- Argv: `python3 <backendDir>runs/dispatch-preview.py --defaults ROOT`; `python3 <backendDir>runs/dispatch-preview.py ROOT <target> [--base-branch B] --branch-prefix P --max-concurrent N [--verify CMD]... [--allow-no-verification]`; `python3 <backendDir>runs/start-run.py ROOT <target> <same options>`; `python3 <backendDir>projects/viewer-state.py set-run-settings <madeFor> <JSON>`.
- Verification: `bash tests/run.sh` green.

## Review Focus

1. A verify command that starts with `-` or contains spaces must reach the helper as one verbatim argv item after `--verify` (am would otherwise read it as a flag or split it) — Task 4, `test_allow_no_verification_flag`.
2. A default-branch lookup that fails, is unreadable, returns a blank or non-string `default_branch`, or a branch padded with whitespace: base is trimmed, and a blank base sends no `--base-branch` pair — Task 3, `test_defaults_failure_sends_no_base`.
3. A double click on Start: the second `dispatchStart()` while `starting` returns `false` and launches nothing — Task 5, `test_start_refused_unless_ready`.
4. Values of the wrong type (a `verify` that is not a list, `parallelism` given as a string, an unreadable settings reply) are refused or ignored without a throw, and the saved history is then just the prefix — Task 4, `test_a_verify_value_that_is_not_a_list_is_refused_not_thrown`; Task 5, `test_prefix_history_dedups_and_caps_at_20`.
5. A start reply whose `run_id` is not a non-empty string, whose `exit_code` is not a number or whose `log_tail` is not a string: `dispatchStarted(null)`, `dispatchExitCode` `null`, `dispatchLogTail` `""` — Task 5, `test_start_ok_without_run_id_emits_null` and `test_start_unreadable_goes_failed`.

## File Structure

- Modify `core/stores/RunStore.qml` — all dispatch state, functions, runners, timer and the start `Component`. Functions go in one new `// ---- dispatch (S3 3.1)` section placed directly before the `// The guard is the project root, so a snapshot launched for a project the` comment (above `HelperRunner { id: snapshotRunner`); every task appends its functions at that same spot, so they stay in task order.
- Modify `tests/core/stores/tst_run_store.qml` — new tests appended (each task's block goes immediately before the file's last line, the closing `}` of `TestCase`).
- Modify `docs/architecture.md` — one new paragraph in the `RunStore.qml` block and one clause in the "Refresh model" line.

## How to run tests

From the worktree root, one test file, fast:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml
```

Append `StoresRunStore::test_name` (one or more) to run single functions. The whole suite: `bash tests/run.sh`. Existing test helpers in this file you will reuse: `make()`, `makeWithProject(root)`, `reply(proc, text, code)` (sets `outText`, emits `exited`), `argv(proc)` (`command.join("|")`), `fire(timer)` (stops a one-shot then emits `triggered()`), `activeStore(root)`, `ctlFail(type, message)` (an `{ok:false,error:{type,message}}` line), the `spyC` SignalSpy component, and the properties `tc.rootA` (`"/home/u/my proj"`), `tc.rootB` (`"/home/u/b"`), `tc.viewerCmd` (`"python3|/plugin/core/backend/projects/viewer-state.py|"`).

---

### Task 1: `runSettings` keeps the whole `get-run-settings` reply

**Files:**
- Modify: `core/stores/RunStore.qml` (property block line ~96, `projectSwitched()` lines 253-286, `applyRunSettings` lines 811-819)
- Test: `tests/core/stores/tst_run_store.qml` (append)

**Interfaces:**
- Consumes: `store.parseEnvelope(text)` → object or `null` (existing).
- Produces: `property var runSettings` — the current project's last parsed `get-run-settings` object, `{}` until a reply, when unreadable and after a project switch. Test fixtures `tc.previewCmd`, `tc.startCmd`, `dispatchSettings()` used by every later task.

- [ ] **Step 1: Write the failing tests**

Append before the final `}` of `tests/core/stores/tst_run_store.qml`:

```qml

  // ---- dispatch (S3 3.1)

  property string previewCmd: "python3|/plugin/core/backend/runs/dispatch-preview.py|"
  property string startCmd: "python3|/plugin/core/backend/runs/start-run.py|"

  // get-run-settings with every key, as viewer-state.py prints it.
  function dispatchSettings() {
    return JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false, notifyOnEscalation: false,
                            prefixHistory: ["old"], parallelism: 4, confirmDispatch: true }) + "\n"
  }

  // 35
  function test_run_settings_kept_even_after_notify_touched() {
    var store = makeWithProject(rootA); if (!store) return
    compare(Object.keys(store.runSettings).length, 0, "{} until the reply")
    var load = store.settingsLoadRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, dispatchSettings(), 0)
    compare(store.notifyOnEscalation, true, "the switch keeps the user's value")
    compare(store.runSettings.prefixHistory.length, 1)
    compare(store.runSettings.prefixHistory[0], "old")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.confirmDispatch, true)
    compare(store.runSettings.verify[0], "uv run pytest")
    compare(store.runSettings.notifyOnEscalation, false, "the object is kept as it was read")
  }

  function test_run_settings_follow_the_project() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    compare(store.runSettings.parallelism, 4)
    store.project = rootB
    compare(Object.keys(store.runSettings).length, 0, "a project switch forgets A's settings")
    reply(store.settingsLoadRunner.current, "Traceback: boom\n", 1)
    compare(Object.keys(store.runSettings).length, 0, "an unreadable reply is {}")
    var other = makeWithProject(rootA); if (!other) return
    reply(other.settingsLoadRunner.current, JSON.stringify({ parallelism: 9 }) + "\n", 0)
    compare(other.runSettings.parallelism, 9)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_run_settings_kept_even_after_notify_touched StoresRunStore::test_run_settings_follow_the_project`
Expected: FAIL — `TypeError: Cannot call method 'keys' of undefined` or `Object.keys` on `undefined` (no `runSettings` property).

- [ ] **Step 3: Implement**

In `core/stores/RunStore.qml`, replace

```qml
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
```

with

```qml
  property bool notifyOnEscalation: false
  property bool notifySaved: false
  property bool notifyTouched: false
  // The current project's last get-run-settings object, as it was read: {}
  // until its reply, when the reply is unreadable, and after a project switch.
  // The dispatch form starts from it.
  property var runSettings: ({})
```

In `projectSwitched()`, replace

```js
    store.notifyOnEscalation = false
    store.notifySaved = false
    store.notifyTouched = false
    settingsLoadRunner.guard = store.project
```

with

```js
    store.notifyOnEscalation = false
    store.notifySaved = false
    store.notifyTouched = false
    store.runSettings = {}
    settingsLoadRunner.guard = store.project
```

Replace the whole `applyRunSettings` function (and its comment)

```js
  // get-run-settings: one bare object. Only a real true turns the switch on;
  // an unreadable reply leaves it off. Too late once the user changed it.
  function applyRunSettings(stdout, exitCode) {
    if (store.notifyTouched) return
    var settings = store.parseEnvelope(stdout)
    var on = settings !== null && settings.notifyOnEscalation === true
```

with

```js
  // get-run-settings: one bare object, kept whole as runSettings ({} when
  // unreadable) on every reply. Only a real true turns the switch on; an
  // unreadable reply leaves it off. Too late for the switch once the user
  // changed it.
  function applyRunSettings(stdout, exitCode) {
    var settings = store.parseEnvelope(stdout)
    store.runSettings = settings !== null ? settings : {}
    if (store.notifyTouched) return
    var on = settings !== null && settings.notifyOnEscalation === true
```

(the two lines after it, `store.notifyOnEscalation = on` and `store.notifySaved = on`, stay.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml`
Expected: PASS, every test in the file (`Totals: N passed, 0 failed`).

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "RunStore.qml: keeps the whole get-run-settings reply as runSettings (S3 3.1)"
```

---

### Task 2: dispatch state, `openDispatch`, `closeDispatch`

**Files:**
- Modify: `core/stores/RunStore.qml` (properties after `runSettings`; aliases after `notifyRunners`; new functions section; two runners, one timer, one `QtObject`)
- Test: `tests/core/stores/tst_run_store.qml` (append)

**Interfaces:**
- Consumes: `Runs.dispatchPlan(card, cardMap)` → `{command, flags, level, offered, reason, suggest}`; `Runs.dispatchDefaults({defaultBranch, settings}, card, cardMap)` → `{allowNoVerification, base, parallelism, prefix, verify}`; `runSettings` (Task 1).
- Produces: properties `dispatchState`, `dispatchTarget`, `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchErrorType`, `dispatchErrors`, `dispatchSuggest`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail`, `dispatchExitCode`; `signal dispatchStarted(var runId)`; `openDispatch(card, cardMap)` → bool; `closeDispatch()` → bool; `resetDispatch()`; `clearDispatchError()`; aliases `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`, `dispatchStartRunners`; private `dispatchBook { runners, startRunner, baseTouched, defaultsPending }`. Test helpers `dispatchCards()`, `dispatchStore()`, `checkDispatchIdle(store, label)`.

- [ ] **Step 1: Write the failing tests**

Append before the final `}`:

```qml

  // A milestone, its story, the story's subtask and a done milestone, as
  // Board.indexTree() leaves them; the object is also their {id: card} map.
  function dispatchCards() {
    return {
      m1: { id: "m1", title: "M3 Document runs", status: "todo", parentId: "", depth: 0 },
      s1: { id: "s1", title: "Dispatch store", status: "todo", parentId: "m1", depth: 1 },
      t1: { id: "t1", title: "RunStore dispatch", status: "todo", parentId: "s1", depth: 2 },
      d1: { id: "d1", title: "M2 Monitor runs", status: "done", parentId: "", depth: 0 }
    }
  }

  // Project A with its run settings read (dispatchSettings).
  function dispatchStore() {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    return store
  }

  // Every dispatch field at its "none" value.
  function checkDispatchIdle(store, label) {
    compare(store.dispatchState, "idle", label + ": state")
    compare(store.dispatchTarget, null, label + ": target")
    compare(store.dispatchForm, null, label + ": form")
    compare(store.dispatchPreview, null, label + ": preview")
    compare(store.dispatchError, "", label + ": error")
    compare(store.dispatchErrorType, "", label + ": error type")
    compare(store.dispatchErrors.length, 0, label + ": errors")
    compare(store.dispatchSuggest, null, label + ": suggest")
    compare(store.dispatchRunId, "", label + ": run id")
    compare(store.dispatchMessage, "", label + ": message")
    compare(store.dispatchLog, "", label + ": log")
    compare(store.dispatchLogTail, "", label + ": log tail")
    compare(store.dispatchExitCode, null, label + ": exit code")
  }

  // 1 (dispatchStart() from idle is checked in Task 5's test 21)
  function test_dispatch_starts_idle() {
    var store = make(); if (!store) return
    checkDispatchIdle(store, "fresh")
    compare(store.dispatchStartRunners.length, 0)
    compare(store.dispatchDebounceTimer.running, false)
    verify(!store.dispatchDefaultsRunner.current)
    verify(!store.dispatchPreviewRunner.current)
    compare(store.closeDispatch(), true, "closing an idle dispatch is fine")
    checkDispatchIdle(store, "after close")
  }

  // 2
  function test_open_without_project_is_refused() {
    var store = make(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), false)
    checkDispatchIdle(store, "no project")
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")
  }

  // 3
  function test_open_milestone_goes_previewing_and_asks_defaults() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, JSON.stringify({ verify: ["uv run pytest", "  "], allowNoVerification: true,
      notifyOnEscalation: false, prefixHistory: [], parallelism: 6, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTarget.command, "milestone")
    var proc = store.dispatchDefaultsRunner.current
    verify(proc, "the default branch is looked up")
    compare(proc.command.length, 4)
    compare(argv(proc), tc.previewCmd + "--defaults|/home/u/my proj")
    compare(proc.command[3], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.base, "", "no base until the lookup replies")
    compare(form.prefix, "m3")
    compare(form.verify.length, 1, "the stored non-blank commands")
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 6)
    compare(form.allowNoVerification, false, "the opt-out is never pre-ticked")
    verify(!store.dispatchPreviewRunner.current, "no preview before the default branch is known")
    compare(store.dispatchDebounceTimer.running, false)
  }

  function test_open_before_the_settings_reply_starts_from_nothing() {
    var store = makeWithProject(rootA); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.verify.length, 0)
    compare(store.dispatchForm.parallelism, 4)
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    compare(store.dispatchForm.verify.length, 0, "a late settings reply does not touch the open form")
    compare(store.runSettings.verify[0], "uv run pytest", "but it is kept for the next opening")
  }

  // 4
  function test_open_story_is_refused_with_its_milestone() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.s1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchError, "A story is dispatched through its milestone")
    compare(store.dispatchSuggest.id, "m1")
    compare(store.dispatchSuggest.title, "M3 Document runs")
    compare(store.dispatchTarget.level, "story")
    compare(store.dispatchForm, null, "a refused target has no form")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
    verify(!store.dispatchPreviewRunner.current)
  }

  // 5
  function test_open_done_card_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.d1, cards), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchSuggest, null)
    compare(store.openDispatch(null, cards), false)
    compare(store.dispatchError, "No card to dispatch")
    verify(!store.dispatchDefaultsRunner.current, "nothing launched")
  }

  function test_close_and_reopen_drop_the_pending_lookup() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var first = store.dispatchDefaultsRunner.current
    compare(store.closeDispatch(), true)
    checkDispatchIdle(store, "closed")
    compare(first.running, false, "the lookup is stopped")
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchState, "refused")
    compare(store.openDispatch(cards.m1, cards), true, "opening again replaces a refused target")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchSuggest, null)
    verify(store.dispatchDefaultsRunner.current !== first, "a fresh lookup per opening")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_dispatch_starts_idle StoresRunStore::test_open_milestone_goes_previewing_and_asks_defaults StoresRunStore::test_open_story_is_refused_with_its_milestone`
Expected: FAIL — `dispatchState` is `undefined` / `TypeError: Property 'openDispatch' of object ... is not a function`.

- [ ] **Step 3: Implement the properties**

In `core/stores/RunStore.qml`, directly after the `property var runSettings: ({})` line (Task 1), insert:

```qml

  // Dispatch (S3 3.1): starting an am run. The UI opens it for a target
  // (openDispatch), edits the form (setDispatchField) and presses Start
  // (dispatchStart); the store checks the form, previews it with
  // dispatch-preview.py and starts it with start-run.py. `dispatchState` is
  // idle | previewing | ready | refused | starting | started | failed. Every
  // object here is replaced, never changed in place.
  property string dispatchState: "idle"
  property var dispatchTarget: null     // Runs.dispatchPlan of the opened target; null while idle
  property var dispatchForm: null       // {base, prefix, verify, parallelism, allowNoVerification}; null while idle
  property var dispatchPreview: null    // Runs.previewSummary of the latest good preview
  property string dispatchError: ""     // the sentence for refused / failed
  property string dispatchErrorType: "" // am's or the helper's error.type, "Form", "Target" or ""
  property var dispatchErrors: []       // Runs.validateDispatch errors of a form refusal
  property var dispatchSuggest: null    // a refused story's milestone {id, title}
  property string dispatchRunId: ""     // the started run's id; "" when none (yet)
  property string dispatchMessage: ""   // start-run.py's message after a start
  property string dispatchLog: ""       // a failed start's log path
  property string dispatchLogTail: ""   // the end of that log
  property var dispatchExitCode: null   // a failed start's exit code, when a number
  // A start for the current project went: the run id, or null while am does
  // not list it yet.
  signal dispatchStarted(var runId)
```

After the line `  readonly property alias notifyRunners: notifyState.runners    // in-flight notify.py launches, oldest first` insert:

```qml
  readonly property alias dispatchDefaultsRunner: dispatchDefaultsRunner
  readonly property alias dispatchPreviewRunner: dispatchPreviewRunner
  readonly property alias dispatchDebounceTimer: dispatchDebounceTimer
  readonly property alias dispatchStartRunners: dispatchBook.runners // in-flight start runners, oldest first
```

- [ ] **Step 4: Implement the functions**

Directly before the line `  // The guard is the project root, so a snapshot launched for a project the` insert:

```js
  // ---- dispatch (S3 3.1)

  // No refusal or failure to show.
  function clearDispatchError() {
    store.dispatchError = ""
    store.dispatchErrorType = ""
    store.dispatchErrors = []
    store.dispatchLog = ""
    store.dispatchLogTail = ""
    store.dispatchExitCode = null
  }

  // Every dispatch field back to its "none" value; runSettings stays. The
  // pending check, the preview and the defaults lookup are dropped; a start
  // already launched runs on, but its reply is no longer this dispatch's.
  function resetDispatch() {
    dispatchDebounceTimer.stop()
    dispatchPreviewRunner.cancel()
    dispatchDefaultsRunner.cancel()
    dispatchBook.startRunner = null
    dispatchBook.baseTouched = false
    dispatchBook.defaultsPending = false
    store.dispatchState = "idle"
    store.dispatchTarget = null
    store.dispatchForm = null
    store.dispatchPreview = null
    store.clearDispatchError()
    store.dispatchSuggest = null
    store.dispatchRunId = ""
    store.dispatchMessage = ""
  }

  // Opens the dispatch for a brd card (as Board.indexTree() leaves it) or
  // "board", with its {id: card} map, and returns whether it may be started.
  // Refused (false, nothing changes) without a project or while a start is in
  // flight. A target dispatchPlan does not offer is `refused` at once; any
  // other starts from dispatchDefaults with this project's runSettings and
  // looks up the default branch before anything is checked.
  function openDispatch(card, cardMap) {
    if (store.project === "" || store.dispatchState === "starting") return false
    store.resetDispatch()
    var plan = Runs.dispatchPlan(card, cardMap)
    store.dispatchTarget = plan
    if (!plan.offered) {
      store.dispatchState = "refused"
      store.dispatchError = plan.reason
      store.dispatchErrorType = "Target"
      store.dispatchSuggest = plan.suggest
      return false
    }
    var d = Runs.dispatchDefaults({ defaultBranch: "", settings: store.runSettings }, card, cardMap)
    store.dispatchForm = { base: d.base, prefix: d.prefix, verify: d.verify, parallelism: d.parallelism,
                           allowNoVerification: d.allowNoVerification }
    store.dispatchState = "previewing"
    dispatchBook.defaultsPending = true
    dispatchDefaultsRunner.run(["--defaults", store.project])
    return true
  }

  // Back to idle. Refused while a start is in flight: its outcome must land in
  // a dialog that still shows what was started.
  function closeDispatch() {
    if (store.dispatchState === "starting") return false
    store.resetDispatch()
    return true
  }

```

- [ ] **Step 5: Implement the runners, the timer and the bookkeeping**

Directly before the line `  // A burst of changed lines costs one snapshot.` insert:

```qml
  // dispatch-preview.py --defaults, once per opening. Guarded by the project:
  // a reply for a project the user has left is dropped. No onGuardChanged:
  // the snapshot runner's already runs projectSwitched().
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
  }

  // The dispatch preview; latest wins, and every form change cancels it.
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
  }

```

Directly before the line `  // What the watch Process aliases read; kept apart so consumers cannot write it.` insert:

```qml
  // A burst of dispatch form changes costs one check (and one preview). Runs
  // only while a change waits to be checked.
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
  }

```

Directly before the line `  // One HelperRunner per control request, so requests for different runs never` insert:

```qml
  // The dispatch's own bookkeeping; kept apart so consumers cannot write it.
  // `startRunner` is the runner that put the store into `starting`, forgotten
  // by an idle reset (and so by a project switch); `baseTouched` says the user
  // set base since the opening; `defaultsPending` that the --defaults lookup
  // has not replied yet.
  QtObject {
    id: dispatchBook
    property var runners: []
    property var startRunner: null
    property bool baseTouched: false
    property bool defaultsPending: false
  }

```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml`
Expected: PASS, `0 failed`, and no `TypeError` / `ReferenceError` lines in the output.

- [ ] **Step 7: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "RunStore.qml: openDispatch and closeDispatch, with the dispatch state and its defaults lookup (S3 3.1)"
```

---

### Task 3: the defaults reply, the form check and the preview

**Files:**
- Modify: `core/stores/RunStore.qml` (dispatch functions section; the two runners from Task 2)
- Test: `tests/core/stores/tst_run_store.qml` (append)

**Interfaces:**
- Consumes: Task 2's state, `dispatchBook`, runners; `Runs.validateDispatch(form)` → `{ok, errors:[{field,message}]}`; `Runs.previewSummary(data)` → `{board, integrate, summary}`; `store.copyMap(map)` (existing).
- Produces: `withField(form, name, value)` → new form; `checkDispatch()`; `dispatchTargetArgs()` → `["milestone", ID]` | `["card", ID]` | `["board"]`; `dispatchCommands(form)` → non-blank string commands; `dispatchOptionArgs()` → option argv; `dispatchDefaultsReplied(stdout)`; `dispatchPreviewReplied(stdout)`. Test helpers `defaultsOk(branch)`, `previewOk(data)`, `dispatchDryRun()`, `previewingStore()`, `tc.previewArgs`.

- [ ] **Step 1: Write the failing tests**

Append before the final `}`:

```qml

  function defaultsOk(branch) {
    return JSON.stringify({ ok: true, data: { default_branch: branch, source: "origin/HEAD" } }) + "\n"
  }

  function previewOk(data) { return JSON.stringify({ ok: true, data: data }) + "\n" }

  // `am run --milestone m1 --dry-run` data: 2 levels, 3 subtasks, 1 story already done.
  function dispatchDryRun() {
    return {
      max_concurrent: 4,
      levels: [
        { level: 0, concurrent: 1, stories: [{ story: "s1", title: "Dispatch store", root: "main", subtasks: [
          { id: "t1", title: "RunStore dispatch", status: "todo", branch: "m3-t1", base: "main" },
          { id: "t2", title: "Docs", status: "todo", branch: "m3-t2", base: "m3-t1" }] }] },
        { level: 1, concurrent: 1, stories: [{ story: "s2", title: "Dialog", root: "m3-s2", subtasks: [
          { id: "t3", title: "Dialog", status: "todo", branch: "m3-t3", base: "m3-s2" }] }] }
      ],
      already_done: [{ kind: "story", id: "s0", title: "Done story" }],
      integrate: { branch: "m3-integrate", worktree: "/repo/.worktrees/m3-integrate", order: [] }
    }
  }

  // Project A with milestone m1 opened and its default branch `main` read: the
  // first preview is in flight.
  function previewingStore() {
    var store = dispatchStore(); if (!store) return null
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    return store
  }

  property string previewArgs: "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest"

  // 6
  function test_defaults_reply_sets_base_and_launches_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchDebounceTimer.running, false, "the check runs at once, no debounce")
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "a preview was launched")
    compare(argv(proc), tc.previewCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.command[2], "/home/u/my proj", "the root with a space is one argument")
    compare(proc.command[12], "uv run pytest", "a command with spaces is one argument")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  // 8 + Review Focus 2
  function test_defaults_failure_sends_no_base() {
    var replies = [JSON.stringify({ ok: false, error: { type: "NoDefaultBranch", message: "detached HEAD" } }) + "\n",
                   "Traceback: boom\n",
                   defaultsOk("   "),
                   JSON.stringify({ ok: true, data: { default_branch: null, source: "" } }) + "\n",
                   JSON.stringify({ ok: true }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      store.openDispatch(cards.m1, cards)
      reply(store.dispatchDefaultsRunner.current, replies[i], 1)
      compare(store.dispatchForm.base, "", "reply " + i + " leaves base blank")
      var proc = store.dispatchPreviewRunner.current
      verify(proc, "reply " + i + ": the check still runs")
      compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest",
              "reply " + i + ": no --base-branch pair")
    }
    var padded = dispatchStore(); if (!padded) return
    var map = dispatchCards()
    padded.openDispatch(map.m1, map)
    reply(padded.dispatchDefaultsRunner.current, defaultsOk("  main \n"), 0)
    compare(padded.dispatchForm.base, "main", "the branch is trimmed")
    compare(padded.dispatchPreviewRunner.current.command[6], "main")
  }

  // 10
  function test_preview_ok_goes_ready_with_summary() {
    var store = previewingStore(); if (!store) return
    compare(store.dispatchPreview, null)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done")
    compare(store.dispatchPreview.integrate, "Integrate → m3-integrate")
    compare(store.dispatchPreview.board, false)
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
  }

  // 11
  function test_preview_refusal_goes_refused_verbatim() {
    var store = previewingStore(); if (!store) return
    var message = "milestone m1 is claimed by run 20261005T010000Z-abcd (pid 77)"
    reply(store.dispatchPreviewRunner.current, ctlFail("ClaimedError", message), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, message, "am's sentence, verbatim")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchPreview, null)
    var untyped = previewingStore(); if (!untyped) return
    reply(untyped.dispatchPreviewRunner.current,
          JSON.stringify({ ok: false, error: { type: 7, message: "dependency cycle: s1 -> s2 -> s1" } }) + "\n", 0)
    compare(untyped.dispatchState, "refused")
    compare(untyped.dispatchError, "dependency cycle: s1 -> s2 -> s1")
    compare(untyped.dispatchErrorType, "", "a type that is not a string is unknown")
  }

  // 12
  function test_preview_unreadable_goes_refused() {
    var replies = ["", "Traceback: boom\n", "[1, 2]\n",
                   JSON.stringify({ ok: false, error: { type: "X", message: "  " } }) + "\n",
                   JSON.stringify({ ok: false, error: "boom" }) + "\n",
                   JSON.stringify({ ok: false, error: null }) + "\n",
                   JSON.stringify({ ok: "yes" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = previewingStore(); if (!store) return
      reply(store.dispatchPreviewRunner.current, replies[i], 1)
      compare(store.dispatchState, "refused", "reply " + i)
      compare(store.dispatchError, "The preview could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchPreview, null, "reply " + i)
    }
  }

  // 14
  function test_invalid_form_is_refused_without_launch() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch("board", cards), true)
    compare(store.dispatchTarget.level, "board")
    compare(store.dispatchForm.prefix, "", "the board has no milestone title to stem")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Form")
    compare(store.dispatchErrors.length, 1)
    compare(store.dispatchErrors[0].field, "prefix")
    compare(store.dispatchError, "Enter a branch prefix")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  // 20 (the preview half)
  function test_subtask_goes_ready_without_preview() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), true)
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "m3", "the stem of the subtask's milestone")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview, null, "am has no dry run for one card")
    verify(!store.dispatchPreviewRunner.current, "no preview process")
  }

  function test_a_closed_dispatch_drops_the_late_defaults_reply() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    var lookup = store.dispatchDefaultsRunner.current
    store.closeDispatch()
    reply(lookup, defaultsOk("main"), 0)
    checkDispatchIdle(store, "after the late reply")
    verify(!store.dispatchPreviewRunner.current, "no preview")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_defaults_reply_sets_base_and_launches_preview StoresRunStore::test_preview_ok_goes_ready_with_summary`
Expected: FAIL — `dispatchForm.base` is `""` not `"main"`, and `dispatchPreviewRunner.current` is null (nobody handles the defaults reply yet).

- [ ] **Step 3: Implement the functions**

Append to the dispatch section, i.e. directly before the line `  // The guard is the project root, so a snapshot launched for a project the`:

```js
  // A copy of the form with one field set as given; verify is copied as a
  // fresh array when it is one. The store converts nothing else.
  function withField(form, name, value) {
    var next = store.copyMap(form)
    next[name] = name === "verify" && Array.isArray(value) ? value.slice() : value
    return next
  }

  // The helpers' target words: milestone ID, card ID or board.
  function dispatchTargetArgs() {
    var plan = store.dispatchTarget
    return plan.command === "board" ? ["board"] : [plan.command, plan.flags[1]]
  }

  // The form's verify commands that are non-blank strings, verbatim, in order.
  function dispatchCommands(form) {
    var list = Array.isArray(form.verify) ? form.verify : []
    return list.filter(function(c) { return typeof c === "string" && c.trim() !== "" })
  }

  // The options the preview and the start share. A blank base is left out, so
  // am uses its own default; each verify command is one argument.
  function dispatchOptionArgs() {
    var form = store.dispatchForm
    var args = []
    var base = typeof form.base === "string" ? form.base.trim() : ""
    if (base !== "") args.push("--base-branch", base)
    args.push("--branch-prefix", form.prefix.trim(), "--max-concurrent", String(form.parallelism))
    var commands = store.dispatchCommands(form)
    for (var i = 0; i < commands.length; i++) args.push("--verify", commands[i])
    if (form.allowNoVerification === true) args.push("--allow-no-verification")
    return args
  }

  // The --defaults reply: a non-blank default branch becomes base unless the
  // user set base since the opening; anything else leaves base as it is.
  // Then the form is checked at once.
  function dispatchDefaultsReplied(stdout) {
    if (!dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
    dispatchBook.defaultsPending = false
    var envelope = store.parseEnvelope(stdout)
    var data = envelope !== null && envelope.ok === true ? envelope.data : null
    var branch = data !== null && typeof data === "object" && typeof data.default_branch === "string"
        ? data.default_branch.trim() : ""
    if (branch !== "" && !dispatchBook.baseTouched) store.dispatchForm = store.withField(store.dispatchForm, "base", branch)
    store.checkDispatch()
  }

  // The form is checked: an invalid one is refused and launches nothing, a
  // subtask is ready (am has no dry run for one card), a milestone or the
  // board is previewed. Waits for the defaults lookup, whose reply checks.
  function checkDispatch() {
    if (dispatchBook.defaultsPending || store.dispatchState !== "previewing") return
    dispatchDebounceTimer.stop()
    var result = Runs.validateDispatch(store.dispatchForm)
    if (!result.ok) {
      store.dispatchState = "refused"
      store.dispatchErrors = result.errors
      store.dispatchError = result.errors[0].message
      store.dispatchErrorType = "Form"
      return
    }
    if (store.dispatchTarget.level === "subtask") {
      store.dispatchState = "ready"
      return
    }
    dispatchPreviewRunner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
  }

  // The newest preview's reply for this project and these values (a form
  // change cancels the runner). ok: ready with its summary; am's refusal:
  // its message verbatim; anything else cannot be read.
  function dispatchPreviewReplied(stdout) {
    if (store.dispatchState !== "previewing") return
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      store.dispatchPreview = Runs.previewSummary(envelope.data)
      store.dispatchState = "ready"
      return
    }
    var err = envelope !== null && envelope.ok === false ? envelope.error : null
    var message = err !== null && typeof err === "object" && typeof err.message === "string" ? err.message : ""
    store.dispatchState = "refused"
    if (message.trim() !== "") {
      store.dispatchError = message
      store.dispatchErrorType = typeof err.type === "string" ? err.type : ""
    } else {
      store.dispatchError = "The preview could not be read"
      store.dispatchErrorType = ""
    }
  }

```

- [ ] **Step 4: Wire the runners' replies**

Replace

```qml
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
  }
```

with

```qml
  HelperRunner {
    id: dispatchDefaultsRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchDefaultsReplied(stdout) }
  }
```

and replace

```qml
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
  }
```

with

```qml
  HelperRunner {
    id: dispatchPreviewRunner
    script: store.backendDir + "runs/dispatch-preview.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.dispatchPreviewReplied(stdout) }
  }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml`
Expected: PASS, `0 failed`, no `TypeError` lines.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "RunStore.qml: the default branch, the form check and the dispatch preview (S3 3.1)"
```

---

### Task 4: `setDispatchField` and the 400 ms debounce

**Files:**
- Modify: `core/stores/RunStore.qml` (dispatch functions section; `dispatchDebounceTimer`)
- Test: `tests/core/stores/tst_run_store.qml` (append)

**Interfaces:**
- Consumes: `withField`, `checkDispatch`, `clearDispatchError`, `dispatchBook.baseTouched` (Tasks 2-3).
- Produces: `setDispatchField(name, value)` → bool; the debounce firing calls `checkDispatch()`.

- [ ] **Step 1: Write the failing tests**

Append before the final `}`:

```qml

  // 7
  function test_defaults_reply_keeps_a_user_set_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("base", "develop"), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "develop", "the user's base wins over the lookup")
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|develop|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
  }

  // 9
  function test_debounce_waits_for_defaults() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("prefix", "m3b"), true)
    compare(store.dispatchDebounceTimer.running, true)
    fire(store.dispatchDebounceTimer)
    verify(!store.dispatchPreviewRunner.current, "nothing launched before the default branch is known")
    compare(store.dispatchState, "previewing")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the defaults reply checks the form")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3b|--max-concurrent|4|--verify|uv run pytest")

    var early = dispatchStore(); if (!early) return
    early.openDispatch(cards.m1, cards)
    early.setDispatchField("parallelism", 2)
    reply(early.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(early.dispatchDebounceTimer.running, false, "the defaults reply's check replaces the pending one")
    compare(early.dispatchPreviewRunner.current.command[10], "2")
  }

  // 13
  function test_board_preview_argv() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch("board", cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "refused", "the board starts with no prefix")
    compare(store.setDispatchField("prefix", " all "), true)
    fire(store.dispatchDebounceTimer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the board is previewed")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|board|--base-branch|main|--branch-prefix|all|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 12)
    var board = { board: true, levels: [{ level: 0, milestones: [{ milestone_id: "m1", title: "M3", branch_prefix: "m3",
                                                                   base_branch: "main", plan: dispatchDryRun() }] }] }
    reply(proc, previewOk(board), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchPreview.summary, "1 milestone, 3 subtasks")
    compare(store.dispatchPreview.board, true)
  }

  // 15 + Review Focus 1
  function test_allow_no_verification_flag() {
    var store = previewingStore(); if (!store) return
    store.setDispatchField("verify", [])
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "no command and no opt-out")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "previewing")
    var proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--allow-no-verification")
    store.setDispatchField("verify", ["", "  ", "-x make check", "uv run pytest"])
    fire(store.dispatchDebounceTimer)
    proc = store.dispatchPreviewRunner.current
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|-x make check|--verify|uv run pytest|--allow-no-verification")
    compare(proc.command[12], "-x make check", "a command that starts with a dash is one verbatim argument")
    store.setDispatchField("allowNoVerification", "yes")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchPreviewRunner.current.command[store.dispatchPreviewRunner.current.command.length - 1], "uv run pytest",
            "only a real true sends the opt-out")
  }

  // Review Focus 4 (the form half)
  function test_a_verify_value_that_is_not_a_list_is_refused_not_thrown() {
    var store = previewingStore(); if (!store) return
    compare(store.setDispatchField("verify", "uv run pytest"), true)
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrors[0].field, "verify")
    store.setDispatchField("allowNoVerification", true)
    store.setDispatchField("parallelism", "4")
    fire(store.dispatchDebounceTimer)
    compare(store.dispatchState, "refused", "the store converts nothing")
    compare(store.dispatchErrors[0].field, "parallelism")
    store.setDispatchField("parallelism", 4)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--allow-no-verification")
  }

  // 16
  function test_change_restarts_400ms_debounce_and_one_preview_per_burst() {
    var store = previewingStore(); if (!store) return
    var timer = store.dispatchDebounceTimer
    compare(timer.objectName, "dispatchDebounceTimer")
    compare(timer.interval, 400)
    compare(timer.repeat, false)
    var first = store.dispatchPreviewRunner.current
    compare(store.setDispatchField("prefix", "a"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("prefix", "ab"), true)
    compare(store.dispatchState, "previewing")
    compare(store.setDispatchField("parallelism", 2), true)
    compare(store.dispatchState, "previewing")
    compare(timer.running, true)
    verify(store.dispatchPreviewRunner.current === first, "nothing launched during the burst")
    compare(first.running, false, "the preview in flight was cancelled")
    fire(timer)
    var proc = store.dispatchPreviewRunner.current
    verify(proc !== first, "one preview for the burst")
    compare(argv(proc), tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|ab|--max-concurrent|2|--verify|uv run pytest")
  }

  // 17
  function test_latest_preview_wins() {
    var store = previewingStore(); if (!store) return
    var first = store.dispatchPreviewRunner.current
    store.setDispatchField("parallelism", 2)
    fire(store.dispatchDebounceTimer)
    var second = store.dispatchPreviewRunner.current
    verify(second !== first, "a second preview")
    reply(first, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "previewing", "the older preview's reply is dropped")
    compare(store.dispatchPreview, null)
    reply(second, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    verify(store.dispatchPreview !== null)
  }

  // 18
  function test_change_after_ready_drops_preview_and_goes_previewing() {
    var store = previewingStore(); if (!store) return
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    var form = store.dispatchForm
    var list = ["make test"]
    compare(store.setDispatchField("verify", list), true)
    list.push("rm -rf /")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchPreview, null)
    compare(form.verify[0], "uv run pytest", "the old form was not changed in place")
    compare(store.dispatchForm.verify.length, 1, "verify is copied")
    compare(store.dispatchForm.verify[0], "make test")
    compare(store.dispatchForm.prefix, "m3", "the other fields are kept")
    compare(store.dispatchForm.base, "main")
    compare(store.dispatchDebounceTimer.running, true)
  }

  // 19
  function test_set_unknown_field_or_while_idle_is_refused() {
    var store = dispatchStore(); if (!store) return
    compare(store.setDispatchField("prefix", "x"), false, "idle")
    compare(store.dispatchForm, null)
    var cards = dispatchCards()
    store.openDispatch(cards.s1, cards)
    compare(store.setDispatchField("prefix", "x"), false, "a refused target has no form")
    compare(store.dispatchState, "refused")
    compare(store.dispatchError, "A story is dispatched through its milestone")
    store.openDispatch(cards.m1, cards)
    compare(store.setDispatchField("branch", "x"), false, "unknown field")
    compare(store.setDispatchField("__proto__", {}), false)
    compare(store.dispatchForm.prefix, "m3", "nothing changed")
    compare(store.dispatchForm.branch, undefined)
    compare(store.dispatchDebounceTimer.running, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_change_restarts_400ms_debounce_and_one_preview_per_burst StoresRunStore::test_set_unknown_field_or_while_idle_is_refused`
Expected: FAIL — `TypeError: Property 'setDispatchField' of object ... is not a function`.

- [ ] **Step 3: Implement**

Append to the dispatch section, directly before the line `  // The guard is the project root, so a snapshot launched for a project the`:

```js
  // One form field changed (name one of base, prefix, verify, parallelism,
  // allowNoVerification) while the form may be edited: back to previewing,
  // the preview, any refusal or failure and any preview in flight dropped,
  // and the 400 ms check restarted, so a burst of changes costs one check.
  // Refused (false, nothing changes) for another name, without a form, and
  // while idle, starting or started.
  function setDispatchField(name, value) {
    if (["base", "prefix", "verify", "parallelism", "allowNoVerification"].indexOf(name) < 0) return false
    var state = store.dispatchState
    if (state !== "previewing" && state !== "ready" && state !== "refused" && state !== "failed") return false
    if (store.dispatchForm === null) return false
    store.dispatchForm = store.withField(store.dispatchForm, name, value)
    if (name === "base") dispatchBook.baseTouched = true
    store.dispatchState = "previewing"
    store.dispatchPreview = null
    store.clearDispatchError()
    dispatchPreviewRunner.cancel()
    dispatchDebounceTimer.restart()
    return true
  }

```

Replace

```qml
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
  }
```

with

```qml
  Timer {
    id: dispatchDebounceTimer
    objectName: "dispatchDebounceTimer"
    interval: 400
    repeat: false
    onTriggered: store.checkDispatch()
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml`
Expected: PASS, `0 failed`, no `TypeError` lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "RunStore.qml: setDispatchField, checked 400 ms after the last change (S3 3.1)"
```

---

### Task 5: `dispatchStart`, the start reply and the settings write

**Files:**
- Modify: `core/stores/RunStore.qml` (dispatch functions section; new `Component` `dispatchStartC`)
- Test: `tests/core/stores/tst_run_store.qml` (append)

**Interfaces:**
- Consumes: `dispatchTargetArgs()`, `dispatchOptionArgs()`, `dispatchCommands(form)`, `copyMap`, `parseEnvelope`, `refresh()`, `flash(text)`, `dispatchBook` (earlier tasks / existing).
- Produces: `dispatchStart()` → bool; `isHereStart(runner)` → bool; `dispatchStartReplied(runner, stdout)`; `dispatchSaveReplied(runner, stdout)`; `dropStartRunner(runner)`; start runners with `madeFor` (string), `saved` (object), `savedJson` (string), `saving` (bool). Test helpers `startOk(runId, message)`, `readyStore()`, `tc.savedJson`.

- [ ] **Step 1: Write the failing tests**

Append before the final `}`:

```qml

  function startOk(runId, message) {
    return JSON.stringify({ ok: true, pid: 4242, log: "/home/u/.local/state/am-run.log", started_at: "2026-10-05T02:14:00Z",
                            run_id: runId, message: message }) + "\n"
  }

  // Project A with milestone m1's preview landed: Start is allowed.
  function readyStore() {
    var store = previewingStore(); if (!store) return null
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    return store
  }

  property string savedJson: '{"verify":["uv run pytest"],"allowNoVerification":false,"prefixHistory":["m3","old"],"parallelism":4}'

  // 20 (the start half)
  function test_subtask_start_argv_uses_card() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.openDispatch(cards.t1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchStart(), true)
    var proc = store.dispatchStartRunners[0].current
    compare(argv(proc), tc.startCmd + "/home/u/my proj|card|t1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
    compare(proc.command.length, 13)
  }

  // 21 + Review Focus 3
  function test_start_refused_unless_ready() {
    var store = dispatchStore(); if (!store) return
    compare(store.dispatchStart(), false, "idle")
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    compare(store.dispatchStart(), false, "previewing")
    store.openDispatch(cards.s1, cards)
    compare(store.dispatchStart(), false, "refused")
    compare(store.dispatchStartRunners.length, 0, "no start runner")
    var fresh = make(); if (!fresh) return
    compare(fresh.dispatchStart(), false, "a fresh store")
    var ready = readyStore(); if (!ready) return
    compare(ready.dispatchStart(), true)
    compare(ready.dispatchStart(), false, "a second Start while starting")
    compare(ready.dispatchStartRunners.length, 1, "one launch for a double click")
  }

  // 22
  function test_start_argv_and_starting() {
    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    compare(store.dispatchState, "starting")
    compare(store.dispatchStartRunners.length, 1)
    var runner = store.dispatchStartRunners[0]
    compare(runner.madeFor, "/home/u/my proj")
    compare(runner.guard, "", "a preview or a project switch never stops a start")
    var proc = runner.current
    compare(argv(proc), tc.startCmd + tc.previewArgs)
    compare(proc.command.length, 13)
    compare(proc.running, true)
    compare(store.dispatchPreview.summary, "2 levels · 3 subtasks · 1 story already done", "the preview stays up while starting")
  }

  // 23
  function test_change_and_close_refused_while_starting() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    compare(store.setDispatchField("prefix", "x"), false)
    compare(store.dispatchForm.prefix, "m3")
    compare(store.closeDispatch(), false)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.t1, cards), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchDebounceTimer.running, false)
  }

  // 24
  function test_start_ok_with_run_id_emits_and_saves() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var seq = store.snapshotRunner.seq
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-1")
    compare(store.dispatchMessage, "")
    compare(spy.count, 1)
    compare(spy.signalArguments[0][0], "r-1")
    compare(store.snapshotRunner.seq, seq + 1, "the runs are fetched again")
    compare(argv(store.snapshotRunner.current), "python3|/plugin/core/backend/runs/runs-snapshot.py|/home/u/my proj")
    compare(store.dispatchStartRunners.length, 1, "the same runner writes the settings")
    verify(store.dispatchStartRunners[0] === runner)
    var save = runner.current
    compare(save.command.length, 5)
    compare(argv(save), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson)
    compare(store.runSettings.prefixHistory.join(","), "m3,old")
    compare(store.runSettings.verify.join(","), "uv run pytest")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.allowNoVerification, false)
    compare(store.runSettings.confirmDispatch, true, "keys the start does not write are kept")
    reply(save, JSON.stringify({ ok: true }) + "\n", 0)
    compare(store.dispatchStartRunners.length, 0, "the runner goes after the write")
    compare(store.flashText, "")
    compare(store.dispatchState, "started")
  }

  // 25 + Review Focus 5 (run id half)
  function test_start_ok_without_run_id_emits_null() {
    var ids = [null, "", 42]
    for (var i = 0; i < ids.length; i++) {
      var store = readyStore(); if (!store) return
      var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, startOk(ids[i], "started, run not visible yet"), 0)
      compare(store.dispatchState, "started", "run_id " + i)
      compare(store.dispatchRunId, "", "run_id " + i)
      compare(store.dispatchMessage, "started, run not visible yet")
      compare(spy.count, 1)
      compare(spy.signalArguments[0][0], null, "run_id " + i + ": not visible yet")
    }
  }

  // 26 + Review Focus 4 (the history half)
  function test_prefix_history_dedups_and_caps_at_20() {
    var store = makeWithProject(rootA); if (!store) return
    var history = ["a", "m3", "", "  ", 7, "b"]
    for (var i = 0; i < 25; i++) history.push("p" + i)
    reply(store.settingsLoadRunner.current, JSON.stringify({ verify: ["uv run pytest"], allowNoVerification: false,
      notifyOnEscalation: false, prefixHistory: history, parallelism: 4, confirmDispatch: true }) + "\n", 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "  m3 ")
    fire(store.dispatchDebounceTimer)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchStart(), true)
    var runner = store.dispatchStartRunners[0]
    compare(runner.current.command[8], "m3", "the prefix is sent trimmed")
    reply(runner.current, startOk("r-1", ""), 0)
    var expected = ["m3", "a", "b"]
    for (var j = 0; j < 17; j++) expected.push("p" + j)
    var saved = JSON.parse(runner.current.command[4])
    compare(saved.prefixHistory.length, 20)
    compare(saved.prefixHistory.join(","), expected.join(","))
    compare(store.runSettings.prefixHistory.join(","), expected.join(","))

    var bare = makeWithProject(rootA); if (!bare) return
    reply(bare.settingsLoadRunner.current, "Traceback: boom\n", 1)
    bare.openDispatch(cards.m1, cards)
    reply(bare.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    bare.setDispatchField("verify", ["make test"])
    fire(bare.dispatchDebounceTimer)
    reply(bare.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(bare.dispatchStart(), true)
    var bareRunner = bare.dispatchStartRunners[0]
    reply(bareRunner.current, startOk("r-2", ""), 0)
    compare(argv(bareRunner.current), tc.viewerCmd +
            'set-run-settings|/home/u/my proj|{"verify":["make test"],"allowNoVerification":false,"prefixHistory":["m3"],"parallelism":4}')
  }

  // 27
  function test_start_failure_goes_failed_with_log() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    reply(runner.current, JSON.stringify({ ok: false, error: { type: "AmExited", message: "am run exited at once (exit 2)" },
      log: "/home/u/.local/state/am-run.log", pid: 4242, started_at: "2026-10-05T02:14:00Z", exit_code: 2,
      log_tail: "error: milestone m1 not found" }) + "\n", 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchError, "am run exited at once (exit 2)")
    compare(store.dispatchErrorType, "AmExited")
    compare(store.dispatchLog, "/home/u/.local/state/am-run.log")
    compare(store.dispatchLogTail, "error: milestone m1 not found")
    compare(store.dispatchExitCode, 2)
    compare(spy.count, 0)
    compare(store.dispatchStartRunners.length, 0, "no settings write after a failed start")
    compare(store.runSettings.prefixHistory.join(","), "old", "nothing saved")
    compare(store.dispatchForm.prefix, "m3", "the form stays for another try")
  }

  // 28 + Review Focus 5 (exit code half)
  function test_start_unreadable_goes_failed() {
    var replies = ["", "Traceback: boom\n", JSON.stringify({ ok: "maybe" }) + "\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      reply(store.dispatchStartRunners[0].current, replies[i], 1)
      compare(store.dispatchState, "failed", "reply " + i)
      compare(store.dispatchError, "The launch could not be read", "reply " + i)
      compare(store.dispatchErrorType, "", "reply " + i)
      compare(store.dispatchLog, "", "reply " + i)
      compare(store.dispatchExitCode, null, "reply " + i)
      compare(store.dispatchStartRunners.length, 0, "reply " + i)
    }
    var blank = readyStore(); if (!blank) return
    blank.dispatchStart()
    reply(blank.dispatchStartRunners[0].current, JSON.stringify({ ok: false, error: { type: "SpawnFailed", message: " " },
      log: "/tmp/l", exit_code: "2", log_tail: 5 }) + "\n", 0)
    compare(blank.dispatchState, "failed")
    compare(blank.dispatchError, "The launch could not be read")
    compare(blank.dispatchErrorType, "SpawnFailed")
    compare(blank.dispatchLog, "/tmp/l")
    compare(blank.dispatchLogTail, "", "a log tail that is not a string")
    compare(blank.dispatchExitCode, null, "an exit code that is not a number")
  }

  // 29
  function test_failed_then_change_previews_again() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, ctlFail("ClaimedError", "claimed by r-0"), 0)
    compare(store.dispatchState, "failed")
    compare(store.dispatchErrorType, "ClaimedError")
    compare(store.dispatchStart(), false, "a failed start is not retried without a new check")
    compare(store.setDispatchField("prefix", "m3-retry"), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchError, "")
    compare(store.dispatchErrorType, "")
    compare(store.dispatchLog, "")
    compare(store.dispatchExitCode, null)
    fire(store.dispatchDebounceTimer)
    compare(argv(store.dispatchPreviewRunner.current),
            tc.previewCmd + "/home/u/my proj|milestone|m1|--base-branch|main|--branch-prefix|m3-retry|--max-concurrent|4|--verify|uv run pytest")
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 1)
  }

  // 30
  function test_settings_write_failure_flashes() {
    var replies = [JSON.stringify({ ok: false, error: { type: "Invalid", message: "x" } }) + "\n", "garbage\n"]
    for (var i = 0; i < replies.length; i++) {
      var store = readyStore(); if (!store) return
      store.dispatchStart()
      var runner = store.dispatchStartRunners[0]
      reply(runner.current, startOk("r-1", ""), 0)
      reply(runner.current, replies[i], 1)
      compare(store.flashText, "Dispatch settings could not be saved", "reply " + i)
      compare(store.dispatchState, "started", "the run still started")
      compare(store.dispatchStartRunners.length, 0)
      compare(store.notifyOnEscalation, false, "the notify switch is untouched")
      verify(!store.settingsSaveRunner.current, "the notify switch's runner is not used")
    }
  }

  function test_started_refuses_changes_and_reopening_starts_over() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    reply(store.dispatchStartRunners[0].current, startOk("r-1", ""), 0)
    compare(store.setDispatchField("prefix", "x"), false, "started")
    compare(store.dispatchStart(), false, "started")
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchRunId, "")
    compare(store.dispatchState, "previewing")
    compare(store.dispatchForm.verify[0], "uv run pytest", "the next form starts from the saved values")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_start_argv_and_starting StoresRunStore::test_start_ok_with_run_id_emits_and_saves`
Expected: FAIL — `TypeError: Property 'dispatchStart' of object ... is not a function`.

- [ ] **Step 3: Implement the functions**

Append to the dispatch section, directly before the line `  // The guard is the project root, so a snapshot launched for a project the`:

```js
  // Start: only from ready. start-run.py runs on a HelperRunner of its own
  // (guard "", madeFor this project), which no preview, project switch or
  // other Start stops. The settings a successful start saves are fixed now,
  // from this project's runSettings: the non-blank verify commands sent, the
  // opt-out, the prefix sent followed by the stored history without it (at
  // most 20), and the parallelism.
  function dispatchStart() {
    if (store.dispatchState !== "ready") return false
    var form = store.dispatchForm
    var prefix = form.prefix.trim()
    var history = [prefix]
    var stored = Array.isArray(store.runSettings.prefixHistory) ? store.runSettings.prefixHistory : []
    for (var i = 0; i < stored.length && history.length < 20; i++) {
      var p = stored[i]
      if (typeof p === "string" && p.trim() !== "" && p !== prefix) history.push(p)
    }
    var saved = { verify: store.dispatchCommands(form), allowNoVerification: form.allowNoVerification === true,
                  prefixHistory: history, parallelism: form.parallelism }
    var runner = dispatchStartC.createObject(store, { madeFor: store.project, saved: saved, savedJson: JSON.stringify(saved) })
    dispatchBook.runners = dispatchBook.runners.concat([runner])
    dispatchBook.startRunner = runner
    store.dispatchState = "starting"
    runner.run([store.project].concat(store.dispatchTargetArgs(), store.dispatchOptionArgs()))
    return true
  }

  // A start runner's reply is this dispatch's: it was made in the current
  // project and is the runner that put the store into `starting` (an idle
  // reset, and so a project switch, forgets it).
  function isHereStart(runner) {
    return runner.madeFor === store.project && dispatchBook.startRunner === runner
  }

  // start-run.py's reply. When it is this dispatch's: ok gives `started`,
  // the run id and message, the saved values in runSettings, a re-snapshot
  // and dispatchStarted(id or null); anything else gives `failed` with what
  // the helper said. After any successful start, wherever it was made, the
  // same runner writes the saved values for the project it was made in.
  function dispatchStartReplied(runner, stdout) {
    if (runner.saving) {
      store.dispatchSaveReplied(runner, stdout)
      return
    }
    var here = store.isHereStart(runner)
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      if (here) {
        store.dispatchRunId = typeof envelope.run_id === "string" ? envelope.run_id : ""
        store.dispatchMessage = typeof envelope.message === "string" ? envelope.message : ""
        var settings = store.copyMap(store.runSettings)
        for (var key in runner.saved) settings[key] = runner.saved[key]
        store.runSettings = settings
        store.dispatchState = "started"
        store.refresh()
        store.dispatchStarted(store.dispatchRunId !== "" ? store.dispatchRunId : null)
      }
      runner.saving = true
      runner.script = store.backendDir + "projects/viewer-state.py"
      runner.run(["set-run-settings", runner.madeFor, runner.savedJson])
      return
    }
    if (here) {
      var failure = envelope !== null && envelope.ok === false ? envelope : {}
      var err = failure.error
      var isErr = err !== null && err !== undefined && typeof err === "object"
      var message = isErr && typeof err.message === "string" ? err.message : ""
      store.dispatchState = "failed"
      store.dispatchError = message.trim() !== "" ? message : "The launch could not be read"
      store.dispatchErrorType = isErr && typeof err.type === "string" ? err.type : ""
      store.dispatchLog = typeof failure.log === "string" ? failure.log : ""
      store.dispatchLogTail = typeof failure.log_tail === "string" ? failure.log_tail : ""
      store.dispatchExitCode = typeof failure.exit_code === "number" ? failure.exit_code : null
    }
    store.dropStartRunner(runner)
  }

  // set-run-settings after a start: a failure is said only while the
  // dispatch is still this one. The runner then goes.
  function dispatchSaveReplied(runner, stdout) {
    var reply = store.parseEnvelope(stdout)
    if (store.isHereStart(runner) && !(reply !== null && reply.ok === true)) store.flash("Dispatch settings could not be saved")
    store.dropStartRunner(runner)
  }

  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

```

- [ ] **Step 4: Implement the start runner component**

Directly before the line `  // One Process per watch launch, so each carries what it was launched with.` insert:

```qml
  // One HelperRunner per Start. Guard "": start-run.py may take ~20 s, and
  // neither a preview, a project switch nor a Start in another project may
  // stop it. After a successful start the same runner writes the settings
  // for `madeFor`; it goes when that write replies, or at once after a
  // failed start.
  Component {
    id: dispatchStartC

    HelperRunner {
      id: sr
      property string madeFor: ""     // the project the start was made in
      property var saved: null        // the values a successful start saves
      property string savedJson: ""   // `saved` as set-run-settings takes it
      property bool saving: false     // the settings write is in flight
      script: store.backendDir + "runs/start-run.py"
      guard: ""
      onFinished: function(stdout, exitCode) { store.dispatchStartReplied(sr, stdout) }
    }
  }

```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml`
Expected: PASS, `0 failed`, no `TypeError` lines.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "RunStore.qml: dispatchStart runs start-run.py and saves the used values after a start (S3 3.1)"
```

---

### Task 6: project switch and panel close

**Files:**
- Modify: `core/stores/RunStore.qml` (`stopLive()` lines 154-163, `projectSwitched()` lines 253-286)
- Test: `tests/core/stores/tst_run_store.qml` (append)

**Interfaces:**
- Consumes: `resetDispatch()`, `closeDispatch()` (Task 2); start runners (Task 5).
- Produces: nothing new; `projectSwitched()` and `stopLive()` now close the dispatch.

- [ ] **Step 1: Write the failing tests**

Append before the final `}`:

```qml

  // 31
  function test_project_switch_resets_dispatch_and_drops_old_preview() {
    var store = previewingStore(); if (!store) return
    var preview = store.dispatchPreviewRunner.current
    store.project = rootB
    checkDispatchIdle(store, "after the switch")
    compare(Object.keys(store.runSettings).length, 0)
    compare(preview.running, false, "A's preview is stopped")
    reply(preview, previewOk(dispatchDryRun()), 0)
    checkDispatchIdle(store, "after A's late preview")

    var pending = previewingStore(); if (!pending) return
    pending.setDispatchField("prefix", "x")
    compare(pending.dispatchDebounceTimer.running, true)
    pending.project = rootB
    compare(pending.dispatchDebounceTimer.running, false, "no check is left pending")
    checkDispatchIdle(pending, "switch during a burst")

    var cleared = previewingStore(); if (!cleared) return
    cleared.project = ""
    checkDispatchIdle(cleared, "no project")
  }

  // 32
  function test_start_result_belongs_to_its_project() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    var startProc = runner.current
    store.project = rootB
    checkDispatchIdle(store, "B after the switch from starting")
    compare(startProc.running, true, "the start is not stopped")
    compare(store.dispatchStartRunners.length, 1)
    var seq = store.snapshotRunner.seq
    reply(startProc, startOk("r-1", ""), 0)
    checkDispatchIdle(store, "B after A's start landed")
    compare(spy.count, 0)
    compare(store.snapshotRunner.seq, seq, "no refresh for B")
    compare(Object.keys(store.runSettings).length, 0, "B's settings do not take A's values")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "recorded against A")
    reply(runner.current, "garbage\n", 1)
    compare(store.flashText, "", "no flash about A in B")
    compare(store.dispatchStartRunners.length, 0)
  }

  // 32b
  function test_start_reply_after_switching_away_and_back_is_not_here() {
    var store = readyStore(); if (!store) return
    var spy = spyC.createObject(tc, { target: store, signalName: "dispatchStarted" })
    store.dispatchStart()
    var runner = store.dispatchStartRunners[0]
    store.project = rootB
    store.project = rootA
    checkDispatchIdle(store, "back in A")
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchState, "previewing")
    reply(runner.current, startOk("r-1", ""), 0)
    compare(store.dispatchState, "previewing", "the new dialog is not overwritten")
    compare(store.dispatchRunId, "")
    compare(spy.count, 0)
    compare(store.runSettings.prefixHistory.join(","), "old")
    compare(argv(runner.current), tc.viewerCmd + "set-run-settings|/home/u/my proj|" + tc.savedJson, "still recorded for A")
  }

  // 33
  function test_start_in_other_project_does_not_stop_the_first() {
    var store = readyStore(); if (!store) return
    store.dispatchStart()
    var procA = store.dispatchStartRunners[0].current
    store.project = rootB
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    compare(store.openDispatch(cards.m1, cards), true, "B's dispatch opens while A's start is in flight")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(store.dispatchStartRunners.length, 2)
    compare(store.dispatchStartRunners[0].madeFor, "/home/u/my proj")
    compare(store.dispatchStartRunners[1].madeFor, "/home/u/b")
    compare(procA.running, true, "A's start is still running")
    var procB = store.dispatchStartRunners[1].current
    compare(argv(procB), tc.startCmd + "/home/u/b|milestone|m1|--base-branch|main|--branch-prefix|m3|--max-concurrent|4|--verify|uv run pytest")
    reply(procA, startOk("r-a", ""), 0)
    compare(store.dispatchState, "starting", "A's reply does not land in B's dialog")
    reply(procB, startOk("r-b", ""), 0)
    compare(store.dispatchState, "started")
    compare(store.dispatchRunId, "r-b")
  }

  // 34
  function test_panel_close_closes_dispatch_but_not_a_start() {
    var store = activeStore(rootA); if (!store) return
    reply(store.settingsLoadRunner.current, dispatchSettings(), 0)
    var cards = dispatchCards()
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    store.active = false
    checkDispatchIdle(store, "closed from ready")

    store.active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    store.setDispatchField("prefix", "x")
    compare(store.dispatchDebounceTimer.running, true)
    store.active = false
    compare(store.dispatchDebounceTimer.running, false, "no timer while idle")
    checkDispatchIdle(store, "closed during a burst")

    store.active = true
    store.openDispatch(cards.m1, cards)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    store.dispatchStart()
    var proc = store.dispatchStartRunners[0].current
    store.active = false
    compare(store.dispatchState, "starting", "a start in flight is not closed")
    compare(proc.running, true)
    reply(proc, startOk("r-1", ""), 0)
    compare(store.dispatchState, "started", "it lands normally")
    compare(store.dispatchRunId, "r-1")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml StoresRunStore::test_project_switch_resets_dispatch_and_drops_old_preview StoresRunStore::test_panel_close_closes_dispatch_but_not_a_start`
Expected: FAIL — `after the switch: state` is `previewing` not `idle`; `closed from ready: state` is `ready` not `idle`.

- [ ] **Step 3: Implement**

In `stopLive()`, replace

```js
    store.alertsArmed = false
    store.toasts = []
  }

  // Nothing is stale yet; the 30 s clock starts again while there is something
```

with

```js
    store.alertsArmed = false
    store.toasts = []
    // A start in flight refuses and lands normally.
    store.closeDispatch()
  }

  // Nothing is stale yet; the 30 s clock starts again while there is something
```

Also update the comment above `stopLive()`: replace

```js
  // The panel closed: no process and no timer is left running, and no toast
  // outlives the opening. The runs, the selection and amStatus stay for the
  // next opening.
```

with

```js
  // The panel closed: no process and no timer is left running, and no toast
  // or dispatch outlives the opening (a start in flight runs to its end). The
  // runs, the selection and amStatus stay for the next opening.
```

In `projectSwitched()`, replace

```js
    store.notifyTouched = false
    store.runSettings = {}
    settingsLoadRunner.guard = store.project
```

with

```js
    store.notifyTouched = false
    store.runSettings = {}
    // The dispatch is the old project's, even mid-start: a start already
    // launched still runs, and its reply is no longer this dispatch's.
    store.resetDispatch()
    settingsLoadRunner.guard = store.project
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/stores/tst_run_store.qml`
Expected: PASS, `0 failed`, no `TypeError` lines.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "RunStore.qml: a project switch and closing the panel close the dispatch, never a start in flight (S3 3.1)"
```

---

### Task 7: architecture doc, header comment and the whole suite

**Files:**
- Modify: `docs/architecture.md` (the `RunStore.qml` block ending at line 95; the "Refresh model" line 165)
- Modify: `core/stores/RunStore.qml` (header comment lines 6-17)

**Interfaces:**
- Consumes: the whole public surface from Tasks 1-6.
- Produces: documentation only.

- [ ] **Step 1: Update the store's header comment**

In `core/stores/RunStore.qml`, replace

```js
// Pause, resume and cancel (control()) each get a HelperRunner of their own.
```

with

```js
// Pause, resume and cancel (control()) each get a HelperRunner of their own.
// Dispatch (openDispatch .. dispatchStart) previews a run with
// dispatch-preview.py and starts it with start-run.py, one HelperRunner per
// Start.
```

- [ ] **Step 2: Add the dispatch paragraph to `docs/architecture.md`**

The `RunStore.qml` block's last line is the long line starting `  Run controls (S2 4.1): \`control(action, runId)\``. Directly after that line (before the blank line that precedes `Other \`ui/\` pieces:`), insert this one line:

```markdown
  Dispatch (S3 3.1): the store also starts am runs. `openDispatch(card, cardMap)` takes a brd card as `Board.indexTree()` leaves it (or `"board"`) and its `{id: card}` map; it refuses without a project or while a start is in flight. A story, a finished card or no card goes straight to `refused` (`dispatchErrorType` `Target`, `dispatchSuggest` the story's milestone); otherwise `dispatchTarget` is `Runs.dispatchPlan`'s result, `dispatchForm` (`{base, prefix, verify, parallelism, allowNoVerification}`) starts from `Runs.dispatchDefaults` with `runSettings` -- the current project's whole `get-run-settings` reply, `{}` until it lands and after a project switch -- and `dispatch-preview.py --defaults ROOT` (`dispatchDefaultsRunner`) fills `base` once per opening unless the user set it. `dispatchState` is `idle`, `previewing`, `ready`, `refused`, `starting`, `started` or `failed`. The form is checked with `Runs.validateDispatch` when that lookup replies and 400 ms after the last `setDispatchField(name, value)` (`dispatchDebounceTimer`): an invalid form is `refused` (`Form`, `dispatchErrors`) and launches nothing, a subtask is `ready` at once (am has no dry run for one card), and a milestone or the board runs `dispatch-preview.py ROOT TARGET [--base-branch B] --branch-prefix P --max-concurrent N [--verify CMD]... [--allow-no-verification]` on `dispatchPreviewRunner` (latest wins; every change cancels it), giving `ready` with `dispatchPreview` (`Runs.previewSummary`) or `refused` with am's message verbatim (`The preview could not be read` when there is none). `dispatchStart()` works only from `ready`: it runs `start-run.py ROOT TARGET` with the same options on a `HelperRunner` of its own (`dispatchStartRunners`, guard `""`, `madeFor` the project) that no preview, project switch or other Start stops; while `starting`, `setDispatchField`, `openDispatch` and `closeDispatch()` are refused. A successful start for the dispatch still open in its project sets `started`, `dispatchRunId` (`""` while am does not list the run yet) and `dispatchMessage`, re-snapshots and emits `dispatchStarted(runId)` (`null` when not visible yet); a failed one sets `failed` with `dispatchError`, `dispatchErrorType`, `dispatchLog`, `dispatchLogTail` and `dispatchExitCode`. After any successful start the same runner writes `set-run-settings` for the project it was made in -- `verify`, `allowNoVerification`, `prefixHistory` (the prefix first, at most 20) and `parallelism`, fixed when Start was pressed, never through `settingsSaveRunner` -- and flashes `Dispatch settings could not be saved` when that fails while the dispatch is still that start's. `closeDispatch()`, a project switch (even from `starting`) and closing the panel (except while `starting`) put the dispatch back to `idle`.
```

- [ ] **Step 3: Update the "Refresh model" line**

In `docs/architecture.md`, replace

```markdown
`RunStore`'s watch, its debounce, the liveness re-read (only while a run is running), the fallback poll and the toast expiry (`toastTimer`, only while a toast shows) run only while the panel is open (`active`);
```

with

```markdown
`RunStore`'s watch, its debounce, the liveness re-read (only while a run is running), the fallback poll, the toast expiry (`toastTimer`, only while a toast shows) and the dispatch debounce (`dispatchDebounceTimer`, only while a form change waits to be checked; closing the panel closes the dispatch unless a start is in flight) run only while the panel is open (`active`);
```

- [ ] **Step 4: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest passes (`tests/architecture/test_layers.py` and `test_icon_glyphs.py` included, unchanged), every `== tests/...tst_*.qml` block prints `Totals: N passed, 0 failed`, no `TypeError`/`ReferenceError` lines, exit status 0.

- [ ] **Step 5: Commit**

```bash
git add docs/architecture.md core/stores/RunStore.qml
git commit -m "docs: architecture.md describes RunStore's dispatch and its debounce (S3 3.1)"
```

---

## Self-Review

**Spec coverage.**
- Public surface table: properties, signal, `openDispatch`, `setDispatchField`, `dispatchStart`, `closeDispatch`, the four aliases — Task 2 (state, aliases, open/close), Task 4 (`setDispatchField`), Task 5 (`dispatchStart`, start runners); `runSettings` — Task 1.
- D1 (caller hands the target) — Task 2 `openDispatch(card, cardMap)`. D2 (`runSettings`, set before the `notifyTouched` return; `{}` before a reply) — Task 1, plus `test_open_before_the_settings_reply_starts_from_nothing` in Task 2. D3 (one `--defaults` per opening; user-set base wins; blank never sent) — Tasks 2-4 (tests 3, 6, 7, 8). D4 (subtask has no preview) — Task 3 test 20, Task 5 start half. D5 (form checked first) — Task 3 test 14, Task 4 tests 15/RF4. D6 (one runner per Start, guard `""`, `madeFor`, write after success, runner goes) — Task 5 tests 22/24/27, Task 6 tests 32/32b/33. D7 (save after success, key order, history, built at Start, never `settingsSaveRunner`) — Task 5 tests 24/26/30. D8 (changes and close refused while starting) — Task 5 test 23. D9 (panel close) — Task 6 test 34.
- Behaviour sections: openDispatch steps 1-5 — Task 2; defaults reply — Task 3; setDispatchField rules incl. clearing fields and cancelling the preview — Task 4 tests 16-19, 29; checking (wait for defaults, refuse, subtask ready, preview argv) — Tasks 3-4; preview reply three cases — Task 3 tests 10-12, latest-wins — Task 4 test 17; dispatchStart — Task 5; start reply (`here` incl. A→B→A) — Tasks 5-6; settings write reply — Task 5 test 30, Task 6 test 32; closeDispatch — Tasks 2, 5; project switch / panel close — Task 6.
- Errors table: every row has a test (no project 2; target 4/5; form 14; defaults fail 8; preview refusal 11; unreadable 12; start refusal 27; start unreadable 28; not visible 25; switched mid-start 32/32b; write fails 30).
- Tests list 1-35 (incl. 32b): all present; 1's `dispatchStart() → false` assertion is in test 21 (Task 5), because `dispatchStart` does not exist until then.
- Docs: Task 7. `tests/architecture` and `bash tests/run.sh`: Task 7 step 4; no import is added anywhere.

**Placeholder scan.** No TBD/TODO; every code step carries the code; every test is written out.

**Type consistency.** Names used across tasks: `dispatchBook.{runners,startRunner,baseTouched,defaultsPending}` (Task 2) used in Tasks 3-5; `withField`, `checkDispatch`, `dispatchTargetArgs`, `dispatchCommands(form)`, `dispatchOptionArgs` (Task 3) used in Tasks 4-5; `isHereStart`, `dispatchStartReplied(runner, stdout)`, `dispatchSaveReplied(runner, stdout)`, `dropStartRunner` (Task 5); runner properties `madeFor`, `saved`, `savedJson`, `saving` match between `dispatchStart()` and `dispatchStartC`. Test helpers `dispatchSettings`, `dispatchCards`, `dispatchStore`, `checkDispatchIdle`, `defaultsOk`, `previewOk`, `dispatchDryRun`, `previewingStore`, `readyStore`, `startOk`, `tc.previewCmd`, `tc.startCmd`, `tc.previewArgs`, `tc.savedJson` are each defined once, in the first task that uses them, and none collides with an existing name in the file (`runSettings(notify)`, `settingsReply`, `ctlFail`, `argv`, `fire`, `activeStore` are existing helpers reused as-is).

**Review Focus.** Five lines, each with a pinning test in its owning task (Tasks 3, 4, 5).

**Interpretation note for the executor.** The spec defines `here` for the settings-write reply as "the current project and the runner that put the store into `starting`"; this plan keeps that runner remembered after `started` until an idle reset (`closeDispatch`, `openDispatch`, a project switch) or until the runner goes, so a failed write flashes only while the dialog that started it is still the open one.
<!-- task-pipeline: validated -->
