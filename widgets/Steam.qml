import Quickshell
import Quickshell.Io
import QtQuick

// Steam widget - capsule-art grid of recently played Steam games.
// Data comes from the bundled steam_recent.py helper (local files only:
// localconfig.vdf recency, appmanifest names, librarycache art — no
// network, no API key). Non-Steam shortcuts merge in from shortcuts.vdf +
// grid/ custom artwork, marked with a "non-Steam" badge. Battle.net games
// from the local umu prefix merge in via Battle.net.config recency +
// Lutris coverart, marked with a "Battle.net" badge and launched via
// umu-run Battle.net.exe --exec="launch <CODE>". Click a tile to
// launch. Display-only otherwise; positioning mirrors
// Clock/Date (xRatio/yRatio).
Item {
  id: root

  property var widgetSettings: ({})
  property color themeColor: "#ffffff"

  readonly property bool enabled: widgetSettings.enabled === true
  // Set by the host from the per-output active workspace. A widget hidden on
  // the wrong workspace must also drop its click-mask regions, or invisible
  // tiles keep eating clicks on the full-screen bottom layer.
  property bool workspaceVisible: true
  readonly property bool interactive: widgetSettings.interactive !== false
  readonly property int gameCount: Math.max(1, Math.min(15, Math.round(Number(widgetSettings.count) || 5)))
  readonly property int tileWidth: Math.max(120, Math.round(Number(widgetSettings.tileWidth) || 208))
  readonly property int tileHeight: Math.max(60, Math.round(Number(widgetSettings.tileHeight) || 120))
  readonly property int tileSpacing: (typeof widgetSettings.spacing === "number") ? Math.max(0, Math.round(widgetSettings.spacing)) : 12
  readonly property int cornerRadius: (typeof widgetSettings.cornerRadius === "number") ? Math.max(0, Math.round(widgetSettings.cornerRadius)) : 10
  readonly property bool showName: widgetSettings.showName !== false
  readonly property bool showMeta: widgetSettings.showMeta !== false
  readonly property bool showBigPicture: widgetSettings.showBigPicture !== false
  readonly property string bigPictureLabel: widgetSettings.bigPictureLabel ? String(widgetSettings.bigPictureLabel) : "Big Picture"
  readonly property string bigPictureArt: "file:///usr/share/icons/hicolor/256x256/apps/steam.png"
  readonly property real opacityVal: (typeof widgetSettings.opacity === "number") ? widgetSettings.opacity : 0.95
  readonly property real xRatio: (typeof widgetSettings.xRatio === "number") ? widgetSettings.xRatio : 0.17
  readonly property real yRatio: (typeof widgetSettings.yRatio === "number") ? widgetSettings.yRatio : 0.90
  readonly property int refreshSec: Math.max(15, Math.round(Number(widgetSettings.refreshInterval) || 60))
  readonly property bool requireArt: widgetSettings.requireArt !== false
  readonly property bool showShortcuts: widgetSettings.showShortcuts !== false
  readonly property bool showSourceBadge: widgetSettings.showSourceBadge !== false
  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/primo.widgets/steam_recent.py"
  readonly property string activeFont: widgetSettings.fontFamily === "system"
    ? ""
    : (widgetSettings.fontFamily ? widgetSettings.fontFamily : "Inter Variable")

  readonly property color activeColor: widgetSettings.color
    ? Qt.color(widgetSettings.color)
    : root.themeColor

  readonly property string hideArg: {
    var h = widgetSettings.hideIds
    if (Array.isArray(h)) return h.join(",")
    if (typeof h === "string" && h.length > 0) return h
    return "480"
  }

  // Parsed helper output: [{appid, name, lastPlayed, playtimeMin, art}]
  property var games: []
  // Tile items exposed for Service.qml's input mask (click-to-launch)
  property var clickTargets: []

  readonly property int labelHeight: (root.showName ? 18 : 0) + (root.showMeta ? 15 : 0)
  // A link is pointless when display-only, so the Big Picture tile only
  // exists (and takes up width) in interactive mode.
  readonly property bool bpVisible: root.showBigPicture && root.interactive && root.enabled
  readonly property int tileTotal: Math.max(1, root.games.length) + (root.bpVisible ? 1 : 0)
  width: root.tileTotal * root.tileWidth + Math.max(0, root.tileTotal - 1) * root.tileSpacing
  height: root.tileHeight + root.labelHeight
  x: parent ? Math.round(parent.width * root.xRatio - width / 2) : 0
  y: parent ? Math.round(parent.height * root.yRatio - height / 2) : 0
  // No `visible:` binding here on purpose: Service.qml owns visibility so it
  // can AND in the per-workspace gate. A binding on this root would override
  // the host's and silently defeat it.
  opacity: root.opacityVal

  function nowSec() {
    try {
      var t = wallClock.date.getTime()
      if (typeof t === "number" && isFinite(t)) return t / 1000
    } catch (e) {}
    return -1
  }

  function relTime(epochSec) {
    var ep = Number(epochSec)
    var n = root.nowSec()
    if (n > 0 && ep > 0) {
      var diff = Math.max(0, n - ep)
      if (diff < 3600) {
        var m = Math.max(1, Math.round(diff / 60))
        return m + "m ago"
      }
      if (diff < 86400) return Math.round(diff / 3600) + "h ago"
      if (diff < 86400 * 30) return Math.round(diff / 86400) + "d ago"
    }
    if (ep > 0) {
      try { return Qt.formatDateTime(new Date(ep * 1000), "MMM d") } catch (e) {}
    }
    return ""
  }

  function metaLine(g, _tick) {
    var parts = []
    if (g.lastPlayed) parts.push(root.relTime(g.lastPlayed))
    var hrs = Math.round(Number(g.playtimeMin || 0) / 60)
    if (hrs > 0) parts.push(hrs >= 1000 ? (hrs / 1000).toFixed(1) + "k h" : hrs + "h")
    return parts.join("  •  ")
  }

  function helperCommand() {
    var cmd = ["python3", root.helperPath, "--count", String(root.gameCount),
               "--hide", root.hideArg]
    if (!root.requireArt) cmd.push("--no-require-art")
    if (!root.showShortcuts) cmd.push("--no-shortcuts")
    if (widgetSettings.steamId) cmd.push("--steam-id", String(widgetSettings.steamId))
    if (widgetSettings.steamRoot) cmd.push("--steam-root", String(widgetSettings.steamRoot))
    if (widgetSettings.showBattlenet === false) cmd.push("--no-battlenet")
    if (widgetSettings.battlenetPrefix) cmd.push("--battlenet-prefix", String(widgetSettings.battlenetPrefix))
    if (widgetSettings.battlenetConfig) cmd.push("--battlenet-config", String(widgetSettings.battlenetConfig))
    if (widgetSettings.lutrisCoverDir) cmd.push("--lutris-cover-dir", String(widgetSettings.lutrisCoverDir))
    if (widgetSettings.names && typeof widgetSettings.names === "object")
      cmd.push("--names", JSON.stringify(widgetSettings.names))
    return cmd
  }

  function refresh() {
    if (!root.enabled || steamProc.running) return
    steamProc.command = root.helperCommand()
    steamProc.running = true
  }

  function launch(game) {
    if (game && typeof game === "object" && game.source === "battlenet" && game.launchCode) {
      root.launchBattlenet(game)
    } else if (game && typeof game === "object" && game.source === "shortcut" && game.exe) {
      var exe = String(game.exe)
      var dir = String(game.startDir || "")
      var opts = String(game.launchOptions || "")
      if (exe.startsWith('"') && exe.endsWith('"')) exe = exe.slice(1, -1)
      if (dir.startsWith('"') && dir.endsWith('"')) dir = dir.slice(1, -1)
      var cmd = ""
      if (dir) cmd += "cd " + JSON.stringify(dir) + " && "
      cmd += JSON.stringify(exe)
      if (opts) cmd += " " + opts
      cmd += " &"
      console.log("primo.widgets shortcut launch: " + cmd)
      Quickshell.execDetached(["bash", "-c", cmd])
    } else {
      var id = String((game && typeof game === "object") ? (game.rungameid || game.appid) : game)
      console.log("primo.widgets Steam launch " + id)
      Quickshell.execDetached(["bash", "-c",
        "command -v steam >/dev/null && steam 'steam://rungameid/" + id + "' 2>/dev/null || xdg-open 'steam://rungameid/" + id + "' 2>/dev/null &"])
    }
  }

  function launchBigPicture() {
    console.log("primo.widgets Steam big picture")
    Quickshell.execDetached(["bash", "-c",
      "command -v steam >/dev/null && steam 'steam://open/bigpicture' 2>/dev/null || xdg-open 'steam://open/bigpicture' 2>/dev/null &"])
  }

  function launchBattlenet(game) {
    var code = String(game.launchCode || game.rungameid || "")
    var prefix = game.prefix ? String(game.prefix)
      : (widgetSettings.battlenetPrefix ? String(widgetSettings.battlenetPrefix)
        : Quickshell.env("HOME") + "/Games/battlenet")
    var proton = widgetSettings.battlenetProton ? String(widgetSettings.battlenetProton) : "GE-Proton"
    var gameid = widgetSettings.battlenetGameId ? String(widgetSettings.battlenetGameId) : "umu-battlenet"
    var exe = prefix + "/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
    // One argv "--exec=launch <CODE>" mirrors the Windows shortcut
    // Target: ".../Battle.net.exe" --exec="launch <CODE>"
    var cmd = "WINEPREFIX=" + JSON.stringify(prefix)
      + " PROTONPATH=" + JSON.stringify(proton)
      + " GAMEID=" + JSON.stringify(gameid)
      + " PROTON_VERB=run umu-run " + JSON.stringify(exe)
      + " " + JSON.stringify("--exec=launch " + code) + " &"
    console.log("primo.widgets Battle.net launch " + code)
    Quickshell.execDetached(["bash", "-c", cmd])
  }

  function syncTargets() {
    var arr = []
    if (root.interactive && root.enabled && root.workspaceVisible) {
      for (var i = 0; i < tileRow.children.length; i++) {
        var c = tileRow.children[i]
        if (c && c.isSteamTile === true && c.tileReady === true) arr.push(c)
      }
    }
    var same = arr.length === root.clickTargets.length
    if (same) for (var j = 0; j < arr.length; j++) if (arr[j] !== root.clickTargets[j]) { same = false; break }
    if (!same) root.clickTargets = arr
  }

  onWidgetSettingsChanged: Qt.callLater(root.refresh)
  onEnabledChanged: { pollTimer.running = root.enabled; Qt.callLater(root.refresh); Qt.callLater(root.syncTargets) }
  onInteractiveChanged: Qt.callLater(root.syncTargets)
  onGamesChanged: Qt.callLater(root.syncTargets)

  Component.onCompleted: {
    console.log("primo.widgets Steam count=" + root.gameCount + " tile=" + root.tileWidth + "x" + root.tileHeight)
    Qt.callLater(root.refresh)
  }

  Timer {
    id: pollTimer
    interval: Math.max(15000, root.refreshSec * 1000)
    repeat: true
    running: root.enabled
    onTriggered: root.refresh()
  }

  // Wall-clock source for "x ago" labels (Date.now is unavailable in this engine)
  SystemClock {
    id: wallClock
    precision: SystemClock.Minutes
  }

  Process {
    id: steamProc
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.games = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          console.warn("primo.widgets Steam: invalid helper output: " + String(e).slice(0, 120))
        }
      }
    }
    stderr: SplitParser {
      onRead: data => console.warn("primo.widgets Steam helper: " + String(data).slice(0, 200))
    }
  }

  // Drives syncTargets for tiles created/destroyed by the Repeater
  Timer {
    id: targetSyncTimer
    interval: 500
    repeat: false
    onTriggered: root.syncTargets()
  }

  Row {
    id: tileRow
    anchors.fill: parent
    spacing: root.tileSpacing

    Repeater {
      model: root.games
      delegate: Item {
        id: tile
        required property var modelData
        required property int index
        property bool isSteamTile: true
        property bool tileReady: root.enabled && root.interactive

        width: root.tileWidth
        height: root.tileHeight + root.labelHeight

        Rectangle {
          id: tileBg
          width: parent.width
          height: root.tileHeight
          radius: root.cornerRadius
          color: Qt.rgba(0.1, 0.1, 0.12, 0.88)
          border.width: 1
          border.color: tileHover.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.22)
          clip: true

          Image {
            id: art
            anchors.fill: parent
            source: tile.modelData.art || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
          }

          // Fallback monogram when no local art exists
          Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: String(tile.modelData.name || "?").slice(0, 1).toUpperCase()
            color: root.themeColor
            opacity: 0.8
            font.family: root.activeFont
            font.weight: Font.DemiBold
            font.pixelSize: 40
          }

          // Source badge for non-Steam shortcuts and Battle.net games
          // (overlay pill, no layout change)
          Rectangle {
            anchors { top: parent.top; left: parent.left; margins: 6 }
            width: badgeText.width + 12
            height: badgeText.height + 6
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.65)
            visible: root.showSourceBadge && (tile.modelData.source === "shortcut" || tile.modelData.source === "battlenet")
            Text {
              id: badgeText
              anchors.centerIn: parent
              text: tile.modelData.source === "battlenet" ? "Battle.net" : "non-Steam"
              color: "white"
              font.family: root.activeFont
              font.pixelSize: 9
            }
          }
        }

        Column {
          anchors { top: tileBg.bottom; left: parent.left; right: parent.right; topMargin: 3 }
          spacing: 0
          Text {
            width: parent.width
            visible: root.showName
            text: tile.modelData.name || ""
            color: root.activeColor
            font.family: root.activeFont
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            width: parent.width
            visible: root.showMeta
            // wallClock.date param re-evaluates the label every minute
            text: root.metaLine(tile.modelData, wallClock.date)
            color: root.activeColor
            opacity: 0.65
            font.family: root.activeFont
            font.pixelSize: 11
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
          }
        }

        MouseArea {
          id: tileHover
          anchors.fill: parent
          enabled: root.interactive && root.enabled
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.launch(tile.modelData)
        }

        Component.onCompleted: targetSyncTimer.restart()
        Component.onDestruction: root.syncTargets()
        onTileReadyChanged: targetSyncTimer.restart()
      }
    }

    // Big Picture link tile — same geometry as a game tile, picked up by
    // syncTargets via isSteamTile so it joins the input mask for free.
    Item {
      id: bpTile
      property bool isSteamTile: true
      property bool tileReady: root.bpVisible

      // Collapse to zero so the Row doesn't reserve space when hidden
      // (positioners still lay out invisible children).
      width: root.bpVisible ? root.tileWidth : 0
      height: root.bpVisible ? root.tileHeight + root.labelHeight : 0
      visible: root.bpVisible

      Rectangle {
        id: bpBg
        width: parent.width
        height: root.tileHeight
        radius: root.cornerRadius
        color: Qt.rgba(0.10, 0.18, 0.33, 0.92)
        border.width: 1
        border.color: bpHover.containsMouse ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.22)
        clip: true

        Image {
          id: bpArt
          anchors.fill: parent
          source: root.bigPictureArt
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: status === Image.Ready
        }

        // Fallback monogram when the system Steam icon is missing
        Text {
          anchors.centerIn: parent
          visible: bpArt.status !== Image.Ready
          text: "BP"
          color: "white"
          opacity: 0.85
          font.family: root.activeFont
          font.weight: Font.DemiBold
          font.pixelSize: 40
        }
      }

      Column {
        anchors { top: bpBg.bottom; left: parent.left; right: parent.right; topMargin: 3 }
        spacing: 0
        Text {
          width: parent.width
          visible: root.showName
          text: root.bigPictureLabel
          color: root.activeColor
          font.family: root.activeFont
          font.pixelSize: 12
          font.weight: Font.Medium
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          width: parent.width
          visible: root.showMeta
          text: "fullscreen mode"
          color: root.activeColor
          opacity: 0.65
          font.family: root.activeFont
          font.pixelSize: 11
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
        }
      }

      MouseArea {
        id: bpHover
        anchors.fill: parent
        enabled: root.bpVisible
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.launchBigPicture()
      }

      onTileReadyChanged: targetSyncTimer.restart()
    }
  }
}
