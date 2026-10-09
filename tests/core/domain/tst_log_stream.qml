// tests/core/domain/tst_log_stream.qml
import QtQuick
import QtTest
import "../../../core/domain/logStream.js" as LS

TestCase {
  name: "DomainLogStream"

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
    compare(LS.sanitize("a\x1béb"), "aéb")
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
    compare(LS.sanitize("�é𝄞\u0085"), "�é𝄞\u0085")
  }

  function test_sanitize_is_idempotent_and_total() {
    var sample = "\x1b[1mbold\x1b[0m\r\nx\x00y\r10%\r20%\n\x1b]0;t\x07\tz�\x1b"
    var once = LS.sanitize(sample)
    compare(once, "bold\n20%\n\tz�")
    compare(LS.sanitize(once), once)
    var bad = [undefined, null, 42, {}]
    for (var i = 0; i < bad.length; i++) compare(LS.sanitize(bad[i]), "", String(bad[i]))
  }

  // ---- utf8Length -------------------------------------------------------------------------

  function test_utf8_length_counts_bytes() {
    compare(LS.utf8Length("abc"), 3)
    compare(LS.utf8Length("héllo €𝄞"), 14)
    compare(LS.utf8Length("…"), 3)
    compare(LS.utf8Length(""), 0)
    compare(LS.utf8Length("\uD834"), 3)
    compare(LS.utf8Length("\uDD1E"), 3)
    compare(LS.utf8Length("�"), 3)
    var bad = [undefined, null, 42, {}, ["ab"]]
    for (var i = 0; i < bad.length; i++) compare(LS.utf8Length(bad[i]), 0, String(bad[i]))
  }

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
    compare(r.buffer.lines, ["𝄞"])
  }

  function test_fold_commits_an_overlong_tail() {
    var r = LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("x", 16385)))
    compare(r.buffer.lines, [rep("x", 2000) + "…"])
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
            [rep("a", 2000) + "…"])
    compare(LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("a", 2000) + "\n")).buffer.lines,
            [rep("a", 2000)])
    compare(LS.foldLine(LS.emptyBuffer(1000), chunk(0, rep("a", 1999) + "𝄞y\n")).buffer.lines,
            [rep("a", 1999) + "…"])
  }

  function test_fold_caps_lines_and_counts_dropped() {
    var r = foldAll(LS.emptyBuffer(3), [chunk(0, "1\n2\n3\n4\n5\n"), chunk(10, "6\n7\n")])
    compare(r.buffer.lines, ["5", "6", "7"])
    compare(r.buffer.dropped, 4)
    verify(LS.bufferText(r.buffer).indexOf("… 4 earlier lines\n") === 0, LS.bufferText(r.buffer))
    compare(LS.bufferText(r.buffer), "… 4 earlier lines\n5\n6\n7")
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
    compare(LS.bufferText(b), "… 1 earlier lines\nx")
    b.dropped = 0
    b.partial = "\x1b[1mhi\x1b[0m"
    compare(LS.bufferText(b), "x\nhi")
    var bad = [null, undefined, 42, "a", {}, { lines: "a" }]
    for (var i = 0; i < bad.length; i++) compare(LS.bufferText(bad[i]), "", String(bad[i]))
  }
}
