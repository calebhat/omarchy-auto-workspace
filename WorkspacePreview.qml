import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Mini monitor preview. Assigned apps start in a tiling mock; drag a tile
// or its edges to pin a custom floating layout (fractions of the workspace).
Item {
    id: root
    property int workspace: 1
    property var assignedApps: []
    property var appList: []
    property bool isExpanded: false
    property int screenW: 0
    property int screenH: 0
    property var bar: null
    property string hyprLayout: "dwindle"
    property real columnWidth: 0.49
    property bool dragging: false
    property int frontZ: 10

    readonly property real screenAspect: screenW > 0 && screenH > 0 ? screenH / screenW : 0.5625
    readonly property var appLibrary: root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    readonly property bool customLayout: Model.workspaceUsesCustomLayout(assignedApps)
    readonly property string layoutLabel: {
        if (customLayout) return "custom · drag tiles / edges"
        if (hyprLayout === "scrolling") return "scrolling • " + Math.round(columnWidth * 100) + "% columns"
        if (hyprLayout === "master") return "master"
        if (hyprLayout === "dwindle") return "dwindle"
        return hyprLayout
    }

    signal layoutChanged(var tiles)
    signal layoutCleared()

    function iconSourceFor(exec) {
        for (var i = 0; i < appList.length; i++) {
            if (appList[i].exec === exec || appList[i].command === exec) {
                var a = appList[i]
                if (a.iconPath && a.iconPath !== "") return "file://" + a.iconPath
                var icon = String(a.icon || "")
                if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(icon)
                if (icon !== "" && icon.charAt(0) === "/") return "file://" + icon
                var themed = ""
                try { themed = Quickshell.iconPath(icon, true) } catch (e) { themed = "" }
                if (themed && themed.length > 0) return themed
                try { return Quickshell.iconPath("application-x-executable", true) } catch (e) { return "" }
            }
        }
        var base = String(exec || "").split(" ")[0].split("/").pop()
        if (root.appLibrary && typeof root.appLibrary.iconSource === "function") return root.appLibrary.iconSource(base)
        var fb = ""
        try { fb = Quickshell.iconPath(base, true) } catch (e) { fb = "" }
        if (fb && fb.length > 0 && fb.indexOf("image://icon/application-x-executable") === -1) return fb
        try { return Quickshell.iconPath("application-x-executable", true) } catch (e) { return "" }
    }

    function rectsForCount(n) {
        return Model.autoLayoutRects(n, root.hyprLayout, root.columnWidth)
    }

    function geomForApp(app, idx, total) {
        var g = Model.normalizeGeom(app && app.geom)
        if (g) return g
        var autos = rectsForCount(total)
        return autos[idx] || Model.normalizeGeom({ x: 0, y: 0, w: 1, h: 1 })
    }

    function commitTiles() {
        var out = []
        for (var i = 0; i < tileRepeater.count; i++) {
            var item = tileRepeater.itemAt(i)
            if (!item || !item.app) continue
            var g = item.fracGeom()
            if (g) {
                g.id = item.app.id
                g.z = i
                out.push(g)
            }
        }
        if (out.length) root.layoutChanged(out)
    }

    implicitWidth: 320
    implicitHeight: previewBox.implicitHeight + 28

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: "WS " + root.workspace
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
            }
            Text {
                text: root.assignedApps.length + " app" + (root.assignedApps.length === 1 ? "" : "s")
                color: Qt.darker(Color.foreground, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 1
            }
            Text {
                visible: root.assignedApps.length > 0
                text: "· " + root.layoutLabel
                color: Qt.darker(Color.foreground, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Button {
                visible: root.customLayout
                text: "Reset"
                tooltipText: "Clear pinned sizes and go back to tiling"
                verticalPadding: Style.space(2)
                horizontalPadding: Style.space(8)
                onClicked: root.layoutCleared()
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }

        Rectangle {
            id: previewBox
            Layout.fillWidth: true
            Layout.preferredHeight: width > 0 ? Math.round(width * root.screenAspect) : 92
            Layout.maximumHeight: Layout.preferredHeight
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: width > 0 ? Math.round(width * root.screenAspect) : 92
            radius: Style.cornerRadius
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
            border.width: 1
            border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
            clip: true

            Text {
                visible: root.assignedApps.length === 0
                anchors.centerIn: parent
                text: "Empty — search or add a custom command"
                color: Qt.darker(Color.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 1
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                id: tilesContainer
                anchors.fill: parent
                anchors.margins: 6
                visible: root.assignedApps.length > 0

                Repeater {
                    id: tileRepeater
                    model: root.assignedApps
                    delegate: Tile {
                        required property var modelData
                        required property int index
                        app: modelData
                        appIndex: index
                        z: index
                    }
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }
    }

    component Tile: Rectangle {
        id: tile
        property var app: null
        property int appIndex: 0

        x: 0
        y: 0
        width: 48
        height: 36
        radius: 6
        clip: false
        color: (app && app.enabled !== false)
               ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, moveArea.containsMouse ? 0.32 : 0.18)
               : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
        border.width: 2
        border.color: Color.accent

        function modelGeom() {
            return root.geomForApp(tile.app, tile.appIndex, (root.assignedApps || []).length)
        }

        function applyFrac(g) {
            if (!g || tilesContainer.width <= 0 || tilesContainer.height <= 0) return
            tile.x = g.x * tilesContainer.width
            tile.y = g.y * tilesContainer.height
            tile.width = Math.max(36, g.w * tilesContainer.width)
            tile.height = Math.max(28, g.h * tilesContainer.height)
        }

        function fracGeom() {
            var pw = Math.max(1, tilesContainer.width)
            var ph = Math.max(1, tilesContainer.height)
            return Model.normalizeGeom({
                x: tile.x / pw,
                y: tile.y / ph,
                w: tile.width / pw,
                h: tile.height / ph
            })
        }

        function clampPosSize(nx, ny, nw, nh) {
            var minW = 36, minH = 28
            nw = Math.max(minW, Math.min(tilesContainer.width, nw))
            nh = Math.max(minH, Math.min(tilesContainer.height, nh))
            nx = Math.max(0, Math.min(tilesContainer.width - nw, nx))
            ny = Math.max(0, Math.min(tilesContainer.height - nh, ny))
            tile.x = nx; tile.y = ny; tile.width = nw; tile.height = nh
        }

        function finishDrag(didMove) {
            if (didMove || root.customLayout) root.commitTiles()
            root.dragging = false
        }

        Component.onCompleted: applyFrac(modelGeom())
        onAppChanged: if (!root.dragging) applyFrac(modelGeom())
        Connections {
            target: tilesContainer
            function onWidthChanged() { if (!root.dragging) tile.applyFrac(tile.modelGeom()) }
            function onHeightChanged() { if (!root.dragging) tile.applyFrac(tile.modelGeom()) }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            width: parent.width - 16
            text: app ? (app.name || "App") : ""
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption - 1
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            z: 1
        }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            anchors.bottomMargin: 2
            width: 16
            height: 16
            visible: source !== ""
            source: root.iconSourceFor(app ? (app.exec || app.command) : "")
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            z: 1
            onStatusChanged: if (status === Image.Error) source = ""
        }

        MouseArea {
            id: moveArea
            anchors.fill: parent
            anchors.margins: 10
            cursorShape: Qt.SizeAllCursor
            hoverEnabled: true
            preventStealing: true
            property real grabX: 0
            property real grabY: 0
            property real origX: 0
            property real origY: 0
            property bool moved: false
            onPressed: function(mouse) {
                var p = mapToItem(tilesContainer, mouse.x, mouse.y)
                grabX = p.x; grabY = p.y
                origX = tile.x; origY = tile.y
                moved = false
                root.dragging = true
                tile.z = ++root.frontZ
                mouse.accepted = true
            }
            onPositionChanged: function(mouse) {
                if (!pressed) return
                var p = mapToItem(tilesContainer, mouse.x, mouse.y)
                var nx = origX + p.x - grabX
                var ny = origY + p.y - grabY
                if (Math.abs(nx - origX) > 2 || Math.abs(ny - origY) > 2) moved = true
                tile.clampPosSize(nx, ny, tile.width, tile.height)
            }
            onReleased: tile.finishDrag(moved)
        }

        Repeater {
            model: [
                { edge: "n",  xA: 10, yA: -3, w: -20, h: 10 },
                { edge: "s",  xA: 10, yA: -7, w: -20, h: 10 },
                { edge: "w",  xA: -3, yA: 10, w: 10, h: -20 },
                { edge: "e",  xA: -7, yA: 10, w: 10, h: -20 },
                { edge: "nw", xA: -4, yA: -4, w: 12, h: 12 },
                { edge: "ne", xA: -8, yA: -4, w: 12, h: 12 },
                { edge: "sw", xA: -4, yA: -8, w: 12, h: 12 },
                { edge: "se", xA: -8, yA: -8, w: 12, h: 12 }
            ]
            delegate: MouseArea {
                required property var modelData
                z: 20
                x: modelData.xA >= 0 ? modelData.xA : tile.width + modelData.xA
                y: modelData.yA >= 0 ? modelData.yA : tile.height + modelData.yA
                width: modelData.w > 0 ? modelData.w : Math.max(12, tile.width + modelData.w)
                height: modelData.h > 0 ? modelData.h : Math.max(12, tile.height + modelData.h)
                preventStealing: true
                hoverEnabled: true
                cursorShape: {
                    var e = modelData.edge
                    if (e === "n" || e === "s") return Qt.SizeVerCursor
                    if (e === "e" || e === "w") return Qt.SizeHorCursor
                    if (e === "nw" || e === "se") return Qt.SizeFDiagCursor
                    return Qt.SizeBDiagCursor
                }
                property real grabX: 0
                property real grabY: 0
                property real origX: 0
                property real origY: 0
                property real origW: 0
                property real origH: 0
                property bool moved: false
                onPressed: function(mouse) {
                    var p = mapToItem(tilesContainer, mouse.x, mouse.y)
                    grabX = p.x; grabY = p.y
                    origX = tile.x; origY = tile.y; origW = tile.width; origH = tile.height
                    moved = false
                    root.dragging = true
                    tile.z = ++root.frontZ
                    mouse.accepted = true
                }
                onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var p = mapToItem(tilesContainer, mouse.x, mouse.y)
                    var dx = p.x - grabX
                    var dy = p.y - grabY
                    var nx = origX, ny = origY, nw = origW, nh = origH
                    var e = modelData.edge
                    if (e.indexOf("e") >= 0) nw = origW + dx
                    if (e.indexOf("s") >= 0) nh = origH + dy
                    if (e.indexOf("w") >= 0) { nx = origX + dx; nw = origW - dx }
                    if (e.indexOf("n") >= 0) { ny = origY + dy; nh = origH - dy }
                    tile.clampPosSize(nx, ny, nw, nh)
                    if (Math.abs(nx - origX) > 1 || Math.abs(ny - origY) > 1 || Math.abs(nw - origW) > 1 || Math.abs(nh - origH) > 1)
                        moved = true
                }
                onReleased: tile.finishDrag(moved)
            }
        }

        // Always-visible corner grips so the preview is obviously editable.
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                z: 15
                width: 8
                height: 8
                radius: 1
                color: Color.accent
                x: index % 2 === 0 ? 0 : tile.width - 8
                y: index < 2 ? 0 : tile.height - 8
            }
        }
    }
}
