"""docs/architecture.md documents runs-history.py and board-titles.py.

The `core/backend/runs/` paragraph describes `runs-history.py`'s argv, its am calls, its page limit and its
output, and counts the helpers it covers. A line outside the `RunTitlesStore.qml` bullet states
`board-titles.py`'s contract.
"""
import re

from test_run_store_callers import ROOT
from test_run_store_docs import bullet

DOC = ROOT / "docs" / "architecture.md"
README = ROOT / "README.md"
HISTORY = ROOT / "core" / "backend" / "runs" / "runs-history.py"
TITLES = ROOT / "core" / "backend" / "boards" / "board-titles.py"


def constant(path, name):
    """The integer a helper assigns to `name` at module level."""
    m = re.search(rf"^{name} = (\d+)$", path.read_text(), re.M)
    assert m, f"{path.name} assigns no {name}"
    return m.group(1)


def runs_paragraph():
    """The architecture.md line that starts with `core/backend/runs/`."""
    lines = [line for line in DOC.read_text().splitlines() if line.startswith("`core/backend/runs/`")]
    assert len(lines) == 1, f"{len(lines)} `core/backend/runs/` paragraphs, want 1"
    return lines[0]


def history_part():
    """The runs paragraph from its first `runs-history.py` on."""
    text = runs_paragraph()
    at = text.find("runs-history.py")
    assert at != -1, "the `core/backend/runs/` paragraph names no runs-history.py"
    return text[at:]


def test_backend_paragraph_documents_runs_history():
    part = history_part()
    missing = [token for token in ["--before", "--status", "`more`", "am status"] if token not in part]
    if not re.search(r"--since(?![\w-])", part):
        missing.append("--since")
    assert missing == []


def test_backend_paragraph_states_the_history_limit_and_default():
    part = history_part()
    for name in ["DEFAULT_LIMIT", "MAX_LIMIT"]:
        value = constant(HISTORY, name)
        assert re.search(rf"\b{value}\b", part), f"no {name} ({value}) in the runs-history.py description"


def test_backend_paragraph_counts_the_helpers_it_covers():
    text = runs_paragraph()
    assert "All three use" not in text
    assert "All five use only documented `am` commands" in text


def test_backend_paragraph_describes_no_global_history_keyset():
    part = history_part()
    assert "--all-projects" not in part and "cursor" not in part


def test_architecture_documents_board_titles_contract():
    first, store = bullet("RunTitlesStore.qml")
    span = range(first, first + len(store.splitlines()))
    seconds = constant(TITLES, "TIMEOUT_SECONDS")
    tokens = ["board-titles.py", "brd tree", "RootMissing", "BrdMissing", "BrdBadOutput", f"{seconds} s"]
    hits = [n for n, line in enumerate(DOC.read_text().splitlines(), 1)
            if n not in span and all(token in line for token in tokens)]
    assert len(hits) == 1, hits
