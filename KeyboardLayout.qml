pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

Item {
  id: root
  required property var keys
  property var factory: ({})
  required property var drafts
  required property int selectedLayer
  property int selected: -1
  signal selectedKey(int index)
  // Physical ANSI Air75 V3 rows: index, x in key units, width in key units.
  readonly property var rows: [
    [[0,0,1],[1,1.25,1],[2,2.25,1],[3,3.25,1],[4,4.25,1],[5,5.5,1],[6,6.5,1],[7,7.5,1],[8,8.5,1],[9,9.75,1],[10,10.75,1],[11,11.75,1],[12,12.75,1],[13,13.75,1],[14,15,1],[60,16,1]],
    [[16,0,1],[17,1,1],[18,2,1],[19,3,1],[20,4,1],[21,5,1],[22,6,1],[23,7,1],[24,8,1],[25,9,1],[26,10,1],[27,11,1],[28,12,1],[29,13,2],[31,16,1]],
    [[32,0,1.5],[33,1.5,1],[34,2.5,1],[35,3.5,1],[36,4.5,1],[37,5.5,1],[38,6.5,1],[39,7.5,1],[40,8.5,1],[41,9.5,1],[42,10.5,1],[43,11.5,1],[44,12.5,1],[45,13.5,1.5],[47,16,1]],
    [[48,0,1.75],[49,1.75,1],[50,2.75,1],[51,3.75,1],[52,4.75,1],[53,5.75,1],[54,6.75,1],[55,7.75,1],[56,8.75,1],[57,9.75,1],[58,10.75,1],[59,11.75,1],[61,12.75,2.25],[63,16,1]],
    [[64,0,2.25],[66,2.25,1],[67,3.25,1],[68,4.25,1],[69,5.25,1],[70,6.25,1],[71,7.25,1],[72,8.25,1],[73,9.25,1],[74,10.25,1],[75,11.25,1],[76,12.25,2.75],[78,15,1],[79,16,1]],
    [[80,0,1.25],[81,1.25,1.25],[82,2.5,1.25],[86,3.75,6.25],[90,10,1],[91,11,1],[92,12,1],[93,14,1],[94,15,1],[95,16,1]]
  ]
  readonly property real unit: width / 17
  implicitHeight: unit * 6
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
          text: (root.drafts[root.selectedLayer + ":" + keyIndex] ? "• " : (factoryEntry && factoryEntry.value !== entry.value ? "* " : "")) + (entry.position || "")
          selected: root.selected === keyIndex
          bordered: true; focusable: true
          foreground: root.selected === keyIndex ? Commons.Color.accent : Commons.Color.popups.text
          onClicked: root.selectedKey(keyIndex)
        }
      }
    }
  }
}
