pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
  id: root
  required property var service
  property bool keymapTab: false
  readonly property real preferredWidth: Commons.Style.space(keymapTab ? 760 : 360)
  signal closeRequested()
  focus: true
  Keys.onEscapePressed: {
    if (keymapTab && keymapEditor.pickerOpen) keymapEditor.pickerOpen = false
    else if (!keymapTab && lighting.pickerOpen) lighting.pickerOpen = false
    else closeRequested()
  }
  spacing: Commons.Style.space(10)
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  RowLayout {
    Layout.fillWidth: true
    Ui.Button { Layout.fillWidth: true; text: strings.t("lightingTab"); bordered: !root.keymapTab; focusable: true; onClicked: root.keymapTab = false }
    Ui.Button {
      Layout.fillWidth: true; text: strings.t("keymapTab"); bordered: root.keymapTab; focusable: true
      onClicked: {
        root.keymapTab = true
        if (root.service && !root.service.keymapCurrent) root.service.loadKeymap()
      }
    }
  }
  LightingEditor {
    id: lighting
    visible: !root.keymapTab
    Layout.fillWidth: true; Layout.fillHeight: true
    snapshot: root.service ? root.service.snapshot : ({})
    actionBusy: root.service ? root.service.actionBusy : false
    ready: root.service ? root.service.ready : false
    serviceError: root.service ? root.service.lastError : "NuPhy service unavailable"
    onApplyRequested: function(zone, config) { if (root.service) root.service.request("apply", zone, config) }
    onSyncRequested: if (root.service) root.service.request("sync")
    onCloseRequested: root.closeRequested()
  }
  KeymapEditor {
    id: keymapEditor
    visible: root.keymapTab
    Layout.fillWidth: true; Layout.fillHeight: true
    service: root.service
    onCloseRequested: root.closeRequested()
  }
}
