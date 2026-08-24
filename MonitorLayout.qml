import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Drag monitors in layout pixels (Hyprland x/y). Edges snap to neighbors.
Item {
    id: root
    property var tiles: []
    property bool dragging: false
    property var liveTiles: []

    signal layoutChanged(var positions)

    function rebuild() {
        if (dragging) return
        liveTiles = JSON.parse(JSON.stringify(tiles || []))
    }

    onTilesChanged: rebuild()
    Component.onCompleted: rebuild()

    function bounds() {
        var list = liveTiles || []
        var maxX = 1, maxY = 1
        for (var i = 0; i < list.length; i++) {
            var t = list[i]
            if (t.off) continue
            maxX = Math.max(maxX, t.x + t.w)
            maxY = Math.max(maxY, t.y + t.h)
        }
        return { w: maxX, h: maxY }
    }

    function commit() {
        var out = {}
        var list = liveTiles || []
        for (var i = 0; i < list.length; i++) {
            if (!list[i] || list[i].off) continue
            out[list[i].id] = { x: Math.round(list[i].x), y: Math.round(list[i].y) }
        }
        root.layoutChanged(out)
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
            visible: {
                var n = 0
                var list = root.liveTiles || []
                for (var i = 0; i < list.length; i++) if (!list[i].off) n++
                return n === 0
            }
            anchors.centerIn: parent
            text: "No on-displays in this profile"
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }

        Item {
            id: stage
            anchors.fill: parent
            anchors.margins: 16
            readonly property var box: root.bounds()
            readonly property real scale: {
                var bw = Math.max(1, box.w)
                var bh = Math.max(1, box.h)
                var sx = width / bw
                var sy = height / bh
                var s = Math.min(sx, sy) * 0.9
                return s > 0 ? s : 0.1
            }

            Repeater {
                model: root.liveTiles
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    visible: modelData && !modelData.off
                    x: (modelData.x - 0) * stage.scale
                    y: (modelData.y - 0) * stage.scale
                    width: Math.max(48, modelData.w * stage.scale)
                    height: Math.max(36, modelData.h * stage.scale)
                    radius: 6
                    z: index
                    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, moveArea.containsMouse ? 0.28 : 0.16)
                    border.width: 2
                    border.color: Color.accent

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        text: modelData.label + "\n" + Math.round(modelData.w) + "×" + Math.round(modelData.h)
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
                        property bool moved: false
                        onPressed: function(mouse) {
                            var p = mapToItem(stage, mouse.x, mouse.y)
                            grabX = p.x; grabY = p.y
                            origX = modelData.x; origY = modelData.y
                            moved = false
                            root.dragging = true
                            parent.z = 80
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var p = mapToItem(stage, mouse.x, mouse.y)
                            var nx = origX + (p.x - grabX) / Math.max(0.001, stage.scale)
                            var ny = origY + (p.y - grabY) / Math.max(0.001, stage.scale)
                            if (Math.abs(nx - origX) > 4 || Math.abs(ny - origY) > 4) moved = true
                            var others = []
                            var list = root.liveTiles || []
                            for (var i = 0; i < list.length; i++) {
                                if (!list[i] || list[i].off || list[i].id === modelData.id) continue
                                others.push(list[i])
                            }
                            var snapped = Model.snapLayoutRect({ id: modelData.id, x: nx, y: ny, w: modelData.w, h: modelData.h }, others, 48)
                            var next = JSON.parse(JSON.stringify(list))
                            for (var j = 0; j < next.length; j++) {
                                if (next[j].id === modelData.id) {
                                    next[j].x = snapped.x
                                    next[j].y = snapped.y
                                }
                            }
                            root.liveTiles = next
                        }
                        onReleased: {
                            root.dragging = false
                            if (moved) root.commit()
                            moved = false
                        }
                    }
                }
            }
        }
    }
}
