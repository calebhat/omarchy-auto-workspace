import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "io.github.calebhat.workscape"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property string pluginId: "io.github.calebhat.workscape"
    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string configFile: stateHome + "/omarchy/workscape/config.json"
    readonly property string script: home + "/.config/omarchy/plugins/" + pluginId + "/workscape.sh"

    property int totalCount: 0
    property int enabledCount: 0
    property int profileCount: 0
    property bool pluginEnabled: true
    property string lastError: ""
    property bool pendingOpen: false

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function ensurePanel() {
        if (!panelLoader.active) panelLoader.active = true
    }
    function open() {
        if (panelLoader.item) { panelLoader.item.open(); return }
        pendingOpen = true
        ensurePanel()
    }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() {
        if (panelLoader.item) { panelLoader.item.toggle(); return }
        pendingOpen = true
        ensurePanel()
    }
    function togglePanel() { toggle() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }

    function refreshCounts() {
        if (!statusProc.running) statusProc.running = true
    }

    function applyMatching() {
        if (applyProc.running) return
        applyProc.command = ["bash", root.script, "--apply-matching"]
        applyProc.running = true
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Process {
        id: statusProc
        command: ["bash", "-c", "cat \"$1\" 2>/dev/null | jq -c '{total: ([.profiles[]?.assignments[]?]|length), enabled: ([.profiles[]?.assignments[]?|select(.enabled==true)]|length), profiles: (.profiles|length), pluginEnabled: (.settings.enabled // true)}' 2>/dev/null || echo '{\"total\":0,\"enabled\":0,\"profiles\":0,\"pluginEnabled\":true}'", "_", root.configFile]
        property string out: ""
        stdout: SplitParser { onRead: function(d){ statusProc.out += d } }
        onExited: function(code){
            try {
                var j = JSON.parse(statusProc.out.trim() || "{}")
                root.totalCount = Number(j.total || 0)
                root.enabledCount = Number(j.enabled || 0)
                root.profileCount = Number(j.profiles || 0)
                root.pluginEnabled = j.pluginEnabled !== false
            } catch (e) {}
            statusProc.out = ""
        }
    }

    Process {
        id: applyProc
        stdout: SplitParser { onRead: function(d){ console.log("[workscape] " + d) } }
        stderr: SplitParser { onRead: function(d){ console.warn("[workscape] " + d) } }
    }

    Timer {
        id: pollTimer
        interval: 8000
        repeat: false
        running: false
        triggeredOnStart: false
        onTriggered: root.refreshCounts()
    }

    IpcHandler {
        target: root.pluginId + ".panel"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }

    Connections {
        target: panelLoader.item
        ignoreUnknownSignals: true
        function onCountsChanged() { root.refreshCounts() }
    }

    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
            if (root.pendingOpen && panelLoader.item) {
                root.pendingOpen = false
                panelLoader.item.open()
            }
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󱂬"
        slotSize: Style.bar.statusSlot
        tooltipText: root.pluginEnabled
            ? ("WorkScape • " + root.profileCount + " profiles • " + root.enabledCount + " apps • click to manage • middle-click apply matching")
            : "WorkScape • disabled • click to enable"
        onPressed: function(btn){
            if (btn === Qt.LeftButton) root.toggle()
            else if (btn === Qt.MiddleButton) root.applyMatching()
        }
    }

    Component.onCompleted: refreshCounts()
}
