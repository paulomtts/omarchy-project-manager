// tests/core/domain/tst_results.qml
import QtQuick
import QtTest
import "../../../core/domain/results.js" as Results

TestCase {
  name: "DomainResults"

  function test_parse_json_line_success_exposes_the_payload() {
    var r = Results.parseJsonLine('{"ok": true, "snapshot": "/s"}\n', 0, "generic")
    compare(r.ok, true)
    compare(r.data.snapshot, "/s")
    compare(r.error, "")
  }

  function test_parse_json_line_uses_the_last_non_empty_line() {
    var r = Results.parseJsonLine('noise\n\n{"ok": true, "n": 2}\n\n', 0, "generic")
    compare(r.ok, true)
    compare(r.data.n, 2)
  }

  function test_parse_json_line_fails_on_a_nonzero_exit_code_even_when_ok_is_true() {
    var r = Results.parseJsonLine('{"ok": true}', 1, "generic")
    compare(r.ok, false)
    compare(r.error, "generic")
    compare(r.data.ok, true)
  }

  function test_parse_json_line_reports_the_payload_error() {
    var r = Results.parseJsonLine('{"ok": false, "error": "could not snapshot"}', 1, "generic")
    compare(r.ok, false)
    compare(r.error, "could not snapshot")
  }

  function test_parse_json_line_falls_back_to_the_generic_message() {
    compare(Results.parseJsonLine('{"ok": false}', 0, "generic").error, "generic")
    compare(Results.parseJsonLine('{"ok": false, "error": ""}', 0, "generic").error, "generic")
    compare(Results.parseJsonLine('{"ok": false, "error": 5}', 0, "generic").error, "generic")
  }

  function test_parse_json_line_on_garbage_or_nothing() {
    var g = Results.parseJsonLine("not json", 0, "generic")
    compare(g.ok, false)
    compare(g.data, null)
    compare(g.error, "generic")
    compare(Results.parseJsonLine("", 0, "generic").ok, false)
    compare(Results.parseJsonLine(undefined, 0, "generic").ok, false)
    compare(Results.parseJsonLine("   \n  \n", 0, "generic").data, null)
  }

  function test_parse_json_line_rejects_payloads_that_are_not_objects() {
    compare(Results.parseJsonLine("5", 0, "generic", false).ok, false)
    compare(Results.parseJsonLine("null", 0, "generic", false).ok, false)
    compare(Results.parseJsonLine('"text"', 0, "generic", false).ok, false)
  }

  // The viewer-state helper answers without an `ok` key.
  function test_parse_json_line_without_require_ok_accepts_a_plain_object() {
    var r = Results.parseJsonLine('{"last_project": "/home/u/p"}', 0, "generic", false)
    compare(r.ok, true)
    compare(r.data.last_project, "/home/u/p")
    compare(Results.parseJsonLine('{"last_project": "/x"}', 1, "generic", false).ok, false)
    compare(Results.parseJsonLine('{"last_project": "/x"}', 0, "generic", true).ok, false)
  }

  function test_last_line_is_the_last_non_empty_line_trimmed() {
    compare(Results.lastLine("noise\n  {\"a\":1}  \n\n \n"), '{"a":1}')
  }

  function test_last_line_of_nothing_is_empty() {
    compare(Results.lastLine(null), "")
    compare(Results.lastLine(undefined), "")
    compare(Results.lastLine(""), "")
    compare(Results.lastLine("\n \n\t"), "")
    compare(Results.lastLine(0), "")
  }

  function test_last_line_drops_a_carriage_return() {
    compare(Results.lastLine("x\r\ny\r\n"), "y")
  }

  function test_parse_envelope_reads_the_last_line_object() {
    var envelope = Results.parseEnvelope('warning: something\n{"ok":true,"n":2}\n\n')
    verify(envelope !== null, "an object")
    compare(envelope.n, 2)
    compare(envelope.ok, true)
  }

  function test_parse_envelope_rejects_json_that_is_not_an_object() {
    compare(Results.parseEnvelope("[1]"), null)
    compare(Results.parseEnvelope("3"), null)
    compare(Results.parseEnvelope("\"s\""), null)
    compare(Results.parseEnvelope("true"), null)
    compare(Results.parseEnvelope("null"), null)
  }

  function test_parse_envelope_rejects_garbage() {
    compare(Results.parseEnvelope("{not json"), null)
    compare(Results.parseEnvelope("ok"), null)
    compare(Results.parseEnvelope('{"ok":true}\ngarbage'), null)
  }

  function test_parse_envelope_of_nothing_is_null() {
    compare(Results.parseEnvelope(""), null)
    compare(Results.parseEnvelope(null), null)
    compare(Results.parseEnvelope(undefined), null)
    compare(Results.parseEnvelope("\n\n"), null)
  }

  // String.prototype.trim strips U+00A0, which JSON.parse does not accept as whitespace.
  function test_parse_envelope_trims_what_trim_strips() {
    var envelope = Results.parseEnvelope('{"a":1} ')
    verify(envelope !== null, "an object")
    compare(envelope.a, 1)
  }

  function test_parse_envelope_reads_a_crlf_reply() {
    var envelope = Results.parseEnvelope('warn\r\n{"ok":true}\r\n')
    verify(envelope !== null, "an object")
    compare(envelope.ok, true)
  }

  function test_parse_envelope_of_a_non_string_is_null() {
    compare(Results.parseEnvelope(5), null)
    compare(Results.parseEnvelope(true), null)
    compare(Results.parseEnvelope({}), null)
  }
}
