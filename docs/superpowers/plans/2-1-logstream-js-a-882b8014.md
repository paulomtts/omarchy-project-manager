# 2.1 `logStream.js`: a bounded, sanitized line buffer — spec

Card `882b8014-9bf0-4a04-885f-7498e6b1dd6b`, subtask of story `674c29f7-7a71-4dd8-9fc9-683eb7c53d90`
(Live run output). Parent design: `docs/superpowers/specs/2026-10-05-live-output-design.md`
(below: **LO**).

## Purpose

A new pure domain module, `core/domain/logStream.js`, turns the JSON lines that
`runs-logs-follow.py` prints (am's hello, chunk and end lines, or one refusal envelope) into a
bounded buffer of display lines, and renders that buffer as the text the output pane shows.
The later `RunOutputStore` (a sibling card) calls `foldLine` once per stdout line and shows
`bufferText`; it resumes with the buffer's `nextOffset`. This card builds the module and its
test file only.

## Starting point

Nothing exists: no `core/domain/logStream.js`, no `tests/core/domain/tst_log_stream.qml`, no
reference to `logStream` outside `docs/`. The recorded fixtures already exist:
`tests/fixtures/am/logs-follow-agent.jsonl`, `logs-follow-step.jsonl` (three lines each: hello,
one chunk, end) and `logs-follow-refusal.json` (one object).

## Inherited constraints

| constraint | source |
|---|---|
| `core/domain/logStream.js` is pure and never throws. | LO line 137 |
| `sanitize(text)`: removes ANSI CSI (`ESC [ … final`), OSC (`ESC ] … BEL\|ESC \`) and other `ESC` sequences; `\r\n` → `\n`; a lone `\r` keeps only what follows it on that line (a progress bar's last frame); drops every other C0 control except `\t` and `\n`, and DEL; U+FFFD kept. | LO lines 139-142 |
| `utf8Length(text)`: the UTF-8 byte length (for the resume offset). | LO line 143 |
| `emptyBuffer(maxLines)`: `{lines: [], partial: "", dropped: 0, nextOffset: 0, gapBytes: 0, maxLines}`; a bad `maxLines` is 1000. | LO lines 144-145 |
| `foldLine(buffer, line)` → `{buffer, kind}`, kind `hello \| chunk \| end \| refusal \| ignored`; chunk sanitized, joined to `partial`, split on `\n`; complete lines appended, the unterminated tail stays `partial`; a line over 2000 characters cut to 2000 plus `…`; lines beyond `maxLines` dropped from the front and counted in `dropped`; a chunk whose `offset` is below `nextOffset` ignored; one above adds the gap to `gapBytes` and a `[… N bytes not shown]` line; `nextOffset` becomes `offset + utf8Length(text)`; a hello sets `nextOffset` to its `offset` when the buffer is empty. | LO lines 146-153 |
| `bufferText(buffer)`: the lines plus `partial`, prefixed with `… N earlier lines` when `dropped > 0`. | LO lines 154-155 |
| Stream shapes: hello `{"event":"logs","offset":B,"path":…,"schema":1}`; chunk `{"offset":O,"text":T}`, contiguous, `O` the byte position of the first byte; end `{"event":"end","status":S}`; a refusal is one `{"ok":false,"error":{type,message}}`; only a refusal has an `ok` key; keys are additive, unknown keys ignored; the plugin never reads `path`. | LO lines 52-64, 70 |
| The resume offset may overcount after U+FFFD; the next chunk's `offset` is exact. | LO lines 67-68 |
| The helper re-emits am's lines as parsed JSON objects, never altered; its own failures are `{"ok":false,"error":{…}}` lines. | LO lines 120-127 |
| A very long output holds 1000 lines and shows `… N earlier lines`. | LO line 225 |
| Tests in `tests/core/domain/tst_log_stream.qml`: `sanitize` (CSI, OSC, `\r\n`, lone `\r`, C0, U+FFFD kept), `utf8Length`, `foldLine` for every kind, partial lines across chunks, the cap and `dropped`, long-line cut, duplicate and gap offsets, the fixtures. | LO lines 237-239; card |
| A domain file starts with `.pragma library`, may `.import` only other `core/domain` or `vendor/canvas` `.js` files, and imports no QML, `Qt*`, `Quickshell*` or `qs.*`. | `docs/architecture.md:11`; `tests/architecture/test_layers.py` |
| Docstrings and comments state the contract only, no narrative; `bash tests/run.sh` green (including `tests/architecture`); TDD, tests first. | card description |

## Behaviour

All five functions are exported from `core/domain/logStream.js`. None throws on any input, and
none mutates its arguments. "Character" below means a UTF-16 code unit of a JS string, except
where a surrogate pair is named.

### B1. `sanitize(text)` → string

- A non-string `text` → `""`.
- **CSI**: `ESC [`, then any characters in U+0030–U+003F (parameters), then any in
  U+0020–U+002F (intermediates), then one final character in U+0040–U+007E → removed whole.
  `"\x1b[31mred\x1b[0m"` → `"red"`; `"\x1b[2K\x1b[1G"` → `""`.
- **OSC**: `ESC ]`, then everything up to and including the first BEL (`\x07`) or `ESC \` →
  removed whole. `"\x1b]0;title\x07ok"` → `"ok"`; `"\x1b]8;;http://x\x1b\\link"` → `"link"`.
- **Other ESC sequences**: `ESC`, then any characters in U+0020–U+002F, then one character in
  U+0030–U+007E → removed whole (`"\x1b(Bx"` → `"x"`, `"\x1b7x"` → `"x"`). An `ESC` followed
  by anything else (another control, a character ≥ U+007F, or the end) is removed alone.
- **No sequence crosses a newline**: a CSI or OSC that has not ended before the next `\n` is
  removed up to that `\n`, which stays; one that has not ended by the end of the text is removed
  to the end. `"a\x1b[12\nb"` → `"a\nb"`; `"a\x1b]0;t\nb"` → `"a\nb"`; `"a\x1b["` → `"a"`.
- **`\r\n`** → `\n`.
- **A lone `\r`**: within each line (the text split on `\n`), the line becomes its last
  non-empty `\r`-separated segment, or `""` when every segment is empty.
  `"10%\r55%\r100%"` → `"100%"`; `"abc\rxy"` → `"xy"`; `"abc\r"` → `"abc"` (a trailing `\r`
  with nothing after it keeps the frame it ends); `"\r\r"` → `""`. This is the reading of LO
  line 140-141 ("keeps only what follows it") that holds when nothing follows yet.
- **Other controls**: every remaining character in U+0000–U+001F except `\t` (U+0009) and
  `\n` (U+000A), and DEL (U+007F), is removed. `\t` and `\n` stay. U+FFFD stays. Characters
  U+0080 and above (C1 included) are kept unchanged.
- Order: escape sequences first, then `\r\n`, then lone `\r`, then the remaining controls. So
  an `ESC` removed alone never exposes a sequence, and `"a\x00\rb"` → `"b"`.
- Idempotent: `sanitize(sanitize(x)) === sanitize(x)`.

### B2. `utf8Length(text)` → number

- The byte length of `text` encoded as UTF-8: U+0000–U+007F 1, U+0080–U+07FF 2, other BMP
  characters 3, a surrogate pair 4, a lone surrogate 3 (it encodes as U+FFFD).
  `utf8Length("héllo €𝄞") === 14`; `utf8Length("…") === 3`; `utf8Length("") === 0`.
- A non-string → `0`.

### B3. `emptyBuffer(maxLines)` → buffer

- `{lines: [], partial: "", dropped: 0, nextOffset: 0, gapBytes: 0, slack: 0, maxLines}`
  (`slack`: see B4 "Offsets"; it is the one field added to LO's shape).
- `maxLines` is kept when it is a finite integer ≥ 1; anything else (missing, `0`, negative,
  `2.5`, `NaN`, `Infinity`, a string such as `"50"`, `null`) → `1000`.
- Each call returns a new object with a new `lines` array.

### B4. `foldLine(buffer, line)` → `{buffer, kind}`

**Input buffer.** A `buffer` that is not an object with an array `lines` is treated as
`emptyBuffer(buffer && buffer.maxLines)`. The returned `buffer` is always a new object with a
new `lines` array; the input buffer and its `lines` are never changed. In a buffer with an
array `lines`, a missing or invalid `partial` (not a string), `dropped`, `nextOffset`,
`gapBytes` or `slack` (not a finite number ≥ 0) reads as its `emptyBuffer` value, and an
invalid `maxLines` as 1000, so no comparison runs on `undefined`/`NaN`. When nothing changes,
the returned buffer equals the input field for field.

**Kind**, decided in this order on `line`:

1. not a non-null, non-array object → `ignored`;
2. has an own `ok` key whose value is `false` → `refusal` (am's envelope or the helper's own
   failure line; the caller reads `error`). Buffer unchanged;
3. `event === "logs"` → `hello`;
4. `event === "end"` → `end`. Buffer unchanged (the held `partial` stays and `bufferText`
   still shows it);
5. any other own `event` or own `ok` key → `ignored`;
6. `offset` a finite integer ≥ 0 and `text` a string → `chunk` (or `ignored` for a duplicate,
   below);
7. anything else → `ignored`. Buffer unchanged.

Unknown keys never matter (`path`, `schema`, `status` are not read here).

**Hello.** When the buffer is empty (no lines, `partial` `""`, `dropped` 0, `nextOffset` 0,
`gapBytes` 0) and the hello's `offset` is a finite integer ≥ 0, `nextOffset` becomes that
offset. Otherwise the buffer is unchanged (a resumed buffer keeps its own `nextOffset`). Kind
is `hello` either way.

**Offsets.** Let `E = buffer.nextOffset` and `S = buffer.slack`.

- `offset < E - S` → a duplicate: kind `ignored`, buffer unchanged.
- `E - S <= offset <= E` → contiguous: folded as below, no gap.
- `offset > E` → a gap of `N = offset - E` bytes: `gapBytes += N`; a held non-empty `partial`
  is first committed as a line of its own (B4 "Lines"), then the line `[… N bytes not shown]`
  is appended (`…` is U+2026, `N` in decimal), then the chunk is folded.
- After an accepted chunk: `nextOffset = offset + utf8Length(text)`, and
  `slack = 2 × (the number of U+FFFD characters in text)`. am writes one U+FFFD for each
  invalid byte, so `utf8Length` overcounts by up to 2 bytes per U+FFFD and the next chunk's
  exact `offset` may sit that far below `nextOffset` (LO lines 67-68). Without `slack` that
  contiguous chunk would be ignored as a duplicate. A hello and an ignored line leave `slack`
  unchanged.

**Lines.** For an accepted chunk: `raw = partial + text`. Everything up to the last `\n` of
`raw` is split on `\n`; each piece is `sanitize`d, then cut, then appended to `lines`. What
follows the last `\n` becomes the new `partial`, **unsanitized** (so a `\r\n`, an escape
sequence or a surrogate pair split across two chunks is joined before it is sanitized).

- **Cut**: a sanitized line longer than 2000 characters becomes its first 2000 characters plus
  `…`; when character 2000 (1-based) is a high surrogate, the cut is at 1999 so no surrogate
  pair is split. A line of exactly 2000 characters is unchanged.
- **Held tail bound**: when the new `partial` is longer than 16384 characters, it is committed
  as a line (sanitized and cut) and `partial` becomes `""`. A stream that never writes `\n`
  therefore cannot grow the buffer without bound.
- **Cap**: after appending, while `lines.length > maxLines`, the first line is removed and
  `dropped` increases by one. The gap line counts as a line. `partial` does not count.
- A chunk with `text` `""` appends nothing; it still moves `nextOffset` to its `offset`.
- Empty lines are kept: `"a\n\nb\n"` appends `"a"`, `""`, `"b"`.

### B5. `bufferText(buffer)` → string

- The display lines joined with `\n`: first `… N earlier lines` (U+2026, `N` = `dropped`) when
  `dropped > 0`; then every entry of `lines`; then `sanitize(partial)` cut as in B4, when that
  is not `""`.
- The prefix wording is LO's verbatim for every `N`, including `… 1 earlier lines`.
- An empty buffer → `""`. A buffer that is not an object with an array `lines` → `""`.
- No trailing `\n`.

## Error paths

None throws. Bad input degrades as stated: non-string text → `""`/`0`; a bad `maxLines` →
1000; a bad buffer → a fresh empty one; an unreadable `line` → `ignored` with the buffer
unchanged.

## Tests

One file, `tests/core/domain/tst_log_stream.qml` (tier: domain unit test, run by
`qmltestrunner` through `tests/run.sh`; the module is a `.pragma library` JS file, which only
the QML engine loads, and every behaviour here is a pure function's return value). Shape like
`tst_text.qml`: `import QtQuick`, `import QtTest`,
`import "../../../core/domain/logStream.js" as LS`, `TestCase { name: "DomainLogStream" }`,
snake_case test names. Escapes are written as `"\x1b"` / `"\u001b"` in the test source.

The `.jsonl` fixtures are read by a function local to the test file: a synchronous
`XMLHttpRequest` on `Qt.resolvedUrl("../../fixtures/am/<name>")` (`tests/run.sh` sets
`QML_XHR_ALLOW_FILE_READ=1`), split on `\n`, every non-empty line `JSON.parse`d.
`logs-follow-refusal.json` is read with `tests/helpers/amFixtures.js` `load`. `amFixtures.js`
is not changed.

**sanitize**
1. `test_sanitize_removes_csi` — colour, erase-line and cursor sequences, with and without
   parameters and intermediates.
2. `test_sanitize_removes_osc_ended_by_bel_or_st` — both terminators, text after kept.
3. `test_sanitize_removes_other_esc_sequences` — `ESC ( B`, `ESC 7`, a lone trailing `ESC`,
   `ESC` before a control.
4. `test_sanitize_unended_sequence_stops_at_newline_or_end` — the three examples in B1.
5. `test_sanitize_crlf_becomes_lf`.
6. `test_sanitize_lone_cr_keeps_the_last_frame` — `"10%\r55%\r100%"`, `"abc\rxy"`,
   `"abc\r"`, `"\r\r"`, and per line: `"a\rb\nc\rd"` → `"b\nd"`.
7. `test_sanitize_drops_c0_and_del_keeps_tab_newline_fffd` — every C0 except `\t`/`\n` and
   DEL removed; `\t`, `\n`, `�`, `é`, `𝄞`, U+0085 kept.
8. `test_sanitize_is_idempotent_and_total` — a mixed sample twice; `undefined`, `null`, `42`,
   `{}` → `""`.

**utf8Length**
9. `test_utf8_length_counts_bytes` — ASCII, `"héllo €𝄞"` = 14, `"…"` = 3, `""` = 0, a lone
   high and a lone low surrogate = 3 each, `"�"` = 3; non-strings → 0.

**emptyBuffer**
10. `test_empty_buffer_shape` — `emptyBuffer(50)` equals the B3 object; two calls return
    distinct `lines` arrays.
11. `test_empty_buffer_bad_max_lines_is_1000` — every bad value listed in B3.

**foldLine kinds**
12. `test_fold_hello_on_empty_buffer_sets_next_offset` — `{event:"logs", offset: 120,
    path: "x", schema: 1}` → kind `hello`, `nextOffset` 120, nothing else changed.
13. `test_fold_hello_on_a_used_buffer_keeps_next_offset` — after a chunk, a hello with another
    offset → `hello`, buffer field-for-field equal.
14. `test_fold_chunk_appends_lines_and_moves_next_offset` — `{offset: 0, text: "a\nb\n"}` →
    `chunk`, lines `["a","b"]`, `nextOffset` 4.
15. `test_fold_end_keeps_the_buffer` — `{event:"end", status:"gate_failed"}` → `end`, buffer
    equal, held `partial` still shown by `bufferText`.
16. `test_fold_refusal` — `{ok:false, error:{type:"UnknownAttemptError", message:"m"}}` →
    `refusal`, buffer equal.
17. `test_fold_ignored_lines` — `null`, `"text"`, `42`, `[]`, `{}`, `{event:"other"}`,
    `{ok:true}`, `{offset:"3", text:"x"}`, `{offset:-1, text:"x"}`, `{offset:1.5, text:"x"}`,
    `{offset:0, text: 7}` → each `ignored`, buffer equal.
18. `test_fold_does_not_mutate_its_input` — a buffer frozen in a snapshot (`JSON.stringify`)
    before folding a chunk, a gap and a cap overflow equals its snapshot after.
19. `test_fold_bad_buffer_starts_empty` — `foldLine(null, chunk)` and
    `foldLine({}, chunk)` → a buffer with `maxLines` 1000 holding the chunk's lines.

**partial lines**
20. `test_fold_holds_the_unterminated_tail` — `"abc"` then `"def\ng"` → lines `["abcdef"]`,
    `partial` `"g"`; `bufferText` `"abcdef\ng"`.
21. `test_fold_joins_a_crlf_split_across_chunks` — `"x\r"` then `"\ny\n"` → `["x","y"]`.
22. `test_fold_joins_an_escape_split_across_chunks` — `"\x1b[3"` then `"1mred\n"` →
    `["red"]`; `bufferText` after the first chunk alone is `""`.
23. `test_fold_joins_a_surrogate_pair_split_across_chunks` — `"\uD834"` then `"\uDD1E\n"` →
    `["𝄞"]` (am holds split characters back; this pins that the fold does not break one if it
    arrives split anyway).
24. `test_fold_commits_an_overlong_tail` — 16385 `x` without `\n` → one line of 2000 `x` + `…`,
    `partial` `""`; 16384 stays held.

**long lines and cap**
25. `test_fold_cuts_a_long_line` — 2001 chars → 2000 + `…`; 2000 chars unchanged; a line
    whose 2000th character is a high surrogate is cut at 1999 + `…`.
26. `test_fold_caps_lines_and_counts_dropped` — `emptyBuffer(3)`, five lines in one chunk then
    two in another → last three lines kept, `dropped` 4; `bufferText` starts with
    `"… 4 earlier lines\n"`.
27. `test_fold_cap_of_one` — `emptyBuffer(1)` keeps only the newest line.

**offsets**
28. `test_fold_ignores_a_duplicate_chunk` — `nextOffset` 10, a chunk at 4 → `ignored`, buffer
    equal; a chunk at 10 → `chunk`.
29. `test_fold_gap_adds_a_marker_line` — `nextOffset` 10, a chunk at 25 with `"z\n"` →
    `chunk`, lines end `"[… 15 bytes not shown]"`, `"z"`, `gapBytes` 15, `nextOffset` 27;
    a second gap adds to `gapBytes`.
30. `test_fold_gap_commits_the_held_partial_first` — partial `"ab"`, then a gap chunk
    `"cd\n"` → lines `["ab", "[… N bytes not shown]", "cd"]`.
31. `test_fold_gap_from_an_empty_buffer` — no hello, first chunk at 500 → marker for 500.
32. `test_fold_resume_after_hello` — empty buffer, hello at 40, chunk at 40 → no gap line,
    `nextOffset` 40 + length.
33. `test_fold_slack_after_fffd_accepts_the_exact_next_offset` — chunk at 0 `"a�\n"`
    (`nextOffset` 5, `slack` 2), next chunk at 3 → `chunk`, appended, no gap, `nextOffset`
    3 + length, `slack` 0; a chunk at 2 in the same state → `ignored`.
34. `test_fold_multibyte_text_moves_next_offset_by_bytes` — `"héllo €𝄞\n"` at 0 →
    `nextOffset` 15.

**bufferText**
35. `test_buffer_text_shapes` — empty → `""`; lines only; lines + partial; partial only;
    `dropped` 1 → `"… 1 earlier lines\n…"`; a held partial with an escape is shown sanitized;
    a bad buffer → `""`.

**fixtures, end to end**
36. `test_fixture_step_stream` — `logs-follow-step.jsonl` folded from `emptyBuffer(1000)`:
    kinds `["hello","chunk","end"]`, `bufferText` `"==> verify-ok (exit 0)\nverified"`,
    `nextOffset` 32, `dropped` 0, `gapBytes` 0.
37. `test_fixture_agent_stream` — `logs-follow-agent.jsonl`: kinds
    `["hello","chunk","end"]`, `bufferText` `"stub claude ok phase=review"`, `nextOffset` 28.
38. `test_fixture_refusal` — `logs-follow-refusal.json` → kind `refusal`, buffer equal to
    `emptyBuffer(1000)`.

`tests/architecture` (pytest, already in the suite) must stay green with the new domain file.
Gate: `bash tests/run.sh`.

## Out of scope

- `RunOutputStore` and its tests, the follow process, reconnects, `snapshotWanted()` (LO
  lines 157-190: a sibling card).
- `Runs.isLiveSelection`, step rows, `defaultAttempt` (LO lines 98-110, 240-241: the
  `runs.js` card).
- The output pane UI, `TailScroll`, labels and the end line (LO lines 192-212, 249-250).
- `runs-logs-follow.py`, `runs-logs.py`, `tests/contract/test_am_shapes.py` and the fixtures
  themselves (cards 1.x, done).
- Reading the hello's `schema` (the helper checks it, LO line 125) or the end's `status`
  (the store reads it from the line it passed in).
- `tests/helpers/amFixtures.js` (no `loadLines` helper is added) and `docs/architecture.md`
  (the domain-file sentence for `logStream.js` belongs to the story's docs work).
- ANSI colour rendering (LO line 89-90).

## Handoff to the planner

Follow the `writing-plans` format. Files: create `core/domain/logStream.js` and
`tests/core/domain/tst_log_stream.qml`; nothing else. Style model: `core/domain/runEvents.js`
and `text.js` (`.pragma library`, `var`, ES5 functions, private helpers prefixed `_`, a header
comment stating the contract, "Pure and never throwing"). Run one QML file with
`bash tests/run.sh tst_log_stream` (it still runs pytest first).

Suggested tasks (each with its own test cycle):

1. `sanitize` and `utf8Length`: tests 1-9.
2. `emptyBuffer`, `bufferText` and `foldLine` kinds, lines, cut, cap, held-tail bound: tests
   10-27 and 35.
3. Offsets (duplicate, gap, hello, slack) and the fixtures end to end: tests 28-34, 36-38.

Review Focus candidates: an escape sequence, `\r\n` or surrogate pair split across chunks; a
`\r`-only progress bar that never writes `\n`; a chunk right after one containing U+FFFD; a
gap while a partial line is held; `maxLines` given as a string or `0`.

---

# 2.1 `logStream.js`: a bounded, sanitized line buffer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the pure domain module `core/domain/logStream.js` (`sanitize`, `utf8Length`, `emptyBuffer`, `foldLine`, `bufferText`) that folds `runs-logs-follow.py`'s JSON lines into a bounded buffer of sanitized display lines, with its QML test file.

**Architecture:** One `.pragma library` ES5 file with no imports, private helpers prefixed `_`. `foldLine` always starts from `_read(buffer)`, a fresh validated copy, so no input is ever mutated; a chunk is joined to the held unsanitized `partial`, split on its last `\n`, and each complete line is sanitized and cut before it is appended; the cap then drops lines from the front. Offsets (duplicate, gap, hello, U+FFFD slack) are decided before the text is folded.

**Tech Stack:** QML JavaScript (V4, `.pragma library`), QtTest via `qmltestrunner`, the existing `tests/run.sh` gate (pytest incl. `tests/architecture`, then every `tst_*.qml`).

**Spec:** `docs/superpowers/specs/2-1-logstream-js-a-882b8014.md` (reproduced above).

## Global Constraints

- `core/domain/logStream.js` is pure and never throws; no function mutates its arguments.
- The file starts with `.pragma library` and has no `.import` (a domain file may `.import` only other `core/domain` or `vendor/canvas` `.js` files, and imports no QML, `Qt*`, `Quickshell*` or `qs.*`; `tests/architecture/test_layers.py` enforces this).
- Style of `core/domain/runEvents.js` / `text.js`: `var`, ES5 `function`s, private helpers prefixed `_`, a header comment stating the contract, "Pure and never throwing".
- Docstrings and comments state the contract only, no narrative.
- Display caps: a line over 2000 characters becomes its first 2000 plus `…` (U+2026); a held tail over 16384 characters is committed; `maxLines` defaults to 1000.
- Marker texts verbatim: `[… N bytes not shown]` and `… N earlier lines` (U+2026, `N` decimal, `lines` even for 1).
- Tests in `tests/core/domain/tst_log_stream.qml`, `TestCase { name: "DomainLogStream" }`, snake_case names; escapes written as `"\x1b"` / `"\uXXXX"` in source. Hand-built am payloads carry a `synthetic:` comment.
- Only two files are created: `core/domain/logStream.js`, `tests/core/domain/tst_log_stream.qml`. `tests/helpers/amFixtures.js`, the fixtures and `docs/architecture.md` are not changed.
- Gate: `bash tests/run.sh` green. TDD: tests first.

## Review Focus

1. A `\r`-only progress bar that never writes `\n` — the held tail must stay ≤ 16384 characters and the pane must show the newest frame. Pinned by `test_fold_progress_bar_without_newline_stays_bounded` (Task 2).
2. A buffer whose fields are corrupt or missing (`partial: 5`, `dropped: NaN`, `nextOffset` absent, `gapBytes: -3`, `slack: "2"`, `maxLines: "50"`) — every field must read as its empty value, never as `NaN` arithmetic. Pinned by `test_fold_reads_invalid_fields_as_their_empty_values` (Task 2).
3. Malformed escapes: a control inside a CSI, an `ESC` not followed by `\` inside an OSC — the sequence must still be removed whole, up to its real terminator. Pinned by `test_sanitize_csi_and_osc_end_only_at_their_terminators` (Task 1).
4. A chunk re-sent at its original offset after a chunk holding U+FFFD (a reconnect replay) — the slack must not let it through twice. Pinned by `test_fold_resent_chunk_with_fffd_is_a_duplicate` (Task 3).
5. A gap on a buffer near its cap — the `[… N bytes not shown]` marker counts as a line and can itself be dropped, with `gapBytes` still recording the gap. Pinned by `test_fold_gap_marker_counts_toward_the_cap` (Task 3).

## File map

- Create `core/domain/logStream.js` — the whole module (Tasks 1-3 grow it).
- Create `tests/core/domain/tst_log_stream.qml` — every test (Tasks 1-3 grow it).

## Commands

- Fast loop (this test file only, ~1 s), from the worktree root:
  `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
  A run that cannot load the module prints `FAIL!  : qmltestrunner::tst_log_stream::compile() Script file:///…/core/domain/logStream.js unavailable`.
- Gate (pytest including `tests/architecture`, then every QML test; ~3 min):
  `timeout 600 bash tests/run.sh`

---

### Task 1: `sanitize` and `utf8Length`

**Files:**
- Create: `core/domain/logStream.js`
- Test: `tests/core/domain/tst_log_stream.qml` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `sanitize(text) -> string`, `utf8Length(text) -> number`; private `_inRange(c, lo, hi) -> bool`, `_CONTROLS_RE` (used again by later tasks inside this file).

- [ ] **Step 1: Write the failing tests**

Create `tests/core/domain/tst_log_stream.qml` with exactly:

```qml
// tests/core/domain/tst_log_stream.qml
import QtQuick
import QtTest
import "../../../core/domain/logStream.js" as LS

TestCase {
  name: "DomainLogStream"

  // ---- sanitize ---------------------------------------------------------------------------

  function test_sanitize_removes_csi() {
    compare(LS.sanitize("\x1b[31mred\x1b[0m"), "red")
    compare(LS.sanitize("\x1b[2K\x1b[1G"), "")
    compare(LS.sanitize("a\x1b[mb"), "ab")
    compare(LS.sanitize("a\x1b[?25lb"), "ab")
    compare(LS.sanitize("a\x1b[1;32;40mb"), "ab")
    compare(LS.sanitize("a\x1b[1 qb"), "ab")
  }

  function test_sanitize_removes_osc_ended_by_bel_or_st() {
    compare(LS.sanitize("\x1b]0;title\x07ok"), "ok")
    compare(LS.sanitize("\x1b]8;;http://x\x1b\\link\x1b]8;;\x1b\\"), "link")
  }

  function test_sanitize_removes_other_esc_sequences() {
    compare(LS.sanitize("\x1b(Bx"), "x")
    compare(LS.sanitize("\x1b7x"), "x")
    compare(LS.sanitize("x\x1b"), "x")
    compare(LS.sanitize("a\x1b\x07b"), "ab")
    compare(LS.sanitize("a\x1b\u00e9b"), "a\u00e9b")
  }

  function test_sanitize_unended_sequence_stops_at_newline_or_end() {
    compare(LS.sanitize("a\x1b[12\nb"), "a\nb")
    compare(LS.sanitize("a\x1b]0;t\nb"), "a\nb")
    compare(LS.sanitize("a\x1b["), "a")
  }

  function test_sanitize_csi_and_osc_end_only_at_their_terminators() {
    // A control inside a CSI does not end it; an ESC not followed by "\" does not end an OSC.
    compare(LS.sanitize("\x1b[1;2\x07mx"), "x")
    compare(LS.sanitize("\x1b]0;a\x1bbx\x07y"), "y")
  }

  function test_sanitize_crlf_becomes_lf() {
    compare(LS.sanitize("a\r\nb\r\n"), "a\nb\n")
  }

  function test_sanitize_lone_cr_keeps_the_last_frame() {
    compare(LS.sanitize("10%\r55%\r100%"), "100%")
    compare(LS.sanitize("abc\rxy"), "xy")
    compare(LS.sanitize("abc\r"), "abc")
    compare(LS.sanitize("\r\r"), "")
    compare(LS.sanitize("a\rb\nc\rd"), "b\nd")
    compare(LS.sanitize("a\x00\rb"), "b")
  }

  function test_sanitize_drops_c0_and_del_keeps_tab_newline_fffd() {
    for (var c = 0; c < 32; c++) {
      if (c === 9 || c === 10 || c === 13 || c === 27) continue
      compare(LS.sanitize("a" + String.fromCharCode(c) + "b"), "ab", "U+" + c.toString(16))
    }
    compare(LS.sanitize("a\x7fb"), "ab")
    compare(LS.sanitize("a\tb\nc"), "a\tb\nc")
    compare(LS.sanitize("\uFFFD\u00e9\uD834\uDD1E\u0085"), "\uFFFD\u00e9\uD834\uDD1E\u0085")
  }

  function test_sanitize_is_idempotent_and_total() {
    var sample = "\x1b[1mbold\x1b[0m\r\nx\x00y\r10%\r20%\n\x1b]0;t\x07\tz\uFFFD\x1b"
    var once = LS.sanitize(sample)
    compare(once, "bold\n20%\n\tz\uFFFD")
    compare(LS.sanitize(once), once)
    var bad = [undefined, null, 42, {}]
    for (var i = 0; i < bad.length; i++) compare(LS.sanitize(bad[i]), "", String(bad[i]))
  }

  // ---- utf8Length -------------------------------------------------------------------------

  function test_utf8_length_counts_bytes() {
    compare(LS.utf8Length("abc"), 3)
    compare(LS.utf8Length("h\u00e9llo \u20ac\uD834\uDD1E"), 14)
    compare(LS.utf8Length("\u2026"), 3)
    compare(LS.utf8Length(""), 0)
    compare(LS.utf8Length("\uD834"), 3)
    compare(LS.utf8Length("\uDD1E"), 3)
    compare(LS.utf8Length("\uFFFD"), 3)
    var bad = [undefined, null, 42, {}, ["ab"]]
    for (var i = 0; i < bad.length; i++) compare(LS.utf8Length(bad[i]), 0, String(bad[i]))
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
Expected: `FAIL!  : qmltestrunner::tst_log_stream::compile() Script file:///…/core/domain/logStream.js unavailable` and `Totals: 0 passed, 1 failed`.

- [ ] **Step 3: Write the implementation**

Create `core/domain/logStream.js` with exactly:

```javascript
.pragma library

// Live log stream: folds the JSON lines runs-logs-follow.py prints (am's
// `am logs --follow` hello, chunk and end lines, or one {"ok":false,"error"}
// refusal) into a bounded buffer of display lines. Pure and never throwing;
// no function mutates its arguments.

var _CONTROLS_RE = /[\x00-\x08\x0b-\x1f\x7f]/g

function _inRange(c, lo, hi) { return c >= lo && c <= hi }

// Index where plain text resumes after the ESC at text[j - 1]. A CSI ends at
// its first character in U+0040-U+007E, an OSC at BEL or ESC \; either stops
// before a "\n" or at the end. Another ESC sequence is intermediates
// (U+0020-U+002F) then one final in U+0030-U+007E; anything else is the ESC
// alone.
function _escapeEnd(text, j) {
  var n = text.length
  if (j >= n) return n
  var c = text.charCodeAt(j)
  var k = j + 1
  if (c === 0x5b) {
    for (; k < n; k++) {
      var p = text.charCodeAt(k)
      if (p === 0x0a) return k
      if (_inRange(p, 0x40, 0x7e)) return k + 1
    }
    return n
  }
  if (c === 0x5d) {
    for (; k < n; k++) {
      var o = text.charCodeAt(k)
      if (o === 0x0a) return k
      if (o === 0x07) return k + 1
      if (o === 0x1b && k + 1 < n && text.charCodeAt(k + 1) === 0x5c) return k + 2
    }
    return n
  }
  k = j
  while (k < n && _inRange(text.charCodeAt(k), 0x20, 0x2f)) k++
  if (k < n && _inRange(text.charCodeAt(k), 0x30, 0x7e)) return k + 1
  return j
}

function _stripEscapes(text) {
  var out = ""
  var start = 0
  var i = text.indexOf("\x1b")
  while (i >= 0) {
    out += text.slice(start, i)
    start = _escapeEnd(text, i + 1)
    i = text.indexOf("\x1b", start)
  }
  return out + text.slice(start)
}

// The last non-empty "\r"-separated segment of line, or "".
function _lastFrame(line) {
  var frames = line.split("\r")
  for (var i = frames.length - 1; i >= 0; i--)
    if (frames[i] !== "") return frames[i]
  return ""
}

// text without ANSI CSI/OSC/ESC sequences, "\r\n" as "\n", each line reduced
// to its last "\r" frame, and without C0 controls other than "\t" and "\n"
// or DEL. "" for a non-string.
function sanitize(text) {
  if (typeof text !== "string") return ""
  var lines = _stripEscapes(text).replace(/\r\n/g, "\n").split("\n")
  for (var i = 0; i < lines.length; i++)
    if (lines[i].indexOf("\r") >= 0) lines[i] = _lastFrame(lines[i])
  return lines.join("\n").replace(_CONTROLS_RE, "")
}

// The UTF-8 byte length of text; a lone surrogate counts 3 (U+FFFD). 0 for a
// non-string.
function utf8Length(text) {
  if (typeof text !== "string") return 0
  var bytes = 0
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i)
    if (c < 0x80) bytes += 1
    else if (c < 0x800) bytes += 2
    else if (_inRange(c, 0xd800, 0xdbff) && i + 1 < text.length && _inRange(text.charCodeAt(i + 1), 0xdc00, 0xdfff)) {
      bytes += 4
      i++
    } else bytes += 3
  }
  return bytes
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
Expected: `Totals: 12 passed, 0 failed` (10 tests plus `initTestCase`/`cleanupTestCase`), no `FAIL!` line.

- [ ] **Step 5: Run the gate**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest ends `passed` with no failures (the architecture test accepts the new domain file), every `== tests/…` block shows `0 failed`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add core/domain/logStream.js tests/core/domain/tst_log_stream.qml
git commit -m "feat(domain): logStream.js sanitize and utf8Length"
```

---

### Task 2: `emptyBuffer`, `foldLine` kinds and lines, `bufferText`

**Files:**
- Modify: `core/domain/logStream.js` (replace the whole file)
- Test: `tests/core/domain/tst_log_stream.qml` (add helpers and tests)

**Interfaces:**
- Consumes: `sanitize(text)`, `utf8Length(text)`, `_inRange`, `_CONTROLS_RE` from Task 1.
- Produces:
  - `emptyBuffer(maxLines) -> {lines: string[], partial: string, dropped: number, nextOffset: number, gapBytes: number, slack: number, maxLines: number}`
  - `foldLine(buffer, line) -> {buffer, kind}`, `kind` one of `"hello" | "chunk" | "end" | "refusal" | "ignored"`
  - `bufferText(buffer) -> string`
  - private, used by Task 3: `_foldChunk(b, offset, text) -> {buffer, kind}` (`b` is already a copy), `_displayLine(raw) -> string` (sanitized and cut), `_cap(b)`, constant `_ELLIPSIS = "\u2026"`.
  - test helpers, used by Task 3: `rep(s, n)`, `chunk(offset, text)`, `foldAll(buffer, lines) -> {buffer, kinds}`.

- [ ] **Step 1: Add the test helpers**

In `tests/core/domain/tst_log_stream.qml`, directly after the line `  name: "DomainLogStream"` and its following blank line (before `  // ---- sanitize ---…`), insert:

```qml
  function rep(s, n) { return new Array(n + 1).join(s) }

  function chunk(offset, text) { return { offset: offset, text: text } }

  // Folds lines into buffer in order; {buffer, kinds}.
  function foldAll(buffer, lines) {
    var kinds = []
    for (var i = 0; i < lines.length; i++) {
      var r = LS.foldLine(buffer, lines[i])
      buffer = r.buffer
      kinds.push(r.kind)
    }
    return { buffer: buffer, kinds: kinds }
  }

```

- [ ] **Step 2: Write the failing tests**

In the same file, after the closing `  }` of `test_utf8_length_counts_bytes` and before the file's final `}`, insert:

```qml

  // ---- emptyBuffer ------------------------------------------------------------------------

  function test_empty_buffer_shape() {
    compare(LS.emptyBuffer(50),
            { lines: [], partial: "", dropped: 0, nextOffset: 0, gapBytes: 0, slack: 0, maxLines: 50 })
    var a = LS.emptyBuffer(5), b = LS.emptyBuffer(5)
    verify(a !== b)
    verify(a.lines !== b.lines)
  }

  function test_empty_buffer_bad_max_lines_is_1000() {
    var bad = [undefined, 0, -3, 2.5, NaN, Infinity, "50", null]
    for (var i = 0; i < bad.length; i++) compare(LS.emptyBuffer(bad[i]).maxLines, 1000, String(bad[i]))
    compare(LS.emptyBuffer().maxLines, 1000)
  }

  // ---- foldLine kinds ---------------------------------------------------------------------

  function test_fold_hello_on_empty_buffer_sets_next_offset() {
    var r = LS.foldLine(LS.emptyBuffer(1000), { event: "logs", offset: 120, path: "x", schema: 1 })
    compare(r.kind, "hello")
    compare(r.buffer, { lines: [], partial: "", dropped: 0, nextOffset: 120, gapBytes: 0, slack: 0, maxLines: 1000 })
  }

  function test_fold_hello_on_a_used_buffer_keeps_next_offset() {
    var used = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\n")).buffer
    var r = LS.foldLine(used, { event: "logs", offset: 77, path: "x", schema: 1 })
    compare(r.kind, "hello")
    compare(r.buffer, used)
  }

  function test_fold_chunk_appends_lines_and_moves_next_offset() {
    var r = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\nb\n"))
    compare(r.kind, "chunk")
    compare(r.buffer.lines, ["a", "b"])
    compare(r.buffer.partial, "")
    compare(r.buffer.nextOffset, 4)
  }

  function test_fold_end_keeps_the_buffer() {
    var held = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\nbc")).buffer
    var r = LS.foldLine(held, { event: "end", status: "gate_failed" })
    compare(r.kind, "end")
    compare(r.buffer, held)
    compare(LS.bufferText(r.buffer), "a\nbc")
  }

  function test_fold_refusal() {
    var held = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\nbc")).buffer
    // synthetic: am's refusal envelope arriving after output.
    var r = LS.foldLine(held, { ok: false, error: { type: "UnknownAttemptError", message: "m" } })
    compare(r.kind, "refusal")
    compare(r.buffer, held)
  }

  function test_fold_ignored_lines() {
    var held = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\nbc")).buffer
    var bad = [null, "text", 42, [], {}, { event: "other" }, { ok: true }, { offset: "3", text: "x" },
               { offset: -1, text: "x" }, { offset: 1.5, text: "x" }, { offset: 0, text: 7 },
               { event: "other", offset: 4, text: "x" }, { ok: true, offset: 4, text: "x" }]
    for (var i = 0; i < bad.length; i++) {
      var r = LS.foldLine(held, bad[i])
      compare(r.kind, "ignored", JSON.stringify(bad[i]))
      compare(r.buffer, held, JSON.stringify(bad[i]))
    }
  }

  function test_fold_does_not_mutate_its_input() {
    var b = LS.foldLine(LS.emptyBuffer(2), chunk(0, "a\nb\nc")).buffer
    var snapshot = JSON.stringify(b)
    var lines = b.lines
    LS.foldLine(b, chunk(5, "d\ne\nf\n"))
    LS.foldLine(b, chunk(50, "g\n"))
    LS.foldLine(b, { event: "logs", offset: 9 })
    compare(JSON.stringify(b), snapshot)
    verify(b.lines === lines)
    var r = LS.foldLine(b, { event: "end", status: "ok" })
    verify(r.buffer !== b)
    verify(r.buffer.lines !== b.lines)
  }

  function test_fold_bad_buffer_starts_empty() {
    var bad = [null, undefined, {}, "x", { lines: "a" }]
    for (var i = 0; i < bad.length; i++) {
      var r = LS.foldLine(bad[i], chunk(0, "a\n"))
      compare(r.kind, "chunk", String(bad[i]))
      compare(r.buffer.lines, ["a"], String(bad[i]))
      compare(r.buffer.maxLines, 1000, String(bad[i]))
    }
    compare(LS.foldLine({ maxLines: 7 }, chunk(0, "a\n")).buffer.maxLines, 7)
  }

  function test_fold_reads_invalid_fields_as_their_empty_values() {
    var r = LS.foldLine({ lines: ["x"], partial: 5, dropped: NaN, nextOffset: undefined, gapBytes: -3,
                          slack: "2", maxLines: "50" }, chunk(0, "y\n"))
    compare(r.kind, "chunk")
    compare(r.buffer, { lines: ["x", "y"], partial: "", dropped: 0, nextOffset: 2, gapBytes: 0, slack: 0,
                        maxLines: 1000 })
  }

  // ---- partial lines ----------------------------------------------------------------------

  function test_fold_holds_the_unterminated_tail() {
    var r = foldAll(LS.emptyBuffer(1000), [chunk(0, "abc"), chunk(3, "def\ng")])
    compare(r.buffer.lines, ["abcdef"])
    compare(r.buffer.partial, "g")
    compare(LS.bufferText(r.buffer), "abcdef\ng")
  }

  function test_fold_joins_a_crlf_split_across_chunks() {
    var r = foldAll(LS.emptyBuffer(1000), [chunk(0, "x\r"), chunk(2, "\ny\n")])
    compare(r.buffer.lines, ["x", "y"])
    compare(r.buffer.partial, "")
  }

  function test_fold_joins_an_escape_split_across_chunks() {
    var first = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "\x1b[3")).buffer
    compare(LS.bufferText(first), "")
    var r = LS.foldLine(first, chunk(3, "1mred\n"))
    compare(r.buffer.lines, ["red"])
  }

  function test_fold_joins_a_surrogate_pair_split_across_chunks() {
    var r = foldAll(LS.emptyBuffer(1000), [chunk(0, "\uD834"), chunk(3, "\uDD1E\n")])
    compare(r.buffer.lines, ["\uD834\uDD1E"])
  }

  function test_fold_commits_an_overlong_tail() {
    var r = LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("x", 16385)))
    compare(r.buffer.lines, [rep("x", 2000) + "\u2026"])
    compare(r.buffer.partial, "")
    var held = LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("x", 16384)))
    compare(held.buffer.lines, [])
    compare(held.buffer.partial.length, 16384)
  }

  function test_fold_progress_bar_without_newline_stays_bounded() {
    var b = LS.emptyBuffer(1000)
    for (var i = 0; i < 3000; i++) {
      var text = "\r" + i + "%"
      b = LS.foldLine(b, chunk(b.nextOffset, text)).buffer
      verify(b.partial.length <= 16384, "frame " + i)
    }
    compare(b.lines.length, 1)
    var shown = LS.bufferText(b).split("\n")
    compare(shown.length, 2)
    compare(shown[1], "2999%")
  }

  // ---- long lines and cap -----------------------------------------------------------------

  function test_fold_cuts_a_long_line() {
    compare(LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("a", 2001) + "\n")).buffer.lines,
            [rep("a", 2000) + "\u2026"])
    compare(LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("a", 2000) + "\n")).buffer.lines,
            [rep("a", 2000)])
    compare(LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("a", 1999) + "\uD834\uDD1Ey\n")).buffer.lines,
            [rep("a", 1999) + "\u2026"])
  }

  function test_fold_caps_lines_and_counts_dropped() {
    var r = foldAll(LS.emptyBuffer(3), [chunk(0, "1\n2\n3\n4\n5\n"), chunk(10, "6\n7\n")])
    compare(r.buffer.lines, ["5", "6", "7"])
    compare(r.buffer.dropped, 4)
    verify(LS.bufferText(r.buffer).indexOf("\u2026 4 earlier lines\n") === 0, LS.bufferText(r.buffer))
    compare(LS.bufferText(r.buffer), "\u2026 4 earlier lines\n5\n6\n7")
  }

  function test_fold_cap_of_one() {
    var r = foldAll(LS.emptyBuffer(1), [chunk(0, "a\nb\n"), chunk(4, "c\nd")])
    compare(r.buffer.lines, ["c"])
    compare(r.buffer.partial, "d")
    compare(r.buffer.dropped, 2)
  }

  // ---- bufferText -------------------------------------------------------------------------

  function test_buffer_text_shapes() {
    compare(LS.bufferText(LS.emptyBuffer(5)), "")
    var b = LS.emptyBuffer(5)
    b.lines = ["a", "b"]
    compare(LS.bufferText(b), "a\nb")
    b.partial = "c"
    compare(LS.bufferText(b), "a\nb\nc")
    b.lines = []
    compare(LS.bufferText(b), "c")
    b.lines = ["x"]
    b.partial = ""
    b.dropped = 1
    compare(LS.bufferText(b), "\u2026 1 earlier lines\nx")
    b.dropped = 0
    b.partial = "\x1b[1mhi\x1b[0m"
    compare(LS.bufferText(b), "x\nhi")
    var bad = [null, undefined, 42, "a", {}, { lines: "a" }]
    for (var i = 0; i < bad.length; i++) compare(LS.bufferText(bad[i]), "", String(bad[i]))
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
Expected: `Totals: 12 passed, 21 failed`; the failures read `Property 'emptyBuffer' of object [object Object] is not a function` (or `'foldLine'` / `'bufferText'`).

- [ ] **Step 4: Write the implementation**

Replace the whole of `core/domain/logStream.js` with:

```javascript
.pragma library

// Live log stream: folds the JSON lines runs-logs-follow.py prints (am's
// `am logs --follow` hello, chunk and end lines, or one {"ok":false,"error"}
// refusal) into a bounded buffer of display lines.
//
// Buffer: { lines, partial, dropped, nextOffset, gapBytes, slack, maxLines }.
// lines: sanitized display lines, oldest first, at most maxLines. partial: the
// unterminated tail, unsanitized. dropped: lines removed from the front.
// nextOffset: the byte offset the next chunk is expected at. gapBytes: bytes
// skipped by gaps. slack: how far below nextOffset a chunk is still contiguous
// (2 per U+FFFD in the last chunk). Pure and never throwing; no function
// mutates its arguments.

var _DEFAULT_MAX_LINES = 1000
var _MAX_LINE = 2000
var _MAX_PARTIAL = 16384
var _ELLIPSIS = "\u2026"
var _CONTROLS_RE = /[\x00-\x08\x0b-\x1f\x7f]/g

function _isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function _has(o, key) { return Object.prototype.hasOwnProperty.call(o, key) }
function _inRange(c, lo, hi) { return c >= lo && c <= hi }
function _isByteOffset(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= 0 }
function _isMaxLines(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= 1 }
function _count(v) { return typeof v === "number" && isFinite(v) && v >= 0 ? v : 0 }

// Index where plain text resumes after the ESC at text[j - 1]. A CSI ends at
// its first character in U+0040-U+007E, an OSC at BEL or ESC \; either stops
// before a "\n" or at the end. Another ESC sequence is intermediates
// (U+0020-U+002F) then one final in U+0030-U+007E; anything else is the ESC
// alone.
function _escapeEnd(text, j) {
  var n = text.length
  if (j >= n) return n
  var c = text.charCodeAt(j)
  var k = j + 1
  if (c === 0x5b) {
    for (; k < n; k++) {
      var p = text.charCodeAt(k)
      if (p === 0x0a) return k
      if (_inRange(p, 0x40, 0x7e)) return k + 1
    }
    return n
  }
  if (c === 0x5d) {
    for (; k < n; k++) {
      var o = text.charCodeAt(k)
      if (o === 0x0a) return k
      if (o === 0x07) return k + 1
      if (o === 0x1b && k + 1 < n && text.charCodeAt(k + 1) === 0x5c) return k + 2
    }
    return n
  }
  k = j
  while (k < n && _inRange(text.charCodeAt(k), 0x20, 0x2f)) k++
  if (k < n && _inRange(text.charCodeAt(k), 0x30, 0x7e)) return k + 1
  return j
}

function _stripEscapes(text) {
  var out = ""
  var start = 0
  var i = text.indexOf("\x1b")
  while (i >= 0) {
    out += text.slice(start, i)
    start = _escapeEnd(text, i + 1)
    i = text.indexOf("\x1b", start)
  }
  return out + text.slice(start)
}

// The last non-empty "\r"-separated segment of line, or "".
function _lastFrame(line) {
  var frames = line.split("\r")
  for (var i = frames.length - 1; i >= 0; i--)
    if (frames[i] !== "") return frames[i]
  return ""
}

// text without ANSI CSI/OSC/ESC sequences, "\r\n" as "\n", each line reduced
// to its last "\r" frame, and without C0 controls other than "\t" and "\n"
// or DEL. "" for a non-string.
function sanitize(text) {
  if (typeof text !== "string") return ""
  var lines = _stripEscapes(text).replace(/\r\n/g, "\n").split("\n")
  for (var i = 0; i < lines.length; i++)
    if (lines[i].indexOf("\r") >= 0) lines[i] = _lastFrame(lines[i])
  return lines.join("\n").replace(_CONTROLS_RE, "")
}

// The UTF-8 byte length of text; a lone surrogate counts 3 (U+FFFD). 0 for a
// non-string.
function utf8Length(text) {
  if (typeof text !== "string") return 0
  var bytes = 0
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i)
    if (c < 0x80) bytes += 1
    else if (c < 0x800) bytes += 2
    else if (_inRange(c, 0xd800, 0xdbff) && i + 1 < text.length && _inRange(text.charCodeAt(i + 1), 0xdc00, 0xdfff)) {
      bytes += 4
      i++
    } else bytes += 3
  }
  return bytes
}

// A new empty buffer; maxLines is kept when a finite integer >= 1, else 1000.
function emptyBuffer(maxLines) {
  return { lines: [], partial: "", dropped: 0, nextOffset: 0, gapBytes: 0, slack: 0,
           maxLines: _isMaxLines(maxLines) ? maxLines : _DEFAULT_MAX_LINES }
}

// A new copy of buffer with every invalid field read as its emptyBuffer value;
// emptyBuffer(buffer.maxLines) when buffer has no array lines.
function _read(buffer) {
  if (!_isObject(buffer) || !Array.isArray(buffer.lines)) return emptyBuffer(buffer ? buffer.maxLines : undefined)
  return { lines: buffer.lines.slice(),
           partial: typeof buffer.partial === "string" ? buffer.partial : "",
           dropped: _count(buffer.dropped), nextOffset: _count(buffer.nextOffset),
           gapBytes: _count(buffer.gapBytes), slack: _count(buffer.slack),
           maxLines: _isMaxLines(buffer.maxLines) ? buffer.maxLines : _DEFAULT_MAX_LINES }
}

function _isEmpty(b) {
  return b.lines.length === 0 && b.partial === "" && b.dropped === 0 && b.nextOffset === 0 && b.gapBytes === 0
}

// sanitize(raw) cut to 2000 characters plus "…", never splitting a surrogate pair.
function _displayLine(raw) {
  var line = sanitize(raw)
  if (line.length <= _MAX_LINE) return line
  var end = _inRange(line.charCodeAt(_MAX_LINE - 1), 0xd800, 0xdbff) ? _MAX_LINE - 1 : _MAX_LINE
  return line.slice(0, end) + _ELLIPSIS
}

function _cap(b) {
  var extra = b.lines.length - b.maxLines
  if (extra <= 0) return
  b.lines.splice(0, extra)
  b.dropped += extra
}

// b (already a copy) with the chunk {offset, text} folded in.
function _foldChunk(b, offset, text) {
  var raw = b.partial + text
  var last = raw.lastIndexOf("\n")
  if (last >= 0) {
    var done = raw.slice(0, last).split("\n")
    for (var i = 0; i < done.length; i++) b.lines.push(_displayLine(done[i]))
    raw = raw.slice(last + 1)
  }
  if (raw.length > _MAX_PARTIAL) {
    b.lines.push(_displayLine(raw))
    raw = ""
  }
  b.partial = raw
  b.nextOffset = offset + utf8Length(text)
  _cap(b)
  return { buffer: b, kind: "chunk" }
}

// {buffer, kind}: line folded into a new copy of buffer. kind is "refusal"
// (own ok === false), "hello" (event "logs"), "end" (event "end"), "chunk"
// ({offset, text}) or "ignored". A hello sets nextOffset to its offset on an
// empty buffer only. Only hello and chunk change the buffer.
function foldLine(buffer, line) {
  var b = _read(buffer)
  if (!_isObject(line)) return { buffer: b, kind: "ignored" }
  if (_has(line, "ok") && line.ok === false) return { buffer: b, kind: "refusal" }
  if (line.event === "logs") {
    if (_isEmpty(b) && _isByteOffset(line.offset)) b.nextOffset = line.offset
    return { buffer: b, kind: "hello" }
  }
  if (line.event === "end") return { buffer: b, kind: "end" }
  if (_has(line, "event") || _has(line, "ok")) return { buffer: b, kind: "ignored" }
  if (!_isByteOffset(line.offset) || typeof line.text !== "string") return { buffer: b, kind: "ignored" }
  return _foldChunk(b, line.offset, line.text)
}

// The display text: "… N earlier lines" when dropped > 0, the lines, then the
// sanitized and cut partial when not "", joined by "\n". "" for a bad buffer.
function bufferText(buffer) {
  if (!_isObject(buffer) || !Array.isArray(buffer.lines)) return ""
  var dropped = _count(buffer.dropped)
  var out = dropped > 0 ? [_ELLIPSIS + " " + dropped + " earlier lines"] : []
  out = out.concat(buffer.lines)
  var tail = _displayLine(typeof buffer.partial === "string" ? buffer.partial : "")
  if (tail !== "") out.push(tail)
  return out.join("\n")
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
Expected: `Totals: 33 passed, 0 failed`, no `FAIL!` line.

- [ ] **Step 6: Run the gate**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest with no failures, every QML block `0 failed`, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add core/domain/logStream.js tests/core/domain/tst_log_stream.qml
git commit -m "feat(domain): logStream.js buffer, foldLine and bufferText"
```

---

### Task 3: Offsets (duplicate, gap, slack) and the fixtures end to end

**Files:**
- Modify: `core/domain/logStream.js` (`_foldChunk` and the comment above `foldLine`)
- Test: `tests/core/domain/tst_log_stream.qml` (an import, a helper, tests)

**Interfaces:**
- Consumes: `_foldChunk`, `_displayLine`, `_cap`, `_ELLIPSIS`, `utf8Length` from Tasks 1-2; test helpers `rep`, `chunk`, `foldAll` from Task 2; `tests/helpers/amFixtures.js` `load(name)` (existing, unchanged; returns a fresh parse of `tests/fixtures/am/<name>`).
- Produces: the final `foldLine` behaviour: `offset < nextOffset - slack` → `ignored`; `offset > nextOffset` → `gapBytes += N`, held partial committed, `[… N bytes not shown]` appended; `slack = 2 × count(U+FFFD in text)` after every accepted chunk.

- [ ] **Step 1: Add the fixture import and line reader**

In `tests/core/domain/tst_log_stream.qml`, after the line `import "../../../core/domain/logStream.js" as LS` insert:

```qml
import "../../helpers/amFixtures.js" as F
```

Then, after the closing `  }` of the helper `foldAll` and its following blank line (before `  // ---- sanitize ---…`), insert:

```qml
  // Every non-empty line of tests/fixtures/am/<name>, JSON-parsed.
  function jsonLines(name) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl("../../fixtures/am/" + name), false)
    xhr.send()
    var rows = xhr.responseText.split("\n")
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i] !== "") out.push(JSON.parse(rows[i]))
    return out
  }

```

- [ ] **Step 2: Write the failing tests**

After the closing `  }` of `test_buffer_text_shapes` and before the file's final `}`, insert:

```qml

  // ---- offsets ----------------------------------------------------------------------------

  function test_fold_ignores_a_duplicate_chunk() {
    var b = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "abcdefghi\n")).buffer
    compare(b.nextOffset, 10)
    var dup = LS.foldLine(b, chunk(4, "efghi\n"))
    compare(dup.kind, "ignored")
    compare(dup.buffer, b)
    var next = LS.foldLine(b, chunk(10, "j\n"))
    compare(next.kind, "chunk")
    compare(next.buffer.lines, ["abcdefghi", "j"])
  }

  function test_fold_gap_adds_a_marker_line() {
    var b = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "abcdefghi\n")).buffer
    var r = LS.foldLine(b, chunk(25, "z\n"))
    compare(r.kind, "chunk")
    compare(r.buffer.lines, ["abcdefghi", "[\u2026 15 bytes not shown]", "z"])
    compare(r.buffer.gapBytes, 15)
    compare(r.buffer.nextOffset, 27)
    var again = LS.foldLine(r.buffer, chunk(30, "w\n"))
    compare(again.buffer.lines.slice(-2), ["[\u2026 3 bytes not shown]", "w"])
    compare(again.buffer.gapBytes, 18)
  }

  function test_fold_gap_commits_the_held_partial_first() {
    var r = foldAll(LS.emptyBuffer(1000), [chunk(0, "ab"), chunk(9, "cd\n")])
    compare(r.buffer.lines, ["ab", "[\u2026 7 bytes not shown]", "cd"])
    compare(r.buffer.partial, "")
  }

  function test_fold_gap_from_an_empty_buffer() {
    var r = LS.foldLine(LS.emptyBuffer(1000), chunk(500, "x\n"))
    compare(r.buffer.lines, ["[\u2026 500 bytes not shown]", "x"])
    compare(r.buffer.gapBytes, 500)
  }

  function test_fold_gap_marker_counts_toward_the_cap() {
    var r = LS.foldLine(LS.emptyBuffer(2), chunk(10, "a\nb\n"))
    compare(r.buffer.lines, ["a", "b"])
    compare(r.buffer.dropped, 1)
    compare(r.buffer.gapBytes, 10)
  }

  function test_fold_resume_after_hello() {
    var r = foldAll(LS.emptyBuffer(1000), [{ event: "logs", offset: 40, path: "p", schema: 1 }, chunk(40, "ok\n")])
    compare(r.kinds, ["hello", "chunk"])
    compare(r.buffer.lines, ["ok"])
    compare(r.buffer.gapBytes, 0)
    compare(r.buffer.nextOffset, 43)
  }

  function test_fold_slack_after_fffd_accepts_the_exact_next_offset() {
    var b = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\uFFFD\n")).buffer
    compare(b.nextOffset, 5)
    compare(b.slack, 2)
    var r = LS.foldLine(b, chunk(3, "b\n"))
    compare(r.kind, "chunk")
    compare(r.buffer.lines, ["a\uFFFD", "b"])
    compare(r.buffer.gapBytes, 0)
    compare(r.buffer.nextOffset, 5)
    compare(r.buffer.slack, 0)
    var early = LS.foldLine(b, chunk(2, "b\n"))
    compare(early.kind, "ignored")
    compare(early.buffer, b)
  }

  function test_fold_resent_chunk_with_fffd_is_a_duplicate() {
    var b = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "a\uFFFD\n")).buffer
    var r = LS.foldLine(b, chunk(0, "a\uFFFD\n"))
    compare(r.kind, "ignored")
    compare(r.buffer.lines, ["a\uFFFD"])
  }

  function test_fold_multibyte_text_moves_next_offset_by_bytes() {
    var r = LS.foldLine(LS.emptyBuffer(1000), chunk(0, "h\u00e9llo \u20ac\uD834\uDD1E\n"))
    compare(r.buffer.nextOffset, 15)
  }

  // ---- fixtures, end to end ---------------------------------------------------------------

  function test_fixture_step_stream() {
    var r = foldAll(LS.emptyBuffer(1000), jsonLines("logs-follow-step.jsonl"))
    compare(r.kinds, ["hello", "chunk", "end"])
    compare(LS.bufferText(r.buffer), "==> verify-ok (exit 0)\nverified")
    compare(r.buffer.nextOffset, 32)
    compare(r.buffer.dropped, 0)
    compare(r.buffer.gapBytes, 0)
  }

  function test_fixture_agent_stream() {
    var r = foldAll(LS.emptyBuffer(1000), jsonLines("logs-follow-agent.jsonl"))
    compare(r.kinds, ["hello", "chunk", "end"])
    compare(LS.bufferText(r.buffer), "stub claude ok phase=review")
    compare(r.buffer.nextOffset, 28)
  }

  function test_fixture_refusal() {
    var r = LS.foldLine(LS.emptyBuffer(1000), F.load("logs-follow-refusal.json"))
    compare(r.kind, "refusal")
    compare(r.buffer, LS.emptyBuffer(1000))
  }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
Expected: `Totals: 38 passed, 7 failed`. The seven `FAIL!` lines are `test_fold_gap_adds_a_marker_line`, `test_fold_gap_commits_the_held_partial_first`, `test_fold_gap_from_an_empty_buffer`, `test_fold_gap_marker_counts_toward_the_cap`, `test_fold_ignores_a_duplicate_chunk`, `test_fold_resent_chunk_with_fffd_is_a_duplicate`, `test_fold_slack_after_fffd_accepts_the_exact_next_offset`, each `Compared values are not the same`. `test_fold_resume_after_hello`, `test_fold_multibyte_text_moves_next_offset_by_bytes` and the three `test_fixture_*` tests already pass: they pin behaviour Task 2 delivered (hello on an empty buffer, byte-counted `nextOffset`, contiguous streams).

- [ ] **Step 4: Implement offsets in `_foldChunk`**

In `core/domain/logStream.js` replace:

```javascript
// b (already a copy) with the chunk {offset, text} folded in.
function _foldChunk(b, offset, text) {
  var raw = b.partial + text
  var last = raw.lastIndexOf("\n")
  if (last >= 0) {
    var done = raw.slice(0, last).split("\n")
    for (var i = 0; i < done.length; i++) b.lines.push(_displayLine(done[i]))
    raw = raw.slice(last + 1)
  }
  if (raw.length > _MAX_PARTIAL) {
    b.lines.push(_displayLine(raw))
    raw = ""
  }
  b.partial = raw
  b.nextOffset = offset + utf8Length(text)
  _cap(b)
  return { buffer: b, kind: "chunk" }
}
```

with:

```javascript
// b (already a copy) with the chunk {offset, text} folded in.
function _foldChunk(b, offset, text) {
  if (offset < b.nextOffset - b.slack) return { buffer: b, kind: "ignored" }
  var raw = b.partial
  if (offset > b.nextOffset) {
    var gap = offset - b.nextOffset
    b.gapBytes += gap
    if (raw !== "") b.lines.push(_displayLine(raw))
    raw = ""
    b.lines.push("[" + _ELLIPSIS + " " + gap + " bytes not shown]")
  }
  raw += text
  var last = raw.lastIndexOf("\n")
  if (last >= 0) {
    var done = raw.slice(0, last).split("\n")
    for (var i = 0; i < done.length; i++) b.lines.push(_displayLine(done[i]))
    raw = raw.slice(last + 1)
  }
  if (raw.length > _MAX_PARTIAL) {
    b.lines.push(_displayLine(raw))
    raw = ""
  }
  b.partial = raw
  b.nextOffset = offset + utf8Length(text)
  b.slack = 2 * (text.split("\uFFFD").length - 1)
  _cap(b)
  return { buffer: b, kind: "chunk" }
}
```

- [ ] **Step 5: Update the `foldLine` contract comment**

In the same file replace:

```javascript
// {buffer, kind}: line folded into a new copy of buffer. kind is "refusal"
// (own ok === false), "hello" (event "logs"), "end" (event "end"), "chunk"
// ({offset, text}) or "ignored". A hello sets nextOffset to its offset on an
// empty buffer only. Only hello and chunk change the buffer.
```

with:

```javascript
// {buffer, kind}: line folded into a new copy of buffer. kind is "refusal"
// (own ok === false), "hello" (event "logs"), "end" (event "end"), "chunk"
// ({offset, text} at or after nextOffset - slack) or "ignored". A hello sets
// nextOffset to its offset on an empty buffer only; a chunk past nextOffset
// first appends "[… N bytes not shown]". Only hello and chunk change the buffer.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `timeout 120 env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -import tests/stubs -input tests/core/domain/tst_log_stream.qml 2>&1 | grep -E '^FAIL|Totals'`
Expected: `Totals: 45 passed, 0 failed`, no `FAIL!` line.

- [ ] **Step 7: Run the gate**

Run: `timeout 600 bash tests/run.sh`
Expected: pytest with no failures (including `tests/architecture`), every QML block `0 failed`, `== tests/core/domain/tst_log_stream.qml` then `Totals: 45 passed, 0 failed`, exit code 0.

- [ ] **Step 8: Commit**

```bash
git add core/domain/logStream.js tests/core/domain/tst_log_stream.qml
git commit -m "feat(domain): logStream.js offsets, gaps, U+FFFD slack and fixture streams"
```

---

## Spec coverage

| spec | where |
|---|---|
| B1 `sanitize` (CSI, OSC, other ESC, newline/end stop, `\r\n`, lone `\r`, controls, order, idempotent) | Task 1, tests 1-8 + Review Focus 3 |
| B2 `utf8Length` | Task 1, test 9 |
| B3 `emptyBuffer` | Task 2, tests 10-11 |
| B4 input buffer, kinds, hello, lines, cut, held-tail bound, cap | Task 2, tests 12-27 + Review Focus 1-2 |
| B4 offsets (duplicate, gap, slack) | Task 3, tests 28-34 + Review Focus 4-5 |
| B5 `bufferText` | Task 2, test 35 |
| Fixtures end to end | Task 3, tests 36-38 |
| Layering / architecture test | gate in every task |

One reading the spec leaves open is fixed here and stated in `_escapeEnd`'s comment: a CSI ends at its first character in U+0040–U+007E, so parameter, intermediate and control characters before it are all removed with it; an `ESC` plus intermediates with no valid final is the `ESC` alone.
<!-- task-pipeline: validated -->
