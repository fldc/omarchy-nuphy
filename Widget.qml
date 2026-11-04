pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
  id: root
  moduleName: "local.nuphy"
  ipcTarget: "nuphy"
  implicitWidth: Style.bar.iconSlot
  implicitHeight: Style.bar.iconSlot
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("local.nuphy") : null

  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    tooltipText: "NuPhy"
    onPressed: root.toggle()
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: panel.fittedContentWidth(panel.loadedContent ? panel.loadedContent.preferredWidth : Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(760))
    focusTarget: panel.loadedContent
    content: Component {
      NuphyEditor {
        service: root.service
        onCloseRequested: root.close()
      }
    }
  }
}
