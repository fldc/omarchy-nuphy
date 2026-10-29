import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Ui.PanelSlider {
  id: root
  property var scrollView: null

  function handleWheel(event) {
    // Consume before PanelSlider's MouseArea can alter the lighting value.
    // Forward the gesture to the enclosing popup, not to the keyboard setting.
    const flick = scrollView ? scrollView.contentItem : null
    if (flick && typeof flick.contentY === "number") {
      const delta = event.pixelDelta.y || event.angleDelta.y / 120 * Commons.Style.space(48)
      const minimumY = flick.originY || 0
      const maximumY = minimumY + Math.max(0, flick.contentHeight - flick.height)
      flick.contentY = Math.max(minimumY, Math.min(maximumY, flick.contentY - delta))
    }
    event.accepted = true
  }

  MouseArea {
    anchors.fill: parent
    z: 1
    // Button events pass through to PanelSlider, but wheel events stop here.
    acceptedButtons: Qt.NoButton
    scrollGestureEnabled: true
    onWheel: function(event) { root.handleWheel(event) }
  }
}
