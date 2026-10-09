# 2.4 RunStore: relaunchOpenFor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `RunStore.relaunchOpenFor(card, cardMap, relaunch)` opens S3's dispatch state for a stopped run's card, prefilled with the run's recorded branch prefix and base branch instead of the defaults.

**Architecture:** One new function in a new `// ---- relaunch` section of `core/stores/RunStore.qml`, placed right after `dropStartRunner` (the last dispatch function) and before the first `HelperRunner` declaration (`snapshotRunner`). It guards its two object arguments, delegates to the existing `openDispatch(card, cardMap)`, then overrides `dispatchForm.prefix` / `dispatchForm.base` with `withField` (not `setDispatchField`) and sets `dispatchBook.baseTouched` when base is overridden, so the pending `--defaults` reply keeps the recorded base. No new properties, runners or signals.

**Tech Stack:** QML/JS (Qt 6, Quickshell), QML `TestCase` run by `qmltestrunner` through `bash tests/run.sh`, stub `HelperRunner`/`Process` in `tests/stubs`.

**Spec:** `docs/superpowers/specs/2-4-runstore-6ac0bc6d.md` (reproduced in full below).

## Global Constraints

- The new member lives in a delimited section whose header line is literally `// ---- relaunch`, right after `dropStartRunner` and before the HelperRunner declarations; it holds only `relaunchOpenFor` and any helper prefixed `relaunch`.
- `relaunchOpenFor(card, cardMap, relaunch)` → bool: `false` (nothing changes, `openDispatch` not called) when `card` or `relaunch` is not a non-null, non-array object; otherwise `openDispatch`'s result, with overrides applied only when it is `true`.
- Overrides: `relaunch.prefix` / `relaunch.base` only when a string that is non-blank after trim, stored trimmed; base override also sets `dispatchBook.baseTouched = true`. Never through `setDispatchField`.
- `relaunch.level` and `relaunch.cardId` are not read; `verify`, `parallelism`, `allowNoVerification` stay `openDispatch`'s (from `store.runSettings`).
- No `dispatchRoot` property, no project or target step; no change to `openDispatch`, the preview, the cost warning or Start.
- Stores import only QtQml, Quickshell, Quickshell.Io and `../domain`. No new imports are needed.
- `tests/architecture` must pass; `bash tests/run.sh` must be green; TDD.
- Docstrings and comments state the contract only, with no narrative.
- Store tests go in `tests/core/stores/tst_run_store.qml`, in a new block headed `// ---- relaunch` appended after the last test of the file.

## Review Focus

1. Relaunch pressed while a dispatch start is in flight (`dispatchState === "starting"`) must return `false` and leave the start, its target and its form alone — test `test_relaunch_is_refused_without_a_project_or_while_starting` in Task 1.
2. The `--defaults` lookup fails (helper crash, exit 1): the recorded base must stay, and the preview must carry `--base-branch release` — test `test_relaunch_keeps_the_recorded_base_when_the_defaults_lookup_fails` in Task 1.
3. Relaunch of a subtask (an escalated `task` run): after the defaults reply it is `ready` (no preview) with the recorded prefix and base, so Start sends them — test `test_relaunch_of_a_subtask_is_ready_with_the_recorded_values` in Task 1.
4. A plain `openDispatch` after a relaunch (user closes and dispatches the same card from the board) must not inherit the relaunch's `baseTouched`: the default branch fills base again — test `test_an_opening_after_a_relaunch_takes_the_default_branch_again` in Task 1.
5. Arguments that are objects in `typeof` terms but not cards — arrays, and a string id instead of a card — must be refused like `null` — assertions in `test_relaunch_without_a_card_or_relaunch_is_refused` in Task 1.

---

## Spec (prepended; headings demoted one level)

## 2.4 RunStore: relaunchOpenFor — design

Card: `6ac0bc6d` (subtask of story `d44f2afe`, blocked by `d592e35f`, which is done on this
branch). Parent design: `docs/superpowers/specs/2026-10-05-resume-recover-design.md`, cited
below as "RR l.N".

### Purpose

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

#### A discrepancy with the card, and how it is resolved

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

### Current members this builds on (this branch's lines)

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

### Inherited constraints

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

### Behaviour

#### `relaunchOpenFor(card, cardMap, relaunch)` → bool

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

#### What is not changed

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

### Error paths

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

### Tests

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

### Out of scope

- Any `dispatchRoot` property, project step or target step. These come from dispatch from
  the Runs screen, which is not on this branch.
- The Relaunch button, its offer rules and the disabled reason "Open this run's project to
  relaunch it": sibling UI cards (`StopReasonBlock`, `RunDetailScreen`).
- `Runs.stopReport`, `_relaunchOf`, `offersRelaunch`: domain, already done.
- Looking up the target card in `app.board.cardMap`: the caller.
- The resume dialog (2.3), `VerifyCommandsField`, `ResumeVerifyDialog`, and
  `tests/ui/tst_runs_flow.qml`'s relaunch flow: sibling cards.
- Any change to `openDispatch`, the preview, the cost warning or Start.

---

## File Structure

- Modify: `core/stores/RunStore.qml` — insert the `// ---- relaunch` section (comment + `relaunchOpenFor`) between the closing `}` of `dropStartRunner` (currently `:1884-1888`) and the comment above `HelperRunner { id: snapshotRunner` (currently `:1890`).
- Modify: `tests/core/stores/tst_run_store.qml` — append a `// ---- relaunch` block (one helper, one property, eleven tests) after the last test, `test_a_list_of_the_old_store_in_flight_at_a_hello_reset_is_never_applied` (ends `:6461`), before the file's final `}`.

One task: the function is a single unit, and every test exercises the same eight lines; splitting guards from overrides would leave a task with no RED.

### Task 1: `relaunchOpenFor` in a `// ---- relaunch` section

**Files:**
- Modify: `core/stores/RunStore.qml:1888-1890` (insert after `dropStartRunner`)
- Test: `tests/core/stores/tst_run_store.qml:6461-6463` (append before the final `}`)

**Interfaces:**
- Consumes (existing, unchanged):
  - `store.openDispatch(card, cardMap) → bool` (`RunStore.qml:1598`): refuses `false` with nothing changed when `store.project === ""` or `dispatchState === "starting"`; otherwise resets, and for a target `Runs.dispatchPlan` does not offer sets state `refused`, `dispatchErrorType` `"Target"`, form `null`, returns `false`; for an offered one sets the form from `Runs.dispatchDefaults`, state `previewing`, `dispatchBook.defaultsPending = true`, launches `dispatchDefaultsRunner.run(["--defaults", store.project])`, returns `true`.
  - `store.withField(form, name, value) → object` (`RunStore.qml:1650`): a copy of `form` with `name` set.
  - `dispatchBook.baseTouched` (`RunStore.qml:2081`): when `true`, `dispatchDefaultsReplied` does not write base; `resetDispatch()` clears it.
  - Test helpers in `tst_run_store.qml`: `dispatchStore()`, `dispatchCards()`, `make()`, `reply(proc, text, code)`, `defaultsOk(branch)`, `previewOk(data)`, `dispatchDryRun()`, `readyStore()`, `argv(proc)`, `checkDispatchIdle(store, label)`, properties `tc.previewCmd`, `tc.startCmd`, `tc.previewArgs`, `rootA`.
- Produces: `store.relaunchOpenFor(card, cardMap, relaunch) → bool`, where `relaunch` is `Runs.stopReport(run).relaunch` = `{level, cardId, prefix, base}`. Used by the sibling UI cards (`StopReasonBlock`, `RunDetailScreen`).

- [ ] **Step 1: Write the failing tests**

In `tests/core/stores/tst_run_store.qml`, the file currently ends:

```qml
    reply(store.snapshotRunner.current, capturedList(), 0)
    compare(store.runs.length, 2)
  }
}
```

Insert the block below between the last test's closing `  }` and the file's final `}` (keep one blank line before `  // ---- relaunch`):

```qml

  // ---- relaunch

  // Runs.stopReport's relaunch for m1 with a recorded prefix and base; extra's
  // keys are set over it.
  function relaunchOf(extra) {
    var r = { level: "milestone", cardId: "m1", prefix: "relaunch/m1", base: "release" }
    for (var key in extra) r[key] = extra[key]
    return r
  }

  property string relaunchArgs: "/home/u/my proj|milestone|m1|--base-branch|release|--branch-prefix|relaunch/m1|--max-concurrent|4|--verify|uv run pytest"

  function test_relaunch_overrides_prefix_and_base() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.relaunchOpenFor(cards.m1, cards, relaunchOf()), true)
    compare(store.dispatchState, "previewing")
    compare(store.dispatchTarget.level, "milestone")
    compare(store.dispatchTargetLabel, Runs.dispatchLabel(cards.m1, cards))
    compare(store.dispatchForm.prefix, "relaunch/m1")
    compare(store.dispatchForm.base, "release")
    compare(store.dispatchError, "")
    compare(store.dispatchDebounceTimer.running, false, "no check is scheduled before the defaults reply")
    verify(!store.dispatchPreviewRunner.current, "no preview before the defaults reply")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "release", "the default branch does not replace the recorded base")
    compare(store.dispatchForm.prefix, "relaunch/m1")
  }

  function test_relaunch_takes_verify_and_parallelism_from_the_settings() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    var r = relaunchOf({ verify: ["make lint"], parallelism: 9, allowNoVerification: true })
    compare(store.relaunchOpenFor(cards.m1, cards, r), true)
    var form = store.dispatchForm
    compare(Object.keys(form).sort().join(","), "allowNoVerification,base,parallelism,prefix,verify")
    compare(form.verify.length, 1)
    compare(form.verify[0], "uv run pytest")
    compare(form.parallelism, 4)
    compare(form.allowNoVerification, false)
  }

  function test_relaunch_dispatches_from_the_open_project() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    compare(store.project, rootA)
    var lookup = store.dispatchDefaultsRunner.current
    compare(argv(lookup), tc.previewCmd + "--defaults|/home/u/my proj")
    reply(lookup, defaultsOk("main"), 0)
    var proc = store.dispatchPreviewRunner.current
    verify(proc, "the preview is launched")
    compare(proc.command[2], "/home/u/my proj", "the first argument after the script is the open project")
    compare(proc.launchGuard, "/home/u/my proj")
  }

  function test_relaunch_preview_and_start_carry_the_recorded_values() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.relaunchArgs)
    reply(store.dispatchPreviewRunner.current, previewOk(dispatchDryRun()), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchStart(), true)
    compare(argv(store.dispatchStartRunners[0].current), tc.startCmd + tc.relaunchArgs)
  }

  function test_relaunch_without_a_card_or_relaunch_is_refused() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    var noCards = [null, undefined, [], "m1"]
    for (var i = 0; i < noCards.length; i++) {
      compare(store.relaunchOpenFor(noCards[i], cards, relaunchOf()), false, "card " + i)
      checkDispatchIdle(store, "card " + i)
    }
    var noRelaunch = [null, undefined, []]
    for (var j = 0; j < noRelaunch.length; j++) {
      compare(store.relaunchOpenFor(cards.m1, cards, noRelaunch[j]), false, "relaunch " + j)
      checkDispatchIdle(store, "relaunch " + j)
    }
    verify(!store.dispatchDefaultsRunner.current, "no defaults lookup")

    compare(store.openDispatch(cards.m1, cards), true)
    var target = store.dispatchTarget
    var form = store.dispatchForm
    var lookup = store.dispatchDefaultsRunner.current
    compare(store.relaunchOpenFor(null, cards, relaunchOf()), false)
    compare(store.dispatchState, "previewing", "the open dispatch stays open")
    verify(store.dispatchTarget === target, "same target")
    verify(store.dispatchForm === form, "same form")
    compare(store.dispatchForm.prefix, "old")
    verify(store.dispatchDefaultsRunner.current === lookup, "the same lookup")
    compare(lookup.running, true, "still in flight")

    compare(store.relaunchOpenFor(cards.d1, cards, relaunchOf({ cardId: "d1" })), false)
    compare(store.dispatchState, "refused")
    compare(store.dispatchErrorType, "Target")
    compare(store.dispatchError, "The card is done")
    compare(store.dispatchForm, null, "nothing overridden")
  }

  function test_relaunch_blank_values_keep_the_defaults() {
    var variants = [{ prefix: "", base: "  " }, { prefix: 7, base: null }, { prefix: undefined, base: undefined }]
    for (var i = 0; i < variants.length; i++) {
      var store = dispatchStore(); if (!store) return
      var cards = dispatchCards()
      compare(store.relaunchOpenFor(cards.m1, cards, relaunchOf(variants[i])), true, "variant " + i)
      compare(store.dispatchForm.prefix, "old", "variant " + i + ": dispatchDefaults' prefix")
      compare(store.dispatchForm.base, "", "variant " + i + ": no base until the lookup replies")
      reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
      compare(store.dispatchForm.base, "main", "variant " + i + ": the default branch fills base")
      compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.previewArgs, "variant " + i)
    }
  }

  function test_relaunch_values_are_trimmed() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.relaunchOpenFor(cards.m1, cards, relaunchOf({ prefix: "  relaunch/m1 ", base: " release\n" })), true)
    compare(store.dispatchForm.prefix, "relaunch/m1")
    compare(store.dispatchForm.base, "release")
  }

  // Review Focus 1.
  function test_relaunch_is_refused_without_a_project_or_while_starting() {
    var bare = make(); if (!bare) return
    var cards = dispatchCards()
    compare(bare.relaunchOpenFor(cards.m1, cards, relaunchOf()), false)
    checkDispatchIdle(bare, "no project")
    verify(!bare.dispatchDefaultsRunner.current, "no defaults lookup")

    var store = readyStore(); if (!store) return
    compare(store.dispatchStart(), true)
    var form = store.dispatchForm
    compare(store.relaunchOpenFor(cards.s1, cards, relaunchOf({ level: "story", cardId: "s1" })), false)
    compare(store.dispatchState, "starting")
    compare(store.dispatchTarget.level, "milestone", "the start's target stays")
    verify(store.dispatchForm === form, "the start's form stays")
    compare(store.dispatchForm.prefix, "old")
    compare(store.dispatchStartRunners.length, 1)
  }

  // Review Focus 2.
  function test_relaunch_keeps_the_recorded_base_when_the_defaults_lookup_fails() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    reply(store.dispatchDefaultsRunner.current, "Traceback: boom\n", 1)
    compare(store.dispatchForm.base, "release")
    compare(argv(store.dispatchPreviewRunner.current), tc.previewCmd + tc.relaunchArgs)
  }

  // Review Focus 3.
  function test_relaunch_of_a_subtask_is_ready_with_the_recorded_values() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    compare(store.relaunchOpenFor(cards.t1, cards, relaunchOf({ level: "subtask", cardId: "t1", prefix: "relaunch/t1" })), true)
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchState, "ready")
    compare(store.dispatchTarget.level, "subtask")
    compare(store.dispatchForm.prefix, "relaunch/t1")
    compare(store.dispatchForm.base, "release")
    verify(!store.dispatchPreviewRunner.current, "a subtask has no preview")
  }

  // Review Focus 4.
  function test_an_opening_after_a_relaunch_takes_the_default_branch_again() {
    var store = dispatchStore(); if (!store) return
    var cards = dispatchCards()
    store.relaunchOpenFor(cards.m1, cards, relaunchOf())
    compare(store.openDispatch(cards.m1, cards), true)
    compare(store.dispatchForm.prefix, "old")
    compare(store.dispatchForm.base, "")
    reply(store.dispatchDefaultsRunner.current, defaultsOk("main"), 0)
    compare(store.dispatchForm.base, "main", "the relaunch's base override is not inherited")
  }
```

(`Runs` is the test file's existing `import "../../../core/domain/runs.js" as Runs`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/run.sh tst_run_store`
Expected: FAIL lines for all 11 new tests — each calls `store.relaunchOpenFor`, which does not exist yet, so each fails with `TypeError: Property 'relaunchOpenFor' of object ... is not a function`; the script prints those `TypeError` lines and `Totals` with 11 failures.

- [ ] **Step 3: Write the implementation**

In `core/stores/RunStore.qml`, find the end of the dispatch section:

```qml
  // A start runner's work is over: it leaves dispatchStartRunners and is destroyed.
  function dropStartRunner(runner) {
    dispatchBook.runners = dispatchBook.runners.filter(function(r) { return r !== runner })
    if (dispatchBook.startRunner === runner) dispatchBook.startRunner = null
    runner.destroy()
  }

  // The one list snapshot in flight (requestSnapshot). No guard: its reply is
```

Insert between `dropStartRunner`'s closing `}` and the blank line before `// The one list snapshot in flight`:

```qml

  // ---- relaunch

  // Opens the dispatch for card as openDispatch does and returns its result;
  // when it opens, relaunch.prefix and relaunch.base (Runs.stopReport's
  // relaunch), each when a non-blank string, are set trimmed over the
  // defaults, and a base set so is kept over the default branch. Refused
  // (false, nothing changes) when card or relaunch is not an object.
  function relaunchOpenFor(card, cardMap, relaunch) {
    var isObject = function(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
    if (!isObject(card) || !isObject(relaunch)) return false
    if (!store.openDispatch(card, cardMap)) return false
    if (typeof relaunch.prefix === "string" && relaunch.prefix.trim() !== "")
      store.dispatchForm = store.withField(store.dispatchForm, "prefix", relaunch.prefix.trim())
    if (typeof relaunch.base === "string" && relaunch.base.trim() !== "") {
      store.dispatchForm = store.withField(store.dispatchForm, "base", relaunch.base.trim())
      dispatchBook.baseTouched = true
    }
    return true
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run.sh tst_run_store`
Expected: `Totals: … 0 failed`, no FAIL lines, no TypeError/ReferenceError lines.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: pytest passes (including `tests/architecture`), every QML file prints `Totals: … 0 failed`, exit status 0.

Run: `grep -n "^import" core/stores/RunStore.qml`
Expected: the same imports as before (QtQml, Quickshell, Quickshell.Io, `../domain` files only) — nothing added.

- [ ] **Step 6: Commit**

```bash
git add core/stores/RunStore.qml tests/core/stores/tst_run_store.qml
git commit -m "feat(runs): relaunchOpenFor opens the dispatch with the run's recorded prefix and base"
```
<!-- task-pipeline: validated -->
