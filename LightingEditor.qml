import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Controls.ScrollView {
  id: root
  property var snapshot: ({})
  property bool actionBusy: false
  property bool ready: false
  property string serviceError: ""
  property string zone: "main"
  property string effect: "static"
  property bool syncing: false
  property string direction: "right"
  property string localError: ""
  property bool initialized: false
  property bool complete: false
  property var drafts: ({})
  readonly property bool validColor: /^#[0-9a-fA-F]{6}$/.test(hexInput.text)
  readonly property var mainEffects: ["ray", "stair", "static", "breath", "flower", "wave", "ripple", "spout", "galaxy", "rotation", "ripple2", "point", "grid", "time", "rain", "ribbon", "gaming", "identify", "windmill", "diagonal"]
  readonly property var sideEffects: ["time", "neon", "static", "breathe", "rhythm"]
  signal applyRequested(string zone, var config)
  signal syncRequested()
  signal closeRequested()
  implicitHeight: body.implicitHeight
  contentWidth: availableWidth
  clip: true
  focus: true
  Keys.onEscapePressed: closeRequested()
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  QtObject {
    id: popupPalette
    readonly property color foreground: Commons.Color.popups.text
    readonly property color background: Commons.Color.popups.background
  }

  function config() {
    var savedHex = snapshot.zones ? snapshot.zones[zone].hex : "#ffffff"
    return {effect: effect, hex: syncing && !validColor ? savedHex : hexInput.text, brightness: Math.round(brightness.value),
      speed: Math.round(speed.value), direction: direction, sync: syncing, offset: offset.value}
  }
  function loadZone() {
    var value = drafts[zone] || (snapshot.zones ? snapshot.zones[zone] : null)
    if (!value) return
    effect = value.effect
    syncing = value.sync
    direction = value.direction
    hexInput.text = value.hex
    brightness.value = value.brightness
    speed.value = value.speed
    offset.value = value.offset
    localError = ""
    initialized = true
  }
  function selectZone(value) {
    if (initialized) drafts[zone] = config()
    zone = value
    loadZone()
  }
  function apply() {
    if (!syncing && !validColor) { localError = strings.t("invalid"); return }
    localError = ""
    drafts[zone] = config()
    applyRequested(zone, config())
  }
  Component.onCompleted: { complete = true; loadZone() }
  onSnapshotChanged: if (complete && !initialized) loadZone()

  Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
  Controls.ScrollBar.vertical: Controls.ScrollBar {
    id: verticalScroll
    objectName: "verticalScroll"
    parent: root
    x: root.mirrored ? 0 : root.width - width
    y: root.topPadding
    height: root.availableHeight
    visible: size < 1
    policy: Controls.ScrollBar.AsNeeded
    contentItem: Rectangle {
      implicitWidth: Style.space(5)
      implicitHeight: Style.space(24)
      radius: Style.cornerRadius
      color: verticalScroll.pressed ? Commons.Color.accent : Commons.Color.muted
    }
    background: Rectangle { color: "transparent" }
  }

  ColumnLayout {
    id: body
    width: root.availableWidth
    spacing: Style.space(10)
    PlainText {
      Layout.fillWidth: true
      text: root.snapshot.keyboardName || strings.t("title")
      font.bold: true
      font.pixelSize: Style.font.heading
    }
    PlainText { Layout.fillWidth: true; text: strings.t("theme").arg(root.snapshot.theme || strings.t("missing")) }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Style.space(5)
      color: root.snapshot.theme || Commons.Color.popups.text
      radius: height / 2
    }
    Ui.Dropdown {
      Layout.fillWidth: true
      value: root.zone
      options: ["main", "side", "decorative"].map(function(z) { return {value: z, label: strings.t(z)} })
      onChanged: function(value) { root.selectZone(value) }
    }
    Ui.Toggle {
      Layout.fillWidth: true
      label: strings.t("sync")
      checked: root.syncing
      foreground: Commons.Color.popups.text
      onClicked: root.syncing = !root.syncing
    }
    Ui.Dropdown {
      Layout.fillWidth: true
      label: strings.t("effect")
      value: root.effect
      options: root.zone === "main" ? root.mainEffects : root.sideEffects
      onChanged: function(value) { root.effect = value }
    }
    PlainText { text: strings.t("color") }
    RowLayout {
      Layout.fillWidth: true
      Rectangle {
        implicitWidth: Style.space(28); implicitHeight: Style.space(28)
        radius: Style.space(4)
        color: root.syncing ? (root.snapshot.theme || "transparent") : (root.validColor ? hexInput.text : "transparent")
        border.color: Commons.Color.popups.border
      }
      Ui.TextField {
        id: hexInput
        objectName: "hexInput"
        Layout.fillWidth: true
        text: "#ffffff"
        maximumLength: 7
        enabled: !root.syncing
        foreground: Commons.Color.popups.text
        selectByMouse: true
        placeholderText: "#RRGGBB"
      }
    }
    PlainText { text: strings.t("brightness").arg(I18n.formatNumber(Math.round(brightness.value))) }
    Ui.PanelSlider {
      id: brightness
      objectName: "brightness"
      Layout.fillWidth: true
      bar: popupPalette
      minimum: 0; maximum: 100; step: 1; integer: true; value: 70
      fillColor: Commons.Color.accent
      knobColor: activeFocus ? Commons.Color.accent : Commons.Color.popups.text
      activeFocusOnTab: true
      Keys.onLeftPressed: value = Math.max(minimum, Math.min(maximum, value + (I18n.rightToLeft ? step : -step)))
      Keys.onRightPressed: value = Math.max(minimum, Math.min(maximum, value + (I18n.rightToLeft ? -step : step)))
      onMoved: function(value) { brightness.value = value }
    }
    PlainText { text: strings.t("speed").arg(I18n.formatNumber(Math.round(speed.value))) }
    Ui.PanelSlider {
      id: speed
      objectName: "speed"
      Layout.fillWidth: true
      bar: popupPalette
      minimum: 0; maximum: 4; step: 1; integer: true; value: 2
      tickCount: 5
      fillColor: Commons.Color.accent
      knobColor: activeFocus ? Commons.Color.accent : Commons.Color.popups.text
      activeFocusOnTab: true
      Keys.onLeftPressed: value = Math.max(minimum, Math.min(maximum, value + (I18n.rightToLeft ? step : -step)))
      Keys.onRightPressed: value = Math.max(minimum, Math.min(maximum, value + (I18n.rightToLeft ? -step : step)))
      onMoved: function(value) { speed.value = value }
    }
    Ui.Dropdown {
      visible: root.zone === "main"
      Layout.fillWidth: true
      label: strings.t("direction")
      value: root.direction
      options: ["left", "right"].map(function(d) { return {value: d, label: strings.t(d)} })
      onChanged: function(value) { root.direction = value }
    }
    PlainText { visible: root.zone === "decorative"; Layout.fillWidth: true; text: strings.t("warning"); color: Commons.Color.accent }
    RowLayout {
      visible: root.zone === "decorative"
      PlainText { Layout.fillWidth: true; text: strings.t("offset") }
      Ui.NumberField {
        id: offset
        from: 0; to: 53; value: 17
        foreground: Commons.Color.popups.text
        onModified: function(value) { offset.value = value }
      }
    }
    Ui.Button {
      objectName: "applyButton"
      Layout.fillWidth: true
      text: strings.t(root.actionBusy ? "busy" : "apply")
      enabled: root.ready && !root.actionBusy && (root.syncing || root.validColor)
      foreground: Commons.Color.popups.text
      focusable: true
      bordered: true
      onClicked: root.apply()
    }
    Ui.Button {
      Layout.fillWidth: true
      text: strings.t("syncNow")
      enabled: root.ready && !root.actionBusy
      foreground: Commons.Color.popups.text
      focusable: true
      onClicked: root.syncRequested()
    }
    PlainText {
      Layout.fillWidth: true
      text: root.localError || root.serviceError || root.snapshot.error || root.snapshot.discoveryError || root.snapshot.message || strings.t("ready")
      color: root.localError || root.serviceError || root.snapshot.error || root.snapshot.discoveryError ? Commons.Color.urgent : Commons.Color.popups.text
    }
    PlainText { Layout.fillWidth: true; text: strings.t("help"); font.pixelSize: Style.font.caption; opacity: 0.7 }
  }
}
