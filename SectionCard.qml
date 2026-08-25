import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons

BorderSurface {
    id: root

    property string title: ""
    property string hint: ""
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    property bool fillAvailable: false
    property alias tools: toolsRow.data
    default property alias content: body.data

    Layout.fillWidth: true
    Layout.fillHeight: fillAvailable
    implicitWidth: Style.space(240)
    implicitHeight: col.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
    borderSpec: Border.controlSpec("normal", foreground, Color.accent)

    readonly property int pad: Style.space(10)

    ColumnLayout {
        id: col
        x: root.pad
        y: root.pad
        width: Math.max(0, root.width - root.pad * 2)
        height: root.fillAvailable ? Math.max(0, root.height - root.pad * 2) : undefined
        spacing: Style.space(8)

        RowLayout {
            visible: root.title !== "" || root.hint !== ""
            Layout.fillWidth: true
            spacing: Style.space(6)
            PanelSectionHeader {
                visible: root.title !== ""
                Layout.fillWidth: true
                text: root.title
                foreground: root.foreground
                fontFamily: root.fontFamily
            }
            Item {
                visible: root.title === "" && root.hint !== ""
                Layout.fillWidth: true
            }
            RowLayout {
                id: toolsRow
                spacing: Style.space(4)
            }
            HintMark {
                visible: root.hint !== ""
                tooltipText: root.hint
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: root.fillAvailable
            spacing: Style.space(6)
        }
    }
}
