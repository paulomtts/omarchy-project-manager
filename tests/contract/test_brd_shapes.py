"""The installed brd still speaks the shape core/domain/brd-extras.js parses.

Hermetic: a throwaway project under tmp_path with its own HOME and
XDG_DATA_HOME (brd hashes the project path under $XDG_DATA_HOME/brd), so the
user's real boards are never read or written. Skipped when brd is absent.
"""
import json
import os
import shutil
import subprocess

import pytest

pytestmark = pytest.mark.skipif(shutil.which("brd") is None, reason="brd is not installed here")


@pytest.fixture
def board(tmp_path):
    root = tmp_path / "proj"
    (root / "docs").mkdir(parents=True)
    (root / "docs" / "a.md").write_text("# Design\n\nbody\n")
    env = dict(os.environ)
    env.update({"HOME": str(tmp_path / "home"), "XDG_DATA_HOME": str(tmp_path / "data"),
                "XDG_STATE_HOME": str(tmp_path / "state"), "BRD_AUTHOR": "tester"})
    (tmp_path / "home").mkdir()

    def run(*args):
        proc = subprocess.run(["brd", *args], cwd=root, env=env, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stdout + proc.stderr
        payload = json.loads(proc.stdout.strip().splitlines()[-1])
        assert payload["ok"] is True, payload
        return payload["data"]

    run("init", "--name", "contract")
    card = run("add", "--title", "Card One", "--description", "d")
    child = run("add", "--title", "Child", "--parent", card["id"])
    issue = run("issue", "open", "--title", "Broken build", "--body", "It fails.",
                "--blocks", card["id"], "--ref", card["id"])
    nested_issue = run("issue", "open", "--title", "Blocks a child", "--blocks", child["id"])
    run("comment", "add", card["id"], "a card comment")
    run("comment", "add", issue["id"], "an issue comment")
    run("doc", "add", "docs/a.md", "--title", "Design", "--tag", "design")
    return run, card, child, issue, nested_issue


def test_issue_list_carries_the_fields_the_parsers_read(board):
    run, card, _child, issue, _nested = board
    rows = run("issue", "list")
    row = next(r for r in rows if r["id"] == issue["id"])
    for key in ("id", "kind", "title", "body", "status", "close_reason", "blocks",
                "created_at", "updated_at", "comments", "refs", "referenced_by"):
        assert key in row, key
    assert row["kind"] == "issue"
    assert row["status"] == "open"
    assert row["blocks"] == [card["id"]]


def export_of(run):
    """The one project entry plain `brd export` returns (brd_export 2).

    The envelope is {"brd_export": 2, "projects": [{"project": {...}, "cards": ...,
    "issues": ..., "documents": ..., "comments": ..., "tags": ..., "refs": ...}]}.
    `--all` adds more entries; there is no flag that restores the old flat shape.
    """
    data = run("export")
    assert data["brd_export"] == 2
    assert len(data["projects"]) == 1
    return data["projects"][0]


def test_export_is_a_versioned_envelope_of_per_project_entries(board):
    run = board[0]
    data = run("export")
    assert set(data) == {"brd_export", "projects"}
    assert data["brd_export"] == 2
    project = data["projects"][0]["project"]
    for key in ("id", "name", "root_path", "created_at"):
        assert key in project, key
    assert project["name"] == "contract"


def test_export_carries_every_collection_and_the_same_issue_facts(board):
    run, card, _child, issue, _nested = board
    data = export_of(run)
    for key in ("project", "cards", "issues", "documents", "comments", "tags", "refs"):
        assert key in data, key
    exported = next(i for i in data["issues"] if i["id"] == issue["id"])
    listed = next(i for i in run("issue", "list") if i["id"] == issue["id"])
    # Ruling 1 rests on this: the export's issue facts match `brd issue list`.
    assert exported["status"] == listed["status"]
    for key in ("id", "title", "body", "status", "close_reason", "created_at", "updated_at"):
        assert key in exported, key
    comment = next(c for c in data["comments"] if c["entity_id"] == card["id"])
    for key in ("id", "entity_id", "author", "body", "created_at"):
        assert key in comment, key
    ref = next(r for r in data["refs"] if r["src_id"] == issue["id"])
    assert ref["dst_id"] == card["id"]
    assert "origin" in ref
    document = data["documents"][0]
    for key in ("id", "title", "source_path", "content", "content_hash"):
        assert key in document, key


def test_the_export_carries_only_explicit_refs_never_wikilink_ones(board):
    """Why the panel says "explicit references only": `brd export`'s per-project refs[] hold
    the refs somebody wrote with `--ref`, and never the origin:"link" refs a
    [[wikilink]] in a body creates. Those exist -- `brd show` and
    `brd issue list` report them per entity -- but the export does not carry
    them, so indexRefs() cannot see them either."""
    run, card, _child, issue, _nested = board
    linker = run("add", "--title", "Linker", "--description", "see [[%s]]" % card["id"])
    data = export_of(run)
    assert {r["origin"] for r in data["refs"]} == {"explicit"}
    assert [r for r in data["refs"] if r["src_id"] == linker["id"]] == []
    assert {r["dst_id"] for r in data["refs"] if r["src_id"] == issue["id"]} == {card["id"]}
    # The very same wikilink IS reported by the per-entity commands.
    assert [r["origin"] for r in run("show", linker["id"])["refs"]] == ["link"]


def test_the_export_drops_an_issues_blocks_and_keeps_them_on_the_card_tree(board):
    """indexBlockedCards() exists because of this: the export's issues carry no
    `blocks`, so the relation is read back off the nested cards' `blocked_by`."""
    run, card, child, issue, nested_issue = board
    data = export_of(run)
    exported = next(i for i in data["issues"] if i["id"] == issue["id"])
    assert "blocks" not in exported
    root = next(c for c in data["cards"] if c["id"] == card["id"])
    assert root["blocked_by"] == [issue["id"]]
    # Children are nested inside their parent and carry their own blocked_by.
    nested = next(c for c in root["children"] if c["id"] == child["id"])
    assert nested["blocked_by"] == [nested_issue["id"]]
    assert "children" in nested


def test_doc_list_reports_relative_paths_and_a_source_state(board):
    run = board[0]
    rows = run("doc", "list")
    assert len(rows) == 1
    for key in ("id", "kind", "title", "source_path", "source_state", "tags", "created_at", "updated_at"):
        assert key in rows[0], key
    assert rows[0]["kind"] == "document"
    assert rows[0]["source_path"] == "docs/a.md", "relative to the project root"
    assert rows[0]["source_state"] == "ok"
    assert "design" in rows[0]["tags"]


def test_a_deleted_source_file_becomes_a_missing_document(board, tmp_path):
    run = board[0]
    (tmp_path / "proj" / "docs" / "a.md").unlink()
    assert run("doc", "list")[0]["source_state"] != "ok"


def test_a_closed_issue_reports_a_close_reason_and_keeps_its_blocked_cards(board):
    run, card, _child, issue, _nested = board
    run("issue", "close", issue["id"])
    closed = next(i for i in run("issue", "list") if i["id"] == issue["id"])
    assert closed["status"] == "closed"
    assert closed["close_reason"]
    assert closed["blocks"] == [card["id"]]
    # The card keeps the closed issue in blocked_by, so the derived relation
    # still names the card -- exactly what `brd issue list` reports.
    root = next(c for c in export_of(run)["cards"] if c["id"] == card["id"])
    assert issue["id"] in root["blocked_by"]
