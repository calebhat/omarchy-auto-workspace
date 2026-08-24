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
    property bool applyBusy: false
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
    readonly property bool showMonitorPicker: monitorOptions.length > 1
    property string copyTargetId: ""
    property bool transferOpen: false
    property string transferMode: "copy"
    property string transferFromWs: "1"
    property string transferToWs: "1"
    property string transferToProfileId: ""
    readonly property var copyProfileOptions: {
        var list = config.profiles || []
        var out = []
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === activeProfileId) continue
            out.push({ value: list[i].id, label: list[i].name })
        }
        return out
    }
    readonly property var workspaceOptions: {
        var out = []
        for (var i = 1; i <= 10; i++) out.push({ value: String(i), label: "WS " + i })
        return out
    }
    readonly property var transferToProfileOptions: transferMode === "move"
        ? [{ value: activeProfileId, label: activeProfile.name }]
        : root.profileOptions
    readonly property string workspaceMonitorId: {
        var map = activeProfile.workspaceMonitors || {}
        return String(map[String(formWorkspace)] || "")
    }
    readonly property string workspaceMonitorSummary: {
        var map = activeProfile.workspaceMonitors || {}
        var opts = monitorOptions
        var labelFor = function(id) {
            for (var i = 0; i < opts.length; i++) if (opts[i].value === id) return opts[i].label
            var m = Model.monitorById(config, id)
            return m ? m.label : id
        }
        var parts = []
        for (var ws = 1; ws <= 10; ws++) {
            var id = String(map[String(ws)] || "")
            if (!id) continue
            parts.push(ws + ":" + labelFor(id))
        }
        return parts.length ? parts.join("  ·  ") : "No workspace → monitor pins yet"
    }
    onFormWorkspaceChanged: Qt.callLater(syncMonitorDropdown)
    onActiveProfileIdChanged: Qt.callLater(syncMonitorDropdown)
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
        cfg.settings.lastFormWorkspace = formWorkspace
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
        var opts = []
        var list = cfg.profiles || []
        for (var i = 0; i < list.length; i++) if (list[i].id !== id) opts.push(list[i].id)
        if (opts.length && (root.copyTargetId === id || !root.copyTargetId)) root.copyTargetId = opts[0]
        saveConfig()
    }
    function openTransfer(mode) {
        transferMode = mode === "move" ? "move" : "copy"
        transferFromWs = String(formWorkspace)
        transferToWs = transferMode === "move" ? (formWorkspace === 10 ? "1" : String(formWorkspace + 1)) : String(formWorkspace)
        transferToProfileId = transferMode === "move" ? activeProfileId : (copyTargetId || (copyProfileOptions[0] ? copyProfileOptions[0].value : ""))
        transferOpen = true
    }
    function closeTransfer() { transferOpen = false }
    function confirmTransfer() {
        var fromWs = parseInt(transferFromWs, 10)
        var toWs = parseInt(transferToWs, 10)
        var cfg = root.currentConfig()
        if (transferMode === "move") {
            if (fromWs === toWs) { errorText = "Pick a different destination workspace"; return }
            cfg = Model.moveWorkspace(cfg, activeProfileId, fromWs, toWs)
            config = cfg
            assignments = (Model.profileById(cfg, activeProfileId) || { assignments: [] }).assignments.slice()
            formWorkspace = toWs
            persistFormWorkspace()
            statusText = "Moved WS" + fromWs + " → WS" + toWs
        } else {
            var toId = transferToProfileId
            if (!toId) { errorText = "Pick a destination profile"; return }
            cfg = Model.copyWorkspace(cfg, activeProfileId, fromWs, toId, toWs)
            var dest = Model.profileById(cfg, toId)
            if (!dest) { errorText = "Profile not found"; return }
            config = cfg
            saveConfig()
            statusText = "Copied WS" + fromWs + " → " + dest.name + " WS" + toWs
            clearStatusTimer.restart()
            closeTransfer()
            return
        }
        saveConfig()
        clearStatusTimer.restart()
        closeTransfer()
    }
    function syncMonitorDropdown() {
        if (monitorDropdown) monitorDropdown.value = root.workspaceMonitorId
    }
    function selectWorkspace(n) {
        formWorkspace = n
        workspacePicked = true
        persistWsTimer.restart()
        syncMonitorDropdown()
    }
    function setWorkspaceMonitor(monitorId) {
        monitorId = String(monitorId || "")
        if (monitorId === root.workspaceMonitorId) return
        var cfg = root.currentConfig()
        if (monitorId && !Model.monitorById(cfg, monitorId)) {
            var live = root.liveMonitors || []
            for (var n = 0; n < live.length; n++) {
                var tmp = Model.normalizeMonitor(live[n])
                if (tmp && tmp.id === monitorId) {
                    var up = Model.upsertLiveMonitor(cfg, live[n])
                    cfg = up.config
                    monitorId = up.id
                    break
                }
            }
        }
        var pid = cfg.settings.activeProfileId
        var wsKey = String(formWorkspace)
        for (var i = 0; i < cfg.profiles.length; i++) {
            if (cfg.profiles[i].id !== pid) continue
            var allowed = cfg.profiles[i].monitors || []
            if (monitorId && allowed.length && allowed.indexOf(monitorId) < 0) return
            var map = {}
            var prev = cfg.profiles[i].workspaceMonitors || {}
            var keys = Object.keys(prev)
            for (var k = 0; k < keys.length; k++) map[keys[k]] = prev[keys[k]]
            if (!monitorId) delete map[wsKey]
            else map[wsKey] = monitorId
            cfg.profiles[i].workspaceMonitors = map
        }
        config = cfg
        saveConfig()
        statusText = "WS" + formWorkspace + (monitorId ? " → " + (Model.monitorById(cfg, monitorId) || { label: monitorId }).label : " unpinned")
        clearStatusTimer.restart()
        Qt.callLater(syncMonitorDropdown)
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
        persistWsTimer.restart()
    }
    Timer { id: persistWsTimer; interval: 400; onTriggered: root.saveConfig() }
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
    function applyMatching() {
        if (root.applyBusy || applyProc.running) return
        root.applyBusy = true
        applyProc.command = ["bash", root.script, "--apply-matching"]
        applyProc.running = true
        statusText = "Applying matching profile…"
        clearStatusTimer.restart()
    }
    function applyProfile(id) {
        if (root.applyBusy || applyProc.running) return
        root.applyBusy = true
        applyProc.command = ["bash", root.script, "--apply-profile", id]
        applyProc.running = true
        statusText = "Applying profile…"
        clearStatusTimer.restart()
    }
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
    function applyPreviewLayout(tiles) {
        if (!tiles || !tiles.length) return
        var byId = {}
        for (var t = 0; t < tiles.length; t++) if (tiles[t] && tiles[t].id) byId[tiles[t].id] = tiles[t]
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var a = Model.clone(assignments[i])
            if (byId[a.id]) {
                var g = Model.normalizeGeom(byId[a.id])
                if (g) a.geom = g
            }
            next.push(a)
        }
        assignments = next
        saveConfig()
        statusText = "Saved window layout on WS" + formWorkspace
        clearStatusTimer.restart()
    }

    function resetPreviewLayout() {
        var next = []
        for (var i = 0; i < assignments.length; i++) {
            var a = Model.clone(assignments[i])
            if (a.workspace === formWorkspace) delete a.geom
            next.push(a)
        }
        assignments = next
        saveConfig()
        statusText = "Reset WS" + formWorkspace + " to tiling"
        clearStatusTimer.restart()
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
                var repaired = Model.repairOverlappingLayouts(sane, "dwindle", 0.49)
                sane = repaired.config
                root.config = sane
                var prof = Model.profileById(sane, sane.settings.activeProfileId)
                root.assignments = (prof && prof.assignments) ? prof.assignments.slice() : []
                root.formWorkspace = sane.settings.lastFormWorkspace
                var others = []
                for (var p = 0; p < sane.profiles.length; p++)
                    if (sane.profiles[p].id !== sane.settings.activeProfileId) others.push(sane.profiles[p].id)
                if (others.length) root.copyTargetId = others[0]
                root.countsChanged()
                if (repaired.changed) root.saveConfig()
                Qt.callLater(root.syncMonitorDropdown)
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
        onExited: function(code) {
            root.applyBusy = false
            root.statusText = code === 0 ? "Applied" : "Apply failed"
            clearStatusTimer.restart()
            liveProc.running = true
        }
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
            var seen = {}
            var uniq = []
            for (var u = 0; u < list.length; u++) {
                if (seen[list[u].exec]) continue
                seen[list[u].exec] = true
                uniq.push(list[u])
            }
            uniq.sort(function(a, b){
                var aOn = root.isInList(root.addedApps, a.exec) ? 1 : 0
                var bOn = root.isInList(root.addedApps, b.exec) ? 1 : 0
                if (bOn !== aOn) return bOn - aOn
                if (b.score !== a.score) return b.score - a.score
                return root.alphabeticalCompare(a, b)
            })
            return uniq.slice(0, 24)
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
        return exact.concat(prefix, sub).slice(0, 24)
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
        padding: Style.space(18)
        contentWidth: panel.fittedContentWidth(Style.space(980))
        contentHeight: panel.fittedContentHeight(Math.round(panel.screenH * 0.78), panel.screenH - Style.gapsOut * 2 - Style.space(12))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            blocked: root.transferOpen || filterField.activeFocus || customField.activeFocus || customNameField.activeFocus
            onMoveRequested: function(dx, dy) { if (!root.transferOpen) root.moveCursor(dx, dy) }
            onActivateRequested: { if (!root.transferOpen) root.activateCursor() }
            onCloseRequested: { if (root.transferOpen) root.closeTransfer(); else root.close() }
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
                spacing: Style.space(8)

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
                            text: root.applyBusy ? "Applying…" : "Apply matching"
                            tooltipText: "Detect connected monitors and load that profile (SUPER+ALT+W)"
                            enabled: !root.applyBusy
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

                // ——— Apps ———
                RowLayout {
                    visible: root.mainView === "apps"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Style.space(360)
                    spacing: Style.space(12)

                    ColumnLayout {
                        id: leftStack
                        Layout.fillWidth: false
                        Layout.preferredWidth: Math.round(content.width * 0.38)
                        Layout.minimumWidth: Style.space(280)
                        Layout.fillHeight: true
                        spacing: Style.space(6)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text {
                                text: "Profile"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
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
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 5
                            columnSpacing: Style.space(3)
                            rowSpacing: Style.space(3)
                            Repeater {
                                model: 10
                                delegate: Button {
                                    required property int index
                                    text: String(index + 1)
                                    selected: root.workspacePicked && root.formWorkspace === (index + 1)
                                    horizontalPadding: 0
                                    verticalPadding: 0
                                    onClicked: root.selectWorkspace(index + 1)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(30)
                                }
                            }
                        }

                        RowLayout {
                            visible: root.showMonitorPicker
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text {
                                text: "WS " + root.formWorkspace
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                            Dropdown {
                                id: monitorDropdown
                                Layout.fillWidth: true
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.workspaceMonitorId
                                options: root.monitorOptions
                                onChanged: function(v) {
                                    if (v === root.workspaceMonitorId) return
                                    root.setWorkspaceMonitor(v)
                                }
                            }
                        }
                        Text {
                            visible: !root.showMonitorPicker && root.monitorOptions.length === 1
                            Layout.fillWidth: true
                            text: root.monitorOptions.length ? ("All workspaces → " + root.monitorOptions[0].label) : ""
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: root.showMonitorPicker
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.workspaceMonitorSummary
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption - 1
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Move / copy workspace"
                            tooltipText: "Copy to another profile or move to another workspace number"
                            onClicked: root.openTransfer("copy")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(6)
                            TextField {
                                id: filterField
                                Layout.fillWidth: true
                                verticalPadding: Style.space(6)
                                placeholderText: "Search apps"
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
                            Button { text: "⟳"; tooltipText: "Refresh app list"; verticalPadding: Style.space(6); onClicked: { appsProc.running = true; liveProc.running = true } }
                        }

                        Text {
                            visible: root.filteredApps.length === 0 && root.appFilter.trim().length > 0
                            Layout.fillWidth: true
                            text: "No matches — add a custom command below"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        ScrollView {
                            id: resultsScroll
                            visible: root.filteredApps.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: Style.space(180)
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded
                            Column {
                                width: resultsScroll.width
                                spacing: Style.space(3)
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
                                Layout.preferredWidth: Style.space(88)
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
                        Layout.preferredWidth: Math.round(content.width * 0.62)
                        Layout.fillHeight: true
                        spacing: Style.space(6)

                        PanelSectionHeader {
                            text: "PREVIEW · drag splitters · " + root.activeProfile.name
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
                            onLayoutChanged: function(tiles) { root.applyPreviewLayout(tiles) }
                            onLayoutCleared: root.resetPreviewLayout()
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: {
                                if (root.addedApps.length > 1)
                                    return "Drag the bar between panes. Apply keeps them tiled so later resize still moves both."
                                if (root.addedApps.length === 1)
                                    return "Add another app to split this workspace."
                                return "Toggle apps in the list to place them on WS " + root.formWorkspace + "."
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
                    Layout.fillHeight: true
                    spacing: Style.space(8)

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

            Rectangle {
                id: transferScrim
                visible: root.transferOpen
                z: 200
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                MouseArea { anchors.fill: parent; onClicked: root.closeTransfer() }

                Rectangle {
                    width: Math.min(parent.width - Style.space(28), Style.space(420))
                    implicitHeight: transferCol.implicitHeight + Style.space(28)
                    height: implicitHeight
                    anchors.centerIn: parent
                    radius: Style.cornerRadius
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    MouseArea { anchors.fill: parent; onClicked: function(e) { e.accepted = true } }

                    ColumnLayout {
                        id: transferCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Style.space(16)
                        spacing: Style.space(10)

                        Text {
                            text: "Move / copy workspace"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.title
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.transferMode === "move"
                                  ? "Move apps and the split to another workspace on this profile. If that workspace already has apps, the two swap."
                                  : "Copy apps and the split onto another profile. Pick the destination workspace number."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }

                        ButtonGroup {
                            Layout.fillWidth: true
                            foreground: root.foreground
                            options: [
                                { value: "copy", label: "Copy" },
                                { value: "move", label: "Move" }
                            ]
                            value: root.transferMode
                            onChanged: function(v) {
                                root.transferMode = v
                                if (v === "move") root.transferToProfileId = root.activeProfileId
                                else if (root.copyProfileOptions.length) root.transferToProfileId = root.copyTargetId || root.copyProfileOptions[0].value
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text { text: "From"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(48) }
                            Text {
                                text: root.activeProfile.name
                                color: root.foreground
                                font.family: root.fontFamily
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Dropdown {
                                Layout.preferredWidth: Style.space(110)
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.transferFromWs
                                options: root.workspaceOptions
                                onChanged: function(v) { root.transferFromWs = v }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Text { text: "To"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(48) }
                            Dropdown {
                                visible: root.transferMode === "copy"
                                Layout.fillWidth: true
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.transferToProfileId
                                options: root.transferToProfileOptions
                                onChanged: function(v) { root.transferToProfileId = v; root.copyTargetId = v }
                            }
                            Text {
                                visible: root.transferMode === "move"
                                Layout.fillWidth: true
                                text: root.activeProfile.name
                                color: root.foreground
                                font.family: root.fontFamily
                                elide: Text.ElideRight
                            }
                            Dropdown {
                                Layout.preferredWidth: Style.space(110)
                                label: ""
                                showLabel: false
                                foreground: root.foreground
                                value: root.transferToWs
                                options: root.workspaceOptions
                                onChanged: function(v) { root.transferToWs = v }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            Item { Layout.fillWidth: true }
                            Button { text: "Cancel"; onClicked: root.closeTransfer() }
                            Button {
                                text: root.transferMode === "move" ? "Move" : "Copy"
                                onClicked: root.confirmTransfer()
                            }
                        }
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
        implicitHeight: Style.space(36)

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
