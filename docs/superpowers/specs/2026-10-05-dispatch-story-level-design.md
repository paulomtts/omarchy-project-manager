# Dispatch at story level (S7) — design

Status: proposed. Extends `2026-10-03-am-run-dispatch-design.md` (S3, merged before this
starts). Depends on `am run --story` in agent-manager (spec: `docs/superpowers/specs/2026-10-05-run-story-design.md`
in that repo), which must be merged AND installed first. `am` is a `uv tool` install and, today, an EDITABLE
one (the tool receipt says `editable = "/home/mtts/Code/agent-manager"`): merging into the
main checkout changes the `am` that runs, with no reinstall. That is a hazard, not a feature,
and the install becomes a regular non-editable one once the `agent-manager` stack's prerequisite
P1 (`2026-10-06-single-store-events-design.md`, "Dev safety") is done; from then on reinstall
after the merge (`uv tool install --reinstall .` from a clean checkout of the verified commit).

## Precondition (checked, not assumed)

`am run --help` lists `--story`. The milestone's first subtask is a contract test that
FAILS, with a message naming the missing option, when `am` is on the PATH without `--story`
(it skips only when `am` is absent altogether, like the other `am` contract tests). When that
test cannot pass, the run stops there and escalates: nothing after it can be verified
against real `am`.

## Problem

S3 dispatches a subtask (`am run --card`), a milestone (`--milestone`) and the whole
board (`--board`). A **story** has no `am` mode, so S3 offers its milestone instead
("a story is dispatched through its milestone"). The plugin must be able to start a run
at every level.

## Goal

| card the user is on | command |
|---|---|
| subtask | `am run --card ID` (S3, unchanged) |
| **story** | `am run --story ID` (this spec) |
| milestone | `am run --milestone ID` (S3, unchanged) |
| Runs screen, whole board | `am run --board` (S3, unchanged) |

All four go through the same dispatch dialog: dry-run preview before Start (the card
level has no `am` preview and shows the card's facts, as in S3), the cost warning, the
detached launcher, and landing on the new run's detail.

## Behaviour (story)

- **Entry points:** the Dispatch button in the card detail of a story card, and the `d` key
  on a story in the board list, exactly as for the other levels. The dialog target reads
  `Story "<title>" (milestone "<title>")`.
- **Preview:** `am run --story ID --branch-prefix P --base-branch B --dry-run`. The summary
  reads `N subtasks · rooted on <branch>` (the first subtask's `base`); there is no Integrate
  line (a story run ends at the story's tip branch, `integrate` is null) and no "stories
  already done" count.
- **Prefix:** the branch prefix must be the one the milestone's other stories use. The
  default, in order: the `branch_prefix` of the newest run in the Runs snapshot whose
  `milestone_id` is this story's milestone (so a milestone started from a terminal is
  honoured); else the last prefix used for that milestone through the panel (the per-project
  run settings, keyed by milestone id); else S3's prefix history; else the milestone's short
  stem. It is editable. The same default now also serves the milestone level.
- **Blocked story:** `am` refuses a story whose blocker stories are not finished with
  `StoryBlockedError` before anything is written. The dialog shows the refusal inline, Start
  stays disabled, and an action **Dispatch the milestone instead** retargets the dialog to the
  parent milestone. `am`'s spec does not say whether `--dry-run` raises it too, so the dialog
  handles both: refused at preview, or refused when Start returns it (an `am run --detach`
  pre-flight refusal or the launcher's early exit); the second case returns the dialog to the
  refused state with the same action.
- **Other refusals** (`ClaimedError`, no match, finished story = nothing to run) are shown
  inline as at the other levels. A finished story shows "Nothing left to run". A story whose
  cards a live milestone run holds is a `ClaimedError` naming that run.
- **Cards in terminal statuses** (`done`, `merged`, `canceled`, `archived`) are refused with
  the reason, as at every level.
- **Launch:** the same detached launcher. The run is found by `started_at`, prefix AND
  `story_id` (the row `am runs` returns carries `story_id`; two story runs started seconds
  apart with one prefix would otherwise be confused), or from the `run_id` of an
  `am run --detach` envelope when the launcher uses it. Its first `run_upsert` carries
  `milestone_id` of the parent milestone and `config.story_id`, so the monitor's card mapping
  (`stories[].card_id`) shows the live mark on the story and its subtasks.

## Architecture (changes to S3's pieces)

S3's code is merged on main when this starts; read it before changing it.

- `core/domain/runs.js`: `dispatchPlan(card)` returns `{command:'story', flags:{story:id}}`
  for a story card (replacing the "suggest its milestone" result); `previewSummary` gains
  the story variant (no integrate, no already-done stories); `dispatchDefaults` gains the
  `runs` argument and the prefix order above.
- `core/backend/runs/dispatch-preview.py` and `start-run.py`: accept the target kind `story`
  and build the argv with `--story`; run-id discovery also matches `story_id`; everything
  else (timeouts, envelope handling, detached session) is unchanged.
- Run settings (`viewer-state.py`): a `prefixByMilestone` map next to the existing prefix
  history, validated like the other fields; S3's history stays for the fallback.
- `RunStore` dispatch state machine, `DispatchDialog`, `CardDetailScreen`, `Shortcuts.qml`:
  the story target, the retarget, the entry points. No new component.

## Testing

- `tests/contract/test_am_shapes.py`: the installed `am` has `--story` (fails loudly when it
  does not), the `--story --dry-run` payload (`integrate: null`, one level), `story_id` on the
  `am runs` row (it stays on the row after the store change; the row also gains `project:
  {id, repo_dir}`, which these tests include), and the `StoryBlockedError` refusal, recorded
  from the real `am` against a throwaway board.
- `tst_runs.qml`: `dispatchPlan` for a story (and for terminal-status stories),
  `previewSummary` story variant, the four-step prefix default.
- Backend pytest with a fake `am`: `--story` argv for preview and start, refusal
  passthrough (`StoryBlockedError`), run-id discovery for a story run including two story runs
  with one prefix, `prefixByMilestone` round trip.
- `tst_run_store.qml`: the retarget-to-milestone action from a preview refusal and from a
  start refusal, prefix persistence by milestone.
- `tests/ui/`: the Dispatch button and `d` key on a story, the blocked-story inline refusal
  and its action, a finished story, a claimed story.

## Open

- Dispatching several stories at once is not offered; a milestone run covers that.
