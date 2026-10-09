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
