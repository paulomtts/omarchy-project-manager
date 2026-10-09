# 5.2 RunStore shims removed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore` declares none of the 63 members that moved to `RunControlStore`, `RunAlertsStore` and `RunDispatchStore`, and none of the three handles (`controlStore`, `alertsStore`, `dispatchStore`). App no longer sets the handles, every test reads each moved member on the store that owns it, and an App test pins that the shims are gone.

**Architecture:** The tests move first, while the shims still exist, so every commit is green: Task 1 moves `tst_app_runs.qml` to the owners, and Task 2 moves `tst_run_store.qml` and the three sibling suites. Task 3 adds the absence test, which goes red against the shims. It then deletes the shim block from `RunStore.qml` and the handle lines from `App.qml`, and the test goes green. Each edit is a small Python script, kept outside the repo. Every hand edit is an exact `old → new` pair that the script checks matches once, and every mechanical path change is a regex over a fixed member map that prints how many changes it made.

**Tech Stack:** QML (Qt 6 / Quickshell, stubbed in `tests/stubs`), QtTest via `qmltestrunner`, pytest. Everything runs through `bash tests/run.sh [filter]`: pytest over `tests/` first (about 2 minutes), then every `tst_*.qml` whose path contains the filter. The run fails on any `TypeError`, `ReferenceError`, `non-existent`, `Unable to assign`, `anchors on an item` or `is not a function` in the output. Wrap runs in `timeout`, for example `timeout 900 bash tests/run.sh tst_app_runs`.

**Spec:** `docs/superpowers/specs/5-2-runstore-shims-173b82e2.md` (copied verbatim below, every heading demoted one level).

## Global Constraints

- Owners: `RunStore` = `app.runs`, `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch` (P l.52-57).
- A store never imports or names a sibling. The shim handles were the one temporary exception, and this card removes them (P l.46-50).
- Every member lands in exactly one store, and nothing is duplicated (P l.61-63).
- `RunStore` keeps `project` as a declared input (P l.76). App reads it at `App.qml:138`, `:167` and `:170`.
- No behaviour change, no new helper argv, and no change to which process starts when (P l.146-147).
- Tests move with their members. Only construction and wiring change, never an expectation (P l.98-104). The only exceptions are the shim-only tests and assertions the spec deletes.
- `runSettingsRunner` → `runControl.runSettingsLoadRunner`. A `runSettings` read → `runControl.runSettingsOf(<run store>.project)`. Never compare one project's settings to `RunControlStore.runSettings`, which is the `{root: settings}` map.
- Do not touch `RunControlStore.qml`, `RunAlertsStore.qml`, `RunDispatchStore.qml`, `ui/`, `tests/ui/`, `docs/architecture.md` or `README.md` (5.3 owns the docs).
- Docstrings and comments state the contract only, with no narrative.
- `tests/architecture` stays green: store imports, no duplicated shared patterns, layer allowlists, icon glyph rules.
- Verification: `bash tests/run.sh` green.
- Never run `pkill`, `killall` or a pattern `kill`.

## Review Focus

1. **Shim reads in the sibling suites.** The spec says none of `tst_run_control_store.qml`, `tst_run_alerts_store.qml` or `tst_run_dispatch_store.qml` reads a moved member through a run store. Two of them do. `tst_run_control_store.qml:1429` reads `store.notifyRunners` and `:1516-1526` read `store.runSettings`, `store.setNotifyOnEscalation` and `store.notifyOnEscalation`. `tst_run_alerts_store.qml:874` reads `store.flashText`. After Task 3 each of these would be a `TypeError` or a false pass. Task 2 Step 3 moves the control reads to `c` (`runSettingsOf(store.project)`). It deletes `:1429` and `:874`, because their suites wire no alerts store and no control store, so those reads only ever got a shim's empty fallback.
2. **A read of a deleted member that passes by accident.** `verify(!store.alertsArmed)` or a `=== undefined` check stays green on a missing property. Task 2 Step 5 and Task 3 Step 7 grep every moved name on every run-store variable and expect no hit.
3. **Assigning a deleted property throws.** `store.controlStore = c` against a `RunStore` without the property raises "Cannot assign to non-existent property", which `run.sh` flags. Task 2 removes all six handle assignments before Task 3 deletes the properties.
4. **`runSettings` against the map.** Task 1's substitution maps every `app.runs.runSettings` read to `app.runControl.runSettingsOf(app.runs.project)`, never to `app.runControl.runSettings`. The composition test pins `app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project)`.
5. **`project` deleted along with the shims.** App's `runControl.project`, `runDispatch.project` and `runDispatch.runSettings` bind to `app.runs.project`. The absence test asserts that `project` is still defined, and Task 1's `runControl` composition test now follows `project` across a selection change.

## Execution notes

- Each task's edits are Python scripts. Save each one to `/tmp/5-2/<name>.py`, outside the repo, so `tests/run.sh`'s tar copy never sees it. Run it from the worktree root as `python3 /tmp/5-2/<name>.py .`. A script fails with an `AssertionError` if an anchor does not match exactly once. If that happens, stop and read the file: the anchor text is copied from commit `ba0457d`.
- Every script has been run against `ba0457d` in a scratch copy. The counts it prints, and the test totals below, come from that run.
- Do not commit the scripts.

## File map

| file | task | change |
|---|---|---|
| `tests/core/stores/tst_app_runs.qml` | 1, 3 | moved paths to owners; shim assertions and the write-shim test deleted; composition tests assert inputs; absence and owner tests added |
| `tests/core/stores/tst_run_store.qml` | 2, 3 | handles dropped from the wiring helpers; `wireDispatch`/`dispatchOf`/`dispatchCards` moved up; 37 reads moved to owners; shim sections deleted; R4, R5 and R-D5 kept under "the run store alone" |
| `tests/core/stores/tst_run_control_store.qml` | 2 | handle assignment and its comment; `:1429` deleted; `:1516-1526` read `c` |
| `tests/core/stores/tst_run_alerts_store.qml` | 2 | handle assignment and its comment; `:874` deleted |
| `tests/core/stores/tst_run_dispatch_store.qml` | 2 | handle assignment and its comment |
| `core/stores/RunStore.qml` | 3 | shim block (`:119-219`) deleted; header comment |
| `core/stores/App.qml` | 3 | three handle lines and the comment above `runs` |

---

### Task 1: The App composition suite reads every moved member on its owner

**Files:**
- Modify: `tests/core/stores/tst_app_runs.qml` (`:178-184`, `:331-489`, `:494-513`, `:524`, `:551-570`, `:577`, `:586`, `:667`, `:694-741`, `:778`, `:816-826`)

**Interfaces:**
- Consumes: the members as they exist at `ba0457d`: `app.runControl.runSettingsLoadRunner`, `app.runControl.runSettingsOf(root)`, and the moved members on `app.runControl`, `app.runAlerts` and `app.runDispatch`.
- Produces: a `tst_app_runs.qml` that names no shim and no handle on `app.runs`. Task 3 adds its tests to this file.

This task changes tests only. The shims still exist, so the suite is green before and after. The red step for this card is in Task 3.

- [ ] **Step 1: Run the suite to record the baseline**

Run: `timeout 900 bash tests/run.sh tst_app_runs`
Expected: pytest passes, then `Totals: 49 passed, 0 failed`.

- [ ] **Step 2: Apply the hand edits**

These edits delete the three handle assertions (`:497`, `:554`, `:697`) and the shim-equality assertions (`:524`, `:577`, `:586`, `:667`). They add the `project`-follows-selection assertion to the `runControl` composition test. They delete `test_a_write_to_the_run_store_shim_reaches_the_dispatch_form`. In `test_a_start_through_app_announces_started_once_on_each_store` they drop the `app.runs` spy: `dispatchStarted` no longer exists on the run store, and `ui/Panel.qml` has connected to `runDispatch` since 5.1. The test is renamed `test_a_start_through_app_announces_started_once`. Its `runDispatch` claim is unchanged.

Save as `/tmp/5-2/t1.py`:

```python
import re, sys
from pathlib import Path
p = Path(sys.argv[1]) / "tests/core/stores/tst_app_runs.qml"
t = p.read_text()
def rep(old, new):
    global t
    assert t.count(old) == 1, (t.count(old), old)
    t = t.replace(old, new)
rep('    verify(app.runs.alertsStore === app.runAlerts, "the run store\'s shim handle")\n', '')
rep('    verify(app.runs.toasts === app.runAlerts.toasts, "the run store\'s shim reads the same list")\n', '')
rep('    verify(app.runs.controlStore === app.runControl, "the run store\'s shim handle")\n', '')
rep('''    verify(app.runControl.runs === app.runs.runs, "the run store's merged list")
  }
''', '''    verify(app.runControl.runs === app.runs.runs, "the run store's merged list")
    app.projects.chooseProject(pB)
    compare(app.runControl.project, "/home/u/b", "the project follows the selection")
  }
''')
rep('    verify(app.runs.pending === app.runControl.pending, "the run store\'s shim reads the same map")\n', '')
rep('    verify(app.runs.pending === app.runControl.pending)\n', '')
rep('    verify(app.runs.settingsLoadRunner === app.runControl.settingsLoadRunner, "the run store\'s shim")\n', '')
rep('    verify(app.runs.dispatchStore === app.runDispatch, "the run store\'s shim handle")\n', '')
rep('''  function test_a_start_through_app_announces_started_once_on_each_store() {
    var app = readyApp(); if (!app) return
    var onDispatch = createTemporaryObject(spyC, tc, { target: app.runDispatch, signalName: "dispatchStarted" })
    var onRuns = createTemporaryObject(spyC, tc, { target: app.runs, signalName: "dispatchStarted" })
''', '''  function test_a_start_through_app_announces_started_once() {
    var app = readyApp(); if (!app) return
    var onDispatch = createTemporaryObject(spyC, tc, { target: app.runDispatch, signalName: "dispatchStarted" })
''')
rep('''    compare(onRuns.count, 1, "re-emitted once: Panel opens the run once")
    compare(onRuns.signalArguments[0][0], "r-1")
''', '')
rep('''  // A-S4 and Review Focus 1, 2
  function test_a_write_to_the_run_store_shim_reaches_the_dispatch_form() {
    failOnWarning(/Binding loop/)
    var app = make(); if (!app) return
    app.runs.runSettingsRunner.cancel()
    app.runs.runSettings = { verify: ["make check"] }
    verify(app.runDispatch.runSettings === app.runs.runSettings)
    var cards = dispatchCards()
    compare(app.runDispatch.openDispatch(cards.m1, cards), true)
    compare(app.runDispatch.dispatchForm.verify[0], "make check")
  }

''', '')
p.write_text(t)
```

Run: `python3 /tmp/5-2/t1.py .`
Expected: no output, exit 0.

- [ ] **Step 3: Move every remaining `app.runs.<moved>` path to its owner**

The two renames are handled first, then each moved name goes to its owner. The `dispatchStarted` spy at `:387` gets `target: app.runDispatch`. The `runSettings` reads at `:710`, `:723` and `:778` become `app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project)`, which is the binding they were proving. Every message stays as written.

Save as `/tmp/5-2/t1b.py`:

```python
import re, sys
from pathlib import Path

p = Path(sys.argv[1]) / "tests/core/stores/tst_app_runs.qml"
CONTROL = ("pending stillWaiting stillWaitingText lastControlError lastControlErrorRunId cancelRunId cancelOpen "
           "cancelText cancelError flashText controlRunners pendingTimer flashTimer notifyOnEscalation notifySaved "
           "notifyTouched settingsLoadRunner settingsSaveRunner control refusalOf flash openCancel closeCancel "
           "confirmCancel setNotifyOnEscalation").split()
ALERTS = ("armedRoots alertsArmed toasts toastMs toastTimer notifyRunners raiseAlerts expireToasts dismissToast "
          "dismissAllToasts notify").split()
DISPATCH = ("dispatchState dispatchTarget dispatchTargetLabel dispatchForm dispatchPreview dispatchError "
            "dispatchErrorType dispatchErrors dispatchSuggest dispatchRunId dispatchMessage dispatchLog "
            "dispatchLogTail dispatchExitCode dispatchDefaultsRunner dispatchPreviewRunner dispatchDebounceTimer "
            "dispatchStartRunners dispatchStarted openDispatch closeDispatch retargetToMilestone setDispatchField "
            "dispatchStart checkDispatch").split()
OWNER = {**{n: "runControl" for n in CONTROL}, **{n: "runAlerts" for n in ALERTS},
         **{n: "runDispatch" for n in DISPATCH}}

text = p.read_text()
renamed = text.count("app.runs.runSettingsRunner")
text = text.replace("app.runs.runSettingsRunner", "app.runControl.runSettingsLoadRunner")
read = text.count("app.runs.runSettings")
text = text.replace("app.runs.runSettings", "app.runControl.runSettingsOf(app.runs.project)")
pattern = re.compile(r"\bapp\.runs\.(" + "|".join(sorted(OWNER, key=len, reverse=True)) + r")\b")
text, moved = pattern.subn(lambda m: "app." + OWNER[m.group(1)] + "." + m.group(1), text)
spy_old = 'target: app.runs, signalName: "dispatchStarted"'
spies = text.count(spy_old)
text = text.replace(spy_old, 'target: app.runDispatch, signalName: "dispatchStarted"')
p.write_text(text)
print(f"runSettingsRunner {renamed}, runSettings {read}, moved {moved}, spies {spies}")
```

Run: `python3 /tmp/5-2/t1b.py .`
Expected: `runSettingsRunner 5, runSettings 7, moved 72, spies 1`

- [ ] **Step 4: Check that nothing in the file reaches a moved member or a handle through `app.runs`**

Run:
```bash
grep -nE 'app\.runs\.(pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation|runSettings|runSettingsRunner|armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify|dispatch[A-Za-z]*|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|checkDispatch|controlStore|alertsStore)\b|target: app\.runs, signalName: "dispatch' tests/core/stores/tst_app_runs.qml
```
Expected: no output (exit 1).

- [ ] **Step 5: Run the suite**

Run: `timeout 900 bash tests/run.sh tst_app_runs`
Expected: pytest passes, then `Totals: 48 passed, 0 failed` (one test deleted), with no `TypeError` or `non-existent` lines.

- [ ] **Step 6: Commit**

```bash
git add tests/core/stores/tst_app_runs.qml
git commit -m "test(runs): the App composition suite reads run control, alerts and the dispatch on their own stores"
```

---

### Task 2: The run store suites wire no handle and read each moved member on its owner

**Files:**
- Modify: `tests/core/stores/tst_run_store.qml` (`:1-11`, `:52-107`, the 37 reads listed below, `:3465-3876`)
- Modify: `tests/core/stores/tst_run_control_store.qml:530-541`, `:1429`, `:1516-1526`
- Modify: `tests/core/stores/tst_run_alerts_store.qml:308-318`, `:874`
- Modify: `tests/core/stores/tst_run_dispatch_store.qml:40`, `:52`

**Interfaces:**
- Consumes: the test helpers `controlOf(store)` and `alerts(store)` in `tst_run_store.qml`, and `RunDispatchStore`'s inputs and signals (`project`, `active`, `runs`, `runSettings`, `refreshRequested`, `noticeRequested`, `runSettingsWanted`, `runSettingsSaveRequested`, `dispatchSaveFailed`), unchanged.
- Produces: the test helpers `wireDispatch(store, bound) -> RunDispatchStore` and `dispatchOf(store) -> RunDispatchStore | null` (pairs kept in `tc.dispatchPairs`), and `dispatchCards() -> {m1, s1, t1, d1}`, now beside `wireAlerts` in `tst_run_store.qml`. These suites assign no handle on a `RunStore`. That is the precondition for Task 3's deletion.

This task changes tests only, and every suite stays green with the shims still present. `test_opening_the_run_store_alone_reads_no_switch` (R5) still reads three shims on a bare run store. Task 3 rewrites it as part of that task's red step.

- [ ] **Step 1: Run the four suites to record the baseline**

Run: `timeout 900 bash tests/run.sh tst_run_`
Expected: pytest passes. Then `tst_run_alerts_store` reports 38 passed, `tst_run_control_store` 70 passed, `tst_run_dispatch_store` 69 passed and `tst_run_store` 197 passed, all with 0 failed.

- [ ] **Step 2: Rework `tst_run_store.qml`'s wiring and delete its shim sections**

This step makes these edits:
- `wireControl` and `wireAlerts` stop setting the handles, and their comments drop the handle wording.
- `wireDispatch` moves up beside the other wiring helpers with `dispatchCards`. It stops setting `store.dispatchStore` and records its pair, read through `dispatchOf(store)`.
- The four shim sections are deleted: the alerts shims (R9, R10 and one unnumbered test), the run control shims R1-R3, the dispatch shims R-D1 to R-D4, and the run settings shims R-S1 to R-S3.
- R4, R5 and R-D5 stay under a new heading, `// ---- the run store alone`:
  - R4 drops `store.controlStore = c` and its last `store.pending` line.
  - R-D5 calls `d.openDispatch`.
  - R5 is unchanged here.
- The header comment names the dispatch wiring.

Save as `/tmp/5-2/t2.py`:

```python
import sys
from pathlib import Path
p = Path(sys.argv[1]) / "tests/core/stores/tst_run_store.qml"
t = p.read_text()
def rep(old, new):
    global t
    assert t.count(old) == 1, (t.count(old), old[:80])
    t = t.replace(old, new)

# header
rep('''// project switch leaves alone, and the snapshotReplied it emits. Built
// directly, wired to a RunControlStore and a RunAlertsStore the way App wires
// app.runControl and app.runAlerts, and driven through stubbed Process
// objects.''', '''// project switch leaves alone, and the snapshotReplied it emits. Built
// directly, wired to a RunControlStore and a RunAlertsStore the way App wires
// app.runControl and app.runAlerts (and, where a test needs it, a
// RunDispatchStore the way App wires app.runDispatch), and driven through
// stubbed Process objects.''')
# wireControl
rep('''  // backendDir copied; project, active and runs bound to the run store's own;
  // store.controlStore set; an ok snapshotReplied settles its requests; its
  // refreshRequested goes to refresh() ("all") or requestSnapshot(roots).
  function wireControl(store) {''', '''  // backendDir copied; project, active and runs bound to the run store's own;
  // an ok snapshotReplied settles its requests; its refreshRequested goes to
  // refresh() ("all") or requestSnapshot(roots).
  function wireControl(store) {''')
rep('''    store.controlStore = c
    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
''', '''    store.snapshotReplied.connect(function(root, outcome) { if (outcome === "ok") c.settleAfterSnapshot() })
''')
# wireAlerts
rep('''  // backendDir copied; active and projectRoots bound to the run store's own,
  // notifyOnEscalation bound to the paired control store's; store.alertsStore
  // set; snapshotReplied routed to it.''', '''  // backendDir copied; active and projectRoots bound to the run store's own,
  // notifyOnEscalation bound to the paired control store's; snapshotReplied
  // routed to it.''')
rep('''    a.projectRoots = Qt.binding(function() { return store.projectRoots })
    store.alertsStore = a
''', '''    a.projectRoots = Qt.binding(function() { return store.projectRoots })
''')
# wireDispatch + dispatchOf + dispatchCards, after alerts(store)
rep('''      if (tc.alertsPairs[i].store === store) return tc.alertsPairs[i].alerts
    }
    return null
  }
''', '''      if (tc.alertsPairs[i].store === store) return tc.alertsPairs[i].alerts
    }
    return null
  }

  // Every {store, dispatch} pair wireDispatch made.
  property var dispatchPairs: []

  // A RunDispatchStore with backendDir copied. When `bound`, it is wired the
  // way App wires app.runDispatch: project, active and runs bound to the run
  // store's own, runSettings to the paired control store's
  // runSettingsOf(project); refreshRequested to refresh() ("all") or
  // requestSnapshot(roots); noticeRequested to the paired control store's
  // flash; runSettingsWanted and runSettingsSaveRequested to its
  // loadRunSettings and saveRunSettings, and its runSettingsSaveFailed back to
  // dispatchSaveFailed. Otherwise nothing is bound or routed.
  function wireDispatch(store, bound) {
    var comp = Qt.createComponent("../../../core/stores/RunDispatchStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    var d = comp.createObject(tc, { backendDir: store.backendDir })
    if (bound) {
      d.project = Qt.binding(function() { return store.project })
      d.active = Qt.binding(function() { return store.active })
      d.runs = Qt.binding(function() { return store.runs })
      d.runSettings = Qt.binding(function() { return controlOf(store).runSettingsOf(store.project) })
      d.refreshRequested.connect(function(roots) {
        if (roots === "all") store.refresh()
        else store.requestSnapshot(roots)
      })
      d.noticeRequested.connect(function(text) { controlOf(store).flash(text) })
      var c = controlOf(store)
      d.runSettingsWanted.connect(function(root) { c.loadRunSettings(root) })
      d.runSettingsSaveRequested.connect(function(root, patch) { c.saveRunSettings(root, patch) })
      c.runSettingsSaveFailed.connect(function(root, patch) { d.dispatchSaveFailed(root, patch) })
    }
    tc.dispatchPairs = tc.dispatchPairs.concat([{ store: store, dispatch: d }])
    return d
  }

  // The RunDispatchStore wireDispatch paired with `store`; null when none.
  function dispatchOf(store) {
    for (var i = 0; i < tc.dispatchPairs.length; i++) {
      if (tc.dispatchPairs[i].store === store) return tc.dispatchPairs[i].dispatch
    }
    return null
  }

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
''')
# the shim sections: everything from R9 to the end of the file
start = "\n\n  // R9\n  function test_without_an_alerts_store_the_shims_are_empty_and_inert() {"
assert t.count(start) == 1
t = t[:t.index(start)] + '''

  // ---- the run store alone

  // R4
  function test_a_snapshot_settles_nothing_without_the_route() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    var cc = Qt.createComponent("../../../core/stores/RunControlStore.qml")
    if (cc.status !== Component.Ready) { fail(cc.errorString()); return }
    var c = cc.createObject(tc, { backendDir: "/plugin/core/backend/" })
    c.runs = Qt.binding(function() { return store.runs })
    store.projectRoots = [rootEntry(rootA)]
    store.project = rootA
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    compare(c.control("pause", "r1"), true)
    reply(c.controlRunners[0].current, ctlOk({ requested_at: "t1" }), 0)
    snapshot(store, [ctlEntry("r1", "started", true, "milestone",
                              [{ command: "pause", requested_at: "t1", handled_at: "t1h" }])])
    compare(store.amStatus, "ok")
    compare(c.pending.r1, "pause", "the run store no longer settles requests itself")
  }

  // R5 and Review Focus 1, 5
  function test_opening_the_run_store_alone_reads_no_switch() {
    var comp = Qt.createComponent("../../../core/stores/RunStore.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var store = comp.createObject(tc, { backendDir: "/plugin/core/backend/" })
    store.projectRoots = [rootEntry(rootA)]
    reply(store.snapshotRunner.current, okReply([running("r1")]), 0)
    var seq = store.snapshotRunner.seq
    store.active = true
    compare(store.settingsLoadRunner, null, "no handle: no switch to read")
    compare(store.settingsSaveRunner, null)
    compare(store.notifyOnEscalation, false)
    compare(store.snapshotRunner.seq, seq + 1, "the opening still snapshots")
    verify(store.snapshotRunner.current)
  }

  // R-D5 and Review Focus 4
  function test_closing_and_switching_the_run_store_touch_no_dispatch() {
    var store = makeWithProject(rootA); if (!store) return
    var d = wireDispatch(store, false); if (!d) return
    d.project = rootA
    var cards = dispatchCards()
    compare(d.openDispatch(cards.m1, cards), true)
    compare(d.dispatchState, "previewing")
    store.active = true
    store.active = false
    compare(d.dispatchState, "previewing", "closing the run store leaves the dispatch")
    store.project = rootB
    compare(d.dispatchState, "previewing", "switching the run store's project leaves the dispatch")
  }
}
'''
p.write_text(t)
```

Run: `python3 /tmp/5-2/t2.py .`
Expected: no output, exit 0.

- [ ] **Step 3: Move the 37 run-store reads above the new section to their owners**

This step changes the reads at `:301-367`, `:446`, `:473-509` (`:509` is `dispatchOf(store).dispatchState`), `:534`, `:844-845`, `:1114-1151`, `:2688` (`pendingTimer`), `:2790` (`toastIds`), `:2841`, `:3056-3082` and `:3184-3216`, plus `closed.alertsArmed` at `:347`. Each read becomes `controlOf(<var>).X`, `alerts(<var>).X` or `dispatchOf(<var>).X`. The script refuses to run if a `runSettings` read is left, and it does not touch anything below `// ---- the run store alone`.

Save as `/tmp/5-2/t2b.py`:

```python
import re, sys
from pathlib import Path

p = Path(sys.argv[1]) / "tests/core/stores/tst_run_store.qml"
CONTROL = ("pending stillWaiting stillWaitingText lastControlError lastControlErrorRunId cancelRunId cancelOpen "
           "cancelText cancelError flashText controlRunners pendingTimer flashTimer notifyOnEscalation notifySaved "
           "notifyTouched settingsLoadRunner settingsSaveRunner control refusalOf flash openCancel closeCancel "
           "confirmCancel setNotifyOnEscalation").split()
ALERTS = ("armedRoots alertsArmed toasts toastMs toastTimer notifyRunners raiseAlerts expireToasts dismissToast "
          "dismissAllToasts notify").split()
DISPATCH = ("dispatchState dispatchTarget dispatchTargetLabel dispatchForm dispatchPreview dispatchError "
            "dispatchErrorType dispatchErrors dispatchSuggest dispatchRunId dispatchMessage dispatchLog "
            "dispatchLogTail dispatchExitCode dispatchDefaultsRunner dispatchPreviewRunner dispatchDebounceTimer "
            "dispatchStartRunners dispatchStarted openDispatch closeDispatch retargetToMilestone setDispatchField "
            "dispatchStart checkDispatch").split()
HELPER = {**{n: "controlOf" for n in CONTROL}, **{n: "alerts" for n in ALERTS},
          **{n: "dispatchOf" for n in DISPATCH}}

text = p.read_text()
cut = text.index("  // ---- the run store alone")
head, tail = text[:cut], text[cut:]
assert not re.search(r"\b(store|closed)\.runSettings", head), "a runSettings shim read needs a hand edit"
pattern = re.compile(r"\b(store|closed)\.(" + "|".join(sorted(HELPER, key=len, reverse=True)) + r")\b")
head, moved = pattern.subn(lambda m: f"{HELPER[m.group(2)]}({m.group(1)}).{m.group(2)}", head)
p.write_text(head + tail)
print(f"moved {moved}")
```

Run: `python3 /tmp/5-2/t2b.py .`
Expected: `moved 37`

- [ ] **Step 4: Remove the handle assignments and shim reads from the sibling suites**

`tst_run_control_store.qml` and `tst_run_dispatch_store.qml` drop `store.controlStore = c`, and `tst_run_alerts_store.qml` drops `store.alertsStore = a`. Their comments drop the handle wording. `tst_run_control_store.qml` `test_run_settings_kept_even_after_notify_touched` reads the switch and the run settings on `c`. `test_the_switch_saves_globally_and_a_failed_save_puts_it_back` loses `compare(store.notifyRunners.length, 0)`, because that suite wires no alerts store, so the line only ever read the shim's `[]`. `tst_run_alerts_store.qml` loses `compare(store.flashText, "")` for the same reason: no control store is wired there.

Save as `/tmp/5-2/t2c.py`:

```python
import sys
from pathlib import Path
root = Path(sys.argv[1]) / "tests/core/stores"
def edit(name, pairs):
    p = root / name
    t = p.read_text()
    for old, new in pairs:
        assert t.count(old) == 1, (name, t.count(old), old[:80])
        t = t.replace(old, new)
    p.write_text(t)

edit("tst_run_control_store.qml", [
('''  // backendDir copied; project, active and runs bound to the run store's own;
  // store.controlStore set; an ok snapshotReplied settles its requests; its
  // refreshRequested goes to refresh() ("all") or requestSnapshot(roots).''',
'''  // backendDir copied; project, active and runs bound to the run store's own;
  // an ok snapshotReplied settles its requests; its refreshRequested goes to
  // refresh() ("all") or requestSnapshot(roots).'''),
('''    store.controlStore = c
''', ''),
('''    compare(controlOf(store).notifyTouched, false)
    compare(store.notifyRunners.length, 0)
''', '''    compare(controlOf(store).notifyTouched, false)
'''),
('''    compare(Object.keys(store.runSettings).length, 0, "{} until the reply")
    var load = c.runSettingsLoadRunner.current
    store.setNotifyOnEscalation(true)
    reply(load, dispatchSettings(), 0)
    compare(store.notifyOnEscalation, true, "the switch keeps the user's value")
    compare(store.runSettings.prefixHistory.length, 1)
    compare(store.runSettings.prefixHistory[0], "old")
    compare(store.runSettings.parallelism, 4)
    compare(store.runSettings.confirmDispatch, true)
    compare(store.runSettings.verify[0], "uv run pytest")
    compare(store.runSettings.notifyOnEscalation, false, "the object is kept as it was read")''',
'''    compare(Object.keys(c.runSettingsOf(store.project)).length, 0, "{} until the reply")
    var load = c.runSettingsLoadRunner.current
    c.setNotifyOnEscalation(true)
    reply(load, dispatchSettings(), 0)
    compare(c.notifyOnEscalation, true, "the switch keeps the user's value")
    compare(c.runSettingsOf(store.project).prefixHistory.length, 1)
    compare(c.runSettingsOf(store.project).prefixHistory[0], "old")
    compare(c.runSettingsOf(store.project).parallelism, 4)
    compare(c.runSettingsOf(store.project).confirmDispatch, true)
    compare(c.runSettingsOf(store.project).verify[0], "uv run pytest")
    compare(c.runSettingsOf(store.project).notifyOnEscalation, false, "the object is kept as it was read")'''),
])
edit("tst_run_alerts_store.qml", [
('''  // backendDir copied; active and projectRoots bound to the run store's own;
  // store.alertsStore set; snapshotReplied routed to it. notifyOnEscalation is
  // left to each test.''',
'''  // backendDir copied; active and projectRoots bound to the run store's own;
  // snapshotReplied routed to it. notifyOnEscalation is left to each test.'''),
('''    store.alertsStore = a
''', ''),
('''    compare(toastIds(store), "a,b", "the replies change nothing else")
    compare(store.flashText, "")
''', '''    compare(toastIds(store), "a,b", "the replies change nothing else")
'''),
])
edit("tst_run_dispatch_store.qml", [
('''  // dispatchSaveFailed. The run store's dispatchStore handle is not set.
''', '''  // dispatchSaveFailed.
'''),
('''    store.controlStore = c
''', ''),
])
```

Run: `python3 /tmp/5-2/t2c.py .`
Expected: no output, exit 0.

- [ ] **Step 5: Check that no moved member or handle is reached through a run store**

Run:
```bash
M='pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation|runSettings|runSettingsRunner|armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify|dispatchState|dispatchTarget|dispatchTargetLabel|dispatchForm|dispatchPreview|dispatchError|dispatchErrorType|dispatchErrors|dispatchSuggest|dispatchRunId|dispatchMessage|dispatchLog|dispatchLogTail|dispatchExitCode|dispatchDefaultsRunner|dispatchPreviewRunner|dispatchDebounceTimer|dispatchStartRunners|dispatchStarted|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|dispatchStart|checkDispatch|controlStore|alertsStore|dispatchStore'
grep -nE "\b(store|closed)\.($M)\b" tests/core/stores/tst_run_store.qml
awk 'NR>523' tests/core/stores/tst_run_control_store.qml | grep -nE "\bstore\.($M)\b"
awk 'NR>301' tests/core/stores/tst_run_alerts_store.qml | grep -nE "\bstore\.($M)\b"
grep -nE "\b(store|c)\.(controlStore|alertsStore|dispatchStore)\b" tests/core/stores/tst_run_*_store.qml
```
Expected: the first grep prints exactly R5's three lines (`store.settingsLoadRunner`, `store.settingsSaveRunner`, `store.notifyOnEscalation`, near line 3549), which Task 3 rewrites. The other three print nothing. (In the sibling suites, `store` before those line numbers is the store under test, not a run store. In `tst_run_dispatch_store.qml`, `store` is the dispatch store everywhere.)

- [ ] **Step 6: Run the four suites**

Run: `timeout 900 bash tests/run.sh tst_run_`
Expected: pytest passes. Then `tst_run_alerts_store` reports 38 passed, `tst_run_control_store` 70 passed, `tst_run_dispatch_store` 69 passed and `tst_run_store` 184 passed (13 shim tests deleted), all with 0 failed and no `TypeError`, `non-existent` or `Unable to assign` lines.

- [ ] **Step 7: Commit**

```bash
git add tests/core/stores/tst_run_store.qml tests/core/stores/tst_run_control_store.qml tests/core/stores/tst_run_alerts_store.qml tests/core/stores/tst_run_dispatch_store.qml
git commit -m "test(runs): the run store suites wire no shim handle and read each moved member on its owner"
```

---

### Task 3: RunStore drops the shims and App drops the handles

**Files:**
- Modify: `tests/core/stores/tst_app_runs.qml` (new section before `// ---- app.runAlerts (split-runstore 2.2)`)
- Modify: `tests/core/stores/tst_run_store.qml` (R5, `test_opening_the_run_store_alone_reads_no_switch`)
- Modify: `core/stores/RunStore.qml:13-15`, `:32-34`, `:119-219`
- Modify: `core/stores/App.qml:103-116`

**Interfaces:**
- Consumes: Task 1's `tst_app_runs.qml` helper `makeBare()`, and Task 2's handle-free wiring.
- Produces: `RunStore` with no moved member and no handle. In `tst_app_runs.qml`: the arrays `movedToControl` (25 names), `renamedOnControl` (2), `movedToAlerts` (11), `movedToDispatch` (25) and `runStoreHandles` (3), and the helper `answered(obj, names, present) -> [name]`.

- [ ] **Step 1: Write the failing tests**

This step adds `test_the_run_store_has_none_of_the_moved_members` and `test_each_owner_answers_to_its_moved_members` to `tst_app_runs.qml`. Absence is checked with `typeof obj[name] === "undefined"`, not `in`. None of the 66 names collides with a `QObject` built-in. Each test gathers every offending name into one failure message. It also rewrites R5 in `tst_run_store.qml`, so that each of its three switch members must be absent from a bare run store.

Save as `/tmp/5-2/t3a.py`:

```python
import sys
from pathlib import Path
root = Path(sys.argv[1]) / "tests/core/stores"
def edit(name, pairs):
    p = root / name
    t = p.read_text()
    for old, new in pairs:
        assert t.count(old) == 1, (name, t.count(old), old[:80])
        t = t.replace(old, new)
    p.write_text(t)

edit("tst_app_runs.qml", [
('''  // ---- app.runAlerts (split-runstore 2.2)
''', '''  // ---- the run store keeps none of the moved members (split-runstore 5.2)

  // The members that moved out of the run store, by the store that owns them,
  // in the order of MOVED in tests/architecture/test_run_store_callers.py.
  // runSettings and runSettingsRunner have other names on run control.
  property var movedToControl: ["pending", "stillWaiting", "stillWaitingText", "lastControlError",
    "lastControlErrorRunId", "cancelRunId", "cancelOpen", "cancelText", "cancelError", "flashText",
    "controlRunners", "pendingTimer", "flashTimer", "notifyOnEscalation", "notifySaved", "notifyTouched",
    "settingsLoadRunner", "settingsSaveRunner", "control", "refusalOf", "flash", "openCancel", "closeCancel",
    "confirmCancel", "setNotifyOnEscalation"]
  property var renamedOnControl: ["runSettings", "runSettingsRunner"]
  property var movedToAlerts: ["armedRoots", "alertsArmed", "toasts", "toastMs", "toastTimer", "notifyRunners",
    "raiseAlerts", "expireToasts", "dismissToast", "dismissAllToasts", "notify"]
  property var movedToDispatch: ["dispatchState", "dispatchTarget", "dispatchTargetLabel", "dispatchForm",
    "dispatchPreview", "dispatchError", "dispatchErrorType", "dispatchErrors", "dispatchSuggest", "dispatchRunId",
    "dispatchMessage", "dispatchLog", "dispatchLogTail", "dispatchExitCode", "dispatchDefaultsRunner",
    "dispatchPreviewRunner", "dispatchDebounceTimer", "dispatchStartRunners", "dispatchStarted", "openDispatch",
    "closeDispatch", "retargetToMilestone", "setDispatchField", "dispatchStart", "checkDispatch"]
  // The handles the run store once read the moved members through.
  property var runStoreHandles: ["controlStore", "alertsStore", "dispatchStore"]

  // The names of `names` that `obj` answers to (present) or does not (absent).
  function answered(obj, names, present) {
    return names.filter(function(name) { return (typeof obj[name] !== "undefined") === present })
  }

  function test_the_run_store_has_none_of_the_moved_members() {
    var app = makeBare(); if (!app) return
    var names = tc.movedToControl.concat(tc.renamedOnControl, tc.movedToAlerts, tc.movedToDispatch, tc.runStoreHandles)
    compare(names.length, 66, "63 moved members and 3 handles")
    compare(answered(app.runs, names, true).join(", "), "", "the run store still answers to these")
    compare(answered(app.runs, ["runs", "project", "refresh", "requestSnapshot", "snapshotReplied", "runsChanged"],
                     false).join(", "), "", "members that stay are still there")
  }

  function test_each_owner_answers_to_its_moved_members() {
    var app = makeBare(); if (!app) return
    compare(answered(app.runControl, tc.movedToControl, false).join(", "), "", "run control lacks these")
    compare(answered(app.runControl, ["runSettingsLoadRunner", "runSettingsOf", "applyRunSettings"], false).join(", "), "",
            "run control lacks the renamed run settings members")
    compare(answered(app.runAlerts, tc.movedToAlerts, false).join(", "), "", "the alerts lack these")
    compare(answered(app.runDispatch, tc.movedToDispatch, false).join(", "), "", "the dispatch lacks these")
  }

  // ---- app.runAlerts (split-runstore 2.2)
'''),
])
edit("tst_run_store.qml", [
('''    store.active = true
    compare(store.settingsLoadRunner, null, "no handle: no switch to read")
    compare(store.settingsSaveRunner, null)
    compare(store.notifyOnEscalation, false)
''', '''    store.active = true
    var names = ["settingsLoadRunner", "settingsSaveRunner", "notifyOnEscalation"]
    for (var i = 0; i < names.length; i++)
      compare(typeof store[names[i]], "undefined", names[i] + ": the run store has no switch to read")
'''),
])
```

Run: `python3 /tmp/5-2/t3a.py .`
Expected: no output, exit 0.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh tst_app_runs; timeout 900 bash tests/run.sh tst_run_store`
Expected:
- `tst_app_runs`: `FAIL!  : ...test_the_run_store_has_none_of_the_moved_members() the run store still answers to these`, `Totals: 49 passed, 1 failed`. The `Actual` line lists all 66 names.
- `tst_run_store`: `FAIL!  : ...test_opening_the_run_store_alone_reads_no_switch() settingsLoadRunner: the run store has no switch to read`, `Totals: 183 passed, 1 failed`.
- `test_each_owner_answers_to_its_moved_members` already passes. It pins that the deletion drops nothing.

- [ ] **Step 3: Delete the shims and the handles**

This step deletes everything in `RunStore.qml` from `// Moved to RunControlStore; removed by the last story` up to, but not including, `// A debounce window's nudged run ids`:
- the three shim blocks and their `Binding`s,
- the `on…Changed` write-back handlers,
- the `dispatchStarted` signal and its `Connections`,
- the three handles.

It rewrites the two header passages: `project` is now the open project's root, an input App hands on to the other run stores, and the dispatch-shim sentence goes. In `App.qml` it drops `alertsStore`, `controlStore` and `dispatchStore` on `runs`, and their mention in the comment above.

Save as `/tmp/5-2/t3b.py`:

```python
import sys
from pathlib import Path
root = Path(sys.argv[1]) / "core/stores"
def edit(name, pairs):
    p = root / name
    t = p.read_text()
    for old, new in pairs:
        assert t.count(old) == 1, (name, t.count(old), old[:80])
        t = t.replace(old, new)
    p.write_text(t)

p = root / "RunStore.qml"
t = p.read_text()
start = "  // Moved to RunControlStore; removed by the last story\n"
end = "  // A debounce window's nudged run ids, each once, in first-nudge order,\n"
assert t.count(start) == 1 and t.count(end) == 1
t = t[:t.index(start)] + t[t.index(end):]
p.write_text(t)
edit("RunStore.qml", [
('''// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project, is read only
// by the run settings shims; the attempt logs act on each run's own project
// root. Plus the selected run, the''', '''// order, a run id listed once, under the first root that lists it. A project
// switch leaves the run list alone: `project`, the open project's root, is an
// input App hands on to the other run stores; the attempt logs act on each
// run's own project root. Plus the selected run, the'''),
('''// status -- never on a timer.
// The dispatch is RunDispatchStore's; its members here are shims through
// `dispatchStore`. Each applied list snapshot reply is announced per project
// (snapshotReplied).''', '''// status -- never on a timer.
// Each applied list snapshot reply is announced per project
// (snapshotReplied).'''),
])
edit("App.qml", [
('''  // path (never the project object), the panel-open flag that starts and
  // stops its watch, and the stores its shims read (controlStore,
  // alertsStore, dispatchStore).''', '''  // path (never the project object) and the panel-open flag that starts and
  // stops its watch.'''),
('''    searchQuery: app.nav.searchQuery
    alertsStore: app.runAlerts
    controlStore: app.runControl
    dispatchStore: app.runDispatch
''', '''    searchQuery: app.nav.searchQuery
'''),
])
```

Run: `python3 /tmp/5-2/t3b.py .`
Expected: no output, exit 0. `git diff --stat core` shows about 111 lines changed in `RunStore.qml` and 8 in `App.qml`.

- [ ] **Step 4: Read the results**

Run: `sed -n '7,38p' core/stores/RunStore.qml; sed -n '100,112p' core/stores/App.qml`
Expected:
- The `RunStore` header reads `... A project switch leaves the run list alone: \`project\`, the open project's root, is an input App hands on to the other run stores; the attempt logs act on each run's own project root. ...`. Below it come `// status -- never on a timer.`, `// Each applied list snapshot reply is announced per project` and `// (snapshotReplied).`.
- Nothing in the header mentions shims or handles.
- In `App.qml`, `runs` is `backendDir`, `projectRoots`, `project`, `active`, `searchQuery` and the three handlers, and its comment ends `... the selected project's root path (never the project object) and the panel-open flag that starts and stops its watch.`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh tst_app_runs; timeout 900 bash tests/run.sh tst_run_`
Expected: `tst_app_runs` 50 passed, `tst_run_store` 184 passed, `tst_run_control_store` 70, `tst_run_alerts_store` 38 and `tst_run_dispatch_store` 69, all with 0 failed and no `TypeError`, `non-existent` or `Unable to assign` lines.

- [ ] **Step 6: Run the full suite**

Run: `timeout 1500 bash tests/run.sh`
Expected: exit 0. pytest passes, including `tests/architecture`, and every `tst_*.qml` reports 0 failed, with no flagged lines.

- [ ] **Step 7: Check the acceptance greps**

Run:
```bash
grep -nE 'shim|controlStore|alertsStore|dispatchStore' core/stores/RunStore.qml core/stores/App.qml
grep -rnE 'controlStore|alertsStore|dispatchStore' core ui tests | grep -v 'tst_run_dispatch_store.qml:.*dispatchStore()'
M='pending|stillWaiting|stillWaitingText|lastControlError|lastControlErrorRunId|cancelRunId|cancelOpen|cancelText|cancelError|flashText|controlRunners|pendingTimer|flashTimer|notifyOnEscalation|notifySaved|notifyTouched|settingsLoadRunner|settingsSaveRunner|control|refusalOf|flash|openCancel|closeCancel|confirmCancel|setNotifyOnEscalation|runSettings|runSettingsRunner|armedRoots|alertsArmed|toasts|toastMs|toastTimer|notifyRunners|raiseAlerts|expireToasts|dismissToast|dismissAllToasts|notify|dispatchState|dispatchTarget|dispatchTargetLabel|dispatchForm|dispatchPreview|dispatchError|dispatchErrorType|dispatchErrors|dispatchSuggest|dispatchRunId|dispatchMessage|dispatchLog|dispatchLogTail|dispatchExitCode|dispatchDefaultsRunner|dispatchPreviewRunner|dispatchDebounceTimer|dispatchStartRunners|dispatchStarted|openDispatch|closeDispatch|retargetToMilestone|setDispatchField|dispatchStart|checkDispatch'
grep -nE "\b(store|closed)\.($M)\b" tests/core/stores/tst_run_store.qml
grep -rnE "\.runs\.($M)\b" core tests --include=*.qml --include=*.js
```
Expected:
- First grep: no output.
- Second: only the `runStoreHandles` line in `tests/core/stores/tst_app_runs.qml`.
- Third and fourth: no output.

- [ ] **Step 8: Commit**

```bash
git add core/stores/RunStore.qml core/stores/App.qml tests/core/stores/tst_app_runs.qml tests/core/stores/tst_run_store.qml
git commit -m "refactor(runs): RunStore drops the shims and App the handles; an App test pins that they are gone"
```

---

## Self-review against the spec

- **RunStore declares none of the moved members (Behaviour, Acceptance 1):** Task 3 Step 3 deletes `:119-219`, and Step 1's absence test pins all 66 names. The header passages `:13-14` and `:32-33` are rewritten, and `project` stays.
- **App sets no handle (Acceptance 2):** Task 3 Step 3, checked by Step 7's first grep.
- **Every test outside `tests/ui/` reads a moved member on its owner:** `tst_app_runs.qml` (Task 1), `tst_run_store.qml` and the three sibling suites (Task 2), with greps in Task 1 Step 4, Task 2 Step 5 and Task 3 Step 7.
- **Absence test and owner test (Tests 1-2, Acceptance 4):** Task 3 Step 1.
- **Composition tests assert every input (Tests 3):**
  - `runAlerts` already asserts all four inputs, and Task 1 drops only its handle line.
  - `runControl` gains `project` across a selection change (Task 1 Step 2) beside `backendDir`, `active` and `runs`.
  - `runDispatch` asserts `backendDir`, `project`, `active`, `runs` and, after Task 1 Step 3, `runSettings === app.runControl.runSettingsOf(app.runs.project)`.
- **Shim-equality assertions (Tests 4):** `:524`, `:577`, `:586` and `:667` are deleted in Task 1 Step 2. `:710`, `:723` and `:778` become the `runSettingsOf` binding in Task 1 Step 3, and `:822` goes with its test.
- **Write-shim test deleted (Tests 5):** Task 1 Step 2.
- **`tst_run_store.qml` helpers, shim sections, R4/R5/R-D5 (spec "tst_run_store.qml"):**
  - Task 2 Step 2 covers the helpers, the shim sections, R4 and R-D5.
  - Task 2 Step 3 moves the 37 reads.
  - Task 3 Step 1 rewrites R5.
  - The section heading becomes `// ---- the run store alone`.
- **Sibling suites:** Task 2 Step 4. Beyond the spec, it also clears the shim reads Review Focus 1 lists.
- **Deviation from the spec:** `test_a_start_through_app_announces_started_once_on_each_store` asserted the run store's re-emit of `dispatchStarted`, a shim. That spy is dropped and the test is renamed `test_a_start_through_app_announces_started_once` (Task 1 Step 2). The spec's "move to owner" would have duplicated the `runDispatch` spy.
- **Deviation from the spec's TDD order:** the spec writes the absence test first. Here Tasks 1-2 move the tests while the shims exist, so every commit is green. The absence test is still red before the deletion (Task 3 Step 2) and green after it (Step 5).
- **Placeholders:** none. Every edit is an exact anchor/replacement or a counted substitution.
- **Names:** `controlOf`, `alerts`, `dispatchOf`, `wireDispatch(store, bound)`, `dispatchCards`, `answered`, `movedToControl`, `renamedOnControl`, `movedToAlerts`, `movedToDispatch` and `runStoreHandles` are used consistently across the tasks.

---

## The spec (verbatim)

## 5.2 RunStore shims removed — design

Card: `173b82e2` ("5.2 RunStore shims removed"). It is a subtask of story `97aa329f` "Retire the
RunStore shims". It is blocked by 5.1 `68b40cb3` ("ui callers use the new run stores"), which has
landed on this branch (`ba0457d`), and its sibling is 5.3 `e7709c33` ("Docs: the four run stores").
The parent design is `docs/superpowers/specs/2026-10-05-split-runstore-design.md`, cited below as
"P l.N". Line numbers into `core/` and `tests/` come from this card's start (`ba0457d`).

### Purpose

Subtasks 2.2, 3.1, 3.2, 4.1 and 4.2 moved the run alerts, the run controls, the dispatch and the
run settings out of `RunStore` into `RunAlertsStore`, `RunControlStore` and `RunDispatchStore`.
They left `RunStore` a shim of the same name for each moved member, read through three handles
that App sets (P l.122-127). 5.1 moved every `ui/` and `tests/ui/` caller to `app.runControl`,
`app.runAlerts` and `app.runDispatch`. This card does the rest (P l.128-130):

- `RunStore` declares none of the moved members and none of the three handles.
- App no longer sets the handles.
- Every test outside `tests/ui/` that still reaches a moved member through the run store reaches
  it on the store that owns it.
- An App test asserts that `RunStore` has none of the moved members, and that each of the three
  new stores is composed with its inputs (P l.129-130, l.163-164).

A user sees nothing different. No helper gets a different argv, and no process starts at a
different moment (P l.146-147). The full suite passes.

### Scope

#### In scope

- `core/stores/RunStore.qml`: delete the three shim blocks and fix the header comment.
- `core/stores/App.qml`: delete the three handle lines and fix the comment above `runs`.
- `tests/core/stores/tst_app_runs.qml`: the new absence test, the composition assertions, and every
  `app.runs.<moved>` path.
- `tests/core/stores/tst_run_store.qml`: the shim test sections, the handle assignments in the
  wiring helpers, and every `store.<moved>` read in the remaining tests.
- `tests/core/stores/tst_run_control_store.qml`, `tst_run_alerts_store.qml` and
  `tst_run_dispatch_store.qml`: their handle assignments and the comments that name the handles.

#### Out of scope

- **5.3** owns `docs/architecture.md` and `README.md`. That includes the shim paragraph at
  `docs/architecture.md:91` and the `app.runs` mentions at `:83` and `:167`. This card edits no doc
  apart from this spec and its plan.
- `ui/` and `tests/ui/`: 5.1 finished them, and `tests/architecture/test_run_store_callers.py`
  already guards them.
- `RunControlStore.qml`, `RunAlertsStore.qml` and `RunDispatchStore.qml`: no change. Their public
  members, inputs and signals stay as they are.
- No new member, signal or input on any store. No renamed member that stays.
- No change to what any remaining test expects. Only the store a test reads a member from changes,
  and the construction of the tests that exist only to test the shims (they are deleted, see
  "Tests").
- The members Appendix A lists as "not present at this commit" (P l.407-416). None of them exists,
  so there is nothing of theirs to delete.

### Inherited constraints

| constraint | source |
|---|---|
| Owners: `RunStore` = `app.runs`, `RunControlStore` = `app.runControl`, `RunAlertsStore` = `app.runAlerts`, `RunDispatchStore` = `app.runDispatch` | P l.52-57 |
| A store never imports or names a sibling; the shim handles were the one temporary exception, and the last story removes them | P l.46-50 |
| Every member lands in exactly one store; nothing is duplicated | P l.61-63 |
| Inputs come from App; each store gets only what it reads (the inputs table) | P l.71-79 |
| `RunStore`'s inputs include `project` (the open root) | P l.76 |
| The last story deletes the shims and the handles; an App test then asserts that `RunStore` has none of the moved members | P l.128-130 |
| No behaviour change, no new helper argv, no change to which process starts when | P l.146-147 |
| Tests move with their members; only construction and wiring change, never an expectation | P l.98-104 |
| `tests/architecture` stays green: store imports, no duplicated shared patterns, layer allowlists, icon glyph rules | P l.105-106; card |
| The last story: the App test asserts that the shims are gone | P l.163-164 |
| Docstrings and comments state the contract only, with no narrative | card |
| Verification: `bash tests/run.sh` green | card |

### The moved members

The set is `MOVED` in `tests/architecture/test_run_store_callers.py:15-79` (63 names). It is the
shim set at `core/stores/RunStore.qml:119-217`, the members of P Appendix A.1 whose target is not
`RunStore` and that exist at this commit:

- **Run control** (`RunStore.qml:119-166`): `pending`, `stillWaiting`, `stillWaitingText`,
  `lastControlError`, `lastControlErrorRunId`, `cancelRunId`, `cancelOpen`, `cancelText`,
  `cancelError`, `flashText`, `controlRunners`, `pendingTimer`, `flashTimer`,
  `notifyOnEscalation`, `notifySaved`, `notifyTouched`, `settingsLoadRunner`,
  `settingsSaveRunner`, `control`, `refusalOf`, `flash`, `openCancel`, `closeCancel`,
  `confirmCancel`, `setNotifyOnEscalation`, `runSettings`, `runSettingsRunner`.
- **Alerts** (`RunStore.qml:168-180`): `armedRoots`, `alertsArmed`, `toasts`, `toastMs`,
  `toastTimer`, `notifyRunners`, `raiseAlerts`, `expireToasts`, `dismissToast`,
  `dismissAllToasts`, `notify`.
- **Dispatch** (`RunStore.qml:182-217`): `dispatchState`, `dispatchTarget`, `dispatchTargetLabel`,
  `dispatchForm`, `dispatchPreview`, `dispatchError`, `dispatchErrorType`, `dispatchErrors`,
  `dispatchSuggest`, `dispatchRunId`, `dispatchMessage`, `dispatchLog`, `dispatchLogTail`,
  `dispatchExitCode`, `dispatchDefaultsRunner`, `dispatchPreviewRunner`, `dispatchDebounceTimer`,
  `dispatchStartRunners`, the signal `dispatchStarted`, `openDispatch`, `closeDispatch`,
  `retargetToMilestone`, `setDispatchField`, `dispatchStart`, `checkDispatch`.
- **The handles**: `controlStore`, `alertsStore`, `dispatchStore`.

Also deleted: the `Binding` objects and `on…Changed` handlers that served the writable shims
(`cancelRunId`, `cancelText`, `runSettings`, `dispatchState`), and the `Connections` that
re-emitted `dispatchStarted`.

Two shims have a different name on the store that owns them (5.1 spec, "The two shims whose names
differ"). A test that read them reads:

| shim on the run store | on `RunControlStore` |
|---|---|
| `runSettingsRunner` | `runSettingsLoadRunner` |
| `runSettings` (read) | `runSettingsOf(<run store>.project)` |
| `runSettings = X` (write) | `applyRunSettings(<run store>.project, X)` |

`RunControlStore.runSettings` is the `{root: settings}` map, not one project's settings. Never
compare one project's settings to it.

### Behaviour

#### `core/stores/RunStore.qml`

- After the change, the file declares none of the names in "The moved members". Nothing else
  changes: every member that stays keeps its name, type, default and behaviour.
- `project` stays. It is a `RunStore` input (P l.76), and App reads it as `app.runs.project` to
  feed `runControl.project`, `runDispatch.project` and `runDispatch.runSettings`
  (`App.qml:138`, `:167`, `:170`). After the change no code inside `RunStore` reads it.
- The header comment states the contract of what is left. Two passages go:
  - `:13-14` "`project`, the open project, is read only by the run settings shims". It becomes a
    statement that `project` is the open project's root, held for App, and that the store itself
    reads it for nothing (for example "A project switch leaves the run list alone; `project`, the
    open project's root, is an input App hands on to the other run stores").
  - `:32-33` "The dispatch is RunDispatchStore's; its members here are shims through
    `dispatchStore`." It goes. The sentence after it ("Each applied list snapshot reply is
    announced per project (snapshotReplied).") stays.
  - The comment says nothing about shims, handles or the other three stores' members.

#### `core/stores/App.qml`

- `runs` no longer sets `alertsStore`, `controlStore` or `dispatchStore` (`:114-116`).
- The comment above `runs` (`:103-106`) drops "and the stores its shims read (controlStore,
  alertsStore, dispatchStore)". It keeps the rest: the registry's roots and names in registry
  order, the selected project's root path, the panel-open flag.
- The `onSnapshotReplied` routing, `runControl`, `runAlerts` and `runDispatch` and their comments
  stay exactly as they are.

#### Error paths

There are none new. Each shim had a fallback for a missing handle (an empty value, or a function
that returned `undefined`). With the shims gone, a caller that names a moved member on `app.runs`
gets `undefined` for a property, and a `TypeError` for a call. 5.1's guard keeps `ui/` and
`tests/ui/` from doing that, and the absence test below pins the result for every name.

### Tests

TDD order: the absence test is written first and fails (every shim still answers). Then the core
deletions make it pass. The rest of the suite is then moved off the shims so that it passes again.

#### `tests/core/stores/tst_app_runs.qml` (QML unit tier, `qmltestrunner`)

This tier is right because the claims are about App's composed object graph. Only a real `App.qml`
instance shows which members `app.runs` answers to and what each new store is bound to.

New tests:

1. **`test_the_run_store_has_none_of_the_moved_members`.** For each of the 63 moved names and the
   three handle names, `typeof app.runs[name] === "undefined"`. It reports each name that is still
   there in one failure message (collect, then `compare(found, [])`), so a red run names every
   leftover. The list is written into the test, in the same order as `MOVED`.
   Against vacuity, the same test asserts that a few members that stay are defined:
   `runs`, `project`, `refresh`, `requestSnapshot`, `snapshotReplied`, `runsChanged`.
2. **`test_each_owner_answers_to_its_moved_members`.** For each moved name except the two renamed
   ones, `typeof app.<owner>[name] !== "undefined"`, where `<owner>` is `runControl`, `runAlerts`
   or `runDispatch` as listed in "The moved members". For `runSettingsRunner` the test checks
   `app.runControl.runSettingsLoadRunner`, and for `runSettings` it checks
   `app.runControl.runSettingsOf` and `applyRunSettings`. This shows that nothing was dropped
   (P l.61-63).

Changed tests:

3. **Composition tests** `test_app_composes_run_alerts_wired_to_the_run_store` (`:494`),
   `test_app_composes_run_control_wired_to_the_run_store` (`:551`) and
   `test_app_composes_run_dispatch_wired_to_the_run_store` (`:694`). Each drops its handle
   assertion (`:497`, `:554`, `:697`) and asserts every input of its store from P l.71-79 as App
   binds it (`App.qml:133-171`):
   - `runAlerts`: `backendDir`, `active`, `notifyOnEscalation` (follows
     `app.runControl.notifyOnEscalation`), `projectRoots` (`=== app.runs.projectRoots`). The test
     already asserts these (`:498-512`).
   - `runControl`: `backendDir`, `project` (follows `app.runs.project` across a selection change),
     `active` (follows `panelOpen`), `runs` (`=== app.runs.runs` after a snapshot).
   - `runDispatch`: `backendDir`, `project`, `active`, `runs`, and `runSettings`
     (`=== app.runControl.runSettingsOf(app.runs.project)` after the settings load replies).
   The test names keep "wired to the run store", because the inputs still come from `app.runs`.
   The assertions that each test already makes stay.
4. **Shim-equality assertions** `:524` (`app.runs.toasts === app.runAlerts.toasts`), `:577` and
   `:586` (`pending`), `:667` (`settingsLoadRunner`), `:710`, `:723`, `:778` and `:822`
   (`runSettings`). Each one compared a shim with its owner, so it is deleted. The owner-side
   assertion around it stays. `:710`, `:723`, `:778` and `:822` become
   `app.runDispatch.runSettings === app.runControl.runSettingsOf(app.runs.project)`, which is the
   binding they were proving.
5. **`test_a_write_to_the_run_store_shim_reaches_the_dispatch_form`** (`:817`). It tested the
   shim's write path, so it is deleted. `applyRunSettings` reaching the dispatch is the claim of
   `test_the_dispatch_reads_its_run_settings_from_run_control` (`:771`), which stays.
6. **Every other `app.runs.<moved>` path** in the file (`:178-184`, `:331-489`, `:709-727`, and
   any other hit for a moved name) goes to its owner, with the renames above. Each expectation and
   message stays as written.

#### `tests/core/stores/tst_run_store.qml` (QML unit tier)

This is the run store's own suite. After the change it builds `RunStore` beside its three
siblings, wired the way App wires them, and reads each moved member on its owner.

- **Helpers.** `wireControl` (`:57-70`) and `wireAlerts` (`:89-100`) stop setting
  `store.controlStore` / `store.alertsStore`. Every other binding and connection stays. Their
  comments drop "store.controlStore set" and "store.alertsStore set". `controlOf(store)` and
  `alerts(store)` stay.
- **`wireDispatch`** (`:3707-3729`) moves up beside the other wiring helpers, together with
  `dispatchCards` (`:3689-3696`), because `test_a_project_switch_leaves_the_run_list_and_the_live_state_alone`
  (`:465`) uses it. It stops setting `store.dispatchStore`. It records its pair the way the other
  two do (`dispatchPairs`, read through a `dispatchOf(store)` helper). Its comment drops "set as
  `store`'s dispatchStore handle".
- **Reads in the tests that stay.** Every `store.<moved>` before the shim sections goes to its
  owner: `controlOf(store).X`, `alerts(store).X` or `dispatchOf(store).X`. That is 36 hits at this
  commit, among them `:301-367`, `:473-509`, `:534`, `:844-845`, `:1114-1151`, `:2688`, `:2790`
  (`toastIds`), `:2841`, `:3056-3082`, `:3184-3216`. The helpers that take a run store and read a
  moved member (for example `toastIds`) read it on the owner. No expectation changes.
- **Shim sections deleted.** These sections exist only to test the shims, and each claim they make
  is either gone or already pinned on the owner's own suite:
  - `:3467-3524` "the alerts shims" (3 tests).
  - `:3526-3646` "the run control shims": the 3 shim tests at `:3529`, `:3569` and `:3613`.
  - `:3731-3826` "the dispatch shims" (5 tests, including the re-emit test at `:3804`).
  - `:3828-3876` "the run settings shims" (3 tests).
- **Two tests in the control section stay, rewritten:**
  - `test_a_snapshot_settles_nothing_without_the_route` (`:3648`) keeps its claim (a snapshot
    alone settles nothing in run control). It drops `store.controlStore = c` and the last line
    `compare(store.pending.r1, "pause")`. `compare(c.pending.r1, "pause", …)` stays.
  - `test_opening_the_run_store_alone_reads_no_switch` (`:3670`) keeps its claim (the run store
    opened alone launches no settings read, and it still snapshots). The three shim reads
    (`settingsLoadRunner`, `settingsSaveRunner`, `notifyOnEscalation` on the run store) become
    one assertion per name that `typeof store[name] === "undefined"`. The snapshot assertions
    stay.
  - Their section heading comment becomes one that names the claim, not the shims
    (for example "the run store alone").
- **`test_closing_and_switching_the_run_store_touch_no_dispatch`** (`:3814`) keeps its claim. Its
  `store.openDispatch(...)` becomes `d.openDispatch(...)`, and the test moves with
  `wireDispatch`.

#### `tests/core/stores/tst_run_control_store.qml`, `tst_run_alerts_store.qml`, `tst_run_dispatch_store.qml` (QML unit tier)

- `tst_run_control_store.qml:541` (`store.controlStore = c` in `wireControl`),
  `tst_run_alerts_store.qml:318` (`store.alertsStore = a` in `wireAlerts`) and
  `tst_run_dispatch_store.qml:52` (`store.controlStore = c`) are deleted. The comments that name
  them (`tst_run_control_store.qml:532`, `tst_run_alerts_store.qml:310`,
  `tst_run_dispatch_store.qml:40`, "The run store's dispatchStore handle is not set") drop the
  handle wording.
- No test in these files reads a moved member through a run store at this commit. A grep for
  `\.(<moved>)\b` on a run store variable must stay empty after the change.

#### `tests/architecture` (pytest tier)

No new test. `test_run_store_callers.py` keeps guarding `ui/` and `tests/ui/`. The whole directory
must stay green (P l.105-106).

#### Full suite

`bash tests/run.sh` passes: pytest, then every `tst_*.qml` under `qmltestrunner` (offscreen).

### Acceptance

1. `core/stores/RunStore.qml` declares none of the 63 moved names and none of the three handles,
   and no comment in it mentions shims or the handles.
2. `core/stores/App.qml` sets no handle on `runs`, and no comment in it mentions shims.
3. A grep of `core/`, `ui/` and `tests/` for `controlStore`, `alertsStore` and `dispatchStore`
   finds only test helper function names (`tst_run_dispatch_store.qml`'s `dispatchStore()`) and
   this card's absence test list.
4. `tst_app_runs.qml` has the absence test and the owner test, and the three composition tests
   assert each store's inputs.
5. `bash tests/run.sh` is green.

### Review focus for the planner

- **`in` versus `typeof`.** QML's `in` on a `QObject` wrapper is not a reliable absence check. Use
  `typeof app.runs[name] === "undefined"`. None of the 66 names collides with a `QObject` built-in
  (`objectName`, `destroyed`, `deleteLater`, `toString`), so `typeof` is exact.
- **A missed `store.<moved>` read in `tst_run_store.qml`.** A read of a deleted property returns
  `undefined`. `compare(store.toasts.length, 0)` throws, but a negative check such as
  `verify(!store.alertsArmed)` or `compare(store.pending.r1, undefined)`-style reads can pass by
  accident. After the edit, grep the file for every moved name on a run store variable and expect
  no hit.
- **`wireDispatch` callers.** It is used at `:467` before its definition section. When the shim
  section is deleted, it must survive, moved up with `dispatchCards`.
- **`runSettings` renames.** Any assertion that compared one project's settings to
  `RunControlStore.runSettings` (the map) is wrong. Use `runSettingsOf(project)`.
- **The `project` header comment.** `project` must stay a declared input even though `RunStore`
  reads it for nothing after the change. Deleting it would break App's bindings at `App.qml:138`,
  `:167` and `:170`.
<!-- task-pipeline: validated -->
