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
