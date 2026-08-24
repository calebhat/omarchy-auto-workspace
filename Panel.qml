import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.calebhat.auto-workspace"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
    readonly property string pluginId: "io.github.calebhat.auto-workspace"
    readonly property string configFile: stateHome + "/omarchy/auto-workspace/config.json"
    readonly property string script: home + "/.config/omarchy/plugins/" + pluginId + "/auto-workspace.sh"

    signal countsChanged()

    property var config: Model.defaultConfig()
    property var assignments: []
    property bool loading: true
    property string errorText: ""
    property string statusText: ""
    property var appList: []
    property string appFilter: ""
    property bool adding: false
    property int formWorkspace: 1
    property bool workspacePicked: false
    property string formName: ""
    property string formCommand: ""
    property string formType: "app"
    property string formExecPreview: ""
    property bool formNameEdited: false
    property string autoName: ""
    property bool fillingName: false
    property string mainView: "apps"
    property string customCommand: ""
    property string customName: ""
    property var liveStatus: ({ live: [], profiles: [], matchedProfileId: "", bindings: {} })
    property var liveMonitors: []
    onFormTypeChanged: { updateFormPreview(); updateAutofillName() }

    property string hyprLayout: "dwindle"
    property real hyprColumnWidth: 0.49

    property bool cursorActive: false
    property int selectedRow: 0
    property int selectedButton: 0

    readonly property color foreground: root.barForeground
    readonly property color dim: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.55)
    readonly property string fontFamily: Style.font.family

    readonly property string activeProfileId: (config.settings && config.settings.activeProfileId) ? config.settings.activeProfileId : "default"
    readonly property var activeProfile: Model.profileById(config, activeProfileId) || Model.defaultProfile()
    readonly property var profileOptions: {
        var list = config.profiles || []
        var out = []
        for (var i = 0; i < list.length; i++) out.push({ value: list[i].id, label: list[i].name })
        return out
    }
    readonly property var monitorOptions: Model.monitorOptions(config, activeProfile, liveMonitors)
    readonly property string workspaceMonitorId: {
        var map = activeProfile.workspaceMonitors || {}
        return String(map[String(formWorkspace)] || "")
    }
    readonly property string matchedLabel: liveStatus.matchedProfileName ? ("matches " + liveStatus.matchedProfileName) : "no layout match"
    readonly property int totalCount: {
        var n = 0
        var list = config.profiles || []
        for (var i = 0; i < list.length; i++) n += (list[i].assignments || []).length
        return n
    }
    readonly property int enabledCount: (function(){
        var n = 0
        for (var i = 0; i < assignments.length; i++) if (assignments[i].enabled !== false) n++
        return n
    })()

    function open() { root.controller.show(); loadConfig(); layoutProc.running = true; liveProc.running = true; root.workspacePicked = true }
    function close() { root.controller.hide() }
    function toggle() { root.opened ? root.close() : root.open() }
    function closeForPopoutSwitch() { root.close() }
    function switchPanel(dir) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, dir)
        return false
    }

    function loadConfig() { loading=true; errorText=""; loadProc.running=true; if (!layoutProc.running) layoutProc.running = true; liveProc.running = true }
    function currentConfig() {
        var cfg = Model.sanitizeConfig(config)
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id === pid) {
                cfg.profiles[i].assignments = assignments.slice(0, 50)
                for (var j = 0; j < cfg.profiles[i].assignments.length; j++) {
                    var a = cfg.profiles[i].assignments[j]
                    if (a.type === "webapp" && a.command.indexOf("http") === 0) {
                        a.exec = "omarchy-launch-webapp '" + a.command.replace(/'/g, "'\\''") + "'"
                        if (!a.name || a.name === a.command) a.name = Model.displayNameForExec(a.exec, "Web App")
                    } else if (a.exec === "" && a.command !== "") a.exec = a.command
                    cfg.profiles[i].assignments[j] = a
                }
            }
        }
        return cfg
    }
    function saveConfig() {
        var cfg = root.currentConfig()
        config = cfg
        assignments = (Model.profileById(cfg, cfg.settings.activeProfileId) || { assignments: [] }).assignments.slice()
        saveProc.pendingJson = JSON.stringify(cfg, null, 2)
        if (saveProc.running) { saveProc.wantsSave = true; return }
        saveProc.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\"; printf '%s' \"$2\" > \"$1\"; cat \"$1\" | jq empty && echo OK || echo FAIL", "_", root.configFile, saveProc.pendingJson]
        saveProc.running = true
    }
    function setActiveProfile(id) {
        var cfg = root.currentConfig()
        if (!Model.profileById(cfg, id)) return
        cfg.settings.activeProfileId = id
        config = cfg
        assignments = Model.profileById(cfg, id).assignments.slice()
        saveConfig()
    }
    function setWorkspaceMonitor(monitorId) {
        var cfg = root.currentConfig()
        var pid = cfg.settings.activeProfileId
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var map = cfg.profiles[i].workspaceMonitors || {}
            if (!monitorId) delete map[String(formWorkspace)]
            else map[String(formWorkspace)] = monitorId
            cfg.profiles[i].workspaceMonitors = map
            if (monitorId && cfg.profiles[i].monitors.indexOf(monitorId) < 0)
                cfg.profiles[i].monitors = cfg.profiles[i].monitors.concat([monitorId])
        }
        config = cfg
        saveConfig()
    }
    function addAssignment() {
        var name = formName.trim(), cmd = formCommand.trim()
        if (!cmd.length) { errorText = "Command / URL is required"; return }
        if (!name.length) {
            if (formType === "webapp") name = Model.displayNameForExec("omarchy-launch-webapp '" + cmd + "'", "Web App")
            else name = Model.displayNameForExec(cmd, "App")
        }
        var execStr = cmd
        if (formType === "webapp" && (cmd.indexOf("http://") === 0 || cmd.indexOf("https://") === 0))
            execStr = "omarchy-launch-webapp '" + cmd.replace(/'/g, "'\\''") + "'"
        var item = Model.normalizeAssignment({ workspace: formWorkspace, name: name, command: cmd, exec: execStr, type: formType, enabled: true, onlyOnBoot: true })
        assignments = assignments.concat([item])
        formName = ""; formCommand = ""; formType = "app"; formNameEdited = false
        saveConfig(); statusText = "Added " + item.name + " → WS" + item.workspace; clearStatusTimer.restart()
        if (root.bar && typeof root.bar.broadcast === "function") root.bar.broadcast("refreshCounts")
        root.countsChanged()
    }
    function addCustomCommand() {
        var cmd = customCommand.trim()
        if (!cmd.length) { errorText = "Command is required"; return }
        var name = customName.trim() || Model.displayNameForExec(cmd, "App")
        var item = Model.normalizeAssignment({ workspace: formWorkspace, name: name, command: cmd, exec: cmd, type: "custom", enabled: true, onlyOnBoot: false })
        assignments = assignments.concat([item])
        customCommand = ""; customName = ""
        saveConfig(); statusText = "Added " + item.name + " → WS" + item.workspace; clearStatusTimer.restart()
        root.countsChanged()
    }
    function updateFormPreview() {
        if (formType === "webapp" && (formCommand.indexOf("http://") === 0 || formCommand.indexOf("https://") === 0)) formExecPreview = "omarchy-launch-webapp '" + formCommand + "'"
        else formExecPreview = formCommand
    }
    function persistFormWorkspace() {
        var s = Model.clone(root.config); s.settings.lastFormWorkspace = root.formWorkspace; root.config = s; root.saveConfig()
    }
    function removeAssignment(id) {
        root.assignments = root.assignments.filter(function(a){ return a.id !== id })
        root.saveConfig()
        root.statusText = "Removed"; clearStatusTimer.restart()
    }
    function isInList(list, exec) {
        if (!list) return false
        for (var i = 0; i < list.length; i++) if (list[i].exec === exec || list[i].command === exec) return true
        return false
    }
    function toggleInWorkspace(exec, name) {
        var ws = root.formWorkspace
        for (var i = 0; i < root.assignments.length; i++) {
            var a = root.assignments[i]
            if (a.workspace === ws && (a.exec === exec || a.command === exec)) {
                root.removeAssignment(a.id)
                root.statusText = "Removed " + a.name + " from WS" + ws; clearStatusTimer.restart()
                return
            }
        }
        var type = /herdr/.test(exec) || exec.indexOf("/") === 0 || exec.indexOf(" ") >= 0 ? "custom" : "app"
        var item = Model.normalizeAssignment({ workspace: ws, name: name, command: exec, exec: exec, type: type, enabled: true, onlyOnBoot: true })
        root.assignments = root.assignments.concat([item])
        root.saveConfig(); root.statusText = "Added " + item.name + " → WS" + item.workspace; clearStatusTimer.restart()
        if (root.bar && typeof root.bar.broadcast === "function") root.bar.broadcast("refreshCounts")
        root.countsChanged()
    }
    function updateAutofillName() {
        var cmd = formCommand.trim()
        if (!cmd.length) { autoName = ""; if (!formNameEdited) { fillingName = true; formName = ""; fillingName = false } return }
        var n
        if (formType === "webapp" && (cmd.indexOf("http://") === 0 || cmd.indexOf("https://") === 0)) n = Model.displayNameForExec("omarchy-launch-webapp '" + cmd + "'", "Web App")
        else n = Model.displayNameForExec(cmd, "App")
        autoName = n
        if (!formNameEdited) { fillingName = true; formName = n; fillingName = false }
    }
    function applyMatching() { applyProc.command = ["bash", root.script, "--apply-matching"]; applyProc.running = true; statusText = "Applying matching profile…"; clearStatusTimer.restart() }
    function applyProfile(id) { applyProc.command = ["bash", root.script, "--apply-profile", id]; applyProc.running = true; statusText = "Applying profile…"; clearStatusTimer.restart() }
    function addProfileFromLive() {
        var cfg = root.currentConfig()
        var live = root.liveMonitors || []
        if (!live.length) { errorText = "No monitors detected"; return }
        var ids = []
        for (var i = 0; i < live.length; i++) {
            var up = Model.upsertLiveMonitor(cfg, live[i])
            cfg = up.config
            if (up.id) ids.push(up.id)
        }
        var prof = Model.defaultProfile()
        prof.id = Model.makeId("pr")
        prof.name = live.length <= 1 ? "Laptop" : ("Desk " + live.length + " monitors")
        prof.monitors = ids
        prof.matchMode = "exact"
        cfg.profiles = cfg.profiles.concat([prof])
        cfg.settings.activeProfileId = prof.id
        config = cfg
        assignments = []
        saveConfig()
        statusText = "Saved layout as " + prof.name; clearStatusTimer.restart()
        mainView = "profiles"
    }
    function renameProfile(id, name) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) if (cfg.profiles[i].id === id) cfg.profiles[i].name = String(name).slice(0, 48)
        config = cfg; saveConfig()
    }
    function setMatchMode(id, mode) {
        var cfg = root.currentConfig()
        for (var i = 0; i < cfg.profiles.length; i++) if (cfg.profiles[i].id === id) cfg.profiles[i].matchMode = mode === "all-present" ? "all-present" : "exact"
        config = cfg; saveConfig()
    }
    function deleteProfile(id) {
        var cfg = root.currentConfig()
        if ((cfg.profiles || []).length <= 1) { errorText = "Keep at least one profile"; return }
        cfg.profiles = cfg.profiles.filter(function(p){ return p.id !== id })
        if (cfg.settings.activeProfileId === id) cfg.settings.activeProfileId = cfg.profiles[0].id
        config = cfg
        assignments = (Model.profileById(cfg, cfg.settings.activeProfileId) || { assignments: [] }).assignments.slice()
        saveConfig()
    }
    function setApplyOnBoot(on) {
        var cfg = root.currentConfig()
        cfg.settings.applyOnBoot = !!on
        config = cfg
        saveConfig()
    }
    onFormCommandChanged: { updateFormPreview(); updateAutofillName() }
    Timer { id: clearStatusTimer; interval: 3000; onTriggered: root.statusText = "" }

    function actionCount(app) { return 1 }
    function clampCursor() {
        var rows = filteredApps
        if (rows.length === 0) { selectedRow = 0; selectedButton = 0; return }
        selectedRow = Math.max(0, Math.min(selectedRow, rows.length - 1))
        selectedButton = Math.max(0, Math.min(selectedButton, actionCount(rows[selectedRow]) - 1))
    }
    function setCursor(row, button) { cursorActive = true; selectedRow = row; selectedButton = button; clampCursor() }
    function moveCursor(dx, dy) {
        var rows = filteredApps
        if (rows.length === 0) return
        if (!cursorActive) { setCursor(0, 0); return }
        if (dy !== 0) {
            if (dy < 0 && selectedRow === 0) { cursorActive = false; filterField.forceActiveFocus(); return }
            if (dy > 0 && selectedRow === rows.length - 1) { cursorActive = false; filterField.forceActiveFocus(); return }
            selectedRow = Math.max(0, Math.min(rows.length - 1, selectedRow + dy))
            selectedButton = Math.min(selectedButton, actionCount(rows[selectedRow]) - 1)
        } else if (dx !== 0) {
            selectedButton = Math.max(0, Math.min(actionCount(rows[selectedRow]) - 1, selectedButton + dx))
        }
        cursorActive = true
    }
    function moveTabCursor(direction) {
        var rows = filteredApps
        if (rows.length === 0) return
        if (!cursorActive) { if (direction > 0) setCursor(0, 0); return }
        if (direction > 0) {
            if (selectedRow === rows.length - 1) { cursorActive = false; filterField.forceActiveFocus(); return }
            selectedRow++; selectedButton = 0
        } else {
            if (selectedRow === 0) { cursorActive = false; filterField.forceActiveFocus(); return }
            selectedRow--; selectedButton = actionCount(rows[selectedRow]) - 1
        }
        cursorActive = true
    }
    function activateCursor() {
        var app = filteredApps[selectedRow]
        if (!app) return
        toggleInWorkspace(app.exec, app.name)
    }
    function ensureCursorVisible(item) {
        if (!item || !resultsScroll) return
        var flick = resultsScroll.contentItem
        var point = item.mapToItem(flick.contentItem || flick, 0, 0)
        var top = point.y
        var bottom = top + item.height
        if (top < flick.contentY) flick.contentY = Math.max(0, top - Style.space(8))
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = bottom - flick.height + Style.space(8)
    }

    Process {
        id: loadProc
        command: ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\"; [[ -f \"$1\" || ! -f \"$3\" ]] || cp \"$3\" \"$1\"; [[ -f \"$1\" ]] || echo '{\"version\":2,\"settings\":{\"enabled\":true,\"applyOnBoot\":false,\"launchDelayMs\":800,\"staggerMs\":400,\"silent\":true,\"onlyOnBoot\":true,\"lastFormWorkspace\":1,\"activeProfileId\":\"default\"},\"monitors\":[],\"extraApps\":[],\"profiles\":[{\"id\":\"default\",\"name\":\"Default\",\"matchMode\":\"exact\",\"monitors\":[],\"workspaceMonitors\":{},\"assignments\":[]}]}' > \"$1\"; cat \"$1\"", "_", root.configFile, "", root.configHome + "/omarchy/plugins/tenzin.auto-workspace/config.json"]
        stdout: StdioCollector { id: loadOut; waitForEnd: true }
        stderr: StdioCollector { id: loadErr; waitForEnd: true }
        onExited: function(code){
            root.loading = false; var txt = loadOut.text || ""
            if (code !== 0) { root.errorText = "Failed to load config (" + code + ")"; return }
            try {
                var j = JSON.parse(txt)
                var sane = Model.sanitizeConfig(j)
                root.config = sane
                var prof = Model.profileById(sane, sane.settings.activeProfileId)
                root.assignments = (prof && prof.assignments) ? prof.assignments.slice() : []
                root.formWorkspace = sane.settings.lastFormWorkspace
                root.countsChanged()
            } catch (e) { root.errorText = "Invalid config JSON: " + e }
        }
    }
    Process {
        id: saveProc
        property string pendingJson: ""
        property bool wantsSave: false
        stdout: StdioCollector { id: saveOut; waitForEnd: true }
        stderr: StdioCollector { id: saveErr; waitForEnd: true }
        onExited: function(code){
            if (code !== 0) { root.errorText = "Save failed (" + code + "): " + (saveErr.text || "") }
            else root.errorText = ""
            if (saveProc.wantsSave) {
                saveProc.wantsSave = false
                saveProc.command = ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\"; printf '%s' \"$2\" > \"$1\"; cat \"$1\" | jq empty && echo OK || echo FAIL", "_", root.configFile, saveProc.pendingJson]
                saveProc.running = true
            } else if (code === 0) {
                root.countsChanged(); refreshServiceProc.running = true
            }
        }
    }
    Process { id: refreshServiceProc; command: ["bash", "-c", "omarchy-shell -q io.github.calebhat.auto-workspace refreshConfig >/dev/null 2>&1 || true"] }
    Process {
        id: applyProc
        stdout: SplitParser { onRead: function(d){ console.log("[auto-workspace] " + d) } }
        stderr: SplitParser { onRead: function(d){ console.warn("[auto-workspace] " + d) } }
        onExited: function(code) { root.statusText = code === 0 ? "Applied" : "Apply failed"; clearStatusTimer.restart(); liveProc.running = true }
    }
    Process {
        id: layoutProc
        command: ["bash", "-c", "layout=$(hyprctl getoption general:layout -j 2>/dev/null | jq -r '.str // empty' 2>/dev/null); col=$(hyprctl getoption scrolling:column_width -j 2>/dev/null | jq -r '.float // 0.49' 2>/dev/null); echo \"${layout:-dwindle}|${col:-0.49}\""]
        stdout: StdioCollector { id: layoutOut; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) return
            var txt = (layoutOut.text || "").trim()
            if (!txt) return
            var parts = txt.split("|")
            if (parts[0]) root.hyprLayout = parts[0].trim()
            var cw = parseFloat(parts[1])
            if (!isNaN(cw) && cw > 0.1 && cw < 1.0) root.hyprColumnWidth = cw
        }
    }
    Process {
        id: liveProc
        command: ["bash", root.script, "--live-status"]
        stdout: StdioCollector { id: liveOut; waitForEnd: true }
        onExited: function(code) {
            if (code !== 0) return
            try {
                var j = JSON.parse(liveOut.text || "{}")
                root.liveStatus = j
                root.liveMonitors = j.live || []
            } catch (e) {}
        }
    }
    Process {
        id: appsProc
        command: ["bash", root.script, "--list-apps"]
        stdout: StdioCollector { id: appsOut; waitForEnd: true }
        onExited: function(code){
            if (code !== 0) return
            var txt = appsOut.text || "", lines = txt.split("\n"), list = []
            for (var i = 0; i < lines.length; i++) {
                var l = lines[i].trim(); if (!l) continue
                var p = l.split("\t"); if (p.length < 2) continue
                list.push({ name: p[0], exec: p[1], icon: p[2] || "", iconPath: p[3] || "", score: Number(p[5]) || 0 })
                if (list.length > 600) break
            }
            root.appList = list
        }
    }
    function alphabeticalCompare(a, b) {
        var na = a.name.toLowerCase(), nb = b.name.toLowerCase()
        return na.localeCompare(nb, undefined, { numeric: true })
    }
    readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    function iconSourceFor(app) {
        if (!app) return ""
        if (app.iconPath && app.iconPath !== "") return "file://" + app.iconPath
        var icon = String(app.icon || "")
        if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(icon)
        if (icon !== "" && icon.charAt(0) === "/") return "file://" + icon
        var themed = ""
        try { themed = Quickshell.iconPath(icon, true) } catch (e) { themed = "" }
        if (themed && themed.length > 0) return themed
        try { return Quickshell.iconPath("application-x-executable", true) } catch (e) { return "" }
    }
    property var filteredApps: {
        var f = appFilter.trim().toLowerCase()
        var list = []
        for (var i = 0; i < appList.length; i++) list.push(appList[i])
        if (!f) {
            var act = list.filter(function(a){ return root.isInList(root.addedApps, a.exec) })
            var pinned = list.filter(function(a){ return a.score >= 9999 })
            var pool = act.length > 0 ? act : (pinned.length > 0 ? pinned.concat(list) : list)
            var seen = {}
            var uniq = []
            for (var u = 0; u < pool.length; u++) {
                if (seen[pool[u].exec]) continue
                seen[pool[u].exec] = true
                uniq.push(pool[u])
            }
            uniq.sort(function(a, b){
                if (b.score !== a.score) return b.score - a.score
                return root.alphabeticalCompare(a, b)
            })
            return uniq.slice(0, 8)
        }
        var exact = [], prefix = [], sub = []
        for (var j = 0; j < list.length; j++) {
            var b = list[j]
            var n = b.name.toLowerCase(), e = b.exec.toLowerCase()
            if (n === f || e === f) exact.push(b)
            else if (n.indexOf(f) === 0) prefix.push(b)
            else if (n.indexOf(f) !== -1 || e.indexOf(f) !== -1) sub.push(b)
        }
        exact.sort(root.alphabeticalCompare)
        prefix.sort(root.alphabeticalCompare)
        sub.sort(root.alphabeticalCompare)
        return exact.concat(prefix, sub).slice(0, 6)
    }
    function getAppsForWs(ws) {
        var out = []
        for (var i = 0; i < assignments.length; i++) if (assignments[i].workspace === ws) out.push(assignments[i])
        return out
    }
    property var addedApps: {
        var out = []
        for (var i = 0; i < assignments.length; i++) if (assignments[i].workspace === formWorkspace) out.push(assignments[i])
        return out
    }
    function profileMatchBadge(id) {
        var list = (liveStatus.profiles || [])
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        centerOnBar: true
        focusTarget: keyCatcher
        padding: Style.space(24)
        contentWidth: panel.fittedContentWidth(Style.space(920))
        contentHeight: panel.fittedContentHeight(content.implicitHeight + Style.space(40), panel.screenH - Style.gapsOut * 2 - Style.space(16))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: filterField.activeFocus || customField.activeFocus || customNameField.activeFocus
            onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
            onActivateRequested: root.activateCursor()
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.moveTabCursor(direction) }
            onTextKey: function(t) {
                if (t === "/") {
                    cursorActive = false
                    filterField.forceActiveFocus()
                    filterField.selectAll()
                }
            }

            ColumnLayout {
                id: content
                anchors.fill: parent
                spacing: Style.space(12)

                PanelHero {
                    Layout.fillWidth: true
                    title: "Auto Workspace"
                    meta: root.totalCount + " apps · " + (root.config.profiles || []).length + " profiles · " + root.matchedLabel
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    iconComponent: Component {
                        Text {
                            text: "󱂬"
                            color: Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.display
                        }
                    }
                    trailingControl: Component {
                        Button {
                            text: "Apply matching"
                            tooltipText: "Detect connected monitors and load that profile (SUPER+ALT+W)"
                            onClicked: root.applyMatching()
                        }
                    }
                }

                ButtonGroup {
                    Layout.fillWidth: true
                    foreground: root.foreground
                    options: [
                        { value: "apps", label: "Apps" },
                        { value: "profiles", label: "Profiles" }
                    ]
                    value: root.mainView
                    onChanged: function(v) { root.mainView = v; liveProc.running = true }
                }

                Text {
                    text: root.mainView === "apps"
                          ? "↑↓ navigate · Enter toggles · / searches · Esc closes"
                          : "Profiles match the connected monitors by serial/description, not DP-1 names."
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // ——— Apps ———
                RowLayout {
                    visible: root.mainView === "apps"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Style.space(460), Math.round(panel.screenH * 0.52))
                    Layout.maximumHeight: Layout.preferredHeight
                    Layout.minimumHeight: Layout.preferredHeight
                    spacing: Style.space(14)

                    ColumnLayout {
                        id: leftStack
                        Layout.fillWidth: false
                        Layout.preferredWidth: Math.round(content.width * 0.34)
                        Layout.minimumWidth: Style.space(260)
                        Layout.alignment: Qt.AlignTop
                        spacing: Style.space(8)

                        PanelSectionHeader {
                            text: "PROFILE"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }
                        Dropdown {
                            Layout.fillWidth: true
                            label: ""
                            showLabel: false
                            foreground: root.foreground
                            value: root.activeProfileId
                            options: root.profileOptions
                            onChanged: function(v) { root.setActiveProfile(v) }
                        }

                        PanelSectionHeader {
                            text: "PICK A WORKSPACE"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 5
                            columnSpacing: Style.space(4)
                            rowSpacing: Style.space(4)
                            Repeater {
                                model: 10
                                delegate: Button {
                                    required property int index
                                    text: String(index + 1)
                                    selected: root.workspacePicked && root.formWorkspace === (index + 1)
                                    horizontalPadding: 0
                                    verticalPadding: 0
                                    onClicked: { root.workspacePicked = true; root.formWorkspace = index + 1; root.persistFormWorkspace() }
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(38)
                                }
                            }
                        }

                        Dropdown {
                            Layout.fillWidth: true
                            label: "Load workspace on"
                            foreground: root.foreground
                            value: root.workspaceMonitorId
                            options: root.monitorOptions
                            onChanged: function(v) { root.setWorkspaceMonitor(v) }
                        }

                        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

                        PanelSectionHeader {
                            text: "SEARCH APPS"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            TextField {
                                id: filterField
                                Layout.fillWidth: true
                                verticalPadding: Style.space(9)
                                placeholderText: "Search apps, Herdr, ShopHawk…"
                                foreground: root.foreground
                                accent: Color.accent
                                font.family: root.fontFamily
                                text: root.appFilter
                                onTextChanged: { root.appFilter = text; root.cursorActive = false }
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
                                    else if (event.key === Qt.Key_Down) { root.setCursor(0, 0); keyCatcher.forceActiveFocus(); event.accepted = true }
                                }
                            }
                            Button { text: "⟳"; tooltipText: "Refresh app list"; verticalPadding: Style.space(9); onClicked: { appsProc.running = true; liveProc.running = true } }
                        }

                        Text {
                            visible: root.filteredApps.length === 0 && root.appFilter.trim().length > 0
                            Layout.fillWidth: true
                            text: "No matches — use custom command below"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        ScrollView {
                            id: resultsScroll
                            visible: root.filteredApps.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded
                            Column {
                                width: resultsScroll.width
                                spacing: Style.space(6)
                                Repeater {
                                    model: root.filteredApps
                                    delegate: AppRow {
                                        app: modelData
                                        rowIndex: index
                                        width: parent.width
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            TextField {
                                id: customNameField
                                Layout.preferredWidth: Style.space(110)
                                placeholderText: "Name"
                                foreground: root.foreground
                                text: root.customName
                                onTextChanged: root.customName = text
                            }
                            TextField {
                                id: customField
                                Layout.fillWidth: true
                                placeholderText: "Custom command"
                                foreground: root.foreground
                                text: root.customCommand
                                onTextChanged: root.customCommand = text
                                Keys.onReturnPressed: root.addCustomCommand()
                            }
                            Button { text: "Add"; onClicked: root.addCustomCommand() }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.round(content.width * 0.66)
                        Layout.alignment: Qt.AlignTop
                        spacing: Style.space(10)

                        PanelSectionHeader {
                            text: "PREVIEW · " + root.activeProfile.name
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }
                        WorkspacePreview {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: Math.min(Style.space(200), Math.round(panel.screenH * 0.3))
                            bar: root.bar
                            workspace: root.formWorkspace
                            assignedApps: root.addedApps
                            appList: root.appList
                            screenW: panel.screenW
                            screenH: panel.screenH
                            hyprLayout: root.hyprLayout
                            columnWidth: root.hyprColumnWidth
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: {
                                var mon = ""
                                var opts = root.monitorOptions
                                for (var i = 0; i < opts.length; i++) if (opts[i].value === root.workspaceMonitorId) mon = opts[i].label
                                var line = mon && root.workspaceMonitorId ? ("WS " + root.formWorkspace + " → " + mon + ". ") : ("WS " + root.formWorkspace + " has no monitor pin. ")
                                if (root.addedApps.length > 1) {
                                    if (root.hyprLayout === "scrolling") line += "Scrolling layout."
                                    else if (root.hyprLayout === "master") line += "Master layout."
                                    else line += "Dwindle layout."
                                }
                                return line
                            }
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption - 1
                        }
                    }
                }

                // ——— Profiles ———
                ColumnLayout {
                    visible: root.mainView === "profiles"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Style.space(460), Math.round(panel.screenH * 0.52))
                    spacing: Style.space(10)

                    Toggle {
                        Layout.fillWidth: true
                        label: "Apply matching profile at login"
                        description: "Off by default. Hotkey SUPER+ALT+W (or Apply matching) detects the layout and loads it."
                        checked: root.config.settings && root.config.settings.applyOnBoot === true
                        foreground: root.foreground
                        onClicked: root.setApplyOnBoot(!(root.config.settings && root.config.settings.applyOnBoot === true))
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Button { text: "Save current monitors as profile"; onClicked: root.addProfileFromLive() }
                        Button { text: "Refresh layout"; onClicked: liveProc.running = true }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: {
                            var live = root.liveMonitors || []
                            if (!live.length) return "No monitors reported by Hyprland."
                            var parts = []
                            for (var i = 0; i < live.length; i++) parts.push(live[i].label || live[i].description || live[i].name)
                            return "Connected now: " + parts.join(" · ")
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        Column {
                            width: parent.parent.width
                            spacing: Style.space(8)
                            Repeater {
                                model: root.config.profiles || []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    implicitHeight: col.implicitHeight + Style.space(16)
                                    radius: Style.cornerRadius
                                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                                    border.width: 1
                                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, modelData.id === root.activeProfileId ? 0.35 : 0.12)
                                    ColumnLayout {
                                        id: col
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: Style.space(10)
                                        spacing: Style.space(6)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: modelData.name
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.bold: true
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: {
                                                    var b = root.profileMatchBadge(modelData.id)
                                                    if (!b) return ""
                                                    return b.matches ? "matches now" : b.reason
                                                }
                                                color: {
                                                    var b = root.profileMatchBadge(modelData.id)
                                                    return (b && b.matches) ? Color.accent : root.dim
                                                }
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData.monitors || []).length + " monitors · " + (modelData.assignments || []).length + " apps · " + (modelData.matchMode === "all-present" ? "all required present" : "exact layout")
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(6)
                                            Button { text: "Edit apps"; onClicked: { root.setActiveProfile(modelData.id); root.mainView = "apps" } }
                                            Button { text: "Apply"; onClicked: root.applyProfile(modelData.id) }
                                            Button {
                                                text: modelData.matchMode === "all-present" ? "Match: all present" : "Match: exact"
                                                onClicked: root.setMatchMode(modelData.id, modelData.matchMode === "all-present" ? "exact" : "all-present")
                                            }
                                            Item { Layout.fillWidth: true }
                                            Button { text: "Delete"; onClicked: root.deleteProfile(modelData.id) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(12)
                    Text {
                        visible: root.statusText !== ""
                        text: "✓ " + root.statusText
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: root.errorText !== ""
                        text: root.errorText
                        color: Color.urgent || "#ff4444"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    component AppRow: CursorSurface {
        property var app: null
        property int rowIndex: 0
        readonly property bool rowSelected: root.cursorActive && root.selectedRow === rowIndex
        hasCursor: rowSelected
        foreground: root.foreground
        implicitHeight: Style.space(44)

        onRowSelectedChanged: if (rowSelected) root.ensureCursorVisible(this)

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Item {
                Layout.preferredWidth: Style.space(22)
                Layout.alignment: Qt.AlignVCenter
                Image {
                    id: rowIcon
                    anchors.centerIn: parent
                    visible: source !== ""
                    width: 16
                    height: 16
                    source: app ? root.iconSourceFor(app) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    onStatusChanged: if (status === Image.Error) source = ""
                }
                Text {
                    anchors.centerIn: parent
                    visible: rowIcon.source === ""
                    text: "󰐱"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: app ? app.name : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: app ? (app.exec.indexOf("omarchy-launch-webapp") !== -1 ? "web app" : app.exec.split(" ")[0].split("/").pop()) : ""
                    color: root.dim
                    font.family: "monospace"
                    font.pixelSize: Style.font.caption - 2
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            ToggleSwitch {
                Layout.alignment: Qt.AlignVCenter
                checked: app ? root.isInList(root.addedApps, app.exec) : false
                cursorRing: true
                cursorPad: Style.space(3)
                foreground: root.foreground
                accent: Color.accent
                hasCursor: rowSelected && root.selectedButton === 0
                onHovered: function(on) { if (on) root.setCursor(rowIndex, 0) }
                onToggled: if (app) root.toggleInWorkspace(app.exec, app.name)
            }
        }
    }

    Component.onCompleted: { loadConfig(); appsProc.running = true; layoutProc.running = true; liveProc.running = true }
}
