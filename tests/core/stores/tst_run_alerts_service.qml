// tests/core/stores/tst_run_alerts_service.qml
// The service entry point: it builds as the shell's ensureService builds it
// (createObject(null), no properties), declares none of the properties the
// shell injects, and its backendDir is the plugin's real core/backend/.
import QtQuick
import QtTest
import Qt.labs.folderlistmodel

TestCase {
  id: tc
  name: "StoresRunAlertsService"
  when: windowShown
  width: 400; height: 400

  Component { id: hostC; Item { width: 400; height: 400 } }

  // A directory listing is the only filesystem read QML offers here.
  FolderListModel { id: folder; showDirs: true; showFiles: true; showDotAndDotDot: false }

  function fileExists(path) {
    var slash = path.lastIndexOf("/")
    var dir = path.substring(0, slash)
    var name = path.substring(slash + 1)
    folder.folder = "file://" + dir
    // The model loads asynchronously and still lists the previous folder (at
    // first, the working directory) for a while: poll until it lists entries
    // of `dir` itself or the budget runs out.
    for (var t = 0; t < 40; t++) {
      if (folder.status === FolderListModel.Ready && folder.count > 0
          && String(folder.get(0, "filePath")).indexOf(dir + "/") === 0) break
      tc.wait(20)
    }
    for (var i = 0; i < folder.count; i++)
      if (folder.get(i, "fileName") === name) return true
    return false
  }

  // Built exactly as the shell builds a third-party service: no parent, no properties.
  function make() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsService.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return null }
    return comp.createObject(null)
  }

  function test_it_loads_and_instantiates_without_a_parent_or_properties() {
    var comp = Qt.createComponent("../../../core/stores/RunAlertsService.qml")
    compare(comp.status, Component.Ready, comp.errorString())
    var s = comp.createObject(null)
    verify(s !== null, "createObject(null) returned null")
    s.destroy()
  }

  function test_it_can_be_created_again_after_it_was_destroyed() {
    var a = make(); if (!a) return
    var dir = a.backendDir
    a.destroy()
    wait(0)
    var b = make(); if (!b) return
    compare(b.backendDir, dir)
    b.destroy()
  }

  function test_backend_dir_is_the_absolute_core_backend_of_the_plugin() {
    var s = make(); if (!s) return
    var dir = s.backendDir
    s.destroy()
    verify(dir.indexOf("/") === 0, "not an absolute path: " + dir)
    verify(dir.indexOf("file:") === -1, "still a URL: " + dir)
    verify(dir.endsWith("/core/backend/"), dir)
    verify(fileExists(dir + "runs/runs-alerts.py"), "no runs/runs-alerts.py under " + dir)
  }

  function test_backend_dir_is_what_the_panel_hands_app() {
    var s = make(); if (!s) return
    var dir = s.backendDir
    s.destroy()
    var host = createTemporaryObject(hostC, tc)
    var comp = Qt.createComponent("../../../ui/Panel.qml")
    if (comp.status !== Component.Ready) { fail(comp.errorString()); return }
    var p = comp.createObject(host)
    verify(p !== null, "Panel did not build")
    compare(dir, p.app.backendDir)
  }

  function test_the_shell_injects_nothing() {
    var s = make(); if (!s) return
    verify("backendDir" in s, "the in-operator sees no declared property")
    verify(!("shell" in s), "declares shell")
    verify(!("manifest" in s), "declares manifest")
    verify(!("omarchyPath" in s), "declares omarchyPath")
    verify(!("pluginRegistry" in s), "declares pluginRegistry")
    verify(!("barWidgetRegistry" in s), "declares barWidgetRegistry")
    s.destroy()
  }
}
