import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "widgets" as Widgets

// Desktop widgets host rendered on the bottom layer, behind all windows
// but above the wallpaper. One PanelWindow per screen, shared surface
// containing all enabled widgets. Hot-reloads when config.json is edited.
Item {
  id: root

  FontLoader {
    id: bundledFont
    source: Qt.resolvedUrl("fonts/InterVariable.ttf")
  }
  FontLoader {
    id: appleFont
    source: Qt.resolvedUrl("fonts/PlusJakartaSans-Variable.ttf")
  }

  readonly property string newConfigPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/primo.widgets/config.json"
  readonly property string legacyConfigPath: Quickshell.env("HOME") + "/.config/omaclock/config.json"

  readonly property var defaults: ({
    namespace: "primo.widgets",
    outputs: ["DP-2"],
    widgets: {
      clock: {
        enabled: true,
        format: "h:mm",
        showSeconds: false,
        workspace: "all",
        fontFamily: "",
        fontWeight: 200,
        fontScale: 0.15,
        letterSpacing: -3,
        color: "",
        opacity: 0.92,
        position: "top",
        xRatio: null,
        yRatio: 0.20
      },
      date: {
        enabled: false,
        format: "dddd, MMMM d",
        workspace: "all",
        fontFamily: "",
        fontWeight: 300,
        fontScale: 0.06,
        letterSpacing: 0,
        color: "",
        opacity: 0.85,
        position: "top",
        xRatio: null,
        yRatio: 0.33
      },
      cava: {
        enabled: false,
        xRatio: 0.5,
        yRatio: 0.5,
        workspace: "all",
        size: 280,
        bars: 48,
        framerate: 60,
        innerRadiusRatio: 0.35,
        barSpacing: 2,
        barThickness: 0,
        color: "",
        opacity: 0.9,
        hideWhenIdle: true,
        idleTimeout: 3.0,
        sensitivity: 100,
        ringPulse: 1.0
      },
      steam: {
        enabled: false,
        workspace: "all",
        count: 5,
        tileWidth: 208,
        tileHeight: 120,
        spacing: 12,
        cornerRadius: 10,
        showName: true,
        showMeta: true,
        showBigPicture: true,
        bigPictureLabel: "Big Picture",
        fontFamily: "",
        opacity: 0.95,
        interactive: true,
        xRatio: 0.17,
        yRatio: 0.90,
        refreshInterval: 60,
        requireArt: true,
        showShortcuts: true,
        showSourceBadge: true,
        showBattlenet: true,
        battlenetPrefix: "",
        battlenetConfig: "",
        lutrisCoverDir: "",
        hideIds: ["480"],
        steamId: "",
        steamRoot: "",
        names: ({})
      }
    }
  })

  property var settings: root.defaults
  property string _lastRaw: ""

  readonly property color themeColor: Color.bar.text
  // Foundational theme palette for "system"-colored widgets (muted ->
  // foreground -> accent -> urgent). Rebuilt when the theme switches, so
  // consumers repaint with the new palette automatically.
  readonly property var themePalette: [Color.muted, Color.foreground, Color.accent, Color.urgent]

  function deepClone(obj) {
    return JSON.parse(JSON.stringify(obj))
  }

  // Per-widget workspace scoping. Layer-shell surfaces are not managed windows,
  // so Hyprland cannot scope them with a rule (there is no WORKSPACE effect for
  // layer rules, and `hyprctl layerrulev2` does not exist) — visibility has to
  // be decided here from the workspace state.
  //
  // Absent / "" / "all" / "*" means every workspace, i.e. today's behaviour.
  // Anything else is a single workspace, matched against the workspace *name*
  // so numbers ("2"), named ("web") and special ("special:cliamp") workspaces
  // all work the same way. Case-insensitive because workspace names are
  // user-authored strings.
  //
  // currentName is the active workspace on the output this panel covers. An
  // empty currentName means the state is not known yet (the workspace model is
  // lazily populated), so fail open and show the widget: a wrong "hidden"
  // makes widgets silently vanish until something forces a re-read.
  function visibleOnWorkspace(cfg, currentName) {
    if (!cfg) return true
    var want = cfg.workspace
    if (want === undefined || want === null) return true
    want = String(want).trim().toLowerCase()
    if (want === "" || want === "all" || want === "*") return true
    var current = String(currentName === undefined || currentName === null ? "" : currentName).trim().toLowerCase()
    if (current === "") return true
    return want === current
  }

  function applyRaw(raw) {
    if (!raw || String(raw).trim().length === 0) return
    if (raw === root._lastRaw) return
    root._lastRaw = raw
    try {
      var parsed = JSON.parse(raw)
      var merged = root.deepClone(root.defaults)

      if (typeof parsed.namespace === "string") merged.namespace = parsed.namespace
      if (Array.isArray(parsed.outputs)) {
        merged.outputs = parsed.outputs.slice()
      } else if (typeof parsed.outputs === "string") {
        merged.outputs = [parsed.outputs]
      } else if (typeof parsed.clockOutput === "string") {
        merged.outputs = [parsed.clockOutput]
      }

      var flatKeys = ["format", "showSeconds", "fontFamily", "fontWeight", "fontScale", "letterSpacing", "color", "opacity", "position", "xRatio", "yRatio"]
      var isFlat = false
      for (var fk = 0; fk < flatKeys.length; fk++) {
        if (parsed.hasOwnProperty(flatKeys[fk])) { isFlat = true; break }
      }
      if (isFlat && !parsed.widgets) {
        for (var i = 0; i < flatKeys.length; i++) {
          var k = flatKeys[i]
          if (parsed.hasOwnProperty(k)) merged.widgets.clock[k] = parsed[k]
        }
      }

      if (parsed.widgets && typeof parsed.widgets === "object") {
        for (var w in parsed.widgets) {
          if (!parsed.widgets.hasOwnProperty(w)) continue
          var src = parsed.widgets[w]
          if (src === null || src === undefined) continue
          if (!src || typeof src !== "object" || Array.isArray(src)) continue
          if (!merged.widgets[w]) merged.widgets[w] = {}
          for (var pk in src) {
            if (src.hasOwnProperty(pk)) merged.widgets[w][pk] = src[pk]
          }
        }
      }
      var directWidgets = ["clock", "date", "cava", "steam"]
      for (var dw = 0; dw < directWidgets.length; dw++) {
        var wName = directWidgets[dw]
        if (parsed.hasOwnProperty(wName) && parsed[wName] && typeof parsed[wName] === "object" && !parsed[wName].hasOwnProperty("widgets")) {
          if (parsed.widgets && parsed.widgets[wName]) continue
          if (!merged.widgets[wName]) merged.widgets[wName] = {}
          var dwSrc = parsed[wName]
          for (var dp in dwSrc) if (dwSrc.hasOwnProperty(dp)) merged.widgets[wName][dp] = dwSrc[dp]
        }
      }

      root.settings = merged
    } catch (e) {
      console.warn("primo.widgets: invalid config.json: " + e)
    }
  }

  Process {
    id: cfgProc
    command: ["bash", "-c", "cat \"" + root.newConfigPath + "\" 2>/dev/null || cat \"" + root.legacyConfigPath + "\" 2>/dev/null || echo \"\""]
    stdout: StdioCollector { onStreamFinished: root.applyRaw(text) }
    Component.onCompleted: running = true
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: if (!cfgProc.running) cfgProc.running = true
  }

  readonly property var outputs: (Array.isArray(root.settings.outputs) ? root.settings.outputs : ["DP-2"])
  property var widgetScreens: filteredScreens()

  function filteredScreens() {
    var out = []
    var names = root.outputs
    var showAll = names.length === 0 || (names.length === 1 && String(names[0]) === "")
    var screenNames = []
    for (var i = 0; i < Quickshell.screens.length; i++) screenNames.push(String(Quickshell.screens[i].name))
    console.log("primo.widgets screens=" + JSON.stringify(screenNames) + " outputs=" + JSON.stringify(names) + " showAll=" + showAll)
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var screen = Quickshell.screens[i]
      if (showAll) {
        out.push(screen)
      } else {
        for (var j = 0; j < names.length; j++) {
          if (String(screen.name) === String(names[j])) { out.push(screen); break }
        }
      }
    }
    console.log("primo.widgets filtered=" + out.length)
    return out
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.widgetScreens = root.filteredScreens()
    }
  }

  onOutputsChanged: root.widgetScreens = root.filteredScreens()


  Variants {
    model: root.widgetScreens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: true
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      updatesEnabled: true

      // Debounced mirror of liveWorkspaceName. Workspace switches arrive as
      // bursts (a move event plus a focus event), and every widget's visible
      // binding re-evaluates on this, so coalesce them. Same shape as cliamp's
      // scheduleApply: set the interval, then restart.
      property string activeWorkspace: ""
      readonly property string liveWorkspaceName: {
        var values = Hyprland.workspaces.values
        var mine = String(modelData.name)
        for (var i = 0; i < values.length; i++) {
          var w = values[i]
          // w.monitor is a HyprlandMonitor object, not a string — comparing
          // it directly never matches an output name, which silently left
          // every panel in the fail-open branch. Read .name off it.
          if (w && w.active && w.monitor && String(w.monitor.name) === mine) return String(w.name)
        }
        return ""
      }
      function syncWorkspace() {
        panel.activeWorkspace = panel.liveWorkspaceName
      }
      Timer {
        id: wsTimer
        interval: 120
        repeat: true
        onTriggered: panel.syncWorkspace()
      }
      // Read the workspace list, not focusedWorkspace: the per-output test
      // below needs each workspace's monitor and active flag. Reading off
      // Hyprland.monitors instead would silently answer "visible" forever,
      // because monitors populate without their activeWorkspace links
      // attached (cf. wallpaper-weather WeatherState.qml:149-152).
      Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { wsTimer.restart() }
      }
      Component.onCompleted: {
        Hyprland.refreshWorkspaces()
        wsTimer.restart()
      }
      WlrLayershell.namespace: root.settings.namespace || "primo.widgets"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Steam tile items (click-to-launch).
      property var steamTiles: []
      readonly property var interactiveCards: panel.steamTiles
      Instantiator {
        id: steamMaskParts
        model: panel.steamTiles
        delegate: Region {
          required property var modelData
          item: modelData
        }
        onObjectAdded: panel.rebuildMask()
        onObjectRemoved: panel.rebuildMask()
      }
      property var maskRegions: []
      function rebuildMask() {
        var parts = []
        for (var i = 0; i < steamMaskParts.count; i++) {
          var obj = steamMaskParts.objectAt(i)
          if (obj) parts.push(obj)
        }
        panel.maskRegions = parts
      }
      mask: Region { regions: panel.maskRegions }

      Item {
        id: surface
        anchors.fill: parent

        Widgets.Clock {
          anchors.fill: parent
          widgetSettings: (root.settings.widgets && root.settings.widgets.clock) ? root.settings.widgets.clock : root.defaults.widgets.clock
          themeColor: root.themeColor
          visible: widgetSettings.enabled !== false
            && root.visibleOnWorkspace(widgetSettings, panel.activeWorkspace)
        }

        Widgets.Date {
          anchors.fill: parent
          widgetSettings: (root.settings.widgets && root.settings.widgets.date) ? root.settings.widgets.date : root.defaults.widgets.date
          themeColor: root.themeColor
          visible: widgetSettings.enabled !== false
            && root.visibleOnWorkspace(widgetSettings, panel.activeWorkspace)
        }

        // No anchors.fill here: Cava sizes/positions itself (width=size,
        // x/y from xRatio/yRatio). Anchors would override that geometry.
        Widgets.Cava {
          widgetSettings: (root.settings.widgets && root.settings.widgets.cava) ? root.settings.widgets.cava : root.defaults.widgets.cava
          themeColor: root.themeColor
          themePalette: root.themePalette
          visible: widgetSettings.enabled === true
            && root.visibleOnWorkspace(widgetSettings, panel.activeWorkspace)
        }

        // Same: Steam sizes/positions itself from tile metrics + ratios.
        Widgets.Steam {
          id: steamWidget
          widgetSettings: (root.settings.widgets && root.settings.widgets.steam) ? root.settings.widgets.steam : root.defaults.widgets.steam
          themeColor: root.themeColor
          visible: widgetSettings.enabled === true
            && root.visibleOnWorkspace(widgetSettings, panel.activeWorkspace)
          // The input mask is built from these tiles, so a widget hidden on the
          // wrong workspace must drop them too — otherwise invisible tiles keep
          // swallowing clicks on this full-screen bottom layer.
          workspaceVisible: root.visibleOnWorkspace(widgetSettings, panel.activeWorkspace)
          onWorkspaceVisibleChanged: Qt.callLater(steamWidget.syncTargets)
          onClickTargetsChanged: panel.steamTiles = clickTargets
        }

      }
    }
  }
}
