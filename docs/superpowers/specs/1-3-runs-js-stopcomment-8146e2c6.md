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
