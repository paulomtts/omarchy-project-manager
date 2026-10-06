# Test helpers

`find.js` is a `.pragma library` with `find(item, name)`, a depth-first search by
`objectName` through `children`, `data` and `contentItem`. Import it from a QML
test with a path relative to the test file:

    .import "../helpers/find.js" as H

(`import "../helpers/find.js" as H` in tests under `tests/ui`; adjust the `..`
count for deeper folders.)

`amFixtures.js` is a `.pragma library` with `load(name)`. It returns a fresh
parse of `tests/fixtures/am/<name>` on every call, so edits never leak between
tests, and it throws an `Error` naming `<name>` when the file cannot be read or
parsed. It reads through `XMLHttpRequest`, which needs `QML_XHR_ALLOW_FILE_READ=1`;
`tests/run.sh` sets it. Which tests must build their am input from these
fixtures is the rule in `docs/architecture.md`'s Tests section. From a test
under `tests/<dir>/`:

    import "../helpers/amFixtures.js" as F
