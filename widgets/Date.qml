import Quickshell
import QtQuick

// Date widget - secondary desktop widget showing full date.
// Stub proving the multi-widget host works; mirrors Clock's theming/positioning.
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
    : (widgetSettings.position === "top" ? 0.33
      : widgetSettings.position === "bottom" ? 0.86 : 0.5)

  readonly property real fontWeight: (typeof widgetSettings.fontWeight === "number") ? widgetSettings.fontWeight : 300
  readonly property real fontScale: (typeof widgetSettings.fontScale === "number") ? widgetSettings.fontScale : 0.06
  readonly property real letterSpacing: (typeof widgetSettings.letterSpacing === "number") ? widgetSettings.letterSpacing : 0
  readonly property real opacityVal: (typeof widgetSettings.opacity === "number") ? widgetSettings.opacity : 0.85
  readonly property string format: widgetSettings.format ? String(widgetSettings.format) : "dddd, MMMM d"

  Text {
    id: dateText
    color: root.activeColor
    opacity: root.opacityVal
    font.family: root.activeFont
    font.weight: root.fontWeight
    font.pixelSize: Math.max(8, Math.round(root.height * root.fontScale))
    font.letterSpacing: root.letterSpacing
    renderType: Text.CurveRendering
    text: Qt.formatDateTime(dateClock.date, root.format)

    x: root.width * root.xRatio - width / 2
    y: root.height * root.yRatio - height / 2
  }

  SystemClock {
    id: dateClock
    precision: SystemClock.Minutes
    onDateChanged: dateText.text = Qt.formatDateTime(date, root.format)
  }
}
