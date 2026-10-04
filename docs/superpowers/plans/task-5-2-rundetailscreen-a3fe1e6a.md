<!-- task-pipeline: validated -->
# 5.2 RunDetailScreen with output pane (card a3fe1e6a)

Narrows `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` ("Run detail", lines ~197-218) to one subtask. Parent story 8bb02694 "Runs screens and integration". Built on branch `mon/task-5-1-runsscreen-sidebar-f9e44406` (1d76074), in worktree `mon/task-5-2-rundetailscreen-a3fe1e6a`. Check that the base contains `core/stores/RunStore.qml`, `core/domain/runs.js`, `ui/screens/RunsScreen.qml` and `ui/components/PhaseTimeline.qml` before starting. The main checkout (`main`, 3cca636) does not have any of these files.

Note: the exploration summary passed to this stage was cut off at 8000 of 9734 characters, partway through "TEST PLACEMENT RULES". The upstream stage went over its brief. The test tiers below come from `docs/architecture.md` "How to add" (lines 156-166) and "Tests" (168-180), and from the test layout already in the 5.1 tree. They are not taken from the missing text.

## Scope

In scope:

1. **`core/domain/runs.js`** (pure additions; existing functions keep their behaviour):
   - `normalizeRun` also carries `base_branch` and `branch_prefix`. It reads them from the `am runs` row first and from `status.run` second, and defaults each to `""`. The header needs them, and today they are dropped.
   - `runTree(run)` turns a normalised run into the detail tree. It reads the shape `runs.js` already reads: `tree.stories[]` and `tree.subtasks[]`, each with `card_id`. A subtask belongs to a story through `story_id` or the story's `subtasks` entries (same rule as `_storyHas`). Phases are `{name, status, detail?, attempts[]}` and attempts are `{n | attempt, status}`. The output is the list of stories in am's order. Each story has its subtasks, each subtask has its phases (in a form `PhaseTimeline` accepts) and its attempts. Subtasks that belong to no story are kept under an "Other" group, not dropped. Synthetic ids (`integrate`, `bases`, `base-<story-id>`) are taken out of the story and subtask lists and returned separately as labelled rows: `Integrate`, `Bases`, `Base <story-id>`. They are returned only when present. The function never throws, and garbage becomes empty.
   - `defaultAttempt(run)` returns the attempt the pane opens on: `{card_id, phase, attempt}`. It is the newest attempt (highest `n`/`attempt`; the last one listed on a tie or when none has a number) of the first `started` phase in subtask order that has at least one attempt (the same walk as `currentPhase`, skipping started phases with no attempts). If no phase is started, it is the newest attempt of the last flat `rows[]` entry for a real card. Otherwise it is `null`.
   - `attemptStatus(run, card_id, phase, attempt)` returns that attempt's status from the tree, or `""`.
   - `logTail(data, maxLines)` returns the last `maxLines` (200 at the call site) lines of `am logs` `data.stdout`, followed by `data.stderr` when non-empty, as one string. It returns `{text, truncated}`: `truncated` is true when lines were cut, so the pane can say "last 200 lines". A non-object or a missing field gives `{text: "", truncated: false}`.
   - `snapshotAgeText(fetchedMs, nowMs)` returns `"Ns"` under a minute, then `"Nm"`, `"Nh"` and `"Nd"`. It returns `""` for a fetch time that is missing, in the future or not finite. `ageText` cannot be used here because it says "just now" under a minute.
2. **`core/stores/RunStore.qml`**: logs fetching, which the monitor spec calls the second `HelperRunner`.
   - New state: `selectedAttempt` (`{card_id, phase, attempt}` or `null`), `logsText`, `logsTruncated`, `logsFetchedMs` (Date.now() when a good reply arrived, else 0), `logsLoading`, `logsError` (`Runs.errorText` of the envelope), and `logsStatus`, which is the attempt status in effect when the fetch was launched.
   - `selectAttempt(card_id, phase, attempt)` sets the selection and fetches the logs. `refreshLogs()` fetches the logs for the current selection again. Each fetch runs `logsRunner` (`runs/runs-logs.py`) with `[selectedRunId, card_id, phase, String(attempt)]`. Nothing is fetched when there is no project, no run or no selection.
   - When `selectedRunId` changes, the selection is reset to `Runs.defaultAttempt` of that run and fetched. Clearing the run clears the selection and the logs.
   - After every applied snapshot, if `attemptStatus` of the selected attempt differs from `logsStatus`, the logs are fetched once. Nothing else triggers an automatic fetch. No new timer is added, and logs are never polled.
   - `logsRunner` is guarded by the project, like `snapshotRunner`, so a reply for a project the user has left is dropped. A reply for an older selection loses under the runner's latest-wins rule. `projectSwitched()` also clears the selection and all logs state. `onGuardChanged` stays only on `snapshotRunner`, so `projectSwitched` still runs once.
   - Reply handling uses the existing `parseEnvelope`. On `ok:true`, `logsText` and `logsTruncated` are set from `Runs.logTail(data, 200)`, `logsFetchedMs` is set, and `logsError` is cleared. On `ok:false` (`AmMissing`, `AmBadOutput`, `HelperError`, `Usage`, or am's own error such as an unknown run), `logsError` is set and the previous text is kept. A reply that is not usable gives "The logs snapshot gave no usable result (exit N)." These failures never touch `amStatus`, `runs` or `lastError`.
   - Update the header comment so it says two runners plus the watch.
3. **`ui/screens/RunDetailScreen.qml`** (new). Copy the RunsScreen pattern: a Column root, `property var app`, `property var navigator`, `property var theme: T.Theme {}`, `signal revealRequested(var item)`, and `visible: app.nav.viewMode === "run" && !!app.projects.selectedProject`. Imports: `qs.Commons`, `runs.js`, `runGlyphs.js`, `"../components" as UI` and `"../theme" as T`. It never imports `core/stores`. The run shown is the entry in `app.runs.runs` whose id equals `app.runs.selectedRunId`.
   - **Header:** `Run <shortId>`, then the state glyph and the state word (from `Runs.runState`, never from brd status). The second line is `Milestone <id> · prefix <p> · base <b> · lease pid <pid> live|not live`, or `no lease`. Any part that is empty is left out. For an escalated run, `Runs.escalationReason` appears under the header.
   - **Tree:** one row per story with its state glyph and its subtasks (card id, glyph, current phase and attempt). Under the selected subtask there is a `PhaseTimeline` line and one clickable row per attempt (`<phase>.<n>` with its status glyph). Clicking an attempt row calls `app.runs.selectAttempt(...)` and marks the row as selected, using a marker as well as colour. The synthetic rows (Integrate, Bases, Base …) are labelled, show their status, and only appear when present. A card whose brd status is merged, canceled or archived (looked up through `app`'s existing board data) is listed dimmed, not hidden. Titles also come from that board data and fall back to the card id. State is never shown by colour alone. Glyphs come from `runGlyphs.js`, plus the glyphs `PhaseTimeline` already draws, and no new glyph literals are added. The `urgent` theme token is used for escalated. Merged purple and canceled red are not used.
   - **Output pane:** the heading is `Output · <card> <phase>.<n>`, then `snapshot <snapshotAgeText> ago` (with "last 200 lines" when cut), then a shared `ActionButton` labelled "Refresh" that calls `app.runs.refreshLogs()`. The body is `logsText` in a read-only text area. The wording must never say "live". While there is no reply yet, the label reads "loading…". On a failure it shows `logsError` and keeps the last text, if any. If no attempt is selected, it shows "No attempt selected". The age's `nowMs` is a binding re-read when `logsFetchedMs` or the run list changes, the same way RunsScreen does it. There is no per-second timer.
   - Only shared components are used (`ThemedText`, `ActionButton`, `Badge`, `ListRow`, `ListStatus`, `PhaseTimeline`). None of the patterns the duplication test rejects are added. The component name must not clash with a shell or QtQuick type.
4. **`ui/Panel.qml`:** mount `RunDetailScreen` next to `RunsScreen` (around line 551) with the same `app`, `navigator`, `theme` and `onRevealRequested` wiring, and replace the placeholder comment.

Out of scope: run marks on Board, Graph or CardDetail (RunBadge and RollupBar placement, the Runs section in CardDetail) belong to 5.3. The architecture.md and README write-up belongs to 5.4. Keyboard movement between attempts is also out of scope: the run view's `currentList()` stays `[]` and Enter still does nothing, as the 5.1 flow test pins. Also out of scope: any live tail, run controls, Navigator changes (openRun, restoreRunsList and goBack already exist), and changes to `runs-logs.py`.

## Observable behaviour

- `openRun(id)` shows the run's header and tree. The output pane fetches the default attempt's logs at once. Esc, Left or the crumb returns to Runs and clears the selection and the logs, as 5.1 already does for the selection.
- Clicking another attempt fetches that attempt. Refresh fetches it again and updates the age. When a snapshot changes the selected attempt's status (for example, started to done), the pane fetches once more.
- Switching projects while on the run view leaves no old header, tree or logs behind. A late logs reply for the old project changes nothing.
- When am is missing, the pane shows the AmMissing text and the rest of the screen stays as the snapshot left it.

## Error paths

- A selected run id that is no longer in `runs` shows `ListStatus` "This run is no longer in the snapshot". There is no crash.
- `runs-logs.py` can fail with an `ok:false` envelope of any type, output that is not JSON, or an empty stdout. In every case `logsError` is shown, the old text is kept, and `amStatus` is unaffected.
- A run with an empty tree, phases without attempts, or attempts without `n`/`attempt` still renders. `defaultAttempt` gives `null` and the pane shows "No attempt selected".

## Tests (written first)

| Test | Tier (per docs/architecture.md) |
|---|---|
| `normalizeRun` carries `base_branch`/`branch_prefix` (row first, then status.run, default ""); `runTree` grouping, story membership through story_id and story.subtasks, the "Other" group, synthetic rows split out and labelled only when present, garbage input; `defaultAttempt` (started phase, rows fallback, null); `attemptStatus`; `logTail` (under 200, exactly 200, 5000 lines, stderr appended, truncated flag, bad data); `snapshotAgeText` boundaries | `tests/core/domain/tst_runs.qml` (domain tier) |
| logsRunner args for `selectAttempt` and `refreshLogs`; no launch without project, run or selection; ok reply sets text, truncation and fetchedMs; each `ok:false` type and unparsable output sets `logsError`, keeps the text and leaves `amStatus` alone; a status change on a snapshot fetches once, an unchanged status fetches nothing; a `selectedRunId` change resets to the default attempt; `projectSwitched` clears the logs; a stale-project reply is dropped; no new timer runs while idle | `tests/core/stores/tst_run_store.qml` (store tier, headless) |
| RunDetailScreen renders the header parts (prefix, base, lease live and not live, no lease), state glyph plus word, escalation reason, the story, subtask and attempt rows, the PhaseTimeline line under the selected subtask, synthetic rows only when present, dimmed terminal-brd cards, the pane label with "snapshot Ns ago" and no "live", Refresh calling `refreshLogs`, an attempt click calling `selectAttempt`, and the missing-run `ListStatus` | `tests/ui/screens/tst_run_detail_screen.qml` (new screen, `tests/ui/`) |
| Flow: openRun leads to the detail view and a logs launch for the default attempt; Esc returns to Runs and clears the logs; a project switch on the run view clears it; the existing "Enter does nothing / currentList is empty" test is unchanged | `tests/ui/tst_runs_flow.qml` (UI flow tier) |
| Layers, duplicates and icon glyphs pass unchanged | `tests/architecture/` (run, not edited) |

No backend or contract test changes: `runs-logs.py` is done and already tested in `tests/core/backend/runs/test_runs_logs.py`.

## Open point for the plan

The backend fixture in `test_runs_snapshot.py` nests `stories[].subtasks[]` keyed by `id`, while `runs.js` and `tst_runs.qml` read flat `tree.stories` and `tree.subtasks` keyed by `card_id`. The contract test does not pin the `am status` tree. `runTree` follows the shape `runs.js` already uses and does not try to reconcile the two in this card. Raise the mismatch with the user rather than widening scope.

---

# 5.2 RunDetailScreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Run detail screen (header, story > subtask > phase > attempt tree, synthetic rows, and a snapshot-only `am logs` output pane with Refresh) backed by a second, project-guarded logs runner in RunStore and pure helpers in `runs.js`.

**Architecture:** Pure helpers in `core/domain/runs.js` build the tree, choose the default attempt, read an attempt's status, tail the logs and format the snapshot age. `core/stores/RunStore.qml` gains a `logsRunner` (HelperRunner for `runs/runs-logs.py`) plus selection/logs state; it refetches only on a selection, on Refresh, or when a snapshot changes the selected attempt's status. `ui/screens/RunDetailScreen.qml` reads `app.runs` and `app.board.cardMap` only, and is mounted in `ui/Panel.qml` next to `RunsScreen`.

**Tech Stack:** QML (Qt 6, Quickshell), `.pragma library` JS, QtTest via `qmltestrunner` (stubs under `tests/stubs`), pytest for architecture rules. Single test entry point: `bash tests/run.sh [filter]` (always runs pytest first, then the QML tests whose path contains the filter).

**Spec:** `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-2-rundetailscreen-a3fe1e6a/docs/superpowers/specs/task-5-2-rundetailscreen-a3fe1e6a-design.md` (prepended verbatim above).

**Worktree:** every path below is relative to `/home/mtts/Code/omarchy-project-manager/.claude/worktrees/mon/task-5-2-rundetailscreen-a3fe1e6a` (branch `mon/task-5-2-rundetailscreen-a3fe1e6a`, cut from `mon/task-5-1-runsscreen-sidebar-f9e44406`). Run every command from that directory. Nothing from 5.3 or 5.4 exists on this branch and none is assumed.

**Upstream truncation note:** both summaries handed to the plan stage were truncated by their upstream stages (the spec summary at 2000 of 2821 characters, the exploration summary at 8000 of 9734). That is evidence those stages over-ran their briefs. This plan was written from the on-disk spec and the code on this branch, not from the missing text.

## Global Constraints

- Layering: `ui/screens/*.qml` never imports `core/stores`; it gets `property var app`, `property var navigator`, `property var theme: T.Theme {}`.
- `core/stores/*.qml` imports only `QtQml`, `Quickshell`, `Quickshell.Io` and `../domain/*.js`.
- `core/domain/*.js` is `.pragma library`, pure, never throws; garbage becomes the default.
- Do not add a second copy of `Qt.rgba(0, 0, 0, 0.55)`, `radius: height / 2`, `bordered: true`, `font.family:` or `CursorSurface {` (tests/architecture/test_layers.py `GUARDS`). This rules out a hand-made text area: the output body is a `UI.ThemedText` with `textFormat: Text.PlainText`. Text is read-only by nature, and it does not repeat `font.family:`.
- No new glyph literals: state glyphs come from `ui/components/runGlyphs.js` (`GLYPHS`, `glyphOf`) and `PhaseTimeline`. The selected-attempt marker `›` is plain BMP. The architecture test checks private-use code points only, and `›` already appears in its own decoder test.
- State is never shown by colour alone: every story, subtask, attempt and synthetic row prints its status word, and its glyph when it has one. `urgent` is used for escalated and dead; merged purple `#9b72cf` and canceled red `#d9534f` are never used.
- Run state comes from am (`Runs.runState`, `Runs.glyphStateOf` of am statuses), never from a brd status. brd's `app.board.cardMap` only supplies titles and the dimming of merged/canceled/archived cards.
- The output pane never says "live". Its age is `snapshot <Ns|Nm|Nh|Nd> ago`.
- No new Timer. Logs are fetched on a selection, on Refresh, and when an applied snapshot changes the selected attempt's status. They are never polled.
- `logsRunner` is guarded by `store.project`. Only `snapshotRunner` has `onGuardChanged`.
- The out-of-scope list is binding: no Navigator change, no keyboard movement between attempts (the run view's `currentList()` stays `[]`), no `runs-logs.py` change, and no docs (the write-up is 5.4's).
- Verification: `bash tests/run.sh` must exit 0.

## Review Focus

These are inputs the spec implies but does not pin. Each one has a test in the owning task.

1. **Switching to another attempt must not show the previous attempt's output under the new heading.** `selectAttempt` with a different attempt clears `logsText`, `logsTruncated`, `logsFetchedMs` and `logsError` before fetching. Refresh of the same attempt keeps the text until its reply arrives. Test: `test_selecting_another_attempt_clears_the_old_text_but_refresh_keeps_it` (Task 3).
2. **A run opened before its first attempt exists.** The pane would otherwise say "No attempt selected" forever. When an applied snapshot finds a selected run with no selection, the store picks `defaultAttempt` then. Test: `test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears` (Task 4).
3. **Attempts with no `n`/`attempt` cannot be passed to `am logs`.** They are listed as `<phase>.?` with their status, are not clickable, and are never the default. Tests: `test_run_tree` t4 and `test_default_attempt` unnumbered case (Task 2), `test_an_unnumbered_attempt_is_listed_but_not_clickable` (Task 5).
4. **Reaching another subtask's attempts.** Attempt rows only appear under the selected subtask, so without this the user could never open a different subtask. Clicking a subtask row selects its current phase's newest attempt (when it has one). Test: `test_clicking_a_subtask_selects_its_current_attempt` (Task 5).
5. **A huge stderr.** It is tailed to `maxLines` as well, and `truncated` is set, so the pane stays bounded. Test: `test_log_tail` stderr-cut case (Task 1).

## File map

- Modify `core/domain/runs.js`: `normalizeRun` adds two fields; a new "Run detail (5.2)" section at the end with `glyphStateOf`, `runTree`, `defaultAttempt`, `attemptStatus`, `logTail` and `snapshotAgeText` plus private helpers.
- Modify `tests/core/domain/tst_runs.qml`: two key-list strings and `checkDefaults`, plus new tests appended.
- Modify `core/stores/RunStore.qml`: header comment, logs state, `logsRunner`, logs functions, the `projectSwitched` and `applySnapshot` hooks.
- Modify `tests/core/stores/tst_run_store.qml`: new tests appended.
- Create `ui/screens/RunDetailScreen.qml`.
- Create `tests/ui/screens/tst_run_detail_screen.qml`.
- Modify `ui/Panel.qml:551-559`: mount the screen and drop the placeholder comment.
- Modify `tests/ui/tst_runs_flow.qml`: new flow tests appended. Existing tests are untouched.

---

### Task 1: Domain — branch fields, log tail, snapshot age

**Files:**
- Modify: `core/domain/runs.js:43-52` (normalizeRun return), append to end of file
- Test: `tests/core/domain/tst_runs.qml`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Runs.normalizeRun(raw)` result gains `base_branch: string`, `branch_prefix: string`.
  - `Runs.logTail(data, maxLines) -> { text: string, truncated: bool }`
  - `Runs.snapshotAgeText(fetchedMs: number, nowMs: number) -> string` (`"Ns" | "Nm" | "Nh" | "Nd" | ""`)

- [ ] **Step 1: Confirm the base**

Run: `git branch --show-current && ls core/stores/RunStore.qml core/domain/runs.js ui/screens/RunsScreen.qml ui/components/PhaseTimeline.qml core/backend/runs/runs-logs.py`
Expected: `mon/task-5-2-rundetailscreen-a3fe1e6a`, then all five paths listed with no "No such file". If any is missing, stop: the branch was not cut from 5.1.

- [ ] **Step 2: Update the existing key-list assertions (they pin normalizeRun's exact keys)**

In `tests/core/domain/tst_runs.qml`, replace `checkDefaults` (lines 32-46) with:

```qml
  function checkDefaults(r, label) {
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,repo_dir,rows,started_at,status,tree", label)
    compare(r.started_at, "", label)
    compare(r.id, "", label)
    compare(r.repo_dir, "", label)
    compare(r.milestone_id, "", label)
    compare(r.status, "", label)
    compare(r.base_branch, "", label)
    compare(r.branch_prefix, "", label)
    compare(r.lease, null, label)
    compare(Array.isArray(r.rows), true, label)
    compare(r.rows.length, 0, label)
    compare(Array.isArray(r.tree.stories), true, label)
    compare(r.tree.stories.length, 0, label)
    compare(Array.isArray(r.tree.subtasks), true, label)
    compare(r.tree.subtasks.length, 0, label)
  }
```

and in `test_normalize_full` replace line 50:

```qml
    compare(Object.keys(r).sort().join(","), "id,lease,milestone_id,repo_dir,rows,started_at,status,tree")
```

with:

```qml
    compare(Object.keys(r).sort().join(","), "base_branch,branch_prefix,id,lease,milestone_id,repo_dir,rows,started_at,status,tree")
```

- [ ] **Step 3: Write the failing tests**

Append to `tests/core/domain/tst_runs.qml`, before the final closing `}` of the `TestCase`:

```qml
  // ---- Run detail (5.2)

  function test_normalize_branch_fields() {
    var r = Runs.normalizeRun(fullRaw())
    compare(r.base_branch, "main")
    compare(r.branch_prefix, "mon/")
    var fromRun = Runs.normalizeRun({ status: { run: { base_branch: "master", branch_prefix: "m3" } } })
    compare(fromRun.base_branch, "master", "status.run is the fallback")
    compare(fromRun.branch_prefix, "m3")
    var rowWins = Runs.normalizeRun({ row: { base_branch: "a", branch_prefix: "p" },
                                      status: { run: { base_branch: "b", branch_prefix: "q" } } })
    compare(rowWins.base_branch, "a", "the am runs row comes first")
    compare(rowWins.branch_prefix, "p")
    var blankRow = Runs.normalizeRun({ row: { base_branch: "", branch_prefix: null },
                                       status: { run: { base_branch: "b", branch_prefix: "q" } } })
    compare(blankRow.base_branch, "b", "an empty row value falls back")
    compare(blankRow.branch_prefix, "q")
    compare(Runs.normalizeRun({}).base_branch, "")
    compare(Runs.normalizeRun({}).branch_prefix, "")
  }

  function numbered(n, from) {
    var out = []
    for (var i = 0; i < n; i++) out.push("line " + ((from || 0) + i))
    return out.join("\n") + "\n"
  }

  function test_log_tail() {
    var under = Runs.logTail({ stdout: "collecting...\n3 passed\n", stderr: "" }, 200)
    compare(under.text, "collecting...\n3 passed")
    compare(under.truncated, false)

    var exact = Runs.logTail({ stdout: numbered(200) }, 200)
    compare(exact.text.split("\n").length, 200)
    compare(exact.truncated, false, "exactly 200 lines is not cut")

    var big = Runs.logTail({ stdout: numbered(5000), stderr: "" }, 200)
    var lines = big.text.split("\n")
    compare(lines.length, 200)
    compare(lines[0], "line 4800")
    compare(lines[199], "line 4999")
    compare(big.truncated, true)

    var withErr = Runs.logTail({ stdout: "out\n", stderr: "err1\nerr2\n" }, 200)
    compare(withErr.text, "out\nerr1\nerr2", "stderr follows stdout")
    compare(withErr.truncated, false)

    var errOnly = Runs.logTail({ stdout: "", stderr: "boom" }, 200)
    compare(errOnly.text, "boom")

    // A huge stderr is bounded too (Review Focus 5).
    var hugeErr = Runs.logTail({ stdout: "out\n", stderr: numbered(300) }, 200)
    var errLines = hugeErr.text.split("\n")
    compare(errLines.length, 201, "stdout, then the last 200 stderr lines")
    compare(errLines[0], "out")
    compare(errLines[1], "line 100")
    compare(hugeErr.truncated, true)

    compare(Runs.logTail({ stdout: numbered(250) }, undefined).text.split("\n").length, 200, "a bad maxLines is 200")

    var bad = [undefined, null, "x", 5, [], {}, { stdout: 5, stderr: {} }]
    for (var i = 0; i < bad.length; i++) {
      var t = Runs.logTail(bad[i], 200)
      compare(t.text, "", "garbage " + i)
      compare(t.truncated, false, "garbage " + i)
    }
  }

  function test_snapshot_age_text() {
    var now = 1790000000000
    compare(Runs.snapshotAgeText(now, now), "0s")
    compare(Runs.snapshotAgeText(now - 14000, now), "14s")
    compare(Runs.snapshotAgeText(now - 59999, now), "59s")
    compare(Runs.snapshotAgeText(now - 60000, now), "1m")
    compare(Runs.snapshotAgeText(now - 3599999, now), "59m")
    compare(Runs.snapshotAgeText(now - 3600000, now), "1h")
    compare(Runs.snapshotAgeText(now - 86399999, now), "23h")
    compare(Runs.snapshotAgeText(now - 86400000, now), "1d")
    compare(Runs.snapshotAgeText(now + 1, now), "", "the future")
    var bad = [0, -5, NaN, Infinity, null, undefined, "x", {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.snapshotAgeText(bad[i], now), "", "missing fetch " + i)
    var badNow = [NaN, Infinity, null, undefined, "x"]
    for (var j = 0; j < badNow.length; j++) compare(Runs.snapshotAgeText(now, badNow[j]), "", "garbage now " + j)
  }
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash tests/run.sh core/domain/tst_runs.qml`
Expected: exit 1. FAIL lines for `test_normalize_full`, `test_normalize_garbage` (key list), `test_normalize_branch_fields` (`undefined` vs `"main"`), and `TypeError ... is not a function` for `logTail`/`snapshotAgeText`.

- [ ] **Step 5: Implement**

In `core/domain/runs.js`, replace the `normalizeRun` return block (lines 43-52):

```js
  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    lease: lease,
    rows: arrayOr(st.rows),
    tree: { stories: arrayOr(st.stories), subtasks: arrayOr(st.subtasks) }
  }
```

with:

```js
  return {
    id: firstText(row.id, run.id),
    repo_dir: firstText(row.repo_dir, run.repo_dir),
    milestone_id: firstText(run.milestone_id, row.milestone_id),
    status: firstText(run.status, row.status),
    started_at: firstText(row.started_at, run.started_at),
    base_branch: firstText(row.base_branch, run.base_branch),
    branch_prefix: firstText(row.branch_prefix, run.branch_prefix),
    lease: lease,
    rows: arrayOr(st.rows),
    tree: { stories: arrayOr(st.stories), subtasks: arrayOr(st.subtasks) }
  }
```

Append to the end of `core/domain/runs.js`:

```js

// ---- Run detail (5.2) --------------------------------------------------------------------
//
// The Run detail screen's tree, the attempt its output pane opens on, one
// attempt's status, the tail of an `am logs` snapshot and that snapshot's age.
// Pure and never throwing, like the rest of this file. The tree is read in the
// shape the functions above read: flat tree.stories[] and tree.subtasks[], each
// keyed by card_id; phases are { name, status, detail?, attempts[] } and
// attempts { n | attempt, status }.

// A text's lines without the one trailing newline; [] for "" or a non-string.
function _linesOf(text) {
  if (typeof text !== "string" || text === "") return []
  var t = text.charAt(text.length - 1) === "\n" ? text.slice(0, -1) : text
  return t === "" ? [] : t.split("\n")
}

// The last `maxLines` lines of an `am logs` data object's stdout, then the last
// `maxLines` of its stderr, as one string. `truncated` says lines were cut, so
// the pane can say "last 200 lines". A bad maxLines is 200.
function logTail(data, maxLines) {
  var max = _isFiniteNumber(maxLines) && maxLines >= 1 ? Math.floor(maxLines) : 200
  var out = _isObject(data) ? _linesOf(data.stdout) : []
  var err = _isObject(data) ? _linesOf(data.stderr) : []
  var truncated = out.length > max || err.length > max
  if (out.length > max) out = out.slice(out.length - max)
  if (err.length > max) err = err.slice(err.length - max)
  return { text: out.concat(err).join("\n"), truncated: truncated }
}

// How old a logs snapshot is, without "ago": "Ns" under a minute, then "Nm",
// "Nh" or "Nd". "" for a fetch time that is missing (0 or less), not finite or
// in the future, or a clock that is not a finite number.
function snapshotAgeText(fetchedMs, nowMs) {
  if (!_isFiniteNumber(fetchedMs) || fetchedMs <= 0 || !_isFiniteNumber(nowMs)) return ""
  var diff = nowMs - fetchedMs
  if (diff < 0) return ""
  if (diff < 60000) return Math.floor(diff / 1000) + "s"
  if (diff < 3600000) return Math.floor(diff / 60000) + "m"
  if (diff < 86400000) return Math.floor(diff / 3600000) + "h"
  return Math.floor(diff / 86400000) + "d"
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash tests/run.sh core/domain/tst_runs.qml`
Expected: exit 0, `Totals: N passed, 0 failed`. No TypeError lines.

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): carry base/prefix, add logTail and snapshotAgeText (5.2)"
```

---

### Task 2: Domain — detail tree, default attempt, attempt status, glyph state

**Files:**
- Modify: `core/domain/runs.js` (append after Task 1's section)
- Test: `tests/core/domain/tst_runs.qml`

**Interfaces:**
- Consumes: private helpers already in `runs.js`: `_isObject`, `_arrayOr`, `_stringOr`, `_isFiniteNumber`, `_treeOf`, `_isSynthetic`, `_isCardId`, `_findByCardId`, `_storyHas`, `_subtasksOf`.
- Produces:
  - `Runs.glyphStateOf(status) -> "running"|"parked"|"escalated"|"dead"|"cancelled"|"done"|""`. Feed it to `RunGlyphs.glyphOf`.
  - `Runs.runTree(run) -> { stories: StoryNode[], synthetic: SyntheticRow[] }` where
    - `StoryNode = { card_id: string, label: string, status: string, other: bool, subtasks: SubtaskNode[] }`. The "Other" group is `{ card_id: "", label: "Other", status: "", other: true }` and is last, only when non-empty.
    - `SubtaskNode = { card_id, status, phases: [{name, status}], attempts: [{phase, attempt, status}], currentPhase: string, currentAttempt: number }`. `attempt` and `currentAttempt` are 0 when unnumbered.
    - `SyntheticRow = { id, label, status }`.
  - `Runs.defaultAttempt(run) -> { card_id, phase, attempt } | null`
  - `Runs.attemptStatus(run, cardId, phase, attempt) -> string`

- [ ] **Step 1: Write the failing tests**

Append to `tests/core/domain/tst_runs.qml`, before the final closing `}`:

```qml
  // s1 owns t1 (via its list) and t2 (via a {card_id} entry); s2 lists t1 too
  // (already s1's) and owns t3 via story_id; t4 belongs to no story. base-s1,
  // bases and integrate are bookkeeping ids from the stories, subtasks and rows.
  function detailRun() {
    return mkRun("r", "started", true, {
      rows: [{ card_id: "t1", phase: "implement", attempt: 2, status: "started" },
             { card_id: "integrate", phase: "integrate", attempt: 1, status: "pending" }],
      tree: {
        stories: [{ card_id: "s1", status: "started", subtasks: ["t1", { card_id: "t2" }] },
                  { card_id: "s2", subtasks: ["t1"] },
                  { card_id: "base-s1", status: "done" }],
        subtasks: [
          { card_id: "t1", phases: [
            { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
            { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { attempt: 2, status: "started" }] }] },
          { card_id: "t2", status: "pending", phases: [{ name: "spec", status: "pending", attempts: [] }] },
          { card_id: "t3", story_id: "s2", phases: [] },
          { card_id: "t4", phases: [{ name: "review", status: "done", attempts: [{ status: "done" }] }] },
          { card_id: "bases", status: "done" }
        ]
      }
    })
  }

  function cardIds(list) { return list.map(function(x) { return x.card_id }).join(",") }

  function test_glyph_state_of() {
    var cases = [["started", "running"], ["running", "running"], ["stopped", "parked"], ["parked", "parked"],
                 ["escalated", "escalated"], ["failed", "dead"], ["dead", "dead"], ["cancelled", "cancelled"],
                 ["done", "done"], ["pending", ""], ["", ""], [undefined, ""], [null, ""], [5, ""], ["constructor", ""]]
    for (var i = 0; i < cases.length; i++) compare(Runs.glyphStateOf(cases[i][0]), cases[i][1], String(cases[i][0]))
  }

  function test_run_tree() {
    var t = Runs.runTree(detailRun())
    compare(t.stories.map(function(s) { return s.label }).join(","), "s1,s2,Other")
    compare(cardIds(t.stories[0].subtasks), "t1,t2", "story_id-less membership through the story's list")
    compare(cardIds(t.stories[1].subtasks), "t3", "story_id membership; t1 stays with the first story only")
    compare(cardIds(t.stories[2].subtasks), "t4", "a subtask of no story is kept under Other")
    compare(t.stories[0].card_id, "s1")
    compare(t.stories[0].status, "started")
    compare(t.stories[0].other, false)
    compare(t.stories[1].status, "")
    compare(t.stories[2].card_id, "")
    compare(t.stories[2].other, true)

    var t1 = t.stories[0].subtasks[0]
    compare(t1.status, "started", "no own status: the last am row for the card")
    compare(t1.phases.map(function(p) { return p.name + ":" + p.status }).join(","), "spec:done,implement:started")
    compare(t1.attempts.map(function(a) { return a.phase + "." + a.attempt + ":" + a.status }).join(","),
            "spec.1:done,implement.1:failed,implement.2:started")
    compare(t1.currentPhase, "implement")
    compare(t1.currentAttempt, 2)

    var t2 = t.stories[0].subtasks[1]
    compare(t2.status, "pending", "its own status wins")
    compare(t2.currentPhase, "spec", "no started phase: the last named one")
    compare(t2.currentAttempt, 0)
    compare(t2.attempts.length, 0)

    // Review Focus 3: an unnumbered attempt is listed with attempt 0.
    var t4 = t.stories[2].subtasks[0]
    compare(t4.attempts.length, 1)
    compare(t4.attempts[0].attempt, 0)
    compare(t4.attempts[0].status, "done")
    compare(t4.currentAttempt, 0)

    compare(t.synthetic.map(function(s) { return s.id }).join(","), "base-s1,bases,integrate")
    compare(t.synthetic.map(function(s) { return s.label }).join(","), "Base s1,Bases,Integrate")
    compare(t.synthetic.map(function(s) { return s.status }).join(","), "done,done,pending")
  }

  function test_run_tree_without_synthetic_rows_or_orphans() {
    var t = Runs.runTree(mkRun("r", "started", true, { tree: { stories: [{ card_id: "s1", subtasks: [] }], subtasks: [] } }))
    compare(t.synthetic.length, 0, "no bookkeeping rows unless present")
    compare(t.stories.length, 1, "no Other group without orphans")
    compare(t.stories[0].subtasks.length, 0)
    compare(Runs.runTree(mkRun("r", "started", true)).stories.length, 0)
  }

  function test_run_tree_garbage() {
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x" },
               { tree: { stories: "x", subtasks: [null, 5, { card_id: 7 }, { card_id: "" }] } }]
    for (var i = 0; i < bad.length; i++) {
      var t = Runs.runTree(bad[i])
      compare(t.stories.length, 0, "garbage " + i)
      compare(t.synthetic.length, 0, "garbage " + i)
    }
    var odd = Runs.runTree({ rows: "y", tree: { stories: [null, { card_id: "s1", subtasks: "x" }],
      subtasks: [{ card_id: "t1", phases: [null, { name: "" }, { name: "spec", attempts: "x" }] }] } })
    compare(odd.stories.map(function(s) { return s.label }).join(","), "s1,Other")
    compare(cardIds(odd.stories[1].subtasks), "t1")
    compare(odd.stories[1].subtasks[0].phases.length, 1)
    compare(odd.stories[1].subtasks[0].attempts.length, 0)
  }

  function at(d) { return d === null ? "null" : d.card_id + "/" + d.phase + "/" + d.attempt }

  function test_default_attempt() {
    compare(at(Runs.defaultAttempt(detailRun())), "t1/implement/2")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "a", phases: [{ name: "review", status: "started", attempts: [] }] },
      { card_id: "b", phases: [{ name: "plan", status: "started", attempts: [{ n: 3, status: "started" }, { n: 1, status: "failed" }] }] }
    ] } }))), "b/plan/3", "a started phase without attempts is skipped; the highest number wins")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "integrate", phases: [{ name: "integrate", status: "started", attempts: [{ n: 1 }] }] }] } }))),
      "null", "a bookkeeping id is never a card")
    compare(at(Runs.defaultAttempt(mkRun("r", "done", null, {
      rows: [{ card_id: "t1", phase: "spec", attempt: 1, status: "done" }, { card_id: "integrate", phase: "integrate", attempt: 1 }],
      tree: { stories: [], subtasks: [{ card_id: "t1", phases: [{ name: "spec", status: "done", attempts: [{ n: 1 }, { n: 2 }] }] }] }
    }))), "t1/spec/2", "no started phase: the newest attempt of the last real row")
    compare(at(Runs.defaultAttempt(mkRun("r", "done", null, { rows: [{ card_id: "t5", phase: "plan", n: 4 }] }))),
            "t5/plan/4", "a row's own n")
    compare(at(Runs.defaultAttempt(mkRun("r", "done", null, { rows: [{ card_id: "t5", phase: "plan", status: "done" }] }))),
            "null", "a row with no number and no tree attempt")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "implement", status: "started", attempts: [{ status: "started" }] }] }] } }))),
      "null", "unnumbered attempts cannot be fetched")
    compare(at(Runs.defaultAttempt(mkRun("r", "started", true))), "null", "an empty tree")
    var bad = [undefined, null, "x", 5, [], {}, { tree: "x", rows: "y" }, { rows: [null, 5, { card_id: 7, phase: "x", n: 1 }] }]
    for (var i = 0; i < bad.length; i++) compare(Runs.defaultAttempt(bad[i]), null, "garbage " + i)
  }

  function test_attempt_status() {
    var run = detailRun()
    compare(Runs.attemptStatus(run, "t1", "implement", 2), "started")
    compare(Runs.attemptStatus(run, "t1", "implement", 1), "failed")
    compare(Runs.attemptStatus(run, "t1", "spec", 1), "done")
    compare(Runs.attemptStatus(run, "t1", "spec", 9), "")
    compare(Runs.attemptStatus(run, "t1", "verify", 1), "")
    compare(Runs.attemptStatus(run, "zz", "spec", 1), "")
    compare(Runs.attemptStatus(run, "t4", "review", 0), "", "0 is not an attempt number")
    var bad = [undefined, null, "x", 5, [], {}]
    for (var i = 0; i < bad.length; i++) compare(Runs.attemptStatus(bad[i], "t1", "spec", 1), "", "garbage " + i)
    compare(Runs.attemptStatus(run, null, "spec", 1), "")
    compare(Runs.attemptStatus(run, "t1", null, 1), "")
    compare(Runs.attemptStatus(run, "t1", "spec", "1"), "", "a string attempt is not a number")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh core/domain/tst_runs.qml`
Expected: exit 1, `TypeError: ... is not a function` for `glyphStateOf`, `runTree`, `defaultAttempt`, `attemptStatus`.

- [ ] **Step 3: Implement**

Append to the end of `core/domain/runs.js`:

```js

// The run-state name (a runGlyphs.js key) an am story, subtask, phase, attempt
// or row status is drawn with -- the mapping PhaseTimeline uses (started is
// running, failed is dead). "" for anything else, which shows no glyph.
function glyphStateOf(status) {
  if (status === "started" || status === "running") return "running"
  if (status === "stopped" || status === "parked") return "parked"
  if (status === "escalated") return "escalated"
  if (status === "failed" || status === "dead") return "dead"
  if (status === "cancelled") return "cancelled"
  if (status === "done") return "done"
  return ""
}

// An attempt's number: `attempt`, else `n`, when a finite number above 0; else
// 0, an attempt `am logs` cannot be asked about.
function _attemptNumber(a) {
  if (!_isObject(a)) return 0
  if (_isFiniteNumber(a.attempt) && a.attempt > 0) return a.attempt
  if (_isFiniteNumber(a.n) && a.n > 0) return a.n
  return 0
}

// The highest attempt number of a phase; 0 when it has no numbered attempt.
function _newestAttempt(phase) {
  var attempts = _isObject(phase) ? _arrayOr(phase.attempts) : []
  var best = 0
  for (var i = 0; i < attempts.length; i++) best = Math.max(best, _attemptNumber(attempts[i]))
  return best
}

// The subtask's first phase with this name, or null.
function _findPhase(subtask, name) {
  if (!_isObject(subtask) || typeof name !== "string" || name === "") return null
  var phases = _arrayOr(subtask.phases)
  for (var i = 0; i < phases.length; i++) {
    if (_isObject(phases[i]) && phases[i].name === name) return phases[i]
  }
  return null
}

// The status of the last am row for an id; "" when there is none.
function _lastRowStatus(run, id) {
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var i = rows.length - 1; i >= 0; i--) {
    if (_isObject(rows[i]) && rows[i].card_id === id) return _stringOr(rows[i].status)
  }
  return ""
}

function _syntheticLabel(id) {
  if (id === "integrate") return "Integrate"
  if (id === "bases") return "Bases"
  return id.length > 5 ? "Base " + id.slice(5) : "Base"
}

// One subtask as the detail tree shows it. Its own status, else its last am
// row's; phases with a name only; every attempt object (attempt 0 when it has
// no number); the current phase is the first started one, else the last.
function _subtaskNode(run, subtask) {
  var phases = [], attempts = []
  var started = null, last = null
  var list = _arrayOr(subtask.phases)
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!_isObject(p) || typeof p.name !== "string" || p.name === "") continue
    phases.push({ name: p.name, status: _stringOr(p.status) })
    if (started === null && p.status === "started") started = p
    last = p
    var tries = _arrayOr(p.attempts)
    for (var k = 0; k < tries.length; k++) {
      if (_isObject(tries[k])) attempts.push({ phase: p.name, attempt: _attemptNumber(tries[k]), status: _stringOr(tries[k].status) })
    }
  }
  var current = started !== null ? started : last
  var own = _stringOr(subtask.status)
  return {
    card_id: subtask.card_id,
    status: own !== "" ? own : _lastRowStatus(run, subtask.card_id),
    phases: phases,
    attempts: attempts,
    currentPhase: current === null ? "" : current.name,
    currentAttempt: _newestAttempt(current)
  }
}

// The Run detail tree: the run's stories in am's order, each with the subtasks
// it owns (a subtask goes to the first story that owns it), then an "Other"
// group for subtasks of no story. Bookkeeping ids (integrate, bases, base-*)
// from the stories, the subtasks or the rows become labelled rows of their own,
// only when present. Never throws.
function runTree(run) {
  var tree = _treeOf(run)
  var stories = _arrayOr(tree.stories), subtasks = _arrayOr(tree.subtasks)
  var synthetic = [], seen = []
  function addSynthetic(id, status) {
    if (seen.indexOf(id) >= 0) return
    seen.push(id)
    var own = _stringOr(status)
    synthetic.push({ id: id, label: _syntheticLabel(id), status: own !== "" ? own : _lastRowStatus(run, id) })
  }
  var realStories = [], realSubtasks = []
  for (var i = 0; i < stories.length; i++) {
    var s = stories[i]
    if (!_isObject(s)) continue
    if (_isSynthetic(s.card_id)) addSynthetic(s.card_id, s.status)
    else if (_isCardId(s.card_id)) realStories.push(s)
  }
  for (var j = 0; j < subtasks.length; j++) {
    var t = subtasks[j]
    if (!_isObject(t)) continue
    if (_isSynthetic(t.card_id)) addSynthetic(t.card_id, t.status)
    else if (_isCardId(t.card_id)) realSubtasks.push(t)
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = 0; r < rows.length; r++) {
    if (_isObject(rows[r]) && _isSynthetic(rows[r].card_id)) addSynthetic(rows[r].card_id, "")
  }
  var claimed = [], out = []
  for (var si = 0; si < realStories.length; si++) {
    var story = realStories[si]
    var mine = []
    for (var ti = 0; ti < realSubtasks.length; ti++) {
      if (claimed.indexOf(ti) >= 0 || !_storyHas(story, realSubtasks[ti], story.card_id)) continue
      claimed.push(ti)
      mine.push(_subtaskNode(run, realSubtasks[ti]))
    }
    var ownStatus = _stringOr(story.status)
    out.push({ card_id: story.card_id, label: story.card_id,
               status: ownStatus !== "" ? ownStatus : _lastRowStatus(run, story.card_id), other: false, subtasks: mine })
  }
  var others = []
  for (var oi = 0; oi < realSubtasks.length; oi++) {
    if (claimed.indexOf(oi) < 0) others.push(_subtaskNode(run, realSubtasks[oi]))
  }
  if (others.length > 0) out.push({ card_id: "", label: "Other", status: "", other: true, subtasks: others })
  return { stories: out, synthetic: synthetic }
}

// The attempt the output pane opens on: the newest numbered attempt of the
// first started phase (in subtask order) that has one; else, walking the flat
// rows from the last, the newest attempt of a real card's row phase (the row's
// own number or the tree's, whichever is higher); else null.
function defaultAttempt(run) {
  var subtasks = _subtasksOf(run)
  for (var i = 0; i < subtasks.length; i++) {
    var t = subtasks[i]
    if (!_isObject(t) || !_isCardId(t.card_id)) continue
    var phases = _arrayOr(t.phases)
    for (var j = 0; j < phases.length; j++) {
      var p = phases[j]
      if (!_isObject(p) || p.status !== "started" || typeof p.name !== "string" || p.name === "") continue
      var n = _newestAttempt(p)
      if (n > 0) return { card_id: t.card_id, phase: p.name, attempt: n }
    }
  }
  var rows = _isObject(run) ? _arrayOr(run.rows) : []
  for (var r = rows.length - 1; r >= 0; r--) {
    var row = rows[r]
    if (!_isObject(row) || !_isCardId(row.card_id)) continue
    var phase = _stringOr(row.phase)
    if (phase === "") continue
    var newest = Math.max(_attemptNumber(row), _newestAttempt(_findPhase(_findByCardId(subtasks, row.card_id), phase)))
    if (newest > 0) return { card_id: row.card_id, phase: phase, attempt: newest }
  }
  return null
}

// One attempt's status from the run's tree; "" when it is not there.
function attemptStatus(run, cardId, phase, attempt) {
  if (!_isCardId(cardId) || !_isFiniteNumber(attempt) || attempt <= 0) return ""
  var p = _findPhase(_findByCardId(_subtasksOf(run), cardId), phase)
  var tries = _isObject(p) ? _arrayOr(p.attempts) : []
  for (var i = tries.length - 1; i >= 0; i--) {
    if (_attemptNumber(tries[i]) === attempt) return _stringOr(tries[i].status)
  }
  return ""
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh core/domain/tst_runs.qml`
Expected: exit 0, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): runTree, defaultAttempt, attemptStatus, glyphStateOf (5.2)"
```

---

### Task 3: RunStore — logs runner, selection, replies

**Files:**
- Modify: `core/stores/RunStore.qml` (header comment lines 6-12; properties after line 43; alias after line 51; `projectSwitched` lines 188-201; new functions before line 203; new HelperRunner after line 293)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: `Runs.defaultAttempt`, `Runs.attemptStatus`, `Runs.logTail`, `Runs.errorText` (Tasks 1-2); `HelperRunner { script, guard, run(args), cancel(), current, seq, finished(stdout, exitCode, launchedGuard) }`.
- Produces (read by the screen and the flow test):
  - properties `selectedAttempt: {card_id, phase, attempt}|null`, `logsText: string`, `logsTruncated: bool`, `logsFetchedMs: real`, `logsLoading: bool`, `logsError: string`, `logsStatus: string`, `readonly alias logsRunner`
  - `selectAttempt(cardId: string, phase: string, attempt: number)`, `refreshLogs()`, `fetchLogs()`, `clearLogs()`, `openDefaultAttempt()`, `runById(id) -> run|null`, `applyLogs(stdout, exitCode)`

- [ ] **Step 1: Write the failing tests**

Add a property next to `rootB` (after line 14) in `tests/core/stores/tst_run_store.qml`:

```qml
  property string logsCmd: "python3|/plugin/core/backend/runs/runs-logs.py|"
```

Append before the final closing `}`:

```qml
  // ---- attempt logs (5.2)

  // A snapshot entry whose run has story s1 with subtask t1: spec is done,
  // implement is started and on its second attempt, whose status is `status`.
  function treeEntry(id, status) {
    var e = entry(id, "started", true)
    e.status.stories = [{ card_id: "s1", subtasks: ["t1"] }]
    e.status.subtasks = [{ card_id: "t1", phases: [
      { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
      { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: status }] }] }]
    return e
  }

  function logsReply(stdout, stderr) {
    return JSON.stringify({ ok: true, data: { stdout: stdout, stderr: stderr || "" } }) + "\n"
  }

  function argv(proc) { return proc.command.join("|") }

  // Project A's snapshot listed r1 (treeEntry) and r1 is the selected run, so
  // its default attempt's logs are in flight.
  function opened(status) {
    var store = makeWithProject(rootA); if (!store) return null
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", status || "started")]), 0)
    store.selectedRunId = "r1"
    return store
  }

  function test_logs_defaults() {
    var store = make(); if (!store) return
    compare(store.selectedAttempt, null)
    compare(store.logsText, "")
    compare(store.logsTruncated, false)
    compare(store.logsFetchedMs, 0)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.logsStatus, "")
    verify(!store.logsRunner.current, "no logs fetch at start")
  }

  function test_selecting_a_run_fetches_its_default_attempt() {
    var store = opened(); if (!store) return
    var proc = store.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    compare(argv(proc), tc.logsCmd + "r1|t1|implement|2")
    compare(proc.launchGuard, "/home/u/my proj", "guarded by the project")
    compare(store.selectedAttempt.card_id, "t1")
    compare(store.selectedAttempt.phase, "implement")
    compare(store.selectedAttempt.attempt, 2)
    compare(store.logsStatus, "started", "the status the fetch was launched for")
    compare(store.logsLoading, true)
  }

  function test_select_attempt_and_refresh_launch_the_exact_argv() {
    var store = opened(); if (!store) return
    store.selectAttempt("t1", "spec", 1)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|spec|1")
    compare(store.logsStatus, "done")
    var first = store.logsRunner.current
    var seq = store.logsRunner.seq
    store.refreshLogs()
    compare(store.logsRunner.seq, seq + 1, "Refresh fetches again")
    verify(store.logsRunner.current !== first)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|spec|1")
  }

  function test_no_logs_launch_without_project_run_or_selection() {
    var bare = make(); if (!bare) return
    bare.selectAttempt("t1", "spec", 1)
    verify(!bare.logsRunner.current, "no project")
    compare(bare.selectedAttempt, null)
    bare.refreshLogs()
    verify(!bare.logsRunner.current)

    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), entry("r2", "started", true)]), 0)
    store.selectAttempt("t1", "spec", 1)
    verify(!store.logsRunner.current, "no run selected")
    compare(store.selectedAttempt, null)
    store.selectedRunId = "r2"
    verify(!store.logsRunner.current, "a run with no attempt selects nothing")
    compare(store.selectedAttempt, null)
    store.refreshLogs()
    verify(!store.logsRunner.current, "no selection")
    store.selectAttempt("t1", "spec", 0)
    store.selectAttempt("t1", "", 1)
    store.selectAttempt("", "spec", 1)
    store.selectAttempt("t1", "spec", "1")
    verify(!store.logsRunner.current, "not a real attempt")
  }

  function test_an_ok_logs_reply_sets_text_truncation_and_time() {
    var store = opened(); if (!store) return
    var before = Date.now()
    reply(store.logsRunner.current, logsReply("collecting...\n3 passed\n"), 0)
    var after = Date.now()
    compare(store.logsText, "collecting...\n3 passed")
    compare(store.logsTruncated, false)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    verify(store.logsFetchedMs >= before && store.logsFetchedMs <= after, "fetched now: " + store.logsFetchedMs)
    var lines = []
    for (var i = 0; i < 250; i++) lines.push("line " + i)
    store.refreshLogs()
    reply(store.logsRunner.current, logsReply(lines.join("\n") + "\n", "boom\n"), 0)
    var shown = store.logsText.split("\n")
    compare(shown.length, 201, "the last 200 stdout lines, then stderr")
    compare(shown[0], "line 50")
    compare(shown[199], "line 249")
    compare(shown[200], "boom")
    compare(store.logsTruncated, true)
  }

  function test_logs_failures_keep_the_text_and_never_touch_am_status() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("kept\n"), 0)
    var types = ["AmMissing", "AmBadOutput", "HelperError", "Usage", "UnknownRunError"]
    for (var i = 0; i < types.length; i++) {
      store.refreshLogs()
      reply(store.logsRunner.current, JSON.stringify({ ok: false, error: { type: types[i], message: "m" } }) + "\n",
            types[i] === "Usage" ? 2 : 0)
      compare(store.logsError, types[i] + ": m", types[i])
      compare(store.logsText, "kept", types[i] + " keeps the last text")
      compare(store.logsLoading, false)
      compare(store.amStatus, "ok", types[i] + " is not a snapshot failure")
      compare(store.lastError, "")
      compare(store.runs.length, 1)
    }
    store.refreshLogs()
    reply(store.logsRunner.current, "Traceback (most recent call last):\n  oops {not json", 1)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 1).")
    store.refreshLogs()
    reply(store.logsRunner.current, "", 0)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 0).")
    store.refreshLogs()
    reply(store.logsRunner.current, "[]", 0)
    compare(store.logsError, "The logs snapshot gave no usable result (exit 0).")
    compare(store.logsText, "kept")
    compare(store.amStatus, "ok")
    compare(store.lastError, "")
    store.refreshLogs()
    reply(store.logsRunner.current, logsReply("new\n"), 0)
    compare(store.logsError, "", "a good reply clears the error")
    compare(store.logsText, "new")
  }

  function test_only_the_latest_logs_fetch_is_applied() {
    var store = opened(); if (!store) return
    var first = store.logsRunner.current
    store.selectAttempt("t1", "spec", 1)
    var second = store.logsRunner.current
    compare(first.running, false, "the older fetch is stopped")
    reply(second, logsReply("spec text\n"), 0)
    compare(store.logsText, "spec text")
    reply(first, logsReply("implement text\n"), 0)
    compare(store.logsText, "spec text", "a late reply for an older selection changes nothing")
  }

  // Review Focus 1.
  function test_selecting_another_attempt_clears_the_old_text_but_refresh_keeps_it() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("first\n"), 0)
    store.refreshLogs()
    compare(store.logsText, "first", "a refresh keeps the text until its reply")
    compare(store.logsLoading, true)
    store.selectAttempt("t1", "spec", 1)
    compare(store.logsText, "", "another attempt's text is never shown under this heading")
    compare(store.logsFetchedMs, 0)
    compare(store.logsError, "")
    compare(store.logsTruncated, false)
    compare(store.logsLoading, true)
  }

  function test_changing_the_selected_run_resets_to_its_default_attempt() {
    var store = makeWithProject(rootA); if (!store) return
    var r2 = treeEntry("r2", "started")
    r2.status.stories = [{ card_id: "s9", subtasks: ["t9"] }]
    r2.status.subtasks = [{ card_id: "t9", phases: [{ name: "review", status: "started", attempts: [{ n: 3, status: "started" }] }] }]
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started"), r2]), 0)
    store.selectedRunId = "r1"
    reply(store.logsRunner.current, logsReply("r1 text\n"), 0)
    store.selectAttempt("t1", "spec", 1)
    store.selectedRunId = "r2"
    compare(store.selectedAttempt.card_id, "t9")
    compare(store.selectedAttempt.phase, "review")
    compare(store.selectedAttempt.attempt, 3)
    compare(store.logsText, "")
    compare(store.logsFetchedMs, 0)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r2|t9|review|3")
    var pending = store.logsRunner.current
    store.selectedRunId = ""
    compare(store.selectedAttempt, null, "clearing the run clears the selection")
    compare(store.logsText, "")
    compare(store.logsLoading, false)
    compare(store.logsStatus, "")
    compare(pending.running, false, "the pending fetch is stopped")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "", "and its late reply is dropped")
  }

  function test_a_project_switch_clears_the_logs_and_drops_the_late_reply() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    store.refreshLogs()
    var pending = store.logsRunner.current
    store.project = rootB
    compare(store.selectedAttempt, null)
    compare(store.logsText, "")
    compare(store.logsTruncated, false)
    compare(store.logsFetchedMs, 0)
    compare(store.logsLoading, false)
    compare(store.logsError, "")
    compare(store.logsStatus, "")
    compare(store.logsRunner.guard, "/home/u/b")
    reply(pending, logsReply("late\n"), 0)
    compare(store.logsText, "", "A's late logs reply changes nothing")
  }

  function test_logs_add_no_timer_and_none_runs_while_idle() {
    var store = opened(); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var timers = []
    for (var i = 0; i < store.data.length; i++) {
      var o = store.data[i]
      if (o && typeof o.interval === "number" && typeof o.repeat === "boolean") timers.push(o.objectName)
    }
    compare(timers.sort().join(","), "debounceTimer,livenessTimer,pollTimer,staleTimer", "the logs add no timer")
    compare(store.debounceTimer.running, false)
    compare(store.livenessTimer.running, false)
    compare(store.staleTimer.running, false)
    compare(store.pollTimer.running, false)
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: exit 1. The new tests fail (`logsRunner` undefined → `TypeError: Cannot read property 'current' of undefined`, `selectAttempt is not a function`). The pre-existing tests still pass.

- [ ] **Step 3: Implement — header comment**

In `core/stores/RunStore.qml` replace lines 6-12:

```qml
// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run
// and whether `am` could be asked at all. While `active` (the panel is open) a
// long-lived runs-watch.py says which runs changed, and each burst of changes
// costs one debounced snapshot. The project root and the backend directory are
// handed to it from outside -- it never reaches for another store. App
// composes it as `app.runs` and binds `active` to the panel being open.
```

with:

```qml
// The am run monitor's data: one snapshot of the selected project's runs
// (runs-snapshot.py), normalized by the run domain model, plus the selected run,
// the attempt the Run detail pane shows and that attempt's `am logs` snapshot
// (runs-logs.py), and whether `am` could be asked at all. Two HelperRunners
// (snapshot, attempt logs) plus, while `active` (the panel is open), a
// long-lived runs-watch.py that says which runs changed; each burst of changes
// costs one debounced snapshot. Logs are fetched on a selection, on Refresh and
// when a snapshot changes the selected attempt's status -- never on a timer.
// The project root and the backend directory are handed to it from outside --
// it never reaches for another store. App composes it as `app.runs` and binds
// `active` to the panel being open.
```

- [ ] **Step 4: Implement — state and alias**

After line 43 (`property string watchSchemaError: "" // the schema banner text while its fallback poll runs`) insert:

```qml

  // The Run detail pane (5.2): which attempt of the selected run it shows and
  // that attempt's last `am logs` snapshot. Never a live tail.
  property var selectedAttempt: null  // { card_id, phase, attempt } or null
  property string logsText: ""        // Runs.logTail of the last good reply
  property bool logsTruncated: false  // lines were cut from it
  property real logsFetchedMs: 0      // Date.now() when that reply landed; 0 before any
  property bool logsLoading: false    // a fetch is in flight
  property string logsError: ""       // why the last fetch failed; "" after a good one
  property string logsStatus: ""      // the attempt's status when its fetch was launched
```

After line 51 (`readonly property alias pollTimer: pollTimer`) insert:

```qml
  readonly property alias logsRunner: logsRunner
```

- [ ] **Step 5: Implement — projectSwitched clears the logs**

In `projectSwitched()` replace:

```qml
    store.runs = []
    store.selectedRunId = ""
    store.runFilter = ""
```

with:

```qml
    store.runs = []
    store.selectedRunId = ""
    store.clearLogs()
    store.runFilter = ""
```

- [ ] **Step 6: Implement — logs functions**

Insert immediately before the line `  // The helper prints exactly one JSON line; anything before it (a warning) and`:

```qml
  // ---- attempt logs (5.2)

  // The run with this id in the snapshot, or null.
  function runById(id) {
    var list = store.runs
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }

  // Shows (and fetches) one attempt of the selected run. Another attempt than
  // the one shown starts from an empty pane -- its predecessor's text is never
  // shown under its heading. Nothing happens without a project, a selected run
  // or a real attempt (a non-empty card and phase, a number above 0).
  function selectAttempt(cardId, phase, attempt) {
    if (store.project === "" || store.selectedRunId === "") return
    if (typeof cardId !== "string" || cardId === "" || typeof phase !== "string" || phase === "") return
    if (typeof attempt !== "number" || !isFinite(attempt) || attempt <= 0) return
    var old = store.selectedAttempt
    if (!old || old.card_id !== cardId || old.phase !== phase || old.attempt !== attempt) {
      store.logsText = ""
      store.logsTruncated = false
      store.logsFetchedMs = 0
      store.logsError = ""
    }
    store.selectedAttempt = { card_id: cardId, phase: phase, attempt: attempt }
    store.fetchLogs()
  }

  // The Refresh button: the same attempt again; the text stays until the reply.
  function refreshLogs() {
    store.fetchLogs()
  }

  // One runs-logs.py launch for the current selection, remembering the status
  // it was launched for (a snapshot that changes it fetches again).
  function fetchLogs() {
    var sel = store.selectedAttempt
    if (store.project === "" || store.selectedRunId === "" || !sel) return
    store.logsStatus = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    store.logsLoading = true
    logsRunner.run([store.selectedRunId, sel.card_id, sel.phase, String(sel.attempt)])
  }

  // No selection and no logs; a fetch in flight is stopped and its reply dropped.
  function clearLogs() {
    logsRunner.cancel()
    store.selectedAttempt = null
    store.logsText = ""
    store.logsTruncated = false
    store.logsFetchedMs = 0
    store.logsLoading = false
    store.logsError = ""
    store.logsStatus = ""
  }

  // The selected run's default attempt, when it has one.
  function openDefaultAttempt() {
    var d = Runs.defaultAttempt(store.runById(store.selectedRunId))
    if (d) store.selectAttempt(d.card_id, d.phase, d.attempt)
  }

  // Another run (or none): the pane starts over on that run's default attempt.
  onSelectedRunIdChanged: {
    store.clearLogs()
    if (store.selectedRunId !== "") store.openDefaultAttempt()
  }

  // One logs reply. ok:true replaces the text with its last 200 lines; any
  // failure keeps the text and only says why. Never touches amStatus, runs or
  // lastError: those belong to the snapshot. A reply for a project the user
  // has left, or for an older fetch, never gets here (the runner's guards).
  function applyLogs(stdout, exitCode) {
    store.logsLoading = false
    var envelope = store.parseEnvelope(stdout)
    if (envelope !== null && envelope.ok === true) {
      var tail = Runs.logTail(envelope.data, 200)
      store.logsText = tail.text
      store.logsTruncated = tail.truncated
      store.logsFetchedMs = Date.now()
      store.logsError = ""
      return
    }
    if (envelope !== null && envelope.ok === false) {
      store.logsError = Runs.errorText(envelope)
      return
    }
    store.logsError = "The logs snapshot gave no usable result (exit " + exitCode + ")."
  }

```

- [ ] **Step 7: Implement — the runner**

Immediately after the `snapshotRunner` block (the `HelperRunner { id: snapshotRunner ... }` ending at line 293) insert:

```qml

  // The attempt-logs helper. Guarded by the project like the snapshot, so a
  // reply for a project the user has left is dropped; a newer fetch (another
  // attempt, a Refresh) wins over an older one. No onGuardChanged here: the
  // snapshot runner's already runs projectSwitched() once per switch.
  HelperRunner {
    id: logsRunner
    script: store.backendDir + "runs/runs-logs.py"
    guard: store.project
    onFinished: function(stdout, exitCode) { store.applyLogs(stdout, exitCode) }
  }
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: exit 0, 0 failed. This includes every pre-existing RunStore test, for example `test_a_project_switch_clears_runs_selection_and_error_and_refreshes`, whose plain `{id:"r1"}` run has no attempts and so launches no logs.

- [ ] **Step 9: Run the App wiring test too (App composes this store)**

Run: `bash tests/run.sh core/stores/tst_app_runs.qml`
Expected: exit 0.

- [ ] **Step 10: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): attempt logs runner, selection and replies (5.2)"
```

---

### Task 4: RunStore — refetch when a snapshot changes the selected attempt

**Files:**
- Modify: `core/stores/RunStore.qml` (`applySnapshot` ok branch; one new function next to the Task 3 logs functions)
- Test: `tests/core/stores/tst_run_store.qml`

**Interfaces:**
- Consumes: Task 3's `selectedAttempt`, `logsStatus`, `fetchLogs()`, `openDefaultAttempt()`, `runById()`; `Runs.attemptStatus`.
- Produces: `logsAfterSnapshot()`, called once per applied ok snapshot.

- [ ] **Step 1: Write the failing tests**

Append before the final closing `}` of `tests/core/stores/tst_run_store.qml`:

```qml
  // The next snapshot of project A lists `entries`.
  function snapshot(store, entries) {
    store.refresh()
    reply(store.snapshotRunner.current, okReply(entries), 0)
  }

  function test_a_snapshot_that_changes_the_attempt_status_fetches_once() {
    var store = opened("started"); if (!store) return
    reply(store.logsRunner.current, logsReply("a\n"), 0)
    var seq = store.logsRunner.seq
    snapshot(store, [treeEntry("r1", "started")])
    compare(store.logsRunner.seq, seq, "an unchanged status fetches nothing")
    store.refresh()
    reply(store.snapshotRunner.current, '{"ok": false, "error": {"type": "HelperError", "message": "boom"}}', 1)
    compare(store.logsRunner.seq, seq, "a failed snapshot fetches nothing")
    snapshot(store, [treeEntry("r1", "done")])
    compare(store.logsRunner.seq, seq + 1, "started -> done fetches the logs again")
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|implement|2")
    compare(store.logsStatus, "done")
    compare(store.logsText, "a", "the text stays until the new reply")
    snapshot(store, [treeEntry("r1", "done")])
    compare(store.logsRunner.seq, seq + 1, "only once")
  }

  function test_a_snapshot_without_a_selected_run_fetches_no_logs() {
    var store = makeWithProject(rootA); if (!store) return
    reply(store.snapshotRunner.current, okReply([treeEntry("r1", "started")]), 0)
    snapshot(store, [treeEntry("r1", "done")])
    verify(!store.logsRunner.current, "nothing is selected")
  }

  // Review Focus 2.
  function test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears() {
    var store = makeWithProject(rootA); if (!store) return
    var bare = treeEntry("r1", "started")
    bare.status.subtasks[0].phases = []
    reply(store.snapshotRunner.current, okReply([bare]), 0)
    store.selectedRunId = "r1"
    compare(store.selectedAttempt, null)
    verify(!store.logsRunner.current)
    snapshot(store, [treeEntry("r1", "started")])
    verify(store.selectedAttempt, "the first attempt is picked once it exists")
    compare(store.selectedAttempt.attempt, 2)
    compare(argv(store.logsRunner.current), tc.logsCmd + "r1|t1|implement|2")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh core/stores/tst_run_store.qml`
Expected: exit 1. `test_a_snapshot_that_changes_the_attempt_status_fetches_once` fails at "started -> done fetches the logs again". `test_a_run_opened_before_its_first_attempt_picks_one_when_it_appears` fails at "the first attempt is picked once it exists". `test_a_snapshot_without_a_selected_run_fetches_no_logs` already passes; it is a guard.

- [ ] **Step 3: Implement**

In `core/stores/RunStore.qml`, add right after the `openDefaultAttempt()` function from Task 3:

```qml
  // After every applied snapshot: a selected run with no attempt yet gets its
  // default once one exists; otherwise the selected attempt is fetched again
  // only when its status moved since its fetch was launched. Nothing else
  // fetches logs on its own.
  function logsAfterSnapshot() {
    if (store.selectedRunId === "") return
    var sel = store.selectedAttempt
    if (!sel) {
      store.openDefaultAttempt()
      return
    }
    var status = Runs.attemptStatus(store.runById(store.selectedRunId), sel.card_id, sel.phase, sel.attempt)
    if (status !== store.logsStatus) store.fetchLogs()
  }
```

In `applySnapshot`, replace:

```qml
      store.runs = out
      if (pollTimer.running && store.watchSchemaError !== "") {
```

with:

```qml
      store.runs = out
      store.logsAfterSnapshot()
      if (pollTimer.running && store.watchSchemaError !== "") {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh core/stores/`
Expected: exit 0, 0 failed across `tst_run_store.qml`, `tst_app_runs.qml` and the other store tests.

- [ ] **Step 5: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(run-store): refetch logs when a snapshot changes the attempt (5.2)"
```

---

### Task 5: RunDetailScreen

**Files:**
- Create: `ui/screens/RunDetailScreen.qml`
- Test: `tests/ui/screens/tst_run_detail_screen.qml` (new, same tier and conventions as `tests/ui/screens/tst_runs_screen.qml`)

**Interfaces:**
- Consumes: `app.nav.viewMode`, `app.projects.selectedProject`, `app.board.cardMap` (`{ [id]: { title, status } }`), and `app.runs.{runs, selectedRunId, selectedAttempt, logsText, logsTruncated, logsFetchedMs, logsLoading, logsError, selectAttempt(), refreshLogs()}`. Also `Runs.runTree/runState/shortId/escalationReason/glyphStateOf/snapshotAgeText` and `RunGlyphs.glyphOf`. Shared components: `UI.ThemedText`, `UI.ListRow`, `UI.ListStatus`, `UI.ActionButton` and `UI.PhaseTimeline`.
- Produces: QML type `RunDetailScreen` (objectName `runDetailView`) with child objectNames `runDetailMissing`, `runDetailBody`, `runDetailTitle`, `runDetailState`, `runDetailMeta`, `runDetailReason`, `runStory<i>`, `runSubtask<i>_<j>`, `runSubtaskLabel<i>_<j>`, `runTimeline<i>_<j>`, `runAttempt<i>_<j>_<k>`, `runAttemptLabel<i>_<j>_<k>`, `runSynthetic<k>`, `runOutputPane`, `runOutputHeading`, `runOutputAge`, `runOutputRefresh`, `runOutputNone`, `runOutputError` and `runOutputText`.

- [ ] **Step 1: Write the failing test file**

Create `tests/ui/screens/tst_run_detail_screen.qml`:

```qml
// tests/ui/screens/tst_run_detail_screen.qml
// ui/screens/RunDetailScreen.qml on its own: the header, the story > subtask >
// attempt tree with its bookkeeping rows, the output pane and the missing-run
// line. A stub app: a REAL NavigationStore, a plain object carrying the
// RunStore properties the screen reads (with recorders for selectAttempt and
// refreshLogs), and a board whose cardMap lends titles and brd statuses.
import QtQuick
import QtTest
import "../../helpers/find.js" as H
import "../../../ui/components/runGlyphs.js" as RG

TestCase {
  id: tc
  name: "RunDetailScreen"
  when: windowShown
  visible: true
  width: 500; height: 900

  Component { id: hostC; Item { width: 500; height: 900 } }

  Component {
    id: runsC
    QtObject {
      id: rs
      property var runs: []
      property string selectedRunId: ""
      property var selectedAttempt: null
      property string logsText: ""
      property bool logsTruncated: false
      property real logsFetchedMs: 0
      property bool logsLoading: false
      property string logsError: ""
      property string amStatus: "ok"
      property var selected: null
      property int refreshed: 0
      function selectAttempt(cardId, phase, attempt) {
        rs.selected = [cardId, phase, attempt]
        rs.selectedAttempt = { card_id: cardId, phase: phase, attempt: attempt }
      }
      function refreshLogs() { rs.refreshed += 1 }
    }
  }

  Component {
    id: appC
    QtObject {
      property var nav: null
      property var runs: null
      property var projects: ({ selectedProject: { root_path: "/home/u/a", name: "alpha" } })
      property var board: ({ cardMap: {
        s1: { id: "s1", title: "Runs screens", status: "in_progress" },
        t1: { id: "t1", title: "RunDetailScreen", status: "in_progress" },
        t2: { id: "t2", title: "Old work", status: "merged" },
        s2: { id: "s2", title: "Dropped story", status: "canceled" },
        t3: { id: "t3", title: "Shelved", status: "archived" }
      } })
    }
  }

  function make(list, selectedId, attempt) {
    var host = createTemporaryObject(hostC, tc)
    var navComp = Qt.createComponent("../../../core/stores/NavigationStore.qml")
    if (navComp.status !== Component.Ready) { fail(navComp.errorString()); return null }
    var nav = navComp.createObject(host)
    var runs = runsC.createObject(host)
    var app = appC.createObject(host, { nav: nav, runs: runs })
    var sC = Qt.createComponent("../../../ui/screens/RunDetailScreen.qml")
    if (sC.status !== Component.Ready) { fail(sC.errorString()); return null }
    var screen = sC.createObject(host, { width: 500, app: app, navigator: null })
    nav.viewMode = "run"
    runs.runs = list || []
    runs.selectedRunId = selectedId === undefined ? "run-20261004-19efcddc" : selectedId
    runs.selectedAttempt = attempt === undefined ? null : attempt
    wait(20)
    return { app: app, runs: runs, nav: nav, screen: screen }
  }

  // Two clicks inside the double-click interval make the second a double-click.
  function tap(item) {
    wait(450)
    mouseClick(item)
  }

  // A normalised run, as RunStore holds them. live === null means no lease.
  function run(id, status, live, opts) {
    var o = opts || {}
    return { id: id, repo_dir: "/home/u/a", milestone_id: o.milestone === undefined ? "M3" : o.milestone,
             base_branch: o.base === undefined ? "master" : o.base,
             branch_prefix: o.prefix === undefined ? "m3" : o.prefix,
             status: status, started_at: "",
             lease: live === null ? null : { pid: 4121, host: "h", heartbeat_at: "", accepting: true, live: live },
             rows: o.rows || [], tree: o.tree || { stories: [], subtasks: [] } }
  }

  function detailTree() {
    return { stories: [{ card_id: "s1", status: "started", subtasks: ["t1", "t2"] },
                       { card_id: "s2", status: "cancelled", subtasks: ["t3"] }],
             subtasks: [
               { card_id: "t1", status: "started", phases: [
                 { name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] },
                 { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] },
               { card_id: "t2", status: "done", phases: [{ name: "spec", status: "done", attempts: [{ n: 1, status: "done" }] }] },
               { card_id: "t3", phases: [] }] }
  }

  function detail() { return [run("run-20261004-19efcddc", "started", true, { tree: detailTree() })] }
  function sel(card, phase, n) { return { card_id: card, phase: phase, attempt: n } }

  // ---- header

  function test_the_header_names_the_run_its_state_and_its_branches() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runDetailTitle").text, "Run …19efcddc")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("running") + " running")
    compare(H.find(s.screen, "runDetailMeta").text, "Milestone M3 · prefix m3 · base master · lease pid 4121 live")
    compare(H.find(s.screen, "runDetailReason").visible, false, "only an escalated run has a reason")
  }

  function test_a_dead_lease_and_no_lease() {
    var s = make([run("run-x-dead0001", "started", false, {})], "run-x-dead0001"); if (!s) return
    compare(H.find(s.screen, "runDetailMeta").text, "Milestone M3 · prefix m3 · base master · lease pid 4121 not live")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("dead") + " dead")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent), "dead is urgent")
    s.runs.runs = [run("run-x-dead0001", "stopped", null, { milestone: "", prefix: "", base: "" })]
    compare(H.find(s.screen, "runDetailMeta").text, "no lease", "empty parts are left out")
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("parked") + " parked")
  }

  function test_an_escalated_run_shows_its_reason_in_urgent() {
    var s = make([run("run-x-escl0002", "escalated", null, { tree: { stories: [], subtasks: [
      { card_id: "t1", phases: [{ name: "review", status: "failed", detail: "tests red after 3 attempts" }] }] } })],
      "run-x-escl0002"); if (!s) return
    compare(H.find(s.screen, "runDetailState").text, RG.glyphOf("escalated") + " escalated")
    verify(Qt.colorEqual(H.find(s.screen, "runDetailState").color, s.screen.theme.urgent))
    var reason = H.find(s.screen, "runDetailReason")
    compare(reason.visible, true)
    compare(reason.text, "tests red after 3 attempts")
    verify(Qt.colorEqual(reason.color, s.screen.theme.urgent))
  }

  // ---- tree

  function test_story_and_subtask_rows_carry_glyph_title_status_and_phase() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runStory0").text, RG.glyphOf("running") + " s1 Runs screens · started")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, RG.glyphOf("running") + " t1 RunDetailScreen · started · implement.2")
    compare(H.find(s.screen, "runSubtaskLabel0_1").text, RG.glyphOf("done") + " t2 Old work · done · spec.1")
    compare(H.find(s.screen, "runStory1").text, RG.glyphOf("cancelled") + " s2 Dropped story · cancelled")
    compare(H.find(s.screen, "runSubtaskLabel1_0").text, "t3 Shelved", "no status, no phase: just the card")
  }

  function test_terminal_brd_cards_are_dimmed_not_hidden() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSubtask0_0").opacity, 1)
    compare(H.find(s.screen, "runSubtask0_1").visible, true, "merged is listed")
    compare(H.find(s.screen, "runSubtask0_1").opacity, 0.5)
    compare(H.find(s.screen, "runStory1").visible, true, "canceled is listed")
    compare(H.find(s.screen, "runStory1").opacity, 0.5)
    compare(H.find(s.screen, "runSubtask1_0").opacity, 0.5, "archived too")
    compare(H.find(s.screen, "runStory0").opacity, 1)
  }

  function test_the_timeline_and_attempts_show_under_the_selected_subtask_only() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    var tl = H.find(s.screen, "runTimeline0_0")
    compare(tl.visible, true)
    compare(tl.text, "spec" + RG.GLYPHS.done + " → implement" + RG.GLYPHS.running)
    compare(H.find(s.screen, "runTimeline0_1").visible, false)
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("done") + " spec.1 done")
    compare(H.find(s.screen, "runAttemptLabel0_0_1").text, "  " + RG.glyphOf("dead") + " implement.1 failed")
    var chosen = H.find(s.screen, "runAttemptLabel0_0_2")
    compare(chosen.text, "› " + RG.glyphOf("running") + " implement.2 started", "a marker, not colour alone")
    compare(chosen.font.bold, true)
    compare(H.find(s.screen, "runAttemptLabel0_0_1").font.bold, false)
    compare(H.find(s.screen, "runAttempt0_1_0"), null, "another subtask's attempts stay folded")
  }

  function test_no_selection_shows_no_attempt_rows() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runAttempt0_0_0"), null)
    compare(H.find(s.screen, "runTimeline0_0").visible, false)
    compare(H.find(s.screen, "runOutputNone").visible, true)
    compare(H.find(s.screen, "runOutputNone").text, "No attempt selected")
    compare(H.find(s.screen, "runOutputRefresh").visible, false)
  }

  function test_clicking_an_attempt_selects_it() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected.join("|"), "t1|spec|1")
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text.indexOf("› "), 0, "the clicked row is marked")
    compare(H.find(s.screen, "runAttemptLabel0_0_2").text.indexOf("  "), 0)
  }

  // Review Focus 4.
  function test_clicking_a_subtask_selects_its_current_attempt() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runSubtask0_1"))
    compare(s.runs.selected.join("|"), "t2|spec|1")
    verify(H.find(s.screen, "runAttempt0_1_0"), "its attempts unfold")
    compare(H.find(s.screen, "runAttempt0_0_0"), null, "the other subtask folds")
    s.runs.selected = null
    tap(H.find(s.screen, "runSubtask1_0"))
    compare(s.runs.selected, null, "a subtask with no attempt selects nothing")
  }

  // Review Focus 3.
  function test_an_unnumbered_attempt_is_listed_but_not_clickable() {
    var tree = { stories: [], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ status: "started" }, { n: 1, status: "failed" }] }] }] }
    var s = make([run("run-20261004-19efcddc", "started", true, { tree: tree })], undefined, sel("t1", "implement", 1)); if (!s) return
    compare(H.find(s.screen, "runAttemptLabel0_0_0").text, "  " + RG.glyphOf("running") + " implement.? started")
    s.runs.selected = null
    tap(H.find(s.screen, "runAttempt0_0_0"))
    compare(s.runs.selected, null)
  }

  function test_bookkeeping_rows_only_when_present() {
    var s = make(detail()); if (!s) return
    compare(H.find(s.screen, "runSynthetic0"), null)
    var tree = detailTree()
    tree.stories.push({ card_id: "base-s1", status: "done" })
    s.runs.runs = [run("run-20261004-19efcddc", "started", true,
                       { tree: tree, rows: [{ card_id: "integrate", phase: "integrate", status: "" }] })]
    compare(H.find(s.screen, "runSynthetic0").text, RG.glyphOf("done") + " Base s1 done")
    compare(H.find(s.screen, "runSynthetic1").text, "Integrate not started")
    compare(H.find(s.screen, "runStory2"), null, "a bookkeeping id is never a story row")
  }

  // ---- output pane

  function test_the_output_pane_is_a_labelled_snapshot_never_live() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsText = "collecting...\n3 passed"
    s.runs.logsFetchedMs = Date.now() - 14000
    var heading = H.find(s.screen, "runOutputHeading")
    var age = H.find(s.screen, "runOutputAge")
    compare(heading.text, "Output · t1 implement.2")
    compare(age.text, "snapshot 14s ago")
    compare(H.find(s.screen, "runOutputText").text, "collecting...\n3 passed")
    s.runs.logsTruncated = true
    compare(age.text, "snapshot 14s ago · last 200 lines")
    compare(heading.text.indexOf("live"), -1)
    compare(age.text.indexOf("live"), -1)
    compare(H.find(s.screen, "runOutputRefresh").text, "Refresh")
  }

  function test_loading_then_an_error_that_keeps_the_text() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    s.runs.logsLoading = true
    compare(H.find(s.screen, "runOutputAge").text, "loading…")
    s.runs.logsLoading = false
    s.runs.logsText = "old text"
    s.runs.logsError = "AmMissing: am is not installed."
    var err = H.find(s.screen, "runOutputError")
    compare(err.visible, true)
    compare(err.text, "AmMissing: am is not installed.")
    verify(Qt.colorEqual(err.color, s.screen.theme.urgent))
    compare(H.find(s.screen, "runOutputText").visible, true, "the last text stays")
    compare(H.find(s.screen, "runOutputText").text, "old text")
    compare(H.find(s.screen, "runStory0").visible, true, "the tree stays as the snapshot left it")
  }

  function test_refresh_asks_the_store_again() {
    var s = make(detail(), undefined, sel("t1", "implement", 2)); if (!s) return
    tap(H.find(s.screen, "runOutputRefresh"))
    compare(s.runs.refreshed, 1)
  }

  // ---- missing, malformed, visibility

  function test_a_run_no_longer_in_the_snapshot() {
    var s = make(detail(), "run-gone"); if (!s) return
    var msg = H.find(s.screen, "runDetailMissing")
    compare(msg.visible, true)
    compare(msg.text, "This run is no longer in the snapshot")
    compare(H.find(s.screen, "runDetailBody").visible, false)
  }

  function test_a_malformed_run_renders_without_throwing() {
    var odd = { id: "run-20261004-19efcddc", status: 7, lease: "x", rows: "y",
                tree: { stories: "x", subtasks: [null, 5, { card_id: 7 }, { card_id: "t9", phases: "x" }] } }
    var s = make([odd]); if (!s) return
    compare(H.find(s.screen, "runDetailMissing").visible, false)
    compare(H.find(s.screen, "runStory0").text, "Other")
    compare(H.find(s.screen, "runSubtaskLabel0_0").text, "t9")
    compare(H.find(s.screen, "runOutputNone").visible, true)
  }

  function test_the_screen_is_hidden_outside_the_run_view() {
    var s = make(detail()); if (!s) return
    compare(s.screen.visible, true)
    s.nav.viewMode = "runs"
    compare(s.screen.visible, false)
    s.nav.viewMode = "run"
    s.app.projects = { selectedProject: null }
    compare(s.screen.visible, false)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: exit 1. Every test FAILs with `... RunDetailScreen.qml: No such file or directory` from `fail(sC.errorString())`.

- [ ] **Step 3: Implement the screen**

Create `ui/screens/RunDetailScreen.qml`:

```qml
import QtQuick
import qs.Commons
import "../../core/domain/runs.js" as Runs
import "../components/runGlyphs.js" as RunGlyphs
import "../components" as UI
import "../theme" as T

// One am run (the "run" view): a header with its state, milestone, branch
// prefix and base and lease; its story > subtask > phase > attempt tree, with
// the orchestrator's own Integrate / Bases / Base rows when it has them; and an
// output pane holding ONE attempt's `am logs` snapshot -- labelled with its age,
// never presented as a live tail. Run state always comes from am (the run
// store), never from a brd status; brd's board only lends titles and dims the
// cards it has closed. It reads the run store and asks it to show another
// attempt or fetch again; it owns no state of its own. Ages are read against
// the clock when a logs reply lands or a snapshot replaces the runs: no timer.
Column {
  id: screen
  objectName: "runDetailView"

  property var app
  property var navigator
  property var theme: T.Theme {}

  // The panel scrolls; Panel wires this like every other screen's.
  signal revealRequested(var item)

  readonly property var run: screen.runById(screen.app.runs.runs, screen.app.runs.selectedRunId)
  readonly property var tree: Runs.runTree(screen.run)
  readonly property string runState: Runs.runState(screen.run)
  readonly property var selection: screen.app.runs.selectedAttempt
  // Re-read whenever a logs reply lands or a snapshot replaces the runs.
  readonly property real nowMs: screen.app.runs.logsFetchedMs >= 0 && screen.app.runs.runs ? Date.now() : 0

  visible: screen.app.nav.viewMode === "run" && !!screen.app.projects.selectedProject
  spacing: Style.space(6)

  function runById(list, id) {
    if (!list || typeof id !== "string" || id === "") return null
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
    return null
  }

  // "Milestone M3 · prefix m3 · base master · lease pid 4121 live"; empty parts
  // are left out, and a run without a lease says so.
  function metaText(run) {
    if (!run) return ""
    var parts = []
    if (typeof run.milestone_id === "string" && run.milestone_id !== "") parts.push("Milestone " + run.milestone_id)
    if (typeof run.branch_prefix === "string" && run.branch_prefix !== "") parts.push("prefix " + run.branch_prefix)
    if (typeof run.base_branch === "string" && run.base_branch !== "") parts.push("base " + run.base_branch)
    var lease = run.lease
    if (lease !== null && typeof lease === "object") {
      var pid = lease.pid === undefined || lease.pid === null || lease.pid === "" ? "" : " pid " + lease.pid
      parts.push("lease" + pid + (lease.live === true ? " live" : " not live"))
    } else {
      parts.push("no lease")
    }
    return parts.join(" · ")
  }

  // The brd card behind an id, or null. Own keys only, so "__proto__" is no card.
  function cardOf(id) {
    var map = screen.app.board ? screen.app.board.cardMap : null
    if (!map || typeof id !== "string" || id === "") return null
    return Object.prototype.hasOwnProperty.call(map, id) ? map[id] : null
  }

  function titleOf(id) {
    var card = screen.cardOf(id)
    return card && typeof card.title === "string" ? card.title : ""
  }

  // brd has closed this card: it is listed dimmed, never hidden.
  function isClosed(id) {
    var card = screen.cardOf(id)
    return !!card && (card.status === "merged" || card.status === "canceled" || card.status === "archived")
  }

  function glyphOf(status) { return RunGlyphs.glyphOf(Runs.glyphStateOf(status)) }

  function isUrgent(status) {
    var s = Runs.glyphStateOf(status)
    return s === "escalated" || s === "dead"
  }

  // "<glyph> <id> <title> · <status>", each part only when it has something.
  function cardLine(id, status) {
    var parts = []
    var glyph = screen.glyphOf(status)
    if (glyph !== "") parts.push(glyph)
    parts.push(id)
    var title = screen.titleOf(id)
    if (title !== "") parts.push(title)
    var line = parts.join(" ")
    return status !== "" ? line + " · " + status : line
  }

  function phaseText(subtask) {
    if (subtask.currentPhase === "") return ""
    return subtask.currentAttempt > 0 ? subtask.currentPhase + "." + subtask.currentAttempt : subtask.currentPhase
  }

  function attemptText(a) {
    var glyph = screen.glyphOf(a.status)
    var label = a.phase + "." + (a.attempt > 0 ? a.attempt : "?")
    return (glyph !== "" ? glyph + " " : "") + label + (a.status !== "" ? " " + a.status : "")
  }

  function syntheticText(entry) {
    var glyph = screen.glyphOf(entry.status)
    return (glyph !== "" ? glyph + " " : "") + entry.label + " " + (entry.status !== "" ? entry.status : "not started")
  }

  function isSelected(cardId, phase, attempt) {
    var s = screen.selection
    return !!s && s.card_id === cardId && s.phase === phase && s.attempt === attempt
  }

  // The pane's age line: the snapshot's age (and "last 200 lines" when cut),
  // "loading…" before the first reply, "" otherwise. Never "live".
  function outputAge() {
    var store = screen.app.runs
    if (!screen.selection) return ""
    if (store.logsFetchedMs > 0) {
      var age = Runs.snapshotAgeText(store.logsFetchedMs, screen.nowMs)
      var line = age !== "" ? "snapshot " + age + " ago" : "snapshot"
      return store.logsTruncated ? line + " · last 200 lines" : line
    }
    return store.logsLoading ? "loading…" : ""
  }

  // Safe reads by position: a Repeater may still bind a delegate once while
  // the tree it came from shrinks under it.
  function storyAt(i) {
    return screen.tree.stories[i] || ({ card_id: "", label: "", status: "", other: false, subtasks: [] })
  }
  function subtaskAt(i, j) {
    return screen.storyAt(i).subtasks[j] || ({ card_id: "", status: "", phases: [], attempts: [], currentPhase: "", currentAttempt: 0 })
  }
  function attemptAt(subtask, k) {
    return subtask.attempts[k] || ({ phase: "", attempt: 0, status: "" })
  }
  function syntheticAt(k) {
    return screen.tree.synthetic[k] || ({ id: "", label: "", status: "" })
  }

  UI.ListStatus {
    objectName: "runDetailMissing"
    theme: screen.theme
    width: parent.width
    empty: !screen.run
    emptyText: "This run is no longer in the snapshot"
  }

  Column {
    objectName: "runDetailBody"
    width: parent.width
    spacing: Style.space(6)
    visible: !!screen.run

    Row {
      width: parent.width
      spacing: Style.space(8)

      UI.ThemedText {
        objectName: "runDetailTitle"
        variant: "heading"
        theme: screen.theme
        text: "Run " + Runs.shortId(screen.run)
      }

      UI.ThemedText {
        objectName: "runDetailState"
        variant: "heading"
        theme: screen.theme
        text: (RunGlyphs.glyphOf(screen.runState) !== "" ? RunGlyphs.glyphOf(screen.runState) + " " : "") + screen.runState
        color: screen.runState === "escalated" || screen.runState === "dead" ? screen.theme.urgent : screen.theme.foreground
      }
    }

    UI.ThemedText {
      objectName: "runDetailMeta"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: text !== ""
      text: screen.metaText(screen.run)
      wrapMode: Text.WordWrap
    }

    UI.ThemedText {
      objectName: "runDetailReason"
      variant: "caption"
      theme: screen.theme
      width: parent.width
      visible: screen.runState === "escalated"
      text: Runs.escalationReason(screen.run)
      color: screen.theme.urgent
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: screen.tree.stories.length
      delegate: StoryBlock {}
    }

    Repeater {
      model: screen.tree.synthetic.length
      delegate: SyntheticRow {}
    }

    Column {
      objectName: "runOutputPane"
      width: parent.width
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(10)

        UI.ThemedText {
          objectName: "runOutputHeading"
          theme: screen.theme
          text: screen.selection
            ? "Output · " + screen.selection.card_id + " " + screen.selection.phase + "." + screen.selection.attempt
            : "Output"
        }

        UI.ThemedText {
          objectName: "runOutputAge"
          variant: "caption"
          theme: screen.theme
          visible: text !== ""
          text: screen.outputAge()
        }

        UI.ActionButton {
          objectName: "runOutputRefresh"
          theme: screen.theme
          visible: !!screen.selection
          text: "Refresh"
          tooltipText: "Fetch this attempt's output again"
          onClicked: screen.app.runs.refreshLogs()
        }
      }

      UI.ThemedText {
        objectName: "runOutputNone"
        variant: "dim"
        theme: screen.theme
        visible: !screen.selection
        text: "No attempt selected"
      }

      UI.ThemedText {
        objectName: "runOutputError"
        variant: "caption"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && screen.app.runs.logsError !== ""
        text: screen.app.runs.logsError
        color: screen.theme.urgent
        wrapMode: Text.WordWrap
      }

      // Read-only by nature: a Text, in the theme's font, never an editor.
      UI.ThemedText {
        objectName: "runOutputText"
        variant: "small"
        theme: screen.theme
        width: parent.width
        visible: !!screen.selection && text !== ""
        text: screen.app.runs.logsText
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
      }
    }
  }

  component StoryBlock: Column {
    id: storyBlock
    required property int index
    readonly property var story: screen.storyAt(storyBlock.index)

    width: screen.width
    spacing: Style.space(2)

    UI.ThemedText {
      objectName: "runStory" + storyBlock.index
      theme: screen.theme
      width: parent.width
      opacity: !storyBlock.story.other && screen.isClosed(storyBlock.story.card_id) ? 0.5 : 1
      text: storyBlock.story.other ? storyBlock.story.label : screen.cardLine(storyBlock.story.card_id, storyBlock.story.status)
      color: screen.isUrgent(storyBlock.story.status) ? screen.theme.urgent : screen.theme.foreground
      elide: Text.ElideRight
    }

    Repeater {
      model: storyBlock.story.subtasks.length
      delegate: SubtaskBlock { storyIndex: storyBlock.index }
    }
  }

  component SubtaskBlock: Column {
    id: subBlock
    required property int index
    property int storyIndex: -1
    readonly property var subtask: screen.subtaskAt(subBlock.storyIndex, subBlock.index)
    readonly property bool expanded: !!screen.selection && screen.selection.card_id === subBlock.subtask.card_id
    readonly property string key: subBlock.storyIndex + "_" + subBlock.index

    width: screen.width
    spacing: Style.space(2)

    UI.ListRow {
      objectName: "runSubtask" + subBlock.key
      width: parent.width
      theme: screen.theme
      contentMargin: Style.space(22)
      opacity: screen.isClosed(subBlock.subtask.card_id) ? 0.5 : 1
      onActivated: {
        if (subBlock.subtask.currentAttempt > 0)
          screen.app.runs.selectAttempt(subBlock.subtask.card_id, subBlock.subtask.currentPhase, subBlock.subtask.currentAttempt)
      }

      UI.ThemedText {
        objectName: "runSubtaskLabel" + subBlock.key
        theme: screen.theme
        width: parent.width
        text: {
          var line = screen.cardLine(subBlock.subtask.card_id, subBlock.subtask.status)
          var phase = screen.phaseText(subBlock.subtask)
          return phase !== "" ? line + " · " + phase : line
        }
        color: screen.isUrgent(subBlock.subtask.status) ? screen.theme.urgent : screen.theme.foreground
        elide: Text.ElideRight
      }
    }

    UI.PhaseTimeline {
      objectName: "runTimeline" + subBlock.key
      x: Style.space(32)
      theme: screen.theme
      visible: subBlock.expanded && text !== ""
      phases: subBlock.subtask.phases
    }

    Repeater {
      model: subBlock.expanded ? subBlock.subtask.attempts.length : 0
      delegate: AttemptRow { storyIndex: subBlock.storyIndex; subtaskIndex: subBlock.index }
    }
  }

  component AttemptRow: UI.ListRow {
    id: attemptRow
    required index
    property int storyIndex: -1
    property int subtaskIndex: -1
    readonly property var subtask: screen.subtaskAt(attemptRow.storyIndex, attemptRow.subtaskIndex)
    readonly property var attempt: screen.attemptAt(attemptRow.subtask, attemptRow.index)
    readonly property bool selected: screen.isSelected(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    readonly property string key: attemptRow.storyIndex + "_" + attemptRow.subtaskIndex + "_" + attemptRow.index

    objectName: "runAttempt" + attemptRow.key
    width: screen.width
    theme: screen.theme
    contentMargin: Style.space(32)
    hoverCursorShape: attemptRow.attempt.attempt > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onActivated: {
      if (attemptRow.attempt.attempt > 0)
        screen.app.runs.selectAttempt(attemptRow.subtask.card_id, attemptRow.attempt.phase, attemptRow.attempt.attempt)
    }

    UI.ThemedText {
      objectName: "runAttemptLabel" + attemptRow.key
      theme: screen.theme
      text: (attemptRow.selected ? "› " : "  ") + screen.attemptText(attemptRow.attempt)
      font.bold: attemptRow.selected
      color: screen.isUrgent(attemptRow.attempt.status) ? screen.theme.urgent : screen.theme.foreground
    }
  }

  component SyntheticRow: UI.ThemedText {
    id: synthRow
    required property int index
    readonly property var entry: screen.syntheticAt(synthRow.index)

    objectName: "runSynthetic" + synthRow.index
    theme: screen.theme
    width: screen.width
    text: screen.syntheticText(synthRow.entry)
    color: screen.isUrgent(synthRow.entry.status) ? screen.theme.urgent : screen.theme.foreground
  }
}
```

Notes for the implementer:
- `AttemptRow` uses `required index` (not `required property int index`) because `ListRow` already declares `index`. This is the same idiom as `RunsScreen.RunRow`. The row's `cursorIndex` stays `-1`, so it never takes the keyboard cursor. That is right: keyboard movement between attempts is out of scope.
- `ListRow` puts its declared children into its own content column, so the `UI.ThemedText` inside it gets `parent.width` from that column.
- Do not add `font.family:` anywhere. `ThemedText` already sets it, and the architecture guard rejects a second copy.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/run.sh tst_run_detail_screen`
Expected: exit 0, 0 failed, and no `TypeError`/`ReferenceError`/`Unable to assign` lines (run.sh fails on those).

- [ ] **Step 5: Run the architecture rules**

Run: `python3 -m pytest tests/architecture -q`
Expected: all pass. This covers layers (no `core/stores` import), duplication guards and icon glyphs.

- [ ] **Step 6: Commit**

```bash
git add ui/screens/RunDetailScreen.qml tests/ui/screens/tst_run_detail_screen.qml
git commit -m "feat(ui): RunDetailScreen with tree and logs snapshot pane (5.2)"
```

---

### Task 6: Mount in Panel and the flow tests

**Files:**
- Modify: `ui/Panel.qml:551-559`
- Test: `tests/ui/tst_runs_flow.qml`

**Interfaces:**
- Consumes: `RunDetailScreen` (Task 5), `app.runs.logsRunner`, `selectedAttempt`, `logsText` (Task 3), and `navi.openRun`, `p.shortcuts.closeRequested()` (5.1, unchanged).
- Produces: the run view's body in the real panel.

- [ ] **Step 1: Write the failing flow tests**

Append before the final closing `}` of `tests/ui/tst_runs_flow.qml` (existing tests stay untouched, including `test_the_run_view_renders_and_enter_there_does_nothing`):

```qml
  // ---- Run detail (5.2)

  // A started run with one story s1 > subtask t1 whose implement phase is on
  // its second attempt.
  function treeRun(id) {
    var r = run(id, "started", true, "alpha")
    r.tree = { stories: [{ card_id: "s1", subtasks: ["t1"] }], subtasks: [{ card_id: "t1", phases: [
      { name: "implement", status: "started", attempts: [{ n: 1, status: "failed" }, { n: 2, status: "started" }] }] }] }
    return r
  }

  // The panel on the detail view of treeRun("run-0000000000e5"), its default
  // attempt's logs in flight.
  function openDetail() {
    var p = make(); if (!p) return null
    p.app.runs.runs = [treeRun("run-0000000000e5")]
    p.navigator.showSection("runs")
    p.navigator.openRun("run-0000000000e5")
    wait(50)
    return p
  }

  function logsOk(text) { return JSON.stringify({ ok: true, data: { stdout: text, stderr: "" } }) + "\n" }

  function test_opening_a_run_shows_it_and_fetches_its_default_attempt() {
    var p = openDetail(); if (!p) return
    compare(p.app.nav.viewMode, "run")
    var view = H.find(p, "runDetailView")
    verify(view, "the Run detail screen is mounted")
    compare(view.visible, true)
    compare(H.find(p, "runsView").visible, false)
    compare(H.find(p, "runDetailTitle").text, "Run …000000e5")
    var proc = p.app.runs.logsRunner.current
    verify(proc, "the default attempt's logs were asked for")
    verify(String(proc.command[1]).indexOf("core/backend/runs/runs-logs.py") > 0, String(proc.command[1]))
    compare(proc.command.slice(2).join("|"), "run-0000000000e5|t1|implement|2")
    proc.outText = logsOk("3 passed\n")
    proc.exited(0)
    compare(H.find(p, "runOutputHeading").text, "Output · t1 implement.2")
    compare(H.find(p, "runOutputText").text, "3 passed")
    compare(p.navigator.currentList().length, 0, "no keyboard list in the run view")
  }

  function test_escape_returns_to_runs_and_clears_the_logs() {
    var p = openDetail(); if (!p) return
    var proc = p.app.runs.logsRunner.current
    proc.outText = logsOk("3 passed\n")
    proc.exited(0)
    compare(p.app.runs.logsText, "3 passed")
    p.shortcuts.closeRequested()
    compare(p.app.nav.viewMode, "runs")
    compare(p.app.runs.selectedRunId, "")
    compare(p.app.runs.selectedAttempt, null)
    compare(p.app.runs.logsText, "")
    compare(H.find(p, "runDetailView").visible, false)
    compare(H.find(p, "runsView").visible, true)
  }

  function test_a_project_switch_on_the_run_view_clears_it() {
    var p = openDetail(); if (!p) return
    var proc = p.app.runs.logsRunner.current
    p.app.projects.applyProjectsList([{ root_path: "/home/u/b", name: "beta" }])
    p.app.runs.snapshotRunner.cancel()
    compare(p.app.runs.selectedAttempt, null)
    compare(p.app.runs.logsText, "")
    compare(H.find(p, "runDetailView").visible, false)
    proc.outText = logsOk("late\n")
    proc.exited(0)
    compare(p.app.runs.logsText, "", "the old project's late reply changes nothing")
  }
```

- [ ] **Step 2: Run the flow tests to verify they fail**

Run: `bash tests/run.sh tst_runs_flow`
Expected: exit 1. `test_opening_a_run_shows_it_and_fetches_its_default_attempt` FAILs at "the Run detail screen is mounted". `test_escape_returns_to_runs_and_clears_the_logs` FAILs on `H.find(p, "runDetailView").visible` (TypeError on null). The pre-existing flow tests pass.

- [ ] **Step 3: Mount the screen**

In `ui/Panel.qml` replace:

```qml
          // The "run" view's body is card 5.2's; until then the run mode
          // shows nothing here.
          RunsScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }
```

with:

```qml
          RunsScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }

          RunDetailScreen {
            width: parent.width
            app: appStores
            navigator: navi
            theme: panelTheme
            onRevealRequested: function(item) { root.scrollItemIntoView(item) }
          }
```

(`import "screens"` at `ui/Panel.qml:13` already makes the new file visible as a type.)

- [ ] **Step 4: Run the flow tests to verify they pass**

Run: `bash tests/run.sh tst_runs_flow`
Expected: exit 0, 0 failed. This includes the unchanged `test_the_run_view_renders_and_enter_there_does_nothing`.

- [ ] **Step 5: Commit**

```bash
git add ui/Panel.qml tests/ui/tst_runs_flow.qml
git commit -m "feat(panel): mount RunDetailScreen in the run view (5.2)"
```

---

### Task 7: Full verification

**Files:** none changed (fix-forward only if something fails, inside the task that owns the code).

- [ ] **Step 1: Run the whole suite**

Run: `bash tests/run.sh`
Expected: exit 0. pytest passes (architecture layers, duplication guards, icon glyphs, backend), and every `tst_*.qml` prints `Totals: N passed, 0 failed` with no `TypeError`/`ReferenceError`/`non-existent`/`Unable to assign`/`is not a function` lines. Other Panel-based flow tests (board, graph, issues, memories, documents, milestone) instantiate the new screen invisibly. They must stay green too, which shows its bindings tolerate a run store with no selected run.

- [ ] **Step 2: Check the scope fence**

Run: `git diff --stat mon/task-5-1-runsscreen-sidebar-f9e44406...HEAD`
Expected: only these files: `core/domain/runs.js`, `core/stores/RunStore.qml`, `ui/screens/RunDetailScreen.qml`, `ui/Panel.qml`, `tests/core/domain/tst_runs.qml`, `tests/core/stores/tst_run_store.qml`, `tests/ui/screens/tst_run_detail_screen.qml`, `tests/ui/tst_runs_flow.qml`, plus this plan and its spec under `docs/superpowers/`. There must be no change to `ui/Navigator.qml`, `core/backend/`, `README.md` or `docs/architecture.md`.

- [ ] **Step 3: Commit (only if Step 1 required a fix)**

```bash
git add -A
git commit -m "fix: keep the full suite green after 5.2"
```

---

## Notes for the user (raise, do not act on)

- **Tree-shape mismatch (from the spec's open point):** `tests/core/backend/runs/test_runs_snapshot.py` nests `stories[].subtasks[]` keyed by `id`, while `runs.js` (and now `runTree`) reads flat `tree.stories` / `tree.subtasks` keyed by `card_id`. No contract test pins the `am status` tree. If real `am status` output is nested, the detail tree will render empty until this is reconciled. That belongs in a separate card.
- **Choices where the spec left room** (all pinned by tests):
  - `logTail` also tails stderr to `maxLines`, so the pane is always bounded.
  - Attempts without a number are listed as `<phase>.?` and cannot be selected.
  - Clicking a subtask row selects its current attempt.
  - A snapshot that brings a selected run's first attempt opens it.
  - Selecting a different attempt clears the previous text, while Refresh keeps it.
