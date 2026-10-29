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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(760))
    focusTarget: panel.loadedContent
    content: Component {
      LightingEditor {
        snapshot: root.service ? root.service.snapshot : ({})
        actionBusy: root.service ? root.service.actionBusy : false
        ready: root.service ? root.service.ready : false
        serviceError: root.service ? root.service.lastError : "NuPhy service unavailable"
        onApplyRequested: function(zone, config) { if (root.service) root.service.request("apply", zone, config) }
        onSyncRequested: if (root.service) root.service.request("sync")
        onCloseRequested: root.close()
      }
    }
  }
}
