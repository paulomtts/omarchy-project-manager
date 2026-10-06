#!/usr/bin/env bash
# Runs everything: pytest, then every QML test against the REAL repo files,
# mirrored into a temp dir so relative imports resolve exactly as in the plugin.
# Usage: tests/run.sh [substring-filter-for-qml-test-paths]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
cd "$repo"
filter="${1:-}"

# python3 may be a uv-managed interpreter, which refuses installs and so has no
# pytest. Fall back to uv's throwaway environment rather than failing.
if python3 -c 'import pytest' 2>/dev/null; then
  python3 -m pytest tests -q
else
  uv run --with pytest python3 -m pytest tests -q
fi

runner=$(command -v /usr/lib/qt6/bin/qmltestrunner || command -v qmltestrunner)
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/repo"
tar --exclude=.git --exclude=__pycache__ --exclude=.pytest_cache --exclude=.superpowers -cf - . | tar -xf - -C "$work/repo"

status=0
while IFS= read -r test; do
  case "$test" in *"$filter"*) ;; *) continue ;; esac
  echo "== ${test#$repo/}"
  out=$(QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 "$runner" -import "$work/repo/tests/stubs" -input "$work/repo/${test#$repo/}" 2>&1) || status=1
  echo "$out" | grep -E "^(FAIL|Totals)|^   Loc" || true
  bad=$(echo "$out" | grep -E "TypeError|ReferenceError|non-existent|Unable to assign|anchors on an item|is not a function" | grep -v "width' of null" || true)
  if [ -n "$bad" ]; then echo "$bad"; status=1; fi
done < <(find "$repo/tests" -name 'tst_*.qml' | sort)
exit $status
