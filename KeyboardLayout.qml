pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Item {
  id: root
  required property var keys
  property var codes: []
  property var factory: ({})
  required property var drafts
  required property int selectedLayer
  property int selected: -1
  property bool matrixMode: false
  property int matrixRows: 0
  property int matrixCols: 0
  readonly property bool validMatrix: matrixRows > 0 && matrixRows <= 32 && matrixCols > 0 && matrixCols <= 32
  signal selectedKey(int index)
  // Physical ANSI Air75 V3 rows: index, x in key units, width in key units.
  readonly property var physicalRows: [
    [[0,0,1],[1,1,1],[2,2,1],[3,3,1],[4,4,1],[5,5,1],[6,6,1],[7,7,1],[8,8,1],[9,9,1],[10,10,1],[11,11,1],[12,12,1],[13,13,1],[14,14,1],[60,15,1]],
    [[16,0,1],[17,1,1],[18,2,1],[19,3,1],[20,4,1],[21,5,1],[22,6,1],[23,7,1],[24,8,1],[25,9,1],[26,10,1],[27,11,1],[28,12,1],[29,13,2],[31,15,1]],
    [[32,0,1.5],[33,1.5,1],[34,2.5,1],[35,3.5,1],[36,4.5,1],[37,5.5,1],[38,6.5,1],[39,7.5,1],[40,8.5,1],[41,9.5,1],[42,10.5,1],[43,11.5,1],[44,12.5,1],[45,13.5,1.5],[47,15,1]],
    [[48,0,1.75],[49,1.75,1],[50,2.75,1],[51,3.75,1],[52,4.75,1],[53,5.75,1],[54,6.75,1],[55,7.75,1],[56,8.75,1],[57,9.75,1],[58,10.75,1],[59,11.75,1],[61,12.75,2.25],[63,15,1]],
    [[64,0,2.25],[66,2.25,1],[67,3.25,1],[68,4.25,1],[69,5.25,1],[70,6.25,1],[71,7.25,1],[72,8.25,1],[73,9.25,1],[74,10.25,1],[75,11.25,1],[76,12.25,1.75],[78,14,1],[79,15,1]],
    [[80,0,1.25],[81,1.25,1.25],[82,2.5,1.25],[86,3.75,6.25],[90,10,1],[91,11,1],[92,12,1],[93,13,1],[94,14,1],[95,15,1]]
  ]
  readonly property var rows: matrixMode ? (validMatrix ? Array.from({length: matrixRows}, function(_, row) {
    return Array.from({length: root.matrixCols}, function(_, col) { return [row * root.matrixCols + col, col, 1] })
  }) : []) : physicalRows
  readonly property real unit: width / (matrixMode ? Math.max(1, matrixCols) : 16)
  readonly property var codeNames: codes.reduce(function(result, code) { result[code.value] = code.name; return result }, {})
  readonly property var shortNames: ({BSPC: "Bksp", ENT: "Enter", SPC: "Space", LSFT: "Shift", RSFT: "Shift", LCTL: "Ctrl", RCTL: "Ctrl", LALT: "Alt", RALT: "Alt", LGUI: "GUI", RGUI: "GUI", GRV: "`", MINS: "−", EQL: "=", LBRC: "[", RBRC: "]", BSLS: "\\", SCLN: ";", QUOT: "'", COMM: ",", DOT: ".", SLSH: "/", LEFT: "←", RGHT: "→", UP: "↑", DOWN: "↓", BRID: "Bri−", BRIU: "Bri+", MPRV: "Prev", MNXT: "Next", MPLY: "Play", VOLD: "Vol−", VOLU: "Vol+", MUTE: "Mute", MISSION_CONTROL: "Tasks", MAC_SEARCH: "Find", SIRI: "Mic", DND: "DND", NO: "—", TRNS: "▽"})
  implicitHeight: unit * rows.length
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function assignmentName(value, fallback) { return codeNames[value] || fallback || ("0x" + value.toString(16)) }
  function assignmentLabel(value, fallback) {
    if ((value & 0xffe0) === 0x5220) return "FN" + (value & 31)
    var name = assignmentName(value, fallback)
    return shortNames[name] || name
  }

  LayoutMirroring.enabled: false
  LayoutMirroring.childrenInherit: true
  Repeater {
    model: root.rows
    delegate: Item {
      id: row
      required property var modelData
      required property int index
      y: index * root.unit; width: root.width; height: root.unit
      Repeater {
        model: row.modelData
        delegate: Ui.Button {
          id: key
          required property var modelData
          readonly property int keyIndex: modelData[0]
          readonly property var entry: root.keys[root.selectedLayer + ":" + keyIndex] || ({})
          x: modelData[1] * root.unit; width: modelData[2] * root.unit - 2; height: root.unit - 2
          readonly property var factoryEntry: root.factory[root.selectedLayer + ":" + keyIndex]
          readonly property var pending: root.drafts[root.selectedLayer + ":" + keyIndex]
          readonly property bool modified: !!factoryEntry && factoryEntry.value !== entry.value
          readonly property int assignment: pending ? pending.value : (entry.value || 0)
          objectName: "diagramKey-" + keyIndex
          text: root.assignmentLabel(assignment, pending ? "" : entry.name)
          readonly property string positionLabel: root.matrixMode ? strings.t("keymapMatrixPosition").arg(Math.floor(keyIndex / root.matrixCols)).arg(keyIndex % root.matrixCols).arg(keyIndex) : (entry.position || "#" + keyIndex)
          tooltipText: strings.t("keymapKeyTip").arg((!root.matrixMode && keyIndex === 60 ? strings.t("keymapKnobPress") + " · " : "") + positionLabel).arg(root.assignmentName(assignment, pending ? "" : entry.name))
          radius: !root.matrixMode && keyIndex === 60 ? height / 2 : Commons.Style.space(3)
          horizontalPadding: Commons.Style.space(2)
          fontSize: Commons.Style.font.caption
          PlainText {
            anchors.top: parent.top; anchors.right: parent.right
            anchors.margins: Commons.Style.space(2)
            visible: !!key.pending || key.modified
            text: key.pending ? "•" : "*"
            color: Commons.Color.accent
            font.pixelSize: Commons.Style.font.caption
          }
          selected: root.selected === keyIndex
          enabled: entry.value !== undefined
          bordered: true; focusable: true
          foreground: root.selected === keyIndex ? Commons.Color.accent : Commons.Color.popups.text
          onClicked: root.selectedKey(keyIndex)
        }
      }
    }
  }
}
