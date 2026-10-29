import QtQuick
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
  id: root
  property real hue: 0
  property real saturation: 0
  property real value: 1
  property var scrollView: null
  readonly property color selectedColor: Qt.hsva(hue, saturation, value, 1)
  readonly property bool mirrored: LayoutMirroring.enabled
  signal chosen(string hex)
  signal closed()
  spacing: Commons.Style.space(10)
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  QtObject {
    id: popupPalette
    readonly property color foreground: Commons.Color.popups.text
    readonly property color background: Commons.Color.popups.background
  }

  function clamp(number) { return Math.max(0, Math.min(1, number)) }
  function setColor(hex) {
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return
    const parsedColor = Qt.color(hex)
    if (parsedColor.hsvHue >= 0) hue = parsedColor.hsvHue
    saturation = parsedColor.hsvSaturation
    value = parsedColor.hsvValue
  }
  function select(s, v) {
    saturation = clamp(s)
    value = clamp(v)
    chosen(selectedColor.toString())
  }
  function selectHue(next) {
    hue = clamp(next)
    chosen(selectedColor.toString())
  }

  PlainText { text: strings.t("picker"); font.bold: true }
  Rectangle {
    id: field
    objectName: "saturationValueField"
    Layout.fillWidth: true
    implicitHeight: Commons.Style.space(140)
    color: Qt.hsva(root.hue, 1, 1, 1)
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: strings.t("saturationValue")
    Keys.onLeftPressed: root.select(root.saturation + (root.mirrored ? 0.01 : -0.01), root.value)
    Keys.onRightPressed: root.select(root.saturation + (root.mirrored ? -0.01 : 0.01), root.value)
    Keys.onUpPressed: root.select(root.saturation, root.value + 0.01)
    Keys.onDownPressed: root.select(root.saturation, root.value - 0.01)
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: root.mirrored ? "transparent" : "white" }
        GradientStop { position: 1; color: root.mirrored ? "white" : "transparent" }
      }
    }
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: "transparent" }
        GradientStop { position: 1; color: "black" }
      }
    }
    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: Math.max(1, Commons.Style.space(1))
      border.color: field.activeFocus ? Commons.Color.accent : Commons.Color.popups.border
    }
    Rectangle {
      width: Commons.Style.space(12)
      height: width
      radius: width / 2
      x: Math.max(0, Math.min(field.width - width, (root.mirrored ? 1 - root.saturation : root.saturation) * field.width - width / 2))
      y: Math.max(0, Math.min(field.height - height, (1 - root.value) * field.height - height / 2))
      color: root.selectedColor
      border.width: Math.max(1, Commons.Style.space(2))
      border.color: root.value > 0.6 ? "black" : "white"
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      function choose(mouse) {
        var fraction = mouse.x / Math.max(1, width)
        root.select(root.mirrored ? 1 - fraction : fraction, 1 - mouse.y / Math.max(1, height))
      }
      onPressed: function(mouse) { field.forceActiveFocus(); choose(mouse) }
      onPositionChanged: function(mouse) { if (pressed) choose(mouse) }
    }
  }
  PlainText { text: strings.t("hue") }
  Item {
    Layout.fillWidth: true
    implicitHeight: hueSlider.implicitHeight
    Rectangle {
      x: hueSlider.knobSize / 2
      width: parent.width - hueSlider.knobSize
      height: hueSlider.trackHeight
      anchors.verticalCenter: parent.verticalCenter
      radius: height / 2
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#ff0000" }
        GradientStop { position: 1 / 6; color: root.mirrored ? "#ff00ff" : "#ffff00" }
        GradientStop { position: 2 / 6; color: root.mirrored ? "#0000ff" : "#00ff00" }
        GradientStop { position: 3 / 6; color: "#00ffff" }
        GradientStop { position: 4 / 6; color: root.mirrored ? "#00ff00" : "#0000ff" }
        GradientStop { position: 5 / 6; color: root.mirrored ? "#ffff00" : "#ff00ff" }
        GradientStop { position: 1; color: "#ff0000" }
      }
    }
    LightingSlider {
      id: hueSlider
      objectName: "hueSlider"
      anchors.fill: parent
      bar: popupPalette
      scrollView: root.scrollView
      minimum: 0; maximum: 1; step: 1 / 360
      value: root.hue
      fillColor: "transparent"
      trackColor: "transparent"
      knobColor: activeFocus ? Commons.Color.accent : Commons.Color.popups.text
      activeFocusOnTab: true
      Accessible.role: Accessible.Slider
      Accessible.name: strings.t("hue")
      Keys.onLeftPressed: root.selectHue(root.hue + (root.mirrored ? step : -step))
      Keys.onRightPressed: root.selectHue(root.hue + (root.mirrored ? -step : step))
      onMoved: function(value) { root.selectHue(value) }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    PlainText { Layout.fillWidth: true; text: root.selectedColor.toString() }
    Ui.Button {
      text: strings.t("done")
      foreground: Commons.Color.popups.text
      focusable: true
      bordered: true
      onClicked: root.closed()
    }
  }
}
