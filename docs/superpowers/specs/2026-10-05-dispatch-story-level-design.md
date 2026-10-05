# Dispatch at story level (S7) — design

Status: proposed. Extends `2026-10-03-am-run-dispatch-design.md` (S3). Depends on
`am run --story` in agent-manager (spec: `docs/superpowers/specs/2026-10-05-run-story-design.md`
in that repo), which must be merged and installed first.

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
  reads `N subtasks · rooted on <branch>`; there is no Integrate line (a story run ends at
  the story's tip branch) and no "stories already done" count.
- **Prefix:** the branch prefix must be the one the milestone's other stories use. The
  default is the last prefix used for this story's MILESTONE (kept in the per-project run
  settings, keyed by milestone id), else the milestone's short stem; it is editable.
  The same keyed default now also serves the milestone level.
- **Blocked story:** `am` refuses a story whose blocker stories are not finished with
  `StoryBlockedError`. The dialog shows the refusal inline, Start stays disabled, and an
  action **Dispatch the milestone instead** retargets the dialog to the parent milestone.
- **Other refusals** (`ClaimedError`, no match, finished story = nothing to run) are shown
  inline as at the other levels. A finished story shows "Nothing left to run".
- **Cards in terminal statuses** (`done`, `merged`, `canceled`, `archived`) are refused with
  the reason, as at every level.
- **Launch:** the same detached launcher; the run is found by `started_at` and prefix, and
  its first `run_upsert` carries `milestone_id` of the parent milestone and
  `config.story_id`, so the monitor's card mapping (`stories[].card_id`) shows the live
  mark on the story and its subtasks.

## Architecture (changes to S3's pieces)

- `core/domain/runs.js`: `dispatchPlan(card)` returns `{command:'story', flags:{story:id}}`
  for a story card (replacing the "suggest its milestone" result); `previewSummary` gains
  the story variant (no integrate, no already-done stories); `dispatchDefaults` takes the
  prefix from the milestone-keyed settings.
- `core/backend/runs/dispatch-preview.py` and `start-run.py`: accept the target kind `story`
  and build the argv with `--story`; everything else (timeouts, envelope handling, detached
  session, run-id discovery) is unchanged.
- Run settings (`viewer-state.py`): a `prefixByMilestone` map next to the existing prefix
  history; S3's history stays for the fallback.
- `RunStore` dispatch state machine, `DispatchDialog`, `CardDetailScreen`, `Shortcuts.qml`:
  the story target, the blocked-story action, the entry points. No new component.

## Testing

- `tst_runs.qml`: `dispatchPlan` for a story (and for terminal-status stories),
  `previewSummary` story variant, prefix default from the milestone-keyed settings.
- Backend pytest with a stub `am`: `--story` argv for preview and start, refusal
  passthrough (`StoryBlockedError`), run-id discovery for a story run.
- `tst_run_store.qml`: the retarget-to-milestone action, prefix persistence by milestone.
- `tests/ui/`: the Dispatch button and `d` key on a story, the blocked-story inline refusal
  and its action, a finished story.
- `tests/contract/test_am_shapes.py`: the `--story --dry-run` payload (`integrate: null`) and
  the `story_id` field of `am runs`, skipped when the installed `am` lacks `--story`.

## Open

- Dispatching several stories at once is not offered; a milestone run covers that.
