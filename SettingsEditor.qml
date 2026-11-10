pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
  id: root
  required property var service
  readonly property var state: (service ? service.settings : null) || ({})
  readonly property bool editable: service && service.settingsCurrent && !service.actionBusy
  readonly property bool busy: service && service.actionBusy
  readonly property bool accessoryKnown: !!state.values && (state.values.accessory === "knob" || state.values.accessory === "button")
  signal closeRequested()
  implicitHeight: Commons.Style.space(560)
  spacing: Commons.Style.space(10)
  focus: true
  Keys.onEscapePressed: closeRequested()
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function value(key) {
    if (service && key in (service.settingsDraft || {})) return service.settingsDraft[key]
    return state.values ? state.values[key] : undefined
  }
  function stage(key, value) { if (editable) service.stageSetting(key, value) }
  RowLayout {
    Layout.fillWidth: true
    PlainText { Layout.fillWidth: true; text: strings.t("settingsTab"); font.bold: true }
    Ui.Button {
      objectName: "settingsRefresh"
      text: strings.t("keymapRefresh"); focusable: true
      tooltipText: strings.t("settingsRefreshHelp")
      enabled: root.service && root.service.ready && !root.busy
      onClicked: root.service.loadSettings(root.accessoryKnown, true)
    }
  }
  PlainText {
    Layout.fillWidth: true
    visible: root.busy || !root.editable || !!root.state.error
    text: root.busy ? strings.t("settingsWorking") : (root.state.error || (root.service && root.service.lastError) || strings.t("settingsUnavailable"))
    color: Commons.Color.urgent
  }
  PlainText {
    Layout.fillWidth: true; visible: !!root.state.message && !root.state.error && !(root.service && root.service.settingsDirty)
    text: strings.t(root.state.message === "applied" ? "settingsApplied" : "settingsUnchanged")
  }
  Controls.ScrollView {
    Layout.fillWidth: true; Layout.fillHeight: true
    contentWidth: availableWidth; clip: true
    ColumnLayout {
      width: parent.width
      spacing: Commons.Style.space(10)
      Ui.Toggle {
        objectName: "autoSleep"
        Layout.fillWidth: true; label: strings.t("autoSleep")
        description: strings.t("autoSleepHelp")
        foreground: Commons.Color.popups.text
        checked: root.value("auto_sleep") === true
        enabled: root.editable
        onClicked: root.stage("auto_sleep", !checked)
      }
      PlainText { Layout.fillWidth: true; text: strings.t("sleepOrder") }
      Repeater {
        model: ["level1_minutes", "level2_minutes"]
        delegate: ColumnLayout {
          id: timerRow
          required property string modelData
          Layout.fillWidth: true
          PlainText { Layout.fillWidth: true; text: strings.t(timerRow.modelData === "level1_minutes" ? "level1Sleep" : "level2Sleep") }
          RowLayout {
            Layout.fillWidth: true
            Ui.Button {
              objectName: timerRow.modelData + "-minus"
              text: "−"; focusable: true; foreground: Commons.Color.popups.text
              enabled: root.editable && root.value("auto_sleep") === true && root.value(timerRow.modelData) > 5
              onClicked: root.stage(timerRow.modelData, root.value(timerRow.modelData) - 1)
            }
            PlainText {
              objectName: timerRow.modelData
              Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
              text: root.state.values ? strings.t("settingsMinutes").arg(Commons.I18n.formatNumber(root.value(timerRow.modelData))) : "—"
            }
            Ui.Button {
              objectName: timerRow.modelData + "-plus"
              text: "+"; focusable: true; foreground: Commons.Color.popups.text
              enabled: root.editable && root.value("auto_sleep") === true && root.value(timerRow.modelData) < 127
              onClicked: root.stage(timerRow.modelData, root.value(timerRow.modelData) + 1)
            }
          }
        }
      }
      PlainText { Layout.fillWidth: true; text: strings.t("accessoryHelp") }
      Ui.Button {
        objectName: "readAccessory"
        Layout.fillWidth: true; text: strings.t("readAccessory"); focusable: true
        visible: !root.accessoryKnown
        enabled: root.editable
        foreground: Commons.Color.popups.text
        onClicked: root.service.loadSettings(true, false)
      }
      PlainText { Layout.fillWidth: true; visible: !!root.state.accessoryError; text: root.state.accessoryError || ""; color: Commons.Color.urgent }
      Ui.Dropdown {
        objectName: "accessorySwitch"
        Layout.fillWidth: true; label: strings.t("accessorySwitch")
        visible: root.accessoryKnown; enabled: root.editable
        value: root.value("accessory") || ""
        options: [{value: "knob", label: strings.t("accessoryKnob")}, {value: "button", label: strings.t("accessoryButton")}]
        onChanged: function(value) { root.stage("accessory", value) }
      }
      PlainText { Layout.fillWidth: true; text: strings.t("settingsHelp") }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    Ui.Button {
      objectName: "settingsApply"
      Layout.fillWidth: true; text: strings.t("settingsApply"); bordered: true; focusable: true
      enabled: root.editable && root.service.settingsDirty
      onClicked: root.service.applySettings()
    }
    Ui.Button {
      objectName: "settingsDiscard"
      Layout.fillWidth: true; text: strings.t("keymapDiscard"); focusable: true
      enabled: !!root.service && !!root.service.settingsDirty && !root.busy
      onClicked: root.service.discardSettings()
    }
  }
}
