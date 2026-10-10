# 2.4 RunStore: relaunchOpenFor — design

Card: `6ac0bc6d` (subtask of story `d44f2afe`, blocked by `d592e35f`, which is done on this
branch). Parent design: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`, cited
below as "RR l.N".

## Purpose

Relaunch starts a new run of a stopped run's work. A stopped run can be cancelled, an
escalated `task` run, or a run whose resume am refused. This card adds the store entry point
that opens S3's dispatch dialog state for that work. The dialog is prefilled with the run's
recorded branch prefix and base branch, not the defaults: `relaunchOpenFor(card, cardMap,
relaunch)`. The caller passes:

- `card`: the target card from `app.board.cardMap`;
- `cardMap`: the board's `{id: card}` map;
- `relaunch`: the `relaunch` part of `Runs.stopReport(run)`, which is
  `{level, cardId, prefix, base}` (`core/domain/runs.js:1129-1139`, `_relaunchOf`).

From the open state on, everything belongs to S3: the preview, the cost warning, Start, and
landing on the new run.

This card changes the store only. The Relaunch button, its disabled reason, and the lookup of
the target card in `app.board.cardMap` belong to sibling cards (`StopReasonBlock`,
`RunDetailScreen`).

### A discrepancy with the card, and how it is resolved

The card and RR l.273-278 say to build on the merged S3/S7 card-entry open function, with
`dispatchRoot` being the open project and the project and target steps skipped. That is the
state after "dispatch from the Runs screen" merges. That work is **not on this branch**:

- `grep dispatchRoot core ui` finds nothing;
- the `dispatch-from-the-runs-*` branches are not ancestors of HEAD.

The only open function here is S3/S7's project-bound `openDispatch(card, cardMap)`
(`core/stores/RunStore.qml:1598-1621`). It is already a card entry in every way the card
cares about:

- it opens for `store.project`, the open project, and for no other;
- it has no project step and no target step;
- verify and parallelism come from `store.runSettings` through `Runs.dispatchDefaults`.

So `relaunchOpenFor` builds on `openDispatch`. "dispatchRoot is the open project" is pinned
by what can be observed on this branch:

- `store.project` is unchanged;
- the `--defaults` lookup is launched for the open project's root;
- the preview argv begins with that root.

No `dispatchRoot` property is added: that belongs to the dispatch-from-Runs work. When that
work merges, its card-entry open function replaces `openDispatch` here. This spec asks for
nothing that would conflict with it.

## Current members this builds on (this branch's lines)

| member | lines |
|---|---|
| `// ---- dispatch (S3 3.1)` section header | `RunStore.qml:1554` |
| `resetDispatch()` (clears `dispatchBook.baseTouched`) | `:1570-1591` |
| `openDispatch(card, cardMap)` | `:1598-1621` |
| `withField(form, name, value)` | `:1650-1654` |
| `dispatchDefaultsReplied(stdout)`, which skips base when `baseTouched` | `:1685-1694` |
| `setDispatchField(name, value)`, which restarts the debounce and sets `baseTouched` | `:1758-1771` |
| `dropStartRunner(runner)`, the last dispatch function | `:1884-1888` |
| `dispatchBook.baseTouched` | `:2076-2084` |
| `Runs.dispatchPlan`, `Runs.dispatchDefaults` | `core/domain/runs.js:1348-1357`, `:1489-1506` |

## Inherited constraints

- The new member lives in a delimited section whose header line is literally
  `// ---- relaunch`. It goes right after S3's dispatch section: after `dropStartRunner` and
  before the HelperRunner declarations. It holds only `relaunchOpenFor` and any helper
  prefixed `relaunch`. The split lifts it whole into `RunDispatchStore`
  (RR l.17-25; `docs/superpowers/specs/2026-10-05-split-runstore-design.md:57`).
- `relaunchOpenFor(card, cardMap, relaunch)` opens S3's dispatch state machine for `card`,
  with `relaunch.prefix` and `relaunch.base` over the defaults (RR l.273-278, l.200-205).
- Verify and parallelism come from the project's run settings, as for any dispatch
  (RR l.204-205).
- Preview, cost warning, Start and landing are S3's, unchanged (RR l.205-206).
- Relaunch is a card entry bound to the open project (RR l.207-211).
- It is refused (false) without the card. A card that is gone or finished is refused by
  `dispatchPlan`, as at any dispatch (RR l.211-213, l.278).
- Store tests go in `tests/core/stores/tst_run_store.qml`, in their own relaunch block
  (RR l.311-319).
- Card rules:
  - stores import only QtQml, Quickshell, Quickshell.Io and `../domain`
    (`docs/architecture.md`);
  - `tests/architecture` passes (no duplicated components, icon glyph rules);
  - `bash tests/run.sh` is green;
  - TDD;
  - docstrings and comments state the contract only, with no narrative.

## Behaviour

### `relaunchOpenFor(card, cardMap, relaunch)` → bool

Its comment above the function (contract only): it opens the dispatch for `card` as
`openDispatch` does, with `relaunch.prefix` and `relaunch.base`, when non-blank, over the
defaults. It returns `openDispatch`'s result. It is refused (false, nothing changes) when
`card` or `relaunch` is not an object.

The steps run in order:

1. **Guard.** `card` must be a non-null object that is not an array, and so must
   `relaunch`. When either is not, return `false`. Nothing changes: the dispatch state, form,
   target and runners keep whatever they were. A dispatch already open stays open, and
   `openDispatch` is not called. This covers a `null` or `undefined` card, such as a target
   that is no longer on the board, where the caller's `cardMap[id]` gives `undefined`. It
   also covers a `null` relaunch, from a run that names no target.
2. **Open.** `opened = store.openDispatch(card, cardMap)`. Its refusals are unchanged and
   pass through as `false`:
   - no open project, or a start in flight: nothing changes;
   - a card `dispatchPlan` does not offer (finished, unknown depth, bad id): state
     `refused`, with `dispatchErrorType` `"Target"` and `dispatchError` the plan's reason.

   When `opened` is false, return `false` and override nothing.
3. **Override.** When `relaunch.prefix` is a string that is not blank after trim,
   `dispatchForm` becomes `withField(dispatchForm, "prefix", relaunch.prefix.trim())`. When
   `relaunch.base` is a string that is not blank after trim:
   - `dispatchForm` becomes `withField(dispatchForm, "base", relaunch.base.trim())`;
   - `dispatchBook.baseTouched` becomes `true`, so the `--defaults` reply does not replace
     the recorded base.

   A blank, missing or non-string value leaves that field at its default:
   - prefix: `Runs.dispatchDefaults`' prefix;
   - base: `""` until the `--defaults` reply fills the default branch.

   The override does not use `setDispatchField`. That function would restart the debounce,
   clear the error and start a check before the defaults lookup replies. The state stays
   `previewing`, and `dispatchBook.defaultsPending` stays `true`.
4. Return `true`.

### What is not changed

- `verify`, `parallelism` and `allowNoVerification` keep the values `openDispatch` set from
  `store.runSettings`.
- `dispatchTarget`, `dispatchTargetLabel`, the recorded `cardMap` and the milestone are
  `openDispatch`'s.
- `relaunch.level` and `relaunch.cardId` are not read. The caller chose `card` from them,
  and `dispatchPlan` derives the level from `card.depth`.
- The `--defaults` lookup still runs for `store.project`. Its reply checks the form at once:
  - a milestone or story is previewed with the overridden prefix and base;
  - a subtask becomes `ready`.
- The preview, the cost warning, `dispatchStart`, its `set-run-settings` save and landing on
  the new run are untouched.
- A later user edit through `setDispatchField` behaves as in any dispatch.
- No new properties, runners or signals.

## Error paths

| case | result | state after |
|---|---|---|
| `card` null, undefined or not an object | `false` | unchanged (idle stays idle; an open dispatch stays as it was) |
| `relaunch` null, undefined or not an object | `false` | unchanged |
| no open project (`store.project === ""`) | `false` | unchanged (openDispatch's guard) |
| a start in flight (`dispatchState === "starting"`) | `false` | unchanged (openDispatch's guard) |
| finished card (`status` done) | `false` | `refused`, `dispatchErrorType` `"Target"`, form null, nothing overridden |
| `relaunch.prefix` blank or non-string | `true` | prefix is `dispatchDefaults`' |
| `relaunch.base` blank or non-string | `true` | base `""`, then the `--defaults` branch fills it; `baseTouched` stays false |
| `--defaults` reply names another branch than `relaunch.base` | — | base stays `relaunch.base` |
| `--defaults` reply fails | — | base stays `relaunch.base`, and the preview carries `--base-branch` with it |

## Tests

Every test is a store test in `tests/core/stores/tst_run_store.qml` (QML `TestCase`
`StoresRunStore`), in a new block headed `// ---- relaunch` and appended after the last
test. This is the store tier: the behaviour is the store's state and the argv of its
runners, which the existing fake-process `HelperRunner` harness observes directly. No UI is
involved, and no domain function changes.

Reuse the file's helpers:

- `dispatchStore()` (`:4469`): project `rootA` = `"/home/u/my proj"`, settings verify
  `["uv run pytest"]`, parallelism 4, prefixHistory `["old"]`;
- `dispatchCards()` (`:4459`): `m1` milestone, `s1` story, `t1` subtask, `d1` done
  milestone;
- `reply(proc, text, code)`, `defaultsOk(branch)` (`:4603`), `argv(proc)` (`:2422`),
  `tc.previewCmd`, `checkDispatchIdle(store, label)` (`:4476`).

A local helper (prefixed `relaunch`) builds `{level: "milestone", cardId: "m1", prefix:
"relaunch/m1", base: "release"}`.

1. **Prefix and base overridden.** Call `relaunchOpenFor(cards.m1, cards, r)`. It returns
   `true`, the state is `previewing`, and `dispatchForm.prefix` is `"relaunch/m1"` and
   `dispatchForm.base` is `"release"`. After `reply(defaultsRunner, defaultsOk("main"), 0)`,
   base is still `"release"`.
2. **Verify and parallelism from settings.** After the open: `dispatchForm.verify` equals
   `["uv run pytest"]`, `parallelism` is `4` and `allowNoVerification` is `false`. They are
   not taken from the relaunch object, even when it carries `verify` or `parallelism` keys.
3. **The open project is the dispatch root.** `store.project` is still `rootA`. The
   `--defaults` runner's argv ends with `--defaults|/home/u/my proj`. After the defaults
   reply, the preview argv's first argument after the script is `/home/u/my proj`, and the
   preview runner's `launchGuard` is `/home/u/my proj`.
4. **A missing card is refused.**
   - For `card` `null` and `undefined`: `false`, `checkDispatchIdle` holds, and no defaults
     runner is launched.
   - With `m1` already open by `openDispatch`, a `null` card returns `false` and leaves the
     m1 dispatch untouched: same target, same form.
   - A `null` relaunch with `cards.m1` returns `false` and stays idle.
   - The finished `d1` returns `false` with state `refused` and `dispatchErrorType`
     `"Target"`.
5. **The preview starts with the overridden values.** After the defaults reply `main`, the
   preview argv is `tc.previewCmd + "/home/u/my
   proj|milestone|m1|--base-branch|release|--branch-prefix|relaunch/m1|--max-concurrent|4|--verify|uv
   run pytest"`.
6. **Blank values keep the defaults.** A relaunch with prefix `""` and base `"  "`: the
   prefix is `"old"` (dispatchDefaults), and after `defaultsOk("main")` the base is
   `"main"`. The preview argv equals the existing `tc.previewArgs` pattern for m1.
7. **Values are trimmed.** Prefix `"  relaunch/m1 "` and base `" release\n"` give
   `"relaunch/m1"` and `"release"` in the form.

## Out of scope

- Any `dispatchRoot` property, project step or target step. These come from dispatch from
  the Runs screen, which is not on this branch.
- The Relaunch button, its offer rules and the disabled reason "Open this run's project to
  relaunch it": sibling UI cards (`StopReasonBlock`, `RunDetailScreen`).
- `Runs.stopReport`, `_relaunchOf`, `offersRelaunch`: domain, already done.
- Looking up the target card in `app.board.cardMap`: the caller.
- The resume dialog (2.3), `VerifyCommandsField`, `ResumeVerifyDialog`, and
  `tests/ui/tst_runs_flow.qml`'s relaunch flow: sibling cards.
- Any change to `openDispatch`, the preview, the cost warning or Start.
