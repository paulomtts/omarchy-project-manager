# 2.4 Docs: dispatch at every level Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `README.md` and `docs/architecture.md` describe dispatch at all four levels (subtask, story, milestone, board), remove the two stale claims, and document the `am run --story` requirement and the contract test that enforces it.

**Architecture:** Docs only. Six exact text replacements (D1-D6 of the spec): one in the architecture Panel paragraph, one in the architecture Tests section, and four in the README (the Runs bullet, a new Dispatch bullet, the Install `am` paragraph, the Tests paragraph). The "failing test" is a set of grep checks that find the stale phrases before the edit and none after it. The full suite proves nothing else moved.

**Tech Stack:** Markdown. Verification: `bash tests/run.sh` (pytest, then every QML test under `qmltestrunner`, offscreen) and `grep`.

**Spec:** `docs/superpowers/specs/2-4-docs-dispatch-at-4c3d419e.md` (reproduced in full below). Parent design: `docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (S7).

## Global Constraints

- Touch only `README.md` and `docs/architecture.md`. No code, test, comment or docstring changes.
- State only what the code does. Every sentence below was checked against `core/domain/runs.js` (`dispatchPlan` 905, `dispatchLabel` 954, `dispatchDefaults` 1046, `previewSummary` 1169), `core/stores/RunStore.qml`, `ui/components/DispatchDialog.qml`, `ui/Panel.qml:249-338,533-539`, `ui/screens/CardDetailScreen.qml:94-115`, `ui/Shortcuts.qml` and `tests/contract/test_am_shapes.py:1-12,175-300`. Do not reword the replacement text; paste it exactly.
- `docs/architecture.md`: dense one-line paragraphs, backticked identifiers, `S7` tags, ` -- ` dashes. No em dashes in body prose (UI strings such as `Started — opening the run when it appears` stay verbatim).
- `README.md`: short bullets and paragraphs, no S-tags.
- Do not invent an am source URL.
- Do not rewrite `docs/architecture.md:101` (RunStore Dispatch) or `:107-113`.
- Verification: `bash tests/run.sh` is green.

## Review Focus

1. A reader who dispatches a milestone or the board must not be told its Start takes two clicks -- only a subtask's does (`confirmFirst` is bound to a subtask target). The Dispatch bullet in Step 5 says the two clicks only of a subtask; Step 9's grep confirms "two clicks" appears exactly once in README.md.
2. A reader must not expect stories in the Runs toolbar's chip row -- it lists `Whole board` plus each dispatchable milestone (root card). Step 5's text says "each milestone"; Step 9 greps that "Whole board" sits only beside "milestone".
3. A blocked story must not be described as `failed` -- it is refused, nothing saved. Step 5 says "refused"; Step 9 greps that README.md never pairs "blocked" with "failed".
4. A user with an editable `am` install must not be told to reinstall needlessly, and a user with a stale non-editable one must learn how to update it. Step 6's text conditions the reinstall on a non-editable install and names `am run --help`.
5. Someone running the contract tests without `--story` support must learn it fails rather than skips -- both the architecture Tests section (Step 3) and the README Tests paragraph (Step 7) say so; Step 9 greps for "fail, never skip" / "rather than skip".

---

## Spec (verbatim)

# 2.4 Docs: dispatch at every level — design

Card `4c3d419e`, subtask of story `99cd17e4` (Dispatch at story level, S7). Parent spec:
`docs/superpowers/specs/2026-10-05-dispatch-story-level-design.md` (cited below as
"parent", with line numbers).

## Problem

The code dispatches at four levels (parent table, lines 29-34). The docs do not say so
everywhere, and two sentences contradict the code:

1. `docs/architecture.md:176` (Panel owns the dispatch) says the card detail's
   `▶ Dispatch` on "a story or a finished card opens a dialog that says why, and a
   story's offers its milestone". That was S3's behavior. Today `Runs.dispatchPlan`
   (`core/domain/runs.js:905-919`) offers a story with `--story` unless it is
   finished. Only a story that `am` refuses as blocked (`StoryBlockedError`) offers its
   milestone.
2. `README.md:154` (Runs bullet) says the runs are "watched, never controlled: the plugin
   has no pause, resume, cancel or start". The plugin starts runs. It also pauses,
   resumes and cancels them (`docs/architecture.md:100`).
3. The README has no dispatch description. It does not say the installed `am` must
   support `am run --story`, or how to update `am`.
4. Neither doc says that `tests/contract/test_am_shapes.py` fails when the installed
   `am` has no `--story` (parent "Precondition", lines 12-18, and "Testing", lines
   92-96).

This card only changes documentation. It does not change any code, test or comment.

## Inherited constraints

- The four levels and their commands: subtask `am run --card ID`, story
  `am run --story ID`, milestone `am run --milestone ID`, board `am run --board`
  (parent lines 29-34).
- All four use the same dialog: a dry-run preview before Start, except that the
  subtask level shows the card's facts instead. Then the cost warning, the detached
  launcher, and the new run's detail (parent lines 36-38).
- Story entry points: the card detail's Dispatch and `d` on the board list. The
  target reads `Story "<title>" (milestone "<title>")` (parent lines 42-44).
- Prefix default order: the newest snapshot run of the milestone, then the
  per-milestone setting, then the prefix history, then the milestone's stem. The
  same order serves the milestone level (parent lines 49-54).
- A blocked story is refused at preview or at Start. The dialog offers
  **Dispatch the milestone instead** (parent lines 55-61).
- Cards in `done`, `merged`, `canceled` or `archived` are refused at every level
  (parent lines 65-66).
- `am` must have `--story`. The contract test fails, rather than skips, when the
  installed `am` lacks it. `am` is a `uv tool` install, and once installed
  non-editable it is reinstalled after an update (parent lines 3-10, 14-18).
- State only what the code does (card description). Repository docs conventions:
  `docs/architecture.md` uses dense one-line paragraphs per component, backticked
  identifiers, `S3 n.n` / `S7` tags and ` -- ` dashes. The README uses short
  bullets and paragraphs with no S-tags.

## Required behavior (what the docs must say)

### D1. `docs/architecture.md` Panel paragraph (line 176)

Replace the parenthetical on `CardDetailScreen`'s `▶ Dispatch` so it says this:

- `▶ Dispatch` appears on every card.
- A finished card (`done`, `merged`, `canceled`, `archived`) opens a dialog that is
  already `refused`: `The card is <status>`.
- A story opens on its own target (`--story`).
- Only a story that am refuses as blocked offers its milestone, through the dialog's
  `Dispatch the milestone instead` (`dispatchSuggestion`, `RunStore.retargetToMilestone()`).

The phrase "a story's offers its milestone" must disappear. The rest of the paragraph
already matches `ui/Panel.qml:249-338` and stays as it is.

### D2. `docs/architecture.md` am requirement (Tests section, ~line 230-245)

Extend the `test_am_shapes.py` sentence so it covers these points, all checked against
`tests/contract/test_am_shapes.py:1-12,175-300`:

- The story tests build a real git repo and brd board under tmp and run am with a PATH
  that holds only am, brd and git.
- They pin `am run --help` listing `--story`, the `--story --dry-run` payload (one
  level, no integrate), the `StoryBlockedError` refusal at dry run and at a detached
  start, and `story_id` on a story run's `am runs` row.
- When am is present they fail, never skip, if `am run` lacks `--story` or if brd or
  git is absent. The skip-when-am-is-absent rule stays.

Line 101 (RunStore Dispatch) already covers the four levels, the label, the prefix order,
the `StoryBlockedError` retarget, the helper argv and the `prefixByMilestone` save. It is
not rewritten. A short clause there is allowed only if it is needed to point to the am
requirement.

### D3. README Runs bullet (line 154)

- Drop "watched, never controlled: the plugin has no pause, resume, cancel or start".
- Replace it with an accurate clause: the plugin watches the runs and can start them
  (see D4). Naming pause / resume / cancel as present is allowed: `p` / `r` / `c` and
  the Run detail controls exist (`docs/architecture.md:100,107-108`). Describing them in
  detail is out of scope.
- Every other sentence of the bullet stays.

### D4. README dispatch description (Features, inside or right after the Runs bullet)

Add a short bullet or paragraph covering all of the following, in README style:

- **Levels:** a subtask (`am run --card`), a story (`--story`), a milestone
  (`--milestone`) and the whole board (`--board`).
- **Entry points:** a card's `▶ Dispatch` in card detail; a bare `d` on the board
  list's cursor card (search empty) or on the open card; the Runs toolbar's
  `▶ Start run`, which opens on the whole board with a row of `Whole board` plus each
  dispatchable milestone. None of them starts anything. All are disabled while am is
  missing.
- **Dialog:** Base, Prefix, Verify (or `run without any verification`) and Parallel.
  A milestone, a story or the board gets an `am` dry-run preview before Start. A
  subtask has no preview, and its Start takes two clicks. A story preview reads
  `N subtasks · rooted on <branch>`. On success, the panel opens the new run.
- **Refusals:** a finished card is refused with `The card is <status>`. A story whose
  blocker stories are not finished is refused by am, from the preview or from Start,
  and the dialog offers **Dispatch the milestone instead**. Other am refusals are shown
  verbatim.
- **Prefix default, in order:** the branch prefix of the newest run of the target's
  milestone in the Runs list; else the last prefix used for that milestone from the
  panel; else the last prefix used at all; else the milestone title's stem. It is
  editable. The verify commands, parallelism and prefixes are remembered per project
  after a successful start.

Every sentence must be checkable against `core/domain/runs.js` (`dispatchPlan` 905,
`dispatchLabel` 954, `dispatchDefaults` 1046, `previewSummary` 1169),
`core/stores/RunStore.qml`, `ui/components/DispatchDialog.qml`, `ui/Panel.qml` and
`ui/Shortcuts.qml`. Text that cannot be verified there is cut.

### D5. README Install `am` paragraph (line 258)

Add the following, without removing anything:

- To start runs, the installed `am` must support `am run --story`. `am run --help`
  must list it.
- `am` is installed as a `uv` tool. After updating agent-manager, reinstall it from
  its checkout (`uv tool install --reinstall .` run in a clean checkout of
  agent-manager, per parent line 10).
- `tests/contract/test_am_shapes.py` fails when the installed am lacks `--story`.

Do not invent an am source URL. None exists in this repo.

### D6. README Tests section (line 310)

The `test_am_shapes.py` sentence gains: "and its story tests fail, rather than skip,
when the installed `am` has no `am run --story`, or when brd or git is missing".

## Error paths / failure modes the docs must not introduce

- Do not claim the board or the milestone level shows the subtask's two-click Start
  (`confirmFirst` is bound only to a subtask target, `docs/architecture.md:176`).
- Do not claim the Runs `▶ Start run` chip row lists stories. It lists only the board
  and each root card that `dispatchPlan` offers (`ui/Panel.qml:319-330`).
- Do not claim a refused story is `failed`. It is `refused`, with no log fields and
  nothing saved (`docs/architecture.md:101`).
- No em dashes in architecture body prose outside quoted UI strings. UI strings such
  as `Started — opening the run when it appears` stay verbatim.

## Tests

No code changes, so no new unit or QML test is written. No existing test reads
`README.md` or `docs/architecture.md` (`grep -rn "README\|architecture.md" tests` shows
only fixture file names). A docs-text test would pin prose, which the repo does not do.

| Check | Tier | Why |
|---|---|---|
| `bash tests/run.sh` green | full suite (pytest + every QML test) | This is the card's verification command. It shows that nothing outside the docs was touched and that the architecture tests (`tests/architecture/test_layers.py`, `test_icon_glyphs.py`) still pass. |
| `grep -n "a story's offers its milestone" docs/architecture.md` is empty | manual grep in plan step | D1: the stale S3 sentence is gone. |
| `grep -n "no pause, resume, cancel or start" README.md` is empty | manual grep in plan step | D3: the stale README claim is gone. |
| `grep -n -- "--story" README.md` shows hits in Features, Install and Tests | manual grep in plan step | D4, D5 and D6 are present. |
| `git diff --stat` touches only `README.md` and `docs/architecture.md` | manual check in plan step | The scope stays docs-only. |

## Plan hand-off

There is one task: edit both docs (D1-D6), run the grep checks, run `bash tests/run.sh`,
and commit. A docs task has no failing test to write first. The "failing check" step is
the grep checks above: before the edit they find the stale phrases, and after it they do
not.

## Out of scope

- Any change to code, tests, comments or docstrings (`runs.js`, helpers, `RunStore`,
  `DispatchDialog`, `CardDetailScreen`, `Shortcuts`, `Panel`). Sibling cards 1.x-2.3
  own those and have already landed.
- Documenting pause, resume and cancel beyond correcting the README's false
  "no pause, resume, cancel" claim.
- Rewriting `docs/architecture.md:101` or `:107-113`, which are already accurate.
- Making the `am` install non-editable, or changing agent-manager (parent lines 5-10;
  that work belongs to agent-manager's P1).
- Dispatching several stories at once (parent "Open", line 109).

---

## File Structure

| File | Change | Spec item |
|---|---|---|
| `docs/architecture.md:176` | Replace the stale parenthetical on `CardDetailScreen`'s `▶ Dispatch` in the "Panel owns the dispatch" paragraph | D1 |
| `docs/architecture.md:236-238` (Tests section, the `test_am_shapes.py` sentence) | Add the story tests and the fail-not-skip rule | D2 |
| `README.md:154` (Features, **Runs** bullet) | Replace "watched, never controlled: the plugin has no pause, resume, cancel or start" | D3 |
| `README.md`, new bullet right after the **Runs** bullet | Add the **Dispatch** bullet | D4 |
| `README.md:258` (Install, the `am` paragraph) | Append the `--story` requirement and the reinstall note | D5 |
| `README.md:310` (Tests) | Extend the `test_am_shapes.py` sentence | D6 |

Nothing else changes. `docs/architecture.md:101` is already accurate and is not touched.

### How to run the checks

- Full suite: `bash tests/run.sh` (from the worktree root). Green means the pytest summary reports no failures and every QML `Totals:` line reports `0 failed`, and the script exits 0.
- The grep checks are written out in Steps 1 and 9. Run each from the worktree root.

### About "RED" in this plan

A docs task has no failing unit test. Step 1 is the RED step: the grep checks that must come back empty after the edit find the stale phrases now, and the ones that must find the new text find nothing now.

---

### Task 1: Docs for dispatch at every level (D1-D6)

**Files:**
- Modify: `docs/architecture.md:176` (Panel owns the dispatch)
- Modify: `docs/architecture.md:236-238` (Tests, `test_am_shapes.py`)
- Modify: `README.md:154` (Features, Runs bullet) and insert a new bullet after it
- Modify: `README.md:258` (Install, `am` paragraph)
- Modify: `README.md:310` (Tests)

**Interfaces:**
- Consumes: nothing from other tasks. The facts come from the code listed under Global Constraints, which earlier cards (1.x-2.3) already merged.
- Produces: no code interface. Later readers rely on the exact phrases `Dispatch the milestone instead`, `The card is <status>`, `am run --story` and `fail, never skip` / `rather than skip` being present.

- [ ] **Step 1: Run the checks and watch them fail (RED)**

Run:

```bash
grep -n "a story's offers its milestone" docs/architecture.md
grep -n "no pause, resume, cancel or start" README.md
grep -n -- "--story" README.md
grep -n "fail, never skip" docs/architecture.md
```

Expected now:
- the first command prints one hit at line 176;
- the second prints one hit at line 154;
- the third prints nothing;
- the fourth prints nothing.

After Steps 2-7 all four are inverted (see Step 9).

- [ ] **Step 2: D1 -- fix the card detail Dispatch parenthetical in `docs/architecture.md`**

In `docs/architecture.md`, line 176 (the paragraph starting `Panel owns the dispatch (S3 4.2).`), replace exactly this text:

```
`CardDetailScreen`'s `▶ Dispatch` on every card (its `dispatchRequested(cardId)`; a story or a finished card opens a dialog that says why, and a story's offers its milestone),
```

with exactly this text:

```
`CardDetailScreen`'s `▶ Dispatch` on every card (its `dispatchRequested(cardId)`; a finished card -- `done`, `merged`, `canceled` or `archived` -- opens a dialog already `refused` with `The card is <status>`, a story opens on its own target (`--story`, S7), and only a story am refuses as blocked offers its milestone, through the dialog's `Dispatch the milestone instead` (`dispatchSuggestion`, `RunStore.retargetToMilestone()`)),
```

The rest of the line stays as it is. The paragraph must stay one line (no line break added).

- [ ] **Step 3: D2 -- add the story tests to the `test_am_shapes.py` sentence in `docs/architecture.md`**

In `docs/architecture.md`, in the `## Tests` section, replace exactly these three lines:

```
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses,
  with the `--follow` hello's schema accepted as 1 or 2; skipped when `am` is
  absent. `test_am_fixtures.py` pins the committed captures in
```

with exactly these lines:

```
  and `am watch` (one-shot and `--follow`) shapes `core/backend/runs/*` parses,
  with the `--follow` hello's schema accepted as 1 or 2; skipped when `am` is
  absent. Its story tests (S7) build a real git repo and brd board under tmp
  and run am with a `PATH` holding only am, brd and git, so no agent CLI is
  reachable; they pin `am run --help` listing `--story`, the
  `am run --story --dry-run` payload (one level, no integrate), the
  `StoryBlockedError` refusal at dry run and at a detached start (which records
  no run), and `story_id` on a story run's `am runs` row. When am is present
  they fail, never skip, if `am run` lacks `--story` or if brd or git is
  absent: the panel's story dispatch needs an am with `--story`.
  `test_am_fixtures.py` pins the committed captures in
```

Every fact here is in `tests/contract/test_am_shapes.py`: the module docstring (lines 9-11), `require_tool` (`pytest.fail` when a tool is absent), `story_board`, `test_run_help_lists_the_story_option` (`pytest.fail`, not skip), `test_story_dry_run_previews_one_level_with_no_integrate`, `test_blocked_story_is_refused_at_dry_run_with_story_blocked_error`, `test_blocked_story_is_refused_at_a_detached_start_and_nothing_is_recorded` and `test_a_story_run_row_carries_story_id`.

- [ ] **Step 4: D3 -- fix the README Runs bullet**

In `README.md`, line 154 (the bullet starting `- **Runs** (Ctrl+6)`), replace exactly this text:

```
(`am runs --repo-dir <project>`), watched, never controlled: the plugin has no pause, resume, cancel or start.
```

with exactly this text:

```
(`am runs --repo-dir <project>`), which the plugin watches and can start (see **Dispatch** below); a run can also be paused, resumed or cancelled from the panel.
```

Every other sentence of the bullet stays.

- [ ] **Step 5: D4 -- add the README Dispatch bullet**

In `README.md`, insert this new bullet on its own line directly after the **Runs** bullet (line 154) and before the line starting `- **Documents** -`:

```
- **Dispatch** - the panel starts `am` runs at four levels: a subtask (`am run --card`), a story (`--story`), a milestone (`--milestone`) or the whole board (`--board`). Three entry points open the dispatch dialog, and none of them starts anything: a card's **▶ Dispatch** in card detail; a bare `d` on the board list's cursor card (while the search is empty) or on the open card; and the Runs toolbar's **▶ Start run**, which opens on the whole board with a row of `Whole board` plus each milestone that can be dispatched. All three are disabled while `am` is missing. The dialog names the target (a story reads `Story "<title>" (milestone "<title>")`) and has Base, Prefix, Verify (or `run without any verification`) and Parallel. A milestone, a story or the whole board gets an `am` dry-run preview before **Start run**; a story's reads `N subtasks · rooted on <branch>`. A subtask has no preview, and its Start takes two clicks. A done, merged, canceled or archived card is refused with `The card is <status>`. A story whose blocker stories are not finished is refused by `am`, from the preview or from Start, and the dialog offers **Dispatch the milestone instead**; any other `am` refusal is shown verbatim. The prefix defaults to the branch prefix of the newest run of the target's milestone in the Runs list, else the last prefix used for that milestone from the panel, else the last prefix used at all, else a stem of the milestone's title, and it can be edited. After a successful start the panel shows the Runs list and opens the new run once `am` lists it, and it remembers the verify commands, the parallelism and the prefix for the project. Starting runs needs an `am` with `am run --story` (see Install).
```

Facts and their sources (do not add any sentence that is not in this list):
- levels and flags: `runs.js` `dispatchPlan` (905-919);
- entry points, `Whole board` + root-card chips: `Panel.qml` `runsDispatchChoices` (320-330), `CardDetailScreen.qml:99-114`, `Shortcuts.qml` `handleDispatchKey`, `Panel.qml:533-539` (`startRunButton` disabled while `amStatus === "missing"`);
- target label: `runs.js` `dispatchLabel` (954);
- field labels and the opt-out chip: `DispatchDialog.qml:280,299,317,373,386`;
- preview levels and the story summary: `RunStore.qml` (subtask is `ready` at once), `runs.js` `previewSummary` (1169);
- two clicks only for a subtask: `confirmFirst` bound to a subtask target (`docs/architecture.md:176`);
- refusals: `dispatchPlan` (`The card is <status>`, `Board.isFinishedStatus`), `RunStore` `StoryBlockedError` -> `dispatchSuggest`, `DispatchDialog.qml:437`;
- prefix order: `runs.js` `dispatchDefaults` (1040-1046 comment);
- after start: `Navigator.openStartedRun`, `RunStore` `set-run-settings` (`verify`, `allowNoVerification`, `prefixHistory`, `parallelism`, `prefixByMilestone`).

- [ ] **Step 6: D5 -- add the `--story` requirement to the README Install `am` paragraph**

In `README.md`, line 258 (the paragraph starting `The run monitor also needs `am` on `PATH`.`), append this text to the end of that same paragraph (one space after `dimmed.`, same line):

```
Starting runs from the panel needs an `am` whose `am run` supports `--story`: `am run --help` must list it. `am` is installed as a `uv` tool; unless it is an editable install, update it after pulling agent-manager by running `uv tool install --reinstall .` in a clean checkout of agent-manager. `tests/contract/test_am_shapes.py` fails when the installed `am` lacks `--story`.
```

Nothing in the paragraph is removed. Do not add a URL for agent-manager.

- [ ] **Step 7: D6 -- extend the README Tests sentence**

In `README.md`, line 310, replace exactly this text:

```
pin the `am runs`, `am status` and `am watch` shapes the run helpers parse, and it is skipped when `am` is not installed.
```

with exactly this text:

```
pin the `am runs`, `am status` and `am watch` shapes the run helpers parse; it is skipped when `am` is not installed, and its story tests fail, rather than skip, when the installed `am` has no `am run --story`, or when brd or git is missing.
```

- [ ] **Step 8: Check for em dashes introduced into architecture prose**

Run:

```bash
git diff -U0 docs/architecture.md | grep '^+' | grep -n '—'
```

Expected: no output (the new architecture text uses ` -- ` only).

- [ ] **Step 9: Run the checks and watch them pass (GREEN)**

Run:

```bash
grep -n "a story's offers its milestone" docs/architecture.md
grep -n "no pause, resume, cancel or start" README.md
grep -n -- "--story" README.md
grep -n "fail, never skip" docs/architecture.md
grep -c "two clicks" README.md
grep -n "Whole board" README.md
grep -n "blocked.*failed\|failed.*blocked" README.md
grep -n "rather than skip" README.md
git diff --stat
```

Expected:
- 1st: no output (D1).
- 2nd: no output (D3).
- 3rd: at least three hits -- the **Dispatch** bullet (Features, right after line 154), the Install `am` paragraph (about line 259) and the Tests paragraph (about line 311) (D4, D5, D6).
- 4th: one hit in the `## Tests` section (D2).
- 5th: `1` -- only the subtask's Start is described as two clicks (Review Focus 1).
- 6th: one hit, in the **Dispatch** bullet, followed by `plus each milestone that can be dispatched` (Review Focus 2).
- 7th: no output (Review Focus 3).
- 8th: one hit in the Tests paragraph (Review Focus 5).
- `git diff --stat`: exactly two files, `README.md` and `docs/architecture.md`.

If any line differs, fix the text in the step that owns it and run Step 9 again.

- [ ] **Step 10: Run the full suite**

Run: `bash tests/run.sh`
Expected: pytest reports no failures (the `am` contract tests pass, or skip only when `am` is absent), every QML `Totals:` line shows `0 failed`, and the script exits 0. Nothing outside the docs changed, so any failure is pre-existing: stop and report it with its output rather than editing code.

- [ ] **Step 11: Commit**

```bash
git add README.md docs/architecture.md
git commit -m "docs: dispatch at every level, the am --story requirement and its contract test"
```

---

## Self-review against the spec

- D1 -> Step 2 (the stale phrase is gone; finished cards, `--story`, the blocked-only milestone offer through `dispatchSuggestion` / `retargetToMilestone()` named).
- D2 -> Step 3 (real repo and board, PATH of am/brd/git, help, dry-run payload, `StoryBlockedError` at dry run and detached start, `story_id`, fail-not-skip; skip-when-absent kept).
- D3 -> Step 4. D4 -> Step 5 (levels, entry points, dialog, refusals, prefix order, what is remembered). D5 -> Step 6. D6 -> Step 7.
- Error paths: two clicks only for a subtask (Step 5, checked in Step 9), chip row lists milestones not stories (Step 5, Step 9), a blocked story is refused not failed (Step 5 says "refused", Step 9), no em dashes in architecture prose (Step 8).
- Tests table: the four grep checks and `git diff --stat` are Step 9; `bash tests/run.sh` is Step 10.
- Out of scope respected: line 101 and 107-113 untouched; no code edits; pause/resume/cancel only named, not described.
<!-- task-pipeline: validated -->
