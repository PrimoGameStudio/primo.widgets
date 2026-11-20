import QtQuick

// Deprecated shim — Service.qml is now the entry point.
// Kept for backwards compatibility if the shell still references the old path.
Item {
  id: root
  Component.onCompleted: console.warn("primo.widgets: DesktopClock.qml is deprecated, use Service.qml (manifest updated to 0.2.0)")
  Loader {
    anchors.fill: parent
    source: Qt.resolvedUrl("Service.qml")
  }
}
