# 4.4.1 Docs: architecture.md and README run-monitor sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every run-monitor sentence in `docs/architecture.md` and `README.md` describe what the code at the branch head does: the all-projects list snapshot, the `--run` run read, nudges, `asOfSeq` / `appliedSeq` / `watchCursor` / `storeId`, starting over, the new helper argv and hello, the scratch-dir contract tests and the agent-manager 0.2.0 requirement.

**Architecture:** Docs only. Exact text replacements, grouped by the part a reviewer can accept or reject on its own: Task 1 the `RunStore.qml` bullet, the alerts sentence and the Refresh model line of `docs/architecture.md` (spec A, B); Task 2 the `core/backend/runs/` paragraph and the Tests section of `docs/architecture.md` (spec C, D); Task 3 the four README spots (spec E); Task 4 the whole-repo gate and the spec's stale-claim scan. Each task's "failing test" is a `grep` that finds the stale phrases before the edit and none after it, plus a `grep` that finds the new facts only after it.

**Tech Stack:** Markdown. Verification: `grep` and `bash tests/run.sh` (pytest including `tests/architecture` and `tests/contract`, then every QML test under `qmltestrunner`).

**Spec:** `docs/superpowers/specs/4-4-1-docs-architecture-9a37973d.md` (reproduced in full at the end of this plan). Parent design: `docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` (untracked local file).

## Global Constraints

- Files changed: `docs/architecture.md` and `README.md` only. No code, test, fixture, comment or docstring changes.
- State only what the code does, not what the parent spec promised. Where the code and the parent differ, the docs follow the code.
- Do not document as built: a persisted watch cursor, `--since-seq` resume by the store, `am events` use, `runs-events.py`, `RunAlertsStore`, Global Runs, the events timeline, the persisted alert cursor, `start-run.py` run-id discovery.
- Every replacement text below was checked against the code at `4d1bc1a`: `core/backend/runs/runs-snapshot.py:1-33,44-51,180-191`, `core/backend/runs/runs-watch.py:1-30,44-51,92-106,202-216`, `core/stores/RunStore.qml:6-31,55-69,186-460,597-830,1500-1600`, `ui/screens/RunsScreen.qml:139-157`, `core/domain/runs.js:388-398`, `tests/contract/test_am_shapes.py:1-12,243-337`, `tests/contract/test_am_fixtures.py:1-17,396-470` and every `_note` in `tests/fixtures/am/`. Paste the replacement text exactly; if a cited line no longer says what the text claims, the code wins: correct the sentence and say so in the commit message.
- `docs/architecture.md` conventions: long single-line paragraphs in the `RunStore.qml` bullet and the run-monitor paragraphs; hard-wrapped (~80 columns) lines in the Tests section. `README.md`: one long line per bullet and per paragraph in the touched spots.
- ASCII hyphens and ` -- ` dashes; no em dashes in new text. The `·` middle dot in footer strings is the UI's own text and stays.
- Never use `pkill`/`killall`/pattern kills; stop a stuck command with `timeout`.

## Review Focus

1. A user on an older am (no `as_of_seq` in `am runs`) reads the README: they must be told the Runs screen shows an error line saying the plugin needs the newer am, not a schema banner (the list snapshot fails, so no watch ever starts). Pinned by Task 3 Step 4's grep for `the plugin needs the newer am` in README and Task 1 Step 4's grep for `starts no watch` in architecture.
2. A reader assumes the watch resumes from where it stopped: the docs must say `watchCursor` is memory only and never passed back, and that the watch starts with no `--since-seq`. Pinned by Task 1 Step 4's grep for `never passed back to the helper` and `no --since-seq`.
3. A reader expects the footer always to show a version: the README must say the version and schema show once the watch's hello is known (`ui/screens/RunsScreen.qml:150-155` prints `am · watching` before that). Pinned by Task 3 Step 4's grep for `once the watch's hello is known`.
4. A reader of the backend paragraph concludes `runs-snapshot.py <project_root>` was removed, or that `RunStore` uses it: the docs must say it exists and `RunStore` does not use it. Pinned by Task 2 Step 4's grep for `RunStore` does not use it.
5. A contributor fears the live contract check touches their real am data: the docs must say it runs in a scratch dir, never the user's data dir, and is skipped only when am is absent. Pinned by Task 2 Step 4's grep for `never the user's data dir` and Task 3 Step 4's grep for `in a scratch data dir`.

---

## File Structure

- Modify: `docs/architecture.md` -- the `RunStore.qml` bullet (lines 83-97), the alerts sentences inside line 100, the Refresh model line (line 180), the `core/backend/runs/` paragraph (line 204), the Tests section (lines 234-260).
- Modify: `README.md` -- the Runs bullet (line 154), the backend paragraph (line 235), the Install `am` paragraph (line 259), the Tests paragraph (line 311).

No test file: no automated test reads either document (`grep -rn 'architecture.md\|README' tests` hits only unrelated document-store tests).

---

### Task 1: `docs/architecture.md` -- the `RunStore.qml` bullet, alerts and Refresh model (spec A, B)

**Files:**
- Modify: `docs/architecture.md:83-97` (the bullet's opening and its `amStatus` line)
- Modify: `docs/architecture.md:100` (two phrases in the alerts sentences)
- Modify: `docs/architecture.md:180` (the Refresh model line)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks read; Task 4 re-runs this task's stale-phrase grep.

- [ ] **Step 1: Write the failing check (stale phrases present)**

Run:

```bash
grep -nF -e 'one snapshot of the selected' -e '{"hello": {"schema": N, "am": V}}' -e 'every good snapshot is compared with the one before it' -e 'poll when the journal has a schema mismatch or is corrupt' docs/architecture.md
```

Expected: 4 matching lines (83, 88, 93, 100). This is the RED state: each match is a claim the code no longer makes.

- [ ] **Step 2: Replace the bullet's opening and `amStatus` line (lines 83-97)**

Use the Edit tool on `docs/architecture.md`. Replace this exact text (lines 83-97; line 97 is one long line):

````text
- `RunStore.qml` the am run monitor's data: one snapshot of the selected
  project's am runs (`runs-snapshot.py`, normalized through `runs.js`), the
  selected run and `amStatus`. While the panel is open it runs `runs-watch.py`
  (250 ms debounce per burst of changes, 10 s liveness re-read while a run is
  running, a `stale` flag 30 s after the last good snapshot, and a 5 s fallback
  poll when the journal has a schema mismatch or is corrupt). It never reaches
  for another store: `App` hands it `project` (the selected project's root
  path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which
  the panel binds to its `opened`). `amSchema` (the journal schema from the
  current watch's hello; `0` = unknown) and `amVersion` (am's version from it;
  `""` = unknown) are set from the watch's `{"hello": {"schema": N, "am": V}}`
  line -- `N` when it is an integer of 1 or more, else `0`; `V` when it is a
  string, else `""` -- and go back to unknown when a watch starts, stops or
  exits.
  `amStatus` is `ok`, `missing` (an `AmMissing` snapshot: `runs` is emptied, so no run marks show), `schema` (the watch ended with `SchemaMismatch`: `watchSchemaError` holds the banner text, which stays up through the polling snapshots) or `error` (any other failed snapshot: the last good `runs` stay), with `lastError` saying why. A watch that ends with `CorruptJournal` sets `watchWarning` (the Runs screen's warning line) and starts the same 5 s poll.
````

with this exact text (six lines: the bullet line, then five two-space-indented continuation lines):

````text
- `RunStore.qml` the am run monitor's data: a list snapshot of every project's am runs (`runs-snapshot.py` with no argument) kept to the rows whose project is the selected one (`project.repo_dir`, else the row's `repo_dir`, compared with a trailing `/` ignored) and normalized through `runs.js`, plus the selected run and `amStatus`. It never reaches for another store: `App` hands it `project` (the selected project's root path, `""` when none), `backendDir` and `active` (App's `panelOpen`, which the panel binds to its `opened`).
  Nudges, never folded into state: while `active`, the first good list snapshot starts `runs-watch.py` with no argument -- no `--since-seq`, so the watch begins at am's default position and the store never resumes from `watchCursor` -- whose `changed` lines say "run X changed at seq N". The store keeps the highest `seq` per run in `nudges` and takes them once per 250 ms debounce window (`debounceTimer`): a nudge for a run `appliedSeq` does not know costs one list snapshot and no run read; otherwise each nudge newer than `appliedSeq[run]` for a run in `runs` costs one run read (`runs-snapshot.py --run RUN` on a `HelperRunner` of its own, `readRunners`; a newer read of the same run supersedes an older one still in flight); any other nudge is ignored. `asOfSeq` is the last good list snapshot's `as_of_seq` (`0` before one); `appliedSeq` (`{runId: seq}`) is the `as_of_seq` of the list snapshot or run read that last covered each run, of every project the list named; `watchCursor` is the watch's last `{"cursor": C}`, held in memory only and never passed back to the helper; `storeId` is the last non-empty `store_id` a hello, a list snapshot or a run read named.
  A run read's reply: `UnknownRunError` launches one list snapshot; `StoreBusyError` sets `stale` and keeps the nudge for the next window; any other failure changes nothing; a reply naming another store starts over (below). A good reply for a run still in `runs` that no newer snapshot covers rebuilds that run from its remembered `am runs` row and the reply's status, sets `appliedSeq[run]`, leaves `asOfSeq`, `amStatus` and `lastError` alone, and then raises alerts, settles pending controls, refreshes logs and restarts the stale clock as a list snapshot does.
  Starting over: a hello with `cursorReset` true, or a hello or a run read naming a `store_id` other than `storeId`, clears `appliedSeq`, `asOfSeq`, `watchCursor`, `nudges`, the run reads in flight, `runs` and `alertsArmed`, then takes one list snapshot. A list snapshot naming another store first forgets the same live state and is applied as the new store's full snapshot, with no toast. The first `store_id` seen resets nothing, and `storeId` survives a project switch, a watch end and `AmMissing`. A project switch clears `nudges`, `appliedSeq` and `asOfSeq` and drops the run reads in flight.
  `amSchema` (the schema from the current watch's hello; `0` = unknown) and `amVersion` (am's version from it; `""` = unknown) are set from the watch's `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}` line -- `schema` when it is an integer of 1 or more, else `0`; `am` when it is a string, else `""`; `head` is not read -- and go back to unknown when a watch starts, stops or exits. Timers: the 250 ms debounce, a 10 s liveness re-read of the list while a run is running, a `stale` flag 30 s after the last good list snapshot or applied run read, and a 5 s fallback poll after a watch ended with `SchemaMismatch` or `CorruptJournal`.
  `amStatus` is `ok`, `missing` (an `AmMissing` list snapshot: `runs`, `appliedSeq` and `asOfSeq` are emptied, so no run marks show), `schema` (the watch ended with `SchemaMismatch`: `watchSchemaError` holds the banner text, which stays up through the polling snapshots) or `error` (any other failed list snapshot: the last good `runs` stay), with `lastError` saying why. A list snapshot whose reply is `SchemaMismatch` -- an am whose `am runs` has no `as_of_seq` -- is `error`, with `lastError` saying the plugin needs the newer am, and starts no watch: only a good list snapshot starts one. A `StoreBusyError` list snapshot only sets `stale`. A watch that ends with `CorruptJournal` sets `watchWarning` (the Runs screen's warning line) and starts the same 5 s poll.
````

Fact sources: `RunStore.qml:6-27` (header), `:186-192` (`refresh` = no argument), `:247-260` (`startWatch`, argv without `--since-seq`), `:271-295` (`watchLine`; `head` not read), `:299-336` (`recordNudges`, `triggerNudges`), `:338-367` (`resetCursor`, `forgetLive`, `seeStore`), `:415-424` (`projectSwitched`), `:603-700` (`entryProject`, `trimSlashes`, `applySnapshot`), `:704-810` (`readRun`, `readReplied`, `applyRunRead`), `:1564-1600` (timers), `runs-snapshot.py:66-79` (the `SchemaMismatch` message ends "the plugin needs the newer am.").

- [ ] **Step 3: Fix the two alerts phrases (line 100)**

Use the Edit tool on `docs/architecture.md`. Replace the exact text

```text
Alerts (S2 4.4): while `active`, every good snapshot is compared with the one before it through `Runs.newAlerts`
```

with

```text
Alerts (S2 4.4): while `active`, every good list snapshot and every applied run read is compared with the runs before it through `Runs.newAlerts`
```

Then replace the exact text

```text
the first good snapshot after an opening, a project switch or an `AmMissing` reply only arms
```

with

```text
the first good list snapshot after an opening, a project switch, a start-over or an `AmMissing` reply only arms
```

Fact sources: `RunStore.qml:650-675` (a list snapshot compares, then arms), `:795-808` (a run read compares and never arms), `:350-357` (`forgetLive` disarms).

- [ ] **Step 4: Add the nudge cost to the Refresh model line (line 180)**

Use the Edit tool on `docs/architecture.md`. Replace the exact text

```text
Refresh model: no timers while idle. `RunStore`'s watch,
```

with

```text
Refresh model: no timers while idle. A watch nudge costs one run read of that run (`runs-snapshot.py --run RUN`), or one list snapshot for a run the store does not know -- never a re-read per event. `RunStore`'s watch,
```

- [ ] **Step 5: Run the checks to verify they pass**

Run the stale check (expect no output, exit 1):

```bash
grep -nF -e 'one snapshot of the selected' -e '{"hello": {"schema": N, "am": V}}' -e 'every good snapshot is compared with the one before it' -e 'poll when the journal has a schema mismatch or is corrupt' docs/architecture.md
```

Expected: no output.

Run the new-fact check (Review Focus 1 and 2 included):

```bash
for p in 'runs-snapshot.py --run RUN' 'never passed back to the helper' 'no `--since-seq`' 'starts no watch' 'a start-over or an `AmMissing` reply only arms' 'never a re-read per event' '`storeId` survives a project switch'; do grep -qF -- "$p" docs/architecture.md && echo "ok: $p" || echo "MISSING: $p"; done
```

Expected: seven `ok:` lines, no `MISSING:`.

- [ ] **Step 6: Run the architecture rules**

Run: `timeout 300 python3 -m pytest tests/architecture -q`
Expected: all pass (the docs change touches nothing they read; this proves it).

- [ ] **Step 7: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): describe RunStore's list snapshot, run reads, nudges and start-over"
```

---

### Task 2: `docs/architecture.md` -- the `core/backend/runs/` paragraph and the Tests section (spec C, D)

**Files:**
- Modify: `docs/architecture.md:204` (the whole `core/backend/runs/` paragraph, one line)
- Modify: `docs/architecture.md:234-260` (the `test_am_shapes.py` and `test_am_fixtures.py` sentences, the fixtures bullet)

**Interfaces:**
- Consumes: nothing from Task 1 (different paragraphs).
- Produces: nothing other tasks read; Task 4 re-runs this task's stale-phrase grep.

- [ ] **Step 1: Write the failing check (stale phrases present)**

Run:

```bash
grep -nF -e 'scoped to the open project' -e '<project_root> [run_id' -e 'accepts a hello line of journal schema 1 or 2' -e 'before it started' -e 'hand-written schema 1' -e 'in the main checkout' -e "\`RunStore\`'s snapshot, logs and watch handling" docs/architecture.md
```

Expected: matches on lines 204 (four phrases on one line), 234, 249 and 259 -- 4 lines. RED.

- [ ] **Step 2: Replace the `core/backend/runs/` paragraph (line 204)**

Use the Edit tool on `docs/architecture.md`. The old text is the whole of line 204, which begins `` `core/backend/runs/` is the run-monitor backend, scoped to the open project. `` and ends `` so the `XDG_DATA_HOME` it inherits matters. ``. Replace this exact text:

````text
`core/backend/runs/` is the run-monitor backend, scoped to the open project. `runs-snapshot.py <project_root>` runs `am runs --repo-dir R`, then `am status <id> --repo-dir R` for every non-terminal run and the latest 10 terminal ones (terminal: `done`, `escalated`, `stopped`, `cancelled` or `canceled`), and prints one JSON line (`{ok, runs, data_dir}` or an error; nothing in the UI shows `data_dir`). `runs-watch.py <project_root> [run_id ...]` is long-lived: it runs `am watch --all --follow`, accepts a hello line of journal schema 1 or 2 (anything else is `SchemaMismatch`) and prints the first one as `{"hello": {"schema": N, "am": "<version>"}}` (`""` when am's version is not a string), drops journal lines written before it started (an S4 workaround until `am watch --from-now` exists), keeps the watched runs plus any run whose `run_upsert` names this project root, prints at most one debounced `{"changed": [...]}` line per 250 ms, and ends with an `AmMissing`, `SchemaMismatch`, `CorruptJournal` or `HelperError` envelope (exit 0 when it was stopped). `RunStore` runs it as a plain `Process`, not through `HelperRunner`. `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. All three use only documented `am` commands, as argv lists, and never read am's SQLite database or its on-disk layout; am finds its journals under its own data dir, so the `XDG_DATA_HOME` it inherits matters.
````

with this exact text (one line):

````text
`core/backend/runs/` is the run-monitor backend. `runs-snapshot.py` has three modes: no argument runs `am runs --all-projects --limit 200` (every project's runs; the mode `RunStore` uses), `<project_root>` runs `am runs --repo-dir R --limit 200` (one project; `RunStore` does not use it), and `--run RUN` runs `am status RUN` alone, never with `--repo-dir`; any other argv is a `Usage` error (exit 2) and am is not run. The list modes then run `am status <id>` for every non-terminal run and the first 10 terminal ones (terminal: `done`, `escalated`, `stopped`, `cancelled` or `canceled`) in am's newest-first order. It prints exactly one JSON line on every path: `{ok, as_of_seq, store_id, runs: [{...am runs row, status: <am status data>}], data_dir}`, or for `--run` `{ok, run, as_of_seq, store_id, status, data_dir}` (`store_id` is `""` when am's is not a string; nothing in the UI shows `data_dir`), or an error: `Usage`, `AmMissing`, `AmBadOutput`, `SchemaMismatch` (am data without a non-negative integer `as_of_seq`: "the plugin needs the newer am") or `HelperError`; am's own `ok: false` envelope (`StoreBusyError`, `UnknownRunError`, `RepoDirError`, ...) is re-emitted unchanged. A failure stops at the failing am call, so a list is never partial; each am call gets 60 s. `runs-watch.py [--since-seq N]` (N one or more ASCII digits; any other argv is `Usage`, exit 2) is long-lived: it runs `am watch --all-projects --follow` (plus `--since-seq N` when given) and prints the first hello as `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}` (`am` and `storeId` are `""` when not strings, `cursorReset` is true only for a JSON true); every hello must carry an integer `schema` of 1 or more and a non-negative integer `head`, else `SchemaMismatch` (`am watch sent no head; the plugin needs the newer am.` for a missing `head`). A nudge is a line whose `event` is one of its `EVENTS` (`run_upsert`, `story_upsert`, `subtask_upsert`, `phase_upsert`, `attempt_upsert`, `lease_acquired`, `lease_taken_over`, `control_requested`, `control_handled`, `claim_conflict`), with a non-empty `run_id` and an integer `gseq` of 1 or more; every other line is ignored, and event contents are never forwarded. It prints at most one `{"changed": [{"run", "seq"}, ...]}` per 250 ms window, never empty, one entry per run carrying its highest `gseq` in the window, followed directly by `{"cursor": C}` (the highest `gseq` since the helper started). It ends with an `{ok: false, error}` line and exit 1 -- `SchemaMismatch`, `CorruptJournal` (am exited 3, unless its refusal is a `StoreBusyError`), `HelperError`, `AmMissing`, or am's own refusal envelope re-emitted unchanged -- and with exit 0 when am exits 0, on SIGINT or SIGTERM, or when its stdout closes. `RunStore` runs it as a plain `Process`, not through `HelperRunner`. `runs-logs.py <project_root> RUN CARD PHASE ATTEMPT` is a one-shot `am logs RUN CARD --phase P --attempt N --repo-dir R` passthrough: a 60 s timeout, exactly one JSON line. All three use only documented `am` commands, as argv lists, and never read am's SQLite database or its on-disk layout; am finds its journals under its own data dir, so the `XDG_DATA_HOME` it inherits matters.
````

Fact sources: `runs-snapshot.py:1-33,44-51,66-79,180-191`; `runs-watch.py:1-30,44-51,78-106,202-216`; `RunStore.qml:250-258` (plain `Process`).

- [ ] **Step 3: Replace the `test_am_shapes.py` opening (lines 234-238)**

Use the Edit tool on `docs/architecture.md`. Replace this exact text:

```text
  `test_am_shapes.py` does the same for the installed `am`: hand-written schema 1
  journals under a throwaway `XDG_DATA_HOME`, pinning the `am runs`, `am status`
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses,
  with the `--follow` hello's schema accepted as 1 or 2; skipped when `am` is
  absent. Its story tests (S7) build a real git repo and brd board under tmp
```

with:

```text
  `test_am_shapes.py` does the same for the installed `am`: am runs
  hermetically (its own `HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME` under tmp),
  events are seeded only through am commands (a real story run on a scratch
  board, which escalates at its first agent phase because no agent CLI is
  reachable), and it pins the `am runs`, `am status` and `am watch` (one-shot
  and `--follow`) shapes `core/backend/runs/*` parses: the schema 2 journal
  line and hello key sets, `gseq`, `head`, `cursor_reset` and `store_id`, with
  the `--follow` hello's schema accepted as 1 or 2; skipped when `am` is absent.
  Its story tests (S7) build a real git repo and brd board under tmp
```

The story-test sentences that follow (lines 239-245, from `and run am with a \`PATH\` holding only am, brd and git` to `needs an am with \`--story\`.`) stay unchanged: they match `test_am_shapes.py:151-240`.

- [ ] **Step 4: Replace the `test_am_fixtures.py` sentences (lines 246-253)**

Use the Edit tool on `docs/architecture.md`. Replace this exact text:

```text
  `test_am_fixtures.py` pins the committed captures in
  `tests/fixtures/am/`: each level's exact key set, the run and attempt status
  vocabularies, and no top-level `subtasks` in `am status` data. Its live check
  runs `am runs` and `am status <newest>` in the main checkout (the parent of
  git's common dir), read-only with only `--repo-dir`, and expects the same key
  sets, with `story_id` allowed as the one extra key on a runs row and on the
  status run; it is skipped when `am` or `git` is absent, `am runs` fails or
  the checkout has no runs.
```

with:

```text
  `test_am_fixtures.py` pins the committed captures in
  `tests/fixtures/am/`: each level's exact key set (keys starting with `_`
  ignored), the run and attempt status vocabularies, no top-level `subtasks` in
  `am status` data, a `_note` on every capture naming agent-manager 0.2.0, one
  `store_id` shared by the captures, strictly increasing `gseq`, and an events
  page's `head` at least its last `gseq`. Its live check runs the `am` first on
  `PATH` with `HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME` under a scratch dir,
  never the user's data dir: it requires `as_of_seq` in `am runs` data and
  `head` in the first line of `am watch --all --follow`, failing with "the
  plugin needs the newer am" when either is missing, and checks any rows and
  the newest row's `am status` against the capture key sets exactly; it is
  skipped only when `am` is absent.
```

Fact source: `test_am_fixtures.py:1-17,396-470`. Do not add that the live check runs the helpers' argv: it uses `--repo-dir` and `--all`, the helpers `--all-projects`.

- [ ] **Step 5: Update the fixtures bullet (lines 254-260)**

Use the Edit tool on `docs/architecture.md`. Replace this exact text:

```text
- `tests/fixtures/am/` holds real captured am payloads: `runs.json`, five
  `status-*.json`, `watch-events.json`, `watch-hello.json`,
  `logs-attempt.json` and `events.json` (an `am events RUN` page with `head`);
  keys starting with `_` are annotations readers ignore.
  Tests of code that reads am output (`normalizeRun`, `logTail`, the `runs-*`
  helpers, `run-control.py`, `RunStore`'s snapshot, logs and watch handling)
  build their input from these fixtures;
```

with:

```text
- `tests/fixtures/am/` holds real captured am payloads, captured 2026-10-08
  from agent-manager 0.2.0 on a scratch store, as each `_note` says:
  `runs.json`, five `status-*.json`, `watch-events.json`, `watch-hello.json`
  (`schema_1` the historical capture, `schema_2` the current one),
  `logs-attempt.json` and `events.json` (an `am events RUN` page with `head`);
  keys starting with `_` are annotations readers ignore.
  Tests of code that reads am output (`normalizeRun`, `logTail`, the `runs-*`
  helpers, `run-control.py`, `RunStore`'s list snapshot, run read, logs and
  watch handling) build their input from these fixtures;
```

- [ ] **Step 6: Run the checks to verify they pass**

Stale check (expect no output):

```bash
grep -nF -e 'scoped to the open project' -e '<project_root> [run_id' -e 'accepts a hello line of journal schema 1 or 2' -e 'before it started' -e 'hand-written schema 1' -e 'in the main checkout' -e "\`RunStore\`'s snapshot, logs and watch handling" docs/architecture.md
```

Expected: no output.

New-fact check (Review Focus 4 and 5 included):

```bash
for p in 'am runs --all-projects --limit 200' '`RunStore` does not use it' 'runs-watch.py [--since-seq N]' 'am watch --all-projects --follow' 'claim_conflict' "never the user's data dir" 'skipped only when `am` is absent' 'captured 2026-10-08' 'run read, logs and'; do grep -qF -- "$p" docs/architecture.md && echo "ok: $p" || echo "MISSING: $p"; done
```

Expected: nine `ok:` lines, no `MISSING:`.

- [ ] **Step 7: Run the architecture rules**

Run: `timeout 300 python3 -m pytest tests/architecture -q`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add docs/architecture.md
git commit -m "docs(architecture): describe the all-projects run helpers and the scratch-dir am contract tests"
```

---

### Task 3: `README.md` -- Runs bullet, backend paragraph, Install and Tests (spec E)

**Files:**
- Modify: `README.md:154` (two phrases of the Runs bullet)
- Modify: `README.md:235` (the watch command)
- Modify: `README.md:259` (the am requirement)
- Modify: `README.md:311` (the am contract tests)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing other tasks read; Task 4 re-runs this task's stale-phrase grep.

- [ ] **Step 1: Write the failing check (stale phrases present)**

Run:

```bash
grep -nF -e 'journal schema 1' -e 'schema 1 · watching' -e 'hand-written schema 1' -e 'on the open project only (`am runs --repo-dir <project>`)' -e '`am watch --all --follow` and `am logs`' README.md
```

Expected: matches on lines 154, 235, 259 and 311. RED.

- [ ] **Step 2: Fix the Runs bullet (line 154)**

Use the Edit tool on `README.md`. Replace the exact text

```text
the runs the `am` orchestrator has made on the open project only (`am runs --repo-dir <project>`), which the plugin watches
```

with

```text
the runs the `am` orchestrator has made on the open project: the plugin reads every project's runs (`am runs --all-projects`) and lists the open project's, which it watches
```

Then replace the exact text

```text
The footer reads `am · schema 1 · watching` (or `not watching`).
```

with

```text
The footer reads `am <version> · schema <N> · watching` (or `not watching`), the version and schema shown once the watch's hello is known.
```

Leave `Nothing polls while the panel is closed.` as it is. Fact sources: `RunStore.qml:186-192,631-650`; `ui/screens/RunsScreen.qml:139-157`.

- [ ] **Step 3: Fix the backend paragraph (line 235)**

Use the Edit tool on `README.md`. Replace the exact text

```text
(`am runs`, `am status`, `am watch --all --follow` and `am logs`)
```

with

```text
(`am runs`, `am status`, `am watch --all-projects --follow` and `am logs`)
```

- [ ] **Step 4: Fix the Install am requirement (line 259)**

Use the Edit tool on `README.md`. Replace the exact text

```text
`am` must speak journal schema 1; otherwise the Runs screen shows a schema-mismatch banner and the runs are polled every 5 s instead of watched.
```

with

```text
The run monitor needs an `am` whose `am runs` and `am status` carry `as_of_seq` and whose watch hello carries `head` (agent-manager 0.2.0). With an older `am` the list snapshot fails and the Runs screen shows an error line saying the plugin needs the newer am; a watch whose hello lacks `head` shows a schema-mismatch banner and the runs are polled every 5 s instead of watched.
```

The corrupt-journal, stale and `--story` sentences after it stay. Fact sources: `runs-snapshot.py:66-79`; `RunStore.qml:676-700` (`error`, no watch after a failed snapshot), `:381-393` (watch `SchemaMismatch` -> banner + poll); `runs-watch.py:100-102`; `RunsScreen.qml:150-153` (footer shows `lastError` while `error`).

- [ ] **Step 5: Fix the Tests paragraph (line 311)**

Use the Edit tool on `README.md`. Replace this exact line:

```text
`tests/contract/test_am_shapes.py` does the same for `am`: hand-written schema 1 journals under a throwaway `XDG_DATA_HOME` pin the `am runs`, `am status` and `am watch` shapes the run helpers parse; it is skipped when `am` is not installed, and its story tests fail, rather than skip, when the installed `am` has no `am run --story`, or when brd or git is missing.
```

with:

```text
`tests/contract/test_am_shapes.py` does the same for `am`: with its own `HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME`, it seeds a real story run through `am` commands alone and pins the `am runs`, `am status` and `am watch` shapes the run helpers parse; it is skipped when `am` is not installed, and its story tests fail, rather than skip, when the installed `am` has no `am run --story`, or when brd or git is missing. `tests/contract/test_am_fixtures.py` pins the committed `am` captures in `tests/fixtures/am/` and checks the installed `am`, in a scratch data dir, against them; it fails when that `am` lacks `as_of_seq` in `am runs` or `head` in its watch hello.
```

- [ ] **Step 6: Run the checks to verify they pass**

Stale check (expect no output):

```bash
grep -nF -e 'journal schema 1' -e 'schema 1 · watching' -e 'hand-written schema 1' -e 'on the open project only (`am runs --repo-dir <project>`)' -e '`am watch --all --follow` and `am logs`' README.md
```

Expected: no output.

New-fact check (Review Focus 1, 3 and 5 included):

```bash
for p in '`am runs --all-projects`' "once the watch's hello is known" '`am watch --all-projects --follow`' 'the plugin needs the newer am' '(agent-manager 0.2.0)' 'in a scratch data dir' 'Nothing polls while the panel is closed.'; do grep -qF -- "$p" README.md && echo "ok: $p" || echo "MISSING: $p"; done
```

Expected: seven `ok:` lines, no `MISSING:`.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs(readme): describe the all-projects run monitor and the agent-manager 0.2.0 requirement"
```

---

### Task 4: Whole-repo gate and the spec's stale-claim scan

**Files:**
- None modified (verification only; if a check fails, fix the sentence in the file the failing check names and commit that fix).

**Interfaces:**
- Consumes: the edited `docs/architecture.md` (Tasks 1-2) and `README.md` (Task 3).
- Produces: the card's verification evidence.

- [ ] **Step 1: Run the spec's stale-claim scan over both files**

```bash
grep -nF -e 'journal schema 1' -e 'schema 1 · watching' -e 'hand-written schema 1' -e 'before it started' -e '<project_root> [run_id' -e 'accepts a hello line of journal schema 1 or 2' -e 'one snapshot of the selected' -e 'scoped to the open project' docs/architecture.md README.md
```

Expected: no output (exit 1).

- [ ] **Step 2: Check no parent-only future item slipped in, and no em dash was added**

```bash
grep -nF -e 'runs-events.py' -e 'RunAlertsStore' -e 'am events --' -e 'persisted cursor' -e 'Global Runs' docs/architecture.md README.md
git diff 4d1bc1a -- docs/architecture.md README.md | grep '^+' | grep -n '—'
```

Expected: no output from either command. (A `—` on a `+` line would be an em dash in new text; the pre-existing ones in untouched lines do not show in the diff.)

- [ ] **Step 3: Check only the two docs changed**

Run: `git diff --stat 4d1bc1a HEAD -- . ':!docs/superpowers'` (`4d1bc1a` is this card's base commit; the branch is stacked on earlier milestone work, so do not diff against `main`)
Expected: only `README.md` and `docs/architecture.md` listed.

- [ ] **Step 4: Run the full suite**

Run: `timeout 1200 bash tests/run.sh`
Expected: exit 0; pytest (including `tests/architecture` and `tests/contract`) and every QML test pass. A docs-only change must leave it green; a failure here is pre-existing or environmental -- report it with its output, do not edit code.

- [ ] **Step 5: Fact-check every changed sentence against the code**

Open `git diff 4d1bc1a -- docs/architecture.md README.md` beside `core/backend/runs/runs-snapshot.py`, `core/backend/runs/runs-watch.py`, `core/stores/RunStore.qml`, `ui/screens/RunsScreen.qml`, `tests/contract/test_am_fixtures.py` and `tests/contract/test_am_shapes.py`, and confirm each changed sentence against the "Fact sources" lines in Tasks 1-3. Any sentence the code contradicts: correct it, rerun Steps 1-2, and commit:

```bash
git add docs/architecture.md README.md
git commit -m "docs: correct run-monitor sentences the code contradicts"
```

(Skip the commit when nothing needed correcting.)

---

## Self-review against the spec

- A.1-A.11: Task 1 Step 2 (data source, nudges, members, run read, starting over, hello, watch start, project switch, timers, `amStatus` incl. snapshot `SchemaMismatch` / `StoreBusyError` / `AmMissing`), Step 3 (alerts, A.11). B: Task 1 Step 4. C: Task 2 Step 2 (snapshot modes, outputs, errors; watch argv, hello, nudge rule, `EVENTS`, changed+cursor, endings, plain `Process`; logs unchanged; closing rule kept; removals). D: Task 2 Steps 3-5. E: Task 3 Steps 2-5. Tests section of the spec: Task 4 Steps 1, 4, 5.
- Corrections versus the spec, from the code: the project filter also accepts a row's top-level `repo_dir` when `project` is not an object (`RunStore.qml:603-608`); `CorruptJournal` from the watch excludes a `StoreBusyError` refusal (`runs-watch.py:202-211`); the stale clock also restarts on an applied run read (`RunStore.qml:804-806`).
- No placeholders; every replacement is exact text.

---

## The spec (reproduced in full)

# 4.4.1 Docs: architecture.md and README run-monitor sections -- design

Card `9a37973d` (story `5a0d5e67`, milestone 4). Parent design:
`docs/superpowers/specs/2026-10-06-am-snapshots-cursors-design.md` (untracked local file, cited
below as "parent" with its line numbers).

## Problem

Stories 4.0 and 4.1 changed the run-monitor backend, `RunStore`, the am fixtures and the contract
tests, but `docs/architecture.md` and `README.md` still describe the milestone-3 behavior: a
per-project `runs-snapshot.py <project_root>`, a `runs-watch.py <project_root> [run_id ...]`
that filters by project and drops backlog lines, a hello of `{"schema", "am"}` accepted as
schema 1 or 2, a `RunStore` that holds "one snapshot of the selected project's am runs", a footer
reading `am · schema 1 · watching`, an install requirement of "journal schema 1", and
`test_am_shapes.py` using "hand-written schema 1 journals". Every one of those claims is now false.

The parent lists `docs/architecture.md:204` as a file this milestone rewrites (parent line 202)
and makes 4.4.1 the docs card "read from the code" (parent line 266).

## Goal

After this card, every sentence in the run-monitor parts of `docs/architecture.md` and
`README.md` describes what the code at the branch head does. The card's rule: state only what the
code does, not what the parent spec promised. Where the code and the parent differ, the docs follow
the code.

## Scope

Files changed: `docs/architecture.md` and `README.md` only. No code, test or fixture changes.

Out of scope:

- The spec retargets (story 4.2, the docs PR `docs/retarget-specs-new-am`; parent lines 245-249)
  and the 4.3 behavior (Global Runs, the events timeline, the persisted alert cursor, `start-run.py`
  run-id discovery; parent lines 247-249, 262-266). The docs do not mention any of it as built.
- The parent's future items that the code does not have: a persisted watch cursor (parent line
  268: memory only in M4), `--since-seq` resume by the store, `am events` use, `runs-events.py`,
  `RunAlertsStore`. Do not document them.
- Doc paragraphs unrelated to the run monitor, and run-monitor paragraphs the milestone did not
  change (dispatch, controls, logs, toasts' timing) except where a sentence there is now false.
- Other specs and plans under `docs/superpowers/`.

## Inherited constraints

- The plugin reads snapshots and treats watch lines as nudges; it never folds events into state
  (parent lines 45-47, 101-117).
- am calls are argv lists only; no reading of `am.db`, journals or the data-dir layout (parent
  line 58).
- The hello stays at schema 2 with additive `head`, `gseq`, `cursor_reset` and `store_id`; a
  hello without `head` is `SchemaMismatch` "the plugin needs the newer am" (parent lines 92-94,
  224, 273-276).
- Snapshots carry `as_of_seq`; a watch line carries `gseq` (global) and `seq` (per run); a
  snapshot plus the events with `gseq > as_of_seq` is complete with no repeats; unknown events or
  keys are ignored (parent lines 69-81).
- No dead-run detection from events; the lease poll stays (parent lines 61-62).
- `am logs` consumption unchanged (parent line 63).
- The watch cursor is held in memory only in M4 (parent line 268).
- Fixtures are recorded from a throwaway data dir; the live check runs against the dev `am` and a
  scratch data dir (parent lines 213-217).
- Docs conventions already in the files: `docs/architecture.md` uses long single-line prose
  paragraphs in the run-monitor bullets and hard-wrapped lines in the store list; `README.md`
  keeps one long line per bullet; ASCII hyphens and ` -- ` dashes, no em dashes.

## What the docs must say (observable content)

Each item names the place in the current file and the facts that replace the stale text. Every
fact below was read from the code at `4d1bc1a`; the implementer re-reads the cited code before
writing and drops or corrects any fact that no longer holds.

### A. `docs/architecture.md`, the `RunStore.qml` bullet (now lines 83-99)

Replace the opening ("one snapshot of the selected project's am runs") and the hello sentence
with:

1. Data source: a list snapshot of every project's runs (`runs-snapshot.py` with no argument),
   kept to the rows whose `project.repo_dir` equals the selected project (a trailing `/` ignored),
   normalized through `runs.js`. `RunStore.qml:6-27`, `applySnapshot` near line 632.
2. Nudges, never folded: while `active`, `runs-watch.py` (no argument) prints `changed` lines;
   the store records the highest `seq` per run in `nudges`, and once per 250 ms debounce window
   a nudge newer than `appliedSeq[run]` costs one run read (`runs-snapshot.py --run RUN`, one
   `HelperRunner` per run, a newer read of the same run supersedes the older) for a run it
   holds, or one list snapshot (and no reads) when any nudged run is absent from `appliedSeq`;
   other nudges are ignored.
3. Members: `asOfSeq` (the last good list snapshot's `as_of_seq`, `0` before one), `appliedSeq`
   (`{runId: seq}`: the `as_of_seq` of the snapshot or run read that last covered each run,
   covering every project the list named), `watchCursor` (the watch's last `{"cursor": C}`,
   memory only, never passed back to the helper), `storeId` (the last non-empty `store_id` seen
   in a hello, a list snapshot or a run read).
4. Run read reply: `UnknownRunError` -> one list snapshot; `StoreBusyError` -> `stale` and the
   nudge is kept for the next window; other failures change nothing; a reply naming another
   store -> start over (item 5); a good reply rebuilds that run from its remembered `am runs` row
   plus the reply's status, sets `appliedSeq[run]`, leaves `asOfSeq`, `amStatus` and `lastError`
   alone, is skipped when `appliedSeq[run]` is already higher, and then raises alerts, settles
   pending controls and refreshes logs as a list snapshot does.
5. Starting over: a hello with `cursorReset` true, or a hello or run read naming a `store_id`
   other than `storeId`, clears `appliedSeq`, `asOfSeq`, the cursor, the nudges, in-flight reads,
   `runs` and `alertsArmed`, then takes one list snapshot. A list snapshot naming another store
   first forgets the same live state and is applied as the new store's full snapshot with no
   toast. The first `store_id` seen resets nothing. `storeId` survives a project switch, a watch
   end and `AmMissing`.
6. Hello: `amSchema` (`schema` when an integer >= 1, else `0`) and `amVersion` (`am` when a
   string, else `""`) from `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}`;
   `head` is not read by the store. Both go back to unknown when a watch starts, stops or exits.
7. Watch start: the watch starts after the first good list snapshot while `active`, with no
   `--since-seq`, so it begins at am's default position; the store does not resume from
   `watchCursor`.
8. Project switch: clears `nudges`, `appliedSeq` and `asOfSeq` and drops in-flight reads; keeps
   `storeId`.
9. Timers unchanged: debounce 250 ms, liveness 10 s while a run is running (re-reads the list,
   not a run), `stale` 30 s after the last good snapshot, 5 s fallback poll after a watch ended
   with `SchemaMismatch` or `CorruptJournal`.
10. `amStatus`: correct the `schema` case to say it comes from a watch that ended with
    `SchemaMismatch`; a snapshot whose reply is `SchemaMismatch` (an am whose `am runs` has no
    `as_of_seq`) sets `error` with `lastError` "...the plugin needs the newer am", and no watch
    starts because none follows a failed snapshot (`RunStore.qml` lines 640-700, 250, 671).
    `StoreBusyError` from a list snapshot marks `stale` only; `AmMissing` empties `runs`,
    `appliedSeq` and `asOfSeq`.
11. Alerts paragraph: "every good snapshot" becomes every good list snapshot and every applied
    run read.

### B. `docs/architecture.md`, the Refresh model line (now line 180)

Keep it; add that a nudge costs a run read of that run, or one list snapshot for a run the store
does not know, never a re-read per event.

### C. `docs/architecture.md`, the `core/backend/runs/` paragraph (now line 204)

Rewrite the whole paragraph. It is no longer "scoped to the open project".

- `runs-snapshot.py` (docstring lines 1-33): no argument = `am runs --all-projects --limit 200`;
  `<project_root>` = `am runs --repo-dir R --limit 200` (exists; `RunStore` does not use it);
  `--run RUN` = `am status RUN` alone, never `--repo-dir`; any other argv = `Usage`, exit 2, am
  not run. List modes then run `am status <id>` for every non-terminal run and the first 10
  terminal ones (`done`, `escalated`, `stopped`, `cancelled`, `canceled`) in am's newest-first
  order. One JSON line on every path: `{ok, as_of_seq, store_id, runs: [{...row, status}],
  data_dir}`, or for `--run` `{ok, run, as_of_seq, store_id, status, data_dir}`; `store_id` is
  `""` when am's is not a string. Errors: `Usage`, `AmMissing`, `AmBadOutput`, `SchemaMismatch`
  (am data without a non-negative integer `as_of_seq`: "the plugin needs the newer am"),
  `HelperError`; am's own `ok: false` envelope (`StoreBusyError`, `UnknownRunError`,
  `RepoDirError`) is re-emitted unchanged; a failure stops at the failing call, never a partial
  list; 60 s per am call.
- `runs-watch.py` (docstring lines 1-33): argv `[--since-seq N]` (N ASCII digits), else `Usage`
  exit 2. Spawns `am watch --all-projects --follow [--since-seq N]`. Prints the first hello as
  `{"hello": {"schema", "am", "head", "cursorReset", "storeId"}}`; every hello needs an integer
  `schema` >= 1 and a non-negative integer `head`, else `SchemaMismatch` ("am watch sent no head;
  the plugin needs the newer am."). A nudge is a line whose `event` is one of the helper's
  `EVENTS` (list them as the code does), with a non-empty `run_id` and an integer `gseq` >= 1;
  everything else is ignored and event contents are never forwarded. At most one
  `{"changed": [{"run", "seq"}, ...]}` per 250 ms window, never empty, one entry per run carrying
  its highest `gseq` in the window, followed directly by `{"cursor": C}` (the highest `gseq`
  since the helper started). Ends with `{ok: false, error}` and exit 1 (`SchemaMismatch`,
  `CorruptJournal` when am exits 3, `HelperError`, `AmMissing`, or am's refusal envelope
  re-emitted unchanged); am exit 0, SIGINT, SIGTERM or a closed stdout is exit 0. `RunStore`
  runs it as a plain `Process`, not through `HelperRunner`.
- `runs-logs.py`: unchanged sentence.
- Keep the closing rule: only documented am commands, argv lists, never am's SQLite database or
  on-disk layout; the inherited `XDG_DATA_HOME` matters.
- Remove: the project-root argument of the watch, run-id argv, the project-root filter, the
  schema "1 or 2" allowlist, the "drops journal lines written before it started" workaround.

### D. `docs/architecture.md`, the testing section (now lines 228-262)

- `test_am_shapes.py`: replace "hand-written schema 1 journals" with what the file does: am
  runs hermetically (own `HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`), events are seeded only
  through am commands (a real story run on a scratch board that escalates at its first agent
  phase), and it pins the `am runs`, `am status` and `am watch` (one-shot and `--follow`, with
  the schema 2 line and hello key sets, `gseq`, `head`, `cursor_reset`, `store_id`) shapes. Keep
  the story-test sentences, re-checked against the file. Do not claim a hello schema rule the
  test does not assert (it accepts 1 or 2).
- `test_am_fixtures.py`: replace the live-check sentence (it no longer runs in the main checkout,
  is no longer read-only against the user's data, no longer allows `story_id` as an extra key,
  and no longer skips on "no runs"). Say: the fixture contract (exact key set per level, `_` keys
  ignored, the vocabularies, no top-level `subtasks`, every capture's `_note` names
  agent-manager 0.2.0, one shared `store_id`, strictly increasing `gseq`, an events page's
  `head` at least its last `gseq`); the live check runs the `am` first on `PATH` with `HOME`,
  `XDG_DATA_HOME` and `XDG_STATE_HOME` under a scratch dir, never the user's data dir, requires
  `as_of_seq` in `am runs` data and `head` in the first line of `am watch --all --follow`
  (failing with "the plugin needs the newer am" when either is missing), checks any rows and the
  newest row's `am status` against the capture key sets exactly, and is skipped only when am is
  absent. Do not say it runs the helpers' exact argv (it uses `--repo-dir` and `--all`, the
  helpers `--all-projects`).
- `tests/fixtures/am/`: keep the file list (`runs.json`, five `status-*.json`,
  `watch-events.json`, `watch-hello.json` with `schema_1` historical and `schema_2` current,
  `logs-attempt.json`, `events.json`); add that they were captured 2026-10-08 from agent-manager
  0.2.0 on a scratch store, as each `_note` says. Update "`RunStore`'s snapshot, logs and watch
  handling" to include the run read.

### E. `README.md`

- Line 154 (Runs bullet): the runs listed are the open project's rows of a snapshot of every
  project (`am runs --all-projects`), not `am runs --repo-dir <project>`. Footer: `am <version> ·
  schema <N> · watching` (or `not watching`), the version and schema shown once the watch's
  hello is known (`ui/screens/RunsScreen.qml:139-157`); drop `schema 1`. Keep "Nothing polls
  while the panel is closed."
- Line 235: the am commands are `am runs`, `am status`, `am watch --all-projects --follow` and
  `am logs`.
- Line 259 (Install): replace "must speak journal schema 1" with: the run monitor needs an am
  whose `am runs` and `am status` carry `as_of_seq` and whose watch hello carries `head`
  (agent-manager 0.2.0). With an older am the list snapshot fails and the Runs screen shows the
  error line saying the plugin needs the newer am; a watch whose hello lacks `head` shows the
  schema-mismatch banner and falls back to the 5 s poll. Keep the corrupt-journal, stale and
  `--story` sentences.
- Line 311: `test_am_shapes.py` description as in D (no "hand-written schema 1 journals"), and
  one sentence for `test_am_fixtures.py` (fixture contract plus the scratch-dir live check that
  fails when am lacks `as_of_seq` or `head`).

## Errors

The deliverable is prose, so its failure modes are claims that are wrong:

| case | handling |
|---|---|
| a sentence describes the parent's intent, not the code (e.g. persisted cursor, `--since-seq` resume) | removed; the docs follow the code |
| a fact above no longer matches the code at implementation time | the code wins; the implementer corrects the fact |
| an old-am failure described as the schema banner | stated per path, as in A.10 and E line 259 |

## Tests

No automated test reads `docs/architecture.md` or `README.md` (`grep -rn 'architecture.md\|README'
tests` hits only unrelated document-store tests), and prose has no behavior to unit-test, so this
card adds no test. Verification:

1. **Full suite** -- tier: whole repo (`bash tests/run.sh`), because the card's gate requires it
   and it includes `tests/architecture` (layering, duplication, icon glyph rules); a docs-only
   change must leave it green.
2. **Stale-claim scan** -- tier: manual check in the plan's last task, because it is a one-off
   textual check, not a regression the suite should carry. These must have no match in either
   file: `journal schema 1`, `schema 1 · watching`, `hand-written schema 1`, `before it started`,
   `<project_root> [run_id`, `accepts a hello line of journal schema 1 or 2`,
   `one snapshot of the selected`, `scoped to the open project`.
3. **Fact check against code** -- tier: manual review, because only a reader comparing the text
   with `runs-snapshot.py`, `runs-watch.py`, `RunStore.qml`, `RunsScreen.qml`,
   `test_am_fixtures.py` and `test_am_shapes.py` can confirm each claim; the reviewer checks every
   sentence changed against the cited lines.
<!-- task-pipeline: validated -->
