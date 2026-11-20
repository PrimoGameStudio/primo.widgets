import Quickshell
import QtQuick

// Clock widget - large desktop time display
// Lives inside Service.qml's shared bottom-layer surface (anchors.fill: parent)
Item {
  id: root

  property var widgetSettings: ({})
  property color themeColor: "#ffffff"

  readonly property string activeFont: widgetSettings.fontFamily === "system"
    ? ""
    : (widgetSettings.fontFamily ? widgetSettings.fontFamily : "Inter Variable")

  readonly property color activeColor: widgetSettings.color
    ? Qt.color(widgetSettings.color)
    : root.themeColor

  readonly property real xRatio: (typeof widgetSettings.xRatio === "number")
    ? widgetSettings.xRatio : 0.5

  readonly property real yRatio: (typeof widgetSettings.yRatio === "number")
    ? widgetSettings.yRatio
    : (widgetSettings.position === "top" ? 0.14
      : widgetSettings.position === "bottom" ? 0.86 : 0.5)

  readonly property real fontWeight: (typeof widgetSettings.fontWeight === "number") ? widgetSettings.fontWeight : 200
  readonly property real fontScale: (typeof widgetSettings.fontScale === "number") ? widgetSettings.fontScale : 0.15
  readonly property real letterSpacing: (typeof widgetSettings.letterSpacing === "number") ? widgetSettings.letterSpacing : -3
  readonly property real opacityVal: (typeof widgetSettings.opacity === "number") ? widgetSettings.opacity : 0.92
  readonly property string format: widgetSettings.format ? String(widgetSettings.format) : "h:mm"
  readonly property bool showSeconds: widgetSettings.showSeconds === true

  function clockString(date, fmt) {
    if (/h/i.test(fmt) && !/AP/i.test(fmt)) {
      var s = Qt.formatDateTime(date, fmt + " AP").replace(/\s*(AM|PM)$/i, "").trim()
      return s.replace(/^(\d)(?=:)/, "0$1")
    }
    return Qt.formatDateTime(date, fmt)
  }

  Text {
    id: clockText
    color: root.activeColor
    opacity: root.opacityVal
    font.family: root.activeFont
    font.weight: root.fontWeight
    font.pixelSize: Math.max(8, Math.round(root.height * root.fontScale))
    font.letterSpacing: root.letterSpacing
    renderType: Text.CurveRendering
    text: root.clockString(clock.date, root.format)

    x: root.width * root.xRatio - width / 2
    y: root.height * root.yRatio - height / 2
  }

  SystemClock {
    id: clock
    precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    onDateChanged: clockText.text = root.clockString(date, root.format)
  }
}
