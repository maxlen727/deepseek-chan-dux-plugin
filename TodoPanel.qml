import QtQuick
import qs.Common
import "pet.js" as Pet

// 待办面板：一句话加可选时间（"18:30 开会"、"30分钟后 喝水"、"明天 9点 交报告"）。
// 由 PetWindow 实例化，win 指回 PetWindow。
Rectangle {
    id: panel

    property var win
    property real now: Date.now()

    visible: false
    width: 340
    height: Math.min(380, header.height + list.contentHeight + inputBox.height + 40)
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.color: Theme.outlineVariant
    border.width: 1

    function open() {
        now = Date.now();
        visible = true;
        input.forceActiveFocus();
    }

    function close() {
        visible = false;
    }

    Timer {
        interval: 30000
        repeat: true
        running: panel.visible
        onTriggered: panel.now = Date.now()
    }

    MouseArea {
        anchors.fill: parent
        onPressed: input.forceActiveFocus()
    }

    Item {
        id: header
        x: 12
        y: 6
        width: parent.width - 24
        height: 30

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "待办" + (panel.win.todos.length ? "（" + panel.win.todos.length + "）" : "")
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
        }

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 24
            radius: 12
            color: closeMouse.containsMouse ? Theme.primaryHover : "transparent"

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.close()
            }
        }
    }

    ListView {
        id: list
        x: 10
        y: header.y + header.height + 4
        width: parent.width - 20
        height: inputBox.y - y - 8
        clip: true
        spacing: 4
        model: panel.win.sortedTodos

        Text {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "还没有待办～"
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool overdue: modelData.due && modelData.due <= panel.now
            width: list.width
            height: 40
            radius: Theme.cornerRadius / 2
            color: rowMouse.containsMouse ? Theme.surfaceContainerHigh : "transparent"

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
            }

            // 勾选 = 完成
            Rectangle {
                id: check
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 10
                color: checkMouse.containsMouse ? Theme.primaryHover : "transparent"
                border.color: Theme.primary
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    visible: checkMouse.containsMouse
                    text: "✓"
                    color: Theme.primary
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: checkMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.win.completeTodo(row.modelData.id)
                }
            }

            Column {
                x: check.x + check.width + 10
                width: parent.width - x - 34
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: row.modelData.text
                    elide: Text.ElideRight
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }

                Text {
                    visible: !!row.modelData.due
                    text: Pet.fmtDue(row.modelData.due, panel.now) + " · " + Pet.fmtLeft(row.modelData.due - panel.now)
                    color: row.overdue ? Theme.error : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: rowMouse.containsMouse || delMouse.containsMouse
                text: "✕"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall

                MouseArea {
                    id: delMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.win.removeTodo(row.modelData.id)
                }
            }
        }
    }

    Rectangle {
        id: inputBox
        x: 10
        y: parent.height - height - 10
        width: parent.width - 20
        height: 38
        radius: height / 2
        color: Theme.surfaceContainerHigh
        border.color: input.activeFocus ? Theme.primary : Theme.outlineVariant
        border.width: 1

        TextInput {
            id: input
            x: 14
            width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            clip: true
            selectByMouse: true

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === "" && !input.inputMethodComposing
                text: "18:30 开会 / 30分钟后 喝水（回车添加）"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Keys.onReturnPressed: add()
            Keys.onEnterPressed: add()
            Keys.onEscapePressed: panel.close()

            function add() {
                if (panel.win.addTodo(text)) {
                    text = "";
                    panel.now = Date.now();
                }
            }
        }
    }
}
