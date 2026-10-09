# 1.3 runs.js: stopComment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new pure `stopComment(comments, runId)` in `core/domain/runs.js` that finds am's note for a run among one card's comments and returns it as a fresh `{createdAt, kind, fields}`, or `null`.

**Architecture:** One function, its private helpers and five private vars are added to the end of the existing `// ---- Why it stopped (RR 1.2)` section of `core/domain/runs.js`: after `stopReport` and before `// ---- Run alerts (S2 1.2)`. The code splits the body into trimmed, non-blank lines (`_noteLinesOf`), checks author and the last line's `am-key: <runId>/` with a plain `indexOf` (`_noteLinesFor`), then reads the kind from the first line (`_noteKindOf`) and the four fields from the middle lines (`_noteFieldsOf`). It reuses `_isObject`, `_stringOr` and `_textOf`. Tests go first, in a new section `// ---- RR 1.3: am's note` at the end of `tests/core/domain/tst_runs.qml`.

**Tech Stack:** QML/JS (`.pragma library`, ES5 style: `var`/`function`), QtTest via `qmltestrunner`, run by `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/1-3-runs-js-stopcomment-8146e2c6.md`, copied in full below. It is narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md`.

---

# 1.3 runs.js: stopComment (card 8146e2c6)

Narrowed from `docs/superpowers/specs/2026-10-05-resume-recover-design.md` (the "resume and
recover" design, here **RR**): the real comment bodies in "Today" (lines 57-72), the
"am's note" bullet of "Why it stopped (Run detail)" (lines 149-155), the "Architecture"
bullet `stopComment` (lines 249-252), the "am has not posted its comment yet" edge case
(line 295), "Testing" bullet 1 (lines 307-308) and "Limits" (lines 329-330). Parent story
7d1f5810. Blocked by 9a37bb47 (1.2, `stopReport`), which is merged on this branch
(`2e02266`, `ee8bf0c`).

## Starting point

- `core/domain/runs.js` is a `.pragma library` file: pure, never throws, `var` / `function`
  only, private names prefixed `_`, one contract-only comment above each function. Helpers
  this card may reuse: `_isObject`, `_arrayOr`, `_stringOr` (`runs.js:174-176`), `_textOf`
  (`runs.js:470`: `null`/`undefined` → `""`, else `String(v).trim()`).
- `stopReport(run)` ends at `runs.js:1176`; `// ---- Run alerts (S2 1.2)` starts at
  `runs.js:1177`.
- The comment shape is `ExtrasStore.commentsFor(cardId)` (`core/stores/ExtrasStore.qml:95`),
  built by `indexComments` (`core/domain/brd-extras.js:30-52`): an array, oldest first, of
  `{id, entityId, author, body, createdAt}`, every field a string. Equal timestamps keep
  export order, so array order is the authority on "newest".
- Nothing in the repo reads `am-key` yet; there is no `stopComment`.
- The `·` separator is written `·` in `runs.js` source (as at `runs.js:1515-1530`).

## Scope

One new function `stopComment(comments, runId)` (plus any `_`-prefixed private helpers it
needs) appended to the `// ---- Why it stopped` section, after `stopReport` and before
`// ---- Run alerts`. Tests in `tests/core/domain/tst_runs.qml`. Tests first.

Constraints (inherited):

- `runs.js` is a hot file: the diff is the new function and its helpers only (RR 236-237).
- File style and layering (`docs/architecture.md`; `tests/architecture` must pass): no new
  import, no UI import, no glyph literals (write `·`), comments state the contract only.
- Pure: no I/O, no events; never throws; never mutates its inputs; the result is a fresh
  object with a fresh `fields` array (RR 249-252).
- `runId` is compared as a plain string prefix (no RegExp built from it), so ids holding
  regex metacharacters behave like any other id.

### Out of scope

Owned by sibling cards: choosing which card's comments to read (the escalated subtask's
card, else the milestone card's `run-end` note, RR 149-151), fetching comments or
`ExtrasStore` changes, `StopReasonBlock` and its rendering of the note (`am's note · <time>`,
time formatting), `RunDetailScreen` wiring, the store's attempt choice, `runs-logs.py`,
the resume dialog, relaunch, and docs. No file under `ui/`, `core/stores/` or
`core/backend/` changes. Lines of the comment other than the four named keys (for example
`phase:` or `escalated:`) are not returned; multi-line values are not joined. Every
existing function in `runs.js` keeps its behaviour.

## Behaviour

`stopComment(comments, runId)` returns am's note for run `runId` from one card's comments,
or `null`.

### Matching

Let `id` be `_textOf(runId)` when `runId` is a string, else `""`. If `id` is `""` or
`comments` is not an array, the result is `null`.

Walk `comments` from the last entry to the first; the result comes from the first entry
(that is, the newest) that matches. An entry matches when all hold:

1. It is an object (`_isObject`).
2. `author` is a string whose trimmed value is exactly `am` (case-sensitive).
3. `body` is a string. Split it into lines on `\n`; strip a trailing `\r` and surrounding
   whitespace from each line; drop blank lines. At least one line remains.
4. The last remaining line starts with `am-key: ` and the text after that prefix starts
   with `id + "/"`. The `/` is required, so a run id that is a prefix of another run's id
   (`…-4a51d6` vs `…-4a51d663`) does not match.

An entry failing any rule is skipped and the walk continues to older entries; a newer
non-matching entry never hides an older matching one.

### Result

A fresh `{createdAt, kind, fields}`:

- `createdAt`: the entry's `createdAt` when it is a string, else `""`; passed through
  verbatim (no parsing or formatting).
- `kind`: if the first remaining line starts with `am · ` (`"am · "`), the text after
  that prefix up to the next ` · ` (or the line's end), trimmed; else `""`. So
  `am · escalated · run X` → `escalated`, `am · base failed · run X` → `base failed`
  (two words kept), `am · done · run X` → `done`.
- `fields`: an array of `{key, value}` in the fixed order `reason`, `detail`, `next`, `why`
  (not body order). For each key, the first remaining line, other than the first and the
  last, that starts with `<key>:` gives `value`: the rest of that line with every backtick
  removed, then trimmed. A key with no such line, or whose value is `""`, is omitted. Later
  duplicate lines of the same key are ignored. Keys match case-sensitively at the line's
  start, so `phase:`, `escalated:`, `am-key:` and `Reason:` are never fields, and
  `nextstep:` is not `next` (the key is followed directly by `:`).

### Real bodies (fixtures for the tests)

`SUBTASK_BODY` (RR 62-68, `…` kept literally as in RR; run `R = "20261004T165007Z-4a51d663"`):

```
am · escalated · run 20261004T165007Z-4a51d663
phase: verify
detail: VerifyError: could not run none (CLAUDE.md: …)
next: `am resume 20261004T165007Z-4a51d663`
why: `am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify`
am-key: 20261004T165007Z-4a51d663/5bfe746d-…/escalated:cef56efb…
```

→ `{kind: "escalated", fields: [{key: "detail", value: "VerifyError: could not run none (CLAUDE.md: …)"},
{key: "next", value: "am resume 20261004T165007Z-4a51d663"},
{key: "why", value: "am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify"}]}`.

`RUN_END_BODY` (RR 71-72 describes it line by line; the test assembles it, marked
`// synthetic: assembled from RR 71-72`), milestone id `M = "76043cd6-2077-47d4-afbb-c0ab60e62416"`:

```
am · escalated · run 20261004T165007Z-4a51d663
escalated: [[5bfe746d-8ac3-41c4-8e3e-abb939e0b45a]] at verify
next: `am resume 20261004T165007Z-4a51d663`
am-key: 20261004T165007Z-4a51d663/76043cd6-2077-47d4-afbb-c0ab60e62416/run-end:0a1b2c3d
```

→ `{kind: "escalated", fields: [{key: "next", value: "am resume 20261004T165007Z-4a51d663"}]}`.

`DONE_BODY` (synthetic: a later note of the same run):

```
am · done · run 20261004T165007Z-4a51d663
am-key: 20261004T165007Z-4a51d663/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/done:9f9f9f9f
```

→ `{kind: "done", fields: []}`.

## Error paths

- `comments` not an array (`undefined`, `null`, `0`, `"x"`, `{}`, `true`) → `null`.
- `runId` not a string, `""`, or only whitespace (`undefined`, `null`, `42`, `{}`, `"  "`)
  → `null` even when an am note exists.
- Entries that are `null`, numbers, strings, arrays, or objects whose `author` / `body` is
  missing or not a string → skipped, no throw.
- Bodies that are `""`, only blank lines, have no `am-key:` line, or have `am-key:` on a
  line that is not the last non-blank line → skipped.
- A body that is only the `am-key:` line → matches, `kind` `""`, `fields` `[]`.
- CRLF line endings, trailing blank lines and trailing spaces after `am-key:` do not stop a
  match.
- Inputs are never modified: `JSON.stringify(comments)` is the same before and after.

## Tests

Tier: QML unit tests in `tests/core/domain/tst_runs.qml` (TestCase `DomainRuns`), run by
`qmltestrunner` through `bash tests/run.sh` (fast loop: `bash tests/run.sh tst_runs`).
`stopComment` is a pure function of a `.pragma library` file with no I/O, so the domain
unit tier is the right and only tier (RR 307-308); there is no consumer in this card, so no
store, backend or UI test. New tests go in a new section `// ---- RR 1.3: am's note` at the
end of the file, named `test_stopComment_<case>`. Comments are built with a local helper
`comment(author, body, createdAt)` returning `{id, entityId, author, body, createdAt}`;
bodies are the three above joined with `"\n"`.

1. **Subtask escalation** — `[comment("am", SUBTASK_BODY, "2026-10-04T17:45:00Z")]`, `R` →
   exactly the result above, `createdAt` `2026-10-04T17:45:00Z`,
   `Object.keys(result).sort()` `["createdAt", "fields", "kind"]`.
2. **Milestone run-end** — `[comment("am", RUN_END_BODY, …)]`, `R` → the result above; the
   `escalated:` line is not a field.
3. **Newest wins** — `[subtask note, DONE_BODY note]` → `kind` `done`, `fields` `[]`, the
   done note's `createdAt`; reversed order → the subtask note.
4. **Another run ignored** — the subtask note followed by a newer am note whose `am-key` is
   `20261004T170000Z-ffffffff/…` → the subtask note; with `runId`
   `20261004T170000Z-ffffffff` → the other note; with an unknown run id → `null`.
5. **Run-id prefix not a match** — an am note keyed `20261004T165007Z-4a51d663/…` asked for
   `20261004T165007Z-4a51d6` → `null`; a note whose `am-key` is exactly `R` with no `/` →
   `null`.
6. **Non-am author ignored** — a newer comment by `paulo` (and by `AM`, and `am-bot`) with
   the subtask body → the older am note; only non-am comments → `null`. A padded author
   `" am "` matches.
7. **No am-key ignored** — a newer am comment whose body is `SUBTASK_BODY` without its last
   line → the older note; `am-key:` on a middle line followed by another line → skipped.
8. **Field order and backticks** — synthetic body with lines in the order `why:`, `next:`,
   `reason: \`tests\` do not cover the empty list`, `detail:` → `fields` keys
   `reason, detail, next, why`, `reason` value `tests do not cover the empty list`; a
   duplicate `next:` line → the first; an empty `reason:` → omitted; `Reason:` and
   `nextstep:` → not fields.
9. **Kind shapes** — first lines `am · base failed · run R` → `base failed`,
   `am · cancelled · run R` → `cancelled`, `am · done` (no further separator) → `done`,
   a first line not starting with `am · ` → `""`; a body that is only the `am-key:` line →
   `kind` `""`, `fields` `[]`.
10. **Line endings** — `SUBTASK_BODY` joined with `"\r\n"`, plus trailing `"\n\n  "` and a
    trailing space after the am-key → the same result as test 1.
11. **Garbage** — `comments` `undefined`, `null`, `0`, `"x"`, `{}`, `true` → `null`; `runId`
    `undefined`, `null`, `42`, `{}`, `""`, `"  "` with a valid note → `null`; entries
    `[null, 3, "x", [], {}, {author: "am"}, {author: "am", body: 7}, {author: 5, body: SUBTASK_BODY},
    {author: "am", body: ""}, {author: "am", body: "\n \n"}]` → `null`, no throw; the same
    list followed by a valid note → that note; a valid note with `createdAt: 5` → `createdAt`
    `""`.
12. **Fresh and untouched** — two calls give results that are not the same object and whose
    `fields` arrays are distinct; mutating one result leaves the next call's unchanged;
    `JSON.stringify(comments)` is unchanged by the call.
13. **Regex metacharacters in the id** — a note keyed `a.b*c/x` matches `runId` `a.b*c` and
    not `aXbbc`.

## Hand-off to the planner

One task (one function, one test cycle; splitting would leave a reviewer nothing to reject
independently): **Task 1: `stopComment`** — tests 1-13 first, then the function and its
private helpers (e.g. the line splitter, the am-key check, the kind and field readers)
after `stopReport`. Verification: `bash tests/run.sh` green (pytest, including
`tests/architecture`, then every `tst_*.qml`).

---

## Global Constraints

- Change only `core/domain/runs.js` and `tests/core/domain/tst_runs.qml`. No file under `ui/`, `core/stores/` or `core/backend/` changes.
- The `runs.js` diff is the new function, its helpers and their private vars only, inserted between the closing `}` of `stopReport` and `// ---- Run alerts (S2 1.2)`. Every existing function keeps its behaviour.
- Style: `var`/`function` only, no `const`/`let`/arrow functions. Private names start with `_`. One contract-only comment above each function (no narrative). No new import, no UI import.
- No glyph literals in `runs.js`: the middle dot (U+00B7) is written as the six-character escape `\u00b7` (backslash, `u`, `00b7`), as at `runs.js:1515-1530`. Use the same escape in the tests. (The spec copy above shows the character itself where it means this escape.)
- Pure: no I/O, no events. Never throws. Never mutates its inputs. The result is a fresh object with a fresh `fields` array.
- `runId` is compared as a plain string prefix (`indexOf(id + "/") === 0`). Do not build a RegExp from it.
- Result keys, verbatim: `createdAt,fields,kind`. Field keys, in this fixed order: `reason`, `detail`, `next`, `why`. Each field is `{key, value}`.
- Author match: trimmed author `=== "am"` (case-sensitive). Key-line prefix, verbatim: `am-key: `. Kind prefix: `am · `; kind ends at ` · `.
- `tests/architecture` must pass (it runs inside `bash tests/run.sh`).
- Process safety: never use `pkill`/`killall`/pattern kills. Wrap long runs in `timeout`.

## Review Focus

1. **A padded run id.** RunStore may pass a run id with stray whitespace. `_textOf` trims it, so `"  " + R + " "` still finds the note. Pinned in `test_stopComment_garbage` ("a padded run id is trimmed").
2. **A key on the first line.** The first line is the headline, never a field, even if it reads `next: ...`. Then `kind` is `""` and `fields` is `[]`. Pinned in `test_stopComment_fields` ("a key on the first line").
3. **Extra spaces around the kind.** `am ·   done   · run R` gives kind `done`, not `"  done  "`. Pinned in `test_stopComment_kind` (case 3).
4. **A value made only of backticks.** `reason:  `` ` is empty once backticks are removed, so it is omitted, the same as an empty `reason:`. Pinned in `test_stopComment_fields` ("a reason of backticks only is omitted").
5. **Newer junk after the note.** Junk entries (including `undefined`) that come after a valid note must not hide it, since the walk goes newest first. Pinned in `test_stopComment_garbage` ("a note, then newer junk").

Already checked: no existing function or test named `stopComment`, `comment`, `checkNote` or `note*` exists in either file, and nothing in the repo reads `am-key` yet. The plan's code and tests were run in a scratch copy of this branch. Without the implementation, every `test_stopComment_*` fails with `Property 'stopComment' of object [object Object] is not a function`. With it, `tst_runs.qml` reports `Totals: 252 passed, 0 failed` and pytest (including `tests/architecture`) passes.

## Test commands

- Fast loop: `timeout 900 bash tests/run.sh domain/tst_runs`. This runs pytest (about 2 minutes), then only `tests/core/domain/tst_runs.qml`. Read the `== tests/core/domain/tst_runs.qml` block: its `FAIL!` lines, any `TypeError` line and the `Totals:` line.
- Full gate: `timeout 1800 bash tests/run.sh`. It must exit 0, with `0 failed` on every `Totals:` line.

---

### Task 1: `stopComment`

**Files:**
- Modify: `core/domain/runs.js` (insert after `stopReport`'s closing `}`, currently line 1175, before the two blank lines and `// ---- Run alerts (S2 1.2)` at line 1177)
- Test: `tests/core/domain/tst_runs.qml` (append a new section before the file's final `}`, currently line 4981)

**Interfaces:**
- Consumes (existing private helpers in `runs.js`): `_isObject(v)` (a non-null, non-array object), `_stringOr(v)` (`v` if a string, else `""`), `_textOf(v)` (`""` for null/undefined, else `String(v).trim()`, never throws).
- Produces: `stopComment(comments, runId)` → `null` or a fresh `{createdAt: string, kind: string, fields: Array<{key: string, value: string}>}`. Sibling cards (`StopReasonBlock`, `RunDetailScreen` wiring) call it as `Runs.stopComment(ExtrasStore.commentsFor(cardId), run.id)`.

- [ ] **Step 1: Write the failing tests**

Open `tests/core/domain/tst_runs.qml`. The file ends with the closing `}` of `test_stopReport_story_title_edges` and then the `TestCase`'s closing `}` on the last line. Insert the block below just before that last `}`, so it sits inside the `TestCase`, after `test_stopReport_story_title_edges`:

```qml
  // ---- RR 1.3: am's note -------------------------------------------------------------------

  readonly property string noteRun: "20261004T165007Z-4a51d663"
  readonly property string noteOtherRun: "20261004T170000Z-ffffffff"
  readonly property string noteAt: "2026-10-04T17:45:00Z"
  readonly property string noteLaterAt: "2026-10-04T18:00:00Z"

  // One card comment as ExtrasStore.commentsFor gives it.
  function comment(author, body, createdAt) {
    return { id: "c-" + createdAt, entityId: "5bfe746d-8ac3-41c4-8e3e-abb939e0b45a", author: author, body: body,
             createdAt: createdAt }
  }

  // SUBTASK_BODY's lines (RR 62-68, the ellipses kept as in RR).
  function noteSubtaskLines() {
    return ["am \u00b7 escalated \u00b7 run 20261004T165007Z-4a51d663",
            "phase: verify",
            "detail: VerifyError: could not run none (CLAUDE.md: …)",
            "next: `am resume 20261004T165007Z-4a51d663`",
            "why: `am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify`",
            "am-key: 20261004T165007Z-4a51d663/5bfe746d-…/escalated:cef56efb…"]
  }

  function noteSubtaskBody() { return noteSubtaskLines().join("\n") }

  // RUN_END_BODY. synthetic: assembled from RR 71-72
  function noteRunEndBody() {
    return ["am \u00b7 escalated \u00b7 run 20261004T165007Z-4a51d663",
            "escalated: [[5bfe746d-8ac3-41c4-8e3e-abb939e0b45a]] at verify",
            "next: `am resume 20261004T165007Z-4a51d663`",
            "am-key: 20261004T165007Z-4a51d663/76043cd6-2077-47d4-afbb-c0ab60e62416/run-end:0a1b2c3d"].join("\n")
  }

  // DONE_BODY. synthetic: a later note of the same run
  function noteDoneBody() {
    return ["am \u00b7 done \u00b7 run 20261004T165007Z-4a51d663",
            "am-key: 20261004T165007Z-4a51d663/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/done:9f9f9f9f"].join("\n")
  }

  // The note stopComment reads from SUBTASK_BODY, posted at createdAt.
  function noteSubtaskWant(createdAt) {
    return { createdAt: createdAt, kind: "escalated", fields: [
      { key: "detail", value: "VerifyError: could not run none (CLAUDE.md: …)" },
      { key: "next", value: "am resume 20261004T165007Z-4a51d663" },
      { key: "why", value: "am logs 20261004T165007Z-4a51d663 5bfe746d-… --phase verify" }] }
  }

  // got is the note want describes: exactly the keys createdAt, fields and kind,
  // with want's values (fields compared in order); or both are null.
  function checkNote(got, want, label) {
    if (want === null) { compare(got, null, label); return }
    verify(got !== null && typeof got === "object", label + ": an object")
    compare(Object.keys(got).sort().join(","), "createdAt,fields,kind", label + ": keys")
    compare(got.createdAt, want.createdAt, label + ": createdAt")
    compare(got.kind, want.kind, label + ": kind")
    verify(Array.isArray(got.fields), label + ": fields is an array")
    compare(JSON.stringify(got.fields), JSON.stringify(want.fields), label + ": fields")
  }

  function test_stopComment_subtask_escalation() {
    checkNote(Runs.stopComment([comment("am", noteSubtaskBody(), noteAt)], noteRun), noteSubtaskWant(noteAt), "subtask note")
  }

  function test_stopComment_milestone_run_end() {
    checkNote(Runs.stopComment([comment("am", noteRunEndBody(), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: [{ key: "next", value: "am resume 20261004T165007Z-4a51d663" }] },
              "run-end note, its escalated: line is not a field")
  }

  function test_stopComment_newest_wins() {
    var sub = comment("am", noteSubtaskBody(), noteAt)
    var done = comment("am", noteDoneBody(), noteLaterAt)
    checkNote(Runs.stopComment([sub, done], noteRun), { createdAt: noteLaterAt, kind: "done", fields: [] }, "the done note is newer")
    checkNote(Runs.stopComment([done, sub], noteRun), noteSubtaskWant(noteAt), "array order, not createdAt, says newest")
  }

  function test_stopComment_other_run() {
    var sub = comment("am", noteSubtaskBody(), noteAt)
    // synthetic: a newer note of another run on the same card
    var other = comment("am", ["am \u00b7 escalated \u00b7 run " + noteOtherRun,
                               "next: `am resume " + noteOtherRun + "`",
                               "am-key: " + noteOtherRun + "/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/escalated:11111111"].join("\n"),
                        noteLaterAt)
    var list = [sub, other]
    checkNote(Runs.stopComment(list, noteRun), noteSubtaskWant(noteAt), "the other run's newer note is skipped")
    checkNote(Runs.stopComment(list, noteOtherRun),
              { createdAt: noteLaterAt, kind: "escalated", fields: [{ key: "next", value: "am resume " + noteOtherRun }] },
              "asked for the other run")
    compare(Runs.stopComment(list, "20261004T999999Z-00000000"), null, "an unknown run")
  }

  function test_stopComment_run_id_prefix() {
    compare(Runs.stopComment([comment("am", noteSubtaskBody(), noteAt)], "20261004T165007Z-4a51d6"), null,
            "a prefix of the note's run id")
    // synthetic: the am-key is the run id with no "/"
    var bare = comment("am", "am \u00b7 done \u00b7 run " + noteRun + "\nam-key: " + noteRun, noteAt)
    compare(Runs.stopComment([bare], noteRun), null, "no slash after the run id")
  }

  function test_stopComment_author() {
    var am = comment("am", noteSubtaskBody(), noteAt)
    var others = ["paulo", "AM", "am-bot"]
    for (var i = 0; i < others.length; i++) {
      checkNote(Runs.stopComment([am, comment(others[i], noteSubtaskBody(), noteLaterAt)], noteRun), noteSubtaskWant(noteAt),
                "a newer comment by " + others[i])
    }
    compare(Runs.stopComment([comment("paulo", noteSubtaskBody(), noteAt), comment("AM", noteDoneBody(), noteLaterAt)], noteRun),
            null, "only non-am comments")
    checkNote(Runs.stopComment([comment(" am ", noteSubtaskBody(), noteAt)], noteRun), noteSubtaskWant(noteAt), "a padded author")
  }

  function test_stopComment_no_am_key() {
    var am = comment("am", noteSubtaskBody(), noteAt)
    var keyless = noteSubtaskLines()
    keyless.pop()
    checkNote(Runs.stopComment([am, comment("am", keyless.join("\n"), noteLaterAt)], noteRun), noteSubtaskWant(noteAt),
              "a newer am comment with no am-key line")
    // synthetic: a line after the am-key
    var middle = noteSubtaskLines()
    middle.push("note: written after the key")
    checkNote(Runs.stopComment([am, comment("am", middle.join("\n"), noteLaterAt)], noteRun), noteSubtaskWant(noteAt),
              "am-key on a middle line")
    compare(Runs.stopComment([comment("am", middle.join("\n"), noteLaterAt)], noteRun), null, "am-key not last, alone")
  }

  function test_stopComment_fields() {
    // synthetic: fields out of order, a duplicate next, look-alike keys
    var key = "am-key: " + noteRun + "/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/escalated:22222222"
    var lines = ["am \u00b7 escalated \u00b7 run " + noteRun,
                 "why: `am logs " + noteRun + "`",
                 "next: `am resume " + noteRun + "`",
                 "reason: `tests` do not cover the empty list",
                 "detail: VerifyError: boom",
                 "next: something else",
                 "Reason: capitalised",
                 "nextstep: not a field",
                 "phase: verify",
                 key]
    var want = [{ key: "reason", value: "tests do not cover the empty list" }, { key: "detail", value: "VerifyError: boom" },
                { key: "next", value: "am resume " + noteRun }, { key: "why", value: "am logs " + noteRun }]
    checkNote(Runs.stopComment([comment("am", lines.join("\n"), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: want }, "fixed order, first of each key, backticks removed")

    // synthetic: an empty reason and one made only of backticks
    var empty = lines.slice()
    empty[3] = "reason:"
    checkNote(Runs.stopComment([comment("am", empty.join("\n"), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: want.slice(1) }, "an empty reason is omitted")
    empty[3] = "reason:  `` "
    checkNote(Runs.stopComment([comment("am", empty.join("\n"), noteAt)], noteRun),
              { createdAt: noteAt, kind: "escalated", fields: want.slice(1) }, "a reason of backticks only is omitted")

    // synthetic: a key on the first line is not a field
    checkNote(Runs.stopComment([comment("am", "next: `am resume " + noteRun + "`\n" + key, noteAt)], noteRun),
              { createdAt: noteAt, kind: "", fields: [] }, "a key on the first line")
  }

  function test_stopComment_kind() {
    var key = "am-key: " + noteRun + "/5bfe746d-8ac3-41c4-8e3e-abb939e0b45a/escalated:33333333"
    var cases = [["am \u00b7 base failed \u00b7 run " + noteRun, "base failed"],
                 ["am \u00b7 cancelled \u00b7 run " + noteRun, "cancelled"],
                 ["am \u00b7 done", "done"],
                 ["am \u00b7   done   \u00b7 run " + noteRun, "done"],
                 ["note \u00b7 escalated \u00b7 run " + noteRun, ""]]
    for (var i = 0; i < cases.length; i++) {
      checkNote(Runs.stopComment([comment("am", cases[i][0] + "\n" + key, noteAt)], noteRun),
                { createdAt: noteAt, kind: cases[i][1], fields: [] }, "first line " + i)
    }
    checkNote(Runs.stopComment([comment("am", key, noteAt)], noteRun), { createdAt: noteAt, kind: "", fields: [] },
              "only the am-key line")
  }

  function test_stopComment_line_endings() {
    var body = noteSubtaskLines().join("\r\n") + " \r\n\n  "
    checkNote(Runs.stopComment([comment("am", body, noteAt)], noteRun), noteSubtaskWant(noteAt), "CRLF and trailing blanks")
  }

  function test_stopComment_garbage() {
    var valid = comment("am", noteSubtaskBody(), noteAt)
    var badComments = [undefined, null, 0, "x", {}, true]
    for (var i = 0; i < badComments.length; i++) compare(Runs.stopComment(badComments[i], noteRun), null, "comments " + i)
    var badIds = [undefined, null, 42, {}, "", "  "]
    for (var j = 0; j < badIds.length; j++) compare(Runs.stopComment([valid], badIds[j]), null, "runId " + j)
    checkNote(Runs.stopComment([valid], "  " + noteRun + " "), noteSubtaskWant(noteAt), "a padded run id is trimmed")

    var junk = [undefined, null, 3, "x", [], {}, { author: "am" }, { author: "am", body: 7 },
                { author: 5, body: noteSubtaskBody() }, { author: "am", body: "" }, { author: "am", body: "\n \n" }]
    compare(Runs.stopComment(junk, noteRun), null, "only junk")
    checkNote(Runs.stopComment(junk.concat([valid]), noteRun), noteSubtaskWant(noteAt), "junk, then a note")
    checkNote(Runs.stopComment([valid].concat(junk), noteRun), noteSubtaskWant(noteAt), "a note, then newer junk")

    var noTime = comment("am", noteSubtaskBody(), noteAt)
    noTime.createdAt = 5
    checkNote(Runs.stopComment([noTime], noteRun), noteSubtaskWant(""), "a non-string createdAt")
  }

  function test_stopComment_fresh_and_untouched() {
    var list = [comment("am", noteSubtaskBody(), noteAt)]
    var before = JSON.stringify(list)
    var a = Runs.stopComment(list, noteRun)
    var b = Runs.stopComment(list, noteRun)
    verify(a !== b, "two calls, two objects")
    verify(a.fields !== b.fields, "two calls, two fields arrays")
    verify(a.fields[0] !== b.fields[0], "two calls, two field objects")
    a.kind = "changed"
    a.fields[0].value = "changed"
    a.fields.push({ key: "reason", value: "added" })
    checkNote(Runs.stopComment(list, noteRun), noteSubtaskWant(noteAt), "mutating a result leaves the next call alone")
    compare(JSON.stringify(list), before, "the comments are untouched")
  }

  function test_stopComment_regex_id() {
    // synthetic: a run id holding regex metacharacters
    var c = comment("am", "am \u00b7 done \u00b7 run a.b*c\nam-key: a.b*c/x", noteAt)
    checkNote(Runs.stopComment([c], "a.b*c"), { createdAt: noteAt, kind: "done", fields: [] }, "metacharacters match themselves")
    compare(Runs.stopComment([c], "aXbbc"), null, "the id is not a pattern")
  }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 900 bash tests/run.sh domain/tst_runs`
Expected: pytest passes. Under `== tests/core/domain/tst_runs.qml`, each of the 13 `test_stopComment_*` tests prints a `FAIL!` line with `Uncaught exception: Property 'stopComment' of object [object Object] is not a function`. The `Totals:` line reads `239 passed, 13 failed`. Every other test still passes.

- [ ] **Step 3: Write the implementation**

Open `core/domain/runs.js`. Find the end of `stopReport` (its `return { ... }` ends with `relaunch: _relaunchOf(run)`, then `  }`, then `}`). Leave the two blank lines that come before `// ---- Run alerts (S2 1.2) ---...` where they are. Between `stopReport`'s closing `}` and those two blank lines, insert this block. It starts with one blank line and must not end with a trailing blank line:

```js

var _NOTE_AUTHOR = "am"
var _NOTE_KEY_PREFIX = "am-key: "
var _NOTE_KIND_PREFIX = "am \u00b7 "
var _NOTE_SEPARATOR = " \u00b7 "
var _NOTE_FIELD_KEYS = ["reason", "detail", "next", "why"]

// A note body's lines: split on "\n", each trimmed (a trailing "\r" with it),
// blank lines dropped.
function _noteLinesOf(body) {
  var parts = body.split("\n")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var line = parts[i].trim()
    if (line !== "") out.push(line)
  }
  return out
}

// The body lines of entry when it is am's note for run id: an object whose
// trimmed author is "am" and whose string body's last line is
// "am-key: <id>/..."; else null.
function _noteLinesFor(entry, id) {
  if (!_isObject(entry) || typeof entry.author !== "string" || entry.author.trim() !== _NOTE_AUTHOR) return null
  if (typeof entry.body !== "string") return null
  var lines = _noteLinesOf(entry.body)
  if (lines.length === 0) return null
  var last = lines[lines.length - 1]
  if (last.indexOf(_NOTE_KEY_PREFIX) !== 0) return null
  return last.substring(_NOTE_KEY_PREFIX.length).indexOf(id + "/") === 0 ? lines : null
}

// The kind a note's first line names: after "am \u00b7 ", up to the next " \u00b7 " or
// the line's end, trimmed; "" when the line does not start with "am \u00b7 ".
function _noteKindOf(first) {
  if (first.indexOf(_NOTE_KIND_PREFIX) !== 0) return ""
  var rest = first.substring(_NOTE_KIND_PREFIX.length)
  var end = rest.indexOf(_NOTE_SEPARATOR)
  return (end >= 0 ? rest.substring(0, end) : rest).trim()
}

// A fresh [{key, value}] in _NOTE_FIELD_KEYS order: for each key, the first
// line other than the first and the last that starts with "<key>:", its rest
// with every backtick removed, trimmed. Keys with no line or an empty value
// are left out.
function _noteFieldsOf(lines) {
  var out = []
  for (var k = 0; k < _NOTE_FIELD_KEYS.length; k++) {
    var key = _NOTE_FIELD_KEYS[k]
    for (var i = 1; i < lines.length - 1; i++) {
      if (lines[i].indexOf(key + ":") !== 0) continue
      var value = lines[i].substring(key.length + 1).split("`").join("").trim()
      if (value !== "") out.push({ key: key, value: value })
      break
    }
  }
  return out
}

// am's note for run runId among one card's comments (oldest first, as
// ExtrasStore.commentsFor gives them): a fresh {createdAt, kind, fields} from
// the newest entry by author "am" whose last body line is
// "am-key: <runId>/...", else null. null when comments is not an array or
// runId, trimmed, is not a non-empty string. Never mutates its inputs.
function stopComment(comments, runId) {
  var id = typeof runId === "string" ? _textOf(runId) : ""
  if (id === "" || !Array.isArray(comments)) return null
  for (var i = comments.length - 1; i >= 0; i--) {
    var lines = _noteLinesFor(comments[i], id)
    if (lines === null) continue
    return { createdAt: _stringOr(comments[i].createdAt), kind: _noteKindOf(lines[0]), fields: _noteFieldsOf(lines) }
  }
  return null
}
```

Notes for the implementer:
- `line.trim()` also removes a trailing `"\r"`, so CRLF bodies need no extra handling.
- The am-key test is `last.substring(8).indexOf(id + "/") === 0`. The required `/` stops a run id from matching a longer run id that starts with it. `indexOf` does no pattern matching, so `a.b*c` is matched literally.
- `_noteFieldsOf` stops at the first line for each key (`break`) even when that line's value is empty. That is how a later duplicate is ignored. Lines 0 and `length - 1` (the headline and the am-key) are never read as fields.
- `createdAt` passes through `_stringOr` verbatim (no parsing).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash tests/run.sh domain/tst_runs`
Expected: pytest passes. Under `== tests/core/domain/tst_runs.qml`, there is no `FAIL!` or `TypeError` line, and the totals read `Totals: 252 passed, 0 failed, 0 skipped, 0 blacklisted`.

- [ ] **Step 5: Run the full gate**

Run: `timeout 1800 bash tests/run.sh`
Expected: exit code 0. pytest passes, including `tests/architecture` (layers and icon glyphs). Every `Totals:` line shows `0 failed`.

- [ ] **Step 6: Check the diff stays in scope**

Run: `git diff --stat`
Expected: exactly two files, `core/domain/runs.js` and `tests/core/domain/tst_runs.qml`. Then run `git diff core/domain/runs.js` and confirm it only adds lines (no `-` lines) between `stopReport` and `// ---- Run alerts (S2 1.2)`, and that it contains no literal `·` (run `git diff core/domain/runs.js | grep -c '·'`, expected `0`).

- [ ] **Step 7: Commit**

```bash
git add core/domain/runs.js tests/core/domain/tst_runs.qml
git commit -m "feat(runs): stopComment reads am's note for a run from a card's comments"
```

---

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| Matching rules 1-4 (object, author `am` trimmed, string body split/trimmed/non-blank, last line `am-key: <id>/`) | `_noteLinesFor`, `_noteLinesOf`; tests 5, 6, 7, 11, 13 |
| Walk newest first; a non-matching newer entry never hides an older match | `stopComment` loop with `continue`; tests 3, 4, 6, 7, 11 |
| `id` from `_textOf` on a string only; `""` → null; non-array comments → null | `stopComment` first two lines; test 11 |
| `createdAt` verbatim string, else `""` | `_stringOr(comments[i].createdAt)`; tests 1, 11 |
| `kind` from `am · ` to next ` · `, trimmed, else `""` | `_noteKindOf`; tests 1, 2, 3, 9 |
| `fields` fixed order, first line per key excluding first/last line, backticks removed, trimmed, empty omitted, case-sensitive `key:` | `_noteFieldsOf`; tests 1, 2, 8 |
| Real bodies SUBTASK / RUN_END / DONE and their results | `noteSubtaskLines`, `noteRunEndBody`, `noteDoneBody`; tests 1, 2, 3 |
| Error paths: garbage comments, runIds and entries; empty/blank bodies; key not last; only-key body; CRLF/trailing blanks/space; inputs untouched | tests 7, 9, 10, 11, 12 |
| Fresh result and fresh `fields` | object and array literals built per call; test 12 |
| Plain string prefix, no RegExp | `indexOf`; test 13 |
| Placement after `stopReport`, before `// ---- Run alerts`; `\u00b7` escapes; one contract comment per function | Step 3; Step 6 |
| Tests in new section `// ---- RR 1.3: am's note`, named `test_stopComment_<case>`, `comment(author, body, createdAt)` helper | Step 1 |
| Verification `bash tests/run.sh` green | Steps 4, 5 |

Spec test → plan test: 1 `subtask_escalation`, 2 `milestone_run_end`, 3 `newest_wins`, 4 `other_run`, 5 `run_id_prefix`, 6 `author`, 7 `no_am_key`, 8 `fields`, 9 `kind`, 10 `line_endings`, 11 `garbage`, 12 `fresh_and_untouched`, 13 `regex_id`.

Placeholder scan: none. Type consistency: `stopComment`, `_noteLinesOf`, `_noteLinesFor`, `_noteKindOf`, `_noteFieldsOf`, `_NOTE_*` are named the same in the code, the notes and the tests.
<!-- task-pipeline: validated -->
