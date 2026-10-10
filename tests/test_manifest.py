"""manifest.json: the bar widget and the service entry point, every other key as shipped."""
import json
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "manifest.json")

UNCHANGED = {
    "schemaVersion": 1,
    "id": "paulomtts.omarchy-project-manager",
    "name": "Omarchy Project Manager",
    "version": "1.0.0",
    "author": "paulomtts",
    "license": "MIT",
    "description": "Per-project board, milestone graph, documents and Claude memories for brd projects, right from the bar.",
    "activation": "on-demand",
    "barWidget": {
        "displayName": "Project Manager",
        "description": "One bar icon and one panel: pick a project in the sidebar, then browse its board, milestone graph, documents or Claude memories.",
        "category": "Productivity",
        "aliases": ["project manager", "brd", "board", "memories"],
        "allowMultiple": False,
    },
}


def manifest():
    with open(MANIFEST) as f:
        return json.load(f)


def test_kinds_are_bar_widget_and_service():
    assert manifest()["kinds"] == ["bar-widget", "service"]


def test_entry_points():
    assert manifest()["entryPoints"] == {
        "barWidget": "ui/Panel.qml",
        "service": "core/stores/RunAlertsService.qml",
    }


def test_every_entry_point_is_a_file_in_the_repo():
    for kind, path in manifest()["entryPoints"].items():
        assert isinstance(path, str) and path, kind
        assert not os.path.isabs(path), (kind, path)
        assert ":" not in path and "\\" not in path, (kind, path)
        assert ".." not in path.split("/"), (kind, path)
        assert os.path.isfile(os.path.join(REPO, path)), (kind, path)


def test_other_keys_unchanged():
    m = manifest()
    assert m["schemaVersion"] == 1
    assert m["id"] == "paulomtts.omarchy-project-manager"
    assert m["activation"] == "on-demand"
    assert m["barWidget"]["allowMultiple"] is False
    assert "keepLoaded" not in m
    assert {k: v for k, v in m.items() if k not in ("kinds", "entryPoints")} == UNCHANGED
