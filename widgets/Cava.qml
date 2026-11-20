import Quickshell
import Quickshell.Io
import QtQuick

// Cava widget - round (radial) audio visualizer for the desktop layer.
// Spawns `cava` with an inline config (stdin, never touches ~/.config/cava/config)
// capturing system audio (pipewire monitor of default sink) and renders bars
// radiating from a center ring on a single Canvas. Display-only, click-through.
// Hides itself after `idleTimeout` of silence when `hideWhenIdle` is true,
// keeping the process alive so it reappears instantly on sound.
Item {
  id: root

  property var widgetSettings: ({})
  property color themeColor: "#ffffff"
  // Foundational theme palette (muted -> foreground -> accent -> urgent),
  // passed down from Service.qml. Used when color is "system".
  property var themePalette: []

  // "system" paints each bar from the live theme palette by height.
  // "" falls back to themeColor (bar text); anything else is a CSS color.
  readonly property bool systemGradient: widgetSettings.color === "system"

  readonly property bool enabled: widgetSettings.enabled === true
  readonly property real xRatio: (typeof widgetSettings.xRatio === "number") ? widgetSettings.xRatio : 0.5
  readonly property real yRatio: (typeof widgetSettings.yRatio === "number") ? widgetSettings.yRatio : 0.5
  readonly property real widgetSize: Math.max(120, Math.round(Number(widgetSettings.size) || 280))
  readonly property int barCount: Math.min(256, Math.max(8, Math.round(Number(widgetSettings.bars) || 48)))
  readonly property int framerate: Math.min(120, Math.max(15, Math.round(Number(widgetSettings.framerate) || 60)))
  readonly property real innerRatio: Math.min(0.8, Math.max(0.1, Number(widgetSettings.innerRadiusRatio) || 0.35))
  readonly property real barSpacing: Math.max(0, Number(widgetSettings.barSpacing) || 2)
  readonly property real barThickness: Math.max(0, Math.min(256, Number(widgetSettings.barThickness) || 0))
  readonly property real sensitivity: Math.max(10, Number(widgetSettings.sensitivity) || 100)
  readonly property color activeColor: (widgetSettings.color && widgetSettings.color !== "system")
    ? Qt.color(widgetSettings.color)
    : root.themeColor
  readonly property real opacityVal: (typeof widgetSettings.opacity === "number") ? widgetSettings.opacity : 0.9
  readonly property real ringPulse: (typeof widgetSettings.ringPulse === "number") ? Math.min(1, Math.max(0, widgetSettings.ringPulse)) : 1.0
  readonly property bool hideWhenIdle: widgetSettings.hideWhenIdle !== false
  readonly property real idleTimeout: Math.max(0.5, Number(widgetSettings.idleTimeout) || 3.0)

  // Normalized 0..1 levels, one per bar
  property var levels: []
  property bool idleHidden: false
  // Smoothed overall level driving the base-ring throb (fast attack, ~180ms half-life release)
  property real pulse: 0
  // True once construction finished (guards handlers referencing later ids)
  property bool _ready: false
  // Held true briefly to bounce the cava process without breaking its binding
  property bool _restartHold: false
  property bool _exitHold: false

  width: widgetSize
  height: widgetSize
  x: parent ? Math.round(parent.width * root.xRatio - width / 2) : 0
  y: parent ? Math.round(parent.height * root.yRatio - height / 2) : 0
  // No `visible:` binding here on purpose: Service.qml owns visibility so it
  // can AND in the per-workspace gate. A binding on this root would override
  // the host's and silently defeat it.
  opacity: root.opacityVal

  function zeroLevels(n) {
    var arr = []
    for (var i = 0; i < n; i++) arr.push(0)
    return arr
  }

  // Lerp across the theme palette stops by normalized level (0..1).
  // Stop positions bias accent low so color kicks in early: muted holds
  // the floor, foreground covers quiet bars, accent owns the mids from
  // ~45% height, urgent flares only on peaks.
  // Falls back to activeColor when the palette is missing or too short.
  function gradientColor(v) {
    var pal = root.themePalette
    if (!pal || pal.length < 2) return root.activeColor
    var level = Math.min(1, Math.max(0, Number(v) || 0))
    var pos = [0.0, 0.22, 0.45, 1.0]
    while (pos.length < pal.length) pos.push(1.0)
    var i = 0
    while (i < pal.length - 2 && level > pos[i + 1]) i++
    var span = Math.max(1e-6, pos[i + 1] - pos[i])
    var f = Math.min(1, Math.max(0, (level - pos[i]) / span))
    var a = pal[i], b = pal[i + 1]
    return Qt.rgba(
      a.r + (b.r - a.r) * f,
      a.g + (b.g - a.g) * f,
      a.b + (b.b - a.b) * f,
      1
    )
  }

  // Base-ring color driven by the pulse: brightens with the music, and in
  // system-gradient mode warms from the muted stop toward the accent stop.
  function baseRingColor() {
    var amt = root.pulse * root.ringPulse
    if (root.systemGradient && root.themePalette && root.themePalette.length > 0) {
      var pal = root.themePalette
      var m = pal[0]
      var hot = pal.length > 2 ? pal[2] : pal[pal.length - 1]
      return Qt.rgba(
        m.r + (hot.r - m.r) * amt,
        m.g + (hot.g - m.g) * amt,
        m.b + (hot.b - m.b) * amt,
        0.30 + 0.45 * amt
      )
    }
    var base = root.activeColor
    return Qt.rgba(base.r, base.g, base.b, 0.22 + 0.40 * amt)
  }

  onThemePaletteChanged: if (root._ready) ring.requestPaint()

  function cavaScript() {
    var lines = [
      "cava -p /dev/stdin <<'__PRIMO_CAVA_EOF__'",
      "[general]",
      "bars = " + root.barCount,
      "framerate = " + root.framerate,
      "autosens = 1",
      "sensitivity = " + Math.round(root.sensitivity),
      "sleep_timer = 0",
      "[input]",
      "method = pipewire",
      "source = auto",
      "[output]",
      "method = raw",
      "raw_target = /dev/stdout",
      "data_format = ascii",
      "ascii_max_range = 1000",
      "bar_delimiter = 59",
      "[smoothing]",
      "noise_reduction = 77",
      "monstercat = 1",
      "waves = 0",
      "__PRIMO_CAVA_EOF__"
    ]
    return lines.join("\n")
  }

  function parseFrame(data) {
    var line = String(data).trim()
    if (line.length === 0) return
    var parts = line.split(";")
    var n = root.barCount
    var next = []
    var peak = 0
    for (var i = 0; i < n; i++) {
      var v = 0
      if (i < parts.length) {
        v = Number(parts[i]) / 1000.0
        if (isNaN(v)) v = 0
      }
      v = Math.min(1, Math.max(0, v))
      next.push(v)
      if (v > peak) peak = v
    }
    root.levels = next
    // Fast attack to the frame peak, exponential release (~180ms half-life, framerate-independent)
    var dt = 1.0 / Math.max(1, root.framerate)
    root.pulse = Math.max(peak, root.pulse * Math.pow(0.5, dt / 0.18))
    if (peak > 0.02) {
      if (root.idleHidden) root.idleHidden = false
      idleTimer.restart()
    }
    ring.requestPaint()
  }

  // Drive the cava process imperatively: Quickshell drops `running` bindings
  // when a process exits on its own, so every transition funnels through here.
  function syncRunning() {
    if (!cavaProc) return
    var want = root.enabled && !root._restartHold && !root._exitHold
    if (cavaProc.running !== want) cavaProc.running = want
  }

  function bounceStream() {
    root._restartHold = true
    root.syncRunning()
    restartDebounce.restart()
  }

  onEnabledChanged: {
    Qt.callLater(root.syncRunning)
    // Re-arm idle hiding so a fresh enable doesn't stick visible while silent
    if (root.enabled && root.hideWhenIdle) idleTimer.restart()
  }
  onHideWhenIdleChanged: {
    if (!root.hideWhenIdle) {
      idleTimer.stop()
      if (root.idleHidden) root.idleHidden = false
    } else if (root.enabled) {
      idleTimer.restart()
    }
  }
  onIdleTimeoutChanged: {
    if (root.enabled && root.hideWhenIdle) idleTimer.restart()
  }

  onBarCountChanged: {
    root.levels = root.zeroLevels(root.barCount)
    ring.requestPaint()
    root.bounceStream()
  }
  onFramerateChanged: root.bounceStream()
  onSensitivityChanged: root.bounceStream()
  onBarThicknessChanged: ring.requestPaint()
  onBarSpacingChanged: ring.requestPaint()
  onRingPulseChanged: ring.requestPaint()

  Component.onCompleted: {
    root.levels = root.zeroLevels(root.barCount)
    // Start hidden when hideWhenIdle so an idle desktop stays clean until sound
    root.idleHidden = root.hideWhenIdle
    root._ready = true
    console.log("primo.widgets Cava bars=" + root.barCount + " fps=" + root.framerate + " size=" + root.widgetSize + (root.systemGradient ? " system-gradient" : ""))
    Qt.callLater(root.syncRunning)
    if (root.enabled && root.hideWhenIdle) idleTimer.restart()
  }

  // Bounce the stream when audio-shaping settings change (debounced)
  Timer {
    id: restartDebounce
    interval: 400
    repeat: false
    onTriggered: {
      root._restartHold = false
      root.syncRunning()
    }
  }

  // Idle hiding without wall-clock calls: every audible frame re-arms this
  // single-shot timer; if it ever fires, the room has been silent long enough.
  // The cava process keeps running so the ring reappears on the next sound.
  Timer {
    id: idleTimer
    interval: Math.max(500, Math.round(root.idleTimeout * 1000))
    repeat: false
    running: root.enabled && root.hideWhenIdle
    onTriggered: root.idleHidden = true
  }

  // Restart cava if it exits while the widget is enabled (e.g. pipewire hiccup)
  Timer {
    id: exitBackoff
    interval: 2000
    repeat: false
    onTriggered: {
      root._exitHold = false
      root.syncRunning()
    }
  }

  Process {
    id: cavaProc
    command: ["bash", "-c", root.cavaScript()]
    running: false
    stdout: SplitParser {
      onRead: data => root.parseFrame(data)
    }
    stderr: SplitParser {
      onRead: data => console.warn("primo.widgets cava: " + String(data).slice(0, 200))
    }
    onExited: (code, status) => {
      if (root.enabled) {
        console.warn("primo.widgets cava exited (" + code + "), restarting")
        root._exitHold = true
        root.syncRunning()
        exitBackoff.restart()
      }
    }
  }

  Canvas {
    id: ring
    anchors.fill: parent
    visible: !root.idleHidden
    renderStrategy: Canvas.Cooperative
    onPaint: {
      var ctx = getContext("2d")
      var w = width, h = height
      ctx.reset()
      ctx.clearRect(0, 0, w, h)
      var cx = w / 2, cy = h / 2
      var outerMax = Math.min(w, h) / 2 - 4
      var innerR = outerMax * root.innerRatio
      // Headroom for the +20% ring throb so bar tips never clip
      var maxLen = Math.max(4, outerMax - innerR * 1.22)
      var n = root.barCount
      var slot = (2 * Math.PI * innerR) / Math.max(1, n)
      var autoW = Math.min(14, Math.max(1.5, slot - root.barSpacing))
      var lineW = root.barThickness > 0 ? root.barThickness : autoW
      var lvls = root.levels && root.levels.length === n ? root.levels : root.zeroLevels(n)

      // Base-ring throb amount; the ring itself is painted AFTER the bars so
      // wide overlapping bar bases can't bury it
      var throb = root.pulse * root.ringPulse
      var ringR = innerR * (1 + 0.20 * throb)
      var ringW = Math.min(12, Math.max(1, lineW * 0.28) * (1 + 0.8 * throb))

      ctx.lineCap = "round"
      var sysGrad = root.systemGradient
      var col = root.activeColor
      if (!sysGrad) ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 1)
      ctx.lineWidth = lineW
      for (var i = 0; i < n; i++) {
        var v = lvls[i]
        if (typeof v !== "number" || isNaN(v)) v = 0
        var len = Math.max(Math.min(12, lineW * 0.55), v * maxLen)
        var a = (2 * Math.PI * i) / n - Math.PI / 2
        var cosA = Math.cos(a), sinA = Math.sin(a)
        if (sysGrad) {
          var g = root.gradientColor(v)
          ctx.strokeStyle = Qt.rgba(g.r, g.g, g.b, 1)
        }
        ctx.beginPath()
        ctx.moveTo(cx + cosA * ringR, cy + sinA * ringR)
        ctx.lineTo(cx + cosA * (ringR + len), cy + sinA * (ringR + len))
        ctx.stroke()
      }

      // Base ring on top: radius breathes outward, color brightens (and warms
      // toward accent in system mode) via baseRingColor()
      ctx.beginPath()
      ctx.arc(cx, cy, ringR, 0, 2 * Math.PI)
      ctx.strokeStyle = root.baseRingColor()
      ctx.lineWidth = ringW
      ctx.stroke()
    }
  }
}
