# 4.4 Docs: run history and titles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `docs/architecture.md` document the `runs-history.py` and `board-titles.py` helper contracts, and make `README.md` describe the Finished chip, its state and age rows, start-time age, **Show older** and its cost, quiet unreachable titles, and the two helpers. A new architecture-tier pytest file checks the doc text against the code.

**Architecture:** Docs only, plus one new test file. Task 1 adds the architecture tests and two architecture.md edits: a `runs-history.py` description inside the `core/backend/runs/` line, and a new one-line `board-titles.py` paragraph just before that line. Task 2 adds the README tests and four README.md edits: three in the Runs bullet (line 154) and one in the helper sentence (line 235). Each edit is an exact string replacement that was dry-run against the current tree while this plan was written: every new test failed before the edits and all 164 `tests/architecture` tests passed after them.

**Tech Stack:** Markdown; Python 3 + pytest (architecture tier). The machine's `python3` may have no pytest, so run pytest through `uv run --with pytest python3 -m pytest ...`, which is what `tests/run.sh` falls back to. Full gate: `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/4-4-docs-run-history-8acf6a60.md` (reproduced in full below). Parent design: `docs/superpowers/specs/2026-10-05-run-history-titles-design.md`. Where the parent and the code differ (the parent's global `--all-projects` keyset and `cursor` field), the code wins and the parent is not quoted.

## Global Constraints

- Touch only `docs/architecture.md`, `README.md` and the new `tests/architecture/test_run_history_docs.py`. No code, QML, helper or store change.
- State only what the code does, as plain present-tense facts: no narrative, no history, no "new"/"now".
- README.md contains none of `RunStore`, `RunControlStore`, `RunAlertsStore`, `RunDispatchStore`, `RunTitlesStore`, `RunHistoryStore`, `app.runs`, `app.runControl`, `app.runAlerts`, `app.runDispatch`, `app.runTitles`, `app.runHistory`, `shim`. README prose says "the run history" / "the run titles" or describes behaviour; it never names a store.
- Do not edit the architecture.md store bullets (`RunStore.qml` line 83, `RunTitlesStore.qml` line 94, `RunHistoryStore.qml` line 95, and line 92) or the screen paragraph (line 168).
- The `board-titles.py` contract is one unwrapped line, as the `core/backend/runs/` line 199 is.
- The snapshot's "first 10 terminal ones" wording in line 199 stays.
- `docs/architecture.md` style: backticked identifiers, ` -- ` dashes, no em dashes in body prose.
- Docstrings and comments in the new test state the contract only.
- Paste the replacement text exactly as given; it was checked against `core/backend/runs/runs-history.py:1-33,90-104`, `core/backend/boards/board-titles.py:1-31`, `core/domain/runs.js:660-664,700-769` and `ui/screens/RunsScreen.qml:20-33,640-680`.
- Never run `git stash` bare; the stash stack is shared with other worktrees.
- Verification: `bash tests/run.sh` is green.

## Review Focus

1. A reader must not think **Finished** includes parked (`stopped`) runs: it is done, escalated or cancelled only (`runs.js:700-707`). Task 2's `test_readme_finished_chip_is_done_escalated_or_cancelled` pins the chip's parenthetical to exactly `done, escalated or cancelled`.
2. A reader must not think age is measured from an end time: am records none. Task 2's `test_readme_says_age_is_the_start_time` requires every Runs-bullet sentence naming `started_at` to also say `no end time`.
3. A reader must not think an unreachable board is retried on its own: it is asked again only on **Refresh titles**, the next panel opening or a registry change. Task 2's `test_readme_says_unreachable_titles_are_quiet` requires `not asked again until **Refresh titles**` in the `titles unavailable` sentence.
4. A reader of architecture.md must not be told history pages across all projects with a `cursor` field or am-side `--all-projects` paging, as the parent design says: the code pages one project at a time. Task 1's `test_backend_paragraph_describes_no_global_history_keyset` rejects `--all-projects` and `cursor` in the `runs-history.py` description.
5. The "All three use only documented `am` commands" sentence must not undercount once a fifth helper is described in that line. Task 1's `test_backend_paragraph_counts_the_helpers_it_covers` requires `All five use only documented `am` commands` and rejects `All three use`.

---

## Spec (verbatim)

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

---

## File Structure

- Create `tests/architecture/test_run_history_docs.py`: the doc-against-code checks for this card. It reuses `ROOT` from `test_run_store_callers` and `bullet()` from `test_run_store_docs`, the same way `test_run_store_docs.py` imports from `test_run_store_callers`. pytest puts `tests/architecture/` on `sys.path` because the directory has no `__init__.py`.
- Modify `docs/architecture.md`: insert one line before line 199 (`board-titles.py`), and extend line 199 (`runs-history.py` plus the helper count).
- Modify `README.md`: line 154 (the Runs bullet, three in-place replacements) and line 235 (the helper sentence). Line 8 stays as it is (Task 2, Step 7 checks it).

## Background for the engineer

- Both docs use very long single-line paragraphs. Line 199 of `docs/architecture.md` is about 4,400 characters, and line 154 of `README.md` is a similar single line. Use your editor's exact-string replace (the `Edit` tool) with the `old_string` given in each step. Each `old_string` occurs exactly once in its file. Do not reflow or wrap any line.
- `…` in `Loading older runs…` is the single Unicode character U+2026, not three dots. `×` in `7×24` is U+00D7.
- Run pytest from the worktree root. `python3 -m pytest` may fail with `No module named pytest`; use `uv run --with pytest python3 -m pytest` instead.

---

### Task 1: architecture.md documents `runs-history.py` and `board-titles.py`

**Files:**
- Create: `tests/architecture/test_run_history_docs.py`
- Modify: `docs/architecture.md:198-199` (insert one line before 199, extend 199)

**Interfaces:**
- Consumes: `ROOT` (a `pathlib.Path` to the repo root) from `tests/architecture/test_run_store_callers.py`; `bullet(name, text=None) -> (int first_line_1_based, str bullet_text)` from `tests/architecture/test_run_store_docs.py`.
- Produces: in `tests/architecture/test_run_history_docs.py`, the module constants `DOC`, `README`, `HISTORY`, `TITLES` and the helpers `constant(path, name) -> str`, `runs_paragraph() -> str`, `history_part() -> str`. Task 2 adds `runs_bullet()`, `sentences()` and README tests to this same file.

- [ ] **Step 1: Write the failing tests**

Create `tests/architecture/test_run_history_docs.py` with exactly this content:

```python
"""docs/architecture.md documents runs-history.py and board-titles.py.

The `core/backend/runs/` paragraph describes `runs-history.py`'s argv, its am calls, its page limit and its
output, and counts the helpers it covers. A line outside the `RunTitlesStore.qml` bullet states
`board-titles.py`'s contract.
"""
import re

from test_run_store_callers import ROOT
from test_run_store_docs import bullet

DOC = ROOT / "docs" / "architecture.md"
README = ROOT / "README.md"
HISTORY = ROOT / "core" / "backend" / "runs" / "runs-history.py"
TITLES = ROOT / "core" / "backend" / "boards" / "board-titles.py"


def constant(path, name):
    """The integer a helper assigns to `name` at module level."""
    m = re.search(rf"^{name} = (\d+)$", path.read_text(), re.M)
    assert m, f"{path.name} assigns no {name}"
    return m.group(1)


def runs_paragraph():
    """The architecture.md line that starts with `core/backend/runs/`."""
    lines = [line for line in DOC.read_text().splitlines() if line.startswith("`core/backend/runs/`")]
    assert len(lines) == 1, f"{len(lines)} `core/backend/runs/` paragraphs, want 1"
    return lines[0]


def history_part():
    """The runs paragraph from its first `runs-history.py` on."""
    text = runs_paragraph()
    at = text.find("runs-history.py")
    assert at != -1, "the `core/backend/runs/` paragraph names no runs-history.py"
    return text[at:]


def test_backend_paragraph_documents_runs_history():
    part = history_part()
    missing = [token for token in ["--before", "--status", "`more`", "am status"] if token not in part]
    if not re.search(r"--since(?![\w-])", part):
        missing.append("--since")
    assert missing == []


def test_backend_paragraph_states_the_history_limit_and_default():
    part = history_part()
    for name in ["DEFAULT_LIMIT", "MAX_LIMIT"]:
        value = constant(HISTORY, name)
        assert re.search(rf"\b{value}\b", part), f"no {name} ({value}) in the runs-history.py description"


def test_backend_paragraph_counts_the_helpers_it_covers():
    text = runs_paragraph()
    assert "All three use" not in text
    assert "All five use only documented `am` commands" in text


def test_backend_paragraph_describes_no_global_history_keyset():
    part = history_part()
    assert "--all-projects" not in part and "cursor" not in part


def test_architecture_documents_board_titles_contract():
    first, store = bullet("RunTitlesStore.qml")
    span = range(first, first + len(store.splitlines()))
    seconds = constant(TITLES, "TIMEOUT_SECONDS")
    tokens = ["board-titles.py", "brd tree", "RootMissing", "BrdMissing", "BrdBadOutput", f"{seconds} s"]
    hits = [n for n, line in enumerate(DOC.read_text().splitlines(), 1)
            if n not in span and all(token in line for token in tokens)]
    assert len(hits) == 1, hits
```

Notes on the design (do not paste these into the file):
- `--since(?![\w-])` keeps `runs-watch.py`'s `--since-seq` from counting as `--since`.
- `history_part()` starts at the first `runs-history.py`, which the edit places after the `runs-logs.py` sentence, so the earlier snapshot text (`first 10 terminal ones`, `am status`, `--all-projects`, `cursor`) is not in it.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_history_docs.py -q`
Expected: `5 failed`. The four `test_backend_paragraph_*` tests fail on `the `core/backend/runs/` paragraph names no runs-history.py` (or on `All three use`), and `test_architecture_documents_board_titles_contract` fails on `assert len(hits) == 1` with `hits == []`.

- [ ] **Step 3: Add the `board-titles.py` line**

In `docs/architecture.md`, replace this `old_string` (the end of line 198 plus the start of line 199):

```
dialog states before the run starts.
`core/backend/runs/` is the run-monitor backend.
```

with this `new_string` (a new single line between them; do not wrap it):

```
dialog states before the run starts.
`core/backend/boards/board-titles.py ROOT` reads one project's card titles; `RunTitlesStore` is its one caller. ROOT is non-empty and does not start with `-`, else `Usage` (exit 2), and is an existing directory, else `RootMissing`; in both cases brd is not run. It runs `brd tree` once, as an argv list, with cwd ROOT, stdin `/dev/null` and a 30 s bound; it never writes and never reads brd's database. It prints exactly one JSON line on every path: `{ok: true, titles: {<card id>: <title>}}` for every card at any depth (descriptions are not carried), or brd's own `ok: false` envelope unchanged, or an error: `Usage`, `RootMissing`, `BrdMissing`, `HelperError` (including `brd tree` timing out) or `BrdBadOutput`. Exit 0 ok, 1 failure, 2 usage.
`core/backend/runs/` is the run-monitor backend.
```

- [ ] **Step 4: Add the `runs-history.py` description and fix the helper count**

In `docs/architecture.md` (now line 200, the `core/backend/runs/` line), replace this `old_string`:

```
a 60 s timeout, exactly one JSON line. All three use only documented `am` commands,
```

with this `new_string` (one line; do not wrap it):

```
a 60 s timeout, exactly one JSON line. `runs-history.py ROOT --before ISO [--limit K] [--status S,...] [--since ISO]` is one page of a project's older runs, newest first: ROOT is the one positional (non-empty, not starting with `-`), each option is given at most once as the flag then its value, `--before` is required, `--before` and `--since` are ISO-8601 times (one without an offset is UTC), K defaults to 10 and is taken as 25 when larger, and the default status set is `done`, `escalated`, `stopped`, `cancelled` and `canceled`; any other argv is `Usage` (exit 2) and am is not run. It runs `am runs --repo-dir ROOT` once, with no `--limit` and no `--before`, and every listed row needs a readable `started_at` (else `AmBadOutput`). It keeps, in am's newest-first order, the rows whose status is in the set, started strictly before `--before` and, with `--since`, not before `--since`; the page is the first K kept rows, and `more` is true exactly when more than K rows were kept. Then it runs `am status <id>` once per paged row, in order, never with `--repo-dir`; each am call gets 60 s, so one page costs one `am runs` plus one `am status` per run on the page (at most K). It prints exactly one JSON line on every path: `{ok: true, runs: [{...am runs row, status: <am status data>}], more}`, or an error: `Usage`, `AmMissing`, `AmBadOutput`, `SchemaMismatch` or `HelperError`; am's own `ok: false` envelope is re-emitted unchanged. A failure stops at the failing am call, so a list is never partial, and it writes nothing. All five use only documented `am` commands,
```

The rest of that line ("as argv lists, and never read am's SQLite database or its on-disk layout; am finds its journals under its own data dir, so the `XDG_DATA_HOME` it inherits matters.") stays as it is. The snapshot's "first 10 terminal ones" text earlier on the line stays as it is.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass (`5` new tests plus every existing architecture test, including `test_run_store_docs.py`'s one-bullet-per-store, `SHIM_RE` and moved-member checks), `0 failed`.

- [ ] **Step 6: Check nothing else in architecture.md moved**

Run: `git diff --stat docs/architecture.md` — Expected: `1 file changed, 2 insertions(+), 1 deletion(-)`.
Run: `grep -c 'first 10 terminal ones' docs/architecture.md` — Expected: `1`.
Run: `git diff docs/architecture.md | grep '^+' | grep -c '—'` — Expected: `0` (no em dashes added).

- [ ] **Step 7: Commit**

```bash
git add tests/architecture/test_run_history_docs.py docs/architecture.md
git commit -m "docs(architecture): the runs-history.py and board-titles.py helper contracts"
```

---

### Task 2: README.md describes the run history, quiet titles and both helpers

**Files:**
- Modify: `tests/architecture/test_run_history_docs.py` (docstring, plus new helpers and tests appended)
- Modify: `README.md:154` (three replacements in the Runs bullet), `README.md:235` (helper sentence)

**Interfaces:**
- Consumes: `README` (a `pathlib.Path` to `README.md`) from Task 1's module constants in `tests/architecture/test_run_history_docs.py`.
- Produces: `runs_bullet() -> str` (README's one line starting `- **Runs**`) and `sentences(text) -> list[str]` in the same file. Nothing later depends on them.

- [ ] **Step 1: Write the failing tests**

In `tests/architecture/test_run_history_docs.py`, replace the module docstring:

```python
"""docs/architecture.md documents runs-history.py and board-titles.py.

The `core/backend/runs/` paragraph describes `runs-history.py`'s argv, its am calls, its page limit and its
output, and counts the helpers it covers. A line outside the `RunTitlesStore.qml` bullet states
`board-titles.py`'s contract.
"""
```

with:

```python
"""docs/architecture.md documents runs-history.py and board-titles.py; README.md's Runs bullet describes the
run history and the run titles.

The `core/backend/runs/` paragraph describes `runs-history.py`'s argv, its am calls, its page limit and its
output, and counts the helpers it covers. A line outside the `RunTitlesStore.qml` bullet states
`board-titles.py`'s contract. README.md's Runs bullet names the Finished chip and its state and age rows,
says age is the start time, describes Show older, and says an unreachable board is quiet until asked again;
README.md names both helpers.
"""
```

Then append to the end of the file:

```python


def runs_bullet():
    """README.md's line that starts with `- **Runs**`."""
    lines = [line for line in README.read_text().splitlines() if line.startswith("- **Runs**")]
    assert len(lines) == 1, f"{len(lines)} README Runs bullets, want 1"
    return lines[0]


def sentences(text):
    """`text` split after each `.`, `!` or `?` that whitespace and a capital, `*` or backtick follow."""
    return re.split(r"(?<=[.!?])\s+(?=[A-Z*`])", text)


def test_readme_runs_bullet_names_the_finished_chip_and_rows():
    line = runs_bullet()
    missing = [token for token in ["**Finished**", "All finished", "Done", "Escalated", "Cancelled",
                                   "Today", "7 days", "All time"] if token not in line]
    assert missing == []


def test_readme_finished_chip_is_done_escalated_or_cancelled():
    m = re.search(r"\*\*Finished\*\* \(([^)]*)\)", runs_bullet())
    assert m and m.group(1) == "done, escalated or cancelled"


def test_readme_says_age_is_the_start_time():
    said = [s for s in sentences(runs_bullet()) if "started_at" in s]
    assert said and all("no end time" in s for s in said), said


def test_readme_describes_show_older():
    line = runs_bullet()
    missing = [token for token in ["**Show older**", "Loading older runs…", "am status"] if token not in line]
    assert missing == []


def test_readme_says_unreachable_titles_are_quiet():
    line = runs_bullet()
    assert "**Refresh titles**" in line
    said = [s for s in sentences(line) if "titles unavailable" in s]
    assert len(said) == 1, said
    assert "toast" in said[0] and "not asked again until **Refresh titles**" in said[0], said[0]


def test_readme_names_the_history_and_titles_helpers():
    text = README.read_text()
    assert "runs/runs-history.py" in text and "boards/board-titles.py" in text
```

(The `…` in `"Loading older runs…"` is U+2026.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture/test_run_history_docs.py -q`
Expected: `6 failed, 5 passed`. The six `test_readme_*` tests fail (`test_readme_says_age_is_the_start_time` with `said == []`; `test_readme_says_unreachable_titles_are_quiet` on `"toast" in said[0]`); Task 1's five pass.

- [ ] **Step 3: README Runs bullet: chips, state and age rows, start-time age**

In `README.md` (line 154), replace this `old_string`:

```
**Live** (running), **Parked** and **All** chips carry their counts within the chosen project, clicking the active one shows All again, and the search box matches a run's id, title, current phase and state.
```

with this `new_string` (one line; do not wrap):

```
**Live** (running), **Parked**, **Finished** (done, escalated or cancelled) and **All** chips carry their counts within the chosen project, clicking the active one shows All again, and the search box matches a run's id, title, current phase and state. Under **Finished** a state row offers **All finished**, **Done**, **Escalated** and **Cancelled**, and under **Finished** and **All** an age row offers **Today** (since local midnight), **7 days** (the last 7×24 hours) and **All time** (the default); neither row hides a run that is not finished, and closing the panel sets them back to All finished and All time. A run's age is its start time (`started_at`), since `am` records no end time; the age a row shows is likewise time since the start, except a dead run's, which is time since its last heartbeat.
```

- [ ] **Step 4: README Runs bullet: Show older and its cost**

In `README.md` (line 154), replace this `old_string`:

```
plus its 10 newest terminal ones, and runs of a repository `brd` has not registered never appear.
```

with this `new_string` (one line; do not wrap):

```
plus its 10 newest terminal ones, and runs of a repository `brd` has not registered never appear. After each project's runs a **Show older** button fetches that project's next older page of up to 10 runs matching the current chips (never under **Live**); it shows while `am` is present and, for that project, its page is loading, failed or said there are more, or, with no page yet, its list holds 10 terminal runs. It reads `Loading older runs…` while the page is in flight; a failed page's reason shows under it in the urgent colour, the button stays clickable and the runs already loaded stay. Older runs are fetched only on that click, one `am runs` for the project plus one `am status` per run on the page, and never raise a toast; the loaded pages are dropped when the panel closes or when the statuses the chips ask for, or the age, change, and are kept when the project chip changes.
```

- [ ] **Step 5: README Runs bullet: unreachable titles are quiet**

In `README.md` (line 154), replace this `old_string`:

```
says `titles unavailable`, dimmed, in its header, and its runs keep their ids.
```

with this `new_string`:

```
says `titles unavailable`, dimmed, in its header, and its runs keep their ids; nothing else says so (no toast, banner or error text), and that board is not asked again until **Refresh titles**, the next opening of the panel, or a change to the registered projects.
```

- [ ] **Step 6: README helper sentence (line 235)**

In `README.md`, replace this `old_string`:

```
(`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`), and never reads am's SQLite database.
```

with this `new_string` (one line; do not wrap):

```
(`runs/runs-snapshot-all.py`, `runs/runs-watch.py`, `runs/runs-logs.py`, and `runs/runs-history.py` for the older runs **Show older** fetches), and never reads am's SQLite database. For run titles it runs `brd tree`, read-only, in each other registered project's folder that has runs, through `boards/board-titles.py`.
```

- [ ] **Step 7: Check line 8 stays true and unchanged**

Run: `sed -n 8,10p README.md`
Expected: the summary still reads "… the **Runs** the `am` orchestrator makes on every registered project (watched, and paused, resumed, cancelled or started from the panel). Cards and issues are read-only; the plugin's writes are limited to …". Both helpers only read (`runs-history.py` "writes nothing", `board-titles.py` "never writes"), so the write list stays true: leave lines 8–10 untouched.
Run: `git diff -U0 README.md | grep '^@@'` — Expected: exactly two hunks, `@@ -154 +154 @@` and `@@ -235 +235 @@`.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `timeout 300 uv run --with pytest python3 -m pytest tests/architecture -q`
Expected: all pass, `0 failed` (11 tests in `test_run_history_docs.py`, plus `test_run_store_docs.py::test_the_readme_names_no_run_store`, which proves README.md names no store and no `shim`).

- [ ] **Step 9: Run the full gate**

Run: `timeout 600 bash tests/run.sh`
Expected: exit 0. pytest reports `0 failed`, and no QML test prints `FAIL`. This card touches no QML, so if a QML test fails, check whether it also fails on the base commit (`git worktree add /tmp/base-4-4 HEAD~2 && (cd /tmp/base-4-4 && timeout 600 bash tests/run.sh <that test's path substring>); git worktree remove --force /tmp/base-4-4`) and report it rather than editing QML.

- [ ] **Step 10: Commit**

```bash
git add tests/architecture/test_run_history_docs.py README.md
git commit -m "docs(readme): the Finished chip and its rows, Show older, quiet titles and the history and titles helpers"
```

---

## Self-review (done while writing)

- **Spec coverage:** A (argv, am calls, `more`, 60 s, output/errors, cost, helper count, "first 10" kept) → Task 1 Step 4. B (`board-titles.py` contract, one unwrapped line, `RunTitlesStore` as caller) → Task 1 Step 3. C (chips with Finished; state/age rows; rows never hide unfinished runs; panel close resets; start-time age and dead-run heartbeat age; Show older visibility, loading text, failure; cost; drop/keep rules; no toasts; quiet unreachable titles and when they are asked again) → Task 2 Steps 3–5. D (line 8 unchanged; line 235 names `runs/runs-history.py` and the `brd tree` / `boards/board-titles.py` sentence) → Task 2 Steps 6–7. Tests 1–8 → Task 1 Step 1 (1–3) and Task 2 Step 1 (4–8). Inherited constraints → Task 1 Step 5 and Task 2 Step 8 run the whole `tests/architecture` directory.
- **Placeholders:** none; every edit gives its exact `old_string` and `new_string`.
- **Type consistency:** `constant`, `runs_paragraph`, `history_part` (Task 1) and `runs_bullet`, `sentences` (Task 2) are each defined once and used with the same signatures; `README` is defined in Task 1 and used in Task 2.
- **Dry run:** both tasks' edits and tests were applied to this tree while planning (all 11 new tests failed before, all 164 `tests/architecture` tests passed after), then reverted.
<!-- task-pipeline: validated -->
