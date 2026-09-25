import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Monogray Dock: the icon-only task manager from the KDE Mystical Blue panel,
// rebuilt as an Omarchy bar widget. Pinned apps come first (in pin order),
// then any other running app. Every window of an app shares one icon. A thin
// line on the bar-edge side marks running apps; it turns accent-coloured and
// widens for the focused app.
//
// Right-click an icon for Pin to dock / Unpin from dock. Pins are saved in
// this widget's shell.json entry, so they can also be edited by hand:
//   { "id": "monogray.dock", "pinned": ["foot", "discord"] }
// Without a "pinned" key the dock starts with apps every Omarchy install ships.
// Each pin is a .desktop file id without the ".desktop" suffix.
BarWidget {
  id: root
  moduleName: "monogray.dock"

  // Files, browser, terminal, notes, office: all part of a stock Omarchy install.
  readonly property var defaultPins: ["org.gnome.Nautilus", "chromium", "foot", "obsidian", "libreoffice-startcenter"]
  // Set right after a pin/unpin so the dock updates before shell.json reloads.
  property var pendingPins: null
  readonly property var pinnedIds: root.pendingPins !== null ? root.pendingPins : root.setting("pinned", root.defaultPins)
  onSettingsChanged: root.pendingPins = null
  readonly property bool monochrome: root.setting("monochrome", true)
  readonly property int iconSize: Style.space(root.setting("iconSize", 18))
  readonly property real tileSize: root.vertical ? root.barSize : Style.space(30)

  // ------------------------------------------------------------ app model
  function resolveEntry(appId) {
    if (!appId) return null
    return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId)
  }

  function iconFor(key, entry) {
    var icon = entry && entry.icon ? String(entry.icon) : ""
    // Absolute icon paths in .desktop files are legal and common for AppImages.
    if (icon.indexOf("/") === 0) return Util.fileUrl(icon)
    var path = icon.length > 0 ? Quickshell.iconPath(icon, true) : ""
    if (path.length === 0) path = Quickshell.iconPath(key, true)
    if (path.length === 0) path = Quickshell.iconPath(String(key).toLowerCase(), true)
    return path.length > 0 ? path : Quickshell.iconPath("application-x-executable", true)
  }

  property var items: []

  function rebuild() {
    var groups = ({})
    var order = []
    var toplevels = ToplevelManager.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      var entry = root.resolveEntry(t.appId)
      var key = entry ? entry.id : String(t.appId || "")
      if (key.length === 0) continue
      if (!groups[key]) { groups[key] = { entry: entry, toplevels: [] }; order.push(key) }
      groups[key].toplevels.push(t)
    }

    var out = []
    var seen = ({})
    function add(key, entry, windows, pinned) {
      seen[key] = true
      out.push({
        key: key,
        entry: entry,
        name: entry && entry.name ? entry.name : key,
        icon: root.iconFor(key, entry),
        toplevels: windows,
        pinned: pinned
      })
    }

    for (var p = 0; p < root.pinnedIds.length; p++) {
      var pid = String(root.pinnedIds[p])
      if (seen[pid]) continue
      var g = groups[pid]
      var pinnedEntry = g ? g.entry : DesktopEntries.byId(pid)
      // Skip pins for apps that aren't installed rather than showing a blank icon.
      if (!g && !pinnedEntry) continue
      add(pid, pinnedEntry, g ? g.toplevels : [], true)
    }
    for (var o = 0; o < order.length; o++) {
      if (!seen[order[o]]) add(order[o], groups[order[o]].entry, groups[order[o]].toplevels, false)
    }
    root.items = out
  }

  onPinnedIdsChanged: root.rebuild()
  Component.onCompleted: root.rebuild()

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuild() }
  }
  // A window's appId can arrive after it is first listed.
  Instantiator {
    model: ToplevelManager.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onAppIdChanged() { root.rebuild() }
    }
  }
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuild() }
  }

  // -------------------------------------------------------------- actions
  function launch(item) {
    var entry = item.entry || DesktopEntries.byId(item.key)
    if (entry) entry.execute()
  }

  // Launch when closed, focus when open, and cycle through an app's windows
  // on repeated clicks.
  function activate(item) {
    var list = item.toplevels
    if (list.length === 0) { root.launch(item); return }
    var current = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].activated) { current = i; break }
    }
    list[(current + 1) % list.length].activate()
  }

  function closeAll(item) {
    for (var i = 0; i < item.toplevels.length; i++) item.toplevels[i].close()
  }

  // ----------------------------------------------------------- pinning
  function isPinned(key) { return root.pinnedIds.indexOf(key) !== -1 }

  // Only apps with a .desktop entry can be pinned: that's what relaunches them.
  function canPin(item) { return !!(item && item.entry) }

  function togglePin(item) {
    var next = root.pinnedIds.slice()
    var i = next.indexOf(item.key)
    if (i === -1) next.push(item.key)
    else next.splice(i, 1)
    root.savePins(next)
  }

  // `omarchy bar set` can't carry a list through the shell's IPC, so write
  // just this widget's "pinned" key with jq. The file is replaced atomically
  // and the shell hot-reloads it.
  function savePins(list) {
    root.pendingPins = list
    savePinsProcess.command = ["bash", "-c",
      'f="$HOME/.config/omarchy/shell.json"; tmp=$(mktemp) && ' +
      'jq --arg id "$1" --argjson pins "$2" ' +
      '\'.bar.layout |= with_entries(.value |= map(if .id == $id then . + {pinned: $pins} else . end))\' ' +
      '"$f" >"$tmp" && mv "$tmp" "$f"',
      "_", root.moduleName, JSON.stringify(list)]
    savePinsProcess.running = true
  }

  Process {
    id: savePinsProcess
    stderr: StdioCollector { onStreamFinished: if (text) console.warn("monogray.dock: couldn't save pins:", text.trim()) }
  }

  // --------------------------------------------------------- context menu
  property var menuItem: null
  property Item menuAnchor: null
  property bool menuOpen: false

  function openMenu(item, anchor) {
    if (root.bar) root.bar.hideTooltip(anchor)
    root.menuItem = item
    root.menuAnchor = anchor
    root.menuOpen = true
  }

  // PopupCard calls owner.close() on outside clicks.
  function close() { root.menuOpen = false }

  function menuActions() {
    var item = root.menuItem
    if (!item) return []
    var out = []
    if (root.canPin(item))
      out.push({ label: root.isPinned(item.key) ? "Unpin from dock" : "Pin to dock", run: function() { root.togglePin(item) } })
    if (item.entry)
      out.push({ label: "New window", run: function() { root.launch(item) } })
    if (item.toplevels.length > 0)
      out.push({ label: item.toplevels.length > 1 ? "Close all windows" : "Close window", run: function() { root.closeAll(item) } })
    return out
  }

  // --------------------------------------------------------------- layout
  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight
  visible: root.items.length > 0

  GridLayout {
    id: grid
    anchors.fill: parent
    columns: root.vertical ? 1 : Math.max(1, root.items.length)
    columnSpacing: Style.space(2)
    rowSpacing: Style.space(2)

    Repeater {
      model: root.items

      Item {
        id: tile
        required property var modelData

        readonly property bool running: modelData.toplevels.length > 0
        readonly property bool focused: {
          for (var i = 0; i < modelData.toplevels.length; i++) {
            if (modelData.toplevels[i].activated) return true
          }
          return false
        }

        Layout.preferredWidth: root.tileSize
        Layout.preferredHeight: root.vertical ? Style.space(30) : root.barSize

        // Soft hover wash, like the repo's rofi selection (white at 5-8%).
        Rectangle {
          anchors.fill: parent
          anchors.margins: Style.space(2)
          radius: Style.space(5)
          color: Util.alpha(Color.foreground, mouse.pressed ? 0.12 : 0.07)
          opacity: mouse.containsMouse ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        Image {
          id: icon
          anchors.centerIn: parent
          width: root.iconSize
          height: root.iconSize
          sourceSize.width: root.iconSize * 2
          sourceSize.height: root.iconSize * 2
          source: tile.modelData.icon
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          // Kept as a hidden layer so the effect can sample it as a texture.
          visible: !root.monochrome
          layer.enabled: root.monochrome
          opacity: tile.running ? 1 : 0.6
        }

        // Monochrome rendering: desaturate and lift toward white so colour
        // icons read like the repo's line-art icon set.
        MultiEffect {
          anchors.fill: icon
          source: icon
          visible: root.monochrome
          saturation: -1.0
          brightness: 0.25
          contrast: 0.15
          opacity: tile.running ? 1 : 0.55
        }

        // Running/focused marker on the bar-edge side of the icon.
        Rectangle {
          visible: tile.running
          color: tile.focused ? Color.accent : Util.alpha(Color.foreground, 0.4)
          radius: 1
          width: root.vertical ? Style.space(2) : (tile.focused ? Style.space(16) : Style.space(6))
          height: root.vertical ? (tile.focused ? Style.space(16) : Style.space(6)) : Style.space(2)
          x: root.vertical
            ? (root.bar && root.bar.position === "right" ? parent.width - width : 0)
            : (parent.width - width) / 2
          y: root.vertical
            ? (parent.height - height) / 2
            : (root.bar && root.bar.position === "bottom" ? parent.height - height : 0)
          Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 160 } }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
          onEntered: {
            if (!root.bar) return
            var n = tile.modelData.toplevels.length
            root.bar.showTooltip(tile, tile.modelData.name + (n > 1 ? " (" + n + " windows)" : ""))
          }
          onExited: if (root.bar) root.bar.hideTooltip(tile)
          onClicked: function(event) {
            if (root.bar) root.bar.hideTooltip(tile)
            if (event.button === Qt.MiddleButton) root.closeAll(tile.modelData)
            else if (event.button === Qt.RightButton) root.openMenu(tile.modelData, tile)
            else root.activate(tile.modelData)
          }
        }
      }
    }
  }

  PopupCard {
    id: menuPopup
    anchorItem: root.menuAnchor || root
    owner: root
    bar: root.bar
    open: root.menuOpen
    padding: Style.space(6)
    contentWidth: menuPopup.fittedContentWidth(Style.space(190))
    contentHeight: menuPopup.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: 0

      // App name, dimmed, as a heading
      Text {
        width: menuColumn.width
        leftPadding: Style.space(10)
        topPadding: Style.space(4)
        bottomPadding: Style.space(6)
        text: root.menuItem ? root.menuItem.name : ""
        elide: Text.ElideRight
        color: Util.alpha(Color.popups.text, 0.55)
        font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.menuOpen ? root.menuActions() : []

        Rectangle {
          required property var modelData
          width: menuColumn.width
          height: Style.space(28)
          radius: Style.space(5)
          color: rowMouse.containsMouse ? Util.alpha(Color.popups.text, 0.08) : "transparent"

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            text: modelData.label
            color: Color.popups.text
            font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              // Closing the menu empties this Repeater and destroys this row,
              // so take the action before closing.
              var action = modelData.run
              root.menuOpen = false
              action()
            }
          }
        }
      }
    }
  }
}
