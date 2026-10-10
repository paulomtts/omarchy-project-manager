# 4.4 Docs: run history and titles — design

Card `8acf6a60` (subtask of story `5e9efb63`). Parent design:
`docs/superpowers/specs/2026-10-05-run-history-titles-design.md` (cited below as
**parent**, by section and line).

## Problem

The run-history and run-title work is built (cards 4.1–4.3 and earlier). Most of
`docs/architecture.md` already describes it, but three things the code does are not
written down anywhere a reader looks:

1. `docs/architecture.md`'s `core/backend/runs/` paragraph (line 199) documents
   `runs-snapshot.py`, `runs-snapshot-all.py`, `runs-watch.py` and `runs-logs.py`, and
   ends "All three use only documented `am` commands"; it never describes
   `runs-history.py`.
2. `core/backend/boards/board-titles.py` appears only inside the `RunTitlesStore.qml`
   bullet (line 94) as a command name; its contract (argv, `brd tree` with cwd ROOT, the
   30 s bound, the output and error types) is written nowhere in the docs.
3. `README.md` describes none of the history UI: its Runs bullet (line 154) lists the chips
   as "**Needs attention** …, **Live** …, **Parked** and **All**", says nothing of the
   Finished chip, its state and age rows, **Show older** / `Loading older runs…`, that age
   is the run's start time, or what a history page costs; it says an unreachable board
   shows `titles unavailable` but not that this is quiet and when it is retried. Its
   summary (line 8) and its helper sentence (line 235, "For the run monitor it runs only
   `am` … through the helpers in `core/backend/runs/` (`runs/runs-snapshot-all.py`,
   `runs/runs-watch.py`, `runs/runs-logs.py`)") omit `runs-history.py` and
   `board-titles.py`, and so omit that the plugin runs `brd tree` in other projects'
   folders.

Note: the parent design's helper (parent, "History → Data", lines 119–135:
`am runs --all-projects --limit K --before RUN`, a `cursor` field, a global keyset) is
**not** what was built. The code pages one project at a time over a time cursor. The docs
must state what the code does (card: "State only what the code does"); where the parent
and the code differ, the code wins and the parent is not quoted.

## Goal

After this card a reader of `docs/architecture.md` and `README.md` can learn, without
reading code, every observable behaviour below, each stated as a plain present-tense fact
with no narrative, no history and no "new"/"now".

## Behaviour the docs must state

### A. `docs/architecture.md`, `core/backend/runs/` paragraph (line 199)

Add a `runs-history.py` description, after `runs-logs.py`'s, matching its docstring
(`core/backend/runs/runs-history.py:1-33`) and `history()` (`:90-104`):

- Argv: `runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]`;
  ROOT is the one positional (non-empty, not starting with `-`); each option at most once,
  as flag then value; `--before` required; times are ISO-8601 (no offset means UTC); K
  defaults to 10 and is taken as 25 when larger; the default status set is `done`,
  `escalated`, `stopped`, `cancelled`, `canceled`. Any other argv is `Usage` (exit 2) and
  am is not run.
- It runs `am runs --repo-dir ROOT` once, with no `--limit` and no `--before`; every row
  needs a readable `started_at` (else `AmBadOutput`); it keeps, in am's newest-first
  order, the rows whose status is in the set, started strictly before `--before` and, with
  `--since`, not before `--since`; the page is the first K kept rows; `more` is true
  exactly when more than K rows were kept. Then `am status <id>` once per paged row, in
  order, never with `--repo-dir`. Each am call gets 60 s.
- Output: one JSON line on every path, `{ok: true, runs: [{...am runs row, status: <am
  status data>}], more}`, or an error `Usage`, `AmMissing`, `AmBadOutput`,
  `SchemaMismatch` or `HelperError`; am's own `ok: false` envelope re-emitted unchanged. A
  failure stops at the failing am call; a list is never partial; nothing is written.
- Cost: one page is one `am runs` plus one `am status` per run on the page (at most K).
- The closing sentence "All three use only documented `am` commands …" names the count of
  helpers it covers correctly (it covers `runs-history.py` too).
- The snapshot's "first 10 terminal ones" wording stays: it is accurate for
  `runs-snapshot*.py` (`common/am_runs.py` `TERMINAL_LIMIT`).

### B. `docs/architecture.md`, `board-titles.py`

Add one paragraph or sentence, in the backend helper prose (the `core/backend/<domain>/`
paragraphs around lines 186–199, beside the boards helpers), matching
`core/backend/boards/board-titles.py:1-20` and `TIMEOUT_SECONDS = 30` (`:31`):

- `boards/board-titles.py ROOT`: ROOT non-empty and not starting with `-`, else `Usage`
  (exit 2) and brd is not run; ROOT must be an existing directory, else `RootMissing` and
  brd is not run.
- Runs `brd tree` once, as an argv list, with cwd ROOT, stdin `/dev/null`, a 30 s bound;
  never writes; never reads brd's database.
- One JSON line on every path: `{ok: true, titles: {<card id>: <title>}}` for every card at
  any depth (descriptions are not carried), or brd's own `ok: false` envelope unchanged,
  or an error `Usage`, `RootMissing`, `BrdMissing`, `HelperError` (including the timeout)
  or `BrdBadOutput`. Exit 0 ok, 1 failure, 2 usage.
- The `board-titles.py` contract is written as one unwrapped line (as line 199 is), so the
  line-based test 3 can match it.
- `RunTitlesStore` is its one caller (cross-reference only; the store bullet is not
  rewritten).

### C. `README.md`, Runs bullet (line 154)

Edit in place; keep every existing true sentence. The bullet must state:

- The chips are **Needs attention**, **Live**, **Parked**, **Finished** and **All**, each
  with its count within the chosen project; **Finished** is done, escalated or cancelled
  runs (parent, "Filters", line 139).
- Under **Finished** a state row: **All finished**, **Done**, **Escalated**, **Cancelled**.
  Under **Finished** and **All** an age row: **Today** (since local midnight), **7 days**
  (the last 7×24 h), **All time** (the default). Neither row hides a run that is not
  finished (`core/domain/runs.js:742-752`). The panel closing resets both rows to All
  finished / All time (architecture.md line 83).
- Age is the run's start time (`started_at`): am records no end time (parent, "Filters",
  lines 143–145; `runs.js:725-733`). The age shown on a row is also time since start,
  except a dead run's, which is since its last heartbeat (`runs.js:662-664`).
- The "each project lists its non-terminal runs plus its 10 newest terminal ones" sentence
  stays, and is followed by: after each project's runs a **Show older** button fetches that
  project's next older page of up to 10 runs matching the current chips (never under
  **Live**); it shows while `am` is present and, for the project, its page is loading, failed or
  said there are more, or, with no page yet, its list holds 10 terminal runs; it reads `Loading older runs…` while the page is in flight, and a failed
  page's reason shows under it in the urgent colour with the button still clickable and
  the loaded runs kept (`ui/screens/RunsScreen.qml:20-33,640-680`).
- Cost: history is fetched only on that click, one `am runs` for the project plus one
  `am status` per run on the page; loaded pages are dropped when the panel closes or when the status list the
  chip/state implies, or the age, changes, and kept across a project-filter change (architecture.md
  line 95). History runs raise no toasts.
- An unreachable board: the project's runs show their ids, its header says
  `titles unavailable`, dimmed, and nothing else — no toast, banner or error text; the
  board is not asked again until **Refresh titles**, the next opening of the panel, or a
  change to the registered projects (architecture.md line 94).

### D. `README.md`, line 8 and line 235

- Line 8 (summary of what the plugin writes/reads): unchanged unless it states something
  false; it may not claim the plugin writes anything new.
- Line 235: the run-monitor helper list names `runs/runs-history.py` (and `am runs
  --repo-dir R` / `am status` are already named), and a sentence states that for run titles
  it runs `brd tree` in each other registered project's folder with runs through
  `boards/board-titles.py`, read-only.

### Constraints (inherited, must stay green)

- `tests/architecture/test_run_store_docs.py:23,152`: README.md contains none of
  `RunStore`, `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`, `RunTitlesStore`,
  `RunHistoryStore`, `app.runs`, `app.runControl`, `app.runAlerts`, `app.runDispatch`,
  `app.runTitles`, `app.runHistory`, `shim`. README prose says "the run history" / "the run
  titles", never a store name.
- Same file: exactly one top-level bullet per run store in architecture.md, in order, each
  naming every App input; no `SHIM_RE` hit; no `RunStore.<moved member>`. The store
  bullets (lines 83, 92, 94, 95) are not edited.
- `tests/architecture/test_layers.py`, `test_icon_glyphs.py` are unaffected (docs are not
  scanned) and must stay green.
- Card: docstrings/comments in the new test state the contract only.

## Tests

One new pytest file, `tests/architecture/test_run_history_docs.py`. Tier: architecture
(pytest, in `bash tests/run.sh`'s first step) — the existing tier for asserting doc text
against code (`test_run_store_docs.py` is its sibling); docs have no runtime behaviour, so
no unit, QML or UI tier applies. Written first; each must fail on the current tree except
where marked.

1. `test_backend_paragraph_documents_runs_history` — the architecture.md paragraph that
   starts with `` `core/backend/runs/` `` contains `runs-history.py`, `--before`,
   `--since`, `--status`, `more`, and `am status` after `runs-history.py`. Fails today.
2. `test_backend_paragraph_states_the_history_limit_and_default` — that paragraph, in its
   `runs-history.py` part, states `10` and `25` (the default and the cap), read from
   `DEFAULT_LIMIT` / `MAX_LIMIT` in `runs-history.py` so the test follows the code. Fails
   today.
3. `test_architecture_documents_board_titles_contract` — architecture.md has a line outside
   the `RunTitlesStore.qml` bullet naming `board-titles.py` that also names `brd tree`,
   `RootMissing`, `BrdMissing`, `BrdBadOutput` and the timeout in seconds read from
   `TIMEOUT_SECONDS` in `board-titles.py`. Fails today.
4. `test_readme_runs_bullet_names_the_finished_chip_and_rows` — the README line starting
   `- **Runs**` contains `**Finished**`, `All finished`, `Done`, `Escalated`, `Cancelled`,
   `Today`, `7 days`, `All time`. Fails today.
5. `test_readme_says_age_is_the_start_time` — that line contains `started_at`. Fails today.
6. `test_readme_describes_show_older` — that line contains `**Show older**` and
   `Loading older runs…` and `am status`. Fails today.
7. `test_readme_says_unreachable_titles_are_quiet` — that line contains
   `titles unavailable` and `**Refresh titles**` and the word `toast` in the same sentence
   as `titles unavailable`. Fails today (no `toast` in that sentence).
8. `test_readme_names_the_history_and_titles_helpers` — README.md contains
   `runs/runs-history.py` and `boards/board-titles.py`. Fails today.

The existing `test_the_readme_names_no_run_store` already guards the README token rule; no
duplicate is written.

## Errors / edge cases the docs must not get wrong

- Do not describe a global (all-projects) history keyset, a `cursor` field, or am-side
  `--before` / `--limit` for history: the code has none (parent lines 119–135 differ from
  code).
- Do not say Finished includes `stopped`/parked runs: it does not (`runs.js:700-707`); a
  parked run's history is fetched under **Parked** or **All** (`historyStatuses`,
  `runs.js:760-769`).
- Do not say age uses an end time.
- Do not say an unreachable board is retried automatically.

## Out of scope

- Any code, QML, helper or store change; the store bullets in architecture.md (lines 83,
  92, 94, 95) and the screen paragraph (line 168), which already describe the stores,
  their App wiring, the title cache and its invalidation, the chips and Show older.
- Rewriting the parent design spec to match the code.
- Sibling cards' deliverables (4.1–4.3: the helpers, stores and UI themselves).
