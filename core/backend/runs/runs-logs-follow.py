#!/usr/bin/env python3
"""One attempt's stdout as a stream, from `am logs ... --follow`.

    runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]

ATTEMPT and OFFSET are one or more ASCII decimal digits, passed as their
integer. Any other argv is a Usage error (exit 2) and am is neither looked up
nor started. REPO, RUN, CARD and PHASE reach am verbatim; am refuses bad ones
itself. Long-lived. Spawns, as an argv list (no shell, stdin /dev/null),
    am logs RUN CARD --phase PHASE [--attempt ATTEMPT] --follow
        [--since-offset OFFSET] --repo-dir REPO
with --attempt omitted when ATTEMPT is 0 and --since-offset omitted when
OFFSET is absent or 0. Prints one compact JSON object per line, flushed at once:
  every JSON object am prints that has no `ok` key (the hello, each chunk, the
      end line, any other object), its keys and values unchanged; a hello
      (event "logs") must carry the integer schema 1 or 2, else SchemaMismatch;
  am's refusal envelope (an object with an `ok` key read before any line was
      printed), unchanged, as the only line; every later am line is ignored;
  {"ok": false, "error": {"type", "message"}}
      as the last line, with type AmMissing, FollowUnsupported (am exited 2
      without printing anything), SchemaMismatch (am is stopped), StreamError
      (am exited non-zero after a hello; message: am's last stderr line),
      HelperError (any other non-zero exit, or an unexpected failure) or Usage.
Any other line am prints (not JSON, not an object, or an `ok` object after a
printed line) is skipped; a non-zero count is written to stderr as
`runs-logs-follow: skipped N non-JSON lines`. am exiting 0 adds no line.
Exit 0 on every path except Usage. SIGINT, SIGTERM or a closed stdout stop am
(terminate, wait 2 s, kill) and end the helper with exit 0 and nothing more
printed. am is never left running. Only the `am logs` command is used; am's
data dir is never read and the hello's path is never opened.
"""
import json
import shutil
import subprocess
import sys
import threading

USAGE = "usage: runs-logs-follow.py REPO RUN CARD PHASE ATTEMPT [OFFSET]"


def say(payload, code=0):
    """Print `payload` as one compact JSON line and flush it now: stdout is a
    pipe, so it is block-buffered."""
    print(json.dumps(payload, separators=(",", ":")))
    sys.stdout.flush()
    return code


def failure(kind, message, code=0):
    return say({"ok": False, "error": {"type": kind, "message": message}}, code)


def number(text):
    """The integer of one or more ASCII decimal digits, else None."""
    return int(text) if text.isascii() and text.isdigit() else None


def parse_args(argv):
    """(repo, run, card, phase, attempt, offset) for 5 or 6 arguments whose
    ATTEMPT and OFFSET (0 when absent) are ASCII digits, else None."""
    if len(argv) not in (5, 6):
        return None
    attempt = number(argv[4])
    offset = number(argv[5]) if len(argv) == 6 else 0
    if attempt is None or offset is None:
        return None
    return argv[0], argv[1], argv[2], argv[3], attempt, offset


def command(am, repo, run, card, phase, attempt, offset):
    """am's argv: --attempt only when attempt is not 0, --since-offset only when
    offset is not 0."""
    return [am, "logs", run, card, "--phase", phase,
            *(["--attempt", str(attempt)] if attempt else []), "--follow",
            *(["--since-offset", str(offset)] if offset else []), "--repo-dir", repo]


def spawn(argv):
    return subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, encoding="utf-8",
                            errors="replace")


class Seen:
    """What the helper read from am's stdout and printed so far."""

    def __init__(self):
        self.lines = 0  # every stdout line am printed, skipped ones included
        self.skipped = 0
        self.printed = False
        self.hello = False  # a hello was printed
        self.refusal = False


def collect(stream, parts):
    """Reader thread: am's whole stderr, so a chatty am never blocks on a full pipe."""
    parts.append(stream.read())


def stop(proc):
    """Terminate am if it is still running (kill it after 2 s), and reap it."""
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def stream(lines, seen):
    """Print each of am's stdout `lines` that is a JSON object, recording in
    `seen`. An object with an `ok` key read before any printed line is the
    refusal: printed, and every later line ignored. Every other line that is not
    a JSON object without an `ok` key is skipped and counted."""
    for raw in lines:
        seen.lines += 1
        if seen.refusal:
            continue
        try:
            line = json.loads(raw)
        except ValueError:
            line = None
        if not isinstance(line, dict) or ("ok" in line and seen.printed):
            seen.skipped += 1
            continue
        if "ok" in line:
            seen.refusal = True
        elif line.get("event") == "logs":
            seen.hello = True
        say(line)
        seen.printed = True


def finish(code, seen, stderr):
    """Print the last line, if any, for how am ended; return the helper's exit code."""
    return 0


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return failure("Usage", USAGE, 2)
    am = shutil.which("am")
    if am is None:
        return failure("AmMissing", "am is not installed.")
    proc = spawn(command(am, *parsed))
    err, seen = [], Seen()
    err_reader = threading.Thread(target=collect, args=(proc.stderr, err), daemon=True)
    err_reader.start()
    try:
        stream(proc.stdout, seen)
        code = proc.wait()
        err_reader.join(timeout=2)
    finally:
        stop(proc)  # no-op once am has exited; terminates it on every other path
        if seen.skipped:
            sys.stderr.write("runs-logs-follow: skipped %d non-JSON lines\n" % seen.skipped)
            sys.stderr.flush()
    return finish(code, seen, "".join(err))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
