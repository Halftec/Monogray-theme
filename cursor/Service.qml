import QtQuick
import Quickshell.Io

// No UI. Applies the cursor theme once whenever the shell loads this plugin:
// at login, after `omarchy restart shell`, and when the plugin is enabled.
// The work is in apply.sh so it can also be run by hand.
Item {
  id: root

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace("file://", ""))

  Component.onCompleted: applyProcess.running = true

  Process {
    id: applyProcess
    command: ["bash", root.pluginDir + "apply.sh"]
    stdout: StdioCollector { onStreamFinished: if (text) console.log(text.trim()) }
    stderr: StdioCollector { onStreamFinished: if (text) console.warn("monogray-cursor:", text.trim()) }
  }
}
