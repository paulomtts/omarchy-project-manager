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
