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
