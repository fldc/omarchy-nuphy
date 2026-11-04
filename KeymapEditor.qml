pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
  id: root
  required property var service
  property int selectedLayer: 0
  property int selected: -1
  property bool pickerOpen: false
  property string loadedIdentity: ""
  readonly property var state: service ? service.keymap : ({})
  readonly property var info: state.info || ({})
  readonly property var keys: state.keys || ({})
  readonly property var drafts: service ? service.drafts : ({})
  readonly property var entry: keys[selectedLayer + ":" + selected] || null
  readonly property var factory: state.factory ? state.factory[selectedLayer + ":" + selected] : null
  readonly property var draft: drafts[selectedLayer + ":" + selected] || null
  readonly property bool editable: service && service.keymapCurrent && !service.actionBusy && !service.detachedDraft
  readonly property bool air75: /air75\s*v3/i.test(String(info.product || "")) && info.matrix && info.matrix.rows === 6 && info.matrix.cols === 16 && info.extra_entries === 2
  readonly property bool hasMatrix: !!info.matrix && info.matrix.rows > 0 && info.matrix.cols > 0
  property string layoutLinkError: ""
  signal closeRequested()
  function layoutIssueUrl() {
    // Share model/geometry only; never include mappings, serials or local paths.
    var product = String(info.product || "Unknown NuPhy keyboard").replace(/[\r\n]/g, " ").slice(0, 128)
    var body = "### Keyboard layout request\n\n" +
      "Model: " + product + "\n" +
      "Firmware: " + String(info.firmware_version || "Unknown").slice(0, 80) + "\n" +
      "Matrix: " + (hasMatrix ? info.matrix.rows + " rows × " + info.matrix.cols + " columns" : "Unknown") + "\n" +
      "Extra entries: " + (info.extra_entries || 0) + "\n" +
      "Layers: " + (info.layer_count || "Unknown") + "\n\n" +
      "### Physical layout\nPlease attach a clear top-down keyboard photo or a screenshot from NuPhyIO.\n" +
      "State ANSI/ISO/JIS, keyboard size, and any knob or other extra controls.\n\n" +
      "### What needs changing?\nDescribe missing or misplaced keys and label differences.\n"
    return "https://github.com/fldc/omarchy-nuphy/issues/new?template=keyboard-layout.md&title=" + encodeURIComponent("Layout support: " + product) + "&body=" + encodeURIComponent(body)
  }
  focus: true
  implicitHeight: Commons.Style.space(660)
  spacing: Commons.Style.space(8)
  Keys.onEscapePressed: { if (pickerOpen) pickerOpen = false; else closeRequested() }
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function label(value) { return value ? (value.name || ("0x" + value.value.toString(16))) : "—" }
  function codeLabel(value) {
    var code = (state.codes || []).find(function(c) { return c.value === value })
    return code ? code.name : "0x" + value.toString(16)
  }
  function knobLabel(index) {
    var address = selectedLayer + ":" + index
    return drafts[address] ? codeLabel(drafts[address].value) : label(keys[address])
  }
  function stage(value) { if (entry && editable) service.stage(selectedLayer, selected, value); pickerOpen = false }
  function initialize() {
    if (state.identity && loadedIdentity !== state.identity) {
      loadedIdentity = state.identity
      selectedLayer = info.current_mode ? info.current_mode.mode * info.layers_per_mode : 0
      selected = -1
    }
  }
  onStateChanged: Qt.callLater(initialize)
  Component.onCompleted: initialize()
  RowLayout {
    Layout.fillWidth: true
    PlainText { Layout.fillWidth: true; text: root.info.product || strings.t("title"); font.bold: true }
    Ui.Button { text: strings.t("keymapRefresh"); enabled: root.service && root.service.ready && !root.service.actionBusy; focusable: true; onClicked: root.service.loadKeymap() }
  }
  PlainText {
    Layout.fillWidth: true
    visible: !root.editable || !!root.state.error
    text: root.service && root.service.actionBusy ? strings.t("keymapWorking") : (root.state.error || strings.t("keymapRefreshNeeded"))
    color: Commons.Color.urgent
  }
  PlainText { Layout.fillWidth: true; visible: !!root.state.message && !root.state.error; text: strings.t(root.state.message === "applied" ? "keymapApplied" : "keymapUnchanged") }
  PlainText { Layout.fillWidth: true; visible: root.service && root.service.detachedDraft; text: strings.t("keymapDetached") }
  Ui.Button {
    text: strings.t("keymapBind"); visible: root.service && root.service.detachedDraft
    enabled: root.service && root.service.keymapCurrent && root.service.compatibleDraft && !root.service.actionBusy
    focusable: true; onClicked: root.service.bindDraft()
  }
  RowLayout {
    Layout.fillWidth: true
    Ui.Dropdown {
      Layout.fillWidth: true; label: strings.t("keymapMode")
      value: String(Math.floor(root.selectedLayer / (root.info.layers_per_mode || 1)))
      options: (root.info.modes || []).map(function(m) { return {value: String(m.mode), label: m.name} })
      onChanged: function(value) { root.selectedLayer = Number(value) * root.info.layers_per_mode; root.pickerOpen = false }
    }
    Ui.Dropdown {
      Layout.fillWidth: true; label: strings.t("keymapLayer")
      value: String(root.selectedLayer)
      options: Array.from({length: root.info.layers_per_mode || 0}, function(_, i) {
        var mode = Math.floor(root.selectedLayer / root.info.layers_per_mode)
        var layer = mode * root.info.layers_per_mode + i
        return {value: String(layer), label: "FN" + layer}
      })
      onChanged: function(value) { root.selectedLayer = Number(value); root.pickerOpen = false }
    }
  }
  Controls.ScrollView {
    Layout.fillWidth: true; Layout.fillHeight: true
    contentWidth: availableWidth; clip: true
    ColumnLayout {
      width: parent.width
      spacing: Commons.Style.space(8)
      KeyboardLayout {
        Layout.fillWidth: true
        visible: root.air75 && root.width >= Commons.Style.space(620)
        codes: root.state.codes || []; keys: root.keys; factory: root.state.factory || ({}); drafts: root.drafts; selectedLayer: root.selectedLayer; selected: root.selected
        enabled: root.editable
        onSelectedKey: function(index) { root.selected = index; root.pickerOpen = false }
      }
      PlainText {
        Layout.fillWidth: true; visible: !root.air75 && root.hasMatrix
        text: strings.t("keymapMatrixHelp")
      }
      Controls.ScrollView {
        id: matrixScroll
        objectName: "matrixView"
        implicitWidth: 0
        Layout.minimumWidth: 0
        Layout.fillWidth: true
        Layout.preferredHeight: matrixDiagram.implicitHeight + Commons.Style.space(16)
        visible: !root.air75 && root.hasMatrix
        clip: true
        contentWidth: matrixDiagram.width
        contentHeight: matrixDiagram.implicitHeight
        Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AlwaysOff
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AsNeeded
        KeyboardLayout {
          id: matrixDiagram
          objectName: "matrixDiagram"
          width: Math.max(matrixCols * Commons.Style.space(42), Math.min(root.width, matrixCols * Commons.Style.space(60)))
          height: implicitHeight
          matrixMode: true
          matrixRows: !root.air75 && root.info.matrix ? root.info.matrix.rows : 0
          matrixCols: !root.air75 && root.info.matrix ? root.info.matrix.cols : 0
          codes: root.state.codes || []; keys: root.keys; factory: root.state.factory || ({}); drafts: root.drafts
          selectedLayer: root.selectedLayer; selected: root.selected
          enabled: root.editable
          onSelectedKey: function(index) { root.selected = index; root.pickerOpen = false }
        }
      }
      PlainText { Layout.fillWidth: true; visible: !root.air75 && root.hasMatrix && root.info.extra_entries > 0; text: strings.t("keymapExtraEntries") }
      Flow {
        Layout.fillWidth: true
        spacing: Commons.Style.space(6)
        visible: !root.air75 && root.hasMatrix
        Repeater {
          model: !root.air75 && root.hasMatrix ? (root.info.extra_entries || 0) : 0
          delegate: Ui.Button {
            required property int index
            readonly property int entryIndex: root.info.matrix.rows * root.info.matrix.cols + index
            objectName: "extraEntry-" + entryIndex
            text: "#" + entryIndex + " · " + root.knobLabel(entryIndex)
            tooltipText: (root.keys[root.selectedLayer + ":" + entryIndex] || {}).position || "#" + entryIndex
            enabled: root.editable
            selected: root.selected === entryIndex
            bordered: true; focusable: true
            foreground: Commons.Color.popups.text
            onClicked: { root.selected = entryIndex; root.pickerOpen = false }
          }
        }
      }
      Ui.Button {
        objectName: "requestLayout"
        Layout.fillWidth: true
        text: strings.t("keymapRequestLayout")
        tooltipText: strings.t("keymapRequestLayoutHelp")
        visible: root.hasMatrix && !root.air75
        focusable: true
        foreground: Commons.Color.popups.text
        onClicked: root.layoutLinkError = Qt.openUrlExternally(root.layoutIssueUrl()) ? "" : strings.t("keymapLayoutLinkError")
      }
      PlainText { Layout.fillWidth: true; visible: root.hasMatrix && !root.air75 && !!root.layoutLinkError; text: root.layoutLinkError; color: Commons.Color.urgent }
      GridLayout {
        Layout.fillWidth: true
        columns: root.width < Commons.Style.space(620) ? 1 : 2
        visible: root.air75
        Ui.Button { text: strings.t("keymapKnobCcw") + " · " + root.knobLabel(96); enabled: root.editable; focusable: true; onClicked: { root.selected = 96; root.pickerOpen = false } }
        Ui.Button { text: strings.t("keymapKnobCw") + " · " + root.knobLabel(97); enabled: root.editable; focusable: true; onClicked: { root.selected = 97; root.pickerOpen = false } }
      }
      Ui.Dropdown {
        objectName: "keyPosition"
        Layout.fillWidth: true; label: strings.t("keymapPosition")
        enabled: root.editable
        value: root.selected < 0 ? strings.t("keymapSelect") : String(root.selected)
        options: Object.keys(root.keys).filter(function(k) { return root.keys[k].layer === root.selectedLayer }).map(function(k) {
          var entry = root.keys[k]
          return {value: String(entry.index), label: entry.position + " · " + root.label(entry) + (root.drafts[k] ? " •" : "")}
        })
        onChanged: function(value) { root.selected = Number(value); root.pickerOpen = false }
      }
      PlainText {
        Layout.fillWidth: true; visible: !!root.entry
        text: strings.t("keymapAssignments").arg(root.label(root.entry)).arg(root.label(root.factory)).arg(root.draft ? root.codeLabel(root.draft.value) : "—")
      }
      GridLayout {
        Layout.fillWidth: true
        columns: root.width < Commons.Style.space(620) ? 1 : 3
        Ui.Button { objectName: "keymapChoose"; Layout.fillWidth: true; text: strings.t("keymapChoose"); enabled: root.editable && !!root.entry; focusable: true; onClicked: root.pickerOpen = !root.pickerOpen }
        Ui.Button { Layout.fillWidth: true; text: strings.t("keymapFactory"); enabled: root.editable && !!root.factory; focusable: true; onClicked: root.stage(root.factory.value) }
        Ui.Button { Layout.fillWidth: true; text: strings.t("keymapRevert"); enabled: root.editable && !!root.draft; focusable: true; onClicked: root.stage(root.entry.value) }
      }
      Loader {
        Layout.fillWidth: true; active: root.pickerOpen; visible: active
        sourceComponent: Component {
          KeycodePicker {
            codes: root.state.codes || []; layerCount: root.info.layer_count || 0
            onChosen: function(value) { root.stage(value) }
            onClosed: root.pickerOpen = false
          }
        }
      }
      PlainText { Layout.fillWidth: true; text: strings.t("keymapHelp") }
      Repeater {
        model: root.service ? root.service.changes : []
        delegate: ColumnLayout {
          id: change
          required property var modelData
          readonly property string address: modelData.layer + ":" + modelData.index
          readonly property var conflict: root.service.conflicts ? root.service.conflicts[address] : null
          Layout.fillWidth: true
          PlainText {
            Layout.fillWidth: true
            text: strings.t("keymapChange").arg(change.modelData.layer).arg((root.keys[change.address] || {}).position || "#" + change.modelData.index).arg(root.codeLabel(change.modelData.original)).arg(root.codeLabel(change.modelData.value))
          }
          PlainText {
            Layout.fillWidth: true; visible: !!change.conflict
            color: Commons.Color.urgent
            text: strings.t("keymapConflict").arg(change.conflict && !change.conflict.missing ? root.codeLabel(change.conflict.current) : "—")
          }
          GridLayout {
            Layout.fillWidth: true
            columns: root.width < Commons.Style.space(620) ? 1 : 2
            visible: !!change.conflict
            Ui.Button { Layout.fillWidth: true; text: strings.t("keymapKeepKeyboard"); focusable: true; enabled: root.editable; onClicked: root.service.resolve(change.address, false) }
            Ui.Button { Layout.fillWidth: true; text: strings.t("keymapKeepEdit"); focusable: true; enabled: root.editable && change.conflict && !change.conflict.missing; onClicked: root.service.resolve(change.address, true) }
          }
        }
      }

      PlainText { Layout.fillWidth: true; visible: !!root.state.backup; text: strings.t("keymapBackup").arg(root.state.backup || "") }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    Ui.Button {
      objectName: "keymapApply"
      Layout.fillWidth: true; text: strings.t("keymapApply"); bordered: true; focusable: true
      enabled: root.editable && root.service.canApplyKeymap
      onClicked: root.service.applyKeymap()
    }
    Ui.Button { Layout.fillWidth: true; text: strings.t("keymapDiscard"); focusable: true; enabled: root.service && !root.service.actionBusy && root.service.changes.length > 0; onClicked: root.service.discard() }
  }
}
