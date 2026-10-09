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
}
