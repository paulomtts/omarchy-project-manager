import QtQml

// The plugin's `service` entry point (manifest.json entryPoints.service). The
// shell creates one per shell, with no parent, while the plugin is enabled,
// and destroys it with the plugin; App does not compose it. `backendDir` is
// the absolute path of <plugin>/core/backend/, with a trailing "/" and no
// file:// scheme, derived from this file's own URL -- the same string
// ui/Panel.qml hands App as backendDir.
QtObject {
  id: service

  readonly property string backendDir: Qt.resolvedUrl("../backend/").toString().replace(/^file:\/\//, "")   // <plugin>/core/backend/
}
