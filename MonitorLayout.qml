import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Drag monitors in Hyprland layout pixels. Delegates stay alive for the
// whole drag so the grab is not destroyed. Snap runs on release only.
Item {
    id: root
    property var tiles: []
    property bool dragging: false
    property var layoutModel: []
    property real dragScale: 0.1

    signal layoutChanged(var positions)

    function visibleTiles(src) {
        var out = []
        var list = src || []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && !list[i].off) out.push(JSON.parse(JSON.stringify(list[i])))
        }
        return out
    }

    function rebuild() {
        if (dragging) return
        layoutModel = visibleTiles(tiles)
        computeScale()
    }

    function computeScale() {
        var list = layoutModel
        var minX = 0, minY = 0, maxX = 1920, maxY = 1080
        var first = true
        for (var i = 0; i < list.length; i++) {
            var t = list[i]
            if (first) {
                minX = t.x; minY = t.y; maxX = t.x + t.w; maxY = t.y + t.h
                first = false
            } else {
                minX = Math.min(minX, t.x)
                minY = Math.min(minY, t.y)
                maxX = Math.max(maxX, t.x + t.w)
                maxY = Math.max(maxY, t.y + t.h)
            }
        }
        var bw = Math.max(200, maxX - minX)
        var bh = Math.max(200, maxY - minY)
        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2
        var sw = Math.max(1, stage.width)
        var sh = Math.max(1, stage.height)
        // Pad so there is empty space above/beside after each snap.
        var sx = sw / (bw * 2.2)
        var sy = sh / (bh * 2.2)
        var s = Math.min(sx, sy)
        if (!(s > 0)) s = 0.08
        if (s > 0.55) s = 0.55
        dragScale = s
        originX = cx - sw / (2 * s)
        originY = cy - sh / (2 * s)
    }

    property real originX: 0
    property real originY: 0

    onTilesChanged: rebuild()
    Component.onCompleted: rebuild()

    function collectPositions(draggedId) {
        var others = []
        var i
        for (i = 0; i < tileRepeater.count; i++) {
            var item = tileRepeater.itemAt(i)
            if (!item || !item.tileId) continue
            others.push({ id: item.tileId, x: item.layoutX, y: item.layoutY, w: item.layoutW, h: item.layoutH })
        }
        var out = {}
        for (i = 0; i < others.length; i++) {
            var t = others[i]
            var pos = { x: t.x, y: t.y, w: t.w, h: t.h, id: t.id }
            if (draggedId && t.id === draggedId) {
                var rest = []
                for (var j = 0; j < others.length; j++) if (others[j].id !== t.id) rest.push(others[j])
                pos = Model.placeMonitorNoOverlap(pos, rest)
            }
            out[t.id] = { x: Math.round(pos.x), y: Math.round(pos.y) }
        }
        return out
    }

    function commit(draggedId) {
        var positions = collectPositions(draggedId)
        if (Object.keys(positions).length) root.layoutChanged(positions)
    }

    Rectangle {
        id: canvas
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
        border.width: 1
        border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
        clip: true

        Text {
            visible: root.layoutModel.length === 0
            anchors.centerIn: parent
            text: "No on-displays in this profile"
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }

        Item {
            id: stage
            anchors.fill: parent
            anchors.margins: 12

            Repeater {
                id: tileRepeater
                model: root.layoutModel
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    property string tileId: modelData ? String(modelData.id) : ""
                    property real layoutX: modelData ? modelData.x : 0
                    property real layoutY: modelData ? modelData.y : 0
                    property real layoutW: modelData ? modelData.w : 1920
                    property real layoutH: modelData ? modelData.h : 1080

                    x: (layoutX - root.originX) * root.dragScale
                    y: (layoutY - root.originY) * root.dragScale
                    width: Math.max(56, layoutW * root.dragScale)
                    height: Math.max(40, layoutH * root.dragScale)
                    radius: 6
                    z: index
                    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, moveArea.containsMouse || moveArea.pressed ? 0.32 : 0.16)
                    border.width: 2
                    border.color: Color.accent

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        text: (modelData && modelData.label ? modelData.label : "Display") + "\n" + Math.round(tile.layoutW) + "×" + Math.round(tile.layoutH)
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption - 1
                        font.bold: true
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                        id: moveArea
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        hoverEnabled: true
                        preventStealing: true
                        property real grabX: 0
                        property real grabY: 0
                        property real origX: 0
                        property real origY: 0

                        onPressed: function(mouse) {
                            var p = mapToItem(stage, mouse.x, mouse.y)
                            grabX = p.x
                            grabY = p.y
                            origX = tile.layoutX
                            origY = tile.layoutY
                            root.dragging = true
                            tile.z = 80
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var p = mapToItem(stage, mouse.x, mouse.y)
                            var s = Math.max(0.001, root.dragScale)
                            tile.layoutX = origX + (p.x - grabX) / s
                            tile.layoutY = origY + (p.y - grabY) / s
                        }
                        onReleased: {
                            root.dragging = false
                            root.commit(tile.tileId)
                            Qt.callLater(root.rebuild)
                        }
                    }
                }
            }
        }
    }
}
