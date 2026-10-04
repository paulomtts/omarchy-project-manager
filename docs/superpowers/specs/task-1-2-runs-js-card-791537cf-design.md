# 1.2 runs.js: card mapping, rollups, attention, error text (card 791537cf)

Narrowed from `docs/superpowers/specs/2026-10-03-am-run-monitor-design.md` ("Domain model", "Data sources", "Errors", "Testing"). Parent story 10d626dc "Run domain model". Blocked by 1.1 (797d9382, done).

## Starting point

In this worktree, 1.1 is on disk. `core/domain/runs.js` already has `normalizeRun(raw)` (returns `{id, repo_dir, milestone_id, status, lease, rows, tree:{stories, subtasks}}`) and `runState(run)` (returns `running | dead | parked | escalated | cancelled | done | unknown`). `tests/core/domain/tst_runs.qml` (TestCase "DomainRuns") covers both. The main checkout at `/home/mtts/Code/omarchy-project-manager` does not have these files, but this worktree does. 1.2 only adds code to the files. It does not change `normalizeRun`, `runState` or their existing tests.

## Scope

Add five pure functions to `core/domain/runs.js`, with tests in `tests/core/domain/tst_runs.qml`. Write the tests first.

Out of scope: RunStore and any other store, the backend helpers (`runs-snapshot.py`, `runs-watch.py`, `runs-logs.py`), UI components and screens, Navigator, Shortcuts, edits to `docs/architecture.md`, glyphs and colours, and the `stale` flag (that is a store concern).

Constraints: the file stays `.pragma library` and uses `var`/function style. No imports are needed. If any are added, they may only be `core/domain/*.js` via `.import`. No glyph literals. No function throws. Garbage input (null, non-array, non-object, missing fields) becomes a default result. Card ids are compared with `===` on strings, using linear scans, or prototype-less maps with `hasOwnProperty`. Ids such as `constructor`, `__proto__` and `toString` must behave like any other id.

## Shared rules

- Input `runs` is an array of normalised runs, i.e. the output of `normalizeRun`. A non-array is treated as `[]`.
- **Synthetic ids.** `integrate`, `bases`, and any id starting with `base-` never match a card. They are never counted in a rollup.
- **Touches.** A run touches card id C (non-empty, not synthetic) when C equals `run.milestone_id`, any `run.tree.stories[].card_id`, or any `run.tree.subtasks[].card_id`.
- **Non-terminal.** A run is non-terminal when its `runState` is `running` or `dead` (status `started`). This follows the spec's definition: a run is finished when its status is done, escalated, stopped or cancelled.
- **Newest.** `normalizeRun` drops `started_at`, so recency is not stored on the run. If both runs carry a string `started_at` (for example, the store copied it from the `am runs` row), the later ISO string is newer. Otherwise the earlier index in `runs` is newer, since the input is taken as newest-first. 1.2 must not change `normalizeRun` to add the field. Tests pin this rule.
- **Winning run for C.** Take the newest non-terminal run that touches C. If there is none, take the newest run that touches C and mark the result `dimmed`.

## Functions and observable behaviour

**`cardRunState(runs, cardId)`** returns `{state, runId, dimmed, phase, attempt}`.
- No run touches the card (this includes a synthetic or empty `cardId`): `{state:"none", runId:"", dimmed:false, phase:"", attempt:0}`.
- Otherwise, `state` comes from the winning run's `runState`:
  - `running`, `dead`, `parked` and `escalated` pass through.
  - `done`, `cancelled` and `unknown` become `none`.
  - `runId` is still set, and `dimmed` follows the winning-run rule.
- `phase` and `attempt` are filled only when C is a `tree.subtasks[].card_id` in the winning run:
  - `phase` is the `name` of the subtask's last entry in `phases`.
  - `attempt` is that phase's `attempts.length`. If the last attempt has a numeric `attempt`/`n` field, that value is used instead.
  - For stories and milestones, and whenever the shape is missing, `phase` is `""` and `attempt` is `0`. The tree shape is provisional, as in 1.1, and the tests pin it.
- The result never reads brd status.

**`rollup(runs, card)`** returns `{running, parked, escalated, done, pending, total}`, all integers.
- `card` is a brd card object, and its `id` is used.
- The rollup counts only am `rows` from the winning run for `card.id`. A row is counted only when it meets both conditions:
  - its `card_id` is a subtask in that run's `tree.subtasks` and is not synthetic;
  - when `card.id` is a story, it belongs to that story. Membership is either the row's subtask appearing in `tree.stories[k].subtasks`, where `tree.stories[k].card_id === card.id` and entries are id strings or `{card_id}`, or the subtask entry having `story_id === card.id`.
- When `card.id` is the run's `milestone_id`, every qualifying subtask row in the run is counted.
- When `card.id` is a subtask (it appears only in `tree.subtasks`, not as a story or the milestone), only rows whose `card_id === card.id` are counted. The story-membership check does not apply.
- A row is classified by its `status`:
  - `running`/`started` → running
  - `parked`/`stopped` → parked
  - `escalated`/`failed` → escalated
  - `done` → done
  - anything else → pending
- `total` is the sum of the five counts. When no run touches the card, or the card is garbage, every count is 0.
- The function never reads brd status and does not touch `Board.subtreeCounts`.

**`attention(runs)`** returns the runs whose `runState` is `escalated` or `dead`, in input order. The objects are the same ones that were passed in. A non-array returns `[]`.

**`escalationReason(run)`**
- The function walks `run.tree.subtasks[].phases[]` in order to find the first phase whose `status` is `failed`.
- It returns that phase's non-empty `detail`. If the phase has none, it uses the `detail` of the phase's last attempt that has one.
- If a failed phase exists but has no detail anywhere, the result is `"escalated at <phase name>"`.
- If there is no failed phase, the result is `"escalated at <phase>"`, where the phase comes from the last `rows[]` entry with a non-empty `phase`.
- If no phase can be found, or the input is garbage, the result is `"escalated"`.

**`errorText(error)`**
- Accepts either the full envelope `{ok:false, error:{type, message}}` or the bare `{type, message}`.
- The result is `"<type>: <message>"` when both are non-empty, otherwise whichever one is non-empty. If neither is, or the input is garbage, it is `"unknown error"`.
- An `ok:true` envelope returns `""`.
- Values are coerced with `String`. Each value is trimmed.

## Tests (all in `tests/core/domain/tst_runs.qml`, tier: pure domain QML TestCase per docs/architecture.md "Tests"; no store/UI/backend/contract tests)

All tests below go in `tst_runs.qml`.

| Test | What it checks |
|---|---|
| `test_card_maps_story_subtask_milestone` | A card matches through `stories[].card_id`, `subtasks[].card_id` and `milestone_id`. An unrelated id gives `none`. |
| `test_card_synthetic_ids_never_match` | `integrate`, `bases` and `base-x` give `none`, even when they are present in the tree, in rows or as `milestone_id`. |
| `test_card_newest_nonterminal_wins` | A card in an older `running` run and a newer `done` run resolves to the running run, with `dimmed` false. `dead` counts as non-terminal. |
| `test_card_all_terminal_newest_dimmed` | `parked`, `escalated`, `done` and `cancelled` cases each resolve to the newest run, with `dimmed` true and the state mapped (`done`/`cancelled` give `none` with `runId` set). |
| `test_card_newest_by_started_at_then_order` | `started_at` decides when both runs have it. Otherwise the earlier index wins. |
| `test_card_subtask_phase_attempt` | A subtask gets `phase` and `attempt`. A story or milestone gets `""` and `0`. Missing `phases`/`attempts` are tolerated. |
| `test_card_ignores_brd_status` | A `status` field on the card or brd side has no effect. |
| `test_card_proto_ids` | Card ids `__proto__`, `constructor` and `toString` match only when they are really present, and never throw. |
| `test_card_garbage` | Non-array runs, a null run inside the array, and a null or empty cardId all give the `none` default. |
| `test_rollup_milestone` | Counts are correct for every status bucket. `total` is their sum. Story and synthetic rows are excluded. |
| `test_rollup_story_membership` | Only the story's subtasks are counted, through both `stories[].subtasks` (strings and `{card_id}`) and `story_id`. |
| `test_rollup_uses_winning_run_only` | Rows from losing runs are not counted. |
| `test_rollup_subtask_card` | A subtask card counts only its own rows. |
| `test_rollup_rows_only_not_brd` | The card's brd status and children are ignored. An untouched card gets all zeros. Garbage input gets all zeros. |
| `test_attention` | Only `escalated` and `dead` runs are returned, in input order. `running`, `parked`, `done`, `cancelled` and `unknown` are excluded. Non-array input gives `[]`. |
| `test_escalation_reason_detail` | The failed phase's `detail` is returned. The attempt-level `detail` fallback works. |
| `test_escalation_reason_fallbacks` | The function returns `escalated at <failed phase>` when there is no detail, `escalated at <last row phase>` when no phase failed, and `escalated` when there is nothing or the input is garbage. |
| `test_error_text` | Covers the full envelope, a bare error, type only, message only, neither, the `ok:true` envelope giving `""`, and null, string and number input. |

Verification: `bash ./tests/run.sh` (filter: `bash tests/run.sh runs`). The existing 1.1 tests and the `tests/architecture/` suite must pass unchanged. There is no typecheck or lint step.
