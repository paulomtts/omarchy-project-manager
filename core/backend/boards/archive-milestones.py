#!/usr/bin/env python3
"""Archive milestones: `brd update <id> --status archived`, once per id.

    archive-milestones.py <root_path> <id> [<id> ...]

Only the ids passed are touched, and only the card itself -- never its children.
The caller decides which milestones qualify; brd has no atomic guard, so nothing
is re-checked here. A failure for one id does not stop the others.

Prints one JSON line -- {"ok": bool, "results": [{"id", "ok", "error"?}]} -- and
exits 0 when every id was archived, 1 otherwise ({"ok": false, "error": ...}
when nothing could be attempted).
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from common.json_line import emit  # noqa: E402

TIMEOUT_SECONDS = 30


def archive_one(card_id, cwd):
    if card_id.startswith("-"):
        return {"id": card_id, "ok": False, "error": "not a card id"}
    try:
        proc = subprocess.run(["brd", "update", card_id, "--status", "archived"], cwd=cwd,
                              capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    except FileNotFoundError:
        return {"id": card_id, "ok": False, "error": "brd was not found on PATH"}
    except subprocess.TimeoutExpired:
        return {"id": card_id, "ok": False, "error": "brd timed out"}
    try:
        payload = json.loads(proc.stdout)
    except ValueError:
        payload = None
    if proc.returncode == 0 and isinstance(payload, dict) and payload.get("ok") is True:
        return {"id": card_id, "ok": True}
    message = ""
    if isinstance(payload, dict) and isinstance(payload.get("error"), dict):
        message = str(payload["error"].get("message") or "")
    message = message or (proc.stderr or proc.stdout or "").strip() or "brd update failed"
    return {"id": card_id, "ok": False, "error": message}


def main(argv):
    if len(argv) < 3:
        return emit({"ok": False, "error": "usage: archive-milestones.py <root_path> <id> [<id> ...]"}, 1)
    root = argv[1]
    if not os.path.isdir(root):
        return emit({"ok": False, "error": "project directory not found: %s" % root}, 1)
    seen = []
    for card_id in argv[2:]:
        if card_id not in seen:
            seen.append(card_id)
    results = [archive_one(card_id, root) for card_id in seen]
    ok = all(r["ok"] for r in results)
    return emit({"ok": ok, "results": results}, 0 if ok else 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
